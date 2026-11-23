"""Static job lifecycle contracts, not a Windows Job Object execution test."""
from pathlib import Path
import hashlib
import unittest

ROOT = Path(__file__).resolve().parents[2]
CS = (ROOT / 'WorkspaceJob.cs').read_text()
JOB = (ROOT / 'Workspace.Job.ps1').read_text()
LAUNCH = (ROOT / 'Start-Workspace.ps1').read_text()


class WorkspaceJobContracts(unittest.TestCase):
    def test_assign_before_resume_without_breakaway(self):
        start = CS.split('public static OwnedXray Start', 1)[1]
        self.assertLess(start.index('AssignProcessToJobObject(owner.job'), start.index('ResumeThread(pi.thread)'))
        self.assertIn('0x08000004', start)
        self.assertIn('limits.basic.flags = 0x2000', start)
        self.assertIn('IntPtr.Zero, IntPtr.Zero, false,', start)

    def test_job_tree_accounting_and_retained_lock(self):
        self.assertIn('state.activeProcesses == 0', CS)
        self.assertIn('TerminateJobObject(job, 1)', CS)
        self.assertIn('while (-not $Owner.CleanupConfirmed)', JOB)
        self.assertLess(LAUNCH.index('Stop-OwnedWorkspaceXray $xray'), LAUNCH.index('$lock.Dispose()'))
        self.assertNotIn('Stop-Process -Id $xray.Id', LAUNCH)

    def test_pin_and_ssd_compilation(self):
        self.assertIn(hashlib.sha256((ROOT / 'WorkspaceJob.cs').read_bytes()).hexdigest(), JOB)
        self.assertLess(LAUNCH.index('$env:TEMP = $tmp'), LAUNCH.index('Test-OwnedWorkspaceConfig $exe'))
        self.assertIn('Stop-OwnedWorkspaceXray $validation', JOB)
        self.assertIn('Start-OwnedWorkspaceXray $Exe $Config (Split-Path -Parent $Exe) -ValidateOnly', JOB)

    def test_browser_outside_job_and_failure_window(self):
        self.assertIn('$browserLaunchAttempted = $true', LAUNCH)
        self.assertIn('if ($browserLaunchAttempted)', LAUNCH)
        self.assertIn('$browser = Start-Process', LAUNCH)
        console = (ROOT / 'Workspace-Console.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("Join-Path $homeDir 'Start-SessionWindow.ps1'", console)
        entry = (ROOT / 'Start-SessionWindow.ps1').read_text()
        self.assertIn("Read-Host 'Press Enter to close this session window'", entry)


if __name__ == '__main__':
    unittest.main()
