"""SQLite-хранилище: клиенты, заявки, напоминания, очередь уведомлений.

Одно соединение на процесс + блокировка (нагрузка маленькая: десятки сообщений
в минуту), WAL-режим, чтобы чтение не блокировало запись.

Все даты храним как локальные строки 'YYYY-MM-DDTHH:MM:SS' в часовом поясе бота
(config -> bot.timezone). Часовой пояс после начала работы лучше не менять.
"""

from __future__ import annotations

import json
import sqlite3
import threading
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Iterable, Sequence

from .util import from_iso, to_iso

SCHEMA = """
CREATE TABLE IF NOT EXISTS clients (
    vk_id      INTEGER PRIMARY KEY,
    first_name TEXT DEFAULT '',
    last_name  TEXT DEFAULT '',
    phone      TEXT DEFAULT '',
    note       TEXT DEFAULT '',
    created_at TEXT NOT NULL,
    last_seen  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS client_state (
    vk_id      INTEGER PRIMARY KEY,
    state      TEXT NOT NULL DEFAULT 'idle',
    data       TEXT NOT NULL DEFAULT '{}',
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS requests (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    client_vk_id  INTEGER NOT NULL,
    service_id    TEXT NOT NULL,
    service_title TEXT NOT NULL,
    starts_at     TEXT NOT NULL,
    ends_at       TEXT NOT NULL,
    duration      INTEGER NOT NULL,
    price         INTEGER NOT NULL DEFAULT 0,
    client_name   TEXT NOT NULL DEFAULT '',
    contact       TEXT NOT NULL DEFAULT '',
    comment       TEXT NOT NULL DEFAULT '',
    status        TEXT NOT NULL DEFAULT 'pending',
    created_at    TEXT NOT NULL,
    decided_at    TEXT,
    reject_reason TEXT DEFAULT '',
    cancelled_by  TEXT DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_requests_status   ON requests(status, starts_at);
CREATE INDEX IF NOT EXISTS idx_requests_client   ON requests(client_vk_id, status);
CREATE INDEX IF NOT EXISTS idx_requests_starts   ON requests(starts_at);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_active_slot
    ON requests(client_vk_id, starts_at)
    WHERE status IN ('pending', 'confirmed');

CREATE TABLE IF NOT EXISTS reminders (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id INTEGER NOT NULL,
    kind       TEXT NOT NULL,
    send_at    TEXT NOT NULL,
    sent_at    TEXT,
    attempts   INTEGER NOT NULL DEFAULT 0,
    UNIQUE(request_id, kind)
);

CREATE INDEX IF NOT EXISTS idx_reminders_due ON reminders(sent_at, send_at);

CREATE TABLE IF NOT EXISTS blocked (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    starts_at  TEXT NOT NULL,
    ends_at    TEXT NOT NULL,
    note       TEXT DEFAULT '',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS day_off (
    date       TEXT PRIMARY KEY,
    note       TEXT DEFAULT '',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS outbox (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id    INTEGER NOT NULL,
    text       TEXT NOT NULL DEFAULT '',
    keyboard   TEXT DEFAULT '',
    attempts   INTEGER NOT NULL DEFAULT 0,
    last_error TEXT DEFAULT '',
    created_at TEXT NOT NULL,
    send_after TEXT,
    sent_at    TEXT
);

CREATE INDEX IF NOT EXISTS idx_outbox_due ON outbox(sent_at, send_after, id);

CREATE TABLE IF NOT EXISTS kv (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
);
"""

STATUS_PENDING = "pending"
STATUS_CONFIRMED = "confirmed"
STATUS_REJECTED = "rejected"
STATUS_CANCELLED = "cancelled"
STATUS_EXPIRED = "expired"
STATUS_COMPLETED = "completed"

ACTIVE_STATUSES = (STATUS_PENDING, STATUS_CONFIRMED)
BUSY_STATUSES = (STATUS_PENDING, STATUS_CONFIRMED)

STATUS_RU = {
    STATUS_PENDING: "ждёт подтверждения",
    STATUS_CONFIRMED: "подтверждена",
    STATUS_REJECTED: "отклонена",
    STATUS_CANCELLED: "отменена",
    STATUS_EXPIRED: "истекла",
    STATUS_COMPLETED: "завершена",
}


