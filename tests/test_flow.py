"""Полный сценарий записи: клиент → заявка → подтверждение мастера → напоминания."""

from __future__ import annotations

from datetime import datetime, timedelta

from bot.db import STATUS_CANCELLED, STATUS_CONFIRMED, STATUS_PENDING, STATUS_REJECTED
from bot.slots import day_slots
from bot.util import format_dt_full
from tests.helpers import make_harness, walk_booking

CLIENT = 222
ADMIN = 111


def test_greeting_and_menu():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.say(CLIENT, "Привет!")
        text = h.client_text()
        assert "Иван" in text, text          # имя из users.get
        assert "Елена" in text, text         # имя мастера из контактов
        labels = h.client_labels()
        assert "📅 Записаться" in labels, labels
        assert "📞 Связаться" in labels, labels
        assert "🛠 Панель мастера" not in labels, "клиенту нельзя показывать панель"
    finally:
        h.cleanup()


def test_contacts_are_visible():
    """Главное требование: живой контакт мастера всегда под рукой."""
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.press(CLIENT, "contact")
        text = h.client_text()
        assert "+7 900 000-00-00" in text, text
        assert "wa.me" in text, text
        assert "vk.com/id777" in text, text
        assert "Советская" in text, text
    finally:
        h.cleanup()


def test_prices_list():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.press(CLIENT, "prices")
        text = h.client_text()
        assert "Массаж спины" in text and "1500" in text, text
        assert "Общий массаж" in text and "2500" in text, text
        assert "Скрытая услуга" not in text, "active=false не должна показываться"
    finally:
        h.cleanup()


def test_full_booking_happy_path():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        # date_index=1 — запись на следующий рабочий день, чтобы напоминания были в будущем
        request_id = walk_booking(h, service_id="back", date_index=1, comment="Болит шея")

        # 1. клиент получил подтверждение отправки заявки + контакты
        text = h.client_text()
        assert "Заявка отправлена" in text, text
        assert "+7 900 000-00-00" in text, "в ответе должен быть живой контакт"

        # 2. мастеру пришло уведомление с кнопками
        admin_text = h.admin_text()
        assert f"ЗАЯВКА №{request_id}" in admin_text, admin_text
        assert "Массаж спины" in admin_text
        assert "Иван Петров" in admin_text
        assert "+7 (900) 123-45-67" in admin_text, admin_text
        assert "Болит шея" in admin_text
        assert f"vk.com/im?sel={CLIENT}" in admin_text, "мастеру нужна ссылка на диалог"
        labels = h.admin_labels()
        assert "✅ Подтвердить" in labels and "🚫 Отклонить" in labels, labels

        # 3. статус — ждёт подтверждения
        req = h.db.get_request(request_id)
        assert req.status == STATUS_PENDING
        assert req.duration == 40 and req.price == 1500

        # 4. мастер подтверждает
        h.sender.clear()
        h.press(ADMIN, "ok", request_id)
        assert h.db.get_request(request_id).status == STATUS_CONFIRMED
        assert "Запись подтверждена" in h.client_text(), h.client_text()
        assert "Советская" in h.client_text(), "адрес должен быть в подтверждении"
        assert any("подтверждена" in e["text"].lower() for e in h.sender.events), h.sender.events

        # 5. напоминания запланированы (24 ч и 2 ч)
        rows = h.db._query("SELECT kind, send_at FROM reminders WHERE request_id = ? ORDER BY send_at",
                           (request_id,))
        kinds = [r["kind"] for r in rows]
        assert "client_24h" in kinds and "client_2h" in kinds, kinds
        assert "admin_24h" in kinds, kinds
    finally:
        h.cleanup()


def test_reminders_are_delivered():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        # запись на следующий доступный день — чтобы напоминание за 24 ч было в будущем
        rid = walk_booking(h, date_index=1)
        h.press(ADMIN, "ok", rid)
        req = h.db.get_request(rid)
        h.sender.clear()

        # за сутки до сеанса
        h.clock.set(req.starts_at - timedelta(hours=24) + timedelta(minutes=1))
        h.tick()
        assert "Напоминание" in h.client_text(), h.client_text()

        # за 2 часа
        h.sender.clear()
        h.clock.set(req.starts_at - timedelta(hours=2) + timedelta(minutes=1))
        h.tick()
        assert "Напоминание" in h.client_text(), h.client_text()

        # повторно не дублируем
        h.sender.clear()
        h.clock.set(req.starts_at - timedelta(minutes=30))
        h.tick()
        assert not [m for m in h.sender.messages_for(CLIENT) if "Напоминание" in m.text]

        # после сеанса запись становится завершённой
        h.clock.set(req.ends_at + timedelta(minutes=5))
        h.tick()
        assert h.db.get_request(rid).status == "completed"
    finally:
        h.cleanup()


