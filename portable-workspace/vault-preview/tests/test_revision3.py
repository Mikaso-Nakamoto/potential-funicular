"""Linux development checks; NOT execution of Windows C#/PowerShell paths."""
import ctypes
import hashlib
import itertools
import math
from pathlib import Path
import re
import unittest
import nacl._sodium

ROOT = Path(__file__).resolve().parents[1]
WORD_HASH = 'addd35536511597a02fa0a9ff1e5284677b8883b83e986e43f15a3db996b903e'

class Revision3Tests(unittest.TestCase):
    def test_exact_word_list(self):
        data = (ROOT / 'words/eff-large.txt').read_bytes()
        self.assertEqual(len(data), 108800)
        self.assertEqual(hashlib.sha256(data).hexdigest(), WORD_HASH)
        pairs = [line.split('\t') for line in data.decode('ascii').splitlines()]
        self.assertEqual([p[0] for p in pairs], [''.join(p) for p in itertools.product('123456', repeat=5)])
        self.assertEqual(len(set(p[1] for p in pairs)), 7776)
        self.assertTrue(all(re.fullmatch('[a-z]+(-[a-z]+)?', p[1]) for p in pairs))
        self.assertGreaterEqual(min(len(p[1]) for p in pairs), 3)
        self.assertAlmostEqual(6 * math.log2(7776), 77.54887502163469)

    def test_support_hash_pins(self):
        common = (ROOT / 'Vault.Common.ps1').read_text()
        gate = (ROOT / 'Test-SodiumImports.ps1').read_text()
        for name in ('VaultCrypto.cs', 'SodiumPe.cs', 'Test-SodiumImports.ps1'):
            self.assertIn(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), common)
        self.assertIn(hashlib.sha256((ROOT / 'SodiumPe.cs').read_bytes()).hexdigest(), gate)

    def test_system32_only_attributes(self):
        source = (ROOT / 'VaultCrypto.cs').read_text()
        attributes = re.findall(r'\[DefaultDllImportSearchPaths\((.*?)\)\]', source)
        self.assertEqual(len(attributes), source.count('[DllImport('))
        self.assertGreaterEqual(len(attributes), 8)
        self.assertEqual(set(attributes), {'DllImportSearchPath.System32'})
        self.assertIn('randombytes_uniform(7776)', source)

    def test_libsodium_uniform_sampling_bounds(self):
        # Exercises the library primitive on Linux, not the C# generator/Windows DLL.
        lib = ctypes.CDLL(nacl._sodium.__file__)
        self.assertGreaterEqual(lib.sodium_init(), 0)
        lib.randombytes_uniform.argtypes = [ctypes.c_uint32]
        lib.randombytes_uniform.restype = ctypes.c_uint32
        values = [lib.randombytes_uniform(7776) for _ in range(4096)]
        self.assertTrue(all(0 <= value < 7776 for value in values))
        self.assertGreater(len(set(values)), 1)  # smoke test, not proof of entropy

if __name__ == '__main__':
    unittest.main()
