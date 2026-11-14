---
name: applied-cryptography-engineering
description: Implement robust, industry-standard cryptographic algorithms and protocols. Covers modern authenticated ciphers (AES-256-GCM, ChaCha20-Poly1305, XChaCha20), asymmetric encryption and signatures (X25519, Ed25519), Post-Quantum Cryptography (ML-KEM/Kyber, ML-DSA/Dilithium), CSPRNG generation, and prevention of classic cryptographic pitfalls (ECB mode, padding oracles, nonce reuse, malleability).
---

# Applied Cryptography Engineering Skill

This skill guides agents in selecting, implementing, and reviewing cryptographic primitives and algorithms according to modern cryptographic best practices.

---

## 1. Prime Directive: Never Roll Custom Mathematical Primitives

- **RULE:** Never invent a custom substitution-permutation network, custom stream cipher, or custom hash function.
- **WHAT YOU DO BUILD:** You design custom **protocols, container formats, key derivation flows, and authenticated envelopes** that wrap mathematically vetted, peer-reviewed primitives.

---

## 2. Recommended Cipher Decision Matrix

| Use Case | Recommended Algorithm | Key Size | Nonce / IV | Strengths |
|---|---|---|---|---|
| **High-Performance Hardware** | **AES-256-GCM** | 256 bits | 96 bits (12B) | Hardware accelerated on modern Intel/AMD/ARM (AES-NI). Extreme speed (>4 GB/s). |
| **Software / Mobile / Web** | **ChaCha20-Poly1305** | 256 bits | 96 bits (12B) | Constant-time by design; immune to cache-timing attacks on CPUs without hardware AES. |
| **Randomized Nonces** | **XChaCha20-Poly1305** | 256 bits | 192 bits (24B) | Safe to generate nonces randomly without risk of collision. |
| **Risk of Nonce Reuse** | **AES-256-GCM-SIV** | 256 bits | 96 bits (12B) | Synthetic IV mode (RFC 8452). Prevents catastrophic plaintext recovery if nonces repeat. |
| **Post-Quantum Key Exchange** | **ML-KEM (Kyber-768)** | Lattice-based | N/A | NIST FIPS 203 standard for quantum-resistant key encapsulation. |
| **Digital Signatures** | **Ed25519 (EdDSA)** | 256 bits | N/A | High speed, small keys (32B) and signatures (64B), immune to signature malleability. |
| **Key Agreement (ECDH)** | **X25519** | 256 bits | N/A | Fast, secure Montgomery curve Diffie-Hellman (RFC 7748). |

---

## 3. Forbidden & Deprecated Algorithms (Instant Flag)

If encountered in an application, immediately replace them:

- ❌ **DES / 3DES (Triple DES):** Broken block size (64-bit Sweet32 attack), completely insecure.
- ❌ **RC4:** Biased keystream, trivially cracked in real-time.
- ❌ **AES-ECB mode:** Leaks visual and structural patterns of plaintext (the famous ECB Penguin).
- ❌ **Unauthenticated CBC / CTR mode:** Highly vulnerable to Bit-Flipping attacks and Padding Oracle attacks (Lucky Thirteen, POODLE). Always use AEAD!
- ❌ **MD5 and SHA-1:** Cryptographically broken collision resistance. Use SHA-256, SHA-512, or BLAKE3.
- ❌ **RSA with key size < 2048 bits:** Insecure. Prefer Ed25519 or RSA-4096 with OAEP/PSS padding.

---

## 4. Cryptographically Secure Random Number Generation (CSPRNG)

Security entirely collapses if salts, keys, or nonces are predictable.

### Permitted CSPRNG APIs:
- **Python:** `secrets.token_bytes(n)` or `os.urandom(n)` (NEVER `random.random()`)
- **JavaScript / TypeScript:** `crypto.getRandomValues(new Uint8Array(n))` or Node `crypto.randomBytes(n)` (NEVER `Math.random()`)
- **Rust:** `rand::rngs::OsRng` or `getrandom::getrandom`
- **Go:** `crypto/rand.Read` (NEVER `math/rand`)
- **C / C++:** `sodium_randombytes_buf` (libsodium), `getrandom(2)` (Linux), `BCryptGenRandom` (Windows)

---

## 5. Post-Quantum Hybrid Encryption Pattern

To protect encrypted data against "Harvest Now, Decrypt Later" quantum adversary strategies, combine classical elliptic-curve Diffie-Hellman with Post-Quantum ML-KEM:

```txt
           [ Alice ]                                  [ Bob ]
               |                                         |
     Generate Ephemeral X25519 + ML-KEM-768 Keypairs     |
               |                                         |
               |-------- Send Hybrid Public Keys ------->|
               |                                         |
               |                             Encapsulate ML-KEM Shared Secret (SS_pqc)
               |                             Compute X25519 Shared Secret (SS_ecdh)
               |<------- Send Ciphertext + Ephemeral ----|
               |                                         |
  Decapsulate SS_pqc                                     |
  Compute SS_ecdh                                        |
               |                                         |
      Combined Key = HKDF-Extract(Salt, SS_ecdh || SS_pqc)
               \_________________________________________/
                                    |
                    Both parties share 256-bit AES/ChaCha Key
               (Secure even if quantum computer breaks ECDH!)
```
