---
name: secure-application-architecture
description: Architect secure desktop, mobile, and web applications for cryptography and cybersecurity. Covers threat modeling (STRIDE), process isolation (sandboxing crypto engines from UI), secure temporary file handling and RAM-only wiping, binary parser memory safety, defense-in-depth, and fail-closed error handling.
---

# Secure Application Architecture Skill

This skill guides agents in designing software architectures for cybersecurity and encryption tools that remain secure even when running on untrusted or partially compromised host systems.

---

## 1. Threat Modeling for Encryption Tools (STRIDE)

Every encryption application faces specific threats:

| Threat Category | Concrete Attack Vector | Required Defense |
|---|---|---|
| **Spoofing** | Attacker swaps legitimate encrypted file with malicious decoy | Cryptographic signatures (Ed25519) on file containers or HMAC tags |
| **Tampering** | Attacker flips bits in encrypted file to alter business logic | Mandatory AEAD (Poly1305 / GCM) authentication; all headers in AAD |
| **Repudiation** | Sender denies authoring an encrypted bundle | Digital signature verification prior to decryption |
| **Information Disclosure** | Plaintext leaks into OS swap file, crash dumps, or temp disk | In-memory zeroization, RAM-only processing, page locking (`mlock`) |
| **Denial of Service** | Malformed headers claim 10TB allocation causing OOM crash | Strict bounds checking on parser inputs; limit maximum chunk to 64KB-1MB |
| **Elevation of Privilege** | Buffer overflow in binary file parser executes shellcode | Safe memory languages (Rust, Go, modern memory-safe C++), ASLR, DEP |

---

## 2. Process Separation Architecture (UI vs. Crypto Engine)

Never execute heavy cryptographic operations or hold master private keys inside the main UI process (Electron, Tauri, Qt, React Native).

```txt
+------------------------------------+
|            UI Process              |
|  - Renders forms, dials, buttons   |
|  - Communicates via strict IPC/RPC |
+-----------------+------------------+
                  |  (JSON-RPC / Protobuf over UNIX Socket or Named Pipe)
                  v
+-----------------+------------------+
|      Isolated Crypto Worker        |
|  - Holds unencrypted keys in RAM  |
|  - Pinned memory (mlock)           |
|  - Sandboxed (pledge/seccomp)      |
|  - No network access permissions   |
+------------------------------------+
```

### Benefits:
1. **Compromise Containment:** If a vulnerability (e.g., XSS in webview or UI exploit) compromises the UI thread, it cannot directly inspect the memory space of the sandboxed crypto worker.
2. **Crash Resilience:** If decryption of a corrupt file triggers an unhandled error, the UI remains responsive and cleans up gracefully.

---

## 3. Secure File & Temporary Data Handling

A common fatal flaw in encryption tools is writing decrypted files to temporary directories (`/tmp` or `C:\Users\...\AppData\Local\Temp`) and relying on OS garbage collection.

### Golden Rules:
1. **Prefer In-Memory Streaming:** Whenever possible, stream decrypted data directly to destination sockets or consumers without ever touching disk.
2. **Never Write Unencrypted Data to Standard Temp:**
   - On SSDs (NAND flash), "deleting" a file simply marks pointers as free; flash translation layers (FTL) wear-leveling prevents true physical overwriting!
   - Plaintext blocks can easily be recovered with basic forensic carving tools.
3. **If Disk Buffering Is Unavoidable:**
   - Create an encrypted virtual RAM-disk.
   - Or encrypt the temporary cache file on the fly with a random ephemeral session key that is discarded upon process exit.
4. **Immediate Fail-Closed Cleanup:**
   If authentication fails midway through a 5GB file, the partially decrypted output file must be truncated, zeroed, and deleted immediately before returning an error to the user.

---

## 4. Hardened Binary Parsing

When parsing custom file headers:
1. **Explicit Length Validation:** Always read field lengths as unsigned big-endian integers (`uint32_be`). Reject values outside allowed bounds before calling `malloc`/`allocate`.
2. **No Dynamic Execution:** Never include serialized code, executable scripts, or deserializers (e.g., Python `pickle`, Java `ObjectInputStream`, PHP `unserialize`) in custom file formats.
3. **Safe Type-Driven Parsing:** Parse formats into immutable domain structs rather than raw pointer arithmetic.
