"""Общий стенд для тестов: фейковые часы и фейковый «ВКонтакте».

Никакой сети: Sender записывает сообщения в список, тест их проверяет.
Тот же стенд использует scripts/demo.py (интерактивная демонстрация).
"""

from __future__ import annotations

import shutil
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

from bot.config import Config, Contacts, Service
from bot.db import Database
from bot.handlers import Bot
from bot.scheduler import Scheduler
from bot.util import get_tz


class FakeClock:
    """Управляемое «сейчас»: можно перематывать время вперёд."""

    def __init__(self, start: datetime):
        self.current = start

    def __call__(self) -> datetime:
        return self.current

    def advance(self, **kwargs) -> datetime:
        self.current += timedelta(**kwargs)
        return self.current

    def set(self, value: datetime) -> None:
        self.current = value


@dataclass
class Sent:
    peer_id: int
    text: str
    keyboard: dict | None = None
    at: datetime | None = None


class FakeSender:
    """Заменяет bot.vk.VK: копит исходящие сообщения и ответы на callback."""

    def __init__(self, clock: FakeClock | None = None, names: dict[int, tuple[str, str]] | None = None):
        self.sent: list[Sent] = []
        self.events: list[dict] = []
        self.clock = clock
        self.names = names or {}
        self.fail_next: int = 0  # сколько следующих отправок «упадут»
        self.errors: list[str] = []

    # --- интерфейс Sender --- #
    def send_message(self, peer_id: int, text: str = "", keyboard: dict | None = None):
        if "{" in text and "}" in text:
            raise AssertionError(
                f"В сообщении остался нераскрытый плейсхолдер (peer {peer_id}): {text[:160]}"
            )
        if self.fail_next > 0:
            self.fail_next -= 1
            raise RuntimeError("имитация обрыва связи")
        self.sent.append(
            Sent(peer_id=peer_id, text=text, keyboard=keyboard,
                 at=self.clock() if self.clock else None)
        )
        return len(self.sent)

    def answer_event(self, peer_id: int, user_id: int, event_id: str, text: str = "Готово ✅"):
        self.events.append(
            {"peer_id": peer_id, "user_id": user_id, "event_id": event_id, "text": text}
        )

    def get_user_names(self, user_ids: list[int]) -> dict[int, tuple[str, str]]:
        return {uid: self.names[uid] for uid in user_ids if uid in self.names}

    # --- помощники для проверок --- #
    def messages_for(self, peer_id: int) -> list[Sent]:
        return [m for m in self.sent if m.peer_id == peer_id]

    def last(self, peer_id: int) -> Sent | None:
        msgs = self.messages_for(peer_id)
        return msgs[-1] if msgs else None

    def last_text(self, peer_id: int) -> str:
        msg = self.last(peer_id)
        return msg.text if msg else ""

    def labels(self, peer_id: int) -> list[str]:
        """Подписи кнопок последнего сообщения."""
        msg = self.last(peer_id)
        if not msg or not msg.keyboard:
            return []
        out = []
        for row in msg.keyboard.get("buttons", []):
            for button in row:
                label = (button.get("action") or {}).get("label")
                if label:
                    out.append(label)
        return out

    def clear(self) -> None:
        self.sent.clear()
        self.events.clear()


@dataclass
class Harness:
    cfg: Config
    db: Database
    sender: FakeSender
    clock: FakeClock
    bot: Bot
    scheduler: Scheduler
    tmpdir: Path
    admin_id: int = 111
    client_id: int = 222

    def cleanup(self) -> None:
        self.db.close()
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    # --- прогон диалога --- #
    def say(self, user_id: int, text: str) -> None:
        self.bot.on_message(
            {
                "from_id": user_id,
                "peer_id": user_id,
                "text": text,
                "date": int(self.clock().timestamp()),
            }
        )
        self.flush()

    def press(self, user_id: int, cmd: str, value=None, event_id: str = "e1") -> None:
        """Клик по кнопке. payload = {"c": cmd, "v": value} — как в ВК."""
        payload: dict = {"c": cmd}
        if value is not None:
            payload["v"] = value
        self.bot.on_message_event(
            {"user_id": user_id, "peer_id": user_id, "event_id": event_id, "payload": payload}
        )
        self.flush()

    def flush(self) -> None:
        self.bot.flush_outbox()

    def tick(self) -> dict:
        result = self.scheduler.tick()
        self.flush()
        return result

    # --- удобные выборки --- #
    def client_text(self) -> str:
        return self.sender.last_text(self.client_id)

    def admin_text(self) -> str:
        return self.sender.last_text(self.admin_id)

    def client_labels(self) -> list[str]:
        return self.sender.labels(self.client_id)

    def admin_labels(self) -> list[str]:
        return self.sender.labels(self.admin_id)


