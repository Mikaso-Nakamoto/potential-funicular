"""Isolated launcher-integration kit. Whitelist sources only; no real Runtime or native binaries."""
from pathlib import Path
import hashlib
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
entries = {'READ-ME.ru.md': (HERE / 'VAULT-LAUNCH.ru.md').read_bytes()}
for name in ('Workspace.Common.ps1', 'Start-VaultWorkspace.ps1'):
    entries[name] = (HERE.parent / name).read_bytes()
for name in (
    'Install-VaultDependency.ps1', 'Vault.Common.ps1', 'VaultCrypto.cs', 'SodiumPe.cs',
    'Test-SodiumImports.ps1', 'XrayPipe.Common.ps1', 'XrayPipe.cs', 'Test-XrayPipe.ps1',
    'Start-VaultLaunchTests.ps1', 'Test-VaultLaunch.ps1', 'tests/XrayPipeFixture.cs',
    'words/eff-large.txt', 'words/NOTICE.md', 'LICENSE.libsodium.txt',
):
    entries['vault-preview/' + name] = (HERE / name).read_bytes()
assert hashlib.sha256((HERE / 'XrayPipe.cs').read_bytes()).hexdigest() in (HERE / 'XrayPipe.Common.ps1').read_text()
assert hashlib.sha256((HERE / 'VaultCrypto.cs').read_bytes()).hexdigest() in (HERE / 'Vault.Common.ps1').read_text()
assert not any(name.endswith(('.dll', '.exe', '.vault')) or '/Runtime/' in name for name in entries)
entries['SHA256SUMS.txt'] = ''.join(f'{hashlib.sha256(value).hexdigest()}  {name}\n' for name, value in sorted(entries.items())).encode()
output = ROOT / 'downloads/VIC-A-Vault-Launch-Tests.zip'
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name, value in sorted(entries.items()):
        info = zipfile.ZipInfo(name, (2026, 11, 22, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, value)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert all(archive.read(name) == value for name, value in entries.items())
print(output.name, len(entries), 'files;', output.stat().st_size, 'bytes')
print('SHA256:', hashlib.sha256(output.read_bytes()).hexdigest())
