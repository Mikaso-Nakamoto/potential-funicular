using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;
namespace VicaWorkspace {
    // Xray only, never the browser. Suspended creation closes the start/assignment race.
    public sealed class OwnedXray : IDisposable {
        [StructLayout(LayoutKind.Sequential)] private struct Startup {
            public int cb; public string reserved, desktop, title;
            public uint x,y,xSize,ySize,xChars,yChars,fill,flags;
            public short show, reservedSize;
            public IntPtr reservedBytes, stdin, stdout, stderr;
        }
        [StructLayout(LayoutKind.Sequential)] private struct ProcessInfo { public IntPtr process, thread; public uint pid, tid; }
        [StructLayout(LayoutKind.Sequential)] private struct BasicLimits {
            public long processTime, jobTime; public uint flags;
            public UIntPtr minWorkingSet, maxWorkingSet; public uint activeLimit;
            public UIntPtr affinity; public uint priority, scheduling;
        }
        [StructLayout(LayoutKind.Sequential)] private struct IoCounters { public ulong a,b,c,d,e,f; }
        [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimits {
            public BasicLimits basic; public IoCounters io;
            public UIntPtr processMemory, jobMemory, peakProcessMemory, peakJobMemory;
        }
        [StructLayout(LayoutKind.Sequential)] private struct Accounting {
            public long user, kernel, periodUser, periodKernel;
            public uint faults, totalProcesses, activeProcesses, terminatedProcesses;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern SafeFileHandle CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool SetInformationJobObject(SafeFileHandle job, int kind, ref ExtendedLimits info, uint size);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool QueryInformationJobObject(SafeFileHandle job, int kind, out Accounting info, uint size, IntPtr returned);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool TerminateJobObject(SafeFileHandle job, uint code);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool CreateProcess(string app, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, string directory, ref Startup startup, out ProcessInfo info);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll")] private static extern uint WaitForSingleObject(IntPtr handle, uint ms);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        private SafeFileHandle job;
        private Process child;
        public int Id { get { return child.Id; } }
        public bool HasExited { get { return child.HasExited; } }
        public int ExitCode { get { return child.ExitCode; } }
        public bool CleanupConfirmed { get; private set; }
        private OwnedXray() {}
        public static OwnedXray Start(string exe, string config, string directory, bool testMode) {
            if (!System.IO.Path.IsPathRooted(exe) || !System.IO.Path.IsPathRooted(config) || !System.IO.Path.IsPathRooted(directory) || exe.Contains("\"") || config.Contains("\""))
                throw new InvalidOperationException("Absolute unquoted paths required.");
            if (IntPtr.Size != 8 || Marshal.SizeOf(typeof(Startup)) != 104 || Marshal.SizeOf(typeof(ExtendedLimits)) != 144 || Marshal.SizeOf(typeof(Accounting)) != 48)
                throw new InvalidOperationException("Unsupported Windows job ABI layout.");
            OwnedXray owner = new OwnedXray(); ProcessInfo pi = new ProcessInfo();
            try {
                owner.job = CreateJobObject(IntPtr.Zero, null);
                if (owner.job.IsInvalid) throw new Win32Exception();
                ExtendedLimits limits = new ExtendedLimits(); limits.basic.flags = 0x2000; // KILL_ON_JOB_CLOSE; no breakaway.
                if (!SetInformationJobObject(owner.job, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits)))) throw new Win32Exception();
                Startup startup = new Startup(); startup.cb = Marshal.SizeOf(typeof(Startup));
                string mode = testMode ? " run -test -config " : " run -config ";
                StringBuilder command = new StringBuilder("\"" + exe + "\"" + mode + "\"" + config + "\"");
                if (!CreateProcess(exe, command, IntPtr.Zero, IntPtr.Zero, false, 0x08000004, IntPtr.Zero, directory, ref startup, out pi)) throw new Win32Exception();
                if (!AssignProcessToJobObject(owner.job, pi.process)) throw new Win32Exception();
                owner.child = Process.GetProcessById((int)pi.pid);
                if (owner.child.Handle == IntPtr.Zero) throw new Win32Exception(); // retain managed handle before execution.
                if (ResumeThread(pi.thread) == 0xffffffff) throw new Win32Exception();
                return owner;
            } catch {
                if (pi.process != IntPtr.Zero) { TerminateProcess(pi.process, 1); WaitForSingleObject(pi.process, 5000); }
                if (owner.job != null) owner.job.Dispose();
                if (owner.child != null) owner.child.Dispose();
                throw new InvalidOperationException("Owned Xray startup failed. Job containment is mandatory; no uncontained fallback.");
            } finally {
                if (pi.thread != IntPtr.Zero) CloseHandle(pi.thread);
                if (pi.process != IntPtr.Zero) CloseHandle(pi.process);
            }
        }
        public void Dispose() {
            if (CleanupConfirmed) return;
            // Retain handle on uncertainty so caller can keep its session lock and retry cleanup.
            if (job == null || job.IsInvalid || job.IsClosed) return;
            TerminateJobObject(job, 1);
            Stopwatch timer = Stopwatch.StartNew();
            while (timer.ElapsedMilliseconds < 5000) {
                Accounting state;
                if (QueryInformationJobObject(job, 1, out state, (uint)Marshal.SizeOf(typeof(Accounting)), IntPtr.Zero) && state.activeProcesses == 0) {
                    job.Dispose(); child.Dispose(); CleanupConfirmed = true; return;
                }
                Thread.Sleep(50);
            }
        }
    }
}
