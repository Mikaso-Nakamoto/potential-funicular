"""Загрузка конфигурации: config.toml + секреты из .env / переменных окружения.

Секреты (ключ сообщества ВК) в конфиг не кладём — только .env или экспорт в
переменную окружения, чтобы случайно не отправить их в git.
"""

from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from .util import WEEKDAY_KEY, get_tz, parse_hhmm, parse_range, render

try:  # Python 3.11+
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python 3.10 и старше
    try:
        import tomli as tomllib  # type: ignore
    except ModuleNotFoundError:
        tomllib = None  # type: ignore

ROOT = Path(__file__).resolve().parent.parent


def load_toml(path: Path) -> dict:
    if tomllib is None:  # pragma: no cover
        sys.exit(
            "Для чтения config.toml нужен Python 3.11+ (модуль tomllib).\n"
            "Варианты: sudo apt install python3-tomli  ИЛИ  обновить Python до 3.11+.\n"
            "Проверка версии: python3 -V"
        )
    with open(path, "rb") as fh:
        return tomllib.load(fh)


def load_dotenv(path: Path) -> dict[str, str]:
    """Мини-парсер .env (KEY=value, # комментарии, кавычки)."""
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if key:
            env[key] = value
    return env


@dataclass
class Service:
    id: str
    title: str
    duration: int  # минуты
    price: int = 0
    description: str = ""
    active: bool = True

    @property
    def title_short(self) -> str:
        return self.title[:38]

    def price_text(self) -> str:
        if not self.price:
            return "цена по договорённости"
        return f"{self.price} ₽"


@dataclass
class Contacts:
    master_name: str = "мастер"
    phone: str = ""
    whatsapp: str = ""
    telegram: str = ""
    vk: str = ""
    address: str = ""
    how_to_find: str = ""
    note: str = ""

    def card(self) -> str:
        """Карточка контакта — то, что видит клиент («можно написать вживую»)."""
        lines = [f"👩‍⚕️ {self.master_name}"]
        if self.phone:
            lines.append(f"📞 {self.phone}")
        if self.whatsapp:
            lines.append(f"💬 WhatsApp: {self.whatsapp}")
        if self.telegram:
            lines.append(f"✈️ Telegram: {self.telegram}")
        if self.vk:
            lines.append(f"🔵 ВКонтакте: {self.vk}")
        if self.address:
            lines.append(f"📍 {self.address}")
        if self.how_to_find:
            lines.append(f"🚪 {self.how_to_find}")
        if self.note:
            lines.append(f"ℹ️ {self.note}")
        return "\n".join(lines)


