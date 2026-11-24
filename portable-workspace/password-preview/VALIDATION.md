# Validation scope — isolated password/recovery preview

No production migration or cleanup is present. All development tests use synthetic credentials and in-memory payloads.

- New envelope + Windows self-check C# compiled together with the unchanged pinned VaultCrypto.cs using Roslyn C#5/.NETCore3.1 references, then emitted IL and executed on Linux x64 with official libsodium1.0.22 built from upstream tag1.0.22-RELEASE (commit77e1ce5d6dee871c49ef211222ba18ef0c486bda).
- Runtime suite46 checks PASS: both access modes; ten generated words; wrong credentials; slot-role confusion; tampering across outer header/ID/both slots/payload; truncation/append; slot swap/cross-container splice including unused recovery; password policy; NFC-equivalent confirmation; password change/recovery reset; old passwords rejected by current version; caller arrays unchanged on failures; fresh ID/master; old-backup master cannot decrypt new data; independent Argon2id/AESGCM opening of both slots and payload using argon2-cffi/cryptography. Includes execution of the exact C# Windows self-check (17 assertions) delivered in the ZIP.
- NFC checked with ICU enabled. .NETCore invariant globalization was NOT treated as equivalent to real NFC behavior; invariant-mode normalization does not satisfy this gate.
- Seven static/ZIP source contracts PASS: source pins/base primitives, bounds/role/slot binding, new key+ID on changes, ten uniform words, no Runtime/production import/cleanup calls, staged readback+both credentials before publication, source-only ZIP/manifest closure.
- Existing31 vault/format and8 unified-launcher Python tests still PASS; production sources not changed.
- PowerShell/C# tree-sitter parsing PASS. This is not execution of the PS wrapper or an official PowerShell parser.

Remaining Windows gate: PowerShell5.1/.NETFramework compilation, actual dependency/import checks, stage/readback/replace and hidden console input. Start-Test.cmd runs the17 C# self-checks before asking for user credentials, then the user verifies creation, reopen with password, reopen with recovery, restart and recovery reset on synthetic test.vault only.

No independent security audit or zero-vulnerability claim. Limits: offline password guessing, managed strings/pagefile/console scrollback, retained encrypted backups and rollback, local hostile filesystem/host compromise, power-failure behavior. See README and FORMAT. Test master secrets must never be reused for future production migration.

Developer runtime reproduction (not required on user PC): set VICA_RUNTIMECONFIG, VICA_DOTNET, VICA_ROSLYN, VICA_SODIUM to test runtime/assemblies/official Linux libsodium paths; enable non-invariant ICU globalization; install pythonnet, argon2-cffi and cryptography outside the repo; execute tests/runtime_envelope.py from repo root. No downloads are performed by that script and no crypto support/version checks are bypassed. Development runtimes/compilers are not shipped in the Windows ZIP.

Minimum-password update: test-only packaged Crypto.Seal minimum is8 (production source unchanged). Argon2id/AES-GCM and the envelope format are unchanged. Eight characters permit substantially easier offline guessing; prefer a longer random password.
