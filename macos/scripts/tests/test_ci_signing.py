import base64
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "ci-signing.py"


class SigningCredentialsTests(unittest.TestCase):
    def run_helper(self, fail=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shim = root / "bin"
            shim.mkdir()
            security = shim / "security"
            security.write_text('''#!/usr/bin/env python3
import os, sys
assert os.environ['P12_PASSWORD'] not in sys.argv
assert os.environ['NOTARY_PASSWORD'] not in sys.argv
if sys.argv[1:] == ['-i']:
    assert sys.stdin.readline().startswith('"')
elif 'find-identity' in sys.argv:
    print('1) ABC "Developer ID Application: Test Team (1234567890)"')
elif 'list-keychains' in sys.argv and '-s' not in sys.argv:
    print('"/tmp/login.keychain-db"')
''')
            xcrun = shim / "xcrun"
            xcrun.write_text('''#!/usr/bin/env python3
import getpass, os, sys
assert '--password' not in sys.argv
assert os.environ['NOTARY_PASSWORD'] not in sys.argv
assert sys.stdin.isatty()
password = getpass.getpass('App-specific password: ')
assert password == os.environ['NOTARY_PASSWORD']
if os.environ.get('SIMULATE_FAILURE'):
    print('Rejected ' + password)
    sys.exit(1)
print('Credentials validated and saved.')
''')
            for binary in [security, xcrun]:
                binary.chmod(0o700)
            env = dict(os.environ, PATH=str(shim) + os.pathsep + os.environ['PATH'],
                       RUNNER_TEMP=str(root), GITHUB_OUTPUT=str(root / "output"),
                       P12_BASE64=base64.b64encode(b"test certificate").decode(),
                       P12_PASSWORD="test-export-password", TEAM_ID="1234567890",
                       NOTARY_APPLE_ID="test@example.invalid",
                       NOTARY_PASSWORD="abcd-efgh-ijkl-mnop")
            if fail:
                env['SIMULATE_FAILURE'] = '1'
            result = subprocess.run(['python3', str(SCRIPT)], env=env,
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            for name in ['P12_PASSWORD', 'NOTARY_PASSWORD', 'P12_BASE64']:
                self.assertNotIn(env[name], output)
            self.assertFalse((root / "developer-id.p12").exists())
            return result, (root / "output").read_text() if (root / "output").exists() else ''

    def test_passwords_use_stdin_and_tty_and_outputs_are_written(self):
        result, output = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('identity=Developer ID Application: Test Team (1234567890)', output)
        self.assertIn('keychain=', output)

    def test_rejected_credentials_are_redacted_and_do_not_write_outputs(self):
        result, output = self.run_helper(fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('[REDACTED]', result.stdout)
        self.assertEqual(output, '')


if __name__ == '__main__':
    unittest.main()
