"""Cleanup verdict of scripts/org/scale-test-tier1.sh, run against a fake `sf` (no org).

The fake CLI prints an update warning on stderr, as sf 2.153.5 does, and behaves per scenario:
  RESULTS_MODE  ok      `bulk results` returns JSON (a warning line may precede it on stdout)
                warn    same, with the warning on stdout before the JSON
                fail    `bulk results` exits 1 with no JSON
  FAKE_JOB_STATE state of the delete job
  LEAVE         1 = records remain after the delete (counts stay at 5)
"""

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "org" / "scale-test-tier1.sh"

FAKE_SF = r"""#!/usr/bin/env bash
echo " ›   Warning: @salesforce/cli update available from 2.153.5 to 2.154.4." >&2
state="$FAKE_DIR/deleted"
args="$*"
case "$args" in
  "data export bulk"*)
    out=""
    while [[ $# -gt 0 ]]; do [[ "$1" == "--output-file" ]] && out="$2"; shift; done
    if [[ -f "$state" ]]; then printf 'Id\n' >"$out"; else printf 'Id\na001\na002\n' >"$out"; fi
    echo '{"status":0,"result":{}}'
    ;;
  "data delete bulk"*)
    [[ "${LEAVE:-0}" == "1" ]] || touch "$state"
    echo '{"status":0,"result":{"jobInfo":{"id":"750TEST","state":"'"${FAKE_JOB_STATE:-JobComplete}"'"}}}'
    ;;
  "data bulk results"*)
    case "$RESULTS_MODE" in
      fail) echo "boom" >&2; exit 1 ;;
      warn) echo " ›   Warning: @salesforce/cli update available." ;;
    esac
    echo '{"status":0,"result":{"processedRecords":2,"successfulRecords":2,"failedRecords":0}}'
    ;;
  "data query"*)
    if [[ "$args" == *Accounting_Code__c* ]]; then echo '{"result":{"records":[]}}'
    elif [[ -f "$state" ]]; then echo '{"result":{"totalSize":0}}'
    else echo '{"result":{"totalSize":5}}'; fi
    ;;
  *) echo '{"result":[]}' ;;
esac
"""


@unittest.skipUnless(shutil.which("jq") and shutil.which("bash"), "needs jq and bash")
class CleanupVerdictTest(unittest.TestCase):
    def run_cleanup(self, results_mode="ok", job_state="JobComplete", leave="0"):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        bindir = Path(tmp) / "bin"
        bindir.mkdir()
        sf = bindir / "sf"
        sf.write_text(FAKE_SF)
        sf.chmod(sf.stat().st_mode | stat.S_IEXEC)
        env = dict(
            os.environ,
            PATH="%s:%s" % (bindir, os.environ["PATH"]),
            FAKE_DIR=tmp,
            SCALE_TEST_DIR=str(Path(tmp) / "out"),
            SCALE_TEST_SOFT_DELETE="1",
            RESULTS_MODE=results_mode,
            FAKE_JOB_STATE=job_state,
            LEAVE=leave,
        )
        proc = subprocess.run(
            ["bash", str(SCRIPT), "cleanup", "oi-test"],
            env=env, capture_output=True, text=True, timeout=120,
        )
        return proc.returncode, proc.stdout

    def test_results_read_and_all_gone_succeeds(self):
        code, out = self.run_cleanup("ok")
        self.assertEqual(code, 0, out)
        self.assertIn("rows processed: 2, succeeded: 2, failed: 0", out)

    def test_warning_on_stdout_before_json_is_tolerated(self):
        code, out = self.run_cleanup("warn")
        self.assertEqual(code, 0, out)
        self.assertNotIn("could not read the job results", out)

    def test_unreadable_results_on_completed_job_trusts_zero_counts(self):
        code, out = self.run_cleanup("fail")
        self.assertEqual(code, 0, out)
        self.assertIn("could not read the job results", out)
        self.assertNotIn("CLEANUP INCOMPLETE", out)

    def test_unreadable_results_but_records_remain_fails(self):
        code, out = self.run_cleanup("fail", leave="1")
        self.assertEqual(code, 1, out)
        self.assertIn("CLEANUP INCOMPLETE", out)

    def test_failed_job_state_with_unreadable_results_fails(self):
        code, out = self.run_cleanup("fail", job_state="Failed")
        self.assertEqual(code, 1, out)
        self.assertIn("NOTHING OR NOT EVERYTHING WAS DELETED", out)


if __name__ == "__main__":
    unittest.main()
