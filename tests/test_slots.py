"""Проверка расчёта свободных окон."""

from __future__ import annotations

from datetime import datetime, timedelta

from bot.db import STATUS_CONFIRMED
from bot.slots import available_dates, day_slots, is_working_day, slot_is_free
from tests.helpers import build_config, make_harness

import tempfile
from pathlib import Path

from bot.db import Database


def _cfg(tmpdir: Path):
    return build_config(tmpdir / "t.sqlite3")


def test_working_day_and_hours():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))  # четверг
    try:
        thu = datetime(2026, 10, 22)
        sun = datetime(2026, 10, 25)
        assert is_working_day(h.cfg, h.db, thu) is True
        assert is_working_day(h.cfg, h.db, sun) is False, "воскресенье должно быть выходным"
        assert h.cfg.day_ranges(thu)[0][0].strftime("%H:%M") == "10:00"
    finally:
        h.cleanup()


def test_slots_respect_duration_and_buffer():
    h = make_harness(now=datetime(2026, 10, 22, 8, 0))
    try:
        thu = datetime(2026, 10, 22)
        # 60 мин при часах 10:00-19:00 и шаге 30 мин
        slots = day_slots(h.cfg, h.db, thu, 60, h.clock())
        assert slots[0] == thu.replace(hour=10), slots[:2]
        assert slots[-1] == thu.replace(hour=18), "последний сеанс должен заканчиваться к 19:00"

        # 40 мин — последний старт в 18:00 (18:40 < 19:00)
        slots40 = day_slots(h.cfg, h.db, thu, 40, h.clock())
        assert slots40[-1] == thu.replace(hour=18)

        # занятый сеанс 12:00-13:00 + буфер 15 мин вышибает 12:30..13:00
        h.db.create_request(
            client_vk_id=999, service_id="full", service_title="Общий массаж",
            starts_at=thu.replace(hour=12), duration=60, price=2500,
            client_name="Занятый", contact="+79000000000", now=h.clock(),
        )
        after = day_slots(h.cfg, h.db, thu, 60, h.clock())
        assert thu.replace(hour=12) not in after
        assert thu.replace(hour=11) not in after, "11:00 пересекается с 12:00 при 60 мин"
        assert thu.replace(hour=13, minute=30) in after, "после буфера окно должно появиться"
    finally:
        h.cleanup()


def test_min_notice_hides_soon_slots():
    h = make_harness(now=datetime(2026, 10, 22, 9, 30))  # min_notice = 120 мин
    try:
        thu = datetime(2026, 10, 22)
        slots = day_slots(h.cfg, h.db, thu, 40, h.clock())
        assert slots[0] == thu.replace(hour=11, minute=30), slots[:3]
        assert thu.replace(hour=10) not in slots
    finally:
        h.cleanup()


def test_day_off_and_blocked():
    h = make_harness(now=datetime(2026, 10, 22, 8, 0))
    try:
        thu = datetime(2026, 10, 22)
        h.db.add_day_off(thu, now=h.clock())
        assert day_slots(h.cfg, h.db, thu, 40, h.clock()) == []
        assert is_working_day(h.cfg, h.db, thu) is False

        h.db.remove_day_off(thu)
        assert day_slots(h.cfg, h.db, thu, 40, h.clock()), "после снятия выходного окна вернулись"

        # блокировка части дня убирает только пересекающиеся окна
        h.db.add_blocked(thu.replace(hour=10), thu.replace(hour=14), "обучение", now=h.clock())
        slots = day_slots(h.cfg, h.db, thu, 40, h.clock())
        assert thu.replace(hour=10) not in slots
        assert thu.replace(hour=13, minute=30) not in slots
        assert slots and slots[0] >= thu.replace(hour=14, minute=15), slots[:3]

        # блокировка всего дня оставляет день пустым
        h.db.add_blocked(thu.replace(hour=14), thu.replace(hour=19), "весь день", now=h.clock())
        assert day_slots(h.cfg, h.db, thu, 40, h.clock()) == []
    finally:
        h.cleanup()


def test_pending_blocks_slot_when_configured():
    h = make_harness(now=datetime(2026, 10, 22, 8, 0))
    try:
        thu = datetime(2026, 10, 22).replace(hour=15)
        h.db.create_request(
            client_vk_id=555, service_id="back", service_title="Массаж спины",
            starts_at=thu, duration=40, price=1500, client_name="А", contact="vk",
            now=h.clock(),
        )
        assert slot_is_free(h.cfg, h.db, thu, 40, h.clock()) is False
        assert slot_is_free(h.cfg, h.db, thu, 40, h.clock(), include_pending=False) is True

        h.cfg.block_on_pending = False
        assert slot_is_free(h.cfg, h.db, thu, 40, h.clock()) is True
    finally:
        h.cleanup()


def test_available_dates_skips_empty_days():
    h = make_harness(now=datetime(2026, 10, 22, 8, 0))
    try:
        dates = available_dates(h.cfg, h.db, 40, h.clock(), limit=5)
        assert dates, "должна быть хотя бы одна доступная дата"
        assert all(d.weekday() != 6 for d in dates), "воскресенье не должно предлагаться"
        # помечаем ближайшие 3 дня выходными
        for d in dates[:3]:
            h.db.add_day_off(d, now=h.clock())
        later = available_dates(h.cfg, h.db, 40, h.clock(), limit=3)
        assert later and later[0] >= dates[3]
    finally:
        h.cleanup()


def test_config_example_loads_and_validates():
    """config.example.toml должен читаться и проходить проверку структуры."""
    from bot.config import load_toml

    data = load_toml(Path(__file__).resolve().parent.parent / "config.example.toml")
    assert data["bot"]["timezone"] == "Europe/Moscow"
    assert len(data["services"]) >= 4
    assert data["reminders"]["client_before_hours"] == [24, 2]
    assert data["schedule"]["hours"]["sun"] == []


def test_config_validate_reports_missing_secrets():
    tmpdir = Path(tempfile.mkdtemp(prefix="cfg-test-"))
    try:
        cfg = build_config(tmpdir / "t.sqlite3")
        cfg.token = ""
        cfg.group_id = 0
        cfg.admin_ids = []
        problems = cfg.validate()
        assert any("VK_GROUP_TOKEN" in p for p in problems), problems
        assert any("VK_GROUP_ID" in p for p in problems), problems
        assert any("ADMIN_VK_IDS" in p for p in problems), problems

        cfg.token = "x"
        cfg.group_id = 1
        cfg.admin_ids = [1]
        assert cfg.validate() == [], cfg.validate()
    finally:
        import shutil

        shutil.rmtree(tmpdir, ignore_errors=True)


def test_texts_are_lenient():
    """Забыли плейсхолдер в config.toml — бот не падает."""
    h = make_harness()
    try:
        out = h.cfg.text("greeting", name="Иван")  # {master} не передали
        assert "Иван" in out
        assert "{master}" not in h.cfg.text("greeting", name="Иван", master="Елена")
        # неизвестный ключ -> пустая строка, без исключения
        assert h.cfg.text("no_such_key") == ""
    finally:
        h.cleanup()
