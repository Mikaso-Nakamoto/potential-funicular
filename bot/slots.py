"""Расчёт свободных окон под услугу.

Правила:
  * рабочие дни и интервалы часов берутся из config.toml ([schedule]);
  * шаг сетки — schedule.slot_minutes;
  * после сеанса закладывается schedule.buffer_minutes на подготовку;
  * слот должен начинаться не раньше, чем через schedule.min_notice_minutes;
  * занятые интервалы — подтверждённые записи, заявки (если
    schedule.block_on_pending = true) и блокировки мастера (/block);
  * даты-выходные (/off и day_off) исключаются целиком.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from .config import Config
from .db import Database


def day_start(date: datetime) -> datetime:
    return date.replace(hour=0, minute=0, second=0, microsecond=0)


def is_working_day(cfg: Config, db: Database, date: datetime) -> bool:
    if db.is_day_off(day_start(date)):
        return False
    return bool(cfg.day_ranges(date))


def booking_horizon(cfg: Config, now: datetime) -> list[datetime]:
    """Все даты, на которые в принципе можно записаться (без учёта занятости)."""
    today = day_start(now)
    return [today + timedelta(days=i) for i in range(cfg.max_days_ahead + 1)]


def overlaps(
    c_start: datetime, c_end: datetime, b_start: datetime, b_end: datetime, buffer: int
) -> bool:
    """Пересекаются ли интервалы с учётом буфера между сеансами (минуты)."""
    gap = timedelta(minutes=buffer)
    if c_start >= b_end + gap:
        return False
    if c_end + gap <= b_start:
        return False
    return True


def day_slots(
    cfg: Config,
    db: Database,
    date: datetime,
    duration: int,
    now: datetime,
    include_pending: bool | None = None,
) -> list[datetime]:
    """Свободные окна на дату под услугу длительностью `duration` минут."""
    if include_pending is None:
        include_pending = cfg.block_on_pending
    date = day_start(date)
    ranges = cfg.day_ranges(date)
    if not ranges or db.is_day_off(date):
        return []

    earliest = now + timedelta(minutes=cfg.min_notice_minutes)
    busy = db.busy_intervals(
        date - timedelta(days=1), date + timedelta(days=2), include_pending=include_pending
    )

    step = timedelta(minutes=cfg.slot_minutes)
    need = timedelta(minutes=duration)
    out: list[datetime] = []
    for start, end in ranges:
        cursor = start
        while cursor + need <= end:
            if cursor >= earliest and not any(
                overlaps(cursor, cursor + need, b0, b1, cfg.buffer_minutes) for b0, b1 in busy
            ):
                out.append(cursor)
            cursor += step
    out.sort()
    return out


def slot_is_free(
    cfg: Config,
    db: Database,
    starts_at: datetime,
    duration: int,
    now: datetime,
    include_pending: bool | None = None,
) -> bool:
    """Точечная проверка: можно ли поставить сеанс ровно на это время."""
    if starts_at < now + timedelta(minutes=cfg.min_notice_minutes):
        return False
    if not is_working_day(cfg, db, starts_at):
        return False
    ranges = cfg.day_ranges(starts_at)
    ends_at = starts_at + timedelta(minutes=duration)
    if not any(r0 <= starts_at and ends_at <= r1 for r0, r1 in ranges):
        return False
    busy = db.busy_intervals(
        starts_at - timedelta(days=1), starts_at + timedelta(days=2),
        include_pending=cfg.block_on_pending if include_pending is None else include_pending,
    )
    return not any(
        overlaps(starts_at, ends_at, b0, b1, cfg.buffer_minutes) for b0, b1 in busy
    )


def available_dates(
    cfg: Config,
    db: Database,
    duration: int,
    now: datetime,
    limit: int | None = None,
) -> list[datetime]:
    """Даты, на которые есть хотя бы одно свободное окно."""
    out = []
    for date in booking_horizon(cfg, now):
        if day_slots(cfg, db, date, duration, now):
            out.append(date)
            if limit and len(out) >= limit:
                break
    return out


def nearest_slot(
    cfg: Config, db: Database, duration: int, now: datetime
) -> datetime | None:
    dates = available_dates(cfg, db, duration, now, limit=1)
    if not dates:
        return None
    slots = day_slots(cfg, db, dates[0], duration, now)
    return slots[0] if slots else None


def work_hours_text(cfg: Config) -> str:
    """Человекочитаемое расписание для раздела «О мастере»."""
    names = {
        "mon": "Пн",
        "tue": "Вт",
        "wed": "Ср",
        "thu": "Чт",
        "fri": "Пт",
        "sat": "Сб",
        "sun": "Вс",
    }
    lines = []
    for key in ("mon", "tue", "wed", "thu", "fri", "sat", "sun"):
        ranges = cfg.hours.get(key) or []
        if key not in cfg.work_days or not ranges:
            lines.append(f"{names[key]}: выходной")
        else:
            lines.append(f"{names[key]}: {', '.join(ranges)}")
    return "\n".join(lines)
