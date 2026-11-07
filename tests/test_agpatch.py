"""End-to-end tests on synthetic images.

The point is not "does the signature match the README" — it is that the safety
properties hold: refuse on unknown/ambiguous input, never change file size,
always leave a verified pristine backup, always roll back on failure.
"""

from __future__ import annotations

import hashlib
import random
from pathlib import Path

import pytest

from agpatch import patcher
from agpatch.gates import CLI, IDE, MANAGER, VSCODE
from agpatch.hexsig import ByteSig, SigError, parse, spans_overlap
from agpatch.patcher import patch, restore, scan
from agpatch.state import Ledger


# --------------------------------------------------------------------------
# synthetic binaries
# --------------------------------------------------------------------------
IDE_GATE = b"resetIsTierGCPTos(),this.aB3.isGoogleInternal"
MANAGER_SITE = bytes.fromhex("80 78 08 00 74 12 48 8b 44 24 08 48 89 44 24 60")
CLI_SITE = bytes.fromhex("48 85 c0 0f 84 11 22 33 44 80 78 08 00 0f 85 aa bb cc dd 90 90 90 90")
ARM64_MGR_SITE = bytes.fromhex("03 20 40 39 03 00 00 36 1f 20 03 d5 03 10 06 a9")


def fill(n: int, seed: int = 7) -> bytes:
    rnd = random.Random(seed)
    return bytes(rnd.randrange(256) for _ in range(n))


def make_binary(site: bytes, size: int = 4096, seed: int = 7) -> bytes:
    body = fill(size, seed)
    at = size // 3
    return body[:at] + site + body[at + len(site) :]


def write(tmp_path: Path, name: str, data: bytes) -> Path:
    p = tmp_path / name
    p.write_bytes(data)
    return p


@pytest.fixture()
def ledger(tmp_path) -> Ledger:
    return Ledger(tmp_path / "state.json")


# --------------------------------------------------------------------------
# signature language
# --------------------------------------------------------------------------
def test_parse_tokens():
    tokens = parse("de ad ?? [00-0f] [01 21]")
    assert tokens[0] == 0xDE and tokens[2] is None
    assert tokens[3] == ((0, 15),)
    assert tokens[4] == ((1, 1), (0x21, 0x21))


def test_parse_rejects_garbage():
    for bad in ("", "zz", "0", "[00-ff", "[]"):
        with pytest.raises(SigError):
            parse(bad)


def test_fix_must_fit_signature():
    with pytest.raises(SigError):
        ByteSig(pattern="90 90", fix=b"\x01\x02\x03")
    with pytest.raises(SigError):
        ByteSig(pattern="90 90", fix=b"")
    with pytest.raises(SigError):
        ByteSig(pattern="90 90", fix=b"\x01", offset=-1)


def test_overlap_detection():
    assert spans_overlap([(0, 6), (4, 10)])
    assert not spans_overlap([(0, 6), (6, 10)])


def test_state_machine():
    sig = ByteSig(pattern="80 78 08 00 74 ?? 90 90", fix=bytes.fromhex("c640080190"), offset=0)
    assert sig.match(b"\x00" * 32) == ("absent", -1)
    assert sig.match(b"\x00" * 8 + bytes.fromhex("80 78 08 00 74 01 90 90")) == ("unpatched", 8)
    assert sig.match(b"\x00" * 8 + bytes.fromhex("c6 40 08 01 90 90 90 90")) == ("patched", 8)
    doubled = bytes.fromhex("80 78 08 00 74 01 90 90") * 2
    assert sig.match(doubled) == ("ambiguous", -1)


# --------------------------------------------------------------------------
# scan
# --------------------------------------------------------------------------
def test_scan_states(tmp_path):
    clean = write(tmp_path, "language_server", make_binary(MANAGER_SITE))
    assert scan(MANAGER, clean).summary() == "clean"
    patch(MANAGER, clean, ledger=Ledger(tmp_path / "s.json"))
    assert scan(MANAGER, clean).summary() == "patched"


def test_scan_missing_file(tmp_path):
    report = scan(CLI, tmp_path / "nope")
    assert report.error and report.summary() == report.error


def test_scan_unsupported_version(tmp_path):
    unknown = write(tmp_path, "agy", fill(2048))
    report = scan(CLI, unknown)
    assert report.summary() == "unsupported"


def test_scan_symlink_refused(tmp_path):
    real = write(tmp_path, "real", make_binary(CLI_SITE))
    link = tmp_path / "link"
    link.symlink_to(real)
    assert "symlink" in scan(CLI, link).error


# --------------------------------------------------------------------------
# patch: happy path
# --------------------------------------------------------------------------
def test_patch_manager_x64(tmp_path):
    target = write(tmp_path, "language_server", make_binary(MANAGER_SITE))
    before = target.read_bytes()
    result = patch(MANAGER, target, ledger=Ledger(tmp_path / "s.json"))
    assert result.ok, result.message

    after = target.read_bytes()
    assert len(after) == len(before)                       # size preserved
    assert after.count(bytes.fromhex("c64008019090")) == 1  # fix applied once
    assert bytes.fromhex("80 78 08 00 74") not in after     # original gone
    # everything outside the patched span is byte-identical
    at = result.applied and before.index(MANAGER_SITE)
    assert after[:at] == before[:at]
    assert after[at + 6 :] == before[at + 6 :]


