# Network review checklist

Line-by-line pass for anything that opens a socket. Every row maps to a CWE; ASVS 5.0 chapter in brackets where it helps. A row is either `pass`, `fail` (→ finding), or `n/a` with a reason — silence is not a pass.

## Transport & TLS

- [ ] TLS verification enabled on every outbound client, in every code path, including tests copied to prod — CWE-295
- [ ] Hostname verified, not only the chain — CWE-297
- [ ] No plaintext fallback for auth, tokens, cookies, PII — CWE-319
- [ ] Minimum TLS 1.2, TLS 1.3 preferred, ciphers from a current policy (BSI TR-02102 / Mozilla intermediate) — CWE-326, CWE-327
- [ ] Custom CA bundle actually shipped in the image/artifact and validated at boot — CWE-295
- [ ] Pinning (if used) has a rotation plan and a kill switch — CWE-295
- [ ] Certificates and keys not in the repo or image layers — CWE-321, CWE-798
- [ ] mTLS, if claimed, verifies the peer certificate's identity, not merely its presence — CWE-295

## Inbound exposure

- [ ] Bind address deliberate: `127.0.0.1` for local-only, `0.0.0.0` only where an external interface is intended — CWE-1327
- [ ] Debug, metrics, actuator, admin, graphql-introspection endpoints not network-reachable in production — CWE-489, CWE-215
- [ ] Unauthenticated endpoints enumerated and intentional — CWE-306
- [ ] Server header / banner leakage minimized — CWE-200
- [ ] Request body size, header size, URL length capped before allocation — CWE-400, CWE-770
- [ ] Slow-client handling: header/body read timeouts, per-connection limits, max concurrent connections — CWE-400
- [ ] Method allowlist per route; `TRACE`/`PUT`/`DELETE` not silently enabled — CWE-650

## Outbound calls & SSRF

- [ ] Every client has connect/read/total timeouts — CWE-1088
- [ ] Retries capped, with jitter and backoff; no cross-fleet retry storm — CWE-1050
- [ ] User-influenced URL/host/port/path/header → allowlist scheme + host, resolve DNS, block private, loopback, link-local, CGNAT, metadata ranges, re-check after redirect — CWE-918
- [ ] IP-literal bypass forms handled (`::ffff:127.0.0.1`, `0177.0.0.1`, `2130706433`, decimal, trailing dot) — CWE-918
- [ ] Redirects: count capped, scheme restricted, target re-validated, credentials dropped on cross-origin — CWE-601
- [ ] Proxy env vars honoured intentionally and never from untrusted input — CWE-441
- [ ] Egress firewall/allowlist for production, not "any host on 443" — CWE-923
- [ ] Webhooks: signature verified with bounded timestamp window, replay rejected, retries idempotent — CWE-347, CWE-294
- [ ] Third-party SDKs: pinned version, no background telemetry the user did not consent to

## Protocol correctness

- [ ] No conflicting `Content-Length`/`Transfer-Encoding`, hop-by-hop headers stripped at the edge (request smuggling) — CWE-444
- [ ] No CRLF from user input reaching headers, cookies or logs — CWE-113
- [ ] HTTP/2 → /1.1 downgrade path reviewed at proxies — CWE-444
- [ ] WebSocket: `Origin` validated on upgrade, per-message authz, size caps, idle timeout — CWE-346
- [ ] gRPC: deadlines propagated, message size capped, reflection off in prod — CWE-400
- [ ] Custom binary/TCP framing: length prefixes validated against remaining buffer, no partial-read trust — CWE-130, CWE-197
- [ ] UDP/DNS: response source validated, case/ID randomized, no cache poisoning trust — CWE-350

## Authentication

- [ ] Passwords hashed with Argon2id/bcrypt/scrypt, not SHA-family — CWE-916
- [ ] Session/token: signed, audience-scoped, `exp` and `iss` checked, revocable — CWE-613
- [ ] Tokens never in URLs, logs, referrers, or frontend bundles — CWE-598
- [ ] Constant-time comparison for tokens/MACs/passwords — CWE-208
- [ ] MFA path cannot be bypassed by calling the second endpoint directly — CWE-287
- [ ] Brute-force limits per identity and per IP, with delay and lockout that cannot DoS a victim — CWE-307, CWE-799

## Authorization

