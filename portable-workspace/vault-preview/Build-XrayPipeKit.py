"""Whitelist-only kit: no dependency download, private state or generated native/test executables."""
from pathlib import Path
import hashlib
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
entries = {'READ-ME.ru.md': (HERE / 'XRAY-STDIN.ru.md').read_bytes(),
           'Workspace.Common.ps1': (HERE.parent / 'Workspace.Common.ps1').read_bytes()}
for name in ['XrayPipe.cs', 'XrayPipe.Common.ps1', 'Test-XrayPipe.ps1', 'tests/XrayPipeFixture.cs']:
    entries['vault-preview/' + name] = (HERE / name).read_bytes()
assert hashlib.sha256((HERE / 'XrayPipe.cs').read_bytes()).hexdigest() in (HERE / 'XrayPipe.Common.ps1').read_text()
entries['SHA256SUMS.txt'] = ''.join(
    f'{hashlib.sha256(value).hexdigest()}  {name}\n' for name, value in sorted(entries.items())
).encode()
output = ROOT / 'downloads/VIC-A-Xray-Stdin-Tests.zip'
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
