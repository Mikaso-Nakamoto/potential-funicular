---
name: network-security-audit
description: Audit a program's network behavior and the design idea behind it — inbound listeners, outbound egress, protocols, TLS, authentication, parsing, logging, resource limits — and score it against OWASP ASVS/WSTG/Cheat Sheets, CWE and ATT&CK, using Semgrep, CodeQL, Joern, ZAP, nuclei, mitmproxy, tshark, Sigma/Suricata/Zeek and secrets/supply-chain scanners. Covers the authorization and network-ethics gate that must run before any active test, GDPR/§202a StGB/NIS2/CRA obligations for a shipped network product, and a fixed findings report with evidence, repro and verification. Use when someone asks "check my program for security", "review my network code", "is my idea legal/safe to ship", "threat model this service", "audit my API/webhook/parser/daemon", or before a release, pen-test or launch of anything that opens a socket.
---

# Network Security Audit Skill

A repeatable audit for programs that touch the network, and for the idea behind them. The goal is not a scanner report: it is a short list of findings an engineer can fix today, plus an explicit statement of what the design is allowed to do to other people's systems.

Two rules override everything below:

1. **Only test systems you own or have written permission for.** Your repo, your staging, your container, your device, a lab. No third-party hosts, no "just a quick scan", no borrowed credentials.
2. **The report states facts, not vibes.** Every finding needs a location, a trigger, an impact, an evidence artifact and a fix. No "could be risky".

---

## 0. Scope and authorization gate (do this first, always)

Write the scope down before touching a tool:

```text
Target:            <repo path / staging URL / device>
Ownership:         <I own it | written authorization from X dated Y>
Allowed actions:   <static review, local run, traffic capture, authenticated scan>
Forbidden:         <third-party hosts, production data, load tests above N rps, social engineering>
Data handling:     <what traffic/PII may be stored, where, for how long>
Stop conditions:   <anything outside scope, any real user data, any crash on shared infra>
```

- Active testing (ZAP, nuclei, fuzzing, replay) runs **against a local or staging copy**, never against a host you do not control.
- If the program's *purpose* is scanning, crawling, scraping, monitoring or connecting to other people's systems, the audit must also cover **consent and the target's terms**: robots.txt, ToS/API terms, rate limits, and whether the design needs opt-in from the operator. That is a design finding, not a footnote.
- A design whose business model depends on accessing systems without permission is not "fixable by hardening". Say so plainly and stop.

