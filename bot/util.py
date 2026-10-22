"""Мелкие помощники: время, русские даты, телефоны, шаблоны текстов."""

from __future__ import annotations

import re
from datetime import datetime, timedelta
from string import Formatter
from zoneinfo import ZoneInfo

WEEKDAY_SHORT = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
WEEKDAY_LONG = [
    "понедельник",
    "вторник",
    "среда",
    "четверг",
    "пятница",
    "суббота",
    "воскресенье",
]
WEEKDAY_KEY = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
MONTH_GEN = [
    "января",
    "февраля",
    "марта",
    "апреля",
    "мая",
    "июня",
    "июля",
    "августа",
    "сентября",
    "октября",
    "ноября",
    "декабря",
]

DT_FMT = "%Y-%m-%dT%H:%M:%S"
DATE_FMT = "%Y-%m-%d"


# --------------------------------------------------------------------------- #
# время
# --------------------------------------------------------------------------- #
def get_tz(name: str) -> ZoneInfo:
    """Часовой пояс по имени с понятной ошибкой, если tzdata не установлен."""
    try:
        return ZoneInfo(name)
    except Exception as exc:  # pragma: no cover - зависит от системы
        raise RuntimeError(
            f"Не удалось загрузить часовой пояс '{name}'. "
            "Установите системные данные времени: sudo apt install tzdata"
        ) from exc


def now(tz: ZoneInfo) -> datetime:
    """Текущее локальное время (наивный datetime в часовом поясе бота)."""
    return datetime.now(tz).replace(tzinfo=None)


def to_iso(dt: datetime) -> str:
    return dt.strftime(DT_FMT)


def from_iso(value: str) -> datetime:
    value = (value or "").strip()
    for fmt in (DT_FMT, "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", DATE_FMT):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            continue
    raise ValueError(f"Не понимаю дату/время: {value!r}")


def parse_date(value: str) -> datetime:
    """Дата вида 2026-10-25 (или 25.10.2026) -> datetime в 00:00."""
    value = (value or "").strip()
    m = re.fullmatch(r"(\d{1,2})[./](\d{1,2})[./](\d{4})", value)
    if m:
        d, mo, y = (int(x) for x in m.groups())
        return datetime(y, mo, d)
    return from_iso(value)


def parse_hhmm(value: str) -> tuple[int, int]:
    m = re.fullmatch(r"\s*(\d{1,2})[:.](\d{2})\s*", value or "")
    if not m:
        raise ValueError(f"Не понимаю время {value!r}, нужен формат ЧЧ:ММ")
    hh, mm = int(m.group(1)), int(m.group(2))
    if hh > 23 or mm > 59:
        raise ValueError(f"Неверное время {value!r}")
    return hh, mm


def parse_range(value: str) -> tuple[datetime, datetime]:
    """'10:00-14:00' -> (time(10,0), time(14,0)) как datetime(1900,1,1,...)."""
    parts = re.split(r"\s*[-–—]\s*", (value or "").strip())
    if len(parts) != 2:
        raise ValueError(f"Не понимаю интервал {value!r}, нужно '10:00-14:00'")
    base = datetime(1900, 1, 1)
    out = []
    for part in parts:
        hh, mm = parse_hhmm(part)
        out.append(base.replace(hour=hh, minute=mm))
    if out[1] <= out[0]:
        raise ValueError(f"Конец интервала должен быть позже начала: {value!r}")
    return out[0], out[1]


# --------------------------------------------------------------------------- #
# русский вывод
# --------------------------------------------------------------------------- #
def plural(n: int, one: str, few: str, many: str) -> str:
    n10, n100 = n % 10, n % 100
    if n10 == 1 and n100 != 11:
        form = one
    elif 2 <= n10 <= 4 and not (12 <= n100 <= 14):
        form = few
    else:
        form = many
    return f"{n} {form}"


def weekday_key(dt: datetime) -> str:
    return WEEKDAY_KEY[dt.weekday()]


def format_date_full(dt: datetime) -> str:
    """сб, 25 октября"""
    return f"{WEEKDAY_SHORT[dt.weekday()]}, {dt.day} {MONTH_GEN[dt.month - 1]}"


def format_date_long(dt: datetime) -> str:
    """суббота, 25 октября 2026"""
    return (
        f"{WEEKDAY_LONG[dt.weekday()]}, {dt.day} {MONTH_GEN[dt.month - 1]} {dt.year}"
    )


def format_time(dt: datetime) -> str:
    return dt.strftime("%H:%M")


def format_dt(dt: datetime) -> str:
    """25.10 в 14:30"""
    return f"{dt.strftime('%d.%m')} в {format_time(dt)}"


def format_dt_full(dt: datetime) -> str:
    """сб, 25 октября в 14:30"""
    return f"{format_date_full(dt)} в {format_time(dt)}"


def human_delta(td: timedelta) -> str:
    """'через 2 ч 15 мин' / '3 дня' — грубо, но по-русски."""
    total_min = int(td.total_seconds() // 60)
    if total_min < 0:
        total_min = 0
    days, rest = divmod(total_min, 1440)
    hours, minutes = divmod(rest, 60)
    parts = []
    if days:
        parts.append(plural(days, "день", "дня", "дней"))
    if hours:
        parts.append(plural(hours, "час", "часа", "часов"))
    if minutes and not days:
        parts.append(plural(minutes, "минута", "минуты", "минут"))
    return " ".join(parts) if parts else "меньше минуты"


# --------------------------------------------------------------------------- #
# телефон / контакты
# --------------------------------------------------------------------------- #
def normalize_phone(raw: str) -> str | None:
    """Возвращает нормализованный номер или None, если это не телефон."""
    digits = re.sub(r"\D", "", raw or "")
    if not digits:
        return None
    if len(digits) == 11 and digits[0] == "8":
        digits = "7" + digits[1:]
    if len(digits) == 10 and digits[0] == "9":  # частый случай: 9001234567
        digits = "7" + digits
    if len(digits) < 10 or len(digits) > 15:
        return None
    if len(digits) == 11 and digits[0] == "7":
        return f"+7 ({digits[1:4]}) {digits[4:7]}-{digits[7:9]}-{digits[9:]}"
    return "+" + digits


def phone_digits(raw: str) -> str:
    return re.sub(r"\D", "", raw or "")


def looks_like_phone(raw: str) -> bool:
    return normalize_phone(raw) is not None


def vk_user_link(vk_id: int) -> str:
    return f"https://vk.com/id{vk_id}"


def vk_dialog_link(vk_id: int) -> str:
    """Ссылка, которая сразу открывает диалог с человеком."""
    return f"https://vk.com/im?sel={vk_id}"


# --------------------------------------------------------------------------- #
# шаблоны
# --------------------------------------------------------------------------- #
class _LenientFormatter(Formatter):
    """Неизвестный {ключ} остаётся как есть — конфиг правит человек."""

    def get_value(self, key, args, kwargs):  # noqa: D102
        if isinstance(key, str):
            return kwargs.get(key, "{" + key + "}")
        return Formatter.get_value(self, key, args, kwargs)


_LENIENT = _LenientFormatter()


def render(template: str, **ctx) -> str:
    """Безопасный str.format: не падает на лишних/забытых плейсхолдерах."""
    if not template:
        return ""
    try:
        return _LENIENT.vformat(template, (), ctx)
    except (ValueError, KeyError, IndexError):
        return template


def truncate(text: str, limit: int) -> str:
    text = (text or "").strip()
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)].rstrip() + "…"


def chunked(items: list, size: int) -> list[list]:
    return [items[i : i + size] for i in range(0, len(items), size)]
