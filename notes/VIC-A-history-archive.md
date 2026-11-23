# VIC-A technical history archive
No passwords, subscription URLs, HWID values, vault contents or private node endpoints are included.

## Current verified Windows state
Installation Z:\Iran\Browser. Legacy Runtime is separate from encrypted Working-Vault-Preview\WorkingRuntime.
User launched encrypted Working-Vault-Preview\Start-VaultWorkspace.ps1 with explicit -Root WorkingRuntime after migration and confirmed YouTube works.
Do not overwrite working Runtime/vault/profile. Root Start.cmd destination has not been inspected; do not assume it runs the encrypted launcher.

## Subscription investigation, now resolved
Repeated requests with vault metadata produced HTTP200, base64, two zero-UUID placeholders. UA changes and Windows curl through owned SOCKS did not solve it.
Earlier manually entered Inci comparison normalized HWID and did NOT compare the actual old encrypted file.
Legacy source path F:\Data\Iran\LibreWolf Browser\app\secret.ps1; old subscription vpn\sub.txt.enc.
Old container kit-enc/1: PBKDF2 SHA1 (absent prf) or SHA256, 64 bytes split AES256CBC and HMACSHA256; verify MAC(iv+ciphertext) before decrypt; bounded iterations1000..2000000; salt16/iv16/mac32; PKCS7.
Standalone Compare-LegacySubscription.ps1 reads/decrypts in memory, never executes old scripts or writes plaintext. Exact comparison found URL same, UUID genuinely different; UA INCY/3.0.28.
Live old HWID + old UA through existing encrypted config's SOCKS returned HTTP200, six supported nodes, zero skipped.
Opt-in -Apply preserves unique matching outbound, JSON-normalizes dictionary nodes before policy validation, stops fetch children, native-tests candidate, asks APPLY, publishes using encrypted replacement with old encrypted backup.
User successfully applied migration and confirmed YouTube works with encrypted working launcher.
Commits d2527ee original diagnostic; eb5712b missing common import fix;1aa16f8 live old HWID;5122578 apply;ee400fd JSON object normalization fix.
Errors were agent defects, not evidence of wrong passwords: missing Workspace.Common dependency at vault-unlock; missing JSON roundtrip at parse-for-publication.
Do not rerun legacy migration or ask for old passwords without new reason. Normal updater still needs verified tunneled INCY fetch.

## Lifecycle history
Legacy launcher left orphan Xray on17890; no blanket autokill allowed. Path alone doesn't prove orphan age/ownership.
Repair5f4726979aa48cd625d31aacca6ffa18aaf7d17c uses WorkspaceJob.cs, suspended creation, assignment before resume, noninherited unnamed Job KILL_ON_JOB_CLOSE, explicit cleanup confirmation. User Windows ordinary browser close freed17890; forced owner-window close left no Xray. Browser also closed in forced test: independence NOT established.
Repair ZIP is source-only, installed separately VIC-A-Launcher-Repair, uses ../Runtime. It does NOT fix encrypted launcher yet.
Encrypted XrayPipe.cs and CurlPipe.cs currently use Process.Start, not suspended job containment. Must migrate for unified package; don't claim already repaired.

## Standing safety requirements
Official LibreWolf/Xray sources only, retain Authenticode/exact publisher and official-source verification. EXE signature isn't ZIP authentication; GitHub digest not independent archive signature.
Auth before fetch; bounded input/output/timeouts; no secrets on command lines/stderr/files. Keep TEMP/downloads under SSD Runtime. Lock held through cleanup confirmation. No plaintext fallback; strict UUID/TLS/parser policy; JSON-normalize candidate rather than weakening checks. Native validation before encrypted backup/replacement; no partial publication.
Preserve working runtime, vault, profile and binaries. Separate source-only update package with direct GitHub download URL (user cannot use workspace file cards). Static tests are not Windows execution. User rejects repeated speculative diagnostic runs.
Job is not network kill-switch/local SOCKS isolation; browser profile/downloads/old configs remain plaintext. Managed string wiping not guaranteed. Host compromise/power failure/rollback/secure erase not solved. Backups retain old credentials.
Windows PS5.1 x64 required. Current branch arena/690704c9-potential-funicular only. Source repository Mikaso-Nakamoto/potential-funicular.
UI VIC-A, RU/EN; portable Windows own PC now. Linux and two-device migration deferred. Full node menu/migration deferred until safety gates pass.

## Crypto retained
V02: header36/tag16, AES256GCM fresh salt16/nonce12; Argon2id13 ops3 memory64MiB key32; NFC strict UTF8. Six uniformly sampled EFF7776 words ~77.55bits. Official libsodium dependency publisher/runtime checks retained.

## Next task
Build separate unified encrypted launcher + contained processes + authenticated bounded curl SOCKS refresh using working vault HWID and INCY UA. No dependency on old F: after migration. Preserve vault format unless versioned deliberately. Test full packaging/import closure and failure paths; report Windows-only gates honestly. Never promise zero vulnerabilities.
