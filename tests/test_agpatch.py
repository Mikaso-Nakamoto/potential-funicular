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


# --------------------------------------------------------------------------
# doctor: the whole point is that these two are NOT the same problem
# --------------------------------------------------------------------------
def test_doctor_separates_client_gate_from_server_geo():
    from agpatch.doctor import CLIENT_GATE, SERVER_GEO, diagnose

    local = diagnose('{"code": 400, "message": "Your current account is not eligible for Antigravity"}')
    assert local and local.category == CLIENT_GATE and local.patcher_action == "patch"

    server = diagnose("Error 400: User location is not supported for the API use.")
    assert server and server.category == SERVER_GEO
    assert server.patcher_action == "route"
    assert "IP" in server.meaning


def test_doctor_account_errors_say_do_not_patch():
    from agpatch.doctor import diagnose

    for text in (
        "You do not have a valid license of this product (#3501)",
        "403 Forbidden / SUBSCRIPTION_REQUIRED",
        "429 RESOURCE_EXHAUSTED",
    ):
        diag = diagnose(text)
        assert diag is not None and diag.patcher_action == "none", text


def test_doctor_oauth_exchange_is_transport():
    from agpatch.doctor import TRANSPORT, diagnose

    diag = diagnose("Failed to exchange authorization code for token")
    assert diag and diag.category == TRANSPORT
    assert any("DIRECT" in step for step in diag.steps)


def test_doctor_unknown_and_empty():
    from agpatch.doctor import diagnose

    assert diagnose("") is None
    assert diagnose("something entirely unrelated happened") is None


def test_doctor_cli(capsys):
    from agpatch.cli import main

    assert main(["doctor", "User location is not supported for the API use"]) == 0
    out = capsys.readouterr().out
    assert "route" in out and "NOT patch" in out
    assert main(["doctor"]) == 2
    assert main(["doctor", "??? nonsense ???"]) == 1


# --------------------------------------------------------------------------
# route: only the two API hosts, everything else direct
# --------------------------------------------------------------------------
def test_pac_decision_is_narrow():
    from agpatch.route import DIRECT_HOSTS, GATED_HOSTS, pac_decision

    for host in GATED_HOSTS:
        assert pac_decision(host) == "PROXY"
        assert pac_decision(host.upper()) == "PROXY"
        assert pac_decision("eu." + host) == "PROXY"  # subdomain
    for host in DIRECT_HOSTS:
        assert pac_decision(host) == "DIRECT"
    for host in ("google.com", "cloudcode-pa.googleapis.com.evil.test", "example.org"):
        assert pac_decision(host) == "DIRECT"


def test_pac_file_is_valid_js_and_only_gates_two_hosts():
    from agpatch.route import GATED_HOSTS, render_pac

    pac = render_pac("PROXY 127.0.0.1:8899")
    assert pac.count('"') % 2 == 0
    assert 'return "DIRECT";' in pac
    for host in GATED_HOSTS:
        assert host in pac
    assert "accounts.google.com" not in pac


def test_route_build_and_check(tmp_path, capsys):
    from agpatch.cli import main

    out = tmp_path / "p.pac"
    assert main(["route", "build", "--out", str(out), "--proxy", "PROXY 127.0.0.1:9999"]) == 0
    assert out.is_file() and "127.0.0.1:9999" in out.read_text()
    assert main(["route", "check"]) == 0
    assert "PROXY" in capsys.readouterr().out


def test_env_url_conversion():
    import sys as _sys

    from agpatch.route import env_url, platform_plan

    assert env_url("PROXY 127.0.0.1:8899") == "http://127.0.0.1:8899"
    assert env_url("http://10.0.0.1:3128") == "http://10.0.0.1:3128"
    assert env_url("127.0.0.1:8899") == "http://127.0.0.1:8899"
    # no PAC syntax leaking into env vars, on any platform's plan
    for platform in ("win32", "darwin", "linux"):
        plan = "\n".join(platform_plan("PROXY 127.0.0.1:8899", "/tmp/p.pac", platform=platform))
        for line in plan.splitlines():
            if "export HTTP" in line or "export HTTPS" in line:
                assert "PROXY " not in line


def test_route_plan_has_no_hosts_file_edits():
    from agpatch.route import render_plan

    plan = render_plan()
    assert "cloudcode-pa.googleapis.com" in plan
    assert "accounts.google.com" in plan
    lowered = plan.lower()
    assert "/etc/hosts" not in lowered and "hosts file" not in lowered
    assert "nrpt" not in lowered


def test_upstream_spec_parsing():
    from agpatch.route import UpstreamError, _parse_upstream

    assert _parse_upstream("socks://127.0.0.1:1080") == ("socks5", "127.0.0.1", 1080)
    assert _parse_upstream("socks5h://host:9050") == ("socks5", "host", 9050)
    assert _parse_upstream("http://10.0.0.1:3128") == ("http", "10.0.0.1", 3128)
    assert _parse_upstream("127.0.0.1:8080") == ("http", "127.0.0.1", 8080)
    for bad in ("socks://noport", "ftp://x:1", "host:abc"):
        with pytest.raises(UpstreamError):
            _parse_upstream(bad)


