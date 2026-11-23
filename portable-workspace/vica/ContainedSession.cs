using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;
namespace VicaContained {
    // Windows x64 only. No child executes before mandatory Job assignment.
    public sealed class Session : IDisposable {
        [StructLayout(LayoutKind.Sequential)] struct Security { public int size; public IntPtr descriptor; public int inherit; }
        [StructLayout(LayoutKind.Sequential)] struct Startup {
            public int cb; public IntPtr reserved, desktop, title;
            public uint x,y,xSize,ySize,xChars,yChars,fill,flags;
            public short show, reservedSize;
            public IntPtr reservedBytes, stdin, stdout, stderr;
        }
        [StructLayout(LayoutKind.Sequential)] struct StartupEx { public Startup startup; public IntPtr attributes; }
        [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process, thread; public uint pid, tid; }
        [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
            public long processTime, jobTime; public uint flags;
            public UIntPtr minWorkingSet, maxWorkingSet; public uint activeLimit;
            public UIntPtr affinity; public uint priority, scheduling;
        }
        [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong a,b,c,d,e,f; }
        [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits {
            public BasicLimits basic; public IoCounters io;
            public UIntPtr processMemory, jobMemory, peakProcessMemory, peakJobMemory;
        }
        [StructLayout(LayoutKind.Sequential)] struct Accounting {
            public long user, kernel, periodUser, periodKernel;
            public uint faults, totalProcesses, activeProcesses, terminatedProcesses;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern SafeFileHandle CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(SafeFileHandle job, int kind, ref ExtendedLimits info, uint size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(SafeFileHandle job, int kind, out Accounting info, uint size, IntPtr returned);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(SafeFileHandle job, uint code);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string app, StringBuilder command, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr environment, string directory, ref StartupEx startup, out ProcessInfo info);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool CreatePipe(out SafeFileHandle read, out SafeFileHandle write, ref Security attributes, uint size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetHandleInformation(SafeFileHandle handle, uint mask, uint flags);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, uint flags, ref IntPtr size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returned);
        [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle, uint ms);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(SafeFileHandle process, out uint code);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        SafeFileHandle job, process;
        FileStream input, output, error;
        Task writer, outputTask, errorTask;
        byte[] response;
        int failed, inputStarted;
        readonly bool capture;
        public int Id { get; private set; }
        public bool CleanupConfirmed { get; private set; }
        public bool HasFailed { get { return Volatile.Read(ref failed) != 0; } }
        public bool HasExited { get { return CleanupConfirmed || (process != null && !process.IsClosed && WaitForSingleObject(process.DangerousGetHandle(),0) == 0); } }
        public int ExitCode {
            get { uint code; if (CleanupConfirmed || !HasExited || !GetExitCodeProcess(process,out code)) throw new InvalidOperationException("Exit unavailable."); return (int)code; }
        }
        Session(bool saveOutput) { capture = saveOutput; }
        void Abort() { Interlocked.Exchange(ref failed,1); Kill(); }
        void Kill() { if (job != null && !job.IsInvalid && !job.IsClosed) TerminateJobObject(job,1); }
        static void Close(SafeFileHandle handle) { if (handle != null) handle.Dispose(); }
        static bool Finish(Task task, int ms) { if (task == null) return true; try { return task.Wait(ms); } catch { return false; } }
        void Drain(Stream stream, bool save) {
            byte[] buffer = new byte[8192];
            MemoryStream memory = save ? new MemoryStream() : null;
            long total = 0;
            try {
                int count;
                while ((count = stream.Read(buffer,0,buffer.Length)) > 0) {
                    total += count;
                    if (total > (save ? 4194560 : 1048576)) { Abort(); return; }
                    if (save) memory.Write(buffer,0,count);
                }
                if (save) response = memory.ToArray();
            } catch { Abort(); }
            finally {
                Array.Clear(buffer,0,buffer.Length);
                if (memory != null) { byte[] bytes = memory.GetBuffer(); Array.Clear(bytes,0,bytes.Length); memory.Dispose(); }
            }
        }
        public static Session Open(string exe, string directory, string mode) {
            if (IntPtr.Size != 8 || Marshal.SizeOf(typeof(Startup)) != 104 || Marshal.SizeOf(typeof(StartupEx)) != 112 || Marshal.SizeOf(typeof(ExtendedLimits)) != 144 || Marshal.SizeOf(typeof(Accounting)) != 48)
                throw new InvalidOperationException("Unsupported Windows x64 ABI.");
            if (!Path.IsPathRooted(exe) || !Path.IsPathRooted(directory) || exe.IndexOf('"') >= 0) throw new InvalidOperationException("Absolute paths required.");
            string arguments;
            if (mode == "run") arguments = "run -config stdin: -format json";
            else if (mode == "test") arguments = "run -test -config stdin: -format json";
            else if (mode == "curl") arguments = "-q --config -";
            else throw new InvalidOperationException("Invalid native mode.");
            Session owner = new Session(mode == "curl");
            SafeFileHandle childIn = null, parentIn = null, parentOut = null, childOut = null, parentErr = null, childErr = null;
            ProcessInfo pi = new ProcessInfo();
            IntPtr attributes = IntPtr.Zero, handles = IntPtr.Zero, environment = IntPtr.Zero;
            bool initialized = false, assigned = false;
            try {
                owner.job = CreateJobObject(IntPtr.Zero,null);
                if (owner.job.IsInvalid) throw new InvalidOperationException();
                ExtendedLimits limits = new ExtendedLimits(); limits.basic.flags = 0x2000;
                if (!SetInformationJobObject(owner.job,9,ref limits,(uint)Marshal.SizeOf(typeof(ExtendedLimits)))) throw new InvalidOperationException();
                Security sa = new Security(); sa.size = Marshal.SizeOf(typeof(Security)); sa.inherit = 1;
                if (!CreatePipe(out childIn,out parentIn,ref sa,0) || !CreatePipe(out parentOut,out childOut,ref sa,0) || !CreatePipe(out parentErr,out childErr,ref sa,0)) throw new InvalidOperationException();
                if (!SetHandleInformation(parentIn,1,0) || !SetHandleInformation(parentOut,1,0) || !SetHandleInformation(parentErr,1,0)) throw new InvalidOperationException();
                IntPtr size = IntPtr.Zero;
                InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref size);
                if (size == IntPtr.Zero || size.ToInt64() > 1048576) throw new InvalidOperationException();
                attributes = Marshal.AllocHGlobal(size);
                if (!InitializeProcThreadAttributeList(attributes,1,0,ref size)) throw new InvalidOperationException();
                initialized = true;
                handles = Marshal.AllocHGlobal(3 * IntPtr.Size);
                Marshal.WriteIntPtr(handles,0,childIn.DangerousGetHandle());
                Marshal.WriteIntPtr(handles,IntPtr.Size,childOut.DangerousGetHandle());
                Marshal.WriteIntPtr(handles,2 * IntPtr.Size,childErr.DangerousGetHandle());
                // Only these three pipe ends may be inherited. The Job and all parent ends are excluded.
                if (!UpdateProcThreadAttribute(attributes,0,new IntPtr(0x20002),handles,new IntPtr(3 * IntPtr.Size),IntPtr.Zero,IntPtr.Zero)) throw new InvalidOperationException();
                StartupEx startup = new StartupEx(); startup.startup.cb = Marshal.SizeOf(typeof(StartupEx));
                startup.startup.flags = 0x100; startup.startup.stdin = childIn.DangerousGetHandle();
                startup.startup.stdout = childOut.DangerousGetHandle(); startup.startup.stderr = childErr.DangerousGetHandle(); startup.attributes = attributes;
                var env = new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables()) {
                    string key = (string)entry.Key;
                    if (!key.Equals("SSLKEYLOGFILE",StringComparison.OrdinalIgnoreCase)) env[key] = (string)entry.Value;
                }
                StringBuilder block = new StringBuilder();
                foreach (var entry in env) block.Append(entry.Key).Append('=').Append(entry.Value).Append('\0');
                block.Append('\0'); environment = Marshal.StringToHGlobalUni(block.ToString());
                // EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW | CREATE_SUSPENDED
                if (!CreateProcess(exe,new StringBuilder("\"" + exe + "\" " + arguments),IntPtr.Zero,IntPtr.Zero,true,0x08080404,environment,directory,ref startup,out pi)) throw new InvalidOperationException();
                if (!AssignProcessToJobObject(owner.job,pi.process)) throw new InvalidOperationException();
                assigned = true;
                owner.Id = (int)pi.pid; owner.process = new SafeFileHandle(pi.process,true); pi.process = IntPtr.Zero;
                Close(childIn); childIn = null; Close(childOut); childOut = null; Close(childErr); childErr = null;
                owner.input = new FileStream(parentIn,FileAccess.Write,4096,false); parentIn = null;
                owner.output = new FileStream(parentOut,FileAccess.Read,4096,false); parentOut = null;
                owner.error = new FileStream(parentErr,FileAccess.Read,4096,false); parentErr = null;
                owner.outputTask = Task.Factory.StartNew(delegate { owner.Drain(owner.output,owner.capture); },TaskCreationOptions.LongRunning);
                owner.errorTask = Task.Factory.StartNew(delegate { owner.Drain(owner.error,false); },TaskCreationOptions.LongRunning);
                if (ResumeThread(pi.thread) == 0xffffffff) throw new InvalidOperationException();
                return owner;
            } catch {
                // A not-assigned child is still suspended; never resume it or fall back to Process.Start.
                if (!assigned && pi.process != IntPtr.Zero) {
                    while (WaitForSingleObject(pi.process,0) != 0) { TerminateProcess(pi.process,1); WaitForSingleObject(pi.process,5000); }
                }
                Close(childIn); childIn = null; Close(childOut); childOut = null; Close(childErr); childErr = null;
                if (assigned) { while (!owner.CleanupConfirmed) owner.Dispose(); }
                else Close(owner.job);
                throw new InvalidOperationException("Contained startup failed; no uncontained fallback. Diagnostics suppressed.");
            } finally {
                if (pi.thread != IntPtr.Zero) CloseHandle(pi.thread);
                if (pi.process != IntPtr.Zero) CloseHandle(pi.process);
                Close(childIn); Close(parentIn); Close(parentOut); Close(childOut); Close(parentErr); Close(childErr);
                if (initialized) DeleteProcThreadAttributeList(attributes);
                if (attributes != IntPtr.Zero) Marshal.FreeHGlobal(attributes);
                if (handles != IntPtr.Zero) Marshal.FreeHGlobal(handles);
                if (environment != IntPtr.Zero) Marshal.FreeHGlobal(environment);
            }
        }
        public void Send(byte[] bytes, int timeoutMs) {
            if (bytes == null || bytes.Length == 0 || bytes.Length > (capture ? 65536 : 8388608) || timeoutMs < 100 || timeoutMs > 30000 || CleanupConfirmed || Interlocked.CompareExchange(ref inputStarted,1,0) != 0)
                throw new InvalidOperationException("Invalid input/session.");
            byte[] owned = (byte[])bytes.Clone();
            try {
                writer = Task.Factory.StartNew(delegate {
                    try { input.Write(owned,0,owned.Length); input.Flush(); }
                    catch { Abort(); }
                    finally { Array.Clear(owned,0,owned.Length); try { input.Dispose(); } catch { } }
                },TaskCreationOptions.LongRunning);
            } catch { Array.Clear(owned,0,owned.Length); Abort(); throw new InvalidOperationException("Input setup failed."); }
            if (!Finish(writer,timeoutMs) || HasFailed) { Abort(); throw new InvalidOperationException("Input deadline/failure. Diagnostics suppressed."); }
        }
        public void Validate(byte[] bytes, int timeoutMs) {
            Send(bytes,10000);
            if (timeoutMs < 100 || timeoutMs > 120000 || WaitForSingleObject(process.DangerousGetHandle(),(uint)timeoutMs) != 0 || !Finish(outputTask,2000) || !Finish(errorTask,2000) || HasFailed || ExitCode != 0) {
                Abort(); throw new InvalidOperationException("Native validation failed. Diagnostics suppressed.");
            }
        }
        public byte[] Fetch(byte[] bytes) {
            if (!capture) throw new InvalidOperationException("Not a fetch session.");
            Send(bytes,5000);
            if (WaitForSingleObject(process.DangerousGetHandle(),35000) != 0 || !Finish(outputTask,1000) || !Finish(errorTask,1000) || HasFailed || ExitCode != 0 || response == null) {
                Abort(); throw new InvalidOperationException("Fetch failed or deadline exceeded. Diagnostics suppressed.");
            }
            return response;
        }
        public void Dispose() {
            if (CleanupConfirmed) return;
            if (job == null || job.IsInvalid || job.IsClosed) return;
            Kill();
            Stopwatch timer = Stopwatch.StartNew();
            while (timer.ElapsedMilliseconds < 5000) {
                Accounting state;
                if (QueryInformationJobObject(job,1,out state,(uint)Marshal.SizeOf(typeof(Accounting)),IntPtr.Zero) && state.activeProcesses == 0) {
                    if (!Finish(writer,500) || !Finish(outputTask,500) || !Finish(errorTask,500)) return;
                    if (input != null) input.Dispose();
                    if (output != null) output.Dispose();
                    if (error != null) error.Dispose();
                    if (response != null) Array.Clear(response,0,response.Length);
                    job.Dispose(); if (process != null) process.Dispose(); CleanupConfirmed = true; return;
                }
                Thread.Sleep(50);
            }
            // Caller retains this owner and its session lock; Dispose may be retried.
        }
    }
}
