"""Воркер: напоминания, истечение заявок, дайджест, повторы отправки."""

from __future__ import annotations

from datetime import datetime, timedelta

from bot.db import STATUS_COMPLETED, STATUS_CONFIRMED, STATUS_EXPIRED, STATUS_PENDING
from tests.helpers import make_harness, walk_booking

CLIENT = 222
ADMIN = 111


def test_expire_pending_after_ttl():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h)
        assert h.db.get_request(rid).status == STATUS_PENDING

        h.sender.clear()
        h.clock.advance(hours=24, minutes=5)  # pending_ttl_hours = 24
        h.tick()

        assert h.db.get_request(rid).status == STATUS_EXPIRED
        assert "осталась без ответа" in h.client_text(), h.client_text()
    finally:
        h.cleanup()


def test_morning_digest_once_per_day():
    h = make_harness(now=datetime(2026, 10, 22, 8, 0))
    try:
        rid = walk_booking(h)
        h.press(ADMIN, "ok", rid)
        h.sender.clear()

        # до 09:00 дайджеста нет
        h.clock.set(datetime(2026, 10, 22, 8, 30))
        h.tick()
        assert not [m for m in h.sender.messages_for(ADMIN) if "Записи на" in m.text]

        # в 09:00 — приходит список на день
        h.clock.set(datetime(2026, 10, 22, 9, 0, 30))
        h.tick()
        digest = [m for m in h.sender.messages_for(ADMIN) if "Записи на" in m.text]
        assert digest, [m.text for m in h.sender.messages_for(ADMIN)]
        assert "Иван Петров" in digest[0].text

        # повторно в тот же день не дублируется
        h.sender.clear()
        h.clock.set(datetime(2026, 10, 22, 15, 0))
        h.tick()
        assert not [m for m in h.sender.messages_for(ADMIN) if "Записи на" in m.text]
    finally:
        h.cleanup()


def test_digest_when_no_bookings():
    h = make_harness(now=datetime(2026, 10, 22, 8, 0))
    try:
        h.clock.set(datetime(2026, 10, 22, 9, 5))
        h.tick()
        assert "свободный день" in h.admin_text(), h.admin_text()
    finally:
        h.cleanup()


def test_digest_can_be_disabled():
    h = make_harness(now=datetime(2026, 10, 22, 8, 0), digest_enabled=False)
    try:
        h.clock.set(datetime(2026, 10, 22, 9, 5))
        h.tick()
        assert not [m for m in h.sender.messages_for(ADMIN)], h.sender.sent
    finally:
        h.cleanup()


def test_reminders_disabled_by_config():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0), client_before_hours=[])
    try:
        rid = walk_booking(h)
        h.press(ADMIN, "ok", rid)
        rows = h.db._query(
            "SELECT kind FROM reminders WHERE request_id = ? AND kind LIKE 'client%'", (rid,)
        )
        assert rows == [], rows

        req = h.db.get_request(rid)
        h.sender.clear()
        h.clock.set(req.starts_at - timedelta(hours=1))
        h.tick()
        assert not [m for m in h.sender.messages_for(CLIENT) if "Напоминание" in m.text]
    finally:
        h.cleanup()


def test_completed_requests_not_reminded():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h)
        h.press(ADMIN, "ok", rid)
        req = h.db.get_request(rid)

        # запись отменили — напоминания не должны уйти
        h.db.set_status(rid, "cancelled", now=h.clock(), cancelled_by="admin")
        h.sender.clear()
        h.clock.set(req.starts_at - timedelta(hours=24, minutes=5))
        h.tick()
        assert not [m for m in h.sender.messages_for(CLIENT) if "Напоминание" in m.text]
    finally:
        h.cleanup()


def test_outbox_survives_restart():
    """Уведомление мастеру лежит в базе: бот перезапустили — оно всё равно уйдёт."""
    from bot.handlers import Bot
    from bot.scheduler import Scheduler
    from tests.helpers import FakeSender, _date_value_from_label

    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        # доходим до последнего шага обычным способом
        h.press(CLIENT, "book")
        h.press(CLIENT, "svc", "back")
        labels = [label for label in h.client_labels() if "," in label]
        date_value = _date_value_from_label(labels[0], h)
        h.press(CLIENT, "date", date_value)
        slot = next(label for label in h.client_labels() if ":" in label)
        h.press(CLIENT, "time", f"{date_value}T{slot}")
        h.press(CLIENT, "name_ok")
        h.say(CLIENT, "+7 900 123-45-67")
        h.press(CLIENT, "no_comment")
        assert any("Отправить заявку" in label for label in h.client_labels())

        # пропал интернет — отправка падает
        broken = FakeSender(clock=h.clock, names=h.sender.names)
        broken.fail_next = 10
        h.bot.sender = broken
        h.press(CLIENT, "submit")
        assert broken.sent == [], "при обрыве связи сообщения не должны уходить"
        assert h.db.outbox_pending_count() >= 2, "ответ клиенту и уведомление мастеру — в очереди"
        assert h.db.list_requests(statuses=["pending"]), "заявка создаётся даже без сети"

        # связь вернулась, бот «перезапустили»
        sender2 = FakeSender(clock=h.clock, names=h.sender.names)
        h.sender = sender2
        h.bot = Bot(h.cfg, h.db, sender2, now_fn=h.clock)
        h.scheduler = Scheduler(h.cfg, h.db, h.bot, now_fn=h.clock)
        h.clock.advance(minutes=1)
        h.tick()

        assert h.db.outbox_pending_count() == 0
        assert "ЗАЯВКА" in " ".join(m.text for m in sender2.messages_for(ADMIN)), \
            [m.text for m in sender2.messages_for(ADMIN)]
    finally:
        h.cleanup()


def test_due_reminders_return_correct_request_id():
    """Регрессия: раньше `q.*` в JOIN перекрывал id, и заявка собиралась с id напоминания."""
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h, date_index=1)
        h.press(ADMIN, "ok", rid)
        req = h.db.get_request(rid)

        h.clock.set(req.starts_at + timedelta(minutes=1))
        due = h.db.due_reminders(h.clock())
        assert due, "напоминания должны были стать срочными"
        for reminder, request in due:
            assert request.id == rid, f"ожиджали заявку {rid}, получили {request.id}"
            assert reminder.request_id == rid
    finally:
        h.cleanup()


def test_several_due_reminders_send_once():
    """Бот простаивал: накопились напоминания за 24 ч и за 2 ч — спамить не должен."""
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h, date_index=1)
        h.press(ADMIN, "ok", rid)
        req = h.db.get_request(rid)

        # перематываем сразу за оба момента напоминаний
        h.sender.clear()
        h.clock.set(req.starts_at - timedelta(minutes=30))
        h.tick()

        client_reminders = [m for m in h.sender.messages_for(CLIENT) if "Напоминание" in m.text]
        admin_reminders = [m for m in h.sender.messages_for(ADMIN) if "Напоминание" in m.text]
        assert len(client_reminders) == 1, [m.text for m in client_reminders]
        assert len(admin_reminders) == 1, [m.text for m in admin_reminders]

        # все напоминания помечены отправленными
        left = h.db._query("SELECT COUNT(*) c FROM reminders WHERE sent_at IS NULL")[0]["c"]
        assert left == 0, left
    finally:
        h.cleanup()


def test_tick_is_idempotent_and_safe():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        for _ in range(3):
            result = h.tick()
            assert isinstance(result, dict)
        assert h.db.outbox_pending_count() == 0
    finally:
        h.cleanup()
