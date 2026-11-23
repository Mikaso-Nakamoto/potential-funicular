"""Static boundary checks only; not a PowerShell/Windows execution substitute."""
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parents[1]
CORE = (HERE / 'VaultRefresh.Common.ps1').read_text()
TEST = (HERE / 'Test-VaultRefresh.ps1').read_text()


class RefreshSourceContracts(unittest.TestCase):
    def test_auth_before_fetch(self):
        core = CORE.split('function Invoke-VaultRefresh', 1)[1]
        self.assertLess(core.index('$document = Read-Vault'), core.index('if ($Fetch)'))
        self.assertLess(core.index("'.session.lock'"), core.index('$document = Read-Vault'))

    def test_native_before_publish(self):
        core = CORE.split('function Invoke-VaultRefresh', 1)[1]
        self.assertLess(core.index('Test-XrayObjectInMemory'), core.index('$backup = Write-RefreshReplacement'))
        self.assertIn('$next = $next | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json', core)

    def test_ciphertext_disk_readback_before_replace(self):
        core = CORE.split('function Write-RefreshReplacement', 1)[1].split('function Invoke-VaultRefresh', 1)[0]
        self.assertLess(core.index('[VicAVault.Crypto]::Seal'), core.index('$stream.Write($sealed'))
        self.assertLess(core.index('Read-Vault $temp'), core.index('[IO.File]::Replace'))
        self.assertNotIn('[IO.File]::Move', core)
        self.assertNotIn('[IO.File]::Delete', core)
        self.assertIn('$stream.Flush($true)', core)
        self.assertEqual(core.count('-ne $ExpectedHash'), 2)

    def test_no_plaintext_config_path_or_log(self):
        self.assertNotIn('xray.json', CORE)
        self.assertNotIn('WriteAllText', CORE)
        self.assertNotIn('$_.Exception', CORE)
        self.assertNotIn('$_.ToString', CORE)
        self.assertNotIn('Write-Host $response', CORE)

    def test_synthetic_test_never_reads_installed_runtime(self):
        self.assertNotIn('InstalledRoot', TEST)
        self.assertNotIn('Z:\\Iran', TEST)
        self.assertIn("'native-validation'", TEST)
        self.assertIn("'encrypted-replacement'", TEST)
        self.assertIn("$fetchState.calls -ne 0", TEST)
        self.assertIn("-Filter '*.json'", TEST)


if __name__ == '__main__':
    unittest.main()
