#!/usr/bin/env python3
"""Диагностика бота: python3 scripts/doctor.py [--api] [--slots] [--whoami] [--send-test]

Проверяет по шагам всё, что нужно для работы, и пишет по-русски, что сделать.
Безопасно запускать в любой момент — ничего не ломает.

  (без флагов)  конфиг, .env, база, расписание
  --api         связь с api.vk.com, ключ сообщества, long poll сервер
  --slots       показать ближайшие свободные окна (проверка расписания)
  --whoami      показать id людей, которые уже писали боту (как узнать ADMIN_VK_IDS)
  --send-test   отправить тестовое сообщение мастерам (проверка доставки)
  --all         всё сразу
"""

from __future__ import annotations

import argparse
import sys
from datetime import timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from bot.config import Config, load_config  # noqa: E402
from bot.db import STATUS_CONFIRMED, STATUS_PENDING, Database  # noqa: E402
from bot.slots import available_dates, day_slots, work_hours_text  # noqa: E402
from bot.util import format_date_full, now as now_local  # noqa: E402

OK = "✅"
WARN = "⚠️ "
FAIL = "❌"
INFO = "ℹ️ "


def header(title: str) -> None:
    print(f"\n{'─' * 62}\n{title}\n{'─' * 62}")


def check_python() -> bool:
    header("1. Python")
    version = sys.version_info
    print(f"{INFO} версия: {sys.version.split()[0]}")
    if version < (3, 11):
        print(f"{WARN} нужен Python 3.11+ (модуль tomllib для config.toml)")
        print("    Вариант А: sudo apt install python3-tomli")
        print("    Вариант Б: sudo apt install python3.11  (или новее)")
        try:
            import tomli  # type: ignore  # noqa: F401

            print(f"{OK} найден tomli — конфиг прочитается")
            return True
        except ModuleNotFoundError:
            print(f"{FAIL} tomli не найден — конфиг не прочитается")
            return False
    print(f"{OK} версия подходит")
    return True


def check_config(cfg: Config | None, error: str | None) -> bool:
    header("3. Конфигурация")
    if cfg is None:
        print(f"{FAIL} {error}")
        print("    Создайте конфиг:  cp config.example.toml config.toml && nano config.toml")
        return False

    print(f"{OK} config.toml прочитан: {cfg.bot_name}")
    print(f"{INFO} часовой пояс: {cfg.timezone}")
    print(f"{INFO} база данных: {cfg.db_path}")
    print(f"{INFO} услуг: {len(cfg.active_services())}")
    for svc in cfg.active_services():
        print(f"      • {svc.title}: {svc.duration} мин, {svc.price_text()}")

    print(f"\n{INFO} расписание:")
    for line in work_hours_text(cfg).splitlines():
        print(f"      {line}")
    print(
        f"{INFO} шаг сетки {cfg.slot_minutes} мин, буфер {cfg.buffer_minutes} мин, "
        f"запись не позже чем за {cfg.min_notice_minutes} мин"
    )
    print(f"{INFO} напоминания клиенту: за {cfg.client_before_hours or '—'} ч")
    print(f"{INFO} напоминания мастеру: за {cfg.admin_before_hours or '—'} ч")
    print(
        f"{INFO} дайджест: {cfg.digest_time if cfg.digest_enabled else 'выключен'}"
        f" · заявки истекают через {cfg.pending_ttl_hours} ч"
    )

    problems = cfg.validate()
    fatal = False
    if problems:
        for item in problems:
            mark = FAIL if item.startswith(("Не задан ключ", "Не задан VK_GROUP_ID")) else WARN
            if mark == FAIL:
                fatal = True
            print(f"{mark} {item}")
    else:
        print(f"{OK} замечаний к конфигу нет")

    print(f"\n{INFO} карточка контакта, которую видят клиенты:")
    for line in cfg.contacts.card().splitlines():
        print(f"      {line}")
    return not fatal


def check_env_files() -> None:
    header("2. Файлы и секреты")
    for name, hint in (
        ("config.toml", "cp config.example.toml config.toml"),
        (".env", "cp .env.example .env && nano .env"),
    ):
        path = ROOT / name
        if path.exists():
            print(f"{OK} {name} на месте")
        else:
            print(f"{FAIL} нет файла {name} → {hint}")
    env = ROOT / ".env"
    if env.exists():
        mode = env.stat().st_mode & 0o777
        if mode & 0o077:
            print(f"{WARN} .env доступен другим пользователям (права {oct(mode)}) → chmod 600 .env")
        else:
            print(f"{OK} права на .env в порядке ({oct(mode)})")
    if (ROOT / "config.toml").exists():
        text = (ROOT / "config.toml").read_text(encoding="utf-8")
        if "vk1.a." in text:
            print(f"{FAIL} в config.toml лежит ключ сообщества — перенесите его в .env!")