@dataclass
class Request:
    id: int
    client_vk_id: int
    service_id: str
    service_title: str
    starts_at: datetime
    ends_at: datetime
    duration: int
    price: int = 0
    client_name: str = ""
    contact: str = ""
    comment: str = ""
    status: str = STATUS_PENDING
    created_at: datetime | None = None
    decided_at: datetime | None = None
    reject_reason: str = ""
    cancelled_by: str = ""

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "Request":
        def dt(value: Any) -> datetime | None:
            return from_iso(value) if value else None

        return cls(
            id=row["id"],
            client_vk_id=row["client_vk_id"],
            service_id=row["service_id"],
            service_title=row["service_title"],
            starts_at=from_iso(row["starts_at"]),
            ends_at=from_iso(row["ends_at"]),
            duration=row["duration"],
            price=row["price"] or 0,
            client_name=row["client_name"] or "",
            contact=row["contact"] or "",
            comment=row["comment"] or "",
            status=row["status"],
            created_at=dt(row["created_at"]),
            decided_at=dt(row["decided_at"]),
            reject_reason=row["reject_reason"] or "",
            cancelled_by=row["cancelled_by"] or "",
        )

    @property
    def status_ru(self) -> str:
        return STATUS_RU.get(self.status, self.status)

    @property
    def is_active(self) -> bool:
        return self.status in ACTIVE_STATUSES


@dataclass
class Reminder:
    id: int
    request_id: int
    kind: str
    send_at: datetime
    attempts: int = 0


@dataclass
class OutboxItem:
    id: int
    peer_id: int
    text: str
    keyboard: dict | None = None
    attempts: int = 0


