from pathlib import Path
import unittest
S=(Path(__file__).resolve().parents[1]/'Clean-OldCopies.ps1').read_text()
class Cleanup(unittest.TestCase):
 def test_scope(self):
  self.assertIn("@('Xray','LibreWolf','private\\downloads')",S)
  self.assertNotIn('Remove-Item',S)
  self.assertNotIn('Stop-Process',S)
  self.assertNotIn('-Recurse',S)
 def test_verify_before_delete(self):
  self.assertLess(S.index('-ValidateOnly'),S.index("-cne 'CLEAN'"))
  self.assertLess(S.index('if (Same-Stream $a $b)'),S.index('[VicaCleanupFile]::Delete($a)'))
  self.assertIn('SetFileInformationByHandle(file.SafeFileHandle',S)
  self.assertIn('ReparsePoint',S)
  self.assertIn("$LASTEXITCODE -ne 0",S)
 def test_destination_untouched(self):
  self.assertIn("$b=[IO.File]::Open($target,'Open','Read','Read')",S)
  self.assertIn('$a=[VicaCleanupFile]::Open($item.FullName)',S)
  self.assertNotIn('[VicaCleanupFile]::Delete($b)',S)
if __name__=='__main__':unittest.main()
