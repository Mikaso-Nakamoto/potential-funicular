"""Build source-only separate VIC-A package; never include private state or DLLs."""
from pathlib import Path
import hashlib
import zipfile

HERE = Path(__file__).resolve().parent
WORKSPACE = HERE.parent
REPO = WORKSPACE.parent
entries = {}
for name in (
    'Bootstrap.Common.ps1', 'Native.Common.ps1', 'ContainedSession.cs',
    'Start-Vica.ps1', 'Start-VicaSession.ps1', 'Refresh.Common.ps1',
    'Update-VicaSubscription.ps1', 'Test-ContainedSession.ps1', 'ContainmentFixture.cs',
):
    entries['vica/' + name] = (HERE / name).read_bytes()
for name in (
    'Vault.Common.ps1', 'VaultCrypto.cs', 'SodiumPe.cs', 'Test-SodiumImports.ps1',
    'LICENSE.libsodium.txt', 'words/eff-large.txt', 'words/NOTICE.md',
):
    entries['vault-preview/' + name] = (WORKSPACE / 'vault-preview' / name).read_bytes()
entries['Workspace.Common.ps1'] = (WORKSPACE / 'Workspace.Common.ps1').read_bytes()
entries['READ-ME.ru.md'] = (HERE / 'README.ru.md').read_bytes()
entries['VALIDATION.md'] = (HERE / 'VALIDATION.md').read_bytes()
entries['Start.cmd'] = (
    '@echo off\r\nsetlocal\r\n'
    '"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0vica\\Start-Vica.ps1"\r\n'
    'set "code=%errorlevel%"\r\n'
    'if not "%code%"=="0" (\r\n  echo VIC-A stopped. Keep this error visible; do not share secrets.\r\n  pause\r\n)\r\n'
    'exit /b %code%\r\n'
).encode('ascii')
assert hashlib.sha256(entries['vica/ContainedSession.cs']).hexdigest() in entries['vica/Native.Common.ps1'].decode()
for source, wrapper in [('VaultCrypto.cs', 'Vault.Common.ps1'), ('SodiumPe.cs', 'Vault.Common.ps1'), ('Test-SodiumImports.ps1', 'Vault.Common.ps1')]:
    assert hashlib.sha256(entries['vault-preview/' + source]).hexdigest() in entries['vault-preview/' + wrapper].decode()
assert not any(name.endswith(('.exe', '.dll', '.vault', '.enc')) or 'Runtime/' in name for name in entries)
entries['SHA256SUMS.txt'] = ''.join(f'{hashlib.sha256(content).hexdigest()}  {name}\n' for name, content in sorted(entries.items())).encode()
output = REPO / 'downloads/VIC-A-Updated.zip'
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name, content in sorted(entries.items()):
        info = zipfile.ZipInfo(name, (2026, 11, 22, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, content)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist()) == set(entries)
    assert all(archive.read(name) == content for name, content in entries.items())
print(output.name, len(entries), 'entries', output.stat().st_size, 'bytes')
print('SHA256', hashlib.sha256(output.read_bytes()).hexdigest())
