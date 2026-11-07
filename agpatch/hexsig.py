"""Byte-signature mini-language.

Instead of raw ``b"\\x80\\x78\\x08\\x00\\x74."`` regex escapes (which are painful to
review), signatures are written as readable hex tokens:

    80 78 08 00        exact bytes
    ??                 any single byte
    [03 23 43 63]      one byte out of a set
    [00-07]            one byte out of a range

Every signature is compiled to a byte-level regex. Matching is *always*
uniqueness-checked by the caller: a signature that occurs twice is refused
rather than guessed at.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Iterable, List, Optional, Sequence, Tuple, Union

WILDCARD = "??"

# A token is either an exact byte (int), a wildcard (None) or a tuple of
# inclusive byte ranges (a character class).
Token = Union[int, None, Tuple[Tuple[int, int], ...]]

_TOKEN_RE = re.compile(r"\[[^\]]*\]|\S+")


class SigError(ValueError):
    """Malformed signature or impossible patch geometry."""


def _byte(token: str) -> Optional[int]:
    t = token.strip()
    if t == WILDCARD:
        return None
    if len(t) != 2:
        raise SigError(f"bad hex token {token!r} (expected two hex digits or ??)")
    try:
        return int(t, 16)
    except ValueError:
        raise SigError(f"bad hex token {token!r}") from None


def parse(pattern: str) -> List[Token]:
    """Parse the mini-language into a list of tokens."""
    tokens: List[Token] = []
    for chunk in _TOKEN_RE.findall(pattern):
        if chunk.startswith("["):
            if not chunk.endswith("]"):
                raise SigError(f"unterminated character class in {pattern!r}")
            ranges: List[Tuple[int, int]] = []
            for item in chunk[1:-1].split():
                if "-" in item:
                    lo_s, hi_s = item.split("-", 1)
                    lo, hi = _byte(lo_s), _byte(hi_s)
                    if lo is None or hi is None or lo > hi:
                        raise SigError(f"bad range {item!r} in {pattern!r}")
                    ranges.append((lo, hi))
                else:
                    b = _byte(item)
                    if b is None:
                        raise SigError(f"wildcard not allowed inside a class: {chunk!r}")
                    ranges.append((b, b))
            if not ranges:
                raise SigError(f"empty character class in {pattern!r}")
            tokens.append(tuple(ranges))
        else:
            tokens.append(_byte(chunk))
    if not tokens:
        raise SigError("empty signature")
    return tokens


def to_regex(tokens: Sequence[Token]) -> bytes:
    out = bytearray()
    for token in tokens:
        if token is None:
            out += b"."
        elif isinstance(token, int):
            out += re.escape(bytes([token]))
        else:
            out += b"["
            for lo, hi in token:
                if lo == hi:
                    out += re.escape(bytes([lo]))
                else:
                    out += re.escape(bytes([lo])) + b"-" + re.escape(bytes([hi]))
            out += b"]"
    return bytes(out)


def compile_tokens(tokens: Sequence[Token]) -> "re.Pattern[bytes]":
    # re.S so that wildcards also match 0x0A inside binaries.
    return re.compile(to_regex(tokens), re.S)


@dataclass(frozen=True)
class ByteSig:
    """A find-region signature plus the bytes written at ``offset`` inside it.

    ``offset`` is relative to the start of the match. ``fix`` must not be
    longer than the match itself.
    """

    pattern: str
    fix: bytes
    offset: int = 0

    # -- construction -----------------------------------------------------
    def __post_init__(self) -> None:
        tokens = parse(self.pattern)
        if self.offset < 0:
            raise SigError("negative patch offset")
        if not self.fix:
            raise SigError("empty fix")
        if self.offset + len(self.fix) > len(tokens):
            raise SigError(
                f"fix ({len(self.fix)} bytes at offset {self.offset}) does not fit "
                f"inside a {len(tokens)}-byte signature"
            )

    # -- compiled forms ---------------------------------------------------
    @property
    def tokens(self) -> List[Token]:
        return parse(self.pattern)

    @property
    def regex(self) -> "re.Pattern[bytes]":
        return compile_tokens(self.tokens)

    @property
    def done_regex(self) -> "re.Pattern[bytes]":
        """Signature with the fix already substituted in — detects "patched"."""
        tokens = parse(self.pattern)
        for i, byte in enumerate(self.fix):
            tokens[self.offset + i] = byte
        return compile_tokens(tokens)

    # -- matching ---------------------------------------------------------
    def match(self, data: bytes) -> Tuple[str, int]:
        """Return ``(state, offset)``.

        state is one of ``patched``, ``unpatched``, ``ambiguous``, ``absent``.
        Offset is -1 unless a unique site was found.
        """
        m = self.done_regex.search(data)
        if m:
            return "patched", m.start() + self.offset
        sites = [m.start() for m in self.regex.finditer(data)]
        if len(sites) > 1:
            return "ambiguous", -1
        if len(sites) == 1:
            return "unpatched", sites[0] + self.offset
        return "absent", -1

    def locate(self, data: bytes) -> Iterable[Tuple[str, int]]:
        """Every site, tagged patched/unpatched — used by ``agpatch probe``."""
        done = {m.start() for m in self.done_regex.finditer(data)}
        seen = set()
        for m in self.regex.finditer(data):
            seen.add(m.start())
            yield ("patched" if m.start() in done else "unpatched"), m.start()
        for start in sorted(done - seen):
            yield "patched", start


def apply_fix(data: bytearray, offset: int, fix: bytes) -> None:
    if offset < 0 or offset + len(fix) > len(data):
        raise SigError("patch would write outside the file")
    data[offset : offset + len(fix)] = fix


def spans_overlap(spans: Sequence[Tuple[int, int]]) -> bool:
    ordered = sorted(spans)
    return any(ordered[i][1] > ordered[i + 1][0] for i in range(len(ordered) - 1))
