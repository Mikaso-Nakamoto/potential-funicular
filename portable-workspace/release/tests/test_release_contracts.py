from pathlib import Path
import unittest,subprocess,sys,zipfile,hashlib
H=Path(__file__).resolve().parents[1]
class ReleaseContracts(unittest.TestCase):
 def test_package(self):
  subprocess.run([sys.executable,str(H/'Build-Release.py')],check=True,capture_output=True)
  with zipfile.ZipFile(H.parents[1]/'downloads/VIC-A-Password-Edition.zip') as z:
   for line in z.read('SHA256SUMS.txt').decode().splitlines():
    h,n=line.split('  ',1);self.assertEqual(hashlib.sha256(z.read(n)).hexdigest(),h)
   self.assertFalse(any(n.endswith(('.dll','.exe','.vault')) for n in z.namelist()))
   self.assertIn('VicA.Intro.ps1',z.namelist())
   launch=z.read('vica/Start-VicaSession.ps1').decode()
   self.assertIn('VaultV03.Common.ps1',launch)
   self.assertNotIn('Initialize-VaultCrypto',launch)
   self.assertIn('    Initialize-PasswordPreview\n',launch)
   self.assertIn('function Initialize-PasswordPreview',z.read('Password.Common.ps1').decode())
   self.assertLess(launch.index('$env:TEMP = $tmp'),launch.index('    Initialize-PasswordPreview'))
   self.assertLess(launch.index('    Initialize-PasswordPreview'),launch.index("Read-Host 'Password (hidden)'"))
   self.assertTrue(z.read('vica/Refresh.Common.ps1').decode().rstrip().endswith(". (Join-Path $PSScriptRoot 'VaultV03.Common.ps1')"))
   base=z.read('vault-preview/Vault.Common.ps1').decode()
   self.assertNotIn('function Initialize-VaultCrypto',base)
   self.assertNotIn('function Read-Vault(',base)
 def test_import_separate_and_fresh(self):
  s=(H/'Initialize-Vica.ps1').read_text()
  self.assertIn('Destination exists; no merge/overwrite',s)
  self.assertIn('[VicaPasswordPreview.Envelope]::Create',s)
  self.assertLess(s.index('Write-V03Stage'),s.index('[IO.Directory]::Move'))
  self.assertIn("'IMPORT'",s)
  self.assertNotIn('VIC-A-Password-Test',s)
  self.assertIn('ReparsePoint',s)
  self.assertIn('Test-XrayObjectInMemory',s)
  self.assertIn('OSSign (Scheibling Consulting AB)',s)
 def test_refresh_and_reset_confirm_before_replace(self):
  s=(H/'Reset-VicaPassword.ps1').read_text()
  self.assertLess(s.index('Write-V03Stage'),s.index("-cne 'RESET'"))
  self.assertLess(s.index("-cne 'RESET'"),s.index('[IO.File]::Replace'))
  v=(H/'VaultV03.Common.ps1').read_text()
  self.assertIn('::UpdatePayload($original,$Password,$plain)',v)
  self.assertIn('No V02/plaintext fallback',v)
  self.assertLess(v.index('Write-V03Stage $stage'),v.index('[IO.File]::Replace'))
 def test_menu_and_isolated_operations(self):
  s=(H/'Start-Vica.ps1').read_text()
  self.assertIn('Show-VicAIntro',s)
  self.assertIn("'ru'",s);self.assertIn("'en'",s)
  self.assertIn("'eye'",s);self.assertIn("'archive'",s)
  self.assertIn("'Test-ContainedSession.ps1'",s)
  self.assertIn('Initialize-VicaDependency',s)
  self.assertNotIn('Remove-Item',s)
if __name__=='__main__':unittest.main()