def build_config(
    db_path: Path,
    admin_id: int = 111,
    tz_name: str = "Europe/Moscow",
    now: datetime | None = None,
    **overrides,
) -> Config:
    """Рабочий конфиг для тестов (без чтения TOML)."""
    cfg = Config()
    cfg.bot_name = "Тестовый массаж"
    cfg.timezone = tz_name
    cfg.tzinfo = get_tz(tz_name)
    cfg.group_id = 123456
    cfg.token = "test-token"
    cfg.db_path = db_path
    cfg.admin_ids = [admin_id]
    cfg.services = [
        Service(id="back", title="Массаж спины", duration=40, price=1500,
                description="Шея и спина"),
        Service(id="full", title="Общий массаж", duration=60, price=2500),
        Service(id="hidden", title="Скрытая услуга", duration=30, price=1, active=False),
    ]
    cfg.work_days = ["mon", "tue", "wed", "thu", "fri", "sat"]
    cfg.hours = {
        "mon": ["10:00-14:00"],
        "tue": ["10:00-19:00"],
        "wed": ["10:00-14:00"],
        "thu": ["10:00-19:00"],
        "fri": ["10:00-18:00"],
        "sat": ["11:00-16:00"],
        "sun": [],
    }
    cfg.slot_minutes = 30
    cfg.buffer_minutes = 15
    cfg.min_notice_minutes = 120
    cfg.max_days_ahead = 21
    cfg.block_on_pending = True
    cfg.contacts = Contacts(
        master_name="Елена",
        phone="+7 900 000-00-00",
        whatsapp="https://wa.me/79000000000",
        vk="https://vk.com/id777",
        address="г. Тверь, ул. Советская, 10",
        note="Отмена за 3 часа",
    )
    cfg.client_before_hours = [24, 2]
    cfg.admin_before_hours = [24]
    cfg.digest_enabled = True
    cfg.digest_time = "09:00"
    cfg.pending_ttl_hours = 24
    cfg.client_cancel_min_hours = 3
    cfg.cooldown_seconds = 0  # в тестах пауза не нужна
    cfg.use_callback_buttons = True
    for key, value in overrides.items():
        setattr(cfg, key, value)
    return cfg


def make_harness(
    now: datetime | None = None, admin_id: int = 111, client_id: int = 222, **overrides
) -> Harness:
    tmpdir = Path(tempfile.mkdtemp(prefix="massage-test-"))
    clock = FakeClock(now or datetime(2026, 10, 22, 9, 0, 0))  # четверг
    cfg = build_config(tmpdir / "test.sqlite3", admin_id=admin_id, now=clock(), **overrides)
    db = Database(cfg.db_path)
    sender = FakeSender(clock=clock, names={client_id: ("Иван", "Петров")})
    bot = Bot(cfg, db, sender, now_fn=clock)
    scheduler = Scheduler(cfg, db, bot, now_fn=clock)
    return Harness(
        cfg=cfg, db=db, sender=sender, clock=clock, bot=bot, scheduler=scheduler,
        tmpdir=tmpdir, admin_id=admin_id, client_id=client_id,
    )


def walk_booking(h: Harness, service_id: str = "back", slot_index: int = 0,
                 date_index: int = 0, name: str | None = "Иван Петров",
                 phone: str | None = "+7 900 123-45-67",
                 comment: str | None = None) -> int:
    """Прогоняет полный сценарий записи и возвращает id созданной заявки."""
    h.press(h.client_id, "book")
    h.press(h.client_id, "svc", service_id)

    date_labels = [label for label in h.client_labels() if "," in label]
    assert date_labels, f"Нет кнопок с датами: {h.client_labels()}"
    label = date_labels[min(date_index, len(date_labels) - 1)]
    date_value = _date_value_from_label(label, h)
    h.press(h.client_id, "date", date_value)

    slots = [x for x in h.client_labels() if ":" in x]
    assert slots, f"Нет кнопок со временем: {h.client_labels()}"
    h.press(h.client_id, "time", f"{date_value}T{slots[slot_index]}")

    if name is None:
        h.press(h.client_id, "name_ok")
    else:
        h.say(h.client_id, name)
    if phone is None:
        h.press(h.client_id, "contact_vk")
    else:
        h.say(h.client_id, phone)
    if comment:
        h.say(h.client_id, comment)
    else:
        h.press(h.client_id, "no_comment")

    assert any("Отправить заявку" in label for label in h.client_labels()), h.client_labels()
    h.press(h.client_id, "submit")
    requests = h.db.list_requests(statuses=["pending"], client_vk_id=h.client_id)
    assert requests, "Заявка не создалась"
    return requests[-1].id


def date_labels(h: Harness) -> list[str]:
    return [label for label in h.client_labels() if "," in label]


def _slot_value(label: str, h: Harness) -> str:
    """'14:30' -> 'YYYY-MM-DDT14:30' по выбранной в сценарии дате."""
    state, data = h.db.get_state(h.client_id)
    date = data.get("date") or ""
    return f"{date}T{label.strip()}"


def _date_value_from_label(label: str, h: Harness) -> str:
    """'чт, 22 октября' -> '2026-10-22' (ищем по списку доступных дат)."""
    from bot.slots import available_dates
    from bot.util import format_date_full

    state, data = h.db.get_state(h.client_id)
    duration = 40
    svc = h.cfg.service(str(data.get("service_id", "")))
    if svc:
        duration = svc.duration
    for date in available_dates(h.cfg, h.db, duration, h.clock()):
        if format_date_full(date) == label.strip():
            return date.strftime("%Y-%m-%d")
    raise AssertionError(f"Не смог сопоставить кнопку даты {label!r}")
