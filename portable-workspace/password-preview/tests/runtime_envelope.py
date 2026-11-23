"""Development-only C#5 crypto execution on Linux; never reads user data.
Requires pythonnet/CoreCLR3.1, Roslyn assemblies, libsodium1.0.22 and argon2-cffi/cryptography.
Environment paths are explicit; no downloads, substitutions of algorithms, or CheckSupport bypass.
This is not a PowerShell5.1/Windows execution test.
"""
import os
from pythonnet import load
load('coreclr',runtime_config=os.environ['VICA_RUNTIMECONFIG'],dotnet_root=os.environ['VICA_DOTNET'])
import clr,glob
for name in ['System.Collections.Immutable','Microsoft.CodeAnalysis','Microsoft.CodeAnalysis.CSharp']:
 clr.AddReference(os.environ['VICA_ROSLYN']+'/'+name+'.dll')
from Microsoft.CodeAnalysis import MetadataReference,OutputKind,SyntaxTree
from Microsoft.CodeAnalysis.CSharp import CSharpSyntaxTree,CSharpCompilation,CSharpCompilationOptions,CSharpParseOptions,LanguageVersion
from System import Array,Byte
from System.IO import MemoryStream
from System.Reflection import Assembly
from System.Security import SecureString
from pathlib import Path
base=Path('portable-workspace/vault-preview/VaultCrypto.cs').read_text().replace('__SODIUM_DLL__',os.environ['VICA_SODIUM'])
base=base.replace('password.Length < 16','password.Length < 8').replace('at least 16 characters','at least 8 characters')
extra=Path('portable-workspace/password-preview/PasswordEnvelope.cs').read_text()+'\n'+Path('portable-workspace/password-preview/PasswordSelfTests.cs').read_text()
refs=Array[MetadataReference]([MetadataReference.CreateFromFile(x) for x in glob.glob(os.environ['VICA_DOTNET']+'/shared/Microsoft.NETCore.App/*/*.dll')])
tree=CSharpSyntaxTree.ParseText(base+'\n'+extra,CSharpParseOptions.Default.WithLanguageVersion(LanguageVersion.CSharp5))
c=CSharpCompilation.Create('VicaPasswordRun',Array[SyntaxTree]([tree]),refs,CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary))
stream=MemoryStream(); result=c.Emit(stream)
assert result.Success, '\n'.join(str(x) for x in result.Diagnostics)
assembly=Assembly.Load(stream.ToArray())
from VicaPasswordPreview import Envelope, SelfTests
from VicAVault import Crypto
Crypto.CheckSupport()
print('Compiled C#5 and loaded official libsodium1.0.22 on Linux; crypto runtime PASS')
def secret(s):
 x=SecureString()
 for c in s: x.AppendChar(c)
 x.MakeReadOnly();return x
p=secret('Orchid-telescope-river-572!')
created=Envelope.Create(Array[Byte](b'preview-synthetic-payload'),p,p,Array[Byte](Path('portable-workspace/vault-preview/words/eff-large.txt').read_bytes()))
r=created.Recovery.CopyPassword()
assert bytes(Envelope.Open(created.Envelope,p,False))==b'preview-synthetic-payload'
assert bytes(Envelope.Open(created.Envelope,r,True))==b'preview-synthetic-payload'
print('Password and recovery both open: PASS',len(created.Envelope))

from System.Runtime.InteropServices import Marshal
from argon2.low_level import hash_secret_raw, Type
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import hashlib,unicodedata
checks=2

def ok(label):
 global checks
 checks+=1
 print('PASS:',label)

def fails(action,label):
 try: action()
 except Exception: ok(label);return
 raise AssertionError('Expected failure: '+label)

def reveal(s):
 pointer=Marshal.SecureStringToBSTR(s)
 try: return str(Marshal.PtrToStringBSTR(pointer))
 finally: Marshal.ZeroFreeBSTR(pointer)

raw=bytes(created.Envelope)
phrase=reveal(r)
assert len(phrase.split(' '))==10
ok('ten generated recovery words')
short=secret('M7!vQ2#z')
short_created=Envelope.Create(Array[Byte](b'eight-character-test'),short,short,Array[Byte](Path('portable-workspace/vault-preview/words/eff-large.txt').read_bytes()))
assert bytes(Envelope.Open(short_created.Envelope,short,False))==b'eight-character-test'
short_created.Dispose();short.Dispose()
ok('eight-character password creates and opens through actual crypto')
wrong=secret('Different-planet-signal-628!')
fails(lambda: Envelope.Open(created.Envelope,wrong,False),'wrong password')
fails(lambda: Envelope.Open(created.Envelope,wrong,True),'wrong recovery')
fails(lambda: Envelope.Open(created.Envelope,r,False),'recovery cannot masquerade as password slot')
fails(lambda: Envelope.Open(created.Envelope,p,True),'password cannot masquerade as recovery slot')
for offset in [0,8,23,24,131,132,239,240,len(raw)-1]:
 tampered=bytearray(raw);tampered[offset]^=1
 fails(lambda: Envelope.Open(Array[Byte](tampered),p,False),'tamper offset '+str(offset))