Ethics references to cite in the report: [RFC 1087](https://www.rfc-editor.org/rfc/rfc1087.html), [Menlo Report](https://www.caida.org/catalog/papers/2012_menlo_report_actual_formatted/menlo_report_actual_formatted.pdf), [disclose.io](https://disclose.io/), [ACM Code of Ethics](https://www.acm.org/code-of-ethics).

---

## 1. Inventory the network surface

Enumerate before judging. Produce a table and keep it in the report; every later finding points into it.

| Layer | What to record |
| --- | --- |
| Inbound | every listener: port, protocol, bind address (`0.0.0.0` vs `127.0.0.1`), TLS or not, auth required, exposed by default? |
| Outbound | every egress: HTTP client calls, webhooks, DNS, SMTP, update checks, telemetry, LLM/API providers, third-party SDKs |
| Protocols | HTTP/1.1, HTTP/2, gRPC, WebSocket, MQTT, raw TCP/UDP, serial, custom binary framing |
| Identity | who authenticates to whom: API keys, OAuth flows, mTLS, tokens in headers vs query vs cookie |
| Parsers | every place bytes from the network become objects: JSON, XML, protobuf, multipart, archives, images, PDFs |
| State | sessions, caches, queues, retries, idempotency keys, connection pools |

Commands that make the inventory cheap:

```bash
# services and sockets on the box / in the container
ss -tulpn                       # listeners
lsof -i -P -n | grep LISTEN     # who owns them
# what the program actually dials, from source
rg -n "https?://|wss?://|grpc|smtp|mqtt|socket\(|net\.(Dial|connect)|fetch\(|axios|requests\.|urllib" --glob '!**/{node_modules,vendor,test}/**'
rg -n "0\.0\.0\.0|INADDR_ANY|verify\s*=\s*False|rejectUnauthorized:\s*false|InsecureSkipVerify|CURLOPT_SSL_VERIFYPEER" .
```

---

## 2. Threat model the trust boundaries (30 minutes, not 3 days)

Do STRIDE per boundary from §1, not per file. For each boundary answer: what crosses it, who can start the conversation, what the receiver assumes about the sender.

- **Spoofing** — can a caller claim another identity? Is the `Host`/`Origin`/`X-Forwarded-For`/SNI value trusted?
- **Tampering** — is integrity protected end to end (TLS verified properly, signatures, HMAC)? Where is it terminated and re-originated?
- **Repudiation** — can an action be denied later? Are auth and state-changing events logged with actor + request id?
- **Information disclosure** — what leaks in errors, headers, timings, sizes, DNS lookups, telemetry?
- **Denial of service** — unbounded reads, decompression, regex, fan-out, retries, connection pools, one slow client.
- **Elevation of privilege** — does a network-reachable path reach a local-only capability (shell, filesystem, cloud metadata, admin API)?

Output: 5–10 boundaries, each with an owner, an asset, and the worst realistic outcome. If a boundary has no stated assumption, that is finding #1.

---

## 3. Static review of network code

Run the tooling, then read the hits — tools find candidates, you decide.

```bash
# Semgrep: security-audit + language packs + custom rules for your own sink list
semgrep --config=p/security-audit --config=p/secrets --config=p/owasp-top-ten .
semgrep --config=auto --sarif -o semgrep.sarif .
# CodeQL (needs a database; JS/Python/Go/Java/C# supported)
codeql database create db --language=python && codeql database analyze db codeql/python-queries --format=sarif-latest -o codeql.sarif
# Joern for data-flow across the codebase when you need "does this HTTP param reach this sink"
joern --script reachability.sc --params cpgFile=cpg.bin
```

Check these classes by hand. Each one is a common, real bug in network daemons and clients:

**Transport**
- TLS verification not disabled anywhere (`verify=False`, `rejectUnauthorized:false`, `InsecureSkipVerify`, `CURLOPT_SSL_VERIFYPEER=0`), including in tests that then get copied to prod.
- Hostname verification present, not just chain validation. Custom CA loading pinned to a bundle that is actually in the image.
- Minimum version and cipher policy stated (TLS 1.2+/1.3); no fallback to plaintext "for speed" without an explicit, logged opt-in.
- Certificate pinning, if claimed, has a rotation path — otherwise it is an outage waiting to happen.
- Cleartext for anything carrying credentials, tokens, cookies or PII.

**Requests and redirects**
- Every outbound call has connect, read and total timeouts. Default library timeouts are "forever".
- Redirects bounded and, for anything user-influenced, restricted in scheme and host; redirect targets re-validated after each hop.
- Proxy environment variables honoured deliberately, not accidentally (an attacker-controlled `HTTP_PROXY` turns your client into their client).
- User-supplied URL, host, port, path or header reaching the socket = SSRF. Needs scheme allowlist, resolved-IP check, private/link-local/metadata ranges blocked after DNS resolution, and re-check on redirect.
- DNS rebinding, IPv4/IPv6 mixed-literal bypasses (`::ffff:169.254.169.254`), decimal/octal IP encodings.

**Framework and protocol**
- Request smuggling conditions: conflicting `Content-Length`/`Transfer-Encoding`, hop-by-hop header stripping at the proxy, HTTP/2 downgrade.
- Header injection: CRLF in any value copied into headers or logs.
- WebSocket: `Origin` check on upgrade, per-message authorization, message size caps, auth timeout on idle sockets.
- gRPC: reflection on in production, unbounded message size, missing deadline propagation.
- Everything exposed twice: `0.0.0.0` bind where `127.0.0.1` was meant, debug/metrics/actuator/admin endpoints reachable from the network.

**Parsing untrusted bytes**
- Size caps before allocation, streaming instead of `readAll`, decompression ratio limits (zip/gzip bombs), nesting depth limits (XML, JSON, YAML, protobuf), regex timeouts.
- XXE disabled, JSON deserialization of untrusted input avoided (or restricted to allowlisted types), no `pickle`/`eval`/`Function` on network input, no unsafe YAML load.
- Path traversal when a network value becomes a filename; archive entry names normalized before extraction.

**Authn, authz, abuse**
- Authentication on every endpoint that is not deliberately public; authorization checked server-side per object, not per route only.
- Tokens: short-lived, audience-scoped, validated (signature, `exp`, `iss`, `aud`), not accepted from query strings, not logged.
- Rate limiting and quotas per identity and per IP, with backoff on repeated failure; account lockout that cannot be used as a DoS against a user.
- CSRF protection where cookies authenticate state-changing requests; `SameSite`, `Secure`, `HttpOnly` set.
- Idempotency and replay protection on webhooks and payment/state-changing callbacks; signature verification with a bounded timestamp window.
- Sequential/guessable resource ids leaking other tenants' data (IDOR).

**Resource behaviour**
- Bounded worker pools, queues and connection caches. Retries with jitter and a cap, no retry storms across a fleet.
- Circuit breakers on dependency failure; a dependency going down must not take the process down.
- Graceful shutdown that drains in-flight requests instead of dropping them.

**Secrets and configuration**
- No keys in source, images, `docker history`, client-side bundles, CI logs, error messages or URLs.
- Secrets from env/secret store, validated at boot, fail closed when missing — no "empty key means disabled auth".
- Fail-closed defaults everywhere: unknown state must deny, not allow.

---

## 4. Dynamic verification (own staging only)

```bash
# baseline DAST on a staging instance you run
docker run -t zaproxy/zap-stable zap-baseline.py -t http://localhost:8080 -r zap.html
# authenticated/API mode: import a context + OpenAPI, then zap-api-scan.py
# template-driven checks with your own templates only
nuclei -u http://localhost:8080 -t ./my-templates/ -severity medium,high,critical
# what the program sends, byte for byte
mitmproxy -p 8081 --set confdir=./mitm        # or: tshark -i any -f "tcp port 8080" -w cap.pcapng
# interact with the daemon and its own metadata endpoint from outside
curl -sv http://localhost:8080/ ; curl -s http://127.0.0.1:8080/metrics
```

Verify, don't assume: reproduce each static finding with one request, save the request/response pair as evidence, then check the fix reproduces the *absence* of the effect. If a finding cannot be reproduced, downgrade it to "unverified" — do not delete it.

Also test the boring failure modes: kill the upstream mid-request, return 500 from a dependency, hand the client a 2 GB response, a slowloris-style trickle, a malformed body, and a valid body with a hostile field.

---

## 5. Telemetry, logging and privacy

- Auth events, authorization denials, state changes and outbound failures logged with actor, request id, outcome — and no secrets, tokens or full PII.
- Log injection impossible (no raw network strings into line-based logs without escaping).
- Retention and access stated; IP addresses, user agents and URLs are personal data under GDPR — minimize, justify, expire.
- Detection readiness: could you notice your own attack? Map the top 3 abuse cases to Sigma (host/log), Suricata (network) or Zeek (protocol) rules, and check the fields you log actually exist in them.

---

## 6. Supply chain and secrets

```bash
trivy fs --scanners vuln,secret,misconfig .        # deps, secrets, docker/IaC misconfig
gitleaks detect --no-git -v                        # working tree secrets
trufflehog filesystem . --only-verified            # verified live credentials
osv-scanner --lockfile=package-lock.json           # advisories for the exact lockfile
```

Check: lockfiles committed, direct AND transitive advisories, packages with install scripts, typosquat neighbours of your dependencies, publishers with a single maintainer for anything in the auth/crypto path, container base image pinned by digest, no `latest` in production, update channel authenticated (signed metadata, HTTPS, pinned keys).

---

## 7. The idea, not just the code

Answer these in the report's first page — a hardening checklist cannot save a design that is wrong:

1. What does the program do to systems its owner does not control, and with whose consent?
2. What is the worst thing a hostile user can do with it *as designed*, assuming the code is bug-free?
3. Which data does it collect about people who never installed it — logs, IPs, fingerprints, scraped content, device identifiers?
4. Where does it break the target's terms, robots.txt, API limits or local law? (In Germany: §202a–c StGB for access/interception, GDPR for personal data, NIS2/CRA obligations once it is a shipped product in the EU.)
5. What happens when it is compromised — does it become a botnet node, an open proxy, a data exfiltration channel?
6. Is the honest description of the product the same as the marketing one? If not, the gap is a design finding.

---

## 8. Report format

```markdown
# Network security review — <target> — <date>

Scope & authorization: <one paragraph from §0>
Verdict: <ship | ship with fixes | do not ship> + the single reason

## Surface
<table from §1>

## Findings
### F-01 <title> — <critical|high|medium|low|info>
- CWE / ASVS ref: CWE-918 SSRF / ASVS 5.0 V12.6.1
- Where: file:line, endpoint, config key
- Trigger: exact request or sequence
- Impact: what an attacker gets, in one sentence
- Evidence: path to request/response, log, SARIF result
- Fix: the change, with the API/flag to use
- Verify: the command that proves the fix
- Status: fixed | open | accepted-risk (with owner and date)

## Design findings
<§7 answers, one per item>

## Not checked / out of scope
<explicit gaps — better than a false clean bill>

## Ethics & legal gate
<from §0, restated as facts about the shipped product>
```

Severity: use CVSS v4 when the finding is remotely reachable without auth; otherwise state the precondition and let severity follow. Cap the report at ~10 findings sorted by real risk — a wall of 60 low findings gets ignored.

---

## 9. Reference sources

Load these before judging, in this order: requirements → test method → tool → ethics.

- **Requirements:** OWASP ASVS 5.0, OWASP Top 10, OWASP API Security Top 10 (and LLM Top 10 if the product has an AI feature).
- **Method:** OWASP WSTG, OWASP Cheat Sheet Series (SSRF Prevention, TLS Cipher String, WebSocket Security, gRPC Security, OS Command Injection Defense, Deserialization, Logging, Secrets Management, User Privacy Protection, Denial of Service).
- **Tooling:** Semgrep + rules, CodeQL, Joern, ZAP, nuclei, mitmproxy, tshark, Trivy, Gitleaks, TruffleHog, OSV-Scanner.
- **AI review harnesses:** `trailofbits/skills` (static-analysis, differential-review, insecure-defaults, sharp-edges, supply-chain-risk-auditor, fp-check, cvss-scoring, yara-authoring), `anthropics/claude-code-security-review` for PR-level diff review.
- **Detection:** Sigma, Suricata, Zeek, YARA.
- **Ethics/law:** RFC 1087, Menlo Report, disclose.io, ACM Code, BSI TR-02102 / IT-Grundschutz, GDPR Art. 32, §202a StGB, NIS2, CRA.

Exact repositories, star counts and what to pull from each: [`references/source-pack.md`](references/source-pack.md).
Line-by-line checklist with CWE/ASVS mapping: [`references/network-checklist.md`](references/network-checklist.md).

---

## 10. Stop conditions

Stop and report instead of guessing when:

- the scope is unclear or the target is not yours;
- testing would touch real user data or production;
- the finding requires breaking encryption or bypassing a third party's protection;
- the program's purpose requires unauthorized access — that is a design-level "do not ship", not a bug to patch;
- a P0 (RCE, auth bypass, open proxy, data leak) is found: report immediately, do not continue the sweep first.
