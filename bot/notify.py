"""Уведомления: клиенту и мастеру.

Все исходящие сообщения кладутся в таблицу outbox и отправляются воркером
(bot/scheduler.py). Поэтому:
  * уведомления не теряются при перезапуске бота/ноутбука;
  * все вызовы VK API идут последовательно из одного потока (без флуд-лимита);
  * порядок сообщений для одного собеседника сохраняется.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Callable

from .config import Config
from .db import Database, Request
from .keyboards import admin_request_keyboard, main_menu
from .util import (
    format_date_full,
    format_dt_full,
    human_delta,
    plural,
    vk_dialog_link,
    vk_user_link,
)

log = logging.getLogger("bot.notify")


class Notifier:
    def __init__(self, cfg: Config, db: Database, now_fn: Callable[[], datetime]):
        self.cfg = cfg
        self.db = db
        self.now = now_fn

    # ------------------------------------------------------------------ #
    # базовая отправка (в очередь)
    # ------------------------------------------------------------------ #
    def to_user(self, peer_id: int, text: str, keyboard: dict | None = None,
                delay_seconds: float = 0) -> None:
        send_after = None
        if delay_seconds:
            send_after = self.now() + timedelta(seconds=delay_seconds)
        self.db.enqueue_message(peer_id, text, keyboard, send_after=send_after, now=self.now())

    def to_admins(self, text: str, keyboard: dict | None = None) -> None:
        if not self.cfg.admin_ids:
            log.warning("ADMIN_VK_IDS не задан — уведомление ушло в никуда")
            return
        for admin_id in self.cfg.admin_ids:
            self.to_user(admin_id, text, keyboard)

    # ------------------------------------------------------------------ #
    # контекст для шаблонов
    # ------------------------------------------------------------------ #
    def ctx(self, req: Request | None = None, **extra) -> dict:
        now = self.now()
        base: dict = {
            "master": self.cfg.contacts.master_name,
            "phone": self.cfg.contacts.phone or self.cfg.contacts.vk,
            "address": self.cfg.contacts.address,
            "contacts": self.cfg.contacts.card(),
            "card": self.cfg.contacts.card(),
            "ttl": human_delta(timedelta(hours=self.cfg.pending_ttl_hours)),
            "hours": self.cfg.client_cancel_min_hours,
        }
        if req is not None:
            client = self.db.get_client(req.client_vk_id)
            vk_name = ""
            if client:
                vk_name = " ".join(
                    x for x in (client["first_name"], client["last_name"]) if x
                )
            base.update(
                {
                    "id": req.id,
                    "title": req.service_title,
                    "duration": req.duration,
                    "price": f"{req.price} ₽" if req.price else "цена по договорённости",
                    "when": format_dt_full(req.starts_at),
                    "when_short": req.starts_at.strftime("%d.%m %H:%M"),
                    "date": format_date_full(req.starts_at),
                    "name": req.client_name or vk_name or f"id{req.client_vk_id}",
                    "vk_name": vk_name,
                    "contact": req.contact,
                    "comment": req.comment or "—",
                    "status": req.status_ru,
                    "reason": req.reject_reason or "",
                    "dialog": vk_dialog_link(req.client_vk_id),
                    "profile": vk_user_link(req.client_vk_id),
                    "delta": human_delta(req.starts_at - now),
                }
            )
        base.update(extra)
        return base

    # ------------------------------------------------------------------ #
    # конкретные уведомления
    # ------------------------------------------------------------------ #
    def new_request(self, req: Request) -> None:
        """Мастеру приходит заявка с кнопками подтверждения."""
        if not self.cfg.notify_admin_on_request:
            return
        text = self.cfg.text("new_request_admin", **self.ctx(req))
        self.to_admins(text, admin_request_keyboard(self.cfg, req))

    def approved_client(self, req: Request) -> None:
        self.to_user(
            req.client_vk_id, self.cfg.text("approved_client", **self.ctx(req))
        )

    def approved_admin(self, req: Request, exclude_id: int | None = None) -> None:
        """Дублируем подтверждение остальным мастерам.

        Тот, кто нажал кнопку, уже получил ответ с клавиатурой — ему не повторяем.
        """
        text = self.cfg.text("approved_admin", **self.ctx(req))
        for admin_id in self.cfg.admin_ids:
            if exclude_id is not None and admin_id == exclude_id:
                continue
            self.to_user(admin_id, text)

    def rejected_client(self, req: Request) -> None:
        self.to_user(
            req.client_vk_id,
            self.cfg.text("rejected_client", **self.ctx(req)),
            main_menu(self.cfg),
        )

    def expired_client(self, req: Request) -> None:
        self.to_user(
            req.client_vk_id,
            self.cfg.text("expired_client", **self.ctx(req)),
            main_menu(self.cfg),
        )

    def cancelled_to_admin(self, req: Request) -> None:
        if not self.cfg.notify_admin_on_cancel:
            return
        self.to_admins(self.cfg.text("request_cancelled_admin", **self.ctx(req)))

    def cancelled_to_client(self, req: Request) -> None:
        self.to_user(
            req.client_vk_id,
            self.cfg.text("cancelled_client", **self.ctx(req)),
            main_menu(self.cfg),
        )

    def rescheduled_client(self, req: Request) -> None:
        self.to_user(req.client_vk_id, self.cfg.text("rescheduled_client", **self.ctx(req)))

    def rescheduled_admin(self, req: Request) -> None:
        self.to_admins(self.cfg.text("rescheduled_admin", **self.ctx(req)))

    def reminder_client(self, req: Request) -> None:
        self.to_user(req.client_vk_id, self.cfg.text("reminder_client", **self.ctx(req)))

    def reminder_admin(self, req: Request) -> None:
        self.to_admins(self.cfg.text("reminder_admin", **self.ctx(req)))

    # ------------------------------------------------------------------ #
    # планирование напоминаний
    # ------------------------------------------------------------------ #
    def plan_reminders(self, req: Request) -> int:
        """Создаёт напоминания для подтверждённой записи. Возвращает сколько новых."""
        if req.status != "confirmed":
            return 0
        created = 0
        for hours in self.cfg.client_before_hours:
            if self.db.ensure_reminder(
                req.id,
                f"client_{hours}h",
                req.starts_at - timedelta(hours=hours),
                now=self.now(),
            ):
                created += 1
        for hours in self.cfg.admin_before_hours:
            if self.db.ensure_reminder(
                req.id,
                f"admin_{hours}h",
                req.starts_at - timedelta(hours=hours),
                now=self.now(),
            ):
                created += 1
        return created

    # ------------------------------------------------------------------ #
    # утренний дайджест мастера
    # ------------------------------------------------------------------ #
    def digest(self, day: datetime, requests: list[Request]) -> None:
        date_txt = format_date_full(day)
        if not requests:
            self.to_admins(self.cfg.text("digest_empty", date=date_txt))
            return
        lines = []
        for req in requests:
            status = "⏳" if req.status == "pending" else "✅"
            lines.append(
                f"{status} {req.starts_at.strftime('%H:%M')} — {req.client_name}"
                f" · {req.service_title} · {req.contact}"
            )
        self.to_admins(
            self.cfg.text(
                "digest",
                date=date_txt,
                list="\n".join(lines),
                count=plural(len(requests), "запись", "записи", "записей"),
            )
        )
