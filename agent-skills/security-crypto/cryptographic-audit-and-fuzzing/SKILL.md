---
name: cryptographic-audit-and-fuzzing
description: Perform automated security audits, fuzz testing, and formal verification of cryptographic code and binary file parsers. Covers libFuzzer/AFL++ setup for file formats, Known Answer Tests (KAT), Project Wycheproof vulnerability suites, memory sanitizers (ASan/MSan/UBSan), and pre-release security verification checklists.
---

# Cryptographic Audit & Fuzzing Skill

This skill guides agents in testing, fuzzing, and auditing cryptographic applications and custom binary container formats to uncover edge-case vulnerabilities before deployment.

---

## 1. Fuzzing Custom Binary File Parsers

Any code that unpacks binary files, decodes headers, or parses chunk streams is a prime target for buffer overflows, integer overflows, out-of-bounds reads, and panic DoS attacks.

### Fuzzing Strategy with libFuzzer / cargo-fuzz / Atheris:
1. **Target Function:** Isolate the exact decryption/unpacking entrypoint that accepts raw byte slices `(const uint8_t *data, size_t size)`.
2. **Corpus Seeding:** Provide 5 to 10 valid, encrypted containers of various sizes as the initial seed corpus.
3. **Execution with Sanitizers:** Always run fuzzers with AddressSanitizer (ASan) and UndefinedBehaviorSanitizer (UBSan) enabled.

### Example Fuzz Target (Rust / C++ Pattern):
```rust
// In your fuzz_target!
fuzz_target!(|data: &[u8]| {
    // Parser must NEVER panic or segfault, even on heavily corrupted input
    let _ = CustomContainer::parse_and_decrypt(data, "test_password");
});
```

---

## 2. Test Vectors & Known Answer Tests (KAT)

Never assume a cryptographic algorithm is implemented correctly just because it compiles.

### Requirements:
1. **Official RFC / NIST Test Vectors:**
   - For ChaCha20-Poly1305: Validate against RFC 8439 vectors.
   - For AES-GCM: Validate against NIST SP 800-38D vectors.
   - For Argon2id: Validate against RFC 9106 test vectors.
2. **Edge-Case Vectors:**
   - 0-byte plaintext encryption/decryption (empty files).
   - 1-byte plaintext.
   - Exact boundary plaintext sizes (e.g., exactly 65,536 bytes, 65,537 bytes).
   - Maximum allowed file size boundary.

---

## 3. Project Wycheproof Verification

Run test suites from **Google Project Wycheproof** against your chosen cryptographic library bindings. Wycheproof detects:
- Invalid curve attacks on elliptic curve Diffie-Hellman (ECDH).
- Small subgroup attacks.
- Nonce reuse vulnerabilities.
- Weak RSA keys and flawed signature paddings.

---

## 4. Pre-Release Security Audit Checklist

Before releasing any software utilizing encryption:

- [ ] **Primitive Check:** Are all ciphers modern AEAD (AES-256-GCM, ChaCha20-Poly1305, XChaCha20)?
- [ ] **Nonce Uniqueness:** Is there an absolute guarantee that no two operations use the same key + nonce combination?
- [ ] **KDF Hardness:** Is Argon2id configured with at least 64MB memory cost and 3 iterations?
- [ ] **AAD Integrity:** Are all unencrypted header fields included in the AEAD Authenticated Additional Data?
- [ ] **Zeroization:** Are sensitive keys securely wiped from RAM using `explicit_bzero` / `SecureZeroMemory`?
- [ ] **Timing Resistance:** Are all MAC and hash comparisons implemented using constant-time algorithms?
- [ ] **CSPRNG:** Are all salts and nonces sourced from cryptographically secure OS entropy sources?
- [ ] **Fail-Closed Cleanup:** Does the application immediately truncate and securely delete partial files if authentication fails?
- [ ] **Sanitizer Clean:** Has the binary parser run through AddressSanitizer and UndefinedBehaviorSanitizer with zero errors?