def test_reject_frees_slot_and_notifies_client():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h, service_id="back")
        req = h.db.get_request(rid)
        h.sender.clear()
        h.press(ADMIN, "no", rid)

        assert h.db.get_request(rid).status == STATUS_REJECTED
        text = h.client_text()
        assert "не может подтвердить" in text, text
        assert "Записаться" in " ".join(h.client_labels())

        # слот снова свободен
        from bot.slots import slot_is_free

        assert slot_is_free(h.cfg, h.db, req.starts_at, 40, h.clock()) is True
        assert h.db._query("SELECT COUNT(*) c FROM reminders WHERE request_id = ?", (rid,))[0]["c"] == 0
    finally:
        h.cleanup()


def test_second_client_cannot_take_busy_slot():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h, service_id="back")
        taken = h.db.get_request(rid).starts_at

        other = 333
        h.sender.names[other] = ("Ольга", "Смирнова")
        h.press(other, "book")
        h.press(other, "svc", "back")
        # в списке кнопок занятого времени быть не должно
        labels = " ".join(h.sender.labels(other))
        assert taken.strftime("%H:%M") not in labels, f"занятый слот показан: {labels}"
    finally:
        h.cleanup()


def test_slot_taken_race_is_handled():
    """Два человека жмут одно и то же время — второй получает вежливый отказ."""
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.press(CLIENT, "book")
        h.press(CLIENT, "svc", "back")
        state, data = h.db.get_state(CLIENT)
        from tests.helpers import _date_value_from_label

        date_label = next(l for l in h.client_labels() if "," in l and "Услуги" not in l)
        date_value = _date_value_from_label(date_label, h)
        h.press(CLIENT, "date", date_value)
        slot_label = next(l for l in h.client_labels() if ":" in l)
        slot_value = f"{date_value}T{slot_label}"

        # кто-то другой успел занять это окно
        starts = datetime.strptime(slot_value, "%Y-%m-%dT%H:%M")
        h.db.create_request(
            client_vk_id=999, service_id="back", service_title="Массаж спины",
            starts_at=starts, duration=40, price=1500, client_name="Другой",
            contact="vk", now=h.clock(),
        )
        h.press(CLIENT, "time", slot_value)
        text = h.client_text()
        assert "заняли" in text or "Нет свободных" in text or "Выберите" in text, text
        assert h.db.count_active(CLIENT) == 0, "заявка не должна была создаться"
    finally:
        h.cleanup()


def test_my_bookings_and_client_cancel():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h)
        h.press(CLIENT, "mine")
        assert f"№{rid}" in h.client_text(), h.client_text()
        assert any(f"№{rid}" in l for l in h.client_labels()), h.client_labels()

        h.sender.clear()
        h.press(CLIENT, "cancel_req", rid)
        assert h.db.get_request(rid).status == STATUS_CANCELLED
        assert "отменена" in h.client_text(), h.client_text()
        assert "отменил" in h.admin_text(), "мастер должен узнать об отмене"
    finally:
        h.cleanup()


def test_late_cancel_requires_master():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h)
        h.press(ADMIN, "ok", rid)
        req = h.db.get_request(rid)
        h.clock.set(req.starts_at - timedelta(hours=1))  # позже лимита в 3 часа
        h.sender.clear()
        h.press(CLIENT, "cancel_req", rid)
        assert h.db.get_request(rid).status == STATUS_CONFIRMED, "поздно отменять самому"
        assert "+7 900 000-00-00" in h.client_text(), h.client_text()
    finally:
        h.cleanup()


def test_max_active_requests_limit():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0), max_active_requests=1)
    try:
        walk_booking(h)
        h.sender.clear()
        h.press(CLIENT, "book")
        assert "уже есть активные" in h.client_text(), h.client_text()
    finally:
        h.cleanup()


