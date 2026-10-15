"""Unit tests for scripts/data/rest-insert.py against a fake `sf` (no org).

The fake CLI records its arguments and request body, then answers a Collections call: a row
whose FirstName is "Dupe" is refused with DUPLICATES_DETECTED, the rest succeed.
"""

import csv
import importlib.util
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "rest-insert.py"
spec = importlib.util.spec_from_file_location("rest_insert", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

FAKE_SF = r"""#!/usr/bin/env python3
import json, os, sys
log = os.environ["FAKE_LOG"]
body = json.load(sys.stdin)
with open(log, "a") as handle:
    handle.write(json.dumps({"argv": sys.argv[1:], "body": body}) + "\n")
print(" ›   Warning: @salesforce/cli update available.", file=sys.stderr)
out = []
for i, rec in enumerate(body["records"]):
    if rec.get("FirstName") == "Dupe":
        out.append({"success": False, "errors": [{"statusCode": "DUPLICATES_DETECTED",
                    "message": "Use one of these records?", "fields": []}]})
    else:
        out.append({"id": "003%012d" % i, "success": True, "errors": []})
print(json.dumps(out))
"""


class RestInsertTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.dir = Path(self.tmp)
        sf = self.dir / "sf"
        sf.write_text(FAKE_SF)
        sf.chmod(sf.stat().st_mode | stat.S_IEXEC)
        self.log = self.dir / "calls.jsonl"
        os.environ["FAKE_LOG"] = str(self.log)

    def write_rows(self, rows):
        path = self.dir / "in.csv"
        with open(path, "w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(["Sample_Data_Key__c", "FirstName", "LastName", "Phone"])
            writer.writerows(rows)
        return path

    def run_insert(self, rows, chunk=200):
        return mod.insert_file(
            str(self.dir / "sf"), "oi-test", "67.0", "Contact", self.write_rows(rows),
            self.dir / "out", "contacts", chunk,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_sends_allow_save_header_and_blank_cells_are_omitted(self):
        self.run_insert([["SCALE-C-1", "Ann", "Ash", ""]])
        call = self.calls()[0]
        argv = call["argv"]
        self.assertIn("Sforce-Duplicate-Rule-Header: allowSave=true", argv)
        self.assertIn("services/data/v67.0/composite/sobjects", argv)
        self.assertFalse(call["body"]["allOrNone"])
        record = call["body"]["records"][0]
        self.assertEqual(record["attributes"], {"type": "Contact"})
        self.assertNotIn("Phone", record)

    def test_chunks_and_counts(self):
        rows = [["SCALE-C-%d" % i, "Ann", "Ash%d" % i, "555"] for i in range(450)]
        summary = self.run_insert(rows, chunk=200)
        self.assertEqual(len(self.calls()), 3)
        self.assertEqual((summary["processed"], summary["succeeded"], summary["failed"]), (450, 450, 0))

    def test_failed_rows_are_kept_with_their_code(self):
        summary = self.run_insert([
            ["SCALE-C-1", "Ann", "Ash", "1"],
            ["SCALE-C-2", "Dupe", "Ash", "2"],
            ["SCALE-C-3", "Dupe", "Oak", "3"],
        ])
        self.assertEqual(summary["failed"], 2)
        self.assertEqual(summary["errors"], {"DUPLICATES_DETECTED": 2})
        with open(summary["failed_file"], newline="", encoding="utf-8") as handle:
            failed = list(csv.DictReader(handle))
        self.assertEqual([r["Sample_Data_Key__c"] for r in failed], ["SCALE-C-2", "SCALE-C-3"])
        self.assertEqual(failed[0]["sf__StatusCode"], "DUPLICATES_DETECTED")
        with open(summary["success_file"], newline="", encoding="utf-8") as handle:
            ok = list(csv.DictReader(handle))
        self.assertEqual([r["Sample_Data_Key__c"] for r in ok], ["SCALE-C-1"])
        self.assertTrue(ok[0]["sf__Id"].startswith("003"))

    def test_unreadable_response_raises(self):
        bad = self.dir / "badsf"
        bad.write_text("#!/usr/bin/env bash\ncat >/dev/null\necho 'not json'\n")
        bad.chmod(bad.stat().st_mode | stat.S_IEXEC)
        with self.assertRaises(ValueError):
            mod.insert_file(str(bad), "oi-test", "67.0", "Contact",
                            self.write_rows([["SCALE-C-1", "Ann", "Ash", ""]]),
                            self.dir / "out", "contacts")


if __name__ == "__main__":
    unittest.main()
