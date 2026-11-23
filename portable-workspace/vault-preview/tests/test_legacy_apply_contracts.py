"""Source contracts only; not Windows/provider execution tests."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).parents[1] / 'Compare-LegacySubscription.ps1').read_text()


class LegacyApplyContracts(unittest.TestCase):
    def test_opt_in_and_confirmation(self):
        self.assertIn('[switch]$Apply', SOURCE)
        self.assertIn('if ($Apply) {', SOURCE)
        self.assertIn("-cne 'APPLY'", SOURCE)
        self.assertLess(SOURCE.index("-cne 'APPLY'"), SOURCE.index('Write-RefreshReplacement'))

    def test_validated_and_stopped_before_publication(self):
        start = SOURCE.index("$phase = 'stop-fetch-children'")
        validate = SOURCE.index('Test-XrayObjectInMemory $exe $next.activeConfig')
        publish = SOURCE.index('Write-RefreshReplacement')
        self.assertLess(start, validate)
        self.assertLess(validate, publish)
        self.assertIn('Write-RefreshReplacement $vaultPath $next $password $before', SOURCE)

    def test_preserve_old_identity_and_request(self):
        self.assertIn("$next.subscription.hwid = $params['hwid']", SOURCE)
        self.assertIn('$response = $curl.Fetch($requestBytes)', SOURCE)
        self.assertIn("$hwid = [string]$params['hwid']", SOURCE)
        self.assertNotIn('Invoke-VaultRefresh ', SOURCE)


if __name__ == '__main__':
    unittest.main()