@dataclass
class Config:
    # --- доступ к ВК ---
    group_id: int = 0
    token: str = ""
    api_version: str = "5.198"

    # --- общее ---
    bot_name: str = "Массаж"
    timezone: str = "Europe/Moscow"
    db_path: Path = ROOT / "data" / "massage.sqlite3"
    log_level: str = "INFO"

    # --- услуги ---
    services: list[Service] = field(default_factory=list)

    # --- расписание ---
    work_days: list[str] = field(default_factory=lambda: list(WEEKDAY_KEY[:6]))
    hours: dict[str, list[str]] = field(default_factory=dict)
    slot_minutes: int = 30
    buffer_minutes: int = 15
    min_notice_minutes: int = 120
    max_days_ahead: int = 21
    block_on_pending: bool = True

    # --- контакты ---
    contacts: Contacts = field(default_factory=Contacts)

    # --- админ (тётя) ---
    admin_ids: list[int] = field(default_factory=list)
    notify_admin_on_request: bool = True
    notify_admin_on_cancel: bool = True

    # --- напоминания / рассылка ---
    client_before_hours: list[int] = field(default_factory=lambda: [24, 2])
    admin_before_hours: list[int] = field(default_factory=lambda: [24])
    digest_enabled: bool = True
    digest_time: str = "09:00"
    pending_ttl_hours: int = 24

    # --- правила ---
    client_cancel_min_hours: int = 3
    max_active_requests: int = 2
    cooldown_seconds: int = 2
    use_callback_buttons: bool = True

    # --- тексты ---
    texts: dict[str, str] = field(default_factory=dict)

    tzinfo: object = None  # ZoneInfo, проставляется в load_config

    # ------------------------- производные ------------------------------- #
    def text(self, key: str, **ctx) -> str:
        template = self.texts.get(key)
        if template is None:
            template = _DEFAULT_TEXTS.get(key, "")
        return render(template, **ctx)

    def active_services(self) -> list[Service]:
        return [s for s in self.services if s.active]

    def service(self, service_id: str) -> Service | None:
        for s in self.services:
            if s.id == service_id:
                return s
        return None

    def day_ranges(self, dt: datetime) -> list[tuple[datetime, datetime]]:
        """Интервалы рабочего дня для конкретной даты."""
        key = WEEKDAY_KEY[dt.weekday()]
        if key not in self.work_days:
            return []
        out: list[tuple[datetime, datetime]] = []
        for raw in self.hours.get(key, []) or []:
            try:
                start, end = parse_range(raw)
            except ValueError:
                continue
            out.append(
                (
                    dt.replace(hour=start.hour, minute=start.minute),
                    dt.replace(hour=end.hour, minute=end.minute),
                )
            )
        out.sort(key=lambda pair: pair[0])
        return out

    # --------------------------- проверка -------------------------------- #
    def validate(self) -> list[str]:
        """Проверяет конфиг. Пустой список = всё хорошо."""
        problems: list[str] = []
        if not self.token:
            problems.append(
                "Не задан ключ сообщества: добавьте VK_GROUP_TOKEN=... в файл .env"
            )
        elif "xxxx" in self.token.lower():
            problems.append(
                "VK_GROUP_TOKEN похож на заглушку из .env.example — впишите настоящий ключ"
            )
        if not self.group_id:
            problems.append(
                "Не задан VK_GROUP_ID (id сообщества) в .env или config.toml"
            )
        if not self.services:
            problems.append("В config.toml нет ни одной услуги ([[services]])")
        if not self.admin_ids:
            problems.append(
                "Не задан ADMIN_VK_IDS — бот не знает, кому слать уведомления о заявках"
            )
        elif any(i <= 0 for i in self.admin_ids):
            problems.append(
                "ADMIN_VK_IDS содержит 0 — это заглушка из примера. "
                "Нужен настоящий числовой id (узнать: python3 scripts/doctor.py --whoami)"
            )
        if not self.work_days:
            problems.append("schedule.work_days пуст — никто не сможет записаться")
        if not any(self.hours.values()):
            problems.append("schedule.hours пуст — нет рабочих часов")
        for key, values in self.hours.items():
            if key not in WEEKDAY_KEY:
                problems.append(f"schedule.hours.{key}: неизвестный день (mon..sun)")
            for raw in values:
                try:
                    parse_range(raw)
                except ValueError as exc:
                    problems.append(f"schedule.hours.{key} = {raw!r}: {exc}")
        try:
            parse_hhmm(self.digest_time)
        except ValueError as exc:
            problems.append(f"reminders.digest_time: {exc}")
        if not self.contacts.phone and not self.contacts.vk:
            problems.append(
                "contacts: укажите хотя бы phone или vk — клиенту нужен живой контакт"
            )
        if any("id000000000" in self.contacts.vk for _ in (0,)) and self.contacts.vk:
            problems.append(
                "contacts.vk — заглушка из примера: впишите настоящую страницу мастера"
            )
        if len({s.id for s in self.services}) != len(self.services):
            problems.append("services: есть повторяющиеся id услуг")
        return problems