- [ ] Every object access checks ownership/tenant server-side — CWE-639, CWE-862
- [ ] No privilege decision based on client-supplied role/`isAdmin`/hidden field — CWE-602
- [ ] IDs non-enumerable where they are the access control (UUID/opaque), plus real authz — CWE-340
- [ ] Admin/internal endpoints on a separate auth scheme, not a header flag — CWE-863
- [ ] Confused-deputy paths: a privileged component acting on unprivileged input — CWE-441

## Parsing untrusted bytes

- [ ] Size cap before allocation; streaming for large bodies — CWE-400
- [ ] Compression ratio/depth limits (zip, gzip, brotli, nested archives) — CWE-409
- [ ] Nesting depth limits for XML/JSON/YAML/protobuf — CWE-674
- [ ] XXE disabled; external entities and DTDs off — CWE-611
- [ ] No deserialization of untrusted data into arbitrary types (`pickle`, Java serialization, `unserialize`, .NET `BinaryFormatter`) — CWE-502
- [ ] No `eval`/`Function`/`vm`/template evaluation on network input — CWE-95
- [ ] YAML safe loader; no `!!python/object` — CWE-502
- [ ] Regex on user input bounded (no catastrophic backtracking) — CWE-1333
- [ ] Multipart: filename sanitized, entry count/size capped, no path from the client used for writes — CWE-22
- [ ] Archive extraction normalizes entry names, blocks `../` and absolute paths, caps total extracted size — CWE-22, CWE-409
- [ ] Image/PDF/media parsers isolated (separate process/container, resource-limited) — CWE-20
- [ ] Any network value used as a filename, header, command argument or SQL fragment is parameterized/escaped — CWE-78, CWE-89

## State, sessions, caching

- [ ] CSRF protection on cookie-authenticated state changes; `SameSite=Lax/Strict`, `Secure`, `HttpOnly` — CWE-352
- [ ] CORS allowlist exact origins, no `*` with credentials, no reflected `Origin` — CWE-942
- [ ] Cache headers prevent per-user data landing in shared caches — CWE-524
- [ ] Idempotency keys for money/state-changing endpoints — CWE-837
- [ ] Race conditions on balances, quotas, one-time tokens handled with atomic ops/locks — CWE-362
- [ ] Signed URLs/cookies scoped in path, method and lifetime — CWE-613

## Errors, logging, privacy

- [ ] Errors returned to clients carry no stack traces, SQL, paths, versions — CWE-209
- [ ] Auth failures, authz denials, state changes, outbound failures logged with actor + request id — CWE-778
- [ ] No secrets, tokens, cookies, passwords or full PII in logs — CWE-532
- [ ] Line-based logs escape `\r\n` and control chars from network input — CWE-117
- [ ] IP, UA, URL retention justified and expired; GDPR Art. 5/6/32 documented — CWE-359
- [ ] Telemetry/analytics: opt-in where required, documented in the privacy notice

## Availability

- [ ] Worker/thread/connection pools bounded, queue lengths bounded, backpressure visible — CWE-770
- [ ] Circuit breakers and bulkheads around dependencies — CWE-1088
- [ ] Graceful shutdown drains in-flight requests — CWE-404
- [ ] Memory/CPU limits set for the container and the process — CWE-400
- [ ] No unbounded fan-out from a single request (N+1 outbound calls, amplification) — CWE-406

## Supply chain

- [ ] Lockfile committed and used in the build — CWE-1104
- [ ] Advisory scan on exact lockfile (OSV/Trivy) clean of critical/high or triaged — CWE-1395
- [ ] No dependency with install scripts in the auth/crypto path unexplained — CWE-506
- [ ] Base image pinned by digest, non-root, read-only FS where possible — CWE-250
- [ ] Update channel authenticated and signed (or HTTPS + pinned key) — CWE-494
- [ ] Secrets scanner clean on working tree and full history — CWE-798

## Design & ethics

- [ ] Written authorization / ownership for everything the program talks to
- [ ] Target terms, robots.txt, API quotas respected by design, not by accident
- [ ] Third parties' data minimized: no scraping of personal data without a lawful basis
- [ ] Worst case if compromised: cannot become an open proxy, relay, botnet node or exfil channel
- [ ] Security claims in the README match what the code does
- [ ] Vulnerability disclosure path exists (`security.txt` / SECURITY.md) before shipping
- [ ] EU/DE obligations identified: GDPR Art. 32, §202a–c StGB, NIS2, CRA
