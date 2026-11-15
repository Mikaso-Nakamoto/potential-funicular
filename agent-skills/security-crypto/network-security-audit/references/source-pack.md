# Source pack: repositories worth feeding an AI reviewer

Verified against the GitHub API on **2026-11-15** (stars, license, last push). Only repositories that are large, actively maintained and usable as *input for a review pass* are listed — not link dumps. Sorted by role in the audit.

Rule of thumb: requirements and method first, tools second, offense knowledge last and only against your own systems.

---

## 1. Requirements — what "secure" means here

| Repo | ★ | License | Take from it |
| --- | --- | --- | --- |
| [OWASP/ASVS](https://github.com/OWASP/ASVS) | 3.8k | CC-BY-SA-4.0 | Versioned verification requirements (use `5.0/`). The checklist that turns "looks fine" into pass/fail per control. |
| [OWASP/Top10](https://github.com/OWASP/Top10) | 6.5k | — | Risk framing for the report's executive summary. |
| [OWASP/API-Security](https://github.com/OWASP/API-Security) | 2.4k | — | API-specific risk set; the natural baseline for anything with endpoints. |
| [OWASP/www-project-top-10-for-large-language-model-applications](https://github.com/OWASP/www-project-top-10-for-large-language-model-applications) | 1.5k | — | Only if the product calls or exposes an LLM (prompt injection, tool abuse, data leakage). |
| [usnistgov/OSCAL](https://github.com/usnistgov/OSCAL) | 970 | — | Machine-readable NIST controls when you need compliance mapping instead of prose. |
| [mitre-attack/attack-stix-data](https://github.com/mitre-attack/attack-stix-data) | 722 | — | STIX/ATT&CK techniques for naming what an attacker would do to this service. |
| [CVEProject/cvelistV5](https://github.com/CVEProject/cvelistV5) | 3.3k | — | CVE JSON 5 feed to check your dependency versions against reality. |

## 2. Method — how to test it

| Repo | ★ | License | Take from it |
| --- | --- | --- | --- |
| [OWASP/CheatSheetSeries](https://github.com/OWASP/CheatSheetSeries) | 34.1k | CC-BY-SA-4.0 | The highest-value single repo. Relevant sheets: `SSRF_Prevention`, `TLS_Cipher_String`, `HTTP_Headers`, `WebSocket_Security`, `gRPC_Security`, `OS_Command_Injection_Defense`, `Deserialization`, `Input_Validation`, `Denial_of_Service`, `Logging`, `Secrets_Management`, `User_Privacy_Protection`, `REST_Security`, `Authorization`. |
| [OWASP/wstg](https://github.com/OWASP/wstg) | 10.3k | CC-BY-SA-4.0 | Task-by-task web testing procedure — use as the dynamic-test script. |
| [OWASP/mastg](https://github.com/OWASP/mastg) | 13.3k | CC-BY-SA-4.0 | Only for a mobile client, incl. traffic interception and pinning checks. |
| [OWASP/threat-dragon](https://github.com/OWASP/threat-dragon) | 1.7k | Apache-2.0 | Threat-model notation and data-flow diagrams the agent can fill in. |
| [google/security-research](https://github.com/google/security-research) | 4.7k | Apache-2.0 | Real advisory + PoC pairs; good few-shot examples of a well-written finding. |

## 3. AI review harnesses — repos built to be driven by an agent

| Repo | ★ | License | Take from it |
| --- | --- | --- | --- |
| [trailofbits/skills](https://github.com/trailofbits/skills) | 8.2k | CC-BY-SA-4.0 | 47 Claude/Codex plugins from an audit firm. For a network review load: `static-analysis` (CodeQL+Semgrep+SARIF), `differential-review`, `insecure-defaults`, `sharp-edges`, `supply-chain-risk-auditor`, `fp-check` (false-positive gate), `cvss-scoring`, `variant-analysis`, `yara-authoring`, `modern-python`, `burpsuite-project-parser`. Install: `/plugin marketplace add trailofbits/skills`. |
| [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review) | 6.9k | MIT | Drop-in GitHub Action for diff-level review on every PR: semantic analysis, false-positive filtering, PR comments. Not hardened against prompt injection — trusted PRs only. |
| [semgrep/semgrep](https://github.com/semgrep/semgrep) | 17.7k | LGPL-2.1 | Fast pattern engine the agent can run and iterate on. |
| [semgrep/semgrep-rules](https://github.com/semgrep/semgrep-rules) | 1.3k | — | Community rule corpus; source of the `p/…` packs above. |
| [github/codeql](https://github.com/github/codeql) | 10.4k | MIT | Deep data-flow queries; drives "does this HTTP parameter reach this sink". |
| [joernio/joern](https://github.com/joernio/joern) | 3.6k | Apache-2.0 | Code property graphs for cross-language flow queries and reachability. |

## 4. Dynamic testing — run against your own staging only

| Repo | ★ | License | Take from it |
| --- | --- | --- | --- |
| [zaproxy/zaproxy](https://github.com/zaproxy/zaproxy) | 16.2k | Apache-2.0 | Baseline and API scans, authenticated contexts, OpenAPI import. |
| [projectdiscovery/nuclei](https://github.com/projectdiscovery/nuclei) | 32.9k | MIT | YAML DSL for repeatable checks; write your own templates, pin the version. |
| [mitmproxy/mitmproxy](https://github.com/mitmproxy/mitmproxy) | 47k | MIT | Intercept your own client's traffic, including TLS, and diff expected vs actual. |
| [wireshark/wireshark](https://github.com/wireshark/wireshark) | 10.2k | GPL-2.0 | `tshark` for capture and protocol-level assertions in tests. |
| [nmap/nmap](https://github.com/nmap/nmap) | 14k | — | Port/service inventory of your own host; NSE for protocol probes. |
| [owasp-amass/amass](https://github.com/owasp-amass/amass) | 15.5k | — | Attack-surface enumeration of assets you own. Never a third-party domain. |
| [OWASP/Nettacker](https://github.com/OWASP/Nettacker) | 5.7k | Apache-2.0 | Framework for scheduling checks across your own fleet. |

## 5. Detection — could you see your own attack?

| Repo | ★ | License | Take from it |
| --- | --- | --- | --- |
| [SigmaHQ/sigma](https://github.com/SigmaHQ/sigma) | 11.5k | — | Log-based detection rules; check your log fields exist, then write a rule per abuse case. |
| [OISF/suricata](https://github.com/OISF/suricata) | 6.9k | GPL-2.0 | Network IDS rules to prove the traffic pattern is detectable. |
| [zeek/zeek](https://github.com/zeek/zeek) | 8.2k | — | Protocol-level logs and scripts for behavioral checks. |
| [VirusTotal/yara](https://github.com/VirusTotal/yara) | 10k | BSD-3-Clause | Only if the product handles files; pair with the YARA authoring skill. |

## 6. Supply chain, secrets, cloud/network exposure

| Repo | ★ | License | Take from it |
| --- | --- | --- | --- |
| [aquasecurity/trivy](https://github.com/aquasecurity/trivy) | 39.4k | Apache-2.0 | Deps, secrets, IaC and container misconfig in one pass. |
| [gitleaks/gitleaks](https://github.com/gitleaks/gitleaks) | 31k | MIT | Working tree + git history secret scan. |
| [trufflesecurity/trufflehog](https://github.com/trufflesecurity/trufflehog) | 29.4k | AGPL-3.0 | Verified live credentials — use the verification mode to kill false positives. |
| [prowler-cloud/prowler](https://github.com/prowler-cloud/prowler) | 15.2k | Apache-2.0 | Cloud/network posture checks (open SGs, public buckets, exposed services) if you deploy to AWS/GCP/Azure. |

## 7. Offense knowledge — for testing your own app, not other people's

| Repo | ★ | License | Take from it |
| --- | --- | --- | --- |
| [swisskyrepo/PayloadsAllTheThings](https://github.com/swisskyrepo/PayloadsAllTheThings) | 82.7k | MIT | Per-vulnerability payload sets: SSRF filters, header injection, deserialization gadgets. |
| [danielmiessler/SecLists](https://github.com/danielmiessler/SecLists) | 74.8k | MIT | Fuzzing lists for your own endpoints and parameter names. |
| [HackTricks-wiki/hacktricks](https://github.com/HackTricks-wiki/hacktricks) | 12.8k | — | Method knowledge for network pivoting, protocol abuse, cloud metadata. |
| [The-Art-of-Hacking/h4cker](https://github.com/The-Art-of-Hacking/h4cker) | 30.2k | MIT | Courses, labs, DFIR and AI-security material for structured learning. |
| [sbilly/awesome-security](https://github.com/sbilly/awesome-security) | 15.1k | MIT | Index to specialised tools when the pack above lacks one. |

## 8. If the product uses an LLM

| Repo | ★ | License | Take from it |
| --- | --- | --- | --- |
| [meta-llama/PurpleLlama](https://github.com/meta-llama/PurpleLlama) | 4.5k | — | CyberSecEval benchmarks + Llama Guard: measure whether the model helps with abuse. |
| [NVIDIA-NeMo/Guardrails](https://github.com/NVIDIA-NeMo/Guardrails) | 7.5k | — | Programmable input/output rails around a network-capable agent. |
| [protectai/llm-guard](https://github.com/protectai/llm-guard) | 3.2k | MIT | Prompt-injection and PII scanners for the request path. |

## 9. Ethics and law (not repos, but required reading in the report)

| Source | Why |
| --- | --- |
| [RFC 1087 — Ethics and the Internet (1989)](https://www.rfc-editor.org/rfc/rfc1087.html) | The canonical statement: seeking to gain unauthorized access is unethical, not merely illegal. |
| [The Menlo Report (2012)](https://www.caida.org/catalog/papers/2012_menlo_report_actual_formatted/menlo_report_actual_formatted.pdf) | ICT-research ethics: respect for persons, beneficence, justice, respect for law and public interest. The right frame for "my program touches other people's systems". |
| [disclose.io](https://disclose.io/) | Safe-harbor terms so testing permission is written, not implied. |
| [ACM Code of Ethics](https://www.acm.org/code-of-ethics) | Professional obligations when the design has a dual use. |
| BSI TR-02102 + IT-Grundschutz | German crypto/TLS policy and baseline protections — expected by local auditors. |
| GDPR Art. 5, 6, 32 | Lawful basis, minimization and security of processing for IPs, logs, traffic metadata. |
| §202a–c StGB | Access to data, interception and preparatory acts — the German criminal frame for network tooling. |
| NIS2, EU Cyber Resilience Act | Obligations once this ships as a product in the EU. |

---

## How to feed this to an agent without blowing the context

1. **Minimal set (fast audit):** ASVS 5.0 chapter files for the areas in scope + 6–8 Cheat Sheets + `trailofbits/skills/plugins/static-analysis` + `insecure-defaults` + your own code. Enough for a real review of a small service.
2. **Sparse clone instead of full repos** — these repos are huge:

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/OWASP/CheatSheetSeries
cd CheatSheetSeries && git sparse-checkout set cheatsheets
# then read only the sheets named in §2
```

3. **Evaluate against, don't paste.** Ask the model to answer per requirement with `pass / fail / not-checked + evidence (file:line)`. A checklist without evidence is fiction.
4. **Order matters:** requirements → code → tool output → dynamic evidence → ethics. Tool output first biases the review toward what the scanner can see.
5. **One sink at a time for data flow.** "Find all SSRF" fails; "for this URL parameter, trace every hop to the socket" works.
6. **Keep an evidence directory** (`review/evidence/`) with requests, responses, SARIF files and pcap slices; findings cite paths into it.