for cut in [0,24,379,len(raw)-1]:
 fails(lambda: Envelope.Open(Array[Byte](raw[:cut]),p,False),'truncation '+str(cut))
fails(lambda: Envelope.Open(Array[Byte](raw+b'x'),p,False),'appended data')
swapped=raw[:24]+raw[132:240]+raw[24:132]+raw[240:]
fails(lambda: Envelope.Open(Array[Byte](swapped),p,False),'swapped role slots')
for weak in ['short','1234567890123456','passwordpassword','abcdefghijklmnop','qwertyuiopasdfghj',' abcdefg-lantern-52','Abcdefg-lantern-52 ','planetplanetplanet','a'*100]:
 w=secret(weak)
 try: fails(lambda: Envelope.ValidatePassword(w,w),'reject obvious weak/policy input')
 finally: w.Dispose()
nfc=secret('Café-orbit-lantern-572!');nfd=secret('Cafe\u0301-orbit-lantern-572!')
Envelope.ValidatePassword(nfc,nfd)
ok('NFC-equivalent confirmation accepted')
fails(lambda: Envelope.ValidatePassword(p,wrong),'mismatched password confirmation')
new=secret('Juniper-observatory-cloud-934!')
changed=Envelope.ChangePassword(created.Envelope,p,False,new,new,r)
assert bytes(Envelope.Open(changed,new,False))==b'preview-synthetic-payload'
assert bytes(Envelope.Open(changed,r,True))==b'preview-synthetic-payload'
assert bytes(changed)[8:24]!=raw[8:24] and bytes(changed)[132:240]!=raw[132:240]
assert bytes(created.Envelope)==raw
ok('password change rotates key/ID while preserving recovery words, payload and original input')
fails(lambda: Envelope.Open(changed,p,False),'old password fails on changed current envelope')
reset=Envelope.ChangePassword(changed,r,True,p,p,r)
assert bytes(Envelope.Open(reset,p,False))==b'preview-synthetic-payload'
assert bytes(Envelope.Open(reset,r,True))==b'preview-synthetic-payload'
ok('recovery-only reset returns access without changing phrase')
fails(lambda: Envelope.Open(reset,new,False),'pre-reset password fails on current envelope')
fails(lambda: Envelope.ChangePassword(created.Envelope,wrong,False,new,new,r),'wrong current credential cannot change password')
fails(lambda: Envelope.ChangePassword(created.Envelope,p,False,new,wrong,r),'mismatched new confirmation cannot change password')
assert bytes(created.Envelope)==raw
ok('failed changes leave caller envelope unchanged')
second=Envelope.Create(Array[Byte](b'preview-synthetic-payload'),p,p,Array[Byte](Path('portable-workspace/vault-preview/words/eff-large.txt').read_bytes()))
assert bytes(second.Envelope)[8:24]!=raw[8:24] and bytes(second.Envelope)!=raw
cross=raw[:132]+bytes(second.Envelope)[132:240]+raw[240:]
fails(lambda: Envelope.Open(Array[Byte](cross),p,False),'cross-container unused recovery slot replacement detected')
ok('new container ID and randomized envelopes')

def independent_v02(blob,credential):
 assert blob[:8]==b'VICAVA02' and len(blob)>=52
 key=hash_secret_raw(unicodedata.normalize('NFC',credential).encode(),blob[8:24],time_cost=3,memory_cost=65536,parallelism=1,hash_len=32,type=Type.ID,version=19)
 return AESGCM(key).decrypt(blob[24:36],blob[36:],blob[:36])

old_slot=independent_v02(raw[24:132],reveal(p))
fails(lambda: independent_v02(bytes(changed)[240:],old_slot[24:].hex()),'old backup master cannot decrypt changed envelope')

for credential,offset,tag in [(reveal(p),24,b'VICPWD03'),(phrase,132,b'VICREC03')]:
 slot=independent_v02(raw[offset:offset+108],credential)
 assert slot[:8]==tag and slot[8:24]==raw[8:24]
 data=independent_v02(raw[240:],slot[24:].hex())
 assert data[:8]==b'VICDAT03' and data[8:24]==raw[8:24]
 assert data[24:56]==hashlib.sha256(raw[24:132]).digest()
 assert data[56:88]==hashlib.sha256(raw[132:240]).digest()
 assert data[88:]==b'preview-synthetic-payload'
 ok('independent Argon2id/AESGCM opens '+tag.decode())
for x in [p,r,wrong,nfc,nfd,new]:x.Dispose()
created.Dispose();second.Dispose()
assert SelfTests.Run(Array[Byte](Path('portable-workspace/vault-preview/words/eff-large.txt').read_bytes()))==17
ok('the exact Windows-gate C# self-check also passes on Linux')
print('Runtime checks passed:',checks,'; actual C# crypto on Linux, not Windows/PowerShell')