def test_name_phone_validation():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.press(CLIENT, "book")
        h.press(CLIENT, "svc", "back")
        from tests.helpers import _date_value_from_label

        date_label = next(l for l in h.client_labels() if "," in l and "Услуги" not in l)
        h.press(CLIENT, "date", _date_value_from_label(date_label, h))
        slot_label = next(l for l in h.client_labels() if ":" in l)
        state, data = h.db.get_state(CLIENT)
        h.press(CLIENT, "time", f"{data['date']}T{slot_label}")

        # имя
        assert h.db.get_state(CLIENT)[0] == "ask_name"
        h.say(CLIENT, "Я")
        assert "напишите имя" in h.client_text(), h.client_text()
        h.say(CLIENT, "Мария")
        assert h.db.get_state(CLIENT)[0] == "ask_contact"

        # телефон
        h.say(CLIENT, "привет")
        assert "Не похоже на номер" in h.client_text(), h.client_text()
        h.say(CLIENT, "89001234567")
        state, data = h.db.get_state(CLIENT)
        assert data.get("contact") == "+7 (900) 123-45-67", data
        assert h.db.get_client(CLIENT)["phone"] == "+7 (900) 123-45-67"
    finally:
        h.cleanup()


def test_contact_via_vk_option():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h, phone=None)
        req = h.db.get_request(rid)
        assert f"vk.com/id{CLIENT}" in req.contact, req.contact
        assert f"vk.com/id{CLIENT}" in h.admin_text(), "мастер должен видеть ссылку на профиль"
    finally:
        h.cleanup()


def test_cancel_resets_flow():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.press(CLIENT, "book")
        h.press(CLIENT, "svc", "back")
        assert h.db.get_state(CLIENT)[0] == "pick_date"
        h.press(CLIENT, "cancel")
        assert h.db.get_state(CLIENT)[0] == "idle"
        assert "📅 Записаться" in h.client_labels()
    finally:
        h.cleanup()


def test_unknown_text_is_polite():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.say(CLIENT, "а вы делаете баночный массаж?")
        text = h.client_text()
        assert "Связаться" in " ".join(h.client_labels()) or "меню" in text.lower(), text
    finally:
        h.cleanup()


def test_admin_panel_and_commands():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h)

        h.sender.clear()
        h.say(ADMIN, "/pending")
        assert f"№{rid}" in h.admin_text(), h.admin_text()

        h.sender.clear()
        h.say(ADMIN, "/help")
        assert "/today" in h.admin_text() and "/off" in h.admin_text()

        h.sender.clear()
        h.say(ADMIN, "/stats")
        assert "ждут ответа" in h.admin_text(), h.admin_text()

        # клиенту админ-команды недоступны
        h.sender.clear()
        h.say(CLIENT, "/pending")
        assert "№" not in h.client_text() or "мастер" in h.client_text().lower()
    finally:
        h.cleanup()


def test_admin_day_off_command():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.say(ADMIN, "/off 2026-10-24")
        assert "выходной" in h.admin_text(), h.admin_text()
        assert h.db.is_day_off(datetime(2026, 10, 24))
        assert day_slots(h.cfg, h.db, datetime(2026, 10, 24), 40, h.clock()) == []

        h.say(ADMIN, "/on 24.10.2026")
        assert not h.db.is_day_off(datetime(2026, 10, 24))
    finally:
        h.cleanup()


def test_admin_block_command():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        # пятница 23.10, рабочие часы 10:00-18:00
        h.say(ADMIN, "/block 2026-10-23 10:00-14:00 обучение")
        assert "Занято" in h.admin_text(), h.admin_text()
        assert "обучение" in h.admin_text()
        slots = day_slots(h.cfg, h.db, datetime(2026, 10, 23), 40, h.clock())
        assert datetime(2026, 10, 23, 10) not in slots, "утро должно быть закрыто"
        assert slots and slots[0] >= datetime(2026, 10, 23, 14, 15), slots[:3]

        # закрываем остаток дня — окон не остаётся
        h.say(ADMIN, "/block 2026-10-23 14:00-18:00")
        assert day_slots(h.cfg, h.db, datetime(2026, 10, 23), 40, h.clock()) == []

        h.say(ADMIN, "/unblock")
        assert "обучение" in h.admin_text()
    finally:
        h.cleanup()


