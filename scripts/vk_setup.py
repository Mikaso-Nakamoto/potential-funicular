#!/usr/bin/env python3
"""Автоматическая настройка сообщества ВКонтакте под бота.

    python3 scripts/vk_setup.py            # проверить и включить что можно
    python3 scripts/vk_setup.py --apply    # применить изменения

Что делает (нужен ключ сообщества с правом «управление сообществом»):
  1. проверяет ключ и показывает сообщество;
  2. включает Bots Long Poll API нужной версии;
  3. включает нужные типы событий: message_new и message_event
     (message_event обязателен для inline-кнопок «Подтвердить/Отклонить»);
  4. показывает, что осталось сделать руками в веб-интерфейсе.

Всё, что скрипт не смог сделать через API, он печатает как пошаговую инструкцию.
Подробно: docs/VK_SETUP.md
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from bot.config import load_config  # noqa: E402
from bot.vk import VK, VKAuthError, VKError, VKTransportError  # noqa: E402

API_VERSION = "5.198"
NEEDED_EVENTS = ["message_new", "message_event"]

MANUAL_STEPS = """
Что нужно проверить руками в сообществе (API это не переключает):

  1. Сообщения сообщества включены
     Управление → Сообщения → «Сообщения сообщества»: Включены
     Там же: «Кто может писать сообщения» → Все пользователи
     Рекомендую включить «Начальный текст» (приветствие), например:
       «Здравствуйте! Нажмите 📅 Записаться, чтобы выбрать время.
        Если вопрос срочный — пишите сюда текстом.»

  2. Мастер написал сообществу хотя бы одно сообщение
     Без этого ВКонтакте запрещает сообществу писать ПЕРВЫМ, и уведомления
     о заявках не дойдут. Пусть тётя откроет диалог со своим же сообществом
     и напишет «привет». Проверка: python3 scripts/doctor.py --send-test

  3. Ссылка для клиентов
     Её тётя и будет давать людям: https://vk.me/<адрес сообщества>
     (адрес сообщества — в строке браузера, например vk.com/club123456 → vk.me/club123456)
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Настройка сообщества ВК под бота")
    parser.add_argument("--config", help="путь к config.toml")
    parser.add_argument("--env", help="путь к .env")
    parser.add_argument("--apply", action="store_true", help="применить изменения (иначе только проверка)")
    args = parser.parse_args()

    try:
        cfg = load_config(args.config, args.env)
    except Exception as exc:  # noqa: BLE001
        print(f"❌ Не удалось прочитать конфиг: {exc}")
        print("   Сначала: cp config.example.toml config.toml && cp .env.example .env")
        return 2

    if not cfg.token or not cfg.group_id:
        print("❌ В .env нет VK_GROUP_TOKEN / VK_GROUP_ID — см. docs/VK_SETUP.md")
        return 2

    vk = VK(cfg.token, cfg.group_id, cfg.api_version)

    # --- 1. кто мы --- #
    try:
        group = vk.get_group_info()
    except VKAuthError as exc:
        print(f"❌ Ключ сообщества не принят: {exc.msg}")
        print("   Нужен «ключ доступа сообщества» (Управление → Работа с API → Ключи доступа).")
        return 1
    except (VKError, VKTransportError) as exc:
        print(f"❌ Нет связи с api.vk.com: {exc}")
        return 1
    print(f"✅ Сообщество: {group.get('name')} (@{group.get('screen_name')}, id={group.get('id')})")
    print(f"   Тип: {group.get('type')} · закрытое: {bool(group.get('is_closed'))}")

    # --- 2. текущие настройки long poll --- #
    try:
        settings = vk.call("groups.getLongPollSettings", {"group_id": cfg.group_id})
    except (VKError, VKTransportError) as exc:
        print(f"⚠️  Не смог прочитать настройки Long Poll: {exc}")
        settings = {}

    enabled = bool(settings.get("is_enabled"))
    version = str(settings.get("api_version") or "—")
    events = settings.get("events") or {}
    print(f"\n   Long Poll API: {'включён' if enabled else 'ВЫКЛЮЧЕН'} · версия {version}")
    for name in NEEDED_EVENTS:
        print(f"   событие {name:<14}: {'включено' if events.get(name) else 'НЕ включено'}")

    need_change = (
        not enabled
        or version != API_VERSION
        or any(not events.get(name) for name in NEEDED_EVENTS)
    )

    if not need_change:
        print("\n✅ Long Poll настроен правильно, менять нечего.")
        print(MANUAL_STEPS)
        return 0

    if not args.apply:
        print("\n⚠️  Нужны изменения. Запустите с флагом:  python3 scripts/vk_setup.py --apply")
        print(MANUAL_STEPS)
        return 1

    # --- 3. применяем --- #
    new_events = dict(events)
    for name in NEEDED_EVENTS:
        new_events[name] = 1
    import json

    params = {
        "group_id": cfg.group_id,
        "enabled": 1,
        "api_version": API_VERSION,
        "events": json.dumps(new_events, separators=(",", ":")),
    }
    try:
        vk.call("groups.setLongPollSettings", params)
        print(f"\n✅ Long Poll API включён (версия {API_VERSION}), события обновлены.")
    except VKError as exc:
        print(f"\n❌ Не удалось настроить через API: {exc.msg}")
        print("   Скорее всего у ключа нет права «управление сообществом».")
        print("   Либо пересоздайте ключ с этим правом, либо включите вручную:")
        print("   Управление → Работа с API → Long Poll API:")
        print(f"     • Включён, версия {API_VERSION}")
        print("     • Типы событий → Сообщения сообщества: входящие сообщения")
        print("       и «нажатие на callback-кнопку» (message_event)")
        print(MANUAL_STEPS)
        return 1
    except (VKTransportError,) as exc:
        print(f"\n❌ Сетевая ошибка: {exc}")
        return 1

    # --- 4. проверка после применения --- #
    try:
        after = vk.call("groups.getLongPollSettings", {"group_id": cfg.group_id})
        events_after = after.get("events") or {}
        ok = bool(after.get("is_enabled")) and all(events_after.get(n) for n in NEEDED_EVENTS)
        print(f"   Проверка: {'✅ всё включено' if ok else '⚠️  что-то не включилось — проверьте руками'}")
    except (VKError, VKTransportError):
        pass

    try:
        lp = vk.get_long_poll_server()
        if lp.get("server") and lp.get("key"):
            print("✅ Long Poll сервер отвечает — бот сможет слушать сообщения.")
        else:
            print("⚠️  Long Poll сервер вернул пустой ответ.")
    except (VKError, VKTransportError) as exc:
        print(f"⚠️  Не получил long poll сервер: {exc}")

    print(MANUAL_STEPS)
    print("Дальше:  python3 scripts/doctor.py --all")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
