"""Reproducible audit bundle from STAGED Git inputs; stage source changes before running.
No .git data, untracked runtime state, downloaded libraries or private files are included.
"""
from pathlib import Path
import hashlib
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASE = 'd07de26d72ec36dc124a8a6dcfe338f1ebf09d9d'

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

names = [n for n in git('ls-files', '-z', 'portable-workspace').decode().split('\0') if n]
entries = {name: git('show', ':' + name) for name in names}
entries['AUDIT-START-HERE.ru.md'] = entries['portable-workspace/vault-preview/REVIEW-R3.ru.md']
entries['review/changes-after-second-review.patch'] = git('diff', '--cached', '--binary', BASE, '--', 'portable-workspace')
entries['review/SNAPSHOT.txt'] = (
    'Revision: R3; exact source bytes in SHA256SUMS.txt.\n'
    f'Baseline before these fixes: {BASE}\n'
    'Bundle uses staged portable-workspace inputs. No self-referential commit hash.\n'
    'Source files should match the commit publishing this archive.\n'
    'User-supplied R3 Windows reports included under evidence/r3-windows-user.\n'
    'Tested executable inputs match 19fb07f18686d96e47252432869a69eccedc6431.\n'
    'Unsigned user evidence, not an independent execution or clean-machine result.\n'
).encode()
assert not any(n.endswith(('.dll', '.vault', '.pyc')) or any(
    part in ('Runtime', 'private', '__pycache__', 'lib') for part in Path(n).parts
) for n in entries)
entries['SHA256SUMS.txt'] = ''.join(
    f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name, data in sorted(entries.items())
).encode()
output = ROOT / 'downloads/VIC-A-Encryption-Expert-Review-R3-With-Reports.zip'
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name, data in sorted(entries.items()):
        info = zipfile.ZipInfo(name, date_time=(2026, 11, 22, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert all(archive.read(name) == data for name, data in entries.items())
print(f'{output.name}: {len(names)} source files, {len(entries)} entries, {output.stat().st_size} bytes')
print('SHA256:', hashlib.sha256(output.read_bytes()).hexdigest())
