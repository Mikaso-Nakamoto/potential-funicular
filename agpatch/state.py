"""State and backups.

One rule drives everything here: *the only thing we ever write back is a byte
copy of a file that we verified was unpatched at the moment we took it*. That
makes a "backup" a pristine copy by construction, so restore can never put a
patched build back on top of a clean one.

Every record also stores the hash of the file we produced, so ``agpatch
restore`` can tell you whether the file is still the patched one (safe) or has
been replaced since (restoring would be a deliberate downgrade).
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, Optional

BACKUP_SUFFIX = ".agbak"
STATE_VERSION = 1


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def state_dir() -> Path:
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        return Path(base) / "agpatch"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "agpatch"
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "agpatch"


def state_path() -> Path:
    return state_dir() / "state.json"


@dataclass
class FileRecord:
    kind: str
    path: str
    backup: str
    pre_sha256: str
    post_sha256: str
    size: int
    at: str = ""
    app_version: Optional[str] = None
    gates: list = field(default_factory=list)

    def __post_init__(self) -> None:
        if not self.at:
            self.at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class Ledger:
    """Tiny JSON ledger. Read-modify-write, no locking — one user, one shell."""

    def __init__(self, path: Optional[Path] = None) -> None:
        self.path = path or state_path()
        self.data: Dict[str, Any] = {"version": STATE_VERSION, "files": {}}
        self._load()

    def _load(self) -> None:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        if isinstance(raw, dict) and isinstance(raw.get("files"), dict):
            self.data = raw

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.data, indent=2, sort_keys=True), encoding="utf-8")
        os.replace(tmp, self.path)

    # -- records ----------------------------------------------------------
    def get(self, path: Path) -> Optional[FileRecord]:
        raw = self.data["files"].get(str(path))
        if not raw:
            return None
        try:
            return FileRecord(**raw)
        except TypeError:
            return None

    def put(self, record: FileRecord) -> None:
        self.data["files"][record.path] = asdict(record)
        self.save()

    def forget(self, path: Path) -> None:
        self.data["files"].pop(str(path), None)
        self.save()

    def records(self) -> list[FileRecord]:
        out = []
        for raw in self.data["files"].values():
            try:
                out.append(FileRecord(**raw))
            except TypeError:
                continue
        return out


def backup_path_for(path: Path) -> Path:
    return path.with_name(path.name + BACKUP_SUFFIX)


def write_backup(path: Path, pristine: bytes) -> Path:
    """Write a pristine copy next to the target with tight permissions."""
    backup = backup_path_for(path)
    tmp = backup.with_suffix(backup.suffix + ".tmp")
    with open(tmp, "wb") as fh:
        fh.write(pristine)
        fh.flush()
        os.fsync(fh.fileno())
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, backup)
    return backup


def atomic_write(path: Path, data: bytes) -> None:
    """Write in place via temp file + rename, preserving mode and owner.

    Patching a file that is currently *mapped* by a running process is safe on
    POSIX (the kernel keeps the old inode) but not on Windows, so there we
    write straight through the existing handle.
    """
    if sys.platform == "win32":
        with open(path, "r+b") as fh:
            fh.seek(0)
            fh.write(data)
            fh.truncate()
            fh.flush()
            os.fsync(fh.fileno())
        return

    st = path.stat()
    tmp = path.with_name(path.name + ".agpatch-tmp")
    try:
        with open(tmp, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, st.st_mode & 0o7777)
        if hasattr(os, "chown"):
            try:
                os.chown(tmp, st.st_uid, st.st_gid)
            except OSError:
                pass
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass


def backup_is_pristine(record: FileRecord) -> bool:
    backup = Path(record.backup)
    if not backup.is_file():
        return False
    return sha256_file(backup) == record.pre_sha256
