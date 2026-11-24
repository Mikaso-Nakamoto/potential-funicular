"""Source-only launcher repair, no user Runtime and no in-place publication."""
from pathlib import Path
import hashlib
import zipfile

here = Path(__file__).resolve().parent
names = (
    'Workspace-Console.ps1', 'Workspace.Common.ps1', 'Start-Workspace.ps1',
    'Start-SessionWindow.ps1', 'Start-RepairConsole.ps1', 'Workspace.Job.ps1',
    'WorkspaceJob.cs', 'Test-WorkspaceJob.ps1', 'VicA.Intro.ps1', 'Iris.Intro.ps1',
    'Update-Subscription.ps1', 'Test-Parser.ps1', 'Test-CryptoPolicy.ps1',
    'Test-DeviceHwid.ps1', 'Test-VicAConsole.ps1',
)
entries = {name: (here / name).read_bytes() for name in names}
entries['READ-ME.ru.md'] = (here / 'LAUNCHER-REPAIR.ru.md').read_bytes()
entries['Start.cmd'] = ('@echo off\r\nsetlocal\r\ntitle VIC-A - Launcher Repair\r\n'
    '"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Start-RepairConsole.ps1"\r\n'
    'if errorlevel 1 (\r\n  echo Launcher stopped. Read the error above. No policy bypass.\r\n  pause\r\n)\r\nendlocal\r\n').encode('ascii')
assert hashlib.sha256(entries['WorkspaceJob.cs']).hexdigest() in entries['Workspace.Job.ps1'].decode()
entries['SHA256SUMS.txt'] = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name, data in sorted(entries.items())).encode()
output = here.parent / 'downloads/VIC-A-Launcher-Repair.zip'
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name, data in sorted(entries.items()):
        info = zipfile.ZipInfo(name, (2026, 11, 22, 0, 0, 0)); info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert all(archive.read(name) == data for name, data in entries.items())
print(output.name, len(entries), 'entries;', output.stat().st_size, 'bytes')
print('SHA256:', hashlib.sha256(output.read_bytes()).hexdigest())
