"""The gate table: what we look for, what we write, and where it came from.

Nothing here is magic. Each entry documents the instruction pair being
neutralised and the public write-up it was transcribed from.

IMPORTANT: signatures are version-specific. They are marked ``VERIFIED`` only
when they were checked against a real binary of a known release. Everything
shipped here is ``UNVERIFIED`` — run ``agpatch scan`` first, and if a target
reports ``unsupported`` use ``agpatch probe`` to inspect the real bytes before
trusting or extending a signature.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import List, Optional, Tuple

from .hexsig import ByteSig

# --------------------------------------------------------------------------
# target kinds
# --------------------------------------------------------------------------
IDE = "ide"          # Antigravity IDE  -> resources/app/out/main.js (JS/Electron)
MANAGER = "manager"  # Antigravity 2.0  -> language_server (Go)
CLI = "cli"          # Antigravity CLI  -> agy / agy.exe (Go)
VSCODE = "vscode"    # google.google-antigravity extension -> extension.js

KIND_LABELS = {
    IDE: "Antigravity IDE (main.js)",
    MANAGER: "Antigravity 2.0 (language_server)",
    CLI: "Antigravity CLI (agy)",
    VSCODE: "VS Code extension (extension.js)",
}


@dataclass(frozen=True)
class TextGate:
    """A regex substitution in a JavaScript file."""

    key: str
    desc: str
    pattern: str
    template: str
    done_pattern: str
    provenance: str

    @property
    def group(self) -> str:
        """Gates in the same group are alternatives: at least one must match.

        ``manager/hasValidAuth/x64`` and ``.../arm64a`` are the same logical
        check compiled for different CPUs — a binary only contains one of
        them, so an absent sibling must not block the patch.
        """
        return self.key.split("/")[0]

    def match(self, text: str) -> Tuple[str, int]:
        if re.search(self.done_pattern, text):
            return "patched", -1
        sites = list(re.finditer(self.pattern, text))
        if len(sites) > 1:
            return "ambiguous", -1
        if len(sites) == 1:
            return "unpatched", sites[0].start()
        return "absent", -1

    def apply(self, text: str) -> str:
        return re.sub(self.pattern, self.template, text, count=1)


@dataclass(frozen=True)
class StringGate:
    """Equal-length ASCII string substitution inside a binary.

    Some checks are not a branch you can invert, but a literal the client
    compares against: rewriting the literal makes the comparison miss. This is
    far more version-robust than a byte signature (the compiler may reorder
    instructions, but it does not mangle string constants), which is why it is
    offered as an alternative rather than a replacement.

    Experimental: the semantics of the check it defeats are not fully known
    here, so it is never applied unless you ask for it explicitly.
    """

    key: str
    target: str
    needle: bytes
    replacement: bytes
    desc: str
    provenance: str
    max_sites: int = 8

    def __post_init__(self) -> None:
        if len(self.needle) != len(self.replacement):
            raise SigError("replacement must be the same length as the needle")
        if not self.needle:
            raise SigError("empty needle")

    @property
    def group(self) -> str:
        # Kept separate from the byte-gate group on purpose: a string patch and
        # an instruction patch on the same target answer different questions,
        # and neither should mask the other's absence.
        parts = self.key.split("/")
        return "/".join(parts[:2])

    def match(self, data: bytes) -> Tuple[str, int]:
        done = data.find(self.replacement)
        sites = data.count(self.needle)
        if sites == 0:
            return ("patched", done) if done >= 0 else ("absent", -1)
        if sites > self.max_sites:
            return "ambiguous", -1
        return "unpatched", data.find(self.needle)

    def apply_all(self, data: bytearray) -> int:
        count = data.count(self.needle)
        if count == 0 or count > self.max_sites:
            raise SigError(f"unexpected occurrence count ({count}) for {self.key}")
        patched = bytes(data).replace(self.needle, self.replacement)
        if len(patched) != len(data):
            raise SigError("string patch changed the file size — refusing")
        data[:] = patched
        return count


@dataclass(frozen=True)
class Gate:
    key: str
    target: str
    arch: str  # "any" or "x64" / "arm64"
    desc: str
    sig: ByteSig
    provenance: str

    @property
    def group(self) -> str:
        return self.key.split("/")[0]


# --------------------------------------------------------------------------
# Antigravity IDE — isGoogleInternal auth gate
#
#   resetIsTierGCPTos(), this.<mangled>.isGoogleInternal
#   -> resetIsTierGCPTos(), true
#
# (that flag gates the internal-account auth path; forcing it to true walks
# the internal branch)
# --------------------------------------------------------------------------
IDE_ISGOOGLEINTERNAL = TextGate(
    key="ide/isGoogleInternal",
    desc="isGoogleInternal -> true (auth gate)",
    pattern=r"(resetIsTierGCPTos\(\)),this\.[A-Za-z_$0-9]+\.isGoogleInternal",
    template=r"\1,true",
    done_pattern=r"resetIsTierGCPTos\(\),true",
    provenance="public JS diff, open-antigravity-patcher 1.3.x",
)


# --------------------------------------------------------------------------
# VS Code extension — channel-change check
#
#   const isChannelChanged = manifestFetched && lastInstalledUrl !== releaseBaseUrl;
#   -> const isChannelChanged = false;
#
# NOTE: we deliberately do NOT port the "skip version check / never re-download
# the binary" injection. That one freezes the extension on an old client and
# is a maintenance trap. Only the check itself is neutralised.
# --------------------------------------------------------------------------
VSCODE_CHANNEL = TextGate(
    key="vscode/isChannelChanged",
    desc="isChannelChanged -> false",
    pattern=(
        r"const\s+isChannelChanged\s*=\s*"
        r"manifestFetched\s*&&\s*lastInstalledUrl\s*!==\s*releaseBaseUrl\s*;"
    ),
    template="const isChannelChanged = false;",
    done_pattern=r"const\s+isChannelChanged\s*=\s*false\s*;",
    provenance="public JS diff, open-antigravity-patcher 1.3.x",
)


# --------------------------------------------------------------------------
# Antigravity 2.0 — language_server hasValidAuth gate (x86-64)
#
#   cmp  byte ptr [rax+8], 0     80 78 08 00
#   je   short <skip>            74 xx
#   ...
# ->
#   mov  byte ptr [rax+8], 1     c6 40 08 01
#   nop; nop                     90 90
#
# The trailing bytes are context: they pin the site so the 6-byte signature
# stays unique. Only the first 6 bytes are rewritten.
# --------------------------------------------------------------------------
MANAGER_X64 = Gate(
    key="manager/hasValidAuth/x64",
    target=MANAGER,
    arch="x64",
    desc="hasValidAuth=true (x64)",
    sig=ByteSig(
        pattern="80 78 08 00 74 ?? 48 8b ?? 24 ?? 48 89 ?? 24 60",
        fix=bytes.fromhex("c64008019090"),
        offset=0,
    ),
    provenance="UNVERIFIED — disassembly published in open-antigravity-patcher README",
)

# --------------------------------------------------------------------------
# Antigravity 2.0 — language_server hasValidAuth gate (AArch64)
#
#   ldrb w3, [x0, #8]            03 20 40 39
#   tbz  w3, #0, <skip>          [03|23|43|63|83|a3|c3|e3] xx xx 36
# ->
#   mov  w3, #1                  23 00 80 52
#   strb w3, [x0, #8]            03 20 00 39
#
# Two variants: the token-attachment store before the epilogue is either
# preceded by one or two setup instructions, so the context window differs.
# --------------------------------------------------------------------------
_MGR_ARM_TBZ = "[03 23 43 63 83 a3 c3 e3] ?? ?? 36"
MANAGER_ARM64 = (
    Gate(
        key="manager/hasValidAuth/arm64a",
        target=MANAGER,
        arch="arm64",
        desc="hasValidAuth=true (arm64, 1 setup)",
        sig=ByteSig(
            pattern=f"03 20 40 39 {_MGR_ARM_TBZ} ?? ?? ?? ?? 03 10 06 a9",
            fix=bytes.fromhex("2300805203200039"),
            offset=0,
        ),
        provenance="UNVERIFIED — disassembly published in open-antigravity-patcher README",
    ),
    Gate(
        key="manager/hasValidAuth/arm64b",
        target=MANAGER,
        arch="arm64",
        desc="hasValidAuth=true (arm64, 2 setup)",
        sig=ByteSig(
            pattern=(
                f"03 20 40 39 {_MGR_ARM_TBZ} "
                "?? ?? ?? ?? ?? ?? ?? ?? 03 10 06 a9"
            ),
            fix=bytes.fromhex("2300805203200039"),
            offset=0,
        ),
        provenance="UNVERIFIED — disassembly published in open-antigravity-patcher README",
    ),
)

# --------------------------------------------------------------------------
# Antigravity CLI (agy) — "Eligibility check failed" gate (x86-64)
#
#   test rax, rax                48 85 c0
#   je   eligible                0f 84 xx xx xx xx
#   cmp  byte ptr [rax+8], 0     80 78 08 00   <-- neutralised
#   jne  eligible                0f 85 xx xx xx xx
#   call failure_builder
# ->
#   cmp -> test rax, rax ; nop   48 85 c0 90
#
# rax is known non-null at that point, so `jne` always jumps to the
# "eligible" branch and the error builder becomes unreachable.
# --------------------------------------------------------------------------
CLI_X64 = Gate(
    key="cli/eligibility/x64",
    target=CLI,
    arch="x64",
    desc="eligibility gate off (x64)",
    sig=ByteSig(
        pattern="48 85 c0 0f 84 ?? ?? ?? ?? 80 78 08 00 0f 85 ?? ?? ?? ??",
        fix=bytes.fromhex("4885c090"),
        offset=9,
    ),
    provenance="UNVERIFIED — disassembly published in open-antigravity-patcher README",
)

# --------------------------------------------------------------------------
# Antigravity CLI (agy) — eligibility gate (AArch64)
#
#   cbnz x1, error               ?? ?? ?? b5
#   cbz  x0, eligible            ?? ?? ?? b4
#   ldrb w1, [x0, #8]            01 20 40 39   <-- neutralised
#   tbnz w1, #0, eligible        ?? ?? 37
#   bl   failure_builder
#
# CLI >= 1.2.7 recompiled this without the outer cbnz and uses w4; there is
# also an inlined copy using w2. Both sites need patching, hence three gates.
# --------------------------------------------------------------------------
_CLI_TBNZ = "?? ?? 37"
CLI_ARM64 = (
    Gate(
        key="cli/eligibility/arm64w1",
        target=CLI,
        arch="arm64",
        desc="eligibility gate off (arm64, w1)",
        sig=ByteSig(
            pattern=(
                "?? ?? ?? b5 ?? ?? ?? b4 01 20 40 39 "
                "[01 21 41 61 81 a1 c1 e1] " + _CLI_TBNZ
            ),
            fix=bytes.fromhex("21008052"),
            offset=8,
        ),
        provenance="UNVERIFIED — disassembly published in open-antigravity-patcher README",
    ),
    Gate(
        key="cli/eligibility/arm64w4",
        target=CLI,
        arch="arm64",
        desc="eligibility gate off (arm64, w4)",
        sig=ByteSig(
            pattern=(
                "?? ?? ?? b4 04 20 40 39 "
                "[04 24 44 64 84 a4 c4 e4] ?? [00-07] 37 04 94 44 a9"
            ),
            fix=bytes.fromhex("24008052"),
            offset=4,
        ),
        provenance="UNVERIFIED — disassembly published in open-antigravity-patcher README",
    ),
    Gate(
        key="cli/eligibility/arm64w2",
        target=CLI,
        arch="arm64",
        desc="eligibility gate off (arm64, w2)",
        sig=ByteSig(
            pattern=(
                "[01 21 41 61 81 a1 c1 e1] ?? ?? b5 "
                "[00 20 40 60 80 a0 c0 e0] ?? ?? b4 "
                "02 20 40 39 [02 22 42 62 82 a2 c2 e2] " + _CLI_TBNZ
            ),
            fix=bytes.fromhex("22008052"),
            offset=8,
        ),
        provenance="UNVERIFIED — disassembly published in open-antigravity-patcher README",
    ),
)


# --------------------------------------------------------------------------
# OPT-IN: equal-length string patches (experimental)
#
# These do not appear in the default profile. ``--experimental-strings`` turns
# them on. Same length, same file size, trivially reversible from the backup —
# but the check they defeat is not fully understood here, so they are your call
# and not the default.
# --------------------------------------------------------------------------
STRING_PATCHES = {
    MANAGER: [
        StringGate(
            key="manager/string/ineligible",
            target=MANAGER,
            needle=b"ineligible",
            replacement=b"inexigible",
            desc='literal "ineligible" -> "inexigible"',
            provenance="public report (confeden/Antigravity) — semantics unverified",
        )
    ],
}


# --------------------------------------------------------------------------
# profiles
# --------------------------------------------------------------------------
BINARY_PROFILES = {
    MANAGER: {
        "x64": [MANAGER_X64],
        "arm64": list(MANAGER_ARM64),
    },
    CLI: {
        "x64": [CLI_X64],
        "arm64": list(CLI_ARM64),
    },
}

TEXT_GATES = {
    IDE: [IDE_ISGOOGLEINTERNAL],
    VSCODE: [VSCODE_CHANNEL],
}


def all_gates() -> List[object]:
    out: List[object] = []
    for arch_map in BINARY_PROFILES.values():
        for gates in arch_map.values():
            out.extend(gates)
    for gates in TEXT_GATES.values():
        out.extend(gates)
    for gates in STRING_PATCHES.values():
        out.extend(gates)
    return out


def gates_for(kind: str, arch: Optional[str] = None,
              strings: bool = False) -> List[object]:
    if kind not in BINARY_PROFILES:
        raise KeyError(kind)
    profile = BINARY_PROFILES[kind]
    if arch:
        out: List[object] = list(profile.get(arch, []))
    else:
        out = []
        for gates in profile.values():
            out.extend(gates)
    if strings:
        out.extend(STRING_PATCHES.get(kind, []))
    return out
