from pathlib import Path
import unittest,subprocess,sys,zipfile,hashlib
H=Path(__file__).resolve().parents[1]
S=(H/'Organize-Vica.ps1').read_text()
class Organizer(unittest.TestCase):
 def test_no_destruction_or_new_credentials(self):
  for forbidden in ['Remove-Item','Stop-Process','Invoke-WebRequest','::Create($','::ChangePassword']:
   self.assertNotIn(forbidden,S)
  self.assertIn("'Destination already exists. No overwrite/merge.'",S)
 def test_copy_and_publication(self):
  self.assertIn('ComputeHash($inputFile)',S);self.assertIn('ComputeHash($outputFile)',S)
  self.assertIn('ReparsePoint',S)
  self.assertIn('Preserved-Older-Data',S)
  self.assertLess(S.index('-ValidateOnly'),S.index('[IO.Directory]::Move'))
  self.assertLess(S.index('Get-AuthenticodeSignature'),S.index('[IO.Directory]::Move'))
  self.assertIn("'CreateNew','ReadWrite','None'",S)
 def test_package(self):
  subprocess.run([sys.executable,str(H/'Build-Organizer.py')],check=True,capture_output=True)
  with zipfile.ZipFile(H.parents[1]/'downloads/VIC-A-Organizer.zip') as z:
   self.assertEqual(hashlib.sha256(z.read('Application.zip')).hexdigest().upper(),z.read('Application.sha256').decode())
   self.assertTrue(z.read('Organize-Vica.ps1').startswith(b'\xef\xbb\xbf'))
if __name__=='__main__':unittest.main()
