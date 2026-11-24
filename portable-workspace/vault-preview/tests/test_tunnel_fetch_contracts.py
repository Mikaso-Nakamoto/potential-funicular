"""Static source boundaries, NOT C# compilation or Windows execution."""
from pathlib import Path
import hashlib
import unittest

ROOT = Path(__file__).resolve().parents[1]
PS = (ROOT / 'Test-TunnelSubscription.ps1').read_text()
CS = (ROOT / 'CurlPipe.cs').read_text()


class TunnelFetchContracts(unittest.TestCase):
    def test_no_secret_native_arguments_or_config_file(self):
        self.assertIn('new ProcessStartInfo(exe, "-q --config -")', CS)
        self.assertIn('process.StandardInput.BaseStream.Write', CS)
        self.assertNotIn('WriteAllText', PS + CS)
        self.assertNotIn('WriteAllBytes', PS + CS)
        self.assertNotIn('curl -K', PS)
        self.assertNotIn('Invoke-VaultRefresh', PS)
        self.assertNotIn('Write-RefreshReplacement', PS)

    def test_only_explicit_socks_remote_dns_and_https(self):
        for text in ['socks5h://127.0.0.1:17890', 'noproxy = ""', 'proto = "=https"',
                     'proto-redir = "=https"', 'INCY/3.0.28']:
            self.assertIn(text, PS)
        self.assertNotIn('insecure', PS)
        self.assertNotIn('location =', PS)
        self.assertIn("$status -cne '200'", PS)

    def test_owner_before_credentials_and_cleanup_before_unlock(self):
        self.assertLess(PS.index('$xray = Open-XrayRunSession'), PS.index('Send-XrayRunConfig $xray'))
        self.assertLess(PS.index('OwningProcess -eq $xray.Id'), PS.index('$curl = [VicaCurl.Session]::Begin'))
        self.assertLess(PS.index("Wait-OwnedCleanup $curl 'curl'"), PS.index('$lock.Dispose()'))
        self.assertLess(PS.index("Wait-OwnedCleanup $xray 'Xray'"), PS.index('$lock.Dispose()'))
        self.assertIn('while (-not $Handle.CleanupConfirmed)', PS)

    def test_limits_integrity_and_temp_before_crypto(self):
        self.assertIn(hashlib.sha256((ROOT / 'CurlPipe.cs').read_bytes()).hexdigest(), PS)
        self.assertIn('4194560 : 65536', CS)
        self.assertIn('config.Length > 65536', CS)
        self.assertIn('process.WaitForExit(35000)', CS)
        self.assertLess(PS.index('$env:TEMP = $tmp'), PS.index('$document = Read-Vault'))
        self.assertIn('Array.Clear(backing', CS)
        self.assertIn('EnvironmentVariables.Remove("SSLKEYLOGFILE")', CS)


if __name__ == '__main__':
    unittest.main()
