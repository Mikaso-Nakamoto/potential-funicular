using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading;
// Synthetic processes only. Not Xray or LibreWolf and not a proxy implementation.
public static class LifecycleFixture {
    public static int Main(string[] args) {
        string exe = Process.GetCurrentProcess().MainModule.FileName;
        if (Path.GetFileName(exe).Equals("librewolf.exe", StringComparison.OrdinalIgnoreCase)) return Browser(args);
        bool test = String.Join(" ", args) == "run -test -config stdin: -format json";
        if (!test && String.Join(" ", args) != "run -config stdin: -format json") return 80;
        string json = Console.In.ReadToEnd();
        if (!json.Contains("example.invalid")) return 81;
        if (test) return 0;
        File.WriteAllText("live-pid.txt", Process.GetCurrentProcess().Id.ToString());
        TcpListener listener = new TcpListener(IPAddress.Loopback, 17890);
        listener.Start();
        try {
            using (TcpClient client = listener.AcceptTcpClient()) {
                client.ReceiveTimeout = 10000;
                NetworkStream stream = client.GetStream();
                if (stream.ReadByte() != 5 || stream.ReadByte() != 1 || stream.ReadByte() != 0) return 82;
                stream.Write(new byte[] {5, 0}, 0, 2);
            }
            File.WriteAllText("greeting-ok.txt", "synthetic SOCKS5 greeting only");
            if (File.Exists("exit-after-greeting.txt")) return 0;
            Thread.Sleep(60000);
            return 83;
        } finally { listener.Stop(); }
    }
    private static int Browser(string[] args) {
        int index = Array.IndexOf(args, "-profile");
        if (index < 0 || index + 1 >= args.Length) return 84;
        string profile = args[index + 1];
        string root = Directory.GetParent(Directory.GetParent(profile).FullName).FullName;
        string xrayDir = Path.Combine(root, "Xray");
        File.WriteAllText(Path.Combine(xrayDir, "browser-pid.txt"), Process.GetCurrentProcess().Id.ToString());
        using (FileStream busy = File.Open(Path.Combine(profile, "parent.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None)) {
            bool locked = false;
            try { using (FileStream session = File.Open(Path.Combine(root, ".session.lock"), FileMode.Open, FileAccess.ReadWrite, FileShare.None)) {} }
            catch (IOException) { locked = true; }
            if (!locked) return 85;
            string prefs = File.ReadAllText(Path.Combine(profile, "user.js"));
            if (!prefs.Contains("network.proxy.failover_direct\", false") || !prefs.Contains("network.proxy.socks_port\", 17890")) return 86;
            using (TcpClient client = new TcpClient()) {
                client.ReceiveTimeout = 10000;
                client.SendTimeout = 10000;
                client.Connect(IPAddress.Loopback, 17890);
                NetworkStream stream = client.GetStream();
                stream.Write(new byte[] {5, 1, 0}, 0, 3);
                if (stream.ReadByte() != 5 || stream.ReadByte() != 0) return 87;
            }
            Thread.Sleep(5000);
            // Lock must remain held even if the synthetic Xray has exited meanwhile.
            locked = false;
            try { using (FileStream session = File.Open(Path.Combine(root, ".session.lock"), FileMode.Open, FileAccess.ReadWrite, FileShare.None)) {} }
            catch (IOException) { locked = true; }
            if (!locked) return 88;
            File.WriteAllText(Path.Combine(xrayDir, "browser-ok.txt"), "lock held; proxy prefs; SOCKS greeting; normal exit");
        }
        return 0;
    }
}
