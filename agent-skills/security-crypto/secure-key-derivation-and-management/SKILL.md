---
name: secure-key-derivation-and-management
description: Derive, manage, wrap, store, and zeroize cryptographic keys securely. Covers Argon2id parameter tuning, PBKDF2/scrypt comparisons, HKDF (RFC 5869) domain separation, key wrapping (NIST SP 800-38F), in-memory zeroization (explicit_bzero/SecureZeroMemory), page locking (mlock/VirtualLock), and hardware security integration (TPM/Secure Enclave/DPAPI).
---

# Secure Key Derivation & Management Skill

This skill guides agents in implementing hardened key derivation, hierarchical key management, memory protection, and secure destruction of cryptographic material.

---

## 1. Password-Based Key Derivation (KDF)

Passwords and passphrases lack the high entropy required for raw encryption keys. They must be transformed using memory-hard, computationally expensive functions.

### Gold Standard: Argon2id (RFC 9106)
Always prefer **Argon2id** (hybrid of Argon2d and Argon2i) because it provides simultaneous resistance against GPU cracking attacks and side-channel timing attacks.

#### Recommended Production Parameters:
- **Memory Cost (`m`):** At least **64 MB** (`65,536` KiB), ideally **128 MB** to **256 MB** for sensitive file encryption apps.
- **Time Cost / Iterations (`t`):** **3 to 5 iterations**.
- **Parallelism (`p`):** **4 threads** (matches common multi-core hardware).
- **Salt:** At least **16 bytes** (ideally 32 bytes) of pure CSPRNG randomness per file/encryption. Never reuse salt.

### Fallback Standards (Compatibility):
- **scrypt:** Use when Argon2id is not available (e.g., in constrained embedded runtimes). Parameters: $N=2^{16}$ (65536), $r=8$, $p=1$.
- **PBKDF2-HMAC-SHA512:** Use ONLY when required by legacy standards (e.g., FIPS compliance). Minimum **600,000 iterations**. Never use PBKDF2-MD5 or PBKDF2-SHA1.

---

## 2. Key Derivation from High-Entropy Secrets: HKDF (RFC 5869)

When deriving multiple subkeys (e.g., encryption key, MAC key, IV) from an existing master secret or ECDH shared secret:
**Never slice a single key manually with array slicing.** Use **HKDF** (Extract and Expand):

```python
# HKDF-Extract: PRK = HMAC-Hash(salt, IKM)
# HKDF-Expand: OKM = HKDF-Expand(PRK, info, L)

# Info parameter enforces Domain Separation
encryption_key = hkdf_expand(prk, info=b"CustomApp v1 Encryption Key", length=32)
authentication_key = hkdf_expand(prk, info=b"CustomApp v1 Auth Key", length=32)
```

---

## 3. Key Hierarchy Architecture (Envelope Encryption)

In modern cryptographic software, data is never encrypted directly with the user's password-derived key.

```txt
[ User Password / PIN ]
          |
     (Argon2id)
          v
[ Key Encryption Key (KEK) ] ---- Encrypts/Wraps ----> [ Data Encryption Key (DEK) ]
                                                                   |
                                                             (XChaCha20-Poly1305)
                                                                   v
                                                             [ Payload Data ]
```

### Why Envelope Encryption?
1. **Instant Password Changes:** To change the master password, re-derive the new KEK and re-encrypt the 32-byte DEK. You do **not** need to re-encrypt a 50GB data file!
2. **Key Rotation:** New data chunks can be assigned new DEKs while referencing the same user identity.

---

## 4. In-Memory Key Protection & Zeroization

Cryptographic keys stored in normal application memory risk leaking via memory crash dumps, swap files (paging), or memory inspection malware.

### Rules for Sensitive Memory:
1. **Prevent Paging to Disk:**
   - Linux / macOS: Call `mlock(ptr, len)`.
   - Windows: Call `VirtualLock(ptr, len)` or use `CryptProtectMemory`.
2. **Volatile-Safe Zeroization:**
   Compilers optimize away standard `memset(key, 0, len)` calls if the variable is not read again!
   - C / C++: Use `explicit_bzero()` (POSIX), `SecureZeroMemory()` (Windows), or `sodium_memzero()`.
   - Rust: Use `zeroize::Zeroize` or `secrecy::SecretString`.
   - Go: Use `crypto/subtle.ConstantTimeCopy` to clear slices, or avoid GC heap allocations using runtime-pinned buffers.
   - Python / JavaScript: Work with bytearrays and overwrite with zeros before deleting (`buf[:] = b'\x00' * len(buf)`).
3. **Constant-Time Comparison:**
   When verifying keys, hashes, or signatures, ALWAYS use constant-time comparison to prevent timing side-channel attacks:
   - Python: `hmac.compare_digest(a, b)`
   - Node.js: `crypto.timingSafeEqual(a, b)`
   - C: `sodium_memcmp(a, b, len)` or `CRYPTO_memcmp`

---

## 5. OS Keystore Integration

When persisting master keys or recovery secrets locally:
- **Windows:** Windows DPAPI (`CryptProtectData`) or Credential Manager.
- **macOS / iOS:** Apple Keychain Services (`kSecClassGenericPassword`).
- **Linux:** Secret Service API (Freedesktop) or kernel keyring (`keyctl`).
