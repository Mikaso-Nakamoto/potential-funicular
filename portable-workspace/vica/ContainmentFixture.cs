using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
public static class ContainmentFixture {
    public static int Main(string[] args) {
        if (args.Length == 1 && args[0] == "descendant") {
            File.WriteAllText("descendant.pid",Process.GetCurrentProcess().Id.ToString());
            Thread.Sleep(120000); return 0;
        }
        File.WriteAllText("fixture.pid",Process.GetCurrentProcess().Id.ToString());
        string mode = File.ReadAllText("mode.txt");
        string command = String.Join(" ",args);
        if (mode == "curl") {
            if (command != "-q --config -") return 91;
            if (Environment.GetEnvironmentVariable("SSLKEYLOGFILE") != null) return 92;
            if (Console.In.ReadToEnd() != "TEST_ONLY") return 93;
            Console.Out.Write("TEST_RESPONSE"); Console.Error.Write("TEST_PRIVATE_STDERR"); return 0;
        }
        bool test = command == "run -test -config stdin: -format json";
        if (!test && command != "run -config stdin: -format json") return 94;
        if (mode == "blocked") { File.WriteAllText("ready.txt","ready"); Thread.Sleep(120000); return 95; }
        if (mode == "flood") {
            string chunk = new string('x',8192);
            for (int i=0;i<1024;i++) Console.Error.Write(chunk);
            Console.Error.Flush(); Thread.Sleep(120000); return 96;
        }
        if (Console.In.ReadToEnd() != "TEST_ONLY") return 97;
        if (mode == "reject") { Console.Error.Write("TEST_PRIVATE_STDERR"); return 23; }
        if (mode == "hang") { Thread.Sleep(120000); return 98; }
        if (mode == "tree") {
            var start = new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"descendant");
            start.WorkingDirectory = Environment.CurrentDirectory; start.UseShellExecute = false; start.CreateNoWindow = true;
            using (Process child = Process.Start(start)) {
                File.WriteAllText("ready.txt","ready"); Thread.Sleep(120000);
            }
        }
        return 0;
    }
}