def test_admin_approve_by_command():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h)
        h.sender.clear()
        h.say(ADMIN, f"/approve {rid}")
        assert h.db.get_request(rid).status == STATUS_CONFIRMED
        assert "Запись подтверждена" in h.client_text()
    finally:
        h.cleanup()


def test_admin_reschedule():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h)
        h.press(ADMIN, "ok", rid)
        old = h.db.get_request(rid).starts_at
        h.sender.clear()

        h.press(ADMIN, "reschedule", rid)
        labels = h.admin_labels()
        assert any(":" in l for l in labels), labels
        new_label = next(l for l in labels if ":" in l)
        new_value = datetime.strptime(
            f"{new_label.split()[0].replace('.', '-')}-{new_label.split()[1]}", "%Y-%m-%d-%H:%M"
        ) if False else None  # значение берём из payload-кнопки напрямую

        # жмём кнопку переноса: payload содержит полное время
        state, data = h.db.get_state(ADMIN)
        assert state == "adm_reschedule"
        kb = h.sender.last(ADMIN).keyboard
        value = None
        for row in kb["buttons"]:
            for button in row:
                payload = (button.get("action") or {}).get("payload") or ""
                if '"rs_slot"' in payload and '"' in payload:
                    import json

                    parsed = json.loads(payload)
                    if parsed.get("c") == "rs_slot":
                        value = parsed.get("v")
                        break
            if value:
                break
        assert value, "не нашёл кнопку с новым временем"
        h.press(ADMIN, "rs_slot", value)

        req = h.db.get_request(rid)
        assert req.starts_at != old, "время должно было измениться"
        assert "перенесена" in h.client_text().lower() or "Перенесена" in h.client_text()
        # напоминания пересозданы под новое время
        rows = h.db._query("SELECT send_at FROM reminders WHERE request_id = ? AND kind = 'client_2h'",
                           (rid,))
        assert rows, "напоминание пропало после переноса"
    finally:
        h.cleanup()


def test_non_admin_cannot_reach_admin_actions():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        rid = walk_booking(h)
        h.sender.clear()
        h.press(CLIENT, "ok", rid)  # клиент жмёт «подтвердить»
        assert h.db.get_request(rid).status == STATUS_PENDING, "клиент не должен подтверждать"
        assert "мастер" in h.client_text().lower(), h.client_text()
    finally:
        h.cleanup()


def test_chat_messages_are_ignored():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.bot.on_message({"from_id": CLIENT, "peer_id": 2_000_000_001, "text": "записаться"})
        h.flush()
        assert h.sender.messages_for(CLIENT) == [], "в беседах бот отвечать не должен"
        assert h.db.count_active(CLIENT) == 0
    finally:
        h.cleanup()


def test_state_survives_restart():
    """Ноутбук перезагрузился посреди сценария — диалог продолжается с того же шага."""
    from bot.handlers import Bot
    from tests.helpers import _date_value_from_label

    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.press(CLIENT, "book")
        h.press(CLIENT, "svc", "back")
        state, data = h.db.get_state(CLIENT)
        assert state == "pick_date" and data["service_id"] == "back"
        labels = [label for label in h.client_labels() if "," in label]
        assert labels

        # «перезапуск»: новый Bot поверх той же базы
        h.bot = Bot(h.cfg, h.db, h.sender, now_fn=h.clock)
        h.sender.clear()

        h.press(CLIENT, "date", _date_value_from_label(labels[0], h))
        assert h.db.get_state(CLIENT)[0] == "pick_time", "шаг должен был продолжиться"
        assert any(":" in label for label in h.client_labels()), h.client_labels()

        # и слово «меню» выводит из сценария в любой момент
        h.say(CLIENT, "меню")
        assert h.db.get_state(CLIENT)[0] == "idle"
        assert any("Записаться" in label for label in h.client_labels())
    finally:
        h.cleanup()


def test_outbox_retries_on_network_error():
    h = make_harness(now=datetime(2026, 10, 22, 9, 0))
    try:
        h.sender.fail_next = 1
        h.press(CLIENT, "contact")  # сообщение упадёт при отправке
        assert h.sender.messages_for(CLIENT) == []
        assert h.db.outbox_pending_count() == 1

        h.clock.advance(seconds=6)
        h.flush()
        assert h.db.outbox_pending_count() == 0
        assert "+7 900 000-00-00" in h.client_text()
    finally:
        h.cleanup()
