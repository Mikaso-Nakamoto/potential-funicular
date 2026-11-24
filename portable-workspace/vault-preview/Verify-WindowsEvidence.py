"""Offline consistency check for user-supplied R3 reports, not execution attestation."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parent
EVIDENCE = ROOT / 'evidence/r3-windows-user'
REPORTS = {
    'vault-install-report.txt': '97cce818688a9d8ebd3a5f68a4f879623cd0b80f67c8a877dbb90d01e52fd93f',
    'vault-test-report.txt': 'fc1afb0a3b98424a7b204f88de799b7e8426c9a9dd670a42ea5f46e6817e14ff',
}
NOT_PROVIDED = {
    'lib/vica-sodium.dll': 'f656aeb789bfc3a2ac587fae1d7cfe278bbe8ce73f28da73b4d08282ea8f9fe3',
    'lib/dependency.json': '8352a39f251a2a5cec54e0ea470a68b48ef17906ad85d67d12d9fcf48a446b3e',
}

def require(condition, message):
    if not condition:
        raise SystemExit('FAIL: ' + message)

for name, expected in REPORTS.items():
    require(hashlib.sha256((EVIDENCE / name).read_bytes()).hexdigest() == expected,
            'original report bytes changed: ' + name)
text = (EVIDENCE / 'vault-test-report.txt').read_text(encoding='utf-8-sig')
logged = {}
for digest, name in re.findall(r'^SHA256 ([A-Fa-f0-9]{64})  (.+)$', text, re.M):
    name = name.strip().replace('\\', '/')
    require(name not in logged, 'duplicate input name: ' + name)
    logged[name] = digest.lower()
    if name in NOT_PROVIDED:
        require(digest.lower() == NOT_PROVIDED[name], 'unexpected native/manifest hash: ' + name)
        continue
    # Permit only the one documented parent dependency, never arbitrary report paths.
    require((not name.startswith(('/', '../')) and '..' not in name.split('/')) or
            name == '../Workspace.Common.ps1', 'unsafe input path: ' + name)
    path = (ROOT / name).resolve()
    require(path.is_file(), 'missing input: ' + name)
    require(hashlib.sha256(path.read_bytes()).hexdigest() == digest.lower(), 'input mismatch: ' + name)
require(len(logged) == 21 and all(name in logged for name in NOT_PROVIDED), 'unexpected input hash inventory')
require('RESULT: PASS for the implemented tests only.' in text, 'test report does not declare PASS')
require('VC runtime was not preloaded before this test.' in text, 'canary preloading result missing')
print('PASS: 2 original report hashes; 19 available input hashes match.')
print('NOT COMPARED: native DLL and local manifest bytes (not provided).')
print('User-supplied unsigned output: consistency verified, not independent execution/attestation.')