def test_patch_cli_x64_offset(tmp_path):
    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    result = patch(CLI, target, ledger=Ledger(tmp_path / "s.json"))
    assert result.ok, result.message
    out = target.read_bytes()
    at = out.index(bytes.fromhex("4885c0900f85"))
    assert out[at : at + 4] == bytes.fromhex("4885c090")   # cmp replaced
    assert out[at + 4 : at + 6] == bytes.fromhex("0f85")   # jne untouched
    assert bytes.fromhex("4885c00f8411223344") in out      # leading test/je untouched


def test_patch_arm64_manager(tmp_path):
    target = write(tmp_path, "language_server", make_binary(ARM64_MGR_SITE))
    result = patch(MANAGER, target, arch="arm64", ledger=Ledger(tmp_path / "s.json"))
    assert result.ok, result.message
    assert bytes.fromhex("2300805203200039") in target.read_bytes()


def test_patch_is_idempotent(tmp_path):
    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    ledger = Ledger(tmp_path / "s.json")
    assert patch(CLI, target, ledger=ledger).ok
    patched = target.read_bytes()
    second = patch(CLI, target, ledger=ledger)
    assert second.ok and "already patched" in second.message
    assert target.read_bytes() == patched


def test_patch_ide_js(tmp_path):
    target = write(tmp_path, "main.js", b"var x=1;" + IDE_GATE + b";var y=2;")
    result = patch(IDE, target, ledger=Ledger(tmp_path / "s.json"))
    assert result.ok, result.message
    text = target.read_text()
    assert "resetIsTierGCPTos(),true" in text and "isGoogleInternal" not in text


def test_patch_vscode_js(tmp_path):
    js = b"const isChannelChanged = manifestFetched && lastInstalledUrl !== releaseBaseUrl;"
    target = write(tmp_path, "extension.js", js)
    result = patch(VSCODE, target, ledger=Ledger(tmp_path / "s.json"))
    assert result.ok, result.message
    assert "const isChannelChanged = false;" in target.read_text()


# --------------------------------------------------------------------------
# patch: refusals
# --------------------------------------------------------------------------
def test_patch_refuses_unknown_version(tmp_path):
    target = write(tmp_path, "agy", fill(2048))
    before = target.read_bytes()
    result = patch(CLI, target, ledger=Ledger(tmp_path / "s.json"))
    assert not result.ok and "refusing" in result.message
    assert target.read_bytes() == before


def test_patch_refuses_ambiguous(tmp_path):
    doubled = MANAGER_SITE + fill(64) + MANAGER_SITE
    target = write(tmp_path, "language_server", make_binary(doubled, size=8192))
    before = target.read_bytes()
    result = patch(MANAGER, target, ledger=Ledger(tmp_path / "s.json"))
    assert not result.ok and "ambiguous" in result.message
    assert target.read_bytes() == before
    assert not (tmp_path / "language_server.agbak").exists()


def test_dry_run_writes_nothing(tmp_path):
    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    before = target.read_bytes()
    result = patch(CLI, target, dry_run=True, ledger=Ledger(tmp_path / "s.json"))
    assert result.ok and result.dry_run
    assert target.read_bytes() == before
    assert not (tmp_path / "agy.agbak").exists()
    assert not (tmp_path / "s.json").exists()


def test_rollback_when_write_lands_wrong(tmp_path, monkeypatch):
    """If the bytes on disk do not read back as patched, revert immediately."""
    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    before = target.read_bytes()

    real_write = patcher.atomic_write
    calls = {"n": 0}

    def bad_write(path, data):
        calls["n"] += 1
        if calls["n"] == 1:       # the patch write silently lands wrong
            return real_write(path, before)
        return real_write(path, data)  # the rollback write behaves normally

    monkeypatch.setattr(patcher, "atomic_write", bad_write)
    result = patch(CLI, target, ledger=Ledger(tmp_path / "s.json"))
    assert not result.ok and "rolled back" in result.message
    assert target.read_bytes() == before
    assert calls["n"] == 2


def test_absent_sibling_does_not_block(tmp_path):
    """arm64b is simply 'not this build's encoding' — it must not block arm64a."""
    target = write(tmp_path, "language_server", make_binary(ARM64_MGR_SITE))
    report = scan(MANAGER, target, arch="arm64")
    assert report.groups == {"manager": "unpatched"}
    assert any(g.state == "absent" for g in report.gates)


