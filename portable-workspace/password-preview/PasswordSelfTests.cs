namespace VicaPasswordPreview {
    using System;
    using System.Security;
    using System.Text;
    public static class SelfTests {
        static SecureString Secret(string text) { var s = new SecureString(); foreach (char c in text) s.AppendChar(c); s.MakeReadOnly(); return s; }
        static void Same(byte[] a,byte[] b) { if (a.Length != b.Length) throw new InvalidOperationException("Self-check mismatch."); for (int i=0;i<a.Length;i++) if (a[i]!=b[i]) throw new InvalidOperationException("Self-check mismatch."); }
        static void Fail(Action action) { bool failed=false; try { action(); } catch { failed=true; } if (!failed) throw new InvalidOperationException("Self-check expected rejection."); }
        public static int Run(byte[] wordList) {
            byte[] payload = Encoding.UTF8.GetBytes("SYNTHETIC SELF-CHECK ONLY");
            using (SecureString password = Secret("Orbit-lantern-juniper-572!"))
            using (SecureString nextPassword = Secret("Harbor-telescope-cloud-934!"))
            using (SecureString wrong = Secret("Wrong-synthetic-credential-692!"))
            using (SecureString nfc = Secret("Caf\u00e9-orbit-lantern-572!"))
            using (SecureString nfd = Secret("Cafe\u0301-orbit-lantern-572!"))
            using (Created created = Envelope.Create(payload,password,password,wordList))
            using (SecureString phrase = created.Recovery.CopyPassword()) {
                Same(payload,Envelope.Open(created.Envelope,password,false));
                Same(payload,Envelope.Open(created.Envelope,phrase,true));
                Fail(delegate { Envelope.Open(created.Envelope,wrong,false); });
                Fail(delegate { Envelope.Open(created.Envelope,wrong,true); });
                Fail(delegate { Envelope.Open(created.Envelope,phrase,false); });
                byte[] broken = (byte[])created.Envelope.Clone(); broken[132] ^= 1;
                Fail(delegate { Envelope.Open(broken,password,false); });
                byte[] truncated = new byte[379];
                Fail(delegate { Envelope.Open(truncated,password,false); });
                Envelope.ValidatePassword(nfc,nfd);
                Fail(delegate { Envelope.ValidatePassword(password,wrong); });
                using (SecureString weak = Secret("passwordpassword")) { Fail(delegate { Envelope.ValidatePassword(weak,weak); }); }
                byte[] changed = Envelope.ChangePassword(created.Envelope,password,false,nextPassword,nextPassword,phrase);
                Same(payload,Envelope.Open(changed,nextPassword,false));
                Same(payload,Envelope.Open(changed,phrase,true));
                Fail(delegate { Envelope.Open(changed,password,false); });
                byte[] reset = Envelope.ChangePassword(changed,phrase,true,password,password,phrase);
                Same(payload,Envelope.Open(reset,password,false));
                Same(payload,Envelope.Open(reset,phrase,true));
                Fail(delegate { Envelope.Open(reset,nextPassword,false); });
                using (SecureString shortPassword = Secret("M7!vQ2#z"))
                using (Created shortCreated = Envelope.Create(payload,shortPassword,shortPassword,wordList)) {
                    Same(payload,Envelope.Open(shortCreated.Envelope,shortPassword,false));
                }
                return 17;
            }
        }
    }
}
