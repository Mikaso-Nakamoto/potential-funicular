using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
namespace VicAXrayPipe {
    // Bounded-memory transport. Does not parse or persist configuration; callers must validate policy.
    public sealed class Session : IDisposable {
        private readonly Process process;
        private Task stdoutTask, stderrTask, writerTask;
        private int failed, stopping, disposed, cleanupConfirmed, outputLimitExceeded;
        private const long OutputLimit = 1024 * 1024; // per stream, discarded; excessive output aborts child
        private Session(Process child) { process = child; }
        public int Id { get { return process.Id; } }
        public bool HasExited { get { return process.HasExited; } }
        public bool HasFailed { get { return Volatile.Read(ref failed) != 0; } }
        public bool OutputLimitExceeded { get { return Volatile.Read(ref outputLimitExceeded) != 0; } }
        public bool CleanupConfirmed { get { return Volatile.Read(ref cleanupConfirmed) != 0; } }
        private void Abort() {
            Interlocked.Exchange(ref failed, 1);
            KillChild();
        }
        private void KillChild() {
            try { if (!process.HasExited) process.Kill(); } catch { }
        }
        private void Drain(Stream stream) {
            byte[] buffer = new byte[4096];
            long count = 0;
            try {
                int read;
                while ((read = stream.Read(buffer, 0, buffer.Length)) > 0) {
                    count += read;
                    if (count > OutputLimit) { Interlocked.Exchange(ref outputLimitExceeded, 1); Abort(); return; }
                }
            } catch { if (Volatile.Read(ref stopping) == 0) Abort(); }
            finally { Array.Clear(buffer, 0, buffer.Length); }
        }
        private static bool Finish(Task task, int milliseconds) {
            if (task == null) return true;
            try { return task.Wait(milliseconds); } catch { return false; }
        }
        private static bool FinishDrains(Session session, int milliseconds) {
            try { return Task.WaitAll(new Task[] { session.stdoutTask, session.stderrTask }, milliseconds); }
            catch { return false; }
        }
        private static Session Launch(string exe, string workingDirectory, byte[] config, bool testMode, int inputTimeoutMs) {
            if (config == null || config.Length < 1 || config.Length > 8 * 1024 * 1024)
                throw new InvalidOperationException("Xray input size is outside the allowed range.");
            if (inputTimeoutMs < 100 || inputTimeoutMs > 120000)
                throw new InvalidOperationException("Invalid Xray input deadline.");
            if (!Path.IsPathRooted(exe) || !Path.IsPathRooted(workingDirectory))
                throw new InvalidOperationException("Absolute executable and working directory required.");
            Session session = null;
            Process child = null;
            byte[] input = null;
            bool inputTimedOut = false;
            try {
                var info = new ProcessStartInfo();
                info.FileName = exe;
                info.WorkingDirectory = workingDirectory;
                info.Arguments = testMode ? "run -test -config stdin: -format json" : "run -config stdin: -format json";
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.RedirectStandardInput = true;
                info.RedirectStandardOutput = true;
                info.RedirectStandardError = true;
                child = Process.Start(info);
                session = new Session(child);
                Session owner = session;
                // Dedicated drain threads; no output string, log file or unbounded ReadToEnd buffer.
                session.stdoutTask = Task.Factory.StartNew(delegate { owner.Drain(child.StandardOutput.BaseStream); }, TaskCreationOptions.LongRunning);
                session.stderrTask = Task.Factory.StartNew(delegate { owner.Drain(child.StandardError.BaseStream); }, TaskCreationOptions.LongRunning);
                input = (byte[])config.Clone();
                byte[] ownedInput = input;
                session.writerTask = Task.Factory.StartNew(delegate {
                    try { child.StandardInput.BaseStream.Write(ownedInput, 0, ownedInput.Length); }
                    catch { owner.Abort(); }
                    finally {
                        Array.Clear(ownedInput, 0, ownedInput.Length);
                        try { child.StandardInput.BaseStream.Close(); } catch { }
                    }
                }, TaskCreationOptions.LongRunning);
                // Writer owns its cloned buffer even on timeout. Caller can clear its own input immediately on return.
                input = null;
                inputTimedOut = !Finish(session.writerTask, inputTimeoutMs);
                if (inputTimedOut || session.HasFailed)
                    throw new InvalidOperationException();
                if (!testMode && child.HasExited) throw new InvalidOperationException();
                return session;
            } catch {
                if (session != null) session.Dispose();
                else if (child != null) { try { child.Kill(); } catch { } child.Dispose(); }
                if (input != null) Array.Clear(input, 0, input.Length);
                // No native stderr, exception chain, arguments containing JSON or config content is exposed.
                if (session != null && session.OutputLimitExceeded) throw new InvalidOperationException("Xray output limit exceeded. Diagnostics discarded.");
                if (inputTimedOut) throw new InvalidOperationException("Xray stdin input timed out. Diagnostics discarded.");
                throw new InvalidOperationException("Xray stdin launch failed, exceeded output limits or timed out. Diagnostics discarded.");
            }
        }
        public static Session Start(string exe, string workingDirectory, byte[] config, int inputTimeoutMs) {
            return Launch(exe, workingDirectory, config, false, inputTimeoutMs);
        }
        public static void Validate(string exe, string workingDirectory, byte[] config, int timeoutMs) {
            if (timeoutMs < 100 || timeoutMs > 120000) throw new InvalidOperationException("Invalid Xray test deadline.");
            using (Session session = Launch(exe, workingDirectory, config, true, timeoutMs)) {
                try {
                    // Managed waits <= 2*timeout + 5s drain + 8s cleanup, excluding OS scheduling/start/kill calls.
                    if (!session.process.WaitForExit(timeoutMs) || !FinishDrains(session, 5000) || session.HasFailed || session.process.ExitCode != 0)
                        throw new InvalidOperationException();
                    session.Dispose();
                    if (!session.CleanupConfirmed) throw new InvalidOperationException();
                } catch {
                    if (session.OutputLimitExceeded) throw new InvalidOperationException("Xray output limit exceeded. Diagnostics discarded.");
                    throw new InvalidOperationException("Xray stdin validation failed, exceeded output limits or timed out. Diagnostics discarded.");
                }
            }
        }
        public void Dispose() {
            if (Interlocked.Exchange(ref disposed, 1) != 0) return;
            Interlocked.Exchange(ref stopping, 1);
            KillChild();
            // A broken/inherited pipe must not make Dispose synchronously block forever.
            // Cleanup can remain in a background worker on an uncooperative OS/descendant;
            // the caller MUST inspect CleanupConfirmed before releasing session ownership.
            Task cleanup = Task.Factory.StartNew(delegate {
                try {
                    bool exited = process.WaitForExit(5000);
                    try { process.StandardInput.Close(); } catch { }
                    try { process.StandardOutput.Close(); } catch { }
                    try { process.StandardError.Close(); } catch { }
                    bool writerDone = Finish(writerTask, 500);
                    bool stdoutDone = Finish(stdoutTask, 500);
                    bool stderrDone = Finish(stderrTask, 500);
                    process.Dispose();
                    if (exited && writerDone && stdoutDone && stderrDone) Interlocked.Exchange(ref cleanupConfirmed, 1);
                } catch { Interlocked.Exchange(ref failed, 1); }
            }, TaskCreationOptions.LongRunning);
            if (!Finish(cleanup, 8000) || !CleanupConfirmed) Interlocked.Exchange(ref failed, 1);
        }
    }
}
