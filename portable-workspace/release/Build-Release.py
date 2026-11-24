"""Separate V03 production candidate; original runtime and packages never modified."""
from pathlib import Path
import hashlib,zipfile
H=Path(__file__).resolve().parent; W=H.parent; P=W/'password-preview'; V=W/'vica'
e={}
for n in ['Initialize-Vica.ps1','Reset-VicaPassword.ps1','VaultV03.Common.ps1','Start-Vica.ps1']:
 b=(H/n).read_bytes();e['vica/'+n]=b'\xef\xbb\xbf'+b if n=='Start-Vica.ps1' else b
for n in ['Native.Common.ps1','ContainedSession.cs','ContainmentFixture.cs','Test-ContainedSession.ps1','Bootstrap.Common.ps1']:
 e['vica/'+n]=(V/n).read_bytes()
for n in ['Start-VicaSession.ps1','Refresh.Common.ps1','Update-VicaSubscription.ps1']:
 s=(V/n).read_text(encoding='utf-8-sig').replace('Vault passphrase (hidden)','Password (hidden)')
 if n=='Start-VicaSession.ps1':
  assert s.count('    Initialize-VaultCrypto\n') == 1
  s=s.replace('    Initialize-VaultCrypto\n','    Initialize-PasswordPreview\n')
  s=s.replace(". (Join-Path $scriptDirectory 'Native.Common.ps1')", ". (Join-Path $scriptDirectory 'Native.Common.ps1')\n. (Join-Path $scriptDirectory 'VaultV03.Common.ps1')")
 if n=='Refresh.Common.ps1':s+="\n. (Join-Path $PSScriptRoot 'VaultV03.Common.ps1')\n"
 e['vica/'+n]=s.encode()
for n in ['PasswordEnvelope.cs','PasswordSelfTests.cs']:
 e[n]=(P/n).read_bytes()
s=(P/'Password.Common.ps1').read_text();s=s[:s.index('function Assert-TestPayload')];e['Password.Common.ps1']=s.encode()
for n in ['VaultCrypto.cs','SodiumPe.cs','Test-SodiumImports.ps1','words/eff-large.txt','words/NOTICE.md','LICENSE.libsodium.txt']:
 e['vault-preview/'+n]=(W/'vault-preview'/n).read_bytes()
e['vault-preview/VaultCrypto.cs']=e['vault-preview/VaultCrypto.cs'].replace(b'password.Length < 16',b'password.Length < 8').replace(b'at least 16 characters',b'at least 8 characters')
s=(W/'vault-preview/Vault.Common.ps1').read_text()
t="$vaultToolDirectory = $PSScriptRoot\nSet-StrictMode -Version Latest\n$ErrorActionPreference = 'Stop'\n"
for fn in ['Assert-VaultSupportIntegrity','Read-BoundedVaultBytes','Assert-VaultDocument']:
 a=s.index('function '+fn+' ' if fn=='Assert-VaultSupportIntegrity' else 'function '+fn+'(')
 b=s.find('\nfunction ',a+1);t+=s[a:b if b>=0 else len(s)]+'\n'
e['vault-preview/Vault.Common.ps1']=t.encode()
for n in ['Workspace.Common.ps1','VicA.Intro.ps1']:e[n]=(W/n).read_bytes()
e['READ-ME.ru.md']=(H/'README.ru.md').read_bytes()
e['Start.cmd']=('@echo off\r\nsetlocal\r\n"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0vica\\Start-Vica.ps1"\r\nset "code=%errorlevel%"\r\necho VIC-A closed.\r\npause\r\nexit /b %code%\r\n').encode()
for name in ['PasswordEnvelope.cs','PasswordSelfTests.cs','vault-preview/VaultCrypto.cs']:
 assert hashlib.sha256(e[name]).hexdigest() in e['Password.Common.ps1'].decode(),name
assert not any(n.endswith(('.dll','.exe','.vault','.enc')) for n in e)
e['SHA256SUMS.txt']=''.join(f'{hashlib.sha256(v).hexdigest()}  {n}\n' for n,v in sorted(e.items())).encode()
p=W.parent/'downloads/VIC-A-Password-Edition.zip'
with zipfile.ZipFile(p,'w',zipfile.ZIP_DEFLATED) as z:
 for n,v in sorted(e.items()):
  i=zipfile.ZipInfo(n,(2026,11,22,0,0,0));i.compress_type=zipfile.ZIP_DEFLATED;z.writestr(i,v)
with zipfile.ZipFile(p) as z:
 assert z.testzip() is None
 assert all(z.read(n)==v for n,v in e.items())
print(p.name,len(e),'files',p.stat().st_size,'bytes',hashlib.sha256(p.read_bytes()).hexdigest())
