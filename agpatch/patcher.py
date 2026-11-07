"""Inspect (scan), patch, restore.

Patch flow, deliberately boring:

1. read the whole file
2. evaluate every gate for the target
3. if anything is ambiguous -> refuse, change nothing
4. compute the patched image *in memory*
5. verify the patched image reads back as fully patched
6. write a pristine backup (recorded with hashes)
7. atomically replace the file
8. re-read from disk and verify again, else roll back

Size is never allowed to change for binary targets. Symlinks are refused.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence

from .gates import BINARY_PROFILES, TEXT_GATES, Gate, TextGate, gates_for
from .hexsig import SigError, apply_fix, spans_overlap
from .state import (
    FileRecord,
    Ledger,
    atomic_write,
    backup_path_for,
    sha256_bytes,
    sha256_file,
    write_backup,
)

PATCHED = "patched"
UNPATCHED = "unpatched"
AMBIGUOUS = "ambiguous"
ABSENT = "absent"

BINARY_KINDS = set(BINARY_PROFILES)
TEXT_KINDS = set(TEXT_GATES)


PARTIAL = "partial"
UNSUPPORTED = "unsupported"


@dataclass
class GateReport:
    key: str
    desc: str
    state: str
    offset: int = -1
    error: str = ""
    group: str = ""

    @property
    def ok(self) -> bool:
        return self.state in (PATCHED, UNPATCHED)


@dataclass
class Report:
    kind: str
    path: Path
    arch: str
    gates: List[GateReport] = field(default_factory=list)
    error: str = ""
    app_version: Optional[str] = None

    @property
    def states(self) -> set:
        return {g.state for g in self.gates}

    @property
    def groups(self) -> Dict[str, str]:
        """Verdict per logical gate group (see ``Gate.group``)."""
        buckets: Dict[str, List[GateReport]] = {}
        for gate in self.gates:
            buckets.setdefault(gate.group, []).append(gate)
        out: Dict[str, str] = {}
        for name, members in buckets.items():
            states = {m.state for m in members}
            if AMBIGUOUS in states:
                out[name] = AMBIGUOUS
                continue
            # ABSENT siblings are "not this build's encoding" and never count.
            applicable = states - {ABSENT}
            if not applicable:
                out[name] = UNSUPPORTED
            elif applicable <= {PATCHED}:
                out[name] = PATCHED
            elif PATCHED in applicable or PARTIAL in applicable:
                out[name] = PARTIAL
            else:
                out[name] = UNPATCHED
        return out

    @property
    def blocking(self) -> List[str]:
        """Groups we refuse to touch: ambiguous matches, or nothing recognised.

        ``PARTIAL`` (some sites patched, some not) is not blocking — completing
        it is exactly what a re-run is for.
        """
        return [
            name
            for name, state in self.groups.items()
            if state in (AMBIGUOUS, UNSUPPORTED)
        ]

    def summary(self) -> str:
        if self.error:
            return self.error
        if not self.gates:
            return "no gates"
        states = set(self.groups.values())
        if states == {PATCHED}:
            return "patched"
        if states == {UNPATCHED}:
            return "clean"
        if AMBIGUOUS in states:
            return "ambiguous signature"
        if states == {UNSUPPORTED}:
            return "unsupported"
        if PATCHED in states or PARTIAL in states:
            return "partially patched"
        return "unsupported"


def _read(path: Path) -> bytes:
    if path.is_symlink():
        raise SigError(f"refusing to modify a symlink: {path}")
    if not path.is_file():
        raise SigError(f"not a regular file: {path}")
    return path.read_bytes()


def _binary_report(kind: str, path: Path, data: bytes, arch: str) -> Report:
    report = Report(kind=kind, path=path, arch=arch)
    for gate in gates_for(kind, arch):
        try:
            state, offset = gate.sig.match(data)
        except Exception as exc:  # malformed signature is a bug, surface it
            report.gates.append(GateReport(gate.key, gate.desc, ABSENT, error=str(exc), group=gate.group))
            continue
        report.gates.append(GateReport(gate.key, gate.desc, state, offset, group=gate.group))
    return report


def _text_report(kind: str, path: Path, text: str) -> Report:
    report = Report(kind=kind, path=path, arch="js")
    for gate in TEXT_GATES[kind]:
        state, offset = gate.match(text)
        report.gates.append(GateReport(gate.key, gate.desc, state, offset, group=gate.group))
    return report


def scan(kind: str, path: Path, arch: str = "any") -> Report:
    try:
        raw = _read(path)
    except (OSError, SigError) as exc:
        return Report(kind=kind, path=path, arch=arch, error=str(exc))

    if kind in TEXT_KINDS:
        return _text_report(kind, path, raw.decode("utf-8", errors="replace"))

    target_arch = arch
    if target_arch == "any":
        target_arch = _guess_arch(raw)
    report = _binary_report(kind, path, raw, target_arch)
    if not any(g.state != ABSENT for g in report.gates) and arch == "any":
        # Nothing matched under the guessed arch — try the other one and say so.
        other = "arm64" if target_arch == "x64" else "x64"
        alt = _binary_report(kind, path, raw, other)
        if any(g.state != ABSENT for g in alt.gates):
            return alt
    return report


def _guess_arch(data: bytes) -> str:
    """PE/ELF/Mach-O machine field. Falls back to host arch."""
    import platform
    import struct

    if data[:2] == b"MZ" and len(data) > 0x40:
        pe_off = struct.unpack_from("<I", data, 0x3C)[0]
        if data[pe_off : pe_off + 4] == b"PE\0\0":
            machine = struct.unpack_from("<H", data, pe_off + 4)[0]
            if machine == 0x8664:
                return "x64"
            if machine == 0xAA64:
                return "arm64"
    if data[:4] == b"\x7fELF" and len(data) > 20:
        machine = struct.unpack_from("<H", data, 18)[0]
        if machine == 62:
            return "x64"
        if machine == 183:
            return "arm64"
    if data[:4] in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
        machine = struct.unpack_from("<I", data, 4)[0]
        if machine in (0x01000007, 0x00000007):
            return "x64"
        if machine in (0x0100000C, 0x0000000C):
            return "arm64"
    if data[:4] == b"\xca\xfe\xba\xbe":
        return "universal"
    return "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "x64"


def _build_binary_image(data: bytes, report: Report) -> tuple[bytearray, List[str]]:
    image = bytearray(data)
    applied: List[str] = []
    spans: List[tuple] = []
    for gate_report in report.gates:
        if gate_report.state != UNPATCHED:
            continue
        gate = _gate_by_key(gate_report.key)
        apply_fix(image, gate_report.offset, gate.sig.fix)
        spans.append((gate_report.offset, gate_report.offset + len(gate.sig.fix)))
        applied.append(gate.key)
    if spans_overlap(spans):
        raise SigError("two gates would write overlapping bytes — refusing")
    if len(image) != len(data):
        raise SigError("patch changed the file size — refusing")
    return image, applied


def _gate_by_key(key: str) -> Gate:
    for arch_map in BINARY_PROFILES.values():
        for gates in arch_map.values():
            for gate in gates:
                if gate.key == key:
                    return gate
    raise KeyError(key)


def _build_text_image(text: str, report: Report) -> tuple[str, List[str]]:
    image = text
    applied: List[str] = []
    for gate_report in report.gates:
        if gate_report.state != UNPATCHED:
            continue
        gate = next(g for g in TEXT_GATES[report.kind] if g.key == gate_report.key)
        image = gate.apply(image)
        applied.append(gate.key)
    return image, applied


@dataclass
class PatchResult:
    ok: bool
    message: str
    applied: List[str] = field(default_factory=list)
    backup: Optional[Path] = None
    dry_run: bool = False


def patch(kind: str, path: Path, arch: str = "any", dry_run: bool = False,
          ledger: Optional[Ledger] = None) -> PatchResult:
    ledger = ledger or Ledger()
    report = scan(kind, path, arch)
    if report.error:
        return PatchResult(False, report.error)

    blocking = report.blocking
    if blocking:
        detail = "; ".join(
            f"{name}: {report.groups[name]}"
            for name in blocking
        )
        return PatchResult(False, f"refusing to patch — {detail}")
    if not report.gates:
        return PatchResult(False, "no gates defined for this target")
    if set(report.groups.values()) == {PATCHED}:
        return PatchResult(True, "already patched — nothing to do")

    raw = _read(path)
    if kind in BINARY_KINDS:
        try:
            image, applied = _build_binary_image(raw, report)
        except SigError as exc:
            return PatchResult(False, str(exc))
        out_bytes = bytes(image)
        verify = _binary_report(kind, path, out_bytes, report.arch or "any")
    else:
        image, applied = _build_text_image(raw.decode("utf-8"), report)
        out_bytes = image.encode("utf-8")
        verify = _text_report(kind, path, image)

    bad = [g for g in verify.gates if g.state not in (PATCHED, ABSENT)]
    if bad:
        detail = "; ".join(f"{g.key}: {g.state}" for g in bad)
        return PatchResult(False, f"internal check failed, nothing written — {detail}")

    if dry_run:
        return PatchResult(True, "dry run: patch is valid, nothing written", applied, dry_run=True)

    pre_sha = sha256_bytes(raw)
    if path.is_symlink():
        return PatchResult(False, f"refusing to modify a symlink: {path}")
    backup = write_backup(path, raw)
    if sha256_file(backup) != pre_sha:
        return PatchResult(False, "backup verification failed, nothing written")

    atomic_write(path, out_bytes)
    post_sha = sha256_bytes(out_bytes)

    disk = scan(kind, path, arch)
    if set(disk.groups.values()) != {PATCHED}:
        # Roll back immediately; we still hold the pristine bytes.
        atomic_write(path, raw)
        return PatchResult(False, "post-write verification failed — file rolled back")

    ledger.put(
        FileRecord(
            kind=kind,
            path=str(path),
            backup=str(backup),
            pre_sha256=pre_sha,
            post_sha256=post_sha,
            size=len(raw),
            gates=applied,
        )
    )
    return PatchResult(True, f"patched {len(applied)} gate(s)", applied, backup)


@dataclass
class RestoreResult:
    ok: bool
    message: str
    force_required: bool = False


def restore(path: Path, ledger: Optional[Ledger] = None, force: bool = False) -> RestoreResult:
    ledger = ledger or Ledger()
    record = ledger.get(path)
    backup = Path(record.backup) if record and record.backup else backup_path_for(path)

    if not backup.is_file():
        return RestoreResult(False, f"no backup at {backup}")
    if path.is_symlink():
        return RestoreResult(False, f"refusing to modify a symlink: {path}")

    pristine = backup.read_bytes()
    if record and sha256_bytes(pristine) != record.pre_sha256:
        return RestoreResult(False, f"backup {backup.name} does not match its recorded hash")

    current_sha = sha256_file(path) if path.is_file() else ""
    if record and current_sha and current_sha != record.post_sha256 and not force:
        return RestoreResult(
            False,
            "file changed since patching (app updated?) — restoring would put an old "
            "build back. Use --force to restore anyway",
            force_required=True,
        )
    if record and current_sha == record.pre_sha256:
        return RestoreResult(True, "already clean — nothing to do")

    atomic_write(path, pristine)
    if sha256_file(path) != sha256_bytes(pristine):
        return RestoreResult(False, "restore verification failed")
    ledger.forget(path)
    return RestoreResult(True, f"restored from {backup.name}")
