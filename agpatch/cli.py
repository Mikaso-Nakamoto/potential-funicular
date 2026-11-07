"""Command line interface.

    agpatch scan                # what is installed, what state it is in
    agpatch scan --kind cli
    agpatch patch --kind cli --dry-run
    agpatch patch --kind manager
    agpatch restore --all
    agpatch probe --kind cli --path ./agy --around 40

Nothing here elevates privileges, kills processes, edits the registry or
touches the network. If a file needs admin rights to write, you will get an
EACCES and you decide what to do about it.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path
from typing import List, Optional, Sequence

from . import doctor as doctor_mod
from . import route as route_mod
from .gates import CLI, IDE, KIND_LABELS, MANAGER, VSCODE, all_gates
from .patcher import ABSENT, PATCHED, UNPATCHED, patch, restore, scan
from .state import Ledger, backup_path_for, sha256_file
from .targets import discover

ALL_KINDS = (IDE, MANAGER, CLI, VSCODE)


def _kinds(value: Optional[str]) -> List[str]:
    if not value or value == "all":
        return list(ALL_KINDS)
    kinds = [v.strip() for v in value.split(",") if v.strip()]
    unknown = [k for k in kinds if k not in ALL_KINDS]
    if unknown:
        raise ValueError(f"unknown kind(s): {', '.join(unknown)} (use: {', '.join(ALL_KINDS)}, all)")
    return kinds


def _candidates(kinds: Sequence[str], path: Optional[Path]):
    candidates, notes = discover(kinds, path)
    return candidates, notes


def _print_scan(candidates, notes, wide: bool) -> int:
    if not candidates:
        print("Nothing found.")
        for note in notes:
            print(f"  note: {note}")
        print("\nUse --path to point at an install directory or a specific file.")
        return 1

    for candidate in candidates:
        report = scan(candidate.kind, candidate.path)
        print(f"[{KIND_LABELS.get(candidate.kind, candidate.kind)}]")
        print(f"  path   {candidate.path}")
        print(f"  found  {candidate.origin}")
        print(f"  arch   {report.arch}")
        if report.error:
            print(f"  error  {report.error}")
            continue
        print(f"  state  {report.summary()}")
        for name, state in sorted(report.groups.items()):
            print(f"    gate {name:<22} {state}")
        for gate in report.gates:
            if not wide and gate.state == ABSENT:
                continue
            where = f"0x{gate.offset:x}" if gate.offset >= 0 else "-"
            print(f"      . {gate.key:<28} {gate.state:<10} {where:>10}  {gate.desc}")
        if REPORT_ABSENT_HINT and any(g.state == ABSENT for g in report.gates):
            print("    (some gates absent — likely an unsupported version; run `agpatch probe`)")
        print()
    return 0


REPORT_ABSENT_HINT = True


def cmd_scan(args) -> int:
    try:
        kinds = _kinds(args.kind)
    except ValueError as exc:
        print(f"error: {exc}")
        return 2
    candidates, notes = _candidates(kinds, Path(args.path) if args.path else None)
    return _print_scan(candidates, notes, args.wide)


def cmd_patch(args) -> int:
    try:
        kinds = _kinds(args.kind)
    except ValueError as exc:
        print(f"error: {exc}")
        return 2
    candidates, notes = _candidates(kinds, Path(args.path) if args.path else None)
    if not candidates:
        for note in notes:
            print(f"note: {note}")
        print("Nothing to patch.")
        return 1

    ledger = Ledger()
    exit_code = 0
    for candidate in candidates:
        result = patch(
            candidate.kind,
            candidate.path,
            arch=args.arch,
            dry_run=args.dry_run,
            ledger=ledger,
            strings=args.experimental_strings,
        )
        tag = "OK  " if result.ok else "FAIL"
        print(f"{tag} {candidate.kind}: {candidate.path}")
        print(f"     {result.message}")
        if result.backup:
            print(f"     backup: {result.backup}")
        if not result.ok and "refusing" in result.message:
            exit_code = 2
        elif not result.ok:
            exit_code = exit_code or 1
        print()
    return exit_code


def cmd_restore(args) -> int:
    ledger = Ledger()
    targets: List[Path] = []
    if args.all:
        targets = [Path(r.path) for r in ledger.records()]
        if not targets:
            print("No patch records — nothing to restore.")
            return 1
    elif args.path:
        targets = [Path(args.path)]
    else:
        print("Specify --path or --all.")
        return 1

    exit_code = 0
    for target in targets:
        result = restore(target, ledger=ledger, force=args.force)
        if not result.ok and not result.force_required:
            exit_code = 1
        if not result.ok and result.force_required:
            exit_code = 2
        print(f"{'OK  ' if result.ok else 'FAIL'} {target}")
        print(f"     {result.message}")
        if not result.ok and result.force_required:
            backup = backup_path_for(target)
            print(f"     backup kept at {backup}")
        print()
    return exit_code


def cmd_probe(args) -> int:
    path = Path(args.path)
    if not path.is_file():
        print(f"not a file: {path}")
        return 1
    data = path.read_bytes()
    print(f"file   {path}")
    print(f"size   {len(data)} bytes")
    print(f"sha256 {sha256_file(path)}")
    print()
    gates = all_gates()
    for gate in gates:
        if hasattr(gate, "needle"):
            print(f"-- {gate.key}  ({gate.desc})")
            sites = data.count(gate.needle)
            print(f"   {gate.needle.decode('ascii', 'replace')!r} occurs {sites}x")
            start = data.find(gate.needle)
            if start >= 0:
                print(f"   first @ 0x{start:x}")
            print()
            continue
        if hasattr(gate, "sig"):
            print(f"-- {gate.key}  ({gate.desc})")
            print(f"   sig: {gate.sig.pattern}")
            print(f"   fix: {gate.sig.fix.hex()} @ +{gate.sig.offset}")
            for state, start in gate.sig.locate(data):
                print(f"   {state:<9} @ 0x{start:x}")
            print()
        else:
            try:
                text = data.decode("utf-8", errors="replace")
            except Exception:
                continue
            state, pos = gate.match(text)
            print(f"-- {gate.key}  ({gate.desc})")
            print(f"   {state} @ {pos if pos >= 0 else '-'}")
            print()
    return 0


def cmd_gates(args) -> int:
    for gate in all_gates():
        if hasattr(gate, "sig"):
            print(f"{gate.key:<28} {gate.target:<8} {gate.arch:<6} {gate.desc}")
            print(f"   sig {gate.sig.pattern}")
            print(f"   fix {gate.sig.fix.hex()} @ +{gate.sig.offset}")
        elif hasattr(gate, "needle"):
            print(f"{gate.key:<28} {gate.target:<8} {'bytes':<6} {gate.desc}")
            print(f"   {gate.needle.decode('ascii', 'replace')!r} -> {gate.replacement.decode('ascii', 'replace')!r}")
            print("   opt-in: only applied with --experimental-strings")
        else:
            print(f"{gate.key:<28} {'text':<8} {'js':<6} {gate.desc}")
            print(f"   re  {gate.pattern}")
        print(f"   src {gate.provenance}")
        print()
    return 0


def cmd_doctor(args) -> int:
    text = args.text
    if args.log:
        try:
            text = Path(args.log).read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            print(f"error: cannot read {args.log}: {exc}")
            return 2
    if not text:
        print("Paste the error text (or use --log FILE). Known codes:")
        print()
        for code, pattern in doctor_mod._RULES:
            print(f"  {code:<16} {pattern.pattern}")
        print()
        print("Example: agpatch doctor \"Error 400: User location is not supported for the API use\"")
        return 2
    diag = doctor_mod.diagnose(text)
    if diag is None:
        print("Not recognised — paste more of the message.")
        print("Known codes: " + ", ".join(code for code, _ in doctor_mod._RULES))
        return 1
    print(doctor_mod.format_diagnosis(diag))
    return 0


def cmd_route(args) -> int:
    if args.route_action == "plan":
        print(route_mod.render_plan(args.proxy, args.out))
        return 0

    if args.route_action == "build":
        text = route_mod.render_pac(args.proxy)
        out = Path(args.out)
        out.write_text(text, encoding="utf-8")
        print(f"wrote {out.resolve()}")
        print(f"diverted: {', '.join(route_mod.GATED_HOSTS)}")
        print("everything else: DIRECT")
        return 0

    if args.route_action == "check":
        hosts = args.host or list(route_mod.GATED_HOSTS) + list(route_mod.DIRECT_HOSTS)
        for host in hosts:
            print(f"{route_mod.pac_decision(host):<8} {host}")
        return 0

    if args.route_action == "proxy":
        return _run_proxy(args)

    print("use: plan | build | check | proxy")
    return 2


def _run_proxy(args) -> int:
    try:
        route_mod._parse_upstream(args.upstream)
    except route_mod.UpstreamError as exc:
        print(f"error: {exc}")
        return 2

    def log(message: str) -> None:
        print(f"[proxy] {message}", flush=True)

    allow_hosts = None if args.allow_all else route_mod.GATED_HOSTS
    try:
        asyncio.run(route_mod.serve(args.listen, args.upstream, log, allow_hosts=allow_hosts))
    except KeyboardInterrupt:
        print("\nstopped")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agpatch",
        description="Local region-gate patcher for Antigravity. Pristine backups, verified writes, no elevation, no network.",
    )
    parser.add_argument("--version", action="store_true", help="print version and exit")
    sub = parser.add_subparsers(dest="command")

    p_scan = sub.add_parser("scan", help="report installed targets and their state")
    p_scan.add_argument("--kind", help="ide,manager,cli,vscode (comma separated) or all")
    p_scan.add_argument("--path", help="explicit file or install directory")
    p_scan.add_argument("--wide", action="store_true", help="also show absent gates")
    p_scan.set_defaults(func=cmd_scan)

    p_patch = sub.add_parser("patch", help="apply the patch")
    p_patch.add_argument("--kind", help="ide,manager,cli,vscode (comma separated) or all")
    p_patch.add_argument("--path", help="explicit file or install directory")
    p_patch.add_argument("--arch", default="any", choices=["any", "x64", "arm64"])
    p_patch.add_argument("--dry-run", action="store_true", help="validate only, write nothing")
    p_patch.add_argument(
        "--experimental-strings",
        action="store_true",
        help="also apply opt-in equal-length string patches (see agpatch gates)",
    )
    p_patch.set_defaults(func=cmd_patch)

    p_restore = sub.add_parser("restore", help="restore from the pristine backup")
    p_restore.add_argument("--path", help="file to restore")
    p_restore.add_argument("--all", action="store_true", help="restore everything in the ledger")
    p_restore.add_argument("--force", action="store_true", help="restore even if the file changed since patching")
    p_restore.set_defaults(func=cmd_restore)

    p_probe = sub.add_parser("probe", help="hexdump-adjacent inspection of gate sites in a file")
    p_probe.add_argument("--path", required=True)
    p_probe.set_defaults(func=cmd_probe)

    p_gates = sub.add_parser("gates", help="list every gate, signature and fix without touching anything")
    p_gates.set_defaults(func=cmd_gates)

    p_doctor = sub.add_parser("doctor", help="tell client-gate errors from server/account errors")
    p_doctor.add_argument("text", nargs="?", help="the error text, quoted")
    p_doctor.add_argument("--log", help="read the error text from a file")
    p_doctor.set_defaults(func=cmd_doctor)

    p_route = sub.add_parser("route", help="split routing: two API hosts through an egress, rest direct")
    route_sub = p_route.add_subparsers(dest="route_action")

    r_plan = route_sub.add_parser("plan", help="print the whole plan with platform commands")
    r_plan.add_argument("--proxy", default="PROXY 127.0.0.1:8899")
    r_plan.add_argument("--out", default="./agpatch-proxy.pac")
    r_plan.set_defaults(func=cmd_route)

    r_build = route_sub.add_parser("build", help="write the PAC file")
    r_build.add_argument("--proxy", default="PROXY 127.0.0.1:8899")
    r_build.add_argument("--out", default="./agpatch-proxy.pac")
    r_build.set_defaults(func=cmd_route)

    r_check = route_sub.add_parser("check", help="show the PAC decision for hostnames")
    r_check.add_argument("--host", action="append", help="hostname (repeatable)")
    r_check.set_defaults(func=cmd_route)

    r_proxy = route_sub.add_parser("proxy", help="run the local CONNECT proxy")
    r_proxy.add_argument("--listen", default="127.0.0.1:8899")
    r_proxy.add_argument("--upstream", required=True, help="socks://host:port or http://host:port")
    r_proxy.add_argument(
        "--allow-all",
        action="store_true",
        help="forward any host, not just the two Cloud Code API hosts (not recommended)",
    )
    r_proxy.set_defaults(func=cmd_route)

    p_route.set_defaults(func=cmd_route, route_action="plan", proxy="PROXY 127.0.0.1:8899",
                         out="./agpatch-proxy.pac", listen="127.0.0.1:8899", upstream="", host=None,
                         allow_all=False)

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    from . import __version__

    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "version", False):
        print(f"agpatch {__version__}")
        return 0
    if not getattr(args, "func", None):
        parser.print_help()
        return 0
    return args.func(args)


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
