using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
public static class XrayPipeFixture {
    public static int Main(string[] args) {
        File.WriteAllText("pid.txt", Process.GetCurrentProcess().Id.ToString());
        string mode = File.ReadAllText("mode.txt");
        string expected = mode == "serve" ? "run -config stdin: -format json" : "run -test -config stdin: -format json";
        if (String.Join(" ", args) != expected) return 91;
        if (mode == "blocked-input") {
            // Reached the actual no-read branch, not just process creation / CLR initialization.
            File.WriteAllText("blocked-ready.txt", Process.GetCurrentProcess().Id.ToString());
            Thread.Sleep(60000);
            return 92;
        }
        if (mode == "stderr-flood" || mode == "stdout-flood") {
            TextWriter output = mode == "stderr-flood" ? Console.Error : Console.Out;
            string chunk = new string('x', 4096);
            for (int i = 0; i < 1024; i++) output.Write(chunk);
            output.Flush();
            Thread.Sleep(60000);
            return 93;
        }
        string json = Console.In.ReadToEnd(); // test data only; EOF must be delivered
        if (!json.StartsWith("{") || !json.Contains("example.invalid")) return 94;
        Console.Out.WriteLine("VIC-A-PIPE-SYNTHETIC-SECRET-DO-NOT-PRINT");
        Console.Error.WriteLine("VIC-A-PIPE-SYNTHETIC-SECRET-DO-NOT-PRINT");
        if (mode == "reject") return 23;
        // Publishing this marker proves the live branch reached Main, checked args and consumed stdin through EOF.
        if (mode == "serve") File.WriteAllText("serve-ready.txt", Process.GetCurrentProcess().Id.ToString());
        if (mode == "hang-after-input" || mode == "serve") { Thread.Sleep(60000); return 95; }
        return 0;
    }
}
