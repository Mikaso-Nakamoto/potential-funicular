#!/usr/bin/env python3
"""Песочница бота в терминале — без ВКонтакте и интернета.

    python3 scripts/demo.py            # интерактивно: вы и за клиента, и за мастера
    python3 scripts/demo.py --auto     # автоматически прогнать весь сценарий
    python3 scripts/demo.py --config config.toml   # на своём конфиге

Управление в интерактивном режиме:
    1..9      нажать кнопку с этим номером
    текст     написать сообщение как в ВК
    !client   переключиться на клиента
    !admin    переключиться на мастера (тётю)
    !time +2h сдвинуть время (примеры: +30m, +3h, +1d, 2026-10-25T09:00)
    !tick     выполнить проход воркера (напоминания, дайджест, истечение заявок)
    !state    показать текущее состояние диалога
    !help     эта справка
    !quit     выход
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from bot.config import Config, Contacts, Service, load_config  # noqa: E402
from bot.db import Database  # noqa: E402
from bot.handlers import Bot  # noqa: E402
from bot.scheduler import Scheduler  # noqa: E402
from bot.util import get_tz  # noqa: E402

CLIENT_ID = 222
ADMIN_ID = 111

C_CLIENT = "\033[96m"   # голубой
C_ADMIN = "\033[95m"    # розовый
C_BOT = "\033[92m"      # зелёный
C_DIM = "\033[90m"
C_BOLD = "\033[1m"
C_OFF = "\033[0m"


class Clock:
    def __init__(self, start: datetime):
        self.current = start

    def __call__(self) -> datetime:
        return self.current

    def move(self, delta: timedelta) -> None:
        self.current += delta


class TerminalSender:
    """«ВКонтакте» в терминале: печатает сообщения и запоминает кнопки."""

    def __init__(self, clock: Clock):
        self.clock = clock
        self.buttons: dict[int, list[tuple[str, str, Any]]] = {CLIENT_ID: [], ADMIN_ID: []}
        self.count = 0

    def send_message(self, peer_id: int, text: str = "", keyboard: dict | None = None) -> int:
        self.count += 1
        who, color = ("МАСТЕР", C_ADMIN) if peer_id == ADMIN_ID else ("КЛИЕНТ", C_CLIENT)
        stamp = self.clock().strftime("%d.%m %H:%M")
        print(f"\n{color}{C_BOLD}┌─ бот → {who} ({stamp}) ─────────────────{C_OFF}")
        for line in (text or "").splitlines() or [""]:
            print(f"{color}│{C_OFF} {line}")
        labels: list[tuple[str, str, Any]] = []
        if not keyboard:
            # в ВК постоянная клавиатура (one_time=false) остаётся под полем ввода
            print(f"{color}{C_BOLD}└{'─' * 45}{C_OFF}")
            return self.count
        if keyboard:
            import json

            for row in keyboard.get("buttons", []):
                cells = []
                for button in row:
                    action = button.get("action") or {}
                    label = action.get("label", "")
                    payload = action.get("payload") or ""
                    cmd = value = None
                    try:
                        parsed = json.loads(payload) if payload else {}
                        cmd = parsed.get("c")
                        value = parsed.get("v")
                    except Exception:  # noqa: BLE001
                        pass
                    labels.append((label, cmd, value))
                    cells.append(label)
                print(f"{color}│{C_OFF} {C_DIM}[ " + "  |  ".join(cells) + f" ]{C_OFF}")
        print(f"{color}{C_BOLD}└{'─' * 45}{C_OFF}")
        self.buttons[peer_id] = labels
        return self.count

    def answer_event(self, peer_id: int, user_id: int, event_id: str, text: str = "Готово ✅"):
        print(f"{C_DIM}   (всплывашка в ВК: {text}){C_OFF}")

    def get_user_names(self, user_ids: list[int]) -> dict[int, tuple[str, str]]:
        return {CLIENT_ID: ("Мария", "Иванова"), ADMIN_ID: ("Елена", "Массаж")}.copy()


def demo_config(db_path: Path) -> Config:
    cfg = Config()
    cfg.bot_name = "Демо: массаж у Елены"
    cfg.timezone = "Europe/Moscow"
    cfg.tzinfo = get_tz(cfg.timezone)
    cfg.group_id = 1
    cfg.token = "demo"
    cfg.db_path = db_path
    cfg.admin_ids = [ADMIN_ID]
    cfg.services = [
        Service("back", "Массаж спины", 40, 1500, "Шейно-воротниковая зона и спина"),
        Service("full", "Общий массаж", 60, 2500, "Всё тело, классика"),
        Service("face", "Массаж лица", 30, 1200, "Скульптурный"),
    ]
    cfg.work_days = ["mon", "tue", "wed", "thu", "fri", "sat"]
    cfg.hours = {
        "mon": ["10:00-14:00", "15:00-19:00"],
        "tue": ["10:00-19:00"],
        "wed": ["10:00-14:00", "15:00-19:00"],
        "thu": ["10:00-19:00"],
        "fri": ["10:00-18:00"],
        "sat": ["11:00-16:00"],
        "sun": [],
    }
    cfg.contacts = Contacts(
        master_name="Елена",
        phone="+7 900 000-00-00",
        whatsapp="https://wa.me/79000000000",
        vk="https://vk.com/id777",
        address="г. Тверь, ул. Советская, 10, каб. 5",
        how_to_find="Вход со двора, домофон 5",
        note="Отмена/перенос — за 3 часа",
    )
    cfg.client_before_hours = [24, 2]
    cfg.admin_before_hours = [24]
    cfg.digest_time = "09:00"
    cfg.cooldown_seconds = 0
    return cfg


def build(config_path: str | None, db_path: Path):
    clock = Clock(datetime(2026, 10, 22, 9, 0))  # четверг
    if config_path:
        cfg = load_config(config_path)
        cfg.db_path = db_path
        cfg.token = cfg.token or "demo"
        cfg.group_id = cfg.group_id or 1
        cfg.cooldown_seconds = 0
    else:
        cfg = demo_config(db_path)
    db = Database(db_path)
    sender = TerminalSender(clock)
    bot = Bot(cfg, db, sender, now_fn=clock)
    scheduler = Scheduler(cfg, db, bot, now_fn=clock)
    return cfg, db, sender, bot, scheduler, clock


def press(bot: Bot, sender: TerminalSender, user_id: int, index: int) -> None:
    buttons = sender.buttons.get(user_id) or []
    if not 1 <= index <= len(buttons):
        print(f"{C_DIM}Нет кнопки с номером {index}{C_OFF}")
        return
    label, cmd, value = buttons[index - 1]
    if not cmd:
        # обычная текстовая кнопка ВК отправляет текст + payload
        bot.on_message({"from_id": user_id, "peer_id": user_id, "text": label})
    else:
        bot.on_message_event(
            {"user_id": user_id, "peer_id": user_id, "event_id": f"demo{index}",
             "payload": {"c": cmd, "v": value}}
        )
    bot.flush_outbox()


def say(bot: Bot, user_id: int, text: str) -> None:
    bot.on_message({"from_id": user_id, "peer_id": user_id, "text": text})
    bot.flush_outbox()


def parse_shift(raw: str) -> timedelta | datetime | None:
    raw = raw.strip()
    m = re.fullmatch(r"([+-]?)(\d+)([mhdw])", raw)
    if m:
        sign = -1 if m.group(1) == "-" else 1
        value = int(m.group(2)) * sign
        unit = {"m": "minutes", "h": "hours", "d": "days", "w": "weeks"}[m.group(3)]
        return timedelta(**{unit: value})
    try:
        return datetime.fromisoformat(raw)
    except ValueError:
        return None


HELP = __doc__ or ""


def show_help() -> None:
    print(f"{C_DIM}{HELP}{C_OFF}")


def run_auto(cfg, db, sender, bot, scheduler, clock) -> None:
    print(f"{C_BOLD}Автоматический прогон: клиент записывается, мастер подтверждает{C_OFF}")
    say(bot, CLIENT_ID, "Здравствуйте!")
    press(bot, sender, CLIENT_ID, 1)              # Записаться
    press(bot, sender, CLIENT_ID, 1)              # первая услуга
    press(bot, sender, CLIENT_ID, 2)              # вторая доступная дата
    press(bot, sender, CLIENT_ID, 2)              # второе свободное окно
    press(bot, sender, CLIENT_ID, 1)              # имя «Верно»
    say(bot, CLIENT_ID, "+7 900 123-45-67")       # телефон
    press(bot, sender, CLIENT_ID, 1)              # без комментария
    press(bot, sender, CLIENT_ID, 1)              # отправить заявку

    print(f"\n{C_BOLD}— мастер смотрит заявку и подтверждает —{C_OFF}")
    press(bot, sender, ADMIN_ID, 1)               # Подтвердить

    print(f"\n{C_BOLD}— клиент проверяет свои записи —{C_OFF}")
    say(bot, CLIENT_ID, "мои записи")

    print(f"\n{C_BOLD}— сутки до сеанса: срабатывают напоминания —{C_OFF}")
    clock.move(timedelta(hours=24, minutes=30))
    scheduler.tick()

    print(f"\n{C_BOLD}— мастер смотрит расписание на день —{C_OFF}")
    say(bot, ADMIN_ID, "/today")

    print(f"\n{C_BOLD}— следующее утро: дайджест мастера —{C_OFF}")
    clock.move(timedelta(days=1))
    clock.current = clock.current.replace(hour=9, minute=1)
    scheduler.tick()

    print(f"\n{C_BOLD}— сеанс прошёл: статистика мастера —{C_OFF}")
    clock.move(timedelta(hours=4))
    scheduler.tick()
    say(bot, ADMIN_ID, "/stats")


def run_interactive(cfg, db, sender, bot, scheduler, clock) -> None:
    who = CLIENT_ID
    print(f"{C_BOLD}Демо-бот запущен.{C_OFF} Сейчас {clock():%Y-%m-%d %H:%M} ({cfg.timezone})")
    print(f"Вы — {C_CLIENT}КЛИЕНТ{C_OFF} (id {who}). Введите !help для команд, !quit для выхода.\n")
    say(bot, who, "Здравствуйте!")

    while True:
        who_name = f"{C_CLIENT}клиент{C_OFF}" if who == CLIENT_ID else f"{C_ADMIN}мастер{C_OFF}"
        try:
            raw = input(f"\n{who_name} {clock():%d.%m %H:%M} > ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nПока 👋")
            break
        if not raw:
            continue
        if raw in ("!quit", "!exit", "выход"):
            print("Пока 👋")
            break
        if raw == "!help":
            show_help()
            continue
        if raw == "!client":
            who = CLIENT_ID
            continue
        if raw == "!admin":
            who = ADMIN_ID
            continue
        if raw == "!tick":
            result = scheduler.tick()
            bot.flush_outbox()
            print(f"{C_DIM}воркер: {result}, в очереди: {db.outbox_pending_count()}{C_OFF}")
            continue
        if raw == "!state":
            for uid in (CLIENT_ID, ADMIN_ID):
                state, data = db.get_state(uid)
                who_txt = "клиент" if uid == CLIENT_ID else "мастер"
                print(f"{C_DIM}{who_txt}: состояние={state}, данные={data}{C_OFF}")
            print(f"{C_DIM}в очереди сообщений: {db.outbox_pending_count()}{C_OFF}")
            continue
        if raw.startswith("!time"):
            shift = parse_shift(raw.replace("!time", "", 1))
            if shift is None:
                print(f"{C_DIM}Формат: !time +2h | !time -30m | !time +1d | !time 2026-10-25T09:00{C_OFF}")
            elif isinstance(shift, timedelta):
                clock.move(shift)
                print(f"{C_DIM}теперь {clock():%Y-%m-%d %H:%M}{C_OFF}")
            else:
                clock.current = shift
                print(f"{C_DIM}теперь {clock():%Y-%m-%d %H:%M}{C_OFF}")
            continue
        if raw.isdigit():
            press(bot, sender, who, int(raw))
            continue
        say(bot, who, raw)


def main() -> int:
    parser = argparse.ArgumentParser(description="Демо бота в терминале")
    parser.add_argument("--config", help="использовать свой config.toml")
    parser.add_argument("--auto", action="store_true", help="автоматический прогон сценария")
    parser.add_argument("--keep", action="store_true", help="не удалять временную базу")
    args = parser.parse_args()

    import shutil
    import tempfile

    tmp = Path(tempfile.mkdtemp(prefix="massage-demo-"))
    db_path = tmp / "demo.sqlite3"
    try:
        cfg, db, sender, bot, scheduler, clock = build(args.config, db_path)
        if args.auto:
            run_auto(cfg, db, sender, bot, scheduler, clock)
        else:
            run_interactive(cfg, db, sender, bot, scheduler, clock)
        db.close()
    finally:
        if not args.keep:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            print(f"{C_DIM}База демо сохранена: {db_path}{C_OFF}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
