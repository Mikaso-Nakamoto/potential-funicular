"""Source/packaging contracts; explicitly NOT Windows execution or vulnerability proof."""
from pathlib import Path
import ctypes as c
import hashlib
import subprocess
import sys
import unittest
import zipfile

HERE = Path(__file__).resolve().parents[1]
NATIVE = (HERE / 'ContainedSession.cs').read_text()
PS = (HERE / 'Native.Common.ps1').read_text()
REFRESH = (HERE / 'Refresh.Common.ps1').read_text()
LAUNCH = (HERE / 'Start-VicaSession.ps1').read_text()
MENU = (HERE / 'Start-Vica.ps1').read_text()


class UnifiedContracts(unittest.TestCase):
    def test_assign_before_resume_and_whitelisted_modes(self):
        self.assertLess(NATIVE.index('AssignProcessToJobObject(owner.job'), NATIVE.index('ResumeThread(pi.thread)'))
        self.assertIn('0x08080404', NATIVE)
        self.assertIn('limits.basic.flags = 0x2000', NATIVE)
        self.assertNotIn('Process.Start(', NATIVE.replace('// A not-assigned child is still suspended; never resume it or fall back to Process.Start.', ''))
        self.assertIn('Invalid native mode.', NATIVE)
        self.assertIn('run -config stdin: -format json', NATIVE)
        self.assertIn('-q --config -', NATIVE)

    def test_closed_handle_list_and_environment(self):
        self.assertIn('new IntPtr(0x20002)', NATIVE)
        self.assertIn('new IntPtr(3 * IntPtr.Size)', NATIVE)
        self.assertIn('SetHandleInformation(parentIn,1,0)', NATIVE)
        self.assertIn('SetHandleInformation(parentOut,1,0)', NATIVE)
        self.assertIn('SetHandleInformation(parentErr,1,0)', NATIVE)
        self.assertIn('SSLKEYLOGFILE', NATIVE)
        self.assertIn('state.activeProcesses == 0', NATIVE)

    def test_pin_and_cleanup_before_unlock(self):
        self.assertIn(hashlib.sha256((HERE / 'ContainedSession.cs').read_bytes()).hexdigest(), PS)
        self.assertIn('while (-not $Owner.CleanupConfirmed)', PS)
        self.assertLess(LAUNCH.index('Stop-VicaNative $xray'), LAUNCH.index('$lock.Dispose()'))
        self.assertLess(LAUNCH.index('$env:TEMP = $tmp'), LAUNCH.index('Initialize-VaultCrypto'))
        self.assertIn('Get-AuthenticodeSignature -LiteralPath $browserExe', LAUNCH)
        self.assertIn('OSSign (Scheibling Consulting AB)', LAUNCH)

    def test_authenticated_tunneled_fetch_and_exact_hwid(self):
        self.assertLess(REFRESH.index('$document = Read-Vault'), REFRESH.index('Get-VicaTunnelSubscription $Root $document'))
        self.assertNotIn('Get-SubscriptionText ', REFRESH)
        self.assertIn('socks5h://127.0.0.1:17890', PS)
        self.assertIn('INCY/3.0.28', PS)
        self.assertIn("Escape-VicaCurl ([string]$Document.subscription.hwid)", PS)
        self.assertIn("'noproxy = \"\"'", PS)
        self.assertNotIn("'location'", PS)
        self.assertIn("VICA_STATUS:200$", PS)
        self.assertNotIn('F:\\', PS)

    def test_publication_order_and_no_plaintext_fallback(self):
        body = REFRESH.split('function Invoke-VaultRefresh', 1)[1]
        normalize = body.index('$next = $next | ConvertTo-Json')
        validate = body.index('Test-XrayObjectInMemory')
        readonly = body.index('if ($CheckOnly)')
        confirm = body.index("-cne 'UPDATE'")
        publish = body.index('Write-RefreshReplacement')
        self.assertLess(normalize, validate)
        self.assertLess(validate, readonly)
        self.assertLess(readonly, confirm)
        self.assertLess(confirm, publish)
        self.assertIn('[IO.File]::Replace($temp,$Path,$backup)', REFRESH)
        self.assertIn('$stream.Flush($true)', REFRESH)
        self.assertIn('$ExpectedHash', REFRESH)

    def test_selfcheck_gates_menu_in_fresh_process(self):
        self.assertLess(MENU.index("'Test-ContainedSession.ps1'"), MENU.index('while ($true)'))
        self.assertIn("if ($LASTEXITCODE -ne 0) { throw", MENU)
        self.assertIn('Working-Vault-Preview\\WorkingRuntime', MENU)
        self.assertNotIn('Start-Workspace.ps1', MENU)
        fixture = (HERE / 'Test-ContainedSession.ps1').read_text()
        for branch in ['blocked', 'flood', 'curl', 'tree', 'reject', 'hang']:
            self.assertIn("'" + branch + "'", fixture)
        self.assertIn('$supervisor.Kill()', fixture)
        self.assertIn('$descendant.WaitForExit(10000)', fixture)

    def test_archive_closure_source_only_and_manifest(self):
        subprocess.run([sys.executable, str(HERE / 'Build-UpdatedKit.py')], check=True, capture_output=True)
        path = HERE.parents[1] / 'downloads/VIC-A-Updated.zip'
        with zipfile.ZipFile(path) as z:
            names = set(z.namelist())
            self.assertIn('Start.cmd', names)
            self.assertIn('vica/Test-ContainedSession.ps1', names)
            self.assertIn('vault-preview/Vault.Common.ps1', names)
            self.assertIn('Workspace.Common.ps1', names)
            self.assertFalse(any(n.endswith(('.exe','.dll','.vault','.enc')) for n in names))
            self.assertFalse(any('..' in Path(n).parts or n.startswith('/') for n in names))
            for line in z.read('SHA256SUMS.txt').decode().splitlines():
                digest, name = line.split('  ', 1)
                self.assertEqual(hashlib.sha256(z.read(name)).hexdigest(), digest)

    def test_x64_layout_of_redirected_startup(self):
        class Startup(c.Structure):
            _fields_ = [('cb',c.c_int32),('reserved',c.c_void_p),('desktop',c.c_void_p),('title',c.c_void_p)] + [(n,c.c_uint32) for n in ('x','y','xSize','ySize','xChars','yChars','fill','flags')] + [('show',c.c_int16),('reservedSize',c.c_int16),('reservedBytes',c.c_void_p),('stdin',c.c_void_p),('stdout',c.c_void_p),('stderr',c.c_void_p)]
        class StartupEx(c.Structure):
            _fields_ = [('startup',Startup),('attributes',c.c_void_p)]
        self.assertEqual(c.sizeof(Startup),104)
        self.assertEqual(c.sizeof(StartupEx),112)
        self.assertEqual(Startup.stdin.offset,80)
        self.assertEqual(StartupEx.attributes.offset,104)


if __name__ == '__main__':
    unittest.main()
