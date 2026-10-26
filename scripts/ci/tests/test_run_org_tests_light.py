import os
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "..", "org", "run-org-tests.sh")


class LightGateAllowList(unittest.TestCase):
    def test_selfcheck_passes(self):
        # No org and no GitHub: the script feeds sample paths to its own allow-list.
        result = subprocess.run(
            ["bash", SCRIPT, "--light-selfcheck"], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("light-selfcheck: ok", result.stdout)

    def test_unknown_flag_is_a_usage_error(self):
        result = subprocess.run(
            ["bash", SCRIPT, "some-alias", "--bogus"], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("--light", result.stderr)


if __name__ == "__main__":
    unittest.main()