_DEFAULT_TEXTS: dict[str, str] = {
    "greeting": (
        "Здравствуйте, {name}! 🌿\n"
        "Это бот записи на массаж к мастеру {master}.\n\n"
        "Здесь можно выбрать удобное время и оставить заявку — {master} "
        "подтвердит её лично и ответит, если нужно что-то уточнить.\n\n"
        "Выберите, что нужно:"
    ),
    "unknown": (
        "Не совсем понял 🙏 Воспользуйтесь меню ниже или напишите «Меню».\n"
        "Если вопрос срочный — мастеру можно написать напрямую, контакты в "
        "разделе «Связаться»."
    ),
    "menu": "Главное меню 🌿",
    "services_intro": "Выберите, какой массаж вас интересует:",
    "no_services": (
        "Список услуг пока пуст — напишите мастеру напрямую, он подскажет."
    ),
    "service_info": (
        "🔹 {title}\n"
        "⏱ Длительность: {duration} мин\n"
        "💰 {price}\n"
        "{description}\n\n"
        "Выбираем время — нажмите «Записаться» или вернитесь к списку услуг."
    ),
    "pick_date": (
        "Выберите дату ({title}, {duration} мин):\n"
        "Серым/пустым днём окон нет — возьмите другой день."
    ),
    "no_dates": (
        "Ближайшие {days} дней свободных окон нет 😔\n"
        "Напишите мастеру напрямую — возможно, найдётся место вне графика."
    ),
    "no_slots": "На {date} свободных окон нет. Выберите, пожалуйста, другую дату.",
    "pick_time": "Свободное время на {date} (по {minutes} мин):\nВыберите окно:",
    "slot_taken": (
        "Увы, {when} только что заняли 🙈\nВот другие свободные окна:"
    ),
    "ask_name": (
        "Как вас записать? Напишите имя и фамилию.\n"
        "Можно нажать «Верно», если имя из профиля подходит: {name}"
    ),
    "bad_name": "Пожалуйста, напишите имя текстом (от 2 до 60 символов).",
    "ask_contact": (
        "Оставьте, пожалуйста, номер телефона — по нему мастер сможет "
        "перезвонить или написать в WhatsApp, если понадобится перенести запись.\n\n"
        "Если телефон давать не хотите, нажмите «Через ВКонтакте» — мастер "
        "напишет вам сюда."
    ),
    "bad_contact": (
        "Не похоже на номер телефона 🤔 Пример: +7 900 123-45-67.\n"
        "Или нажмите «Через ВКонтакте»."
    ),
    "ask_comment": (
        "Нужно что-то передать мастеру? (зона дискомфорта, аллергия, "
        "«первый визит» и т.п.)\nМожно нажать «Без комментария»."
    ),
    "summary": (
        "Проверьте заявку:\n\n"
        "🔹 Услуга: {title}\n"
        "📅 Когда: {when}\n"
        "⏱ Длительность: {duration} мин\n"
        "💰 {price}\n"
        "👤 Имя: {name}\n"
        "📱 Связь: {contact}\n"
        "📝 Комментарий: {comment}\n\n"
        "Отправить заявку мастеру?"
    ),
    "request_created": (
        "✅ Заявка отправлена!\n\n"
        "🔹 {title}\n📅 {when}\n\n"
        "{master} проверит расписание и подтвердит запись — обычно в течение "
        "{ttl}. Я напишу вам сюда сразу, как только она ответит.\n\n"
        "Если нужно что-то уточнить или поменять время — мастеру можно написать "
        "напрямую:\n{contacts}"
    ),
    "too_many_requests": (
        "У вас уже есть активные заявки ({count}). Дождитесь ответа мастера "
        "или отмените одну из них в разделе «Мои записи»."
    ),
    "approved_client": (
        "🎉 Запись подтверждена!\n\n"
        "🔹 {title}\n📅 {when}\n💰 {price}\n📍 {address}\n\n"
        "Пожалуйста, приходите за 5 минут до начала. Если планы изменились — "
        "отмените запись в разделе «Мои записи» или напишите мастеру: {phone}"
    ),
    "rejected_client": (
        "😔 К сожалению, мастер не может подтвердить запись на {when}.\n"
        "{reason}\n\n"
        "Можно выбрать другое время — нажмите «Записаться»."
    ),
    "expired_client": (
        "⏳ Заявка на {when} осталась без ответа и закрылась.\n"
        "Скорее всего мастер был(а) на сеансе. Напишите, пожалуйста, напрямую "
        "или отправьте заявку ещё раз."
    ),
    "reminder_client": (
        "⏰ Напоминание: {title}\n📅 {when}\n📍 {address}\n\n"
        "Если планы изменились — отмените запись в разделе «Мои записи» "
        "или напишите мастеру: {phone}"
    ),
    "reminder_admin": "⏰ Напоминание: через {delta} — {name}, {title}, {when}.",
    "cancelled_client": "❌ Запись на {when} отменена.",
    "cancel_too_late": (
        "Отменить самостоятельно можно не позже чем за {hours} ч до сеанса.\n"
        "Напишите, пожалуйста, мастеру напрямую: {phone} — он поможет."
    ),
    "my_bookings_empty": (
        "Активных записей нет.\nНажмите «Записаться», чтобы выбрать время."
    ),
    "my_bookings": "Ваши записи:\n\n{list}",
    "request_cancelled_admin": (
        "🔕 {name} отменил(а) запись: {title}, {when}.\nСлот снова свободен."
    ),
    "new_request_admin": (
        "🔔 НОВАЯ ЗАЯВКА №{id}\n\n"
        "🔹 {title} ({duration} мин, {price})\n"
        "📅 {when}\n"
        "👤 {name}\n"
        "📱 {contact}\n"
        "💬 Написать клиенту: {dialog}\n"
        "📝 Комментарий: {comment}\n\n"
        "Подтвердить или отклонить — кнопками ниже."
    ),
    "approved_admin": "✅ Вы подтвердили запись №{id}: {name}, {title}, {when}.",
    "rejected_admin": "🚫 Заявка №{id} отклонена, клиенту отправлено сообщение.",
    "already_decided": "Заявка №{id} уже обработана ({status}).",
    "request_not_found": "Заявка №{id} не найдена.",
    "admin_help": (
        "Команды мастера:\n"
        "/today — записи на сегодня\n"
        "/week — записи на 7 дней\n"
        "/pending — заявки, ждущие ответа\n"
        "/stats — краткая статистика\n"
        "/off 2026-10-25 — выходной на дату\n"
        "/on 2026-10-25 — снять выходной\n"
        "/block 2026-10-25 14:00-16:00 — занять интервал\n"
        "/unblock — список занятых интервалов\n"
        "/contacts — карточка контакта\n"
        "/help — эта справка"
    ),
    "digest": "📋 Записи на {date}:\n\n{list}",
    "digest_empty": "📋 На {date} записей нет — свободный день 🌿",
    "contacts": (
        "Связаться с мастером можно напрямую — отвечу на любые вопросы:\n\n"
        "{card}"
    ),
    "about": (
        "🌿 {master}\n\n"
        "{address}\n\n"
        "График приёма:\n{hours}\n\n"
        "Как связаться напрямую:\n{card}"
    ),
    "rescheduled_client": (
        "🔁 Запись перенесена мастером.\n\n"
        "🔹 {title}\n📅 Новое время: {when}\n📍 {address}\n\n"
        "Если не подходит — напишите мастеру: {phone}"
    ),
    "rescheduled_admin": "🔁 Запись №{id} ({name}) перенесена на {when}.",
    "prices": "Услуги и цены:\n\n{list}",
    "cancelled_by_admin": "Запись отменена мастером.",
}


