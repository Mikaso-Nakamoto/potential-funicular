"""Логика диалога: запись клиента и панель мастера.

Модуль не знает про ВКонтакте: на вход получает текст/payload и данные
пользователя, на выход отдаёт список Reply (текст + клавиатура). Это позволяет
тестировать весь сценарий офлайн (tests/, scripts/demo.py).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Callable

from . import keyboards as kb
from .config import Config, Service
from .db import (
    ACTIVE_STATUSES,
    STATUS_CANCELLED,
    STATUS_CONFIRMED,
    STATUS_EXPIRED,
    STATUS_PENDING,
    STATUS_REJECTED,
    Database,
    Request,
    SlotConflict,
)
from .notify import Notifier
from .slots import (
    available_dates,
    day_slots,
    is_working_day,
    nearest_slot,
    slot_is_free,
    work_hours_text,
)
from .util import (
    format_date_full,
    format_dt,
    format_dt_full,
    normalize_phone,
    parse_date,
    parse_hhmm,
    parse_range,
    plural,
    truncate,
    vk_dialog_link,
    vk_user_link,
)

log = logging.getLogger("bot.flow")

DATES_PER_PAGE = 7
MAX_SLOT_BUTTONS = 24

# состояния клиентского сценария
S_IDLE = "idle"
S_SERVICE = "pick_service"
S_DATE = "pick_date"
S_TIME = "pick_time"
S_NAME = "ask_name"
S_CONTACT = "ask_contact"
S_COMMENT = "ask_comment"
S_SUMMARY = "summary"
# состояния мастера
S_ADM_RESCHEDULE = "adm_reschedule"
S_ADM_OFF = "adm_off"
S_ADM_BLOCK = "adm_block"


@dataclass
class Reply:
    text: str
    keyboard: dict | None = None


@dataclass
class UserCtx:
    vk_id: int
    first_name: str = ""
    last_name: str = ""
    is_admin: bool = False
    peer_id: int | None = None

    @property
    def name(self) -> str:
        return self.first_name or "гость"

    @property
    def full_name(self) -> str:
        full = " ".join(x for x in (self.first_name, self.last_name) if x)
        return full or f"id{self.vk_id}"


@dataclass
class FlowDeps:
    cfg: Config
    db: Database
    notify: Notifier
    now_fn: Callable[[], datetime]

    @property
    def now(self) -> datetime:
        return self.now_fn()


MENU_WORDS = ("меню", "старт", "start", "начало", "здрав", "привет", "добры")
# слова, по которым человек может выйти из сценария записи на любом шаге
ESCAPE_WORDS = ("меню", "отмена", "отменить", "старт", "/start", "/меню")
BOOK_WORDS = ("записа", "забронир", "хочу на массаж", "на массаж", "запись")
MINE_WORDS = ("мои запис", "моя запис", "мои брон", "отменить запис")
PRICE_WORDS = ("цен", "прайс", "услуг", "стоимост", "сколько стоит")
CONTACT_WORDS = ("контакт", "телефон", "позвон", "связ", "написать", "whatsapp", "адрес")


def _has(text: str, words: tuple[str, ...]) -> bool:
    low = text.lower()
    return any(w in low for w in words)


class Flow:
    def __init__(self, deps: FlowDeps):
        self.cfg = deps.cfg
        self.db = deps.db
        self.notify = deps.notify
        self._now_fn = deps.now_fn
        self._last_action: dict[int, datetime] = {}

    @property
    def now(self) -> datetime:
        return self._now_fn()

    def _t(self, key: str, req: Request | None = None, **extra) -> str:
        """Текст из конфига + базовый контекст (мастер, телефон, адрес, контакты)."""
        ctx = self.notify.ctx(req)
        ctx.update(extra)
        return self.cfg.text(key, **ctx)

    # ================================================================== #
    # точка входа
    # ================================================================== #
    def handle(self, ctx: UserCtx, text: str, payload: dict | None) -> list[Reply]:
        text = (text or "").strip()
        cmd = (payload or {}).get("c") if isinstance(payload, dict) else None
        value = (payload or {}).get("v") if isinstance(payload, dict) else None

        if not self._cooldown_ok(ctx):
            return []

        state, data = self.db.get_state(ctx.vk_id)

        # служебные команды мастера — имеют приоритет
        if text.startswith("/") and ctx.is_admin:
            return self.admin_command(ctx, text)

        if cmd == "menu" or (not cmd and _has(text, ESCAPE_WORDS)):
            self.db.clear_state(ctx.vk_id)
            return [self._greeting(ctx)]
        if cmd == "cancel":
            self.db.clear_state(ctx.vk_id)
            return [Reply("Хорошо, отменили 🌿 Чем помочь?", kb.main_menu(self.cfg, ctx.is_admin))]

        # свободный текст-навигация работает только вне сценария записи,
        # иначе «адрес» вместо телефона ломал бы текущий шаг
        free_text = not cmd and state in (S_IDLE, "")
        if cmd == "book" or (free_text and _has(text, BOOK_WORDS)):
            return self._start_booking(ctx)
        if cmd == "mine" or (free_text and _has(text, MINE_WORDS)):
            return self._my_bookings(ctx)
        if cmd == "prices" or (free_text and _has(text, PRICE_WORDS)):
            return self._prices(ctx)
        if cmd == "contact" or (free_text and _has(text, CONTACT_WORDS)):
            return self._contacts(ctx)
        if not cmd and state == S_IDLE and _has(text, MENU_WORDS):
            return [self._greeting(ctx)]
        if cmd == "about":
            return self._about(ctx)
        if cmd == "admin" and ctx.is_admin:
            return self._admin_panel(ctx)

        # --- состояния клиентского сценария --- #
        if cmd == "svc":
            return self._on_service(ctx, str(value or ""))
        if cmd == "back_services":
            return self._services(ctx, S_SERVICE)
        if cmd == "dates":
            return self._show_dates(ctx, data, int(value or 0))
        if cmd == "date":
            return self._on_date(ctx, data, str(value or ""))
        if cmd in ("date_back", "edit_time"):
            data.pop("starts_at", None)
            return self._show_dates(ctx, data, int(data.get("page", 0)))
        if cmd == "time":
            return self._on_time(ctx, data, str(value or ""))
        if cmd == "name_ok":
            data["name"] = ctx.full_name
            return self._ask_contact(ctx, data)
        if cmd == "contact_vk":
            data["contact"] = f"ВКонтакте: {vk_user_link(ctx.vk_id)}"
            return self._ask_comment(ctx, data)
        if cmd == "contact_keep":
            data["contact"] = data.get("contact") or vk_user_link(ctx.vk_id)
            return self._ask_comment(ctx, data)
        if cmd == "no_comment":
            data["comment"] = ""
            return self._summary(ctx, data)
        if cmd == "submit":
            return self._submit(ctx, data)
        if cmd == "cancel_req":
            return self._cancel_request(ctx, int(value or 0))

        # --- состояния мастера --- #
        if cmd == "ok":
            return self._approve(ctx, int(value or 0))
        if cmd == "no":
            return self._reject(ctx, int(value or 0))
        if cmd == "reschedule":
            return self._reschedule_start(ctx, int(value or 0))
        if cmd == "rs_slot":
            return self._reschedule_to(ctx, data, str(value or ""))
        if cmd == "adm_pending":
            return self._admin_pending(ctx)
        if cmd == "adm_today":
            return self._admin_day_list(ctx, self.now.replace(hour=0, minute=0, second=0, microsecond=0))
        if cmd == "adm_week":
            return self._admin_week(ctx)
        if cmd == "adm_stats":
            return self._admin_stats(ctx)
        if cmd == "adm_off":
            return self._admin_off(ctx)
        if cmd == "adm_contacts":
            return self._contacts(ctx)
        if cmd == "adm_help":
            return [Reply(self._t("admin_help"), kb.admin_menu(self.cfg))]
        if cmd == "adm_open":
            req = self.db.get_request(int(value or 0))
            if not req:
                return [Reply(self._t("request_not_found", id=value))]
            return [
                Reply(
                    self._request_card(req) + "\n\nЧто сделать с заявкой?",
                    kb.admin_request_keyboard(self.cfg, req),
                )
            ]

        # --- свободный текст внутри сценария --- #
        if state == S_NAME:
            return self._on_name(ctx, data, text)
        if state == S_CONTACT:
            return self._on_contact(ctx, data, text)
        if state == S_COMMENT:
            return self._on_comment(ctx, data, text)
        if state in (S_SERVICE, S_DATE, S_TIME, S_SUMMARY):
            # человек пишет текстом вместо кнопок — подсказываем и возвращаем клавиатуру
            if _has(text, BOOK_WORDS):
                return self._start_booking(ctx)
            hint = "Сейчас выбираем время — нажмите, пожалуйста, кнопку ниже 🙂"
            live = self.cfg.contacts.phone or self.cfg.contacts.vk
            if live:
                hint += f"\nИли напишите мастеру напрямую: {live}"
            return [Reply(hint, self._keyboard_for_state(state, data))]
        if state == S_ADM_RESCHEDULE:
            return [Reply("Выберите новое время кнопкой ниже или нажмите «Отмена».",
                          self._keyboard_for_state(state, data))]

        return [Reply(self._t("unknown"), kb.main_menu(self.cfg, ctx.is_admin))]

    # ================================================================== #
    # анти-спам
    # ================================================================== #
    def _cooldown_ok(self, ctx: UserCtx) -> bool:
        if not self.cfg.cooldown_seconds:
            return True
        now = self.now
        last = self._last_action.get(ctx.vk_id)
        self._last_action[ctx.vk_id] = now
        if last is None:
            return True
        return (now - last).total_seconds() >= self.cfg.cooldown_seconds

    def _keyboard_for_state(self, state: str, data: dict) -> dict | None:
        if state == S_SERVICE:
            return kb.services_keyboard(self.cfg)
        if state == S_DATE:
            dates = self._dates_for(data)
            page = int(data.get("page", 0))
            chunk = dates[page * DATES_PER_PAGE : (page + 1) * DATES_PER_PAGE]
            return kb.dates_keyboard(chunk, page, max(1, -(-len(dates) // DATES_PER_PAGE)))
        if state == S_TIME:
            starts = self._starts_from(data)
            if not starts:
                return None
            return kb.slots_keyboard(
                day_slots(self.cfg, self.db, starts, self._duration(data), self.now), starts
            )
        if state == S_NAME:
            return kb.name_keyboard(data.get("vk_name", ""))
        if state == S_CONTACT:
            return kb.contact_keyboard()
        if state == S_COMMENT:
            return kb.comment_keyboard()
        if state == S_SUMMARY:
            return kb.summary_keyboard()
        if state == S_ADM_RESCHEDULE:
            slots = self._reschedule_slots(data)
            return kb.admin_reschedule_keyboard(self.cfg, slots) if slots else None
        return None

    # ================================================================== #
    # разделы меню
    # ================================================================== #
    def _greeting(self, ctx: UserCtx) -> Reply:
        text = self._t(
            "greeting", name=ctx.name, master=self.cfg.contacts.master_name
        )
        if ctx.is_admin:
            text += "\n\n(Вы — мастер: доступны команды /help и панель ниже)"
        return Reply(text, kb.main_menu(self.cfg, ctx.is_admin))

    def _services(self, ctx: UserCtx, state: str = S_IDLE) -> list[Reply]:
        services = self.cfg.active_services()
        if not services:
            return [Reply(self._t("no_services"), kb.main_menu(self.cfg, ctx.is_admin))]
        self.db.set_state(ctx.vk_id, state, {}, now=self.now)
        return [Reply(self._t("services_intro"), kb.services_keyboard(self.cfg))]

    def _prices(self, ctx: UserCtx) -> list[Reply]:
        services = self.cfg.active_services()
        if not services:
            return [Reply(self._t("no_services"), kb.main_menu(self.cfg, ctx.is_admin))]
        lines = []
        for svc in services:
            lines.append(f"🔹 {svc.title} — {svc.duration} мин, {svc.price_text()}")
            if svc.description:
                lines.append(f"   {svc.description}")
        text = self._t("prices", list="\n".join(lines))
        rows = [[kb.text_button(svc.title, "svc", svc.id, color=kb.PRIMARY)] for svc in services]
        rows.append([kb.text_button("🔙 Меню", "menu")])
        return [Reply(text, kb.keyboard(rows, one_time=True))]

    def _contacts(self, ctx: UserCtx) -> list[Reply]:
        text = self._t("contacts", card=self.cfg.contacts.card())
        rows = [
            [kb.text_button("📅 Записаться", "book", color=kb.PRIMARY)],
            [kb.text_button("🔙 Меню", "menu")],
        ]
        return [Reply(text, kb.keyboard(rows, one_time=False))]

    def _about(self, ctx: UserCtx) -> list[Reply]:
        text = self._t(
            "about",
            master=self.cfg.contacts.master_name,
            hours=work_hours_text(self.cfg),
            card=self.cfg.contacts.card(),
            address=self.cfg.contacts.address,
        )
        return [Reply(text, kb.main_menu(self.cfg, ctx.is_admin))]

    def _my_bookings(self, ctx: UserCtx) -> list[Reply]:
        requests = self.db.list_requests(statuses=ACTIVE_STATUSES, client_vk_id=ctx.vk_id)
        if not requests:
            return [Reply(self._t("my_bookings_empty"), kb.main_menu(self.cfg, ctx.is_admin))]
        lines = []
        for req in requests:
            mark = "⏳ ждёт подтверждения" if req.status == STATUS_PENDING else "✅ подтверждена"
            lines.append(
                f"№{req.id} · {req.service_title}\n   📅 {format_dt_full(req.starts_at)}\n   {mark}"
            )
        text = self._t("my_bookings", list="\n\n".join(lines))
        return [Reply(text, kb.my_bookings_keyboard(requests))]

    # ================================================================== #
    # сценарий записи
    # ================================================================== #
    def _start_booking(self, ctx: UserCtx) -> list[Reply]:
        active = self.db.count_active(ctx.vk_id)
        if active >= self.cfg.max_active_requests:
            return [
                Reply(
                    self._t("too_many_requests", count=active),
                    kb.main_menu(self.cfg, ctx.is_admin),
                )
            ]
        return self._services(ctx, S_SERVICE)

    def _duration(self, data: dict) -> int:
        svc = self.cfg.service(str(data.get("service_id", "")))
        return svc.duration if svc else 60

    def _dates_for(self, data: dict) -> list[datetime]:
        return available_dates(self.cfg, self.db, self._duration(data), self.now)

    def _on_service(self, ctx: UserCtx, service_id: str) -> list[Reply]:
        svc = self.cfg.service(service_id)
        if not svc or not svc.active:
            return self._services(ctx, S_SERVICE)
        data = {"service_id": svc.id, "page": 0, "vk_name": ctx.full_name}
        dates = available_dates(self.cfg, self.db, svc.duration, self.now)
        if not dates:
            self.db.set_state(ctx.vk_id, S_SERVICE, data, now=self.now)
            return [
                Reply(
                    self._t("no_dates", days=self.cfg.max_days_ahead),
                    kb.services_keyboard(self.cfg),
                )
            ]
        return self._show_dates(ctx, data, 0)

    def _show_dates(self, ctx: UserCtx, data: dict, page: int) -> list[Reply]:
        dates = self._dates_for(data)
        if not dates:
            return [
                Reply(
                    self._t("no_dates", days=self.cfg.max_days_ahead),
                    kb.main_menu(self.cfg, ctx.is_admin),
                )
            ]
        pages = max(1, -(-len(dates) // DATES_PER_PAGE))
        page = max(0, min(page, pages - 1))
        chunk = dates[page * DATES_PER_PAGE : (page + 1) * DATES_PER_PAGE]
        data["page"] = page
        self.db.set_state(ctx.vk_id, S_DATE, data, now=self.now)
        svc = self.cfg.service(str(data.get("service_id", "")))
        title = svc.title if svc else "массаж"
        duration = svc.duration if svc else self._duration(data)
        return [
            Reply(
                self._t("pick_date", title=title, duration=duration),
                kb.dates_keyboard(chunk, page, pages),
            )
        ]

    def _starts_from(self, data: dict) -> datetime | None:
        raw = data.get("starts_at")
        if not raw:
            return None
        try:
            from .util import from_iso

            return from_iso(str(raw))
        except ValueError:
            return None

    def _on_date(self, ctx: UserCtx, data: dict, raw_date: str) -> list[Reply]:
        try:
            date = parse_date(raw_date)
        except ValueError:
            return self._show_dates(ctx, data, int(data.get("page", 0)))
        duration = self._duration(data)
        slots = day_slots(self.cfg, self.db, date, duration, self.now)
        if not slots:
            data["page"] = int(data.get("page", 0))
            return [
                Reply(
                    self._t("no_slots", date=format_date_full(date)),
                    self._keyboard_for_state(S_DATE, data),
                )
            ]
        return self._show_slots(ctx, data, date, slots)

    def _show_slots(self, ctx: UserCtx, data: dict, date: datetime,
                    slots: list[datetime]) -> list[Reply]:
        data["date"] = date.strftime("%Y-%m-%d")
        self.db.set_state(ctx.vk_id, S_TIME, data, now=self.now)
        return [
            Reply(
                self._t(
                    "pick_time",
                    date=format_date_full(date),
                    minutes=self._duration(data),
                    count=plural(len(slots), "свободное окно", "свободных окна", "свободных окон"),
                ),
                kb.slots_keyboard(slots[:MAX_SLOT_BUTTONS], date),
            )
        ]

    def _on_time(self, ctx: UserCtx, data: dict, raw: str) -> list[Reply]:
        try:
            from .util import from_iso

            starts_at = from_iso(raw)
        except ValueError:
            return [Reply("Не понял время 🤔 Выберите, пожалуйста, кнопку со временем.")]
        duration = self._duration(data)
        if not slot_is_free(self.cfg, self.db, starts_at, duration, self.now):
            slots = day_slots(self.cfg, self.db, starts_at, duration, self.now)
            if not slots:
                return self._show_dates(ctx, data, int(data.get("page", 0)))
            return [
                Reply(
                    self._t("slot_taken", when=format_dt(starts_at)),
                    kb.slots_keyboard(slots[:MAX_SLOT_BUTTONS], starts_at),
                )
            ]
        data["starts_at"] = starts_at.strftime("%Y-%m-%dT%H:%M")
        return self._ask_name(ctx, data)

    def _ask_name(self, ctx: UserCtx, data: dict) -> list[Reply]:
        data.setdefault("vk_name", ctx.full_name)
        data["name"] = data.get("name") or ctx.full_name
        self.db.set_state(ctx.vk_id, S_NAME, data, now=self.now)
        return [
            Reply(
                self._t("ask_name", name=data["vk_name"]),
                kb.name_keyboard(data["vk_name"]),
            )
        ]

    def _on_name(self, ctx: UserCtx, data: dict, text: str) -> list[Reply]:
        name = truncate(text, 60)
        if len(name) < 2 or name.startswith("/"):
            return [Reply(self._t("bad_name"), kb.name_keyboard(data.get("vk_name", "")))]
        data["name"] = name
        return self._ask_contact(ctx, data)

    def _ask_contact(self, ctx: UserCtx, data: dict) -> list[Reply]:
        known = self.db.get_client(ctx.vk_id)
        if known and known["phone"] and not data.get("contact"):
            data["contact"] = known["phone"]
        self.db.set_state(ctx.vk_id, S_CONTACT, data, now=self.now)
        hint = f"\n\nРаньше вы оставляли: {data['contact']}" if data.get("contact") else ""
        rows = []
        if data.get("contact"):
            rows.append([kb.text_button("✅ Оставить этот", "contact_keep", color=kb.POSITIVE)])
        rows.append([kb.text_button("🔵 Через ВКонтакте", "contact_vk", color=kb.PRIMARY)])
        rows.append(kb.cancel_row())
        return [Reply(self._t("ask_contact") + hint, kb.keyboard(rows, one_time=True))]

    def _on_contact(self, ctx: UserCtx, data: dict, text: str) -> list[Reply]:
        phone = normalize_phone(text)
        if not phone:
            return [Reply(self._t("bad_contact"), kb.contact_keyboard())]
        data["contact"] = phone
        self.db.set_client_phone(ctx.vk_id, phone)
        return self._ask_comment(ctx, data)

    def _ask_comment(self, ctx: UserCtx, data: dict) -> list[Reply]:
        self.db.set_state(ctx.vk_id, S_COMMENT, data, now=self.now)
        return [Reply(self._t("ask_comment"), kb.comment_keyboard())]

    def _on_comment(self, ctx: UserCtx, data: dict, text: str) -> list[Reply]:
        data["comment"] = truncate(text, 300)
        return self._summary(ctx, data)

    def _summary(self, ctx: UserCtx, data: dict) -> list[Reply]:
        svc = self.cfg.service(str(data.get("service_id", "")))
        starts_at = self._starts_from(data)
        if not svc or not starts_at:
            self.db.clear_state(ctx.vk_id)
            return [
                Reply("Что-то потерялось 🙈 Давайте начнём заново.",
                      kb.main_menu(self.cfg, ctx.is_admin))
            ]
        data["name"] = data.get("name") or ctx.full_name
        data.setdefault("contact", vk_user_link(ctx.vk_id))
        self.db.set_state(ctx.vk_id, S_SUMMARY, data, now=self.now)
        return [
            Reply(
                self._t(
                    "summary",
                    title=svc.title,
                    when=format_dt_full(starts_at),
                    duration=svc.duration,
                    price=svc.price_text(),
                    name=data["name"],
                    contact=data.get("contact", ""),
                    comment=data.get("comment") or "—",
                ),
                kb.summary_keyboard(),
            )
        ]

    def _submit(self, ctx: UserCtx, data: dict) -> list[Reply]:
        svc = self.cfg.service(str(data.get("service_id", "")))
        starts_at = self._starts_from(data)
        if not svc or not starts_at:
            return self._start_booking(ctx)
        if not slot_is_free(self.cfg, self.db, starts_at, svc.duration, self.now):
            slots = day_slots(self.cfg, self.db, starts_at, svc.duration, self.now)
            if slots:
                return [
                    Reply(self._t("slot_taken", when=format_dt(starts_at)),
                          kb.slots_keyboard(slots[:MAX_SLOT_BUTTONS], starts_at))
                ]
            return self._show_dates(ctx, data, int(data.get("page", 0)))

        contact = data.get("contact") or vk_user_link(ctx.vk_id)
        try:
            req = self.db.create_request(
                client_vk_id=ctx.vk_id,
                service_id=svc.id,
                service_title=svc.title,
                starts_at=starts_at,
                duration=svc.duration,
                price=svc.price,
                client_name=data.get("name") or ctx.full_name,
                contact=contact,
                comment=data.get("comment", ""),
                now=self.now,
            )
        except SlotConflict:
            slots = day_slots(self.cfg, self.db, starts_at, svc.duration, self.now)
            return [
                Reply(
                    self._t("slot_taken", when=format_dt(starts_at)),
                    kb.slots_keyboard(slots[:MAX_SLOT_BUTTONS], starts_at) if slots
                    else kb.main_menu(self.cfg, ctx.is_admin),
                )
            ]

        self.db.clear_state(ctx.vk_id)
        self.notify.new_request(req)
        replies = [
            Reply(
                self._t(
                    "request_created",
                    title=svc.title,
                    when=format_dt_full(starts_at),
                    master=self.cfg.contacts.master_name,
                    contacts=self.cfg.contacts.card(),
                ),
                kb.after_request_keyboard(),
            )
        ]
        return replies

    # ================================================================== #
    # отмена записи клиентом
    # ================================================================== #
    def _cancel_request(self, ctx: UserCtx, request_id: int) -> list[Reply]:
        req = self.db.get_request(request_id)
        if not req or req.client_vk_id != ctx.vk_id:
            return [Reply(self._t("request_not_found", id=request_id),
                          kb.main_menu(self.cfg, ctx.is_admin))]
        if req.status not in ACTIVE_STATUSES:
            return [
                Reply(self._t("already_decided", id=req.id, status=req.status_ru),
                      kb.main_menu(self.cfg, ctx.is_admin))
            ]
        hours_left = (req.starts_at - self.now).total_seconds() / 3600
        if req.status == STATUS_CONFIRMED and hours_left < self.cfg.client_cancel_min_hours:
            return [
                Reply(self._t("cancel_too_late", req), kb.main_menu(self.cfg, ctx.is_admin))
            ]
        self.db.set_status(req.id, STATUS_CANCELLED, now=self.now, cancelled_by="client")
        self.db.drop_reminders(req.id)
        self.notify.cancelled_to_client(req)
        self.notify.cancelled_to_admin(req)
        return [
            Reply(
                self._t("cancelled_client", req)
                + "\n\nСлот снова свободен — можно выбрать другое время.",
                kb.main_menu(self.cfg, ctx.is_admin),
            )
        ]

    # ================================================================== #
    # мастер: действия с заявками
    # ================================================================== #
    def _request_card(self, req: Request) -> str:
        """Карточка заявки для мастера: услуга, время, клиент, связь, комментарий."""
        return self._t("new_request_admin", req)

    def _admin_guard(self, ctx: UserCtx) -> list[Reply] | None:
        if ctx.is_admin:
            return None
        log.warning("Попытка не-админа %s вызвать админ-действие", ctx.vk_id)
        return [Reply("Это раздел для мастера 🌿", kb.main_menu(self.cfg, False))]

    def _admin_panel(self, ctx: UserCtx) -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        pending = self.db.list_requests(statuses=[STATUS_PENDING], limit=1)
        today0 = self.now.replace(hour=0, minute=0, second=0, microsecond=0)
        today = self.db.list_requests(
            statuses=[STATUS_CONFIRMED], since=today0, until=today0 + timedelta(days=1)
        )
        header = (
            f"🛠 Панель мастера\n\n"
            f"🔔 Ждут подтверждения: {len(self.db.list_requests(statuses=[STATUS_PENDING]))}\n"
            f"📅 Сегодня записей: {len(today)}"
        )
        if pending:
            header += "\n\nБлижайшая заявка:\n" + self._request_card(pending[0])
        return [Reply(header, kb.admin_menu(self.cfg))]

    def _admin_pending(self, ctx: UserCtx) -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        requests = self.db.list_requests(statuses=[STATUS_PENDING], limit=50)
        if not requests:
            return [Reply("Новых заявок нет 🎉", kb.admin_menu(self.cfg))]
        out: list[Reply] = []
        for req in requests[:5]:
            out.append(
                Reply(self._request_card(req), kb.admin_request_keyboard(self.cfg, req))
            )
        if len(requests) > 5:
            out.append(
                Reply(
                    f"…и ещё {len(requests) - 5}. Полный список: /pending",
                    kb.admin_menu(self.cfg),
                )
            )
        return out

    def _admin_day_list(self, ctx: UserCtx, day: datetime) -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        day0 = day.replace(hour=0, minute=0, second=0, microsecond=0)
        requests = self.db.list_requests(
            statuses=[STATUS_CONFIRMED, STATUS_PENDING],
            since=day0,
            until=day0 + timedelta(days=1),
        )
        return [Reply(self._day_text(day0, requests), kb.admin_menu(self.cfg))]

    def _day_text(self, day: datetime, requests: list[Request]) -> str:
        if not requests:
            return f"📋 {format_date_full(day)}: записей нет — свободный день 🌿"
        lines = [f"📋 {format_date_full(day)} — {plural(len(requests), 'запись', 'записи', 'записей')}:"]
        for req in requests:
            mark = "⏳" if req.status == STATUS_PENDING else "✅"
            lines.append(
                f"{mark} {req.starts_at.strftime('%H:%M')} №{req.id} · {req.client_name}"
                f" · {req.service_title} · {req.contact}"
            )
        return "\n".join(lines)

    def _admin_week(self, ctx: UserCtx) -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        today0 = self.now.replace(hour=0, minute=0, second=0, microsecond=0)
        requests = self.db.list_requests(
            statuses=[STATUS_CONFIRMED, STATUS_PENDING],
            since=today0,
            until=today0 + timedelta(days=7),
        )
        if not requests:
            return [Reply("На ближайшие 7 дней записей нет.", kb.admin_menu(self.cfg))]
        by_day: dict[str, list[Request]] = {}
        for req in requests:
            by_day.setdefault(req.starts_at.strftime("%Y-%m-%d"), []).append(req)
        blocks = []
        for key in sorted(by_day):
            day = parse_date(key)
            blocks.append(self._day_text(day, by_day[key]))
        return [Reply("\n\n".join(blocks), kb.admin_menu(self.cfg))]

    def _admin_stats(self, ctx: UserCtx) -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        since = self.now - timedelta(days=30)
        stats = self.db.stats(since=since)
        lines = [
            f"📊 Статистика за 30 дней (с {since.strftime('%d.%m')}):",
            f"всего заявок: {stats.get('total', 0)}",
            f"✅ подтверждено: {stats.get(STATUS_CONFIRMED, 0)}",
            f"🔔 ждут ответа: {stats.get(STATUS_PENDING, 0)}",
            f"🚫 отклонено: {stats.get(STATUS_REJECTED, 0)}",
            f"❌ отменено: {stats.get(STATUS_CANCELLED, 0)}",
            f"⏳ истекло: {stats.get(STATUS_EXPIRED, 0)}",
            f"👥 клиентов в базе: {self.db.clients_count()}",
        ]
        return [Reply("\n".join(lines), kb.admin_menu(self.cfg))]

    def _admin_off(self, ctx: UserCtx) -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        today0 = self.now.replace(hour=0, minute=0, second=0, microsecond=0)
        days_off = self.db.list_day_off(since=today0, limit=10)
        text = "🚫 Выходные дни (слоты на них не предлагаются):\n"
        text += "\n".join(f"• {format_date_full(d)}" for d in days_off) if days_off else "• не заданы"
        text += "\n\nКак добавить: /off 2026-10-25 (или /off 25.10.2026)\nСнять: /on 2026-10-25"
        return [Reply(text, kb.admin_menu(self.cfg))]

    def _approve(self, ctx: UserCtx, request_id: int) -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        req = self.db.get_request(request_id)
        if not req:
            return [Reply(self._t("request_not_found", id=request_id))]
        if req.status != STATUS_PENDING:
            return [Reply(self._t("already_decided", req))]
        req = self.db.set_status(req.id, STATUS_CONFIRMED, now=self.now) or req
        self._plan_reminders(req)
        self.notify.approved_client(req)
        self.notify.approved_admin(req, exclude_id=ctx.vk_id)
        return [Reply(self._t("approved_admin", req), kb.admin_menu(self.cfg))]

    def _reject(self, ctx: UserCtx, request_id: int, reason: str = "") -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        req = self.db.get_request(request_id)
        if not req:
            return [Reply(self._t("request_not_found", id=request_id))]
        if req.status != STATUS_PENDING:
            return [Reply(self._t("already_decided", req))]
        req = self.db.set_status(req.id, STATUS_REJECTED, now=self.now,
                                 reject_reason=reason) or req
        self.db.drop_reminders(req.id)
        self.notify.rejected_client(req)
        return [Reply(self._t("rejected_admin", id=req.id), kb.admin_menu(self.cfg))]

    def _reschedule_slots(self, data: dict, limit: int = 12) -> list[datetime]:
        req = self.db.get_request(int(data.get("request_id", 0) or 0))
        if not req:
            return []
        slots: list[datetime] = []
        for date in available_dates(self.cfg, self.db, req.duration, self.now, limit=7):
            for s in day_slots(self.cfg, self.db, date, req.duration, self.now):
                if s != req.starts_at:
                    slots.append(s)
                if len(slots) >= limit:
                    return slots
        return slots

    def _reschedule_start(self, ctx: UserCtx, request_id: int) -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        req = self.db.get_request(request_id)
        if not req or req.status not in ACTIVE_STATUSES:
            return [Reply(self._t("request_not_found", id=request_id))]
        slots = self._reschedule_slots({"request_id": req.id})
        self.db.set_state(ctx.vk_id, S_ADM_RESCHEDULE, {"request_id": req.id}, now=self.now)
        if not slots:
            return [Reply("Свободных окон для переноса нет 😔", kb.admin_menu(self.cfg))]
        return [
            Reply(
                f"Куда перенести №{req.id} ({req.client_name}, {format_dt(req.starts_at)})?\n"
                "Ближайшие свободные окна:",
                kb.admin_reschedule_keyboard(self.cfg, slots),
            )
        ]

    def _reschedule_to(self, ctx: UserCtx, data: dict, raw: str) -> list[Reply]:
        blocked = self._admin_guard(ctx)
        if blocked:
            return blocked
        from .util import from_iso

        try:
            new_start = from_iso(raw)
        except ValueError:
            return [Reply("Не понял новое время 🤔")]
        req = self.db.get_request(int(data.get("request_id", 0) or 0))
        if not req:
            self.db.clear_state(ctx.vk_id)
            return [Reply(self._t("request_not_found", id=data.get("request_id")))]
        if not slot_is_free(self.cfg, self.db, new_start, req.duration, self.now,
                            include_pending=False):
            slots = self._reschedule_slots(data)
            return [
                Reply("Это время занято. Вот другие окна:",
                      kb.admin_reschedule_keyboard(self.cfg, slots) if slots else None)
            ]
        updated = self.db.reschedule_request(req.id, new_start, now=self.now)
        if not updated:
            return [Reply("Не получилось перенести — попробуйте ещё раз.")]
        self.db.clear_state(ctx.vk_id)
        self.db.drop_reminders(updated.id)
        self._plan_reminders(updated)
        self.notify.rescheduled_client(updated)
        self.notify.rescheduled_admin(updated)
        return [
            Reply(
                f"✅ Перенесено: №{updated.id} → {format_dt_full(updated.starts_at)}\n"
                "Клиенту отправлено уведомление.",
                kb.admin_menu(self.cfg),
            )
        ]

    def _plan_reminders(self, req: Request) -> None:
        """Планирует напоминания для подтверждённой записи."""
        self.notify.plan_reminders(req)

    # ================================================================== #
    # текстовые команды мастера
    # ================================================================== #
    def admin_command(self, ctx: UserCtx, text: str) -> list[Reply]:
        parts = text.strip().split()
        cmd = parts[0].lower().lstrip("/")
        args = parts[1:]

        if cmd in ("help", "помощь", "commands"):
            return [Reply(self._t("admin_help"), kb.admin_menu(self.cfg))]
        if cmd in ("today", "сегодня"):
            return self._admin_day_list(ctx, self.now)
        if cmd in ("week", "неделя"):
            return self._admin_week(ctx)
        if cmd in ("pending", "заявки"):
            return self._admin_pending(ctx)
        if cmd in ("stats", "статистика"):
            return self._admin_stats(ctx)
        if cmd in ("panel", "панель"):
            return self._admin_panel(ctx)
        if cmd in ("contacts", "контакты"):
            return self._admin_contacts(ctx)
        if cmd == "off":
            return self._cmd_day_off(ctx, args, add=True)
        if cmd == "on":
            return self._cmd_day_off(ctx, args, add=False)
        if cmd == "block":
            return self._cmd_block(ctx, args)
        if cmd in ("unblock",):
            return self._cmd_unblock(ctx, args)
        if cmd == "days":
            return self._cmd_list_days(ctx)
        if cmd == "approve":
            return self._approve(ctx, int(args[0])) if args and args[0].isdigit() else [
                Reply("Формат: /approve <номер заявки>")
            ]
        if cmd == "reject":
            if not args:
                return [Reply("Формат: /reject <номер> [причина]")]
            reason = " ".join(args[1:])
            return self._reject(ctx, int(args[0]), reason) if args[0].isdigit() else [
                Reply("Формат: /reject <номер> [причина]")
            ]
        if cmd == "say" or cmd == "notify":
            return self._cmd_notify(ctx, args)
        if cmd in ("test",):
            self.notify.to_admins("🔧 Тестовое уведомление — бот жив и пишет вам ✅")
            return [Reply("Отправил тестовое сообщение в очередь ✅")]
        return [Reply("Неизвестная команда. /help — список команд.", kb.admin_menu(self.cfg))]

    def _admin_contacts(self, ctx: UserCtx) -> list[Reply]:
        text = (
            "📞 Карточка контакта, которую видят клиенты:\n\n"
            + self.cfg.contacts.card()
            + "\n\nМеняется в config.toml, секция [contacts]."
        )
        return [Reply(text, kb.admin_menu(self.cfg))]

    def _cmd_day_off(self, ctx: UserCtx, args: list[str], add: bool) -> list[Reply]:
        if not args:
            return [Reply("Формат: /off 2026-10-25  или  /off 25.10.2026")]
        try:
            date = parse_date(args[0])
        except ValueError as exc:
            return [Reply(str(exc))]
        if add:
            affected = self.db.list_requests(
                statuses=ACTIVE_STATUSES,
                since=date,
                until=date + timedelta(days=1),
            )
            self.db.add_day_off(date, note=" ".join(args[1:]), now=self.now)
            text = f"🚫 {format_date_full(date)} — выходной, слоты скрыты."
            if affected:
                text += (
                    f"\n⚠️ На этот день {plural(len(affected), 'запись', 'записи', 'записей')}:"
                    + "\n"
                    + "\n".join(
                        f"• №{r.id} {r.starts_at.strftime('%H:%M')} {r.client_name} ({r.contact})"
                        for r in affected
                    )
                    + "\nСвяжитесь с ними, чтобы перенести."
                )
            return [Reply(text, kb.admin_menu(self.cfg))]
        removed = self.db.remove_day_off(date)
        return [
            Reply(
                f"✅ {format_date_full(date)} снова рабочий день."
                if removed
                else f"{format_date_full(date)} и так не был выходным."
            )
        ]

    def _cmd_block(self, ctx: UserCtx, args: list[str]) -> list[Reply]:
        if len(args) < 2:
            return [Reply("Формат: /block 2026-10-25 14:00-16:00 [причина]")]
        try:
            date = parse_date(args[0])
            start_t, end_t = parse_range(args[1])
        except ValueError as exc:
            return [Reply(str(exc))]
        starts = date.replace(hour=start_t.hour, minute=start_t.minute)
        ends = date.replace(hour=end_t.hour, minute=end_t.minute)
        note = " ".join(args[2:])
        blocked_id = self.db.add_blocked(starts, ends, note, now=self.now)
        affected = [
            r
            for r in self.db.list_requests(statuses=ACTIVE_STATUSES, since=starts, until=ends)
            if r.starts_at < ends and r.ends_at > starts
        ]
        text = (
            f"⛔ Занято №{blocked_id}: {format_date_full(starts)} "
            f"{starts.strftime('%H:%M')}–{ends.strftime('%H:%M')}"
        )
        if note:
            text += f"\nПричина: {note}"
        text += "\n\nСнять: /unblock"
        if affected:
            text += "\n⚠️ Пересечения с записями:\n" + "\n".join(
                f"• №{r.id} {r.starts_at.strftime('%H:%M')} {r.client_name}" for r in affected
            )
        return [Reply(text, kb.admin_menu(self.cfg))]

    def _cmd_unblock(self, ctx: UserCtx, args: list[str]) -> list[Reply]:
        if args and args[0].isdigit():
            ok = self.db.remove_blocked(int(args[0]))
            return [Reply("✅ Убрал." if ok else "Не нашёл такой блокировки.")]
        rows = self.db.list_blocked(since=self.now - timedelta(days=1), limit=20)
        if not rows:
            return [Reply("Активных блокировок нет.", kb.admin_menu(self.cfg))]
        lines = ["⛔ Занятые интервалы:"]
        for row in rows:
            starts = parse_date(row["starts_at"][:10]).replace(
                hour=int(row["starts_at"][11:13]), minute=int(row["starts_at"][14:16])
            )
            ends_hh, ends_mm = int(row["ends_at"][11:13]), int(row["ends_at"][14:16])
            lines.append(
                f"№{row['id']} · {format_date_full(starts)} "
                f"{starts.strftime('%H:%M')}–{ends_hh:02d}:{ends_mm:02d}"
                + (f" · {row['note']}" if row["note"] else "")
            )
        lines.append("\nУбрать: /unblock <номер>")
        return [Reply("\n".join(lines), kb.admin_menu(self.cfg))]

    def _cmd_list_days(self, ctx: UserCtx) -> list[Reply]:
        return [Reply("🗓 Расписание из config.toml:\n" + work_hours_text(self.cfg),
                      kb.admin_menu(self.cfg))]

    def _cmd_notify(self, ctx: UserCtx, args: list[str]) -> list[Reply]:
        """/say <текст> — написать всем, у кого есть активная запись."""
        if not args:
            return [Reply("Формат: /say Всем привет! Завтра есть окна в 15:00")]
        text = " ".join(args)
        today0 = self.now.replace(hour=0, minute=0, second=0, microsecond=0)
        targets = self.db.list_requests(
            statuses=[STATUS_CONFIRMED, STATUS_PENDING],
            since=today0,
            until=today0 + timedelta(days=30),
        )
        seen: set[int] = set()
        count = 0
        for req in targets:
            if req.client_vk_id in seen:
                continue
            seen.add(req.client_vk_id)
            self.notify.to_user(req.client_vk_id, f"💬 {text}")
            count += 1
        return [Reply(f"Отправлено {plural(count, 'человеку', 'человекам', 'человекам')} ✅")]
