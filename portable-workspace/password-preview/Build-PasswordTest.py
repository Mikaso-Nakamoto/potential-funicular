"""Deterministic source-only, synthetic-only password/recovery test kit."""
from pathlib import Path
import hashlib
import zipfile

HERE = Path(__file__).resolve().parent
WORKSPACE = HERE.parent
entries = {}
for name in ('Start-PasswordTest.ps1','Password.Common.ps1','PasswordEnvelope.cs','PasswordSelfTests.cs','FORMAT.md','VALIDATION.md'):
    entries[name] = (HERE / name).read_bytes()
entries['READ-ME.ru.md'] = (HERE / 'README.ru.md').read_bytes()
entries['Bootstrap.Common.ps1'] = (WORKSPACE / 'vica/Bootstrap.Common.ps1').read_bytes()
for name in ('Vault.Common.ps1','VaultCrypto.cs','SodiumPe.cs','Test-SodiumImports.ps1','LICENSE.libsodium.txt','words/eff-large.txt','words/NOTICE.md'):
    entries['vault-preview/' + name] = (WORKSPACE / 'vault-preview' / name).read_bytes()
# Test-only minimum; production VaultCrypto.cs is never edited. KDF/cipher/format unchanged.
entries['vault-preview/VaultCrypto.cs'] = entries['vault-preview/VaultCrypto.cs'].replace(b'password.Length < 16',b'password.Length < 8').replace(b'at least 16 characters',b'at least 8 characters')
entries['Start-Test.cmd'] = (
    '@echo off\r\nsetlocal\r\n'
    '"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Start-PasswordTest.ps1"\r\n'
    'set "code=%errorlevel%"\r\n'
    'echo Password TEST ended. No production import or cleanup.\r\npause\r\nexit /b %code%\r\n'
).encode('ascii')
for source in ('PasswordEnvelope.cs','PasswordSelfTests.cs'):
    assert hashlib.sha256(entries[source]).hexdigest() in entries['Password.Common.ps1'].decode()
assert hashlib.sha256(entries['vault-preview/VaultCrypto.cs']).hexdigest() in entries['Password.Common.ps1'].decode()
for source in ('SodiumPe.cs','Test-SodiumImports.ps1'):
    assert hashlib.sha256(entries['vault-preview/' + source]).hexdigest() in entries['vault-preview/Vault.Common.ps1'].decode()
assert not any(n.endswith(('.dll','.exe','.vault','.enc')) or 'Runtime/' in n for n in entries)
entries['SHA256SUMS.txt'] = ''.join(f'{hashlib.sha256(value).hexdigest()}  {name}\n' for name,value in sorted(entries.items())).encode()
output = WORKSPACE.parent / 'downloads/VIC-A-Password-Test.zip'
with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
    for name,value in sorted(entries.items()):
        info = zipfile.ZipInfo(name,(2026,11,22,0,0,0)); info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info,value)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist()) == set(entries)
    assert all(archive.read(name)==value for name,value in entries.items())
print(output.name,len(entries),'entries;',output.stat().st_size,'bytes')
print('SHA256',hashlib.sha256(output.read_bytes()).hexdigest())