class Database:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._conn = sqlite3.connect(
            str(self.path), check_same_thread=False, isolation_level=None
        )
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._conn.execute("PRAGMA busy_timeout=5000")
        self._execute_script(SCHEMA)

    # ------------------------------------------------------------------ #
    # базовые обёртки
    # ------------------------------------------------------------------ #
    def _execute_script(self, script: str) -> None:
        with self._lock:
            self._conn.executescript(script)

    def _query(self, sql: str, params: Sequence = ()) -> list[sqlite3.Row]:
        with self._lock:
            return list(self._conn.execute(sql, params).fetchall())

    def _one(self, sql: str, params: Sequence = ()) -> sqlite3.Row | None:
        rows = self._query(sql, params)
        return rows[0] if rows else None

    def _write(self, sql: str, params: Sequence = ()) -> int:
        with self._lock:
            cur = self._conn.execute(sql, params)
            return cur.lastrowid or cur.rowcount

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    # ------------------------------------------------------------------ #
    # клиенты
    # ------------------------------------------------------------------ #
    def upsert_client(
        self, vk_id: int, first_name: str = "", last_name: str = "", now: datetime | None = None
    ) -> None:
        now = now or datetime.now()
        iso = to_iso(now)
        with self._lock:
            self._conn.execute(
                """
                INSERT INTO clients (vk_id, first_name, last_name, created_at, last_seen)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(vk_id) DO UPDATE SET
                    first_name = excluded.first_name,
                    last_name  = excluded.last_name,
                    last_seen  = excluded.last_seen
                """,
                (vk_id, first_name or "", last_name or "", iso, iso),
            )

    def get_client(self, vk_id: int) -> sqlite3.Row | None:
        return self._one("SELECT * FROM clients WHERE vk_id = ?", (vk_id,))

    def set_client_phone(self, vk_id: int, phone: str) -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE clients SET phone = ? WHERE vk_id = ?", (phone, vk_id)
            )

    def client_display_name(self, vk_id: int) -> str:
        row = self.get_client(vk_id)
        if not row:
            return f"id{vk_id}"
        full = " ".join(x for x in (row["first_name"], row["last_name"]) if x)
        return full or f"id{vk_id}"

    def clients_count(self) -> int:
        row = self._one("SELECT COUNT(*) AS c FROM clients")
        return int(row["c"]) if row else 0

    # ------------------------------------------------------------------ #
    # состояние диалога
    # ------------------------------------------------------------------ #
    def get_state(self, vk_id: int) -> tuple[str, dict]:
        row = self._one("SELECT state, data FROM client_state WHERE vk_id = ?", (vk_id,))
        if not row:
            return "idle", {}
        try:
            data = json.loads(row["data"] or "{}")
        except json.JSONDecodeError:
            data = {}
        return row["state"], data if isinstance(data, dict) else {}

    def set_state(self, vk_id: int, state: str, data: dict | None = None,
                  now: datetime | None = None) -> None:
        iso = to_iso(now or datetime.now())
        payload = json.dumps(data or {}, ensure_ascii=False)
        with self._lock:
            self._conn.execute(
                """
                INSERT INTO client_state (vk_id, state, data, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(vk_id) DO UPDATE SET
                    state = excluded.state, data = excluded.data,
                    updated_at = excluded.updated_at
                """,
                (vk_id, state, payload, iso),
            )

    def clear_state(self, vk_id: int) -> None:
        self.set_state(vk_id, "idle", {})

    # ------------------------------------------------------------------ #
    # заявки
    # ------------------------------------------------------------------ #
    def create_request(
        self,
        client_vk_id: int,
        service_id: str,
        service_title: str,
        starts_at: datetime,
        duration: int,
        price: int = 0,
        client_name: str = "",
        contact: str = "",
        comment: str = "",
        now: datetime | None = None,
    ) -> Request:
        """Атомарно создаёт заявку. Бросает SlotConflict, если слот занят."""
        now = now or datetime.now()
        ends_at = starts_at + timedelta(minutes=duration)
        with self._lock:
            self._conn.execute("BEGIN IMMEDIATE")
            try:
                busy = self._busy_intervals_locked(starts_at, ends_at)
                if busy:
                    raise SlotConflict(starts_at, busy)
                cur = self._conn.execute(
                    """
                    INSERT INTO requests (
                        client_vk_id, service_id, service_title, starts_at, ends_at,
                        duration, price, client_name, contact, comment, status, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        client_vk_id,
                        service_id,
                        service_title,
                        to_iso(starts_at),
                        to_iso(ends_at),
                        duration,
                        price,
                        client_name,
                        contact,
                        comment,
                        STATUS_PENDING,
                        to_iso(now),
                    ),
                )
                self._conn.execute("COMMIT")
            except Exception:
                self._conn.execute("ROLLBACK")
                raise
        return self.get_request(cur.lastrowid)  # type: ignore[return-value]

    def get_request(self, request_id: int) -> Request | None:
        row = self._one("SELECT * FROM requests WHERE id = ?", (request_id,))
        return Request.from_row(row) if row else None

    def list_requests(
        self,
        statuses: Iterable[str] | None = None,
        since: datetime | None = None,
        until: datetime | None = None,
        client_vk_id: int | None = None,
        limit: int = 200,
    ) -> list[Request]:
        sql = "SELECT * FROM requests WHERE 1=1"
        params: list[Any] = []
        if statuses:
            marks = ",".join("?" for _ in statuses)
            sql += f" AND status IN ({marks})"
            params.extend(statuses)
        if since:
            sql += " AND starts_at >= ?"
            params.append(to_iso(since))
        if until:
            sql += " AND starts_at < ?"
            params.append(to_iso(until))
        if client_vk_id is not None:
            sql += " AND client_vk_id = ?"
            params.append(client_vk_id)
        sql += " ORDER BY starts_at ASC LIMIT ?"
        params.append(limit)
        return [Request.from_row(r) for r in self._query(sql, params)]

    def count_active(self, client_vk_id: int) -> int:
        marks = ",".join("?" for _ in ACTIVE_STATUSES)
        row = self._one(
            f"SELECT COUNT(*) AS c FROM requests WHERE client_vk_id = ? AND status IN ({marks})",
            (client_vk_id, *ACTIVE_STATUSES),
        )
        return int(row["c"]) if row else 0

    def set_status(
        self,
        request_id: int,
        status: str,
        now: datetime | None = None,
        reject_reason: str = "",
        cancelled_by: str = "",
    ) -> Request | None:
        now = now or datetime.now()
        with self._lock:
            self._conn.execute(
                """
                UPDATE requests
                   SET status = ?, decided_at = ?, reject_reason = ?, cancelled_by = ?
                 WHERE id = ?
                """,
                (status, to_iso(now), reject_reason, cancelled_by, request_id),
            )
        return self.get_request(request_id)

    def reschedule_request(
        self, request_id: int, starts_at: datetime, now: datetime | None = None
    ) -> Request | None:
        """Переносит запись на новое время (длительность услуги не меняется)."""
        req = self.get_request(request_id)
        if not req:
            return None
        ends_at = starts_at + timedelta(minutes=req.duration)
        with self._lock:
            self._conn.execute("BEGIN IMMEDIATE")
            try:
                busy = [
                    pair
                    for pair in self._busy_intervals_locked(starts_at, ends_at)
                    if pair != (req.starts_at, req.ends_at)
                ]
                if busy:
                    raise SlotConflict(starts_at, busy)
                self._conn.execute(
                    "UPDATE requests SET starts_at = ?, ends_at = ? WHERE id = ?",
                    (to_iso(starts_at), to_iso(ends_at), request_id),
                )
                self._conn.execute("COMMIT")
            except Exception:
                self._conn.execute("ROLLBACK")
                raise
        return self.get_request(request_id)

    def pending_older_than(self, cutoff: datetime) -> list[Request]:
        rows = self._query(
            "SELECT * FROM requests WHERE status = ? AND created_at < ? ORDER BY id",
            (STATUS_PENDING, to_iso(cutoff)),
        )
        return [Request.from_row(r) for r in rows]

    def finished_before(self, moment: datetime) -> list[Request]:
        rows = self._query(
            "SELECT * FROM requests WHERE status = ? AND ends_at < ? ORDER BY id",
            (STATUS_CONFIRMED, to_iso(moment)),
        )
        return [Request.from_row(r) for r in rows]

    def _busy_intervals_locked(
        self, starts_at: datetime, ends_at: datetime
    ) -> list[tuple[datetime, datetime]]:
        """Вызывать внутри транзакции. Пересечения с занятыми интервалами."""
        marks = ",".join("?" for _ in BUSY_STATUSES)
        rows = self._conn.execute(
            f"""
            SELECT starts_at, ends_at FROM requests
             WHERE status IN ({marks}) AND starts_at < ? AND ends_at > ?
            UNION ALL
            SELECT starts_at, ends_at FROM blocked
             WHERE starts_at < ? AND ends_at > ?
            """,
            (*BUSY_STATUSES, to_iso(ends_at), to_iso(starts_at), to_iso(ends_at), to_iso(starts_at)),
        ).fetchall()
        return [(from_iso(r["starts_at"]), from_iso(r["ends_at"])) for r in rows]

    def busy_intervals(
        self, since: datetime, until: datetime, include_pending: bool = True
    ) -> list[tuple[datetime, datetime]]:
        statuses = BUSY_STATUSES if include_pending else (STATUS_CONFIRMED,)
        marks = ",".join("?" for _ in statuses)
        rows = self._query(
            f"""
            SELECT starts_at, ends_at FROM requests
             WHERE status IN ({marks}) AND starts_at < ? AND ends_at > ?
            UNION ALL
            SELECT starts_at, ends_at FROM blocked
             WHERE starts_at < ? AND ends_at > ?
            """,
            (*statuses, to_iso(until), to_iso(since), to_iso(until), to_iso(since)),
        )
        return [(from_iso(r["starts_at"]), from_iso(r["ends_at"])) for r in rows]

    def stats(self, since: datetime | None = None) -> dict[str, int]:
        sql = "SELECT status, COUNT(*) AS c FROM requests"
        params: list[Any] = []
        if since:
            sql += " WHERE created_at >= ?"
            params.append(to_iso(since))
        sql += " GROUP BY status"
        out = {row["status"]: int(row["c"]) for row in self._query(sql, params)}
        out["total"] = sum(out.values())
        return out

    # ------------------------------------------------------------------ #
    # выходные и занятые интервалы
    # ------------------------------------------------------------------ #
    def add_day_off(self, date: datetime, note: str = "", now: datetime | None = None) -> None:
        self._write(
            "INSERT OR REPLACE INTO day_off (date, note, created_at) VALUES (?, ?, ?)",
            (date.strftime("%Y-%m-%d"), note, to_iso(now or datetime.now())),
        )

    def remove_day_off(self, date: datetime) -> bool:
        with self._lock:
            cur = self._conn.execute(
                "DELETE FROM day_off WHERE date = ?", (date.strftime("%Y-%m-%d"),)
            )
            return cur.rowcount > 0

    def is_day_off(self, date: datetime) -> bool:
        return (
            self._one("SELECT 1 AS x FROM day_off WHERE date = ?", (date.strftime("%Y-%m-%d"),))
            is not None
        )

    def list_day_off(self, since: datetime | None = None, limit: int = 60) -> list[datetime]:
        sql = "SELECT date FROM day_off"
        params: list[Any] = []
        if since:
            sql += " WHERE date >= ?"
            params.append(since.strftime("%Y-%m-%d"))
        sql += " ORDER BY date LIMIT ?"
        params.append(limit)
        return [from_iso(r["date"]) for r in self._query(sql, params)]

    def add_blocked(self, starts_at: datetime, ends_at: datetime, note: str = "",
                    now: datetime | None = None) -> int:
        return int(
            self._write(
                "INSERT INTO blocked (starts_at, ends_at, note, created_at) VALUES (?, ?, ?, ?)",
                (to_iso(starts_at), to_iso(ends_at), note, to_iso(now or datetime.now())),
            )
        )

    def remove_blocked(self, blocked_id: int) -> bool:
        with self._lock:
            cur = self._conn.execute("DELETE FROM blocked WHERE id = ?", (blocked_id,))
            return cur.rowcount > 0

    def list_blocked(self, since: datetime | None = None, limit: int = 60) -> list[sqlite3.Row]:
        sql = "SELECT id, starts_at, ends_at, note FROM blocked"
        params: list[Any] = []
        if since:
            sql += " WHERE ends_at >= ?"
            params.append(to_iso(since))
        sql += " ORDER BY starts_at LIMIT ?"
        params.append(limit)
        return self._query(sql, params)

    # ------------------------------------------------------------------ #
    # напоминания
    # ------------------------------------------------------------------ #
    def ensure_reminder(
        self, request_id: int, kind: str, send_at: datetime, now: datetime | None = None
    ) -> bool:
        """Создаёт напоминание, если такого ещё нет. True = создано."""
        if send_at <= (now or datetime.now()):
            return False
        try:
            with self._lock:
                self._conn.execute(
                    """
                    INSERT INTO reminders (request_id, kind, send_at) VALUES (?, ?, ?)
                    """,
                    (request_id, kind, to_iso(send_at)),
                )
            return True
        except sqlite3.IntegrityError:
            return False

    def due_reminders(self, now: datetime, limit: int = 50) -> list[tuple[Reminder, Request]]:
        """Напоминания, которые пора отправить, вместе с их заявками.

        Колонки напоминания специально переименованы: иначе `q.*` перекрывает
        `id`, и заявка собиралась бы с id напоминания.
        """
        rows = self._query(
            """
            SELECT r.id           AS reminder_id,
                   r.request_id   AS reminder_request_id,
                   r.kind         AS reminder_kind,
                   r.send_at      AS reminder_send_at,
                   r.attempts     AS reminder_attempts,
                   q.*
              FROM reminders r JOIN requests q ON q.id = r.request_id
             WHERE r.sent_at IS NULL AND r.send_at <= ?
             ORDER BY r.send_at, r.id LIMIT ?
            """,
            (to_iso(now), limit),
        )
        out = []
        for row in rows:
            rem = Reminder(
                id=row["reminder_id"],
                request_id=row["reminder_request_id"],
                kind=row["reminder_kind"],
                send_at=from_iso(row["reminder_send_at"]),
                attempts=row["reminder_attempts"],
            )
            req = Request.from_row(row)
            assert req.id == rem.request_id, "id заявки и напоминания разошлись"
            out.append((rem, req))
        return out

    def mark_reminder_sent(self, reminder_id: int, now: datetime | None = None) -> None:
        self._write(
            "UPDATE reminders SET sent_at = ? WHERE id = ?",
            (to_iso(now or datetime.now()), reminder_id),
        )

    def bump_reminder(self, reminder_id: int) -> None:
        self._write("UPDATE reminders SET attempts = attempts + 1 WHERE id = ?", (reminder_id,))

    def drop_reminders(self, request_id: int, kinds: Iterable[str] | None = None) -> None:
        if kinds:
            marks = ",".join("?" for _ in kinds)
            self._write(
                f"DELETE FROM reminders WHERE request_id = ? AND kind IN ({marks})",
                (request_id, *kinds),
            )
        else:
            self._write("DELETE FROM reminders WHERE request_id = ?", (request_id,))

    # ------------------------------------------------------------------ #
    # очередь исходящих (уведомления переживают перезапуск)
    # ------------------------------------------------------------------ #
    def enqueue_message(
        self,
        peer_id: int,
        text: str,
        keyboard: dict | None = None,
        send_after: datetime | None = None,
        now: datetime | None = None,
    ) -> int:
        return int(
            self._write(
                """
                INSERT INTO outbox (peer_id, text, keyboard, created_at, send_after)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    peer_id,
                    text,
                    json.dumps(keyboard, ensure_ascii=False) if keyboard else "",
                    to_iso(now or datetime.now()),
                    to_iso(send_after) if send_after else None,
                ),
            )
        )

    def due_messages(self, now: datetime, limit: int = 20) -> list[OutboxItem]:
        rows = self._query(
            """
            SELECT id, peer_id, text, keyboard, attempts FROM outbox
             WHERE sent_at IS NULL AND (send_after IS NULL OR send_after <= ?)
             ORDER BY id LIMIT ?
            """,
            (to_iso(now), limit),
        )
        out = []
        for row in rows:
            kb = None
            if row["keyboard"]:
                try:
                    kb = json.loads(row["keyboard"])
                except json.JSONDecodeError:
                    kb = None
            out.append(
                OutboxItem(
                    id=row["id"],
                    peer_id=row["peer_id"],
                    text=row["text"],
                    keyboard=kb,
                    attempts=row["attempts"],
                )
            )
        return out

    def mark_message_sent(self, outbox_id: int, now: datetime | None = None) -> None:
        self._write(
            "UPDATE outbox SET sent_at = ?, attempts = attempts + 1 WHERE id = ?",
            (to_iso(now or datetime.now()), outbox_id),
        )

    def mark_message_failed(self, outbox_id: int, error: str) -> None:
        self._write(
            "UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?",
            (error[:500], outbox_id),
        )

    def defer_message(self, outbox_id: int, send_after: datetime) -> None:
        """Отложить отправку (используется для повторов после ошибок)."""
        self._write(
            "UPDATE outbox SET send_after = ? WHERE id = ?",
            (to_iso(send_after), outbox_id),
        )

    def outbox_pending_count(self) -> int:
        row = self._one("SELECT COUNT(*) AS c FROM outbox WHERE sent_at IS NULL")
        return int(row["c"]) if row else 0

    def purge_sent(self, older_than: datetime) -> int:
        with self._lock:
            cur = self._conn.execute(
                "DELETE FROM outbox WHERE sent_at IS NOT NULL AND sent_at < ?",
                (to_iso(older_than),),
            )
            return cur.rowcount

    # ------------------------------------------------------------------ #
    # kv
    # ------------------------------------------------------------------ #
    def kv_get(self, key: str, default: str = "") -> str:
        row = self._one("SELECT value FROM kv WHERE key = ?", (key,))
        return row["value"] if row else default

    def kv_set(self, key: str, value: str) -> None:
        self._write(
            "INSERT INTO kv (key, value) VALUES (?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, str(value)),
        )


class SlotConflict(Exception):
    """Слот уже занят другой заявкой/подтверждённой записью."""

    def __init__(self, starts_at: datetime, busy: list[tuple[datetime, datetime]] | None = None):
        self.starts_at = starts_at
        self.busy = busy or []
        super().__init__(f"Слот {starts_at} занят")
