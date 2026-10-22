"""Приём событий Bots Long Poll и маршрутизация в логику (bot/flow.py).

Класс Bot не знает про urllib и про реальный ВКонтакте: ему нужен любой
«отправитель» с двумя методами (send_message / answer_event). Благодаря этому
весь сценарий прогоняется в тестах и в scripts/demo.py без сети.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from typing import Any, Callable, Protocol

from .config import Config
from .db import Database
from .flow import Flow, FlowDeps, Reply, UserCtx
from .notify import Notifier
from .util import vk_user_link

log = logging.getLogger("bot.handlers")

CHAT_PEER_OFFSET = 2_000_000_000  # peer_id бесед начинается с 2e9


class Sender(Protocol):
    def send_message(self, peer_id: int, text: str = "",
                     keyboard: dict | None = None) -> Any: ...

    def answer_event(self, peer_id: int, user_id: int, event_id: str,
                     text: str = "Готово ✅") -> None: ...


SNACKBARS = {
    "ok": "Заявка подтверждена ✅",
    "no": "Заявка отклонена 🚫",
    "reschedule": "Выбираем новое время…",
    "rs_slot": "Переносим запись…",
    "submit": "Отправляю заявку…",
    "cancel_req": "Отменяем запись…",
    "adm_open": "Открываю заявку…",
}


class Bot:
    def __init__(
        self,
        cfg: Config,
        db: Database,
        sender: Sender,
        now_fn: Callable[[], datetime] | None = None,
    ):
        self.cfg = cfg
        self.db = db
        self.sender = sender
        self.now_fn = now_fn or (lambda: datetime.now(cfg.tzinfo).replace(tzinfo=None))
        self.notify = Notifier(cfg, db, self.now_fn)
        self.flow = Flow(FlowDeps(cfg=cfg, db=db, notify=self.notify, now_fn=self.now_fn))
        self.stats = {"messages": 0, "events": 0, "ignored": 0}

    # ------------------------------------------------------------------ #
    # события
    # ------------------------------------------------------------------ #
    def on_event(self, event: dict) -> None:
        etype = event.get("type")
        obj = event.get("object") or {}
        if etype == "message_new":
            message = obj.get("message") or obj
            self.on_message(message)
        elif etype == "message_event":
            self.on_message_event(obj)
        elif etype in ("message_reply", "message_edit", "message_typing_state",
                       "message_allow", "message_deny"):
            self.stats["ignored"] += 1
        else:
            self.stats["ignored"] += 1
            log.debug("Пропущено событие %s", etype)

    def on_message(self, message: dict) -> None:
        from_id = int(message.get("from_id") or 0)
        peer_id = int(message.get("peer_id") or from_id)
        text = message.get("text") or message.get("body") or ""
        payload = self._parse_payload(message.get("payload"))

        if not from_id or from_id < 0:
            self.stats["ignored"] += 1
            return
        if peer_id >= CHAT_PEER_OFFSET:
            # беседа (чат) — запись ведём только в личных сообщениях сообщества
            self.stats["ignored"] += 1
            log.info("Сообщение из беседы %s пропущено", peer_id)
            return

        self.stats["messages"] += 1
        ctx = self._ctx(from_id, peer_id, message)
        log.info(
            "← %s (%s): %s%s",
            ctx.full_name, from_id, text[:60] or "…",
            f" payload={payload}" if payload else "",
        )
        replies = self.flow.handle(ctx, text, payload)
        self._send_replies(peer_id, replies)

    def on_message_event(self, obj: dict) -> None:
        user_id = int(obj.get("user_id") or 0)
        peer_id = int(obj.get("peer_id") or user_id)
        event_id = str(obj.get("event_id") or "")
        payload = self._parse_payload(obj.get("payload"))
        if not user_id:
            return
        self.stats["events"] += 1

        cmd = (payload or {}).get("c", "")
        snackbar = SNACKBARS.get(cmd, "Принято ✅")
        try:
            self.sender.answer_event(peer_id, user_id, event_id, snackbar)
        except Exception as exc:  # noqa: BLE001 - не роняем бота из-за снекбара
            log.warning("answer_event failed: %s", exc)

        ctx = self._ctx(user_id, peer_id)
        log.info("← callback %s от %s", cmd, user_id)
        replies = self.flow.handle(ctx, "", payload)
        self._send_replies(peer_id, replies)

    # ------------------------------------------------------------------ #
    # помощники
    # ------------------------------------------------------------------ #
    def _parse_payload(self, raw: Any) -> dict | None:
        if not raw:
            return None
        if isinstance(raw, dict):
            return raw
        if isinstance(raw, str):
            try:
                parsed = json.loads(raw)
                return parsed if isinstance(parsed, dict) else None
            except json.JSONDecodeError:
                return None
        return None

    def _ctx(self, vk_id: int, peer_id: int | None = None,
             message: dict | None = None) -> UserCtx:
        first = last = ""
        if message:
            first = str(message.get("from_first_name") or "").strip()
            last = str(message.get("from_last_name") or "").strip()
        stored = self.db.get_client(vk_id)
        if stored and (stored["first_name"] or stored["last_name"]):
            first = first or stored["first_name"]
            last = last or stored["last_name"]
        if not first:
            names = self._fetch_names([vk_id])
            first, last = names.get(vk_id, ("", ""))
        self.db.upsert_client(vk_id, first, last, now=self.now_fn())
        return UserCtx(
            vk_id=vk_id,
            first_name=first,
            last_name=last,
            is_admin=vk_id in self.cfg.admin_ids,
            peer_id=peer_id or vk_id,
        )

    def _fetch_names(self, user_ids: list[int]) -> dict[int, tuple[str, str]]:
        """Добираем имена через users.get, если отправитель это умеет."""
        fetch = getattr(self.sender, "get_user_names", None)
        if not callable(fetch):
            return {}
        try:
            return fetch(user_ids) or {}
        except Exception as exc:  # noqa: BLE001
            log.warning("Не получил имена пользователей: %s", exc)
            return {}

    def _send_replies(self, peer_id: int, replies: list[Reply]) -> None:
        for reply in replies or []:
            if not reply.text and not reply.keyboard:
                continue
            self.notify.to_user(peer_id, reply.text, reply.keyboard)

    # ------------------------------------------------------------------ #
    # отправка очереди (вызывается воркером)
    # ------------------------------------------------------------------ #
    def flush_outbox(self, limit: int = 20, max_attempts: int = 5) -> int:
        """Отправляет накопившиеся сообщения. Возвращает число отправленных."""
        sent = 0
        now = self.now_fn()
        for item in self.db.due_messages(now, limit=limit):
            try:
                self.sender.send_message(item.peer_id, item.text, item.keyboard)
            except Exception as exc:  # noqa: BLE001
                attempts = item.attempts + 1
                self.db.mark_message_failed(item.id, str(exc))
                if attempts >= max_attempts:
                    log.error(
                        "→ %s: НЕ доставлено после %s попыток (%s): %s",
                        item.peer_id, attempts, exc, item.text[:60],
                    )
                    self.db.mark_message_sent(item.id, now=self.now_fn())
                else:
                    delay = min(300, 5 * (2 ** (attempts - 1)))
                    self.db.defer_message(item.id, now + _seconds(delay))
                    log.warning(
                        "→ %s: ошибка (%s), повтор через %s с", item.peer_id, exc, delay
                    )
                continue
            self.db.mark_message_sent(item.id, now=self.now_fn())
            sent += 1
            log.info("→ %s: %s", item.peer_id, item.text.replace("\n", " ")[:80])
        return sent


def _seconds(value: float):
    from datetime import timedelta

    return timedelta(seconds=value)
