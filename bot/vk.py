"""Клиент VK API и Bots Long Poll на стандартном urllib (без зависимостей).

Что используется:
  * messages.send            — отправка сообщений и кнопок
  * messages.sendMessageEventAnswer — ответ на нажатие inline-кнопки
  * groups.getLongPollServer — получение адреса long poll
  * groups.getById           — диагностика (scripts/doctor.py)
"""

from __future__ import annotations

import json
import logging
import random
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Iterator

log = logging.getLogger("bot.vk")

API_URL = "https://api.vk.com/method/"
USER_AGENT = "massage-booking-bot/1.0 (+https://github.com/)"

# коды ошибок ВК: https://dev.vk.com/reference/errors
ERR_UNKNOWN = 1
ERR_AUTH_FAILED = 5
ERR_TOO_MANY = 6
ERR_PERMISSION = 7
ERR_FLOOD = 9
ERR_CAPTCHA = 14
ERR_ACCESS_MESSAGE = 901
ERR_PRIVACY = 902


class VKError(Exception):
    def __init__(self, code: int, msg: str, extra: dict | None = None):
        self.code = code
        self.msg = msg
        self.extra = extra or {}
        super().__init__(f"VK error {code}: {msg}")

    @property
    def retry_after(self) -> float:
        try:
            return float(self.extra.get("retry_after", 0.5))
        except (TypeError, ValueError):
            return 0.5


class VKAuthError(VKError):
    """Ошибка авторизации/прав — перезапуск не поможет, нужен новый ключ."""


class VKTransportError(Exception):
    """Сеть/таймаут — можно повторить."""


class VK:
    """Минимальный клиент VK API. Потокобезопасен (состояния почти нет)."""

    def __init__(
        self,
        token: str,
        group_id: int,
        api_version: str = "5.198",
        timeout: float = 20.0,
        max_retries: int = 4,
    ):
        self.token = token
        self.group_id = int(group_id)
        self.api_version = api_version
        self.timeout = timeout
        self.max_retries = max_retries

    # ------------------------------------------------------------------ #
    # низкоуровневый вызов
    # ------------------------------------------------------------------ #
    def _post(self, method: str, params: dict[str, Any]) -> Any:
        body = {k: v for k, v in params.items() if v is not None}
        body["access_token"] = self.token
        body["v"] = self.api_version
        data = urllib.parse.urlencode(body, doseq=True).encode("utf-8")
        url = API_URL + method
        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": USER_AGENT,
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise VKTransportError(f"Не-JSON ответ от {method}: {raw[:200]}") from exc
        if "error" in payload:
            err = payload["error"] or {}
            code = int(err.get("error_code", ERR_UNKNOWN))
            msg = str(err.get("error_msg", "unknown error"))
            if code in (ERR_AUTH_FAILED, ERR_PERMISSION):
                raise VKAuthError(code, msg, err)
            raise VKError(code, msg, err)
        return payload.get("response")

    def call(self, method: str, params: dict[str, Any] | None = None) -> Any:
        """Вызов метода с ретраями на сеть/флуд."""
        params = params or {}
        attempt = 0
        while True:
            attempt += 1
            try:
                return self._post(method, params)
            except VKError as exc:
                if exc.code in (ERR_TOO_MANY, ERR_FLOOD) and attempt <= self.max_retries:
                    delay = min(3.0, max(0.3, exc.retry_after))
                    log.warning("VK flood limit (%s), ждём %.1fs", method, delay)
                    time.sleep(delay)
                    continue
                if exc.code in (ERR_ACCESS_MESSAGE, ERR_PRIVACY):
                    log.warning("VK: нельзя писать peer %s (%s)", params.get("peer_id"), exc.msg)
                    return None
                raise
            except (urllib.error.URLError, TimeoutError, OSError, VKTransportError) as exc:
                if attempt > self.max_retries:
                    raise VKTransportError(f"{method}: {exc}") from exc
                delay = min(8.0, 0.5 * (2 ** (attempt - 1))) + random.random() * 0.3
                log.warning("VK %s: сеть (%s), повтор через %.1fs", method, exc, delay)
                time.sleep(delay)

    # ------------------------------------------------------------------ #
    # сообщения
    # ------------------------------------------------------------------ #
    def send_message(
        self,
        peer_id: int,
        text: str = "",
        keyboard: dict | None = None,
        attachment: str | None = None,
    ) -> int | None:
        params: dict[str, Any] = {
            "peer_id": peer_id,
            "random_id": random.randint(1, 2**31 - 1),
            "message": text or "",
        }
        if keyboard:
            params["keyboard"] = json.dumps(keyboard, ensure_ascii=False, separators=(",", ":"))
        if attachment:
            params["attachment"] = attachment
        try:
            return self.call("messages.send", params)
        except VKError as exc:
            # сообщение слишком длинное — режем и пробуем ещё раз
            if exc.code == ERR_UNKNOWN and "message is too long" in exc.msg.lower():
                params["message"] = (text or "")[:4000]
                if keyboard:
                    params.pop("keyboard")
                return self.call("messages.send", params)
            raise

    def answer_event(
        self, peer_id: int, user_id: int, event_id: str, text: str = "Готово ✅"
    ) -> None:
        """Ответ на нажатие inline-кнопки (иначе ВК показывает ошибку)."""
        event_data = json.dumps({"type": "show_snackbar", "text": text[:90]}, ensure_ascii=False)
        try:
            self.call(
                "messages.sendMessageEventAnswer",
                {
                    "peer_id": peer_id,
                    "user_id": user_id,
                    "event_id": event_id,
                    "event_data": event_data,
                },
            )
        except (VKError, VKTransportError) as exc:
            log.warning("Не ответил на callback %s: %s", event_id, exc)

    # ------------------------------------------------------------------ #
    # служебное
    # ------------------------------------------------------------------ #
    def get_user_names(self, user_ids: list[int]) -> dict[int, tuple[str, str]]:
        """Имена пользователей (в long poll их нет — добираем отдельно)."""
        ids = [int(x) for x in user_ids if x]
        if not ids:
            return {}
        try:
            rows = self.call("users.get", {"user_ids": ",".join(str(i) for i in ids)}) or []
        except (VKError, VKTransportError) as exc:
            log.warning("users.get не удался: %s", exc)
            return {}
        out = {}
        for row in rows:
            if not isinstance(row, dict):
                continue
            try:
                uid = int(row.get("id", 0))
            except (TypeError, ValueError):
                continue
            if uid:
                out[uid] = (row.get("first_name") or "", row.get("last_name") or "")
        return out

    def get_group_info(self) -> dict:
        info = self.call("groups.getById", {"group_id": self.group_id})
        if isinstance(info, list) and info:
            return info[0]
        return {}

    def get_long_poll_server(self) -> dict:
        return self.call(
            "groups.getLongPollServer", {"group_id": self.group_id, "lp_version": 3}
        ) or {}


