"""Клавиатуры ВКонтакте.

Ограничения ВК, которые здесь учтены:
  * обычная клавиатура: до 10 кнопок в ряду, до 10 рядов;
  * inline (callback) клавиатура: до 6 рядов;
  * подпись кнопки: до 40 символов;
  * payload: компактный JSON вида {"c": "<команда>", "v": "<значение>"}.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Iterable, Sequence

from .config import Config, Service
from .db import Request
from .util import chunked, format_date_full, format_dt, truncate

MAX_LABEL = 40
MAX_ROWS = 10
MAX_INLINE_ROWS = 6
BUTTONS_PER_ROW = 4

# цвета кнопок ВК
PRIMARY = "primary"
SECONDARY = "secondary"
POSITIVE = "positive"
NEGATIVE = "negative"


def _payload(cmd: str, value: Any = None) -> str:
    import json

    data: dict[str, Any] = {"c": cmd}
    if value is not None:
        data["v"] = value
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"))


def text_button(label: str, cmd: str | None = None, value: Any = None,
                color: str = SECONDARY, payload_raw: str | None = None) -> dict:
    button: dict[str, Any] = {
        "action": {
            "type": "text",
            "label": truncate(label, MAX_LABEL),
        }
    }
    payload = payload_raw if payload_raw is not None else (_payload(cmd, value) if cmd else None)
    if payload:
        button["action"]["payload"] = payload
    if color:
        button["color"] = color
    return button


def callback_button(label: str, cmd: str, value: Any = None, color: str = SECONDARY) -> dict:
    return {
        "action": {
            "type": "callback",
            "label": truncate(label, MAX_LABEL),
            "payload": _payload(cmd, value),
        },
        "color": color,
    }


def keyboard(rows: Sequence[Sequence[dict]], one_time: bool = False, inline: bool = False) -> dict:
    """Собирает клавиатуру, обрезая лишние ряды под лимиты ВК."""
    limit = MAX_INLINE_ROWS if inline else MAX_ROWS
    clean = [[b for b in row if b] for row in rows]
    clean = [row for row in clean if row][:limit]
    kb: dict[str, Any] = {"buttons": clean}
    if inline:
        kb["inline"] = True
    else:
        kb["one_time"] = one_time
    return kb


# --------------------------------------------------------------------------- #
# клиентские клавиатуры
# --------------------------------------------------------------------------- #
def main_menu(cfg: Config, is_admin: bool = False) -> dict:
    rows = [
        [text_button("📅 Записаться", "book", color=PRIMARY)],
        [
            text_button("📋 Мои записи", "mine"),
            text_button("💰 Услуги и цены", "prices"),
        ],
        [
            text_button("📞 Связаться", "contact"),
            text_button("ℹ️ О мастере", "about"),
        ],
    ]
    if is_admin:
        rows.append([text_button("🛠 Панель мастера", "admin", color=POSITIVE)])
    return keyboard(rows, one_time=False)


def cancel_row(extra: Iterable[dict] = ()) -> list[dict]:
    return [
        *extra,
        text_button("🔙 Меню", "menu"),
        text_button("❌ Отмена", "cancel", color=NEGATIVE),
    ]


def services_keyboard(cfg: Config) -> dict:
    rows = []
    for svc in cfg.active_services():
        rows.append([text_button(svc.title, "svc", svc.id, color=PRIMARY)])
    rows.append(cancel_row())
    return keyboard(rows, one_time=True)


def dates_keyboard(dates: Sequence[datetime], page: int, pages: int) -> dict:
    rows = [
        [text_button(format_date_full(d), "date", d.strftime("%Y-%m-%d"))]
        for d in dates
    ]
    nav: list[dict] = []
    if page > 0:
        nav.append(text_button("⬅️ Раньше", "dates", page - 1))
    if page + 1 < pages:
        nav.append(text_button("Позже ➡️", "dates", page + 1))
    nav.append(text_button("⬅️ Услуги", "back_services"))
    nav.append(text_button("❌ Отмена", "cancel", color=NEGATIVE))
    rows.append(nav)
    return keyboard(rows, one_time=True)


def slots_keyboard(slots: Sequence[datetime], date: datetime) -> dict:
    labels = [text_button(s.strftime("%H:%M"), "time", s.strftime("%Y-%m-%dT%H:%M")) for s in slots]
    rows = chunked(labels, BUTTONS_PER_ROW)
    rows.append(
        [
            text_button("⬅️ Другая дата", "date_back", date.strftime("%Y-%m-%d")),
            text_button("❌ Отмена", "cancel", color=NEGATIVE),
        ]
    )
    return keyboard(rows, one_time=True)


def name_keyboard(name: str) -> dict:
    rows = [[text_button("✅ Верно", "name_ok", color=POSITIVE)]]
    rows.append(cancel_row())
    return keyboard(rows, one_time=True)


def contact_keyboard() -> dict:
    rows = [[text_button("🔵 Через ВКонтакте", "contact_vk", color=PRIMARY)]]
    rows.append(cancel_row())
    return keyboard(rows, one_time=True)


def comment_keyboard() -> dict:
    rows = [[text_button("Без комментария", "no_comment")]]
    rows.append(cancel_row())
    return keyboard(rows, one_time=True)


def summary_keyboard() -> dict:
    rows = [
        [text_button("✅ Отправить заявку", "submit", color=POSITIVE)],
        [
            text_button("⬅️ Изменить время", "edit_time"),
            text_button("❌ Отмена", "cancel", color=NEGATIVE),
        ],
    ]
    return keyboard(rows, one_time=True)


def my_bookings_keyboard(requests: Sequence[Request]) -> dict:
    rows = []
    for req in requests:
        mark = "⏳" if req.status == "pending" else "✅"
        rows.append(
            [
                text_button(
                    f"❌ {mark} №{req.id} {format_dt(req.starts_at)}",
                    "cancel_req",
                    req.id,
                    color=NEGATIVE,
                )
            ]
        )
    rows.append([text_button("📅 Записаться", "book", color=PRIMARY),
                 text_button("🔙 Меню", "menu")])
    return keyboard(rows, one_time=False)


def after_request_keyboard() -> dict:
    return keyboard(
        [
            [text_button("📋 Мои записи", "mine")],
            [text_button("📞 Связаться с мастером", "contact")],
            [text_button("🔙 Меню", "menu")],
        ],
        one_time=False,
    )


def service_info_keyboard(svc: Service) -> dict:
    return keyboard(
        [
            [text_button("📅 Записаться на это", "svc", svc.id, color=PRIMARY)],
            [text_button("⬅️ Все услуги", "back_services"),
             text_button("❌ Отмена", "cancel", color=NEGATIVE)],
        ],
        one_time=True,
    )


# --------------------------------------------------------------------------- #
# клавиатуры мастера
# --------------------------------------------------------------------------- #
def admin_menu(cfg: Config) -> dict:
    return keyboard(
        [
            [text_button("🔔 Заявки", "adm_pending", color=PRIMARY)],
            [text_button("📅 Сегодня", "adm_today"),
             text_button("🗓 Неделя", "adm_week")],
            [text_button("📊 Статистика", "adm_stats"),
             text_button("🚫 Выходной", "adm_off")],
            [text_button("📞 Контакты", "adm_contacts"),
             text_button("❓ Помощь", "adm_help")],
            [text_button("🔙 Общее меню", "menu")],
        ],
        one_time=False,
    )


def admin_request_keyboard(cfg: Config, req: Request) -> dict:
    """Кнопки «Подтвердить» / «Отклонить» под уведомлением о новой заявке."""
    if cfg.use_callback_buttons:
        return keyboard(
            [
                [
                    callback_button("✅ Подтвердить", "ok", req.id, color=POSITIVE),
                    callback_button("🚫 Отклонить", "no", req.id, color=NEGATIVE),
                ],
                [callback_button("🕒 Перенести", "reschedule", req.id)],
            ],
            inline=True,
        )
    return keyboard(
        [
            [text_button(f"✅ Подтвердить №{req.id}", "ok", req.id, color=POSITIVE)],
            [text_button(f"🚫 Отклонить №{req.id}", "no", req.id, color=NEGATIVE)],
            [text_button(f"🕒 Перенести №{req.id}", "reschedule", req.id)],
        ],
        one_time=True,
    )


def admin_requests_list(cfg: Config, requests: Sequence[Request]) -> dict | None:
    rows = []
    for req in requests[:8]:
        if cfg.use_callback_buttons:
            continue
        rows.append([text_button(f"№{req.id} {format_dt(req.starts_at)}", "adm_open", req.id)])
    if not rows:
        return None
    rows.append([text_button("🔙 Панель", "admin")])
    return keyboard(rows, one_time=False)


def admin_reschedule_keyboard(cfg: Config, slots: Sequence[datetime]) -> dict:
    rows = [
        chunk
        for chunk in chunked(
            [text_button(s.strftime("%d.%m %H:%M"), "rs_slot", s.strftime("%Y-%m-%dT%H:%M"))
             for s in slots],
            3,
        )
    ]
    rows.append([text_button("❌ Отмена", "cancel", color=NEGATIVE)])
    return keyboard(rows, one_time=True)


def request_card_lines(req: Request) -> str:
    return (
        f"№{req.id} · {req.service_title}\n"
        f"📅 {format_dt(req.starts_at)} ({req.duration} мин)\n"
        f"👤 {req.client_name}\n📱 {req.contact}"
    )
