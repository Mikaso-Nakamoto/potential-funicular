using System;
using System.Runtime.InteropServices;
using System.Security;
using System.Text;
namespace VicAVault {
    // Crypto operations are provided by libsodium, not implemented here.
    public static class Crypto {
        private const string Dll = @"__SODIUM_DLL__";
        private const int HeaderSize = 36;
        private const int Maximum = 8 * 1024 * 1024;
        private static readonly byte[] Magic = Encoding.ASCII.GetBytes("VICAVA02");
        [DefaultDllImportSearchPaths(DllImportSearchPath.DllLoadDir | DllImportSearchPath.System32)]
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern int sodium_init();
        [DefaultDllImportSearchPaths(DllImportSearchPath.DllLoadDir | DllImportSearchPath.System32)]
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern int crypto_aead_aes256gcm_is_available();
        [DefaultDllImportSearchPaths(DllImportSearchPath.DllLoadDir | DllImportSearchPath.System32)]
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern void randombytes_buf([Out] byte[] output, UIntPtr size);
        [DefaultDllImportSearchPaths(DllImportSearchPath.DllLoadDir | DllImportSearchPath.System32)]
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern int crypto_pwhash([Out] byte[] key, ulong length, byte[] password, ulong passwordLength, byte[] salt, ulong ops, UIntPtr memory, int algorithm);
        [DefaultDllImportSearchPaths(DllImportSearchPath.DllLoadDir | DllImportSearchPath.System32)]
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern int crypto_aead_aes256gcm_encrypt([Out] byte[] cipher, out ulong cipherLength, byte[] message, ulong messageLength, byte[] ad, ulong adLength, IntPtr secretNonce, byte[] nonce, byte[] key);
        [DefaultDllImportSearchPaths(DllImportSearchPath.DllLoadDir | DllImportSearchPath.System32)]
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern int crypto_aead_aes256gcm_decrypt([Out] byte[] message, out ulong messageLength, IntPtr secretNonce, byte[] cipher, ulong cipherLength, byte[] ad, ulong adLength, byte[] nonce, byte[] key);
        public static void CheckSupport() {
            if (!Environment.Is64BitProcess) throw new InvalidOperationException("64-bit PowerShell required.");
            if (sodium_init() < 0 || crypto_aead_aes256gcm_is_available() != 1)
                throw new InvalidOperationException("AES-GCM acceleration unavailable. No weaker fallback is used.");
        }
        private static byte[] PasswordBytes(SecureString password) {
            if (password == null || password.Length < 1 || password.Length > 1024) throw new ArgumentException("Invalid password length.");
            IntPtr ptr = IntPtr.Zero;
            char[] chars = new char[password.Length];
            try {
                ptr = Marshal.SecureStringToBSTR(password);
                for (int k = 0; k < chars.Length; k++) chars[k] = (char)Marshal.ReadInt16(ptr, k * 2);
                return new UTF8Encoding(false, true).GetBytes(new string(chars).Normalize(NormalizationForm.FormC));
            } finally {
                Array.Clear(chars, 0, chars.Length);
                if (ptr != IntPtr.Zero) Marshal.ZeroFreeBSTR(ptr);
            }
        }
        private static byte[] Derive(SecureString password, byte[] salt) {
            byte[] bytes = PasswordBytes(password), key = new byte[32];
            try {
                // Fixed parameters bound CPU/RAM cost even when an attacker edits the envelope.
                // libsodium algorithm 2 = Argon2id13, opslimit=3, memlimit=64 MiB.
                if (crypto_pwhash(key, 32, bytes, (ulong)bytes.Length, salt, 3, new UIntPtr(67108864), 2) != 0)
                    throw new InvalidOperationException("Password KDF failed.");
                return key;
            } catch { Array.Clear(key, 0, key.Length); throw; }
            finally { Array.Clear(bytes, 0, bytes.Length); }
        }
        // Deliberately conservative rejection heuristics, NOT an entropy estimate.
        // Prefer six independently random words from a reputable password manager.
        public static void ValidateNewPassword(SecureString password) {
            byte[] encoded = PasswordBytes(password);
            try {
                string text = new UTF8Encoding(false, true).GetString(encoded);
                if (text.Length < 16) throw new ArgumentException("Use at least 16 characters after NFC normalization.");
                string folded = text.ToLowerInvariant();
                string[] common = { "password", "qwerty", "123456", "letmein", "пароль", "йцукен" };
                foreach (string item in common)
                    if (folded.Contains(item)) throw new ArgumentException("Common password pattern. Use a randomly generated passphrase.");
                int distinct = 0;
                for (int i = 0; i < folded.Length; i++)
                    if (!Char.IsWhiteSpace(folded[i]) && folded.IndexOf(folded[i]) == i) distinct++;
                if (distinct < 8) throw new ArgumentException("Too few distinct characters. Use a randomly generated passphrase.");
                for (int period = 1; period <= text.Length / 2; period++) {
                    bool repeats = true;
                    for (int i = period; i < text.Length; i++) if (folded[i] != folded[i % period]) { repeats = false; break; }
                    if (repeats) throw new ArgumentException("Repeated password pattern. Use a randomly generated passphrase.");
                }
            } finally { Array.Clear(encoded, 0, encoded.Length); }
        }
        public static byte[] Seal(byte[] plaintext, SecureString password) {
            CheckSupport();
            if (plaintext == null || plaintext.Length > Maximum || password == null || password.Length < 16)
                throw new ArgumentException("Use a passphrase of at least 16 characters; payload limit is 8 MiB.");
            ValidateNewPassword(password);
            byte[] salt = new byte[16], nonce = new byte[12], header = new byte[HeaderSize], key = null;
            randombytes_buf(salt, new UIntPtr(16)); randombytes_buf(nonce, new UIntPtr(12));
            Buffer.BlockCopy(Magic, 0, header, 0, 8);
            Buffer.BlockCopy(salt, 0, header, 8, 16); Buffer.BlockCopy(nonce, 0, header, 24, 12);
            try {
                key = Derive(password, salt);
                byte[] cipher = new byte[plaintext.Length + 16]; ulong length;
                if (crypto_aead_aes256gcm_encrypt(cipher, out length, plaintext, (ulong)plaintext.Length, header, HeaderSize, IntPtr.Zero, nonce, key) != 0 || length != (ulong)cipher.Length)
                    throw new InvalidOperationException("Encryption failed.");
                byte[] envelope = new byte[HeaderSize + cipher.Length];
                Buffer.BlockCopy(header, 0, envelope, 0, HeaderSize); Buffer.BlockCopy(cipher, 0, envelope, HeaderSize, cipher.Length);
                return envelope;
            } finally { if (key != null) Array.Clear(key, 0, key.Length); }
        }
        public static byte[] Open(byte[] envelope, SecureString password) {
            CheckSupport();
            if (envelope == null || envelope.Length < HeaderSize + 16 || envelope.Length > Maximum + HeaderSize + 16)
                throw new ArgumentException("Invalid vault or wrong password.");
            for (int k = 0; k < Magic.Length; k++) if (envelope[k] != Magic[k]) throw new ArgumentException("Invalid vault or wrong password.");
            byte[] header = new byte[HeaderSize], salt = new byte[16], nonce = new byte[12], key = null;
            Buffer.BlockCopy(envelope, 0, header, 0, HeaderSize); Buffer.BlockCopy(header, 8, salt, 0, 16); Buffer.BlockCopy(header, 24, nonce, 0, 12);
            byte[] cipher = new byte[envelope.Length - HeaderSize], message = new byte[cipher.Length - 16];
            Buffer.BlockCopy(envelope, HeaderSize, cipher, 0, cipher.Length);
            try {
                key = Derive(password, salt); ulong length;
                if (crypto_aead_aes256gcm_decrypt(message, out length, IntPtr.Zero, cipher, (ulong)cipher.Length, header, HeaderSize, nonce, key) != 0 || length != (ulong)message.Length)
                    throw new ArgumentException("Invalid vault or wrong password.");
                return message;
            } catch { Array.Clear(message, 0, message.Length); throw; }
            finally { if (key != null) Array.Clear(key, 0, key.Length); }
        }
    }
}
