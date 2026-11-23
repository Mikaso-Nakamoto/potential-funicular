"""Static/packaging contracts; not Windows/PowerShell execution."""
from pathlib import Path
import hashlib
import subprocess
import sys
import unittest
import zipfile

HERE = Path(__file__).resolve().parents[1]
CS = (HERE / 'PasswordEnvelope.cs').read_text()
COMMON = (HERE / 'Password.Common.ps1').read_text()
UI = (HERE / 'Start-PasswordTest.ps1').read_text()


class PasswordContracts(unittest.TestCase):
    def test_pins_and_base_primitives(self):
        for name in ('PasswordEnvelope.cs','PasswordSelfTests.cs'):
            self.assertIn(hashlib.sha256((HERE/name).read_bytes()).hexdigest(),COMMON)
        self.assertIn(hashlib.sha256((HERE.parent/'vault-preview/VaultCrypto.cs').read_bytes().replace(b'password.Length < 16',b'password.Length < 8').replace(b'at least 16 characters',b'at least 8 characters')).hexdigest(),COMMON)
        self.assertIn('Crypto.Seal',CS)
        self.assertIn('Crypto.Open',CS)
        self.assertNotIn('DllImport',CS)

    def test_fixed_bounds_roles_and_both_slot_binding(self):
        self.assertIn('Header = 24, Slot = 108, Prefix = 88, Maximum = 1048576',CS)
        for magic in ('VICAPK03','VICPWD03','VICREC03','VICDAT03'):
            self.assertIn(magic,CS)
        self.assertIn('Digest(Slice(envelope,Header,Slot))',CS)
        self.assertIn('Digest(Slice(envelope,Header+Slot,Slot))',CS)
        self.assertLess(CS.index('Check(envelope);'),CS.index('plain = Crypto.Open(slot'))

    def test_fresh_key_and_id_on_password_change(self):
        body=CS.split('public static byte[] ChangePassword',1)[1]
        self.assertIn('ReadMaster(envelope,phrase,true)',body)
        self.assertIn('rng.GetBytes(nextMaster); rng.GetBytes(id)',body)
        self.assertIn('MakeSlot(id,nextMaster,phrase,true)',body)
        self.assertIn('Wipe(nextMaster)',body)
        self.assertNotIn('Slice(envelope,Header+Slot,Slot)',body)

    def test_ten_uniform_words_and_policy_not_entropy_claim(self):
        self.assertIn('GeneratedPassphrase a = Crypto.GeneratePassphrase(wordList)',CS)
        self.assertIn('GeneratedPassphrase b = Crypto.GeneratePassphrase(wordList)',CS)
        self.assertIn('String.Join(" ",words,0,10)',CS)
        self.assertIn('NormalizationForm.FormC',CS)
        self.assertIn('count < 8 || count > 256',CS)
        self.assertIn('not an entropy estimator',CS)

    def test_test_only_no_runtime_import_cleanup(self):
        for forbidden in ('WorkingRuntime','workspace.vault','Read-Vault ','Get-SubscriptionText','Remove-Item -Recurse','Start-VicaSession'):
            self.assertNotIn(forbidden,UI)
        self.assertIn("'test-data'",UI)
        self.assertIn("'verified-'",UI)
        self.assertNotIn('Read-Host \'>'+'\'',UI)
        self.assertIn('-RecoveryVerify $credentialRecovery',UI)
        self.assertIn('[VicaPasswordPreview.SelfTests]::Run($words)',UI)
        self.assertLess(UI.index('[VicaPasswordPreview.SelfTests]::Run'),UI.index("Read-Host 'New TEST password"))

    def test_disk_readback_both_credentials_before_publication(self):
        body=COMMON.split('function Write-TestEnvelope',1)[1]
        self.assertLess(body.index('Assert-TestPayload $disk $Verify $false'),body.index('[IO.File]::Replace'))
        self.assertLess(body.index('Assert-TestPayload $disk $RecoveryVerify $true'),body.index('[IO.File]::Move'))
        self.assertIn('$stream.Flush($true)',body)
        self.assertIn('$ExpectedHash',body)
        self.assertIn("'.backup-'",body)

    def test_zip_source_only_and_manifest(self):
        subprocess.run([sys.executable,str(HERE/'Build-PasswordTest.py')],check=True,capture_output=True)
        with zipfile.ZipFile(HERE.parents[1]/'downloads/VIC-A-Password-Test.zip') as z:
            self.assertIn('Start-Test.cmd',z.namelist())
            self.assertIn('vault-preview/Test-SodiumImports.ps1',z.namelist())
            self.assertNotIn('test-data/test.vault',z.namelist())
            self.assertFalse(any(n.endswith(('.dll','.exe','.enc','.vault')) for n in z.namelist()))
            for line in z.read('SHA256SUMS.txt').decode().splitlines():
                digest,name=line.split('  ',1)
                self.assertEqual(hashlib.sha256(z.read(name)).hexdigest(),digest)


if __name__ == '__main__':
    unittest.main()
