using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
namespace VicaCurl {
    // One owned curl process; secrets only on stdin. Bounded capture of stdout, discard stderr.
    public sealed class Session : IDisposable {
        private readonly Process process;
        private Task outputTask, errorTask, writerTask;
        private byte[] response;
        private int failed, disposed, cleanupConfirmed;
        public bool CleanupConfirmed { get { return Volatile.Read(ref cleanupConfirmed) != 0; } }
        private Session(Process child) { process = child; }
        private void Abort() { Interlocked.Exchange(ref failed, 1); try { if (!process.HasExited) process.Kill(); } catch {} }
        private void Drain(Stream stream, bool capture) {
            byte[] buffer = new byte[8192];
            MemoryStream memory = capture ? new MemoryStream() : null;
            long total = 0;
            try {
                int n;
                while ((n = stream.Read(buffer, 0, buffer.Length)) > 0) {
                    total += n;
                    if (total > (capture ? 4194560 : 65536)) { Abort(); return; }
                    if (capture) memory.Write(buffer, 0, n);
                }
                if (capture) response = memory.ToArray();
            } catch { Abort(); }
            finally {
                Array.Clear(buffer, 0, buffer.Length);
                if (memory != null) {
                    byte[] backing = memory.GetBuffer(); Array.Clear(backing, 0, backing.Length); memory.Dispose();
                }
            }
        }
        private static bool Finish(Task task, int ms) {
            if (task == null) return true;
            try { return task.Wait(ms); } catch { return false; }
        }
        public static Session Begin(string exe, string directory) {
            if (!Path.IsPathRooted(exe) || !Path.IsPathRooted(directory)) throw new InvalidOperationException("Absolute paths required.");
            var info = new ProcessStartInfo(exe, "-q --config -"); // -q FIRST: ignore user curlrc.
            info.WorkingDirectory = directory; info.UseShellExecute = false; info.CreateNoWindow = true;
            info.EnvironmentVariables.Remove("SSLKEYLOGFILE"); // do not inherit optional TLS key logging
            info.RedirectStandardInput = true; info.RedirectStandardOutput = true; info.RedirectStandardError = true;
            Process child = Process.Start(info);
            Session session = new Session(child);
            try {
                session.outputTask = Task.Factory.StartNew(delegate { session.Drain(child.StandardOutput.BaseStream, true); }, TaskCreationOptions.LongRunning);
                session.errorTask = Task.Factory.StartNew(delegate { session.Drain(child.StandardError.BaseStream, false); }, TaskCreationOptions.LongRunning);
                return session;
            } catch { session.Dispose(); throw new InvalidOperationException("curl startup failed; diagnostics suppressed."); }
        }
        public byte[] Fetch(byte[] config) {
            if (config == null || config.Length == 0 || config.Length > 65536 || writerTask != null || Volatile.Read(ref disposed) != 0)
                throw new InvalidOperationException("Invalid curl input/session.");
            byte[] owned = (byte[])config.Clone();
            try {
                writerTask = Task.Factory.StartNew(delegate {
                    try { process.StandardInput.BaseStream.Write(owned, 0, owned.Length); }
                    catch { Abort(); }
                    finally { Array.Clear(owned, 0, owned.Length); try { process.StandardInput.Close(); } catch {} }
                }, TaskCreationOptions.LongRunning);
            } catch { Array.Clear(owned, 0, owned.Length); Abort(); throw new InvalidOperationException("curl input setup failed."); }
            if (!Finish(writerTask, 5000) || !process.WaitForExit(35000) || !Finish(outputTask, 1000) || !Finish(errorTask, 1000)) {
                Abort(); throw new InvalidOperationException("curl deadline exceeded; diagnostics suppressed.");
            }
            if (Volatile.Read(ref failed) != 0 || process.ExitCode != 0 || response == null) throw new InvalidOperationException("curl request failed; diagnostics suppressed.");
            return response;
        }
        public void Dispose() {
            if (Interlocked.Exchange(ref disposed, 1) != 0) return;
            try { if (!process.HasExited) process.Kill(); } catch {}
            Task cleanup = Task.Factory.StartNew(delegate {
                try {
                    bool exited = process.WaitForExit(5000);
                    try { process.StandardInput.Close(); } catch {}
                    try { process.StandardOutput.Close(); } catch {}
                    try { process.StandardError.Close(); } catch {}
                    bool writer = Finish(writerTask, 500), output = Finish(outputTask, 500), error = Finish(errorTask, 500);
                    if (response != null) Array.Clear(response, 0, response.Length);
                    process.Dispose();
                    if (exited && writer && output && error) Interlocked.Exchange(ref cleanupConfirmed, 1);
                } catch {}
            }, TaskCreationOptions.LongRunning);
            Finish(cleanup, 8000);
        }
    }
}
