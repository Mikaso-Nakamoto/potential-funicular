"""Target discovery — where the Antigravity binaries actually live.

Discovery never guesses silently: every candidate is returned together with
why it was considered, and ``agpatch scan`` shows you the list before anything
is touched. ``--path`` always overrides discovery.
"""

from __future__ import annotations

import os
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional

from .gates import CLI, IDE, MANAGER, VSCODE

MANAGER_NAMES = ("language_server.exe", "language_server")
CLI_NAMES = ("agy.exe", "agy", "antigravity.exe", "antigravity")


@dataclass(frozen=True)
class Candidate:
    kind: str
    path: Path
    origin: str

    def __str__(self) -> str:
        return f"{self.kind}: {self.path} ({self.origin})"


def _home() -> Path:
    return Path(os.path.expanduser("~"))


def _dedupe(items: Iterable[Candidate]) -> List[Candidate]:
    seen = set()
    out: List[Candidate] = []
    for item in items:
        key = (item.kind, str(item.path))
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out


# --------------------------------------------------------------------------
# IDE: resources/app/out/main.js inside an install root
# --------------------------------------------------------------------------
def _main_js_under(root: Path) -> Optional[Path]:
    p = root / "resources" / "app" / "out" / "main.js"
    return p if p.is_file() else None


def _ide_roots() -> List[tuple[Path, str]]:
    roots: List[tuple[Path, str]] = []
    home = _home()
    if sys.platform == "win32":
        for var in ("LOCALAPPDATA", "PROGRAMFILES", "PROGRAMFILES(X86)", "ProgramData", "APPDATA"):
            base = os.environ.get(var)
            if not base:
                continue
            for name in ("Antigravity IDE", "Antigravity", "Programs\\Antigravity IDE"):
                roots.append((Path(base) / name, f"%{var}%\\{name}"))
        for name in ("Antigravity IDE", "Antigravity"):
            roots.append((home / "AppData" / "Local" / "Programs" / name, "user install"))
    elif sys.platform == "darwin":
        roots += [
            (Path("/Applications/Antigravity IDE.app"), "system app"),
            (home / "Applications" / "Antigravity IDE.app", "user app"),
            (Path("/Applications/Antigravity.app"), "system app"),
        ]
    else:
        roots += [
            (Path("/usr/share/antigravity-ide"), "system install"),
            (Path("/usr/share/antigravity"), "system install"),
            (Path("/opt/antigravity-ide"), "opt install"),
            (Path("/opt/Antigravity IDE"), "opt install"),
            (home / ".local" / "share" / "antigravity-ide", "user install"),
            (home / ".local" / "share" / "antigravity", "user install"),
        ]
    return roots


def find_ide(explicit: Optional[Path] = None) -> List[Candidate]:
    out: List[Candidate] = []
    if explicit:
        p = explicit
        if p.is_file() and p.name == "main.js":
            out.append(Candidate(IDE, p, "--path"))
        else:
            found = _main_js_under(p)
            if found:
                out.append(Candidate(IDE, found, "--path"))
        return out
    for root, origin in _ide_roots():
        found = _main_js_under(root)
        if found:
            out.append(Candidate(IDE, found, origin))
    return _dedupe(out)


# --------------------------------------------------------------------------
# Binary targets
# --------------------------------------------------------------------------
def _owned_dirs() -> List[Path]:
    home = _home()
    dirs = [Path("/usr/local/bin"), Path("/usr/bin"), Path("/bin"), Path("/opt/homebrew/bin")]
    dirs += [home / ".local" / "bin", home / "bin"]
    if sys.platform == "win32":
        for var in ("LOCALAPPDATA", "APPDATA", "ProgramFiles", "ProgramData", "USERPROFILE"):
            base = os.environ.get(var)
            if base:
                dirs.append(Path(base))
        dirs += [
            home / "AppData" / "Local" / "Programs" / "Antigravity",
            home / "AppData" / "Local" / "Antigravity",
        ]
    elif sys.platform == "darwin":
        dirs += [
            Path("/Applications/Antigravity.app/Contents/Resources/bin"),
            Path("/Applications/Antigravity 2.0.app/Contents/Resources/bin"),
            home / "Library" / "Application Support" / "Antigravity",
            home / ".gemini" / "bin",
        ]
    else:
        dirs += [
            Path("/opt/antigravity"),
            Path("/opt/antigravity/bin"),
            Path("/usr/lib/antigravity"),
            home / ".gemini" / "bin",
        ]
    return dirs