def _env_int(value: str | None, default: int) -> int:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def _as_int_list(raw) -> list[int]:
    if raw is None:
        return []
    if isinstance(raw, (int, float)):
        return [int(raw)]
    if isinstance(raw, str):
        raw = [x for x in re.split(r"[,\s]+", raw.strip()) if x]
    out = []
    for item in raw:
        try:
            out.append(int(str(item).strip()))
        except ValueError:
            continue
    return out


def _as_id_list(raw) -> list[int]:
    return _as_int_list(raw)


def load_config(
    config_path: str | os.PathLike | None = None,
    env_path: str | os.PathLike | None = None,
) -> Config:
    """Собирает Config из config.toml и .env / переменных окружения."""
    root = ROOT
    cfg_path = Path(config_path or os.environ.get("BOT_CONFIG") or root / "config.toml")
    if not cfg_path.exists():
        example = root / "config.example.toml"
        raise FileNotFoundError(
            f"Не найден конфиг: {cfg_path}\n"
            f"Скопируйте пример: cp {example} {cfg_path} и заполните его."
        )
    data = load_toml(cfg_path)
    env = load_dotenv(Path(env_path or root / ".env"))

    def getenv(key: str, default=None):
        value = os.environ.get(key)
        if value is None or value == "":
            value = env.get(key)
        if value is None or value == "":
            return default
        return value

    cfg = Config()

    bot = data.get("bot", {})
    cfg.bot_name = str(bot.get("name", cfg.bot_name))
    cfg.timezone = str(bot.get("timezone", cfg.timezone))
    cfg.api_version = str(bot.get("api_version", cfg.api_version))
    cfg.log_level = str(bot.get("log_level", cfg.log_level))
    cfg.tzinfo = get_tz(cfg.timezone)

    vk = data.get("vk", {})
    cfg.group_id = _env_int(getenv("VK_GROUP_ID", vk.get("group_id")), 0)
    cfg.token = str(getenv("VK_GROUP_TOKEN", vk.get("token", "")) or "")

    storage = data.get("storage", {})
    db_raw = str(getenv("DB_PATH", storage.get("db_path", "data/massage.sqlite3")))
    db_path = Path(db_raw)
    cfg.db_path = db_path if db_path.is_absolute() else root / db_path

    for raw in data.get("services", []) or []:
        if not isinstance(raw, dict):
            continue
        try:
            duration = int(raw.get("duration", 60))
        except (TypeError, ValueError):
            continue
        svc = Service(
            id=str(raw.get("id") or raw.get("title", "")).strip(),
            title=str(raw.get("title", "")).strip(),
            duration=max(5, duration),
            price=_env_int(raw.get("price"), 0),
            description=str(raw.get("description", "")).strip(),
            active=bool(raw.get("active", True)),
        )
        if svc.id and svc.title:
            cfg.services.append(svc)

    sched = data.get("schedule", {})
    if sched.get("work_days"):
        cfg.work_days = [str(d).strip().lower()[:3] for d in sched["work_days"]]
    cfg.hours = {
        str(k).strip().lower()[:3]: [str(v) for v in (vals or [])]
        for k, vals in (sched.get("hours", {}) or {}).items()
    }
    cfg.slot_minutes = max(5, _env_int(sched.get("slot_minutes"), 30))
    cfg.buffer_minutes = max(0, _env_int(sched.get("buffer_minutes"), 0))
    cfg.min_notice_minutes = max(0, _env_int(sched.get("min_notice_minutes"), 120))
    cfg.max_days_ahead = max(1, _env_int(sched.get("max_days_ahead"), 21))
    cfg.block_on_pending = bool(sched.get("block_on_pending", True))

    contacts = data.get("contacts", {})
    cfg.contacts = Contacts(
        master_name=str(contacts.get("master_name", "мастер")),
        phone=str(contacts.get("phone", "")),
        whatsapp=str(contacts.get("whatsapp", "")),
        telegram=str(contacts.get("telegram", "")),
        vk=str(contacts.get("vk", "")),
        address=str(contacts.get("address", "")),
        how_to_find=str(contacts.get("how_to_find", "")),
        note=str(contacts.get("note", "")),
    )

    admin = data.get("admin", {})
    cfg.admin_ids = _as_id_list(getenv("ADMIN_VK_IDS", admin.get("vk_ids")))
    cfg.notify_admin_on_request = bool(admin.get("notify_on_request", True))
    cfg.notify_admin_on_cancel = bool(admin.get("notify_on_cancel", True))

    rem = data.get("reminders", {})
    cfg.client_before_hours = _as_int_list(
        rem.get("client_before_hours", cfg.client_before_hours)
    )
    cfg.admin_before_hours = _as_int_list(rem.get("admin_before_hours", []))
    cfg.digest_enabled = bool(rem.get("digest_enabled", True))
    cfg.digest_time = str(rem.get("digest_time", "09:00"))
    cfg.pending_ttl_hours = max(1, _env_int(rem.get("pending_ttl_hours"), 24))

    policy = data.get("policy", {})
    cfg.client_cancel_min_hours = max(0, _env_int(policy.get("client_cancel_min_hours"), 3))
    cfg.max_active_requests = max(1, _env_int(policy.get("max_active_requests"), 2))
    cfg.cooldown_seconds = max(0, _env_int(policy.get("cooldown_seconds"), 2))
    cfg.use_callback_buttons = bool(policy.get("use_callback_buttons", True))

    texts = data.get("texts", {}) or {}
    cfg.texts = {str(k): str(v) for k, v in texts.items()}

    return cfg
