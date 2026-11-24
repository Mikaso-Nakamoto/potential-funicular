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
        private int failed, stopping, disposed, cleanupConfirmed, outputLimitExceeded, inputStarted, inputTimeoutOccurred;
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
        private static void CheckDeadline(int timeoutMs) {
            if (timeoutMs < 100 || timeoutMs > 120000) throw new InvalidOperationException("Invalid Xray deadline.");
        }
        private static void CheckInput(byte[] config) {
            if (config == null || config.Length < 1 || config.Length > 8 * 1024 * 1024)
                throw new InvalidOperationException("Xray input size is outside the allowed range.");
        }
        private static Session Open(string exe, string workingDirectory, bool testMode) {
            if (!Path.IsPathRooted(exe) || !Path.IsPathRooted(workingDirectory))
                throw new InvalidOperationException("Absolute executable and working directory required.");
            Session session = null;
            Process child = null;
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
                session.stdoutTask = Task.Factory.StartNew(delegate { owner.Drain(child.StandardOutput.BaseStream); }, TaskCreationOptions.LongRunning);
                session.stderrTask = Task.Factory.StartNew(delegate { owner.Drain(child.StandardError.BaseStream); }, TaskCreationOptions.LongRunning);
                return session;
            } catch {
                if (session != null) session.Dispose();
                else if (child != null) { try { child.Kill(); } catch { } child.Dispose(); }
                throw new InvalidOperationException("Xray process creation failed. Diagnostics discarded.");
            }
        }
        private void SendInput(byte[] config, int inputTimeoutMs) {
            CheckDeadline(inputTimeoutMs);
            CheckInput(config);
            if (Volatile.Read(ref disposed) != 0 || Interlocked.CompareExchange(ref inputStarted, 1, 0) != 0)
                throw new InvalidOperationException("Xray session cannot accept another configuration.");
            byte[] input = null;
            bool timedOut = false;
            try {
                input = (byte[])config.Clone();
                byte[] ownedInput = input;
                writerTask = Task.Factory.StartNew(delegate {
                    try { process.StandardInput.BaseStream.Write(ownedInput, 0, ownedInput.Length); }
                    catch { Abort(); }
                    finally {
                        Array.Clear(ownedInput, 0, ownedInput.Length);
                        try { process.StandardInput.BaseStream.Close(); } catch { }
                    }
                }, TaskCreationOptions.LongRunning);
                input = null; // writer owns this buffer until its finally, including after a timeout
                timedOut = !Finish(writerTask, inputTimeoutMs);
                if (timedOut) Interlocked.Exchange(ref inputTimeoutOccurred, 1);
                if (timedOut || HasFailed) throw new InvalidOperationException();
            } catch {
                Dispose();
                if (input != null) Array.Clear(input, 0, input.Length);
                if (OutputLimitExceeded) throw new InvalidOperationException("Xray output limit exceeded. Diagnostics discarded.");
                if (timedOut) throw new InvalidOperationException("Xray stdin input timed out. Diagnostics discarded.");
                throw new InvalidOperationException("Xray stdin write failed. Diagnostics discarded.");
            }
        }
        // Split validation API permits a bounded external readiness handshake in regression tests.
        // It does not claim real Xray has a ready protocol. Caller owns Dispose from the moment this returns.
        public static Session BeginValidation(string exe, string workingDirectory) {
            return Open(exe, workingDirectory, true);
        }
        public void SendAndValidate(byte[] config, int timeoutMs) {
            try {
                SendInput(config, timeoutMs);
                // Managed waits <= 2*timeout + 5s drain + 8s cleanup, excluding OS start/kill/scheduling.
                if (!process.WaitForExit(timeoutMs) || !FinishDrains(this, 5000) || HasFailed || process.ExitCode != 0)
                    throw new InvalidOperationException("Xray stdin validation failed. Diagnostics discarded.");
                Dispose();
                if (!CleanupConfirmed) throw new InvalidOperationException("Xray cleanup was not confirmed.");
            } catch {
                Dispose();
                if (OutputLimitExceeded) throw new InvalidOperationException("Xray output limit exceeded. Diagnostics discarded.");
                if (Volatile.Read(ref inputTimeoutOccurred) != 0) throw new InvalidOperationException("Xray stdin input timed out. Diagnostics discarded.");
                throw new InvalidOperationException("Xray stdin validation failed. Diagnostics discarded.");
            }
        }
        // Ownership-first run API: caller retains the handle even if delivery/cleanup fails.
        public static Session BeginRun(string exe, string workingDirectory) {
            return Open(exe, workingDirectory, false);
        }
        public void SendForRun(byte[] config, int inputTimeoutMs) {
            try {
                SendInput(config, inputTimeoutMs);
                if (HasExited || HasFailed) throw new InvalidOperationException();
            } catch { Dispose(); throw new InvalidOperationException("Xray stdin launch failed. Diagnostics discarded."); }
        }
        public static Session Start(string exe, string workingDirectory, byte[] config, int inputTimeoutMs) {
            CheckDeadline(inputTimeoutMs);
            CheckInput(config);
            Session session = BeginRun(exe, workingDirectory);
            try { session.SendForRun(config, inputTimeoutMs); return session; }
            catch { session.Dispose(); throw; }
        }
        public static void Validate(string exe, string workingDirectory, byte[] config, int timeoutMs) {
            CheckDeadline(timeoutMs);
            CheckInput(config);
            using (Session session = BeginValidation(exe, workingDirectory)) {
                session.SendAndValidate(config, timeoutMs);
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
