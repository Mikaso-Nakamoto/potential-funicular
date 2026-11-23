# Experimental VICAPK03 envelope

Not integrated into the production V02 launcher. Test-only; no implicit conversion/fallback.

All lengths fixed except encrypted payload, total bounded to 380..1,048,956 bytes. Offsets:

| Offset | Size | Meaning |
|---|---:|---|
| 0 | 8 | ASCII VICAPK03 |
| 8 | 16 | random container ID |
| 24 | 108 | password slot, V02 envelope |
| 132 | 108 | recovery slot, V02 envelope |
| 240 | 140..1,048,716 | data V02 envelope |

Each slot plaintext56 = role8 + containerID16 + random master-secret32. Role ASCII VICPWD03 or VICREC03. Each slot is sealed by unchanged V02 Crypto.Seal with its independent credential. Data credential is lowercase hex encoding of the 32-byte random master-secret (64 characters in SecureString). The actual data AES key is derived using the existing V02 Argon2id function, not the raw master bytes. No custom AES/KDF implementation.

Data plaintext88+payload = ASCII VICDAT03 (8) + containerID16 + SHA256(password slot ciphertext)32 + SHA256(recovery slot ciphertext)32 + payload(0..1MiB). The hashes cover both complete 108-byte V02 slots. Outer magic/role/ID and payload are checked before releasing any user bytes. V02 headers (magic/salt/nonce) are GCM-associated data; inner role/ID/slot digests are GCM-authenticated plaintext. Changing the unused slot is detected even when authenticating with the other slot. Truncation/append/slot swap/cross-container splice rejected.

V02 fixed: ASCII VICAVA02 + salt16 + nonce12 (header36) + AES256GCM ciphertext/tag16. Argon2id13 ops3, memory64MiB, lanes1, key32; NFC strict UTF8 credential encoding. No attacker-supplied iteration/cost parameters. Open attempts at most two fixed-cost V02 opens after bounds/outer format checks.

Creation confirms NFC-equivalent password, enforces heuristic password policy (not entropy estimation), independently generates ten uniform EFF7776 words using existing six-word generator twice and selecting first10 samples, then generates master32 and ID16 via OS CSPRNG. Fresh V02 salts/nonces for all slots/data.

Password change/reset authenticates original envelope/payload and recovery credential, then generates NEW master32 and NEW ID16, wraps with new password and SAME recovery words, and reseals data binding the new slots. Ordinary change therefore requires current password plus recovery words; recovery-only reset needs no current password. Old-backup master cannot decrypt new data. Merely rewrapping a stable master is intentionally not used. Knowing the unchanged recovery phrase still opens new and old versions by design. Full-file rollback cannot be prevented without an external trusted state.

File publication belongs to the PS test harness: exclusive test lock, bounded reads, unique owned stage, Flush(true), staged decrypt+payload comparison with password and recovery credentials, expected ciphertext hash on replacements, File.Replace with encrypted backup, no delete/move fallback for replacement. Not a hostile-filesystem/power-failure guarantee.

A future import must generate a fresh production master and ID rather than reuse any synthetic test master. No production import or cleanup APIs are exposed by this test kit.
