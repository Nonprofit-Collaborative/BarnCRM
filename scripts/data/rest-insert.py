#!/usr/bin/env python3
"""rest-insert.py

Inserts a CSV through the REST sObject Collections API with the duplicate rule header
`Sforce-Duplicate-Rule-Header: allowSave=true`. Python 3 standard library plus the `sf` CLI.

Why: the org's standard Account and Contact duplicate rules alert on insert, and an alert
refuses an API insert unless the caller sends that header. Bulk API 2.0 cannot send it, so the
scale test (scripts/org/scale-test-tier1.sh) loads households and contacts here and every
other object through Bulk API 2.0. The product's duplicate handling is not touched; only the
test load is allowed to save through the rules.

    python3 scripts/data/rest-insert.py --sobject Account --file IN.csv --org ALIAS \\
            --out-dir DIR [--label NAME] [--api-version 67.0] [--chunk 200]

Empty cells are left out of the record (a blank column is no value). Writes
DIR/<label>-success-records.csv (sf__Id plus the row) and DIR/<label>-failed-records.csv
(sf__Error and sf__StatusCode plus the row), the same shape as `sf data bulk results`, and
prints one JSON line: {"processed": N, "succeeded": N, "failed": N, "errors": {code: n}}.
Exit status is 0 when the load ran (rows may still have failed: read the JSON), 2 when a call
could not be made or read. The CLI is `$SF_BIN` (default sf).
"""

import argparse
import collections
import csv
import json
import os
import subprocess
import sys
from pathlib import Path

HEADER = "Sforce-Duplicate-Rule-Header: allowSave=true"


def json_from(text):
    """The JSON object in CLI output, ignoring any warning text printed before it."""
    start = text.find("{")
    start_list = text.find("[")
    candidates = [i for i in (start, start_list) if i >= 0]
    if not candidates:
        raise ValueError("no JSON in the response: %s" % text[:300])
    return json.loads(text[min(candidates):])


def post_chunk(sf, org, version, sobject, rows):
    """One collections call; returns the per-record results, in row order."""
    records = []
    for row in rows:
        record = {"attributes": {"type": sobject}}
        record.update({k: v for k, v in row.items() if v != ""})
        records.append(record)
    body = json.dumps({"allOrNone": False, "records": records})
    proc = subprocess.run(
        [sf, "api", "request", "rest", "services/data/v%s/composite/sobjects" % version,
         "--method", "POST", "--header", HEADER, "--header", "Content-Type: application/json",
         "--body", "-", "--target-org", org],
        input=body, capture_output=True, text=True,
    )
    if proc.returncode != 0 and not proc.stdout.strip():
        raise RuntimeError("sf api request rest failed: %s" % proc.stderr.strip()[:400])
    results = json_from(proc.stdout)
    if not isinstance(results, list) or len(results) != len(rows):
        raise RuntimeError("unexpected response: %s" % proc.stdout[:400])
    return results


def error_of(result):
    errors = result.get("errors") or [{}]
    code = errors[0].get("statusCode") or "UNKNOWN"
    message = "; ".join(
        "%s:%s" % (e.get("statusCode", ""), e.get("message", "")) for e in errors
    )
    return code, message


def insert_file(sf, org, version, sobject, path, out_dir, label, chunk=200):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        header = list(reader.fieldnames or [])
        rows = list(reader)
    succeeded = failed = 0
    errors = collections.Counter()
    ok_path = out / ("%s-success-records.csv" % label)
    bad_path = out / ("%s-failed-records.csv" % label)
    with open(ok_path, "w", newline="", encoding="utf-8") as ok, open(
        bad_path, "w", newline="", encoding="utf-8"
    ) as bad:
        ok_writer = csv.writer(ok, lineterminator="\n")
        bad_writer = csv.writer(bad, lineterminator="\n")
        ok_writer.writerow(["sf__Id"] + header)
        bad_writer.writerow(["sf__Error", "sf__StatusCode"] + header)
        for i in range(0, len(rows), chunk):
            batch = rows[i:i + chunk]
            for row, result in zip(batch, post_chunk(sf, org, version, sobject, batch)):
                values = [row[h] for h in header]
                if result.get("success"):
                    succeeded += 1
                    ok_writer.writerow([result.get("id", "")] + values)
                else:
                    failed += 1
                    code, message = error_of(result)
                    errors[code] += 1
                    bad_writer.writerow([message, code] + values)
    return {"processed": len(rows), "succeeded": succeeded, "failed": failed,
            "errors": dict(errors), "success_file": str(ok_path), "failed_file": str(bad_path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--sobject", required=True)
    parser.add_argument("--file", required=True)
    parser.add_argument("--org", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--label", default=None)
    parser.add_argument("--api-version", default="67.0")
    parser.add_argument("--chunk", type=int, default=200)
    args = parser.parse_args()
    if not 1 <= args.chunk <= 200:
        parser.error("--chunk must be 1 to 200 (the Collections API limit)")
    try:
        summary = insert_file(
            os.environ.get("SF_BIN", "sf"), args.org, args.api_version, args.sobject,
            args.file, args.out_dir, args.label or args.sobject.lower(), args.chunk,
        )
    except (RuntimeError, ValueError, OSError) as err:
        print(json.dumps({"error": str(err)}))
        return 2
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
