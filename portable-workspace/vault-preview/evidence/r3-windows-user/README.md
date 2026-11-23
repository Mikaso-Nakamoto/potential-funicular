# User-supplied R3 Windows evidence

## Provenance and scope

The user uploaded these two original TXT files after running the R3 test kit.
They are preserved byte-for-byte, including BOM/newlines. No redaction or
normalization was needed: the supplied content contains synthetic-test diagnostics,
OS/runtime versions, hashes and relative source names, not real subscriptions,
HWID, passphrases, browser state or absolute personal profile paths.
The user authorized publishing them with the audit handoff.

Tested source commit: `19fb07f18686d96e47252432869a69eccedc6431`.
These reports were supplied after that commit, not included retrospectively in it.
This evidence commit changes docs/report tooling, NOT the executable vault source.

Original-file SHA-256:

- `vault-install-report.txt`: `97cce818688a9d8ebd3a5f68a4f879623cd0b80f67c8a877dbb90d01e52fd93f`
- `vault-test-report.txt`: `fc1afb0a3b98424a7b204f88de799b7e8426c9a9dd670a42ea5f46e6817e14ff`

Recorded environment: Windows PowerShell 5.1.26100.10068, x64,
CLR 4.0.30319.42000, OS reported as Windows NT 10.0.26300.0.
The OS string is reproduced as logged; it is not a separate OS attestation.

## Verification and result

19 logged source/fixture/list hashes match the source commit and the current
unchanged executable inputs. Reproduce without Git/network:

```sh
python portable-workspace/vault-preview/Verify-WindowsEvidence.py
```

The report also records two installation-dependent hashes whose underlying bytes
were NOT uploaded or compared locally:

- `lib/vica-sodium.dll`: `f656aeb789bfc3a2ac587fae1d7cfe278bbe8ce73f28da73b4d08282ea8f9fe3`
- `lib/dependency.json`: `8352a39f251a2a5cec54e0ea470a68b48ef17906ad85d67d12d9fcf48a446b3e`

The reports state installation PASS and PASS for all implemented R3 suites:
PE inspection, generated phrase samples, crypto/NFC, file I/O and config policy,
full-copy baseline, neighbouring dependency canary, and five isolated mutations.
Canary explicitly reports VC runtime was not preloaded before the test and the
loaded module path was System32\VCRUNTIME140.dll.

This is a useful process-local loader regression, not proof for every loader state.
The reports are unsigned user-provided outputs. Matching hashes establish consistency
of the DECLARED inputs with source, not unforgeable proof of execution. The agent
has not independently executed Windows tests or verified the actual installed
native binary. This was not a clean-machine or multi-CPU validation.

No evidence here establishes hostile-ZIP safety, AES-unavailable behaviour,
disk-full/power-loss durability, migration or password enforcement in Start/Update.
Do not delete original plaintext configurations based on this test result.
The unchanged `VIC-A-Vault-Test-Kit-R3.zip` can be used for independent reproduction;
the updated expert bundle includes these reports plus current documentation.
