from pathlib import Path
import subprocess,io,zipfile,hashlib
h=Path(__file__).resolve().parent
seed=subprocess.check_output(['git','show','1ac21b1:downloads/VIC-A-Password-Edition.zip'],cwd=h)
with zipfile.ZipFile(io.BytesIO(seed)) as z:
 assert z.testzip() is None
 for line in z.read('SHA256SUMS.txt').decode().splitlines():
  digest,name=line.split('  ',1);assert hashlib.sha256(z.read(name)).hexdigest()==digest
 launch=z.read('vica/Start-VicaSession.ps1').decode()
 assert '    Initialize-PasswordPreview\n' in launch
 assert 'Initialize-VaultCrypto' not in launch
out=h.parents[1]/'downloads/VIC-A-Organizer.zip'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
 entries={'Application.zip':seed,'Application.sha256':hashlib.sha256(seed).hexdigest().upper().encode()}
 for n in ['Organize-Vica.ps1','Start-Organize.cmd','README.ru.md']:
  entries[n]=(b'\xef\xbb\xbf' if n.endswith('.ps1') else b'')+(h/n).read_bytes()
 for n,b in entries.items():
  info=zipfile.ZipInfo(n,(2026,11,22,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,b)
with zipfile.ZipFile(out) as z:assert z.testzip() is None
print(out,hashlib.sha256(out.read_bytes()).hexdigest())
