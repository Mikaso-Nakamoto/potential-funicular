# VIC-A vault preview: format 02 (not a released migration)

## Envelope

`VICAVA02` (8 ASCII bytes) | salt (16 bytes) | nonce (12 bytes) |
AES-256-GCM ciphertext (N bytes) | authentication tag (16 bytes).
The first 36 bytes are authenticated associated data. Plaintext limit: 8 MiB.
Every encryption generates a fresh salt and nonce using libsodium randombytes_buf.
Unknown magic, including preview `VICAVA01`, is rejected without fallback.
No implicit conversion of existing vaults. A future format change needs a new magic
and explicit, tested migration. JSON payload version is separate from crypto version.

## Password and KDF

Input: at most 1024 UTF-16 code units before normalization. Encode NFC-normalized
text as strict UTF-8, with no trimming, case folding or compatibility normalization.
Normalization is identical for creation, confirmation and opening. It does not
correct keyboard layouts or visually similar characters. The temporary normalized
managed string cannot be reliably erased; this is an explicit limitation.

Key: libsodium crypto_pwhash algorithm 2 (Argon2id13), output 32 bytes,
opslimit 3, memlimit 67108864 bytes. This uses libsodium's p=1 mapping; it is NOT
claimed to implement RFC 9106's p=4 recommended profile. Parameters are fixed in
code, never accepted from an unauthenticated file. Changing them requires new magic.

Creation policy: at least 16 UTF-16 code units after NFC, reject a small explicit
set of common patterns, fewer than 8 distinct non-whitespace lowercased characters,
and periodic repetition. This is a rejection heuristic, NOT an entropy estimator
or zxcvbn equivalent. Passing it does NOT imply resistance to offline guessing.
Recommendation: six independently randomly selected words from a trusted password
manager, with an adequately large word list. Password loss is unrecoverable.
Opening does not apply creation heuristics to preserve access if policy evolves.

## Payload and publication

JSON version 1: subscription.url (HTTPS, no userinfo/fragment), subscription.hwid,
activeConfig, optional createdAtUtc. No node list/selection state yet.
Read and write require Assert-VaultDocument, including Assert-ConfigObjectPolicy.
That object policy is the existing tunnel policy factored out of its file wrapper;
no decrypted configuration file is needed for validation.

Read opens one FileStream with FileShare.Read, checks length on that handle,
reads exactly the bounded length and rejects extra/truncated bytes. This narrows
TOCTOU exposure; it is not protection against privileged processes/filesystems.
New vault creation only: CreateNew staging file beside target, write encrypted
bytes, Flush(true), close, authenticate and validate read-back, File.Move without
replacement. Cleanup only removes a staging file this operation created.
No guarantee against all power failures, malicious filesystem changes or rollback.
No update/backup recovery protocol yet. Originals are never automatically deleted.

## Dependency and trust

P/Invoke uses an absolute main DLL path and DefaultDllImportSearchPaths with
DllLoadDir | System32 (requires supported .NET/Windows). No process-global DLL
search mutation. Source SHA-256 is pinned in Vault.Common.ps1; archive SHA-256 is
pinned; installed DLL hash is recorded in a local manifest. These checks do NOT
protect against an attacker able to edit the verifier or manifest.
Installer selects one anchored libsodium-win64/bin/libsodium-N.dll member, checks
listed paths, requires one regular-file listing, and extracts only that member.
This is fail-closed on unfamiliar package layouts, not a general tar validator.

Outstanding release gates: actual official Windows DLL import/dependency review;
Windows bsdtar adversarial archive tests; C# compilation and loader tests in Windows
PowerShell 5.1; file-I/O, policy and failure-path execution tests; full migration,
mandatory unlock, stdin Xray integration and encrypted subscription refresh.
Do not interpret Linux format tests as proof these Windows paths work.
