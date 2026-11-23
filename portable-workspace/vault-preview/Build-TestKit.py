"""Build a public synthetic-only Windows test kit. Run from any working directory."""
from pathlib import Path
import hashlib
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FILES = [
    'Install-VaultDependency.ps1', 'Run-VaultTests.ps1', 'Test-Vault.ps1',
    'Test-VaultIO.ps1', 'Test-VaultLoadFailure.ps1', 'Test-SodiumImports.ps1',
    'Test-SodiumPe.ps1', 'SodiumPe.cs', 'Vault.Common.ps1', 'VaultCrypto.cs',
    'tests/synthetic-vector.json', 'FORMAT.md', 'LICENSE.libsodium.txt',
]
entries = {'READ-ME.ru.md': (HERE / 'TEST-KIT.ru.md').read_bytes(),
           'Workspace.Common.ps1': (HERE.parent / 'Workspace.Common.ps1').read_bytes()}
for name in FILES:
    entries['vault-preview/' + name] = (HERE / name).read_bytes()
source_hash = hashlib.sha256((HERE / 'VaultCrypto.cs').read_bytes()).hexdigest()
assert source_hash in (HERE / 'Vault.Common.ps1').read_text()
assert not any(part.lower() in ('runtime', 'private', 'lib')
               for name in entries for part in Path(name).parts)
assert not any(name.endswith(('.dll', '.vault')) for name in entries)
sums = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name, data in sorted(entries.items()))
entries['SHA256SUMS.txt'] = sums.encode()
output = ROOT / 'downloads' / 'VIC-A-Vault-Test-Kit.zip'
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name, data in sorted(entries.items()):
        info = zipfile.ZipInfo(name, date_time=(2026, 11, 22, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist()) == set(entries)
    assert all(archive.read(name) == data for name, data in entries.items())
print(f'{output.name}: {len(entries)} files, {output.stat().st_size} bytes')
print('SHA256:', hashlib.sha256(output.read_bytes()).hexdigest())
