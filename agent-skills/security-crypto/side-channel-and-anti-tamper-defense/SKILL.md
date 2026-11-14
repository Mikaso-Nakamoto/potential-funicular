---
name: side-channel-and-anti-tamper-defense
description: Defend cryptographic software against side-channel attacks, tampering, and reverse engineering. Covers constant-time programming to prevent timing and cache attacks, padding oracle mitigation, bit-flipping defenses, anti-debugging indicators, integrity self-verification, and secure compilation flags.
---

# Side-Channel & Anti-Tamper Defense Skill

This skill guides agents in eliminating microarchitectural leaks, timing side-channels, and physical tampering vectors in cryptographic implementations.

---

## 1. Timing Attacks & Constant-Time Execution

If the time taken to execute an operation depends on secret data (such as a key byte or password character), an attacker measuring execution time over millions of samples can extract the secret.

### Cardinal Rules of Constant-Time Programming:
1. **No Secret-Dependent Branches:**
   Never branch (`if`, `switch`, ternary `?:`) on secret data.
   ```c
   // VULNERABLE: Leaks the first mismatched byte index via execution time!
   int check_tag(const uint8_t *a, const uint8_t *b, size_t len) {
       for (size_t i = 0; i < len; i++) {
           if (a[i] != b[i]) return 0;
       }
       return 1;
   }

   // SECURE: Constant time bitwise OR accumulator
   int check_tag_constant_time(const uint8_t *a, const uint8_t *b, size_t len) {
       uint8_t diff = 0;
       for (size_t i = 0; i < len; i++) {
           diff |= (a[i] ^ b[i]);
       }
       return diff == 0;
   }
   ```
2. **No Secret-Dependent Memory Lookups:**
   Never use secret values as array indices (e.g., `sbox[secret_byte]`). CPU cache misses create measurable timing variations (Cache-Timing Attacks, Spectre/Meltdown variants).
3. **No Secret-Dependent Variable-Time Arithmetic:**
   Avoid integer division (`/`) or modulo (`%`) on secret keys, as hardware divides in variable clock cycles based on operand size.

---

## 2. Preventing Bit-Flipping & Ciphertext Tampering

In unauthenticated stream ciphers (such as AES-CTR or ChaCha20 without Poly1305), flipping bit $N$ in the ciphertext causes bit $N$ in the decrypted plaintext to flip predictably:

$$C'_n = C_n \oplus \Delta \implies P'_n = P_n \oplus \Delta$$

An attacker can change transfer amounts (e.g., changing `$100` to `$900`) without ever knowing the key!

### The Defense:
Always enforce **AEAD (Authenticated Encryption with Associated Data)**.
If even one bit of the ciphertext or header is modified, the Poly1305 or GCM tag check fails, and **zero bytes of plaintext are released to the application**.

---

## 3. Padding Oracle Defenses

Classic CBC mode encryption requires PKCS#7 padding. When a server or application returns different errors for "invalid padding" vs. "invalid MAC", an attacker can decrypt entire ciphertexts byte by byte (Padding Oracle Attack).

### Defenses:
- Migrate completely away from CBC mode to modern AEAD (GCM or Poly1305).
- If legacy CBC must be supported: Implement **Encrypt-then-MAC (EtM)**. Always verify the HMAC across the entire ciphertext **before** passing it to the AES decryption or unpadding routines.

---

## 4. Anti-Tamper & Binary Hardening Flags

Ensure that compiler security mitigations are enabled during release builds:

### Clang / GCC:
```bash
-fstack-protector-strong      # Stack canaries against buffer overflow
-D_FORTIFY_SOURCE=2           # Runtime bounds checks for standard libc functions
-Wl,-z,relro,-z,now           # Full RELRO (read-only relocation table)
-Wl,-z,noexecstack            # NX / DEP: non-executable stack
-fPIE -pie                    # Full ASLR (Address Space Layout Randomization)
-fsanitize=safe-stack         # SafeStack split stack allocation
```

### MSVC (Windows):
```bash
/GS                           # Buffer security check (stack canaries)
/DYNAMICBASE                  # ASLR
/NXCOMPAT                     # Data Execution Prevention (DEP)
/HIGHENTROPYVA                # 64-bit ASLR
/guard:cf                     # Control Flow Guard (CFG)
```
