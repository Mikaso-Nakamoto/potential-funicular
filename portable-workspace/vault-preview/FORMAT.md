# VIC-A experimental vault — format 02, revision R3

## Status and trust boundary

Not an integrated password-protected launcher. Start/Update still use plaintext
xray.json; browser profile/cookies/downloads are not encrypted. No auto-deletion.
Scripts, verifier, word list, OS and execution environment must be trusted.
Local hash pins detect individual changes, NOT replacement of the whole verifier
and payload. Source distribution authenticity needs an independent trust anchor.
Attacker code execution/admin, preloaded injected modules and rollback are outside
this storage-encryption model. All managed-string erasure is best effort only.

## Envelope (unchanged by R3)

ASCII VICAVA02 (8) | random salt (16) | random nonce (12) | ciphertext (N) | tag (16).
First 36 bytes are GCM associated data. AES-256-GCM from libsodium, no fallback.
Plaintext cap 8 MiB. Unknown magic (including VICAVA01) rejected. Each Seal gets
fresh salt/nonce via randombytes_buf. Key: crypto_pwhash algorithm 2 (Argon2id13),
32 bytes, opslimit=3, memlimit=67108864, libsodium mapping p=1. Not RFC9106 p=4.
NFC then strict UTF-8 on creation, confirmation and opening; no trimming/case fold.
Password input 1..1024 UTF-16 code units; raw Seal has a minimum 16-code-unit guard.
NFC strings/BSTR/JSON may remain in managed memory. Keyboard/IME differences beyond
canonical Unicode equivalence are not corrected. No recovery for a lost phrase.

Magic changes if normalization, KDF parameters, envelope or cipher semantics
change. Word-list/generation policy is NOT decryption metadata and can evolve
without changing magic. Existing valid format-02 data remains readable.

## Creation policy R3 — generated credentials, not a complexity estimator

New-VaultPassphrase calls Crypto.GeneratePassphrase using pinned EFF data:
7776 unique words; six independent selections WITH replacement using libsodium
randombytes_uniform(7776), joined by one ASCII space. No output filtering.
6*log2(7776)=77.548875... bits under trusted, unbiased CSPRNG assumptions.
Exact dictionary bytes/hash/license/provenance: words/NOTICE.md.

GeneratedPassphrase has an internal constructor and owns a SecureString; the
user-facing Write-NewVault only accepts that generated credential type, not raw
user-supplied SecureString text. Prepare displays it and requires hidden re-entry;
it never logs it intentionally, but scrollback/recordings/transcripts can capture
it. No manual choice in this creation workflow. Do not regenerate selectively
until a predictable favourite appears. No built-in dictionary attack estimator.

Crypto.Seal remains an explicitly LOW-LEVEL primitive accepting raw passwords
for synthetic test vectors and interoperability. It does not prove password
strength. Trusted code can bypass wrappers/reflection: this API is not a sandbox
or a boundary against an attacker able to execute/edit scripts. Read accepts
existing passwords, without requiring the current word-list policy.

## Payload and I/O

JSON v1: subscription.url (HTTPS, no userinfo/fragment), subscription.hwid,
activeConfig and optional createdAtUtc. No node list/selection yet.
Assert-VaultDocument checks schema/config on read AND creation.
File wrapper Assert-ConfigPolicy delegates to the existing object tunnel policy.
Vault opens one FileStream with FileShare.Read, bounds length on the handle, reads
exact bytes and rejects truncation/extra bytes. Other reads still need separate
race/resource review. This is not protection against hostile filesystems/reparse.

Create-only: own CreateNew staging beside target, encrypt, Flush(true), close,
authenticate/validate read-back, File.Move without replacement. Cleanup only of
owned stage. No directory flush/write-through protocol, crash-safe replacement,
backup recovery, or power-loss guarantee. Original plaintext is retained.

## Native loading and dependency gate R3

All eight P/Invokes use absolute main DLL path + DllImportSearchPath.System32 ONLY.
UseDllDirectoryForDependencies was removed: lib is NOT a dependency search folder.
Official libsodium 1.0.22 MSVC ZIP SHA-256:
3e03a726fac4bc09cb61d8f29d658ef7a5eca0811de59082130414f7ca2e4279.
Choose one bounded regular x64/Release/v143/dynamic/libsodium.dll ZIP member,
write to fixed staging filename. No archive-controlled extraction paths.
DLL hash in local manifest; runtime version 1.0.22 enforced. MinGW GCC import is
not allowed. MSVC CRT needed on the target PC: vcruntime140[_1].dll checked only
in System32 for Valid Microsoft Authenticode, then their imports inspected too.
No admin/runtime installation/download, PATH lookup, or local runtime deployment.
Core Windows modules/UCRT API contracts remain platform trust, not recursively
audited OS code. Imports checked by DLL name, not imported functions/forwarders
or runtime GetProcAddress. PE delay imports rejected rather than silently skipped.

Common pins Crypto, SodiumPe and gate script hashes; standalone import gate pins
SodiumPe too. These are detection checks rooted in TRUSTED SCRIPTS, not signatures.

## Validation status

R2+compile-fix passed on the user's Windows PowerShell 5.1 x64 (screenshot only;
full log not supplied). That does NOT validate R3. R3 adds word generation,
System32-only loading/canary test, complete negative copies and input hash reports.
Full user-supplied R3 install/test reports are now included under
evidence/r3-windows-user, with all implemented suites reporting PASS on that PC.
19 available input hashes match commit 19fb07f and current executable sources.
The actual DLL/manifest bytes were not provided locally for comparison. Evidence
is unsigned user-provided output, not an independent run or clean-machine matrix.
Linux tests do not execute Windows paths; see evidence README for provenance.

Runner records source/fixture/list/DLL/manifest hashes, PS/CLR/OS versions.
Tests run in fresh processes with full self-contained copies; an unmodified copy
must pass before mutations. Shadowing regression places INVALID IMAGE canaries
next to libsodium, initializes crypto, checks actual VC module paths. It reports
whether VC was already loaded; preloaded state is NOT evidence for first-load
search order, and even a clean process smoke test is not a universal loader proof.
No malicious native code is built or executed. No hostile-ZIP, full-disk, unplug,
power-loss, AES-absent-host, clean-machine matrix or end-to-end migration proof.