class LongPoll:
    """Bots Long Poll: бесконечный итератор событий с авто-переподключением."""

    def __init__(self, vk: VK, wait: int = 25, stop_event=None):
        self.vk = vk
        self.wait = wait
        self.stop_event = stop_event
        self._server = ""
        self._key = ""
        self._ts: Any = ""

    def _refresh(self, full: bool = True) -> None:
        info = self.vk.get_long_poll_server()
        if full:
            self._server = info.get("server", "")
            self._key = info.get("key", "")
        else:
            self._key = info.get("key", self._key)
        self._ts = info.get("ts", "")
        if not self._server or not self._key:
            raise VKTransportError(
                "Не получил long poll сервер. Проверьте, что в сообществе включён "
                "Long Poll API (см. docs/VK_SETUP.md)"
            )

    def events(self) -> Iterator[dict]:
        """Генератор событий. Не падает при обрыве связи — переподключается."""
        backoff = 1.0
        while True:
            if self.stop_event is not None and self.stop_event.is_set():
                return
            if not self._server or not self._key:
                try:
                    self._refresh()
                    backoff = 1.0
                except (VKError, VKTransportError) as exc:
                    log.error("Long poll: %s — повтор через %.0fs", exc, backoff)
                    self._sleep(backoff)
                    backoff = min(60.0, backoff * 2)
                    continue

            url = (
                f"{self._server}?act=a_check&key={urllib.parse.quote(self._key)}"
                f"&ts={self._ts}&wait={self.wait}"
            )
            try:
                req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
                with urllib.request.urlopen(req, timeout=self.wait + 15) as resp:
                    payload = json.loads(resp.read().decode("utf-8", "replace"))
                backoff = 1.0
            except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
                log.warning("Long poll: обрыв связи (%s), переподключаюсь", exc)
                self._sleep(backoff)
                backoff = min(60.0, backoff * 2)
                self._server = ""  # заставит _refresh() отработать заново
                continue

            failed = payload.get("failed")
            if failed in (1, "1"):
                self._ts = payload.get("ts", self._ts)
                continue
            if failed in (2, "2"):
                log.warning("Long poll: ключ устарел, получаю новый")
                self._refresh(full=False)
                continue
            if failed in (3, "3"):
                log.warning("Long poll: потеряна сессия, переподключаюсь")
                self._refresh(full=True)
                continue
            if failed:
                log.error("Long poll: неизвестный failed=%s", failed)
                self._sleep(5)
                self._refresh()
                continue

            self._ts = payload.get("ts", self._ts)
            for event in payload.get("updates", []) or []:
                if isinstance(event, dict):
                    yield event

    def _sleep(self, seconds: float) -> None:
        if self.stop_event is not None:
            self.stop_event.wait(seconds)
        else:
            time.sleep(seconds)