def test_proxy_tunnel_end_to_end(tmp_path):
    """Real sockets: echo server <- socks5-less http upstream <- agpatch proxy <- client."""
    import asyncio
    import socket
    import threading

    async def scenario():
        # 1) target echo server
        async def echo(reader, writer):
            data = await reader.read(100)
            writer.write(b"pong:" + data)
            await writer.drain()
            writer.close()

        target = await asyncio.start_server(echo, "127.0.0.1", 0)
        target_port = target.sockets[0].getsockname()[1]

        # 2) upstream CONNECT proxy (minimal)
        async def upstream(reader, writer):
            await reader.readline()
            while True:
                line = await reader.readline()
                if line in (b"\r\n", b""):
                    break
            up_r, up_w = await asyncio.open_connection("127.0.0.1", target_port)
            writer.write(b"HTTP/1.1 200 OK\r\n\r\n")
            await writer.drain()

            async def pump(a, b):
                try:
                    while chunk := await a.read(4096):
                        b.write(chunk)
                        await b.drain()
                except Exception:
                    pass

            await asyncio.gather(pump(reader, up_w), pump(up_r, writer))
            writer.close()

        up_srv = await asyncio.start_server(upstream, "127.0.0.1", 0)
        up_port = up_srv.sockets[0].getsockname()[1]

        # 3) start agpatch proxy on a free port
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        listen_port = sock.getsockname()[1]
        sock.close()
        logs = []
        task = asyncio.create_task(
            __import__("agpatch.route", fromlist=["serve"]).serve(
                f"127.0.0.1:{listen_port}", f"http://127.0.0.1:{up_port}", logs.append,
                allow_hosts=["example.test"],
            )
        )
        await asyncio.sleep(0.15)

        # 4) client: CONNECT through agpatch, then talk plaintext
        reader, writer = await asyncio.open_connection("127.0.0.1", listen_port)
        writer.write(f"CONNECT example.test:443 HTTP/1.1\r\nHost: example.test\r\n\r\n".encode())
        await writer.drain()
        status = await reader.readline()
        assert status.startswith(b"HTTP/1.1 200"), status
        while (line := await reader.readline()) not in (b"\r\n", b""):
            pass
        writer.write(b"hello")
        await writer.drain()
        reply = await reader.read(100)
        writer.close()

        task.cancel()
        target.close()
        up_srv.close()
        await asyncio.sleep(0.05)
        return reply, logs

    reply, logs = asyncio.run(scenario())
    assert reply == b"pong:hello"
    assert any("example.test:443" in line for line in logs)


def test_proxy_refuses_hosts_outside_the_allowlist():
    """Sign-in hosts must never leave through the egress, even if misconfigured."""
    import asyncio
    import socket

    async def scenario():
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
        sock.close()
        logs = []
        task = asyncio.create_task(
            __import__("agpatch.route", fromlist=["serve"]).serve(
                f"127.0.0.1:{port}", "http://127.0.0.1:1", logs.append
            )
        )
        await asyncio.sleep(0.15)
        reader, writer = await asyncio.open_connection("127.0.0.1", port)
        writer.write(b"CONNECT accounts.google.com:443 HTTP/1.1\r\n\r\n")
        await writer.drain()
        status = await reader.readline()
        writer.close()
        task.cancel()
        await asyncio.sleep(0.05)
        return status, logs

    status, logs = asyncio.run(scenario())
    assert b"403" in status
    assert any("not in allowlist" in line for line in logs)


def test_proxy_returns_502_when_upstream_is_dead(tmp_path):
    import asyncio
    import socket

    async def scenario():
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
        sock.close()
        logs = []
        task = asyncio.create_task(
            __import__("agpatch.route", fromlist=["serve"]).serve(
                f"127.0.0.1:{port}", "http://127.0.0.1:1", logs.append,
                allow_hosts=["x.test"],
            )
        )
        await asyncio.sleep(0.15)
        reader, writer = await asyncio.open_connection("127.0.0.1", port)
        writer.write(b"CONNECT x.test:443 HTTP/1.1\r\n\r\n")
        await writer.drain()
        status = await reader.readline()
        writer.close()
        task.cancel()
        await asyncio.sleep(0.05)
        return status, logs

    status, logs = asyncio.run(scenario())
    assert b"502" in status
    assert any("upstream failed" in line for line in logs)


# --------------------------------------------------------------------------
# opt-in string patch
# --------------------------------------------------------------------------
def test_string_patch_is_opt_in(tmp_path):
    body = fill(512) + b"ineligible" + fill(512, seed=3)
    target = write(tmp_path, "language_server", body)

    default = scan(MANAGER, target)
    assert "manager/string" not in {g.group for g in default.gates}

    explicit = scan(MANAGER, target, strings=True)
    assert "manager/string" in {g.group for g in explicit.gates}


def test_string_patch_applies_equal_length(tmp_path):
    # a real target needs both the instruction gate and the literal
    body = fill(400) + MANAGER_SITE + fill(64, seed=2) + b"ineligible" + fill(400, seed=3)
    target = write(tmp_path, "language_server", body)
    before = target.read_bytes()
    result = patch(MANAGER, target, strings=True, ledger=Ledger(tmp_path / "s.json"))
    assert result.ok, result.message
    after = target.read_bytes()
    assert len(after) == len(before)
    assert b"inexigible" in after and b"ineligible" not in after
    assert restore(target, ledger=Ledger(tmp_path / "s.json")).ok
    assert target.read_bytes() == before


def test_string_patch_refuses_absurd_occurrence_count(tmp_path):
    body = fill(400) + MANAGER_SITE + b"ineligible" * 50
    target = write(tmp_path, "language_server", body)
    result = patch(MANAGER, target, strings=True, ledger=Ledger(tmp_path / "s.json"))
    assert not result.ok and "ambiguous" in result.message
