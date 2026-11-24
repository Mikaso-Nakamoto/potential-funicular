# Validation record — VIC-A Updated candidate

## Completed in the Linux sandbox

- 31 pre-existing vault/format/source-contract Python tests PASS, including independent Argon2id/AES-GCM checks; cryptographic implementation/format not modified.
- 8 new unified-package source/packaging contracts PASS: mandatory suspended Job assignment order; fixed modes/no Process.Start fallback; explicit 3-handle inheritance; helper pin; auth-before-tunneled-fetch; exact stored HWID; native/JSON/confirmation/publication order; startup self-check gate; archive manifest and source-only closure; x64 startup layout.
- Tree-sitter: all 7 new PowerShell files and both C# files have no syntax error nodes.
- Roslyn: both new C# files compile/type-check with C#5 language version and .NETCore3.1 references. Main helper successfully emits IL and loads for reflection.
- Runtime Marshal.SizeOf on emitted helper (Linux x64): Security24, Startup104, StartupEx112, ExtendedLimits144, Accounting48, ProcessInfo24. No Win32 APIs called in this check.
- Deterministic source-only ZIP, SHA256 manifest, roundtrip equality, no executable/DLL/vault/encrypted user payloads or Runtime included.
- git diff --check PASS.

Temporary compiler/runtime/test dependencies are outside the repository and are NOT delivered. A PowerShell Linux binary download was blocked by the outbound host restriction. This is not claimed to be PowerShell parser/runtime execution.

## Not completed here

- Compilation by Windows PowerShell5.1 against .NETFramework4.x.
- Execution of CreateProcessW/pipe inheritance/Job APIs on Windows.
- Real-browser and real-provider execution of this new ZIP.

Therefore the menu first executes Test-ContainedSession.ps1 in a fresh PS5.1 process. If it fails, no real session or refresh is enabled. This test covers the specific new native transport, not every possible Windows/OS failure or a security proof. Original already-working encrypted launcher is intentionally preserved as rollback.

## Windows acceptance after the automatic gate

1. Offline validate (menu4): authenticate existing vault and native-test using contained stdin.
2. Check subscription (menu2): verify six supported entries/unchanged vault using the migrated HWID, without publication.
3. Browser (menu1): YouTube/IP/DNS/disconnect checks; ordinary browser close must free17890.
4. Forced session-window close must leave no owned Xray/curl. Browser independence is not claimed until observed.
5. Only then update (menu3 + UPDATE): encrypted backup retained, candidate native-valid, vault reopens and browser works.

Do not bypass containment/signature/hash checks to pass these gates. No guarantee of zero vulnerabilities, secure erase, hostile-host resistance, antirollback, power-loss durability or system-wide network isolation is made.