def test_two_sites_in_one_group_are_both_patched(tmp_path):
    """CLI >= 1.2.7 has an outer gate plus an inlined copy: both must go."""
    w1 = bytes.fromhex("13 00 00 b5 05 00 00 b4 01 20 40 39 01 00 00 37")
    w2 = bytes.fromhex("01 00 00 b5 00 00 00 b4 02 20 40 39 02 00 00 37")
    body = bytes(2048) + w1 + bytes(64) + w2 + bytes(2048)
    target = write(tmp_path, "agy", body)

    report = scan(CLI, target, arch="arm64")
    states = {g.key: g.state for g in report.gates}
    assert states["cli/eligibility/arm64w1"] == "unpatched"
    assert states["cli/eligibility/arm64w2"] == "unpatched"
    assert report.summary() == "clean"

    result = patch(CLI, target, arch="arm64", ledger=Ledger(tmp_path / "s.json"))
    assert result.ok, result.message
    assert len(result.applied) == 2
    out = target.read_bytes()
    assert bytes.fromhex("21008052") in out and bytes.fromhex("22008052") in out
    assert scan(CLI, target, arch="arm64").summary() == "patched"


def test_partially_patched_group_is_completed(tmp_path):
    w1 = bytes.fromhex("13 00 00 b5 05 00 00 b4 01 20 40 39 01 00 00 37")
    w2 = bytes.fromhex("01 00 00 b5 00 00 00 b4 02 20 40 39 02 00 00 37")
    # w1 already carries its fix, w2 does not
    body = bytes(2048) + w1.replace(bytes.fromhex("01204039"), bytes.fromhex("21008052")) \
        + bytes(64) + w2 + bytes(2048)
    target = write(tmp_path, "agy", body)
    assert scan(CLI, target, arch="arm64").summary() == "partially patched"

    result = patch(CLI, target, arch="arm64", ledger=Ledger(tmp_path / "s.json"))
    assert result.ok, result.message
    assert result.applied == ["cli/eligibility/arm64w2"]
    assert scan(CLI, target, arch="arm64").summary() == "patched"


# --------------------------------------------------------------------------
# backups + restore
# --------------------------------------------------------------------------
def test_backup_is_pristine_and_verified(tmp_path):
    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    pristine = target.read_bytes()
    result = patch(CLI, target, ledger=Ledger(tmp_path / "s.json"))
    backup = Path(result.backup)
    assert backup.read_bytes() == pristine
    assert backup.stat().st_mode & 0o777 == 0o600


def test_restore_roundtrip(tmp_path):
    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    pristine = target.read_bytes()
    ledger = Ledger(tmp_path / "s.json")
    assert patch(CLI, target, ledger=ledger).ok
    result = restore(target, ledger=ledger)
    assert result.ok, result.message
    assert target.read_bytes() == pristine
    assert scan(CLI, target).summary() == "clean"
    assert ledger.get(target) is None


def test_restore_refuses_after_app_update(tmp_path):
    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    ledger = Ledger(tmp_path / "s.json")
    assert patch(CLI, target, ledger=ledger).ok
    # simulate a fresh install overwriting the patched file
    target.write_bytes(make_binary(CLI_SITE, seed=99))
    fresh = target.read_bytes()
    blocked = restore(target, ledger=ledger)
    assert not blocked.ok and blocked.force_required
    assert target.read_bytes() == fresh
    assert restore(target, ledger=ledger, force=True).ok


def test_restore_without_backup(tmp_path):
    target = write(tmp_path, "agy", fill(128))
    assert not restore(target, ledger=Ledger(tmp_path / "s.json")).ok


def test_restore_rejects_tampered_backup(tmp_path):
    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    ledger = Ledger(tmp_path / "s.json")
    result = patch(CLI, target, ledger=ledger)
    Path(result.backup).write_bytes(b"tampered")
    restored = restore(target, ledger=ledger)
    assert not restored.ok and "hash" in restored.message


def test_backup_not_overwritten_when_already_patched(tmp_path):
    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    ledger = Ledger(tmp_path / "s.json")
    first = patch(CLI, target, ledger=ledger)
    backup_bytes = Path(first.backup).read_bytes()
    second = patch(CLI, target, ledger=ledger)
    assert second.ok and "already patched" in second.message
    assert Path(first.backup).read_bytes() == backup_bytes


# --------------------------------------------------------------------------
# cli smoke
# --------------------------------------------------------------------------
def test_cli_scan_and_patch(tmp_path, capsys):
    from agpatch.cli import main

    target = write(tmp_path, "agy", make_binary(CLI_SITE))
    assert main(["scan", "--kind", "cli", "--path", str(target)]) == 0
    assert "clean" in capsys.readouterr().out

    assert main(["patch", "--kind", "cli", "--path", str(target), "--dry-run"]) == 0
    assert "dry run" in capsys.readouterr().out

    assert main(["gates"]) == 0
    assert "cli/eligibility/x64" in capsys.readouterr().out

    assert main(["probe", "--path", str(target)]) == 0
    assert "0x" in capsys.readouterr().out

    assert main(["scan", "--kind", "nonsense"]) == 2