def check_database(cfg: Config) -> bool:
    header("4. База данных")
    try:
        db = Database(cfg.db_path)
    except Exception as exc:  # noqa: BLE001
        print(f"{FAIL} не удалось открыть/создать базу: {exc}")
        return False
    print(f"{OK} база открыта: {cfg.db_path}")
    row = db._one("PRAGMA integrity_check")
    print(f"{INFO} integrity_check: {row[0] if row else '?'}")
    stats = db.stats()
    print(
        f"{INFO} заявок всего: {stats.get('total', 0)} "
        f"(ждут: {stats.get(STATUS_PENDING, 0)}, подтверждено: {stats.get(STATUS_CONFIRMED, 0)})"
    )
    print(f"{INFO} клиентов в базе: {db.clients_count()}")
    print(f"{INFO} сообщений в очереди: {db.outbox_pending_count()}")
    days_off = db.list_day_off(limit=10)
    if days_off:
        print(f"{INFO} выходные: " + ", ".join(format_date_full(d) for d in days_off))
    blocked = db.list_blocked(limit=10)
    if blocked:
        print(f"{INFO} занятых интервалов: {len(blocked)}")
    return True


def check_api(cfg: Config) -> bool:
    header("5. ВКонтакте (api.vk.com)")
    from bot.vk import VK, VKAuthError, VKError, VKTransportError

    if not cfg.token or not cfg.group_id:
        print(f"{FAIL} нет VK_GROUP_TOKEN / VK_GROUP_ID — проверять нечего (см. docs/VK_SETUP.md)")
        return False
    vk = VK(cfg.token, cfg.group_id, cfg.api_version)
    try:
        group = vk.get_group_info()
    except VKAuthError as exc:
        print(f"{FAIL} ключ сообщества отклонён: {exc.msg}")
        print("    • ключ должен быть «ключом сообщества», а не личным")
        print("    • сообщество должно быть привязано к этому ключу")
        print("    • у ключа должно быть право «сообщения сообщества»")
        return False
    except (VKError, VKTransportError) as exc:
        print(f"{FAIL} нет связи с api.vk.com: {exc}")
        print("    • проверьте интернет и точное время на сервере: timedatectl")
        return False

    print(f"{OK} сообщество: {group.get('name')} (@{group.get('screen_name')}, id={group.get('id')})")
    if group.get("is_closed") or group.get("type") == "private":
        print(f"{WARN} сообщество закрытое — клиенты могут не найти бота. Лучше сделать открытым.")

    try:
        lp = vk.get_long_poll_server()
    except (VKError, VKTransportError) as exc:
        print(f"{FAIL} не получил long poll сервер: {exc}")
        print("    Включите в сообществе: Управление → Работа с API → Long Poll API → Включить,")
        print("    версия 5.198, типы событий: message_new, message_event")
        return False
    if lp.get("server") and lp.get("key"):
        print(f"{OK} Bots Long Poll включён и отвечает")
    else:
        print(f"{FAIL} Long Poll вернул пустой ответ: {lp}")
        return False

    try:
        settings = vk.call("groups.getLongPollSettings", {"group_id": cfg.group_id})
        enabled = settings.get("is_enabled")
        print(f"{INFO} is_enabled: {enabled}")
        events = settings.get("events") or {}
        for key in ("message_new", "message_event"):
            mark = OK if events.get(key) else WARN
            print(f"{mark} событие {key}: {'включено' if events.get(key) else 'НЕ включено'}")
        if not events.get("message_event") and cfg.use_callback_buttons:
            print(
                f"{WARN} без message_event inline-кнопки работать не будут.\n"
                "    Либо включите событие, либо поставьте в config.toml "
                "policy.use_callback_buttons = false"
            )
    except (VKError, VKTransportError) as exc:
        print(f"{WARN} не удалось прочитать настройки long poll: {exc}")

    # доставка сообщений
    if cfg.admin_ids:
        admin_id = cfg.admin_ids[0]
        try:
            vk.send_message(admin_id, "🩺 Диагностика: бот может писать вам ✅")
            print(f"{OK} тестовое сообщение отправлено на id {admin_id}")
        except VKError as exc:
            print(f"{FAIL} не смог написать id {admin_id}: {exc.msg}")
            print(
                "    Чтобы бот писал первым, человек должен хотя бы раз написать в сообщество,\n"
                "    либо включите в сообществе «Сообщения сообщества» и добавьте кнопку-приветствие."
            )
            return False
    else:
        print(f"{WARN} ADMIN_VK_IDS не задан — некому слать заявки (узнать id: --whoami)")
    return True


