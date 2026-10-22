"""Фоновый воркер: очередь сообщений, напоминания, дайджест, чистка статусов.

Один поток делает всё по очереди каждые `interval` секунд — так вызовы VK API
никогда не пересекаются и не ловят флуд-лимит.
"""

from __future__ import annotations

import logging
import threading
import time
from datetime import datetime, timedelta
from typing import Callable

from .config import Config
from .db import (
    STATUS_COMPLETED,
    STATUS_CONFIRMED,
    STATUS_EXPIRED,
    STATUS_PENDING,
    Database,
)
from .handlers import Bot
from .util import parse_hhmm

log = logging.getLogger("bot.scheduler")


class Scheduler:
    def __init__(self, cfg: Config, db: Database, bot: Bot,
                 now_fn: Callable[[], datetime] | None = None):
        self.cfg = cfg
        self.db = db
        self.bot = bot
        self.now_fn = now_fn or bot.now_fn
        self.notify = bot.notify
        self.counters = {
            "sent": 0,
            "reminders": 0,
            "expired": 0,
            "completed": 0,
            "digests": 0,
        }

    # ------------------------------------------------------------------ #
    def tick(self) -> dict[str, int]:
        """Один проход воркера. Возвращает счётчики (удобно для тестов)."""
        result = {"sent": 0, "reminders": 0, "expired": 0, "completed": 0, "digest": 0}
        now = self.now_fn()

        try:
            self._plan_missing_reminders(now)
            self._send_due_reminders(now)
            self._expire_pending(now)
            self._complete_past(now)
            self._morning_digest(now)
            result["sent"] = self.bot.flush_outbox()
        except Exception:  # noqa: BLE001
            log.exception("Ошибка в tick() — продолжаю работу")

        for key in ("sent", "reminders", "expired", "completed", "digests"):
            mapped = "digest" if key == "digests" else key
            self.counters[key] = self.counters.get(key, 0) + result.get(mapped, 0)
        return result

    def run_forever(self, stop_event: threading.Event, interval: float = 15.0) -> None:
        log.info("Воркер запущен (интервал %.0f с)", interval)
        while not stop_event.is_set():
            self.tick()
            stop_event.wait(interval)
        log.info("Воркер остановлен")

    # ------------------------------------------------------------------ #
    def _plan_missing_reminders(self, now: datetime) -> None:
        """Страховка: напоминания могли не создаться, если бот перезапустили."""
        requests = self.db.list_requests(
            statuses=[STATUS_CONFIRMED], since=now, until=now + timedelta(days=60), limit=200
        )
        for req in requests:
            self.notify.plan_reminders(req)

    def _send_due_reminders(self, now: datetime) -> int:
        """Рассылает напоминания.

        Если бот простаивал и накопилось несколько напоминаний по одной записи
        (например, за 24 ч и за 2 ч), отправляем только одно — без спама.
        """
        count = 0
        already: set[tuple[int, str]] = set()
        for reminder, req in self.db.due_reminders(now):
            if req.status != STATUS_CONFIRMED:
                self.db.mark_reminder_sent(reminder.id, now=now)
                continue
            audience = "client" if reminder.kind.startswith("client") else "admin"
            if (req.id, audience) in already:
                self.db.mark_reminder_sent(reminder.id, now=now)
                continue
            try:
                if audience == "client":
                    self.notify.reminder_client(req)
                else:
                    self.notify.reminder_admin(req)
                self.db.mark_reminder_sent(reminder.id, now=now)
                already.add((req.id, audience))
                count += 1
                log.info("Напоминание %s для заявки №%s поставлено в очередь",
                         reminder.kind, req.id)
            except Exception as exc:  # noqa: BLE001
                self.db.bump_reminder(reminder.id)
                log.error("Не смог запланировать напоминание №%s: %s", reminder.id, exc)
        return count

    def _expire_pending(self, now: datetime) -> int:
        """Заявки без ответа мастера закрываются, клиент получает вежливое сообщение."""
        cutoff = now - timedelta(hours=self.cfg.pending_ttl_hours)
        count = 0
        for req in self.db.pending_older_than(cutoff):
            self.db.set_status(req.id, STATUS_EXPIRED, now=now)
            self.notify.expired_client(req)
            count += 1
            log.info("Заявка №%s истекла (нет ответа мастера)", req.id)
        return count

    def _complete_past(self, now: datetime) -> int:
        """Сеанс состоялся — запись помечаем завершённой (для статистики)."""
        count = 0
        for req in self.db.finished_before(now):
            self.db.set_status(req.id, STATUS_COMPLETED, now=now)
            count += 1
        return count

    def _morning_digest(self, now: datetime) -> int:
        if not self.cfg.digest_enabled or not self.cfg.admin_ids:
            return 0
        try:
            hh, mm = parse_hhmm(self.cfg.digest_time)
        except ValueError:
            return 0
        today = now.replace(hour=0, minute=0, second=0, microsecond=0)
        if now < today.replace(hour=hh, minute=mm):
            return 0
        key = today.strftime("%Y-%m-%d")
        if self.db.kv_get("digest_last") == key:
            return 0
        requests = self.db.list_requests(
            statuses=[STATUS_CONFIRMED, STATUS_PENDING],
            since=today,
            until=today + timedelta(days=1),
        )
        self.notify.digest(today, requests)
        self.db.kv_set("digest_last", key)
        log.info("Утренний дайджест на %s отправлен (%s записей)", key, len(requests))
        return 1

    # ------------------------------------------------------------------ #
    def housekeeping(self, now: datetime | None = None, keep_days: int = 30) -> None:
        """Чистит отправленные сообщения из очереди (раз в сутки достаточно)."""
        now = now or self.now_fn()
        removed = self.db.purge_sent(now - timedelta(days=keep_days))
        if removed:
            log.info("Очищено %s отправленных сообщений из outbox", removed)


def start_worker(scheduler: Scheduler, stop_event: threading.Event,
                 interval: float = 15.0) -> threading.Thread:
    thread = threading.Thread(
        target=scheduler.run_forever,
        args=(stop_event, interval),
        name="scheduler",
        daemon=True,
    )
    thread.start()
    return thread


def sleep(seconds: float) -> None:  # pragma: no cover - для совместимости
    time.sleep(seconds)
