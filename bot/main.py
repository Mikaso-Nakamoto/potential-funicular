"""Точка входа: python -m bot.main [--config config.toml] [--check] [--once].

Запуск в боевом режиме:
    python3 -m bot.main

Проверка настроек без запуска:
    python3 -m bot.main --check

Один проход воркера (диагностика, без long poll):
    python3 -m bot.main --once
"""

from __future__ import annotations

import argparse
import logging
import os
import signal
import sys
import threading
from pathlib import Path

from . import __version__
from .config import Config, load_config
from .db import Database
from .handlers import Bot
from .scheduler import Scheduler, start_worker
from .util import now as now_local
from .vk import VK, VKAuthError, LongPoll

log = logging.getLogger("bot.main")

BANNER = r"""
 Massage Booking Bot  ·  VK + SQLite
 (запись клиентов, подтверждение мастером, напоминания)
"""


def setup_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stdout,
    )
    logging.getLogger("bot.vk").setLevel(logging.INFO)


def report_problems(cfg: Config) -> int:
    problems = cfg.validate()
    if not problems:
        print("✅ Конфигурация выглядит корректно.")
        return 0
    print("⚠️  Проблемы в конфигурации:")
    for item in problems:
        print(f"   • {item}")
    fatal = any(
        p.startswith(("Не задан ключ", "Не задан VK_GROUP_ID"))
        or "VK_GROUP_TOKEN похож на заглушку" in p
        for p in problems
    )
    if fatal:
        print("\nБез VK_GROUP_TOKEN и VK_GROUP_ID бот работать не может.")
        print("Инструкция: docs/VK_SETUP.md, пример: cp .env.example .env")
        return 2
    return 1


def print_summary(cfg: Config, db: Database) -> None:
    print(
        f"\n🌿 {cfg.bot_name}\n"
        f"   группа ВК: {cfg.group_id or '—'}\n"
        f"   часовой пояс: {cfg.timezone}\n"
        f"   база: {cfg.db_path}\n"
        f"   услуг: {len(cfg.active_services())}\n"
        f"   мастер получает уведомления: {', '.join(str(i) for i in cfg.admin_ids) or '—'}\n"
        f"   напоминания клиенту: за {cfg.client_before_hours} ч\n"
        f"   дайджест: {cfg.digest_time if cfg.digest_enabled else 'выключен'}\n"
    )


class SingleInstance:
    """Защита от двух запущенных ботов (systemd + руками).

    Два long poll на одно сообщество = дубли ответов и гонки в базе.
    """

    def __init__(self, path: Path):
        self.path = path
        self._fh = None

    def acquire(self) -> bool:
        try:
            import fcntl
        except ModuleNotFoundError:  # pragma: no cover - Windows
            return True
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._fh = open(self.path, "w", encoding="utf-8")
        try:
            fcntl.flock(self._fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self._fh.close()
            self._fh = None
            return False
        self._fh.write(f"{os.getpid()}\n")
        self._fh.flush()
        return True

    def release(self) -> None:
        if self._fh is not None:
            try:
                import fcntl

                fcntl.flock(self._fh.fileno(), fcntl.LOCK_UN)
            except OSError:  # pragma: no cover
                pass
            self._fh.close()
            self._fh = None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="VK-бот записи на массаж")
    parser.add_argument("--config", help="путь к config.toml (по умолчанию ./config.toml)")
    parser.add_argument("--env", help="путь к .env (по умолчанию ./.env)")
    parser.add_argument("--db", help="переопределить путь к базе SQLite")
    parser.add_argument("--check", action="store_true", help="проверить конфиг и выйти")
    parser.add_argument("--once", action="store_true", help="один проход воркера и выйти")
    parser.add_argument("--version", action="store_true", help="версия бота")
    args = parser.parse_args(argv)

    if args.version:
        print(f"massage-booking-bot {__version__}")
        return 0

    try:
        cfg = load_config(args.config, args.env)
    except FileNotFoundError as exc:
        print(f"❌ {exc}")
        return 2
    except Exception as exc:  # noqa: BLE001
        print(f"❌ Не удалось прочитать конфиг: {exc}")
        return 2

    if args.db:
        cfg.db_path = Path(args.db)

    setup_logging(cfg.log_level)

    if args.check:
        print(BANNER)
        print_summary(cfg, None)  # type: ignore[arg-type]
        return report_problems(cfg)

    lock = SingleInstance(cfg.db_path.parent / "bot.lock")
    if not lock.acquire():
        print(
            "❌ Бот уже запущен (найдена блокировка "
            f"{cfg.db_path.parent / 'bot.lock'}).\n"
            "   Два бота на одно сообщество = дубли ответов.\n"
            "   Проверьте: systemctl status massage-bot   или   pgrep -af 'bot.main'"
        )
        return 3

    db = Database(cfg.db_path)
    print(BANNER)
    print_summary(cfg, db)
    report_problems(cfg)

    if not cfg.token or not cfg.group_id:
        log.error("Не заданы VK_GROUP_TOKEN / VK_GROUP_ID — запуск невозможен")
        lock.release()
        return 2

    vk = VK(cfg.token, cfg.group_id, cfg.api_version)
    try:
        group = vk.get_group_info()
    except VKAuthError as exc:
        log.error("Ключ сообщества не работает: %s", exc)
        log.error("Проверьте VK_GROUP_TOKEN в .env и права ключа (docs/VK_SETUP.md)")
        lock.release()
        return 2
    except Exception as exc:  # noqa: BLE001
        log.error("Нет связи с api.vk.com: %s", exc)
        log.error("Проверьте интернет и точное время на сервере (sudo timedatectl)")
        lock.release()
        return 2

    log.info(
        "Подключился к сообществу: %s (@%s, id=%s)",
        group.get("name", "?"), group.get("screen_name", "?"), group.get("id", cfg.group_id),
    )

    bot = Bot(cfg, db, vk, now_fn=lambda: now_local(cfg.tzinfo))
    scheduler = Scheduler(cfg, db, bot, now_fn=bot.now_fn)
    stop_event = threading.Event()

    if args.once:
        result = scheduler.tick()
        log.info("Один проход воркера: %s", result)
        log.info("В очереди осталось сообщений: %s", db.outbox_pending_count())
        return 0

    def handle_signal(signum, _frame):  # pragma: no cover - зависит от ОС
        log.info("Получен сигнал %s — останавливаюсь…", signum)
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            signal.signal(sig, handle_signal)
        except (ValueError, OSError):  # pragma: no cover
            pass

    start_worker(scheduler, stop_event, interval=15.0)
    long_poll = LongPoll(vk, wait=25, stop_event=stop_event)

    log.info("Слушаю сообщения сообщества… (Ctrl+C — остановка)")
    try:
        for event in long_poll.events():
            if stop_event.is_set():
                break
            try:
                bot.on_event(event)
            except Exception:  # noqa: BLE001
                log.exception("Ошибка обработки события, продолжаю")
            # сразу проталкиваем ответы, не дожидаясь следующего тика воркера
            try:
                bot.flush_outbox()
            except Exception:  # noqa: BLE001
                log.exception("Ошибка отправки очереди")
    except KeyboardInterrupt:  # pragma: no cover
        stop_event.set()
    finally:
        stop_event.set()
        try:
            bot.flush_outbox()
        except Exception:  # noqa: BLE001
            pass
        db.close()
        lock.release()
        log.info("Остановлен. До связи 👋")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
