---
name: cryptographic-file-format-design
description: Design and implement secure, tamper-proof custom encrypted file formats and container specifications. Covers binary envelope layout, magic bytes, protocol versioning, cipher suite negotiation, salt/nonce generation, chunked streaming encryption, Authenticated Additional Data (AAD), truncation attack defense, and format forward compatibility.
---

# Cryptographic File Format Design Skill

This skill guides agents in architecting and implementing custom encrypted container and file formats that are mathematically sound, immune to tampering, and protected against modern cryptographic attack vectors.

---

## 1. Fundamental Architecture of a Secure Container

A secure encrypted container must NEVER be just raw ciphertext. It must be an authenticated binary envelope containing all parameters required for decryption while guaranteeing that **no parameter can be altered by an adversary without immediate authentication failure**.

### Standard Envelope Layout (Byte Structure)

```txt
+-----------------------------------------------------------------------+
| Header (Cleartext, Authenticated via AAD)                            |
| 1. Magic Bytes        : 4 bytes (e.g., 0x53, 0x45, 0x43, 0x46 "SECF")  |
| 2. Format Version     : 2 bytes (uint16_be, e.g., 0x0001)             |
| 3. Cipher Suite ID    : 2 bytes (uint16_be, e.g., 0x0001 = XChaCha20) |
| 4. KDF Algorithm ID   : 2 bytes (uint16_be, e.g., 0x0001 = Argon2id)  |
| 5. KDF Parameters     : Memory (4B), Time/Iterations (4B), Lanes (2B) |
| 6. KDF Salt           : 16 to 32 bytes (CSPRNG generated)             |
| 7. Master Nonce / IV  : 12 to 24 bytes (CSPRNG generated)             |
| 8. Chunk Size         : 4 bytes (e.g., 65536 bytes = 64 KB)           |
+-----------------------------------------------------------------------+
| Payload (Stream of Authenticated Chunks)                             |
| Chunk 0: [ Encrypted Payload ] + [ 16-byte Poly1305 / GCM Tag ]       |
| Chunk 1: [ Encrypted Payload ] + [ 16-byte Poly1305 / GCM Tag ]       |
| ...                                                                   |
| Final Chunk: [ Encrypted Payload ] + [ 16-byte Tag ] (Final Flag Set) |
+-----------------------------------------------------------------------+
```

---

## 2. Mandatory Rules for Custom Formats

### Rule 1: Authenticate the Entire Header via AAD
Every single byte of the unencrypted header (magic bytes, version, cipher ID, salt, chunk size) **MUST be fed into the AEAD cipher as Authenticated Additional Data (AAD)**.
- **Why:** If an attacker modifies the cipher suite ID (e.g., downgrades from AES-256-GCM to a weaker mode) or changes the KDF iteration count in the header, the AEAD authentication tag check will fail immediately and abort decryption.

### Rule 2: Never Reuse a Nonce / IV (Catastrophic Failure)
- In AES-GCM and ChaCha20-Poly1305, encrypting two different blocks with the same key and nonce leaks the authentication key and allows plaintext recovery.
- **Recommendations:**
  - For randomized nonce generation: Use **XChaCha20-Poly1305** or **AES-GCM-SIV** with a 192-bit (24-byte) nonce. Collision probability is negligible ($2^{-96}$).
  - If using standard AES-256-GCM (96-bit / 12-byte nonce): Nonce MUST be split into a random prefix (8 bytes) + sequential chunk counter (4 bytes).

### Rule 3: Chunked Streaming Encryption (Avoid In-Memory Loading)
Never load an entire 10GB file into RAM to encrypt or decrypt.
- Split files into fixed chunks (typically **64 KB** = `65,536` bytes).
- Each chunk is encrypted with its own derived nonce: `chunk_nonce = master_nonce XOR chunk_index` or incremented counter.
- **Chunk Tagging:** The final chunk must have a `is_final` flag included in its AAD or chunk metadata.
- **Defense Against Truncation Attacks:** If an attacker cuts off the last 20MB of an encrypted file, decryption must fail with `PrematureEOFError` because the final chunk tag was not reached.

---

## 3. Cipher Suite Identifiers (Extensibility)

Reserve a 2-byte field for cipher suites to support algorithm agility and post-quantum migration:

| Suite ID | Symmetric Cipher | Key Size | Nonce Size | MAC / Tag Size |
|---|---|---|---|---|
| `0x0001` | XChaCha20-Poly1305 | 256 bits | 192 bits (24B) | 128 bits (16B) |
| `0x0002` | AES-256-GCM | 256 bits | 96 bits (12B) | 128 bits (16B) |
| `0x0003` | ChaCha20-Poly1305 | 256 bits | 96 bits (12B) | 128 bits (16B) |
| `0x0004` | AES-256-GCM-SIV (Nonce-misuse resistant) | 256 bits | 96 bits (12B) | 128 bits (16B) |
| `0x0100` | Hybrid Post-Quantum (ML-KEM-768 + XChaCha20) | 256 bits | 192 bits (24B) | 128 bits (16B) |

---

## 4. Reference Implementation Blueprint (Pseudo-code)

```python
# Encrypting a chunked custom container
def encrypt_container(input_stream, output_stream, passphrase):
    # 1. Generate cryptographic salt and base nonce
    salt = csprng(32)
    master_nonce = csprng(24)  # For XChaCha20
    
    # 2. Derive master key using Argon2id
    key = argon2id_derive(passphrase, salt, time_cost=3, memory_cost=65536, parallelism=4, key_len=32)
    
    # 3. Construct Header
    header = struct.pack(">4sHHHHII", b"SECF", 1, SUITE_XCHACHA20, KDF_ARGON2ID, 4, 3, 65536)
    header += salt + master_nonce
    output_stream.write(header)
    
    # 4. Stream and Encrypt Chunks
    chunk_index = 0
    while True:
        chunk = input_stream.read(65536)
        is_final = len(chunk) < 65536 or input_stream.peek() == b""
        
        # AAD binds chunk index and final status to header
        aad = header[:8] + struct.pack(">IB", chunk_index, 1 if is_final else 0)
        chunk_nonce = derive_chunk_nonce(master_nonce, chunk_index)
        
        ciphertext, tag = aead_encrypt(key, chunk_nonce, chunk, aad)
        output_stream.write(struct.pack(">I", len(ciphertext)) + ciphertext + tag)
        
        if is_final:
            break
        chunk_index += 1
```

---

## 5. Security Checklist for Binary File Parsers

- [ ] Header size check: Validate that the input file is at least as large as the minimum header size before reading.
- [ ] Magic bytes validation: Immediate rejection if magic bytes do not match.
- [ ] Supported version check: Explicitly reject versions greater than the maximum supported version.
- [ ] Allocation limit guard: Never allocate memory based on an untrusted header field (e.g., if header claims chunk size is 4GB, reject).
- [ ] Constant-time MAC check: The AEAD tag check must be strictly constant-time.
- [ ] Fail-closed: On any decryption error, delete any partially written plaintext files immediately.