def _search_names(names: Iterable[str], dirs: Iterable[Path], depth_limit: int = 3) -> List[Path]:
    found: List[Path] = []
    for name in names:
        hit = shutil.which(name)
        if hit:
            found.append(Path(hit))
    for directory in dirs:
        for name in names:
            candidate = directory / name
            if candidate.is_file():
                found.append(candidate)
    return found


def find_manager(explicit: Optional[Path] = None) -> List[Candidate]:
    if explicit:
        if explicit.is_file():
            return [Candidate(MANAGER, explicit, "--path")]
        out = []
        for name in MANAGER_NAMES:
            p = explicit / name
            if p.is_file():
                out.append(Candidate(MANAGER, p, "--path"))
        return out
    dirs = _owned_dirs()
    hits = _search_names(MANAGER_NAMES, dirs)
    return [Candidate(MANAGER, p, "search") for p in hits]


def find_cli(explicit: Optional[Path] = None) -> List[Candidate]:
    if explicit:
        if explicit.is_file():
            return [Candidate(CLI, explicit, "--path")]
        out = []
        for name in CLI_NAMES:
            p = explicit / name
            if p.is_file():
                out.append(Candidate(CLI, p, "--path"))
        return out
    dirs = _owned_dirs() + [_home() / ".gemini" / "bin"]
    hits = _search_names(CLI_NAMES, dirs)
    return [Candidate(CLI, p, "search") for p in hits]


# --------------------------------------------------------------------------
# VS Code / Cursor / Windsurf extension
# --------------------------------------------------------------------------
def _extension_roots() -> List[Path]:
    home = _home()
    roots = [
        home / ".vscode" / "extensions",
        home / ".vscode-insiders" / "extensions",
        home / ".vscode-server" / "extensions",
        home / ".cursor" / "extensions",
        home / ".windsurf" / "extensions",
    ]
    if sys.platform == "win32":
        appdata = os.environ.get("USERPROFILE")
        if appdata:
            base = Path(appdata)
            roots += [
                base / ".vscode" / "extensions",
                base / ".vscode-insiders" / "extensions",
                base / ".cursor" / "extensions",
            ]
    return roots


def find_vscode(explicit: Optional[Path] = None) -> List[Candidate]:
    if explicit:
        if explicit.is_file():
            return [Candidate(VSCODE, explicit, "--path")]
        for name in ("extension.js", "dist/extension.js"):
            p = explicit / name
            if p.is_file():
                return [Candidate(VSCODE, p, "--path")]
        return []
    out: List[Candidate] = []
    for root in _extension_roots():
        if not root.is_dir():
            continue
        for ext_dir in sorted(root.glob("google.google-antigravity-*")):
            for rel in ("dist/extension.js", "extension.js"):
                p = ext_dir / rel
                if p.is_file():
                    out.append(Candidate(VSCODE, p, f"{root.name} extension"))
                    break
    return _dedupe(out)


FINDERS = {
    IDE: find_ide,
    MANAGER: find_manager,
    CLI: find_cli,
    VSCODE: find_vscode,
}


def discover(kinds: Iterable[str], explicit: Optional[Path] = None) -> tuple[List[Candidate], List[str]]:
    """Return (candidates, notes) where notes explain empty categories."""
    candidates: List[Candidate] = []
    notes: List[str] = []
    for kind in kinds:
        found = FINDERS[kind](explicit)
        if not found:
            notes.append(f"{kind}: not found")
        candidates.extend(found)
    return _dedupe(candidates), notes