def check_slots(cfg: Config) -> None:
    header("6. Свободные окна (как их увидит клиент)")
    db = Database(cfg.db_path)
    now = now_local(cfg.tzinfo)
    print(f"{INFO} сейчас: {now.strftime('%Y-%m-%d %H:%M')} ({cfg.timezone})")
    for svc in cfg.active_services()[:4]:
        dates = available_dates(cfg, db, svc.duration, now, limit=5)
        if not dates:
            print(f"{WARN} {svc.title}: свободных дат нет на {cfg.max_days_ahead} дней вперёд")
            print("    Проверьте [schedule.hours], work_days и min_notice_minutes")
            continue
        print(f"\n{OK} {svc.title} ({svc.duration} мин):")
        for date in dates[:5]:
            slots = day_slots(cfg, db, date, svc.duration, now)[:8]
            shown = ", ".join(s.strftime("%H:%M") for s in slots)
            print(f"    {format_date_full(date)}: {shown or '—'}")


def check_whoami(cfg: Config) -> None:
    header("7. Кто писал боту (как узнать свой vk_id)")
    db = Database(cfg.db_path)
    rows = db._query(
        "SELECT vk_id, first_name, last_name, phone, last_seen FROM clients ORDER BY last_seen DESC LIMIT 20"
    )
    if not rows:
        print(f"{INFO} пока никто не писал боту.")
        print("    Сделайте так:")
        print("      1) запустите бота: python3 -m bot.main")
        print("      2) со страницы тёти напишите в сообщения сообщества любое слово")
        print("      3) снова запустите: python3 scripts/doctor.py --whoami")
        print("      4) впишите полученный id в .env: ADMIN_VK_IDS=<id>")
        return
    for row in rows:
        mark = " (мастер)" if row["vk_id"] in cfg.admin_ids else ""
        name = " ".join(x for x in (row["first_name"], row["last_name"]) if x) or "—"
        print(f"    id {row['vk_id']:<12} {name}{mark}")
    print("\n    Скопируйте id мастера в .env: ADMIN_VK_IDS=... и перезапустите бота.")


def send_test(cfg: Config) -> None:
    header("8. Тестовая доставка")
    from bot.handlers import Bot
    from bot.vk import VK

    if not cfg.admin_ids:
        print(f"{FAIL} ADMIN_VK_IDS пуст — кому отправлять?")
        return
    db = Database(cfg.db_path)
    vk = VK(cfg.token, cfg.group_id, cfg.api_version)
    bot = Bot(cfg, db, vk, now_fn=lambda: now_local(cfg.tzinfo))
    for admin_id in cfg.admin_ids:
        db.enqueue_message(
            admin_id,
            "🩺 Тест доставки от бота записи.\nЕсли вы это видите — уведомления доходят ✅",
            now=now_local(cfg.tzinfo),
        )
    sent = bot.flush_outbox()
    print(f"{OK} отправлено сообщений: {sent} из {len(cfg.admin_ids)}")
    print(f"{INFO} в очереди осталось: {db.outbox_pending_count()}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Диагностика бота записи")
    parser.add_argument("--config", help="путь к config.toml")
    parser.add_argument("--env", help="путь к .env")
    parser.add_argument("--api", action="store_true", help="проверить связь с ВК")
    parser.add_argument("--slots", action="store_true", help="показать свободные окна")
    parser.add_argument("--whoami", action="store_true", help="показать id писавших боту")
    parser.add_argument("--send-test", action="store_true", help="тестовое сообщение мастерам")
    parser.add_argument("--all", action="store_true", help="все проверки")
    args = parser.parse_args()

    if args.all:
        args.api = args.slots = args.whoami = args.send_test = True

    print("🩺 Диагностика VK-бота записи на массаж")
    results: list[tuple[str, bool]] = []

    results.append(("Python", check_python()))
    check_env_files()

    cfg: Config | None = None
    error: str | None = None
    try:
        cfg = load_config(args.config, args.env)
    except FileNotFoundError as exc:
        error = str(exc)
    except Exception as exc:  # noqa: BLE001
        error = f"{type(exc).__name__}: {exc}"
    results.append(("Конфиг", check_config(cfg, error)))

    if cfg is None:
        print(f"\n{FAIL} Дальше проверять нечего — сначала нужен config.toml")
        return 2

    results.append(("База", check_database(cfg)))

    if args.api or args.send_test:
        results.append(("ВКонтакте", check_api(cfg)))
    if args.send_test:
        send_test(cfg)
    if args.slots:
        check_slots(cfg)
    if args.whoami:
        check_whoami(cfg)
    if not (args.api or args.slots or args.whoami or args.send_test):
        check_slots(cfg)

    header("Итог")
    bad = [name for name, ok in results if not ok]
    if bad:
        print(f"{FAIL} требуют внимания: {', '.join(bad)}")
        print("    Что делать — docs/TROUBLESHOOTING.md")
        return 1
    print(f"{OK} всё готово к запуску:  python3 -m bot.main")
    if not cfg.admin_ids:
        print(f"{WARN} но сначала укажите ADMIN_VK_IDS в .env (см. --whoami)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
