"""Triage: given what the app actually prints, what is actually wrong?

The single most expensive mistake with Antigravity region blocks is treating
all of them as one problem. They are not:

  1. a local gate in the client      -> file patch helps
  2. a server-side geo check          -> file patch CANNOT help, need egress
  3. an account/licence state         -> nothing local helps
  4. a transport/DNS problem          -> routing, not patching

This module maps an error string to one of those and says what to do next.
It never pretends a client patch can fix a server answer.

The signatures below are quoted from public issue reports and the upstream
patcher's troubleshooting section. They are matched case-insensitively.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import List, Optional, Tuple

CLIENT_GATE = "client-gate"
SERVER_GEO = "server-geo"
ACCOUNT = "account"
TRANSPORT = "transport"
UNKNOWN = "unknown"

CATEGORY_LABELS = {
    CLIENT_GATE: "local client gate — a file patch is the right tool",
    SERVER_GEO: "server-side geo check — a file patch cannot help, you need egress",
    ACCOUNT: "account/licence state — nothing local will change this",
    TRANSPORT: "network/transport — fix routing, not files",
    UNKNOWN: "not recognised",
}


@dataclass(frozen=True)
class Diagnosis:
    code: str
    title: str
    category: str
    meaning: str
    steps: Tuple[str, ...]
    patcher_action: str  # "patch", "route", "none"


_RULES: List[Tuple[str, "re.Pattern[str]"]] = [
    ("location-400", re.compile(r"user location is not supported|location.{0,20}not supported", re.I)),
    ("ineligible", re.compile(r"not eligible|ineligible|eligibility check failed", re.I)),
    ("subscription-403", re.compile(r"subscription_required|403 forbidden|forbidden", re.I)),
    ("licence-3501", re.compile(r"#3501|do not have a valid license", re.I)),
    ("quota-429", re.compile(r"resource_exhausted|too many requests|429", re.I)),
    ("server-500", re.compile(r"internal server error|500", re.I)),
    ("oauth-exchange", re.compile(r"failed to exchange authorization code", re.I)),
    ("dns", re.compile(r"name or service not known|getaddrinfo|dns|no such host|name resolution", re.I)),
    ("timeout", re.compile(r"timed out|timeout|connection reset|econnrefused|unreachable", re.I)),
]


_DIAGNOSES = {
    "location-400": Diagnosis(
        code="location-400",
        title='400 "User location is not supported for the API use"',
        category=SERVER_GEO,
        meaning=(
            "Google answered after seeing your egress IP. The client sent a valid "
            "request; the server refused it because of where it appears to come from. "
            "No local file edit changes an IP address."
        ),
        steps=(
            "Keep the client stock — patching it makes no difference here.",
            "Send only cloudcode-pa.googleapis.com and daily-cloudcode-pa.googleapis.com "
            "through an egress in a supported region: `agpatch route plan`.",
            "Leave everything else direct, so sign-in and history sync stay on your normal path.",
            "Re-check with `agpatch doctor` after the change: the same chat that failed should answer.",
        ),
        patcher_action="route",
    ),
    "ineligible": Diagnosis(
        code="ineligible",
        title='"Your current account is not eligible for Antigravity" / Eligibility check failed',
        category=CLIENT_GATE,
        meaning=(
            "The client (or the CLI) decided locally that this account/region is not "
            "allowed and never sent the request. This is the one a file patch is for."
        ),
        steps=(
            "`agpatch scan` — see whether the target is `clean` or `unsupported`.",
            "`agpatch patch --kind cli,ide,manager --dry-run`, then without --dry-run.",
            "If scan says `unsupported`, the signature does not cover your version: "
            "run `agpatch probe --path <file>` and check the bytes before extending gates.py.",
            "If the server then answers 400 location — that is a different problem, see `agpatch doctor --help`.",
        ),
        patcher_action="patch",
    ),
    "subscription-403": Diagnosis(
        code="subscription-403",
        title="403 Forbidden / SUBSCRIPTION_REQUIRED",
        category=ACCOUNT,
        meaning=(
            "A server-side entitlement decision for this account. Not a region gate in "
            "the client, and not something a binary patch can grant."
        ),
        steps=(
            "Do not patch for this — it will not change the answer.",
            "Check the plan/entitlement on the account you are signed in with.",
            "If it appeared right after a region bypass, sign out, fix egress, then sign in again.",
        ),
        patcher_action="none",
    ),
    "licence-3501": Diagnosis(
        code="licence-3501",
        title='"You do not have a valid license of this product (#3501)"',
        category=ACCOUNT,
        meaning="Account/licence state evaluated by Google. The client merely displays it.",
        steps=(
            "Nothing local fixes this; the upstream patcher says the same explicitly.",
            "Try signing out and in again on the current client version.",
            "If it persists, the account needs to be looked at on Google's side.",
        ),
        patcher_action="none",
    ),
    "quota-429": Diagnosis(
        code="quota-429",
        title="429 RESOURCE_EXHAUSTED / too many requests",
        category=ACCOUNT,
        meaning="Rate limit or quota, not a region gate.",
        steps=(
            "Wait for the window to reset; switching accounts is what people usually do.",
            "If it triggers instantly on every request, check egress: a shared proxy IP is often already rate-limited.",
            "Do not patch for this.",
        ),
        patcher_action="none",
    ),
    "server-500": Diagnosis(
        code="server-500",
        title="HTTP 500 Internal Server Error",
        category=TRANSPORT,
        meaning="Server-side failure, frequently reported together with proxy/VPN egress.",
        steps=(
            "Retry once after a minute.",
            "If you route traffic through a proxy, try a different egress before touching any file.",
            "Only then suspect the client build.",
        ),
        patcher_action="none",
    ),
    "oauth-exchange": Diagnosis(
        code="oauth-exchange",
        title='"Failed to exchange authorization code for token"',
        category=TRANSPORT,
        meaning=(
            "The sign-in redirect completed but the token exchange failed — almost always "
            "DNS/egress interception of accounts.google.com or oauth2.googleapis.com, "
            "often by a proxy or DNS tool that also swallowed those hosts."
        ),
        steps=(
            "Make sure accounts.google.com and oauth2.googleapis.com go DIRECT.",
            "Disable DNS-level bypass tools while signing in, then re-enable them.",
            "Retry sign-in before touching any client file.",
        ),
        patcher_action="route",
    ),
    "dns": Diagnosis(
        code="dns",
        title="DNS / host resolution failure",
        category=TRANSPORT,
        meaning="Resolution failed — routing or a DNS tool, not the client gate.",
        steps=(
            "`agpatch route plan` and confirm only the two cloudcode-pa hosts are diverted.",
            "Verify with `nslookup cloudcode-pa.googleapis.com` and `nslookup accounts.google.com`.",
            "Remove any leftover hosts-file or DNS entries from other tools.",
        ),
        patcher_action="route",
    ),
    "timeout": Diagnosis(
        code="timeout",
        title="Timeout / connection reset / refused",
        category=TRANSPORT,
        meaning="Traffic is not reaching the API at all.",
        steps=(
            "Check the egress path first: `agpatch route proxy` and its log.",
            "Confirm nothing is set in HTTP_PROXY/HTTPS_PROXY system-wide that the app ignores anyway.",
            "Retry with the proxy off to see whether it is the proxy that broke it.",
        ),
        patcher_action="route",
    ),
}


def diagnose(text: str) -> Optional[Diagnosis]:
    if not text or not text.strip():
        return None
    for code, pattern in _RULES:
        if pattern.search(text):
            return _DIAGNOSES[code]
    return None


def format_diagnosis(diag: Diagnosis) -> str:
    lines = [
        f"diagnosis : {diag.title}",
        f"category  : {CATEGORY_LABELS[diag.category]}",
        "",
        "what it means:",
        f"  {diag.meaning}",
        "",
        "next steps:",
    ]
    for i, step in enumerate(diag.steps, 1):
        lines.append(f"  {i}. {step}")
    if diag.patcher_action == "route":
        lines += ["", "agpatch action: route (see `agpatch route plan`), NOT patch"]
    elif diag.patcher_action == "patch":
        lines += ["", "agpatch action: patch"]
    else:
        lines += ["", "agpatch action: none — do not patch for this"]
    return "\n".join(lines)
