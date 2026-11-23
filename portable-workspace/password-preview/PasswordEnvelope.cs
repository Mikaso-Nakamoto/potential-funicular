namespace VicaPasswordPreview {
    using System;
    using System.Security;
    using System.Text;
    using System.Security.Cryptography;
    using VicAVault;

    public sealed class Created : IDisposable {
        public byte[] Envelope { get; private set; }
        public GeneratedPassphrase Recovery { get; private set; }
        internal Created(byte[] bytes, GeneratedPassphrase recovery) { Envelope = bytes; Recovery = recovery; }
        public void Dispose() {
            if (Envelope != null) { Array.Clear(Envelope,0,Envelope.Length); Envelope = null; }
            if (Recovery != null) { Recovery.Dispose(); Recovery = null; }
        }
    }
    // Nested, unchanged V02 libsodium envelopes; no new cipher/KDF implementation.
    // Fixed slots and per-container role/ID binding. Payload authenticates both slots' SHA256 hashes.
    public static class Envelope {
        const int Header = 24, Slot = 108, Prefix = 88, Maximum = 1048576;
        static readonly byte[] Magic = Encoding.ASCII.GetBytes("VICAPK03");
        static readonly byte[] PasswordTag = Encoding.ASCII.GetBytes("VICPWD03");
        static readonly byte[] RecoveryTag = Encoding.ASCII.GetBytes("VICREC03");
        static readonly byte[] DataTag = Encoding.ASCII.GetBytes("VICDAT03");
        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false,true);
        static void Wipe(byte[] value) { if (value != null) Array.Clear(value,0,value.Length); }
        static byte[] Slice(byte[] value,int offset,int count) { byte[] result = new byte[count]; Buffer.BlockCopy(value,offset,result,0,count); return result; }
        static bool Equal(byte[] left,byte[] right) {
            if (left == null || right == null || left.Length != right.Length) return false;
            int different = 0; for (int i=0;i<left.Length;i++) different |= left[i] ^ right[i]; return different == 0;
        }
        static byte[] Digest(byte[] bytes) { using (SHA256 sha = SHA256.Create()) return sha.ComputeHash(bytes); }
        static byte[] SecretBytes(SecureString value) {
            if (value == null || value.Length < 1 || value.Length > 1024) throw new ArgumentException("Invalid credential.");
            IntPtr pointer = IntPtr.Zero; char[] chars = new char[value.Length];
            try {
                pointer = System.Runtime.InteropServices.Marshal.SecureStringToBSTR(value);
                for (int i=0;i<chars.Length;i++) chars[i] = (char)System.Runtime.InteropServices.Marshal.ReadInt16(pointer,2*i);
                return Utf8.GetBytes(new string(chars).Normalize(NormalizationForm.FormC));
            } finally {
                Array.Clear(chars,0,chars.Length);
                if (pointer != IntPtr.Zero) System.Runtime.InteropServices.Marshal.ZeroFreeBSTR(pointer);
            }
        }
        public static void ValidatePassword(SecureString password,SecureString confirmation) {
            byte[] first = null, second = null;
            try {
                first = SecretBytes(password); second = SecretBytes(confirmation);
                if (!Equal(first,second)) throw new ArgumentException("Password confirmation differs.");
                string text = Utf8.GetString(first);
                int count = 0; var distinct = new System.Collections.Generic.HashSet<int>(); bool digitsOnly = true;
                for (int i=0;i<text.Length;i++) {
                    if (Char.IsControl(text[i]) || Char.GetUnicodeCategory(text,i) == System.Globalization.UnicodeCategory.Format) throw new ArgumentException("Control/format characters prohibited.");
                    int scalar = Char.ConvertToUtf32(text,i); if (Char.IsHighSurrogate(text[i])) i++;
                    count++; distinct.Add(scalar); if (scalar < '0' || scalar > '9') digitsOnly = false;
                }
                if (count < 16 || count > 256 || distinct.Count < 6 || digitsOnly || Char.IsWhiteSpace(text[0]) || Char.IsWhiteSpace(text[text.Length-1]))
                    throw new ArgumentException("Use 16-256 characters, at least 6 different; no all-digit or edge-whitespace password.");
                string lower = text.ToLowerInvariant();
                for (int period=1;period<=text.Length/2;period++) {
                    bool repeated = true;
                    for (int i=period;i<lower.Length;i++) if (lower[i] != lower[i%period]) { repeated = false; break; }
                    if (repeated) throw new ArgumentException("Repeated password pattern prohibited.");
                }
                if ("abcdefghijklmnopqrstuvwxyz".Contains(lower) || "zyxwvutsrqponmlkjihgfedcba".Contains(lower) || lower.StartsWith("qwerty") || lower.StartsWith("password") || lower.StartsWith("123456"))
                    throw new ArgumentException("Obvious password pattern prohibited.");
                // Heuristics, not an entropy estimator or an exhaustive leaked-password database.
            } finally { Wipe(first); Wipe(second); }
        }
        static SecureString MasterSecret(byte[] master) {
            var secret = new SecureString(); const string digits = "0123456789abcdef";
            foreach (byte b in master) { secret.AppendChar(digits[b>>4]); secret.AppendChar(digits[b&15]); }
            secret.MakeReadOnly(); return secret;
        }
        static void Check(byte[] envelope) {
            if (envelope == null || envelope.Length < Header+2*Slot+Prefix+52 || envelope.Length > Header+2*Slot+Prefix+52+Maximum || !Equal(Slice(envelope,0,8),Magic))
                throw new ArgumentException("Invalid envelope or credential.");
        }
        static byte[] MakeSlot(byte[] id,byte[] master,SecureString credential,bool recovery) {
            byte[] plain = new byte[56];
            try {
                Buffer.BlockCopy(recovery ? RecoveryTag : PasswordTag,0,plain,0,8);
                Buffer.BlockCopy(id,0,plain,8,16); Buffer.BlockCopy(master,0,plain,24,32);
                return Crypto.Seal(plain,credential);
            } finally { Wipe(plain); }
        }
        static byte[] ReadMaster(byte[] envelope,SecureString credential,bool recovery) {
            Check(envelope); byte[] slot = Slice(envelope,Header+(recovery ? Slot : 0),Slot), plain = null;
            try {
                plain = Crypto.Open(slot,credential);
                if (plain.Length != 56 || !Equal(Slice(plain,0,8),recovery ? RecoveryTag : PasswordTag) || !Equal(Slice(plain,8,16),Slice(envelope,8,16))) throw new ArgumentException();
                return Slice(plain,24,32);
            } finally { Wipe(plain); }
        }
        static byte[] ReadPayload(byte[] envelope,byte[] master) {
            byte[] plain = null;
            using (SecureString secret = MasterSecret(master)) {
                try {
                    plain = Crypto.Open(Slice(envelope,Header+2*Slot,envelope.Length-Header-2*Slot),secret);
                    if (plain.Length < Prefix || plain.Length > Prefix+Maximum || !Equal(Slice(plain,0,8),DataTag) || !Equal(Slice(plain,8,16),Slice(envelope,8,16)) ||
                        !Equal(Slice(plain,24,32),Digest(Slice(envelope,Header,Slot))) || !Equal(Slice(plain,56,32),Digest(Slice(envelope,Header+Slot,Slot)))) throw new ArgumentException();
                    return Slice(plain,Prefix,plain.Length-Prefix);
                } finally { Wipe(plain); }
            }
        }
        static byte[] Pack(byte[] id,byte[] passwordSlot,byte[] recoverySlot,byte[] master,byte[] payload) {
            if (payload == null || payload.Length > Maximum || passwordSlot.Length != Slot || recoverySlot.Length != Slot) throw new ArgumentException();
            byte[] plain = new byte[Prefix+payload.Length];
            try {
                Buffer.BlockCopy(DataTag,0,plain,0,8); Buffer.BlockCopy(id,0,plain,8,16);
                Buffer.BlockCopy(Digest(passwordSlot),0,plain,24,32); Buffer.BlockCopy(Digest(recoverySlot),0,plain,56,32);
                Buffer.BlockCopy(payload,0,plain,Prefix,payload.Length);
                using (SecureString secret = MasterSecret(master)) {
                    byte[] data = Crypto.Seal(plain,secret), result = new byte[Header+2*Slot+52+plain.Length];
                    Buffer.BlockCopy(Magic,0,result,0,8); Buffer.BlockCopy(id,0,result,8,16);
                    Buffer.BlockCopy(passwordSlot,0,result,Header,Slot); Buffer.BlockCopy(recoverySlot,0,result,Header+Slot,Slot);
                    Buffer.BlockCopy(data,0,result,Header+2*Slot,data.Length); return result;
                }
            } finally { Wipe(plain); }
        }
        static GeneratedPassphrase TenWords(byte[] wordList) {
            byte[] first = null, second = null;
            using (GeneratedPassphrase a = Crypto.GeneratePassphrase(wordList))
            using (GeneratedPassphrase b = Crypto.GeneratePassphrase(wordList))
            using (SecureString sa = a.CopyPassword())
            using (SecureString sb = b.CopyPassword()) {
                try {
                    first = SecretBytes(sa); second = SecretBytes(sb);
                    string[] words = (Utf8.GetString(first)+" "+Utf8.GetString(second)).Split(' ');
                    return new GeneratedPassphrase(String.Join(" ",words,0,10));
                } finally { Wipe(first); Wipe(second); }
            }
        }
        public static Created Create(byte[] payload,SecureString password,SecureString confirmation,byte[] wordList) {
            ValidatePassword(password,confirmation);
            if (payload == null || payload.Length > Maximum) throw new ArgumentException("Invalid payload size.");
            byte[] master = new byte[32], id = new byte[16]; GeneratedPassphrase recovery = null;
            try {
                Crypto.CheckSupport();
                using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) { rng.GetBytes(master); rng.GetBytes(id); }
                recovery = TenWords(wordList);
                using (SecureString phrase = recovery.CopyPassword()) {
                    byte[] bytes = Pack(id,MakeSlot(id,master,password,false),MakeSlot(id,master,phrase,true),master,payload);
                    Created result = new Created(bytes,recovery); recovery = null; return result;
                }
            } finally { Wipe(master); if (recovery != null) recovery.Dispose(); }
        }
        public static byte[] Open(byte[] envelope,SecureString credential,bool recovery) {
            byte[] master = null;
            try { master = ReadMaster(envelope,credential,recovery); return ReadPayload(envelope,master); }
            catch { throw new ArgumentException("Cannot open: credential, file integrity or format failure."); }
            finally { Wipe(master); }
        }
        public static byte[] ChangePassword(byte[] envelope,SecureString credential,bool recovery,SecureString newPassword,SecureString confirmation,SecureString recoveryCredential) {
            byte[] master = null, recoveryMaster = null, nextMaster = new byte[32], payload = null;
            try {
                ValidatePassword(newPassword,confirmation);
                master = ReadMaster(envelope,credential,recovery); payload = ReadPayload(envelope,master);
                SecureString phrase = recovery ? credential : recoveryCredential;
                recoveryMaster = ReadMaster(envelope,phrase,true);
                if (!Equal(master,recoveryMaster)) throw new ArgumentException();
                // Fresh data secret AND container ID: old backup+old password must not reveal future data.
                // Keeping the same recovery words while rotating requires their input on password changes.
                byte[] id = new byte[16];
                using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) { rng.GetBytes(nextMaster); rng.GetBytes(id); }
                return Pack(id,MakeSlot(id,nextMaster,newPassword,false),MakeSlot(id,nextMaster,phrase,true),nextMaster,payload);
            } catch { throw new ArgumentException("Password change failed; original envelope must be retained."); }
            finally { Wipe(master); Wipe(recoveryMaster); Wipe(nextMaster); Wipe(payload); }
        }
    }
}
