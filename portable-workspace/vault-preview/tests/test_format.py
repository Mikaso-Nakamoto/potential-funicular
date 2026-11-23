"""Development-only cross-implementation tests. No real user secrets, network or files in Runtime.
Dependencies: PyNaCl (libsodium), argon2-cffi, cryptography. Not required on user PCs.
"""
import base64
import ctypes
import json
import unittest
import unicodedata
from pathlib import Path
import nacl._sodium
from argon2.low_level import hash_secret_raw, Type
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SODIUM = ctypes.CDLL(nacl._sodium.__file__)
SODIUM.sodium_init()
SODIUM.crypto_pwhash.argtypes = [ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_size_t, ctypes.c_int]
SODIUM.crypto_aead_aes256gcm_encrypt.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulonglong), ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
SODIUM.crypto_aead_aes256gcm_decrypt.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulonglong), ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p, ctypes.c_void_p]


def key(password, salt):
    password = unicodedata.normalize('NFC', password.decode('utf-8')).encode('utf-8')
    result = ctypes.create_string_buffer(32)
    code = SODIUM.crypto_pwhash(result, 32, password, len(password), salt, 3, 67108864, 2)
    assert code == 0
    return result.raw


def seal(password, salt, nonce, message):
    header = b'VICAVA02' + salt + nonce
    output = ctypes.create_string_buffer(len(message) + 16)
    length = ctypes.c_ulonglong()
    code = SODIUM.crypto_aead_aes256gcm_encrypt(output, ctypes.byref(length), message, len(message), header, len(header), None, nonce, key(password, salt))
    assert code == 0 and length.value == len(message) + 16
    return header + output.raw


def open_envelope(password, envelope):
    if len(envelope) < 52 or envelope[:8] != b'VICAVA02':
        raise ValueError('Invalid envelope')
    header, cipher = envelope[:36], envelope[36:]
    output = ctypes.create_string_buffer(len(cipher) - 16)
    length = ctypes.c_ulonglong()
    code = SODIUM.crypto_aead_aes256gcm_decrypt(output, ctypes.byref(length), None, cipher, len(cipher), header, len(header), header[24:36], key(password, header[8:24]))
    if code != 0:
        raise ValueError('Authentication failed')
    return output.raw[:length.value]


class FormatTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if SODIUM.crypto_aead_aes256gcm_is_available() != 1:
            raise unittest.SkipTest('AES-GCM hardware unavailable')
        cls.fixture = json.loads((Path(__file__).parent / 'synthetic-vector.json').read_text())
        cls.password = cls.fixture['syntheticPassword'].encode()
        cls.envelope = base64.b64decode(cls.fixture['envelopeBase64'])
        cls.message = cls.fixture['syntheticPlaintext'].encode()

    def test_sodium_matches_fixture(self):
        self.assertEqual(seal(self.password, self.envelope[8:24], self.envelope[24:36], self.message), self.envelope)
        self.assertEqual(open_envelope(self.password, self.envelope), self.message)

    def test_independent_argon2_and_aes_gcm(self):
        derived = hash_secret_raw(self.password, self.envelope[8:24], time_cost=3, memory_cost=65536, parallelism=1, hash_len=32, type=Type.ID, version=19)
        self.assertEqual(derived, key(self.password, self.envelope[8:24]))
        self.assertEqual(AESGCM(derived).decrypt(self.envelope[24:36], self.envelope[36:], self.envelope[:36]), self.message)

    def test_unicode_canonical_equivalence(self):
        nfc = 'Synthetic Ä passphrase for testing!'.encode()
        nfd = unicodedata.normalize('NFD', nfc.decode()).encode()
        envelope = seal(nfc, bytes(range(16)), bytes(range(12)), self.message)
        self.assertEqual(open_envelope(nfd, envelope), self.message)

    def test_old_format_rejected(self):
        with self.assertRaises(ValueError):
            open_envelope(self.password, b'VICAVA01' + self.envelope[8:])

    def test_wrong_password(self):
        with self.assertRaises(ValueError):
            open_envelope(b'incorrect synthetic password', self.envelope)

    def test_tampering(self):
        for offset in (0, 8, 24, 36, len(self.envelope)-1):
            altered = bytearray(self.envelope)
            altered[offset] ^= 1
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                open_envelope(self.password, bytes(altered))

    def test_truncation(self):
        for length in (0, 7, 35, 51, len(self.envelope)-1):
            with self.subTest(length=length), self.assertRaises(ValueError):
                open_envelope(self.password, self.envelope[:length])

    def test_salt_and_nonce_change_envelope(self):
        self.assertNotEqual(seal(self.password, bytes(range(16,32)), self.envelope[24:36], self.message), self.envelope)
        self.assertNotEqual(seal(self.password, self.envelope[8:24], bytes(range(32,44)), self.message), self.envelope)

if __name__ == '__main__':
    unittest.main()
