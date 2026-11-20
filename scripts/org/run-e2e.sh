#!/usr/bin/env bash
# run-e2e.sh <org alias> [extra Playwright arguments]
#
# Runs the Playwright browser smoke tests (e2e/, plan Q3) against an org the sf CLI knows by
# alias, for example `bash scripts/org/run-e2e.sh barn-sales`. Local only: CI never runs it.
# Prints a summary and the failures; the full results are in e2e-results/results.json and a
# screenshot of each failure is under e2e-results/artifacts/. See docs/contributor-guide/e2e.md.
#
# Sign-in uses a front-door URL from `sf org open --url-only`, read inside the test runner and
# never printed. Point it only at a scratch or test org you are allowed to open pages in.

set -euo pipefail

ALIAS="${1:-}"
if [[ -z "$ALIAS" || "$ALIAS" == -* ]]; then
  echo "Usage: bash scripts/org/run-e2e.sh <org alias> [Playwright arguments]" >&2
  exit 2
fi
shift

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ ! -x node_modules/.bin/playwright ]]; then
  echo "Playwright is not installed: run npm install first." >&2
  exit 2
fi

mkdir -p e2e-results
LOG="e2e-results/run.log"
START=$(date +%s)
set +e
E2E_ORG="$ALIAS" node_modules/.bin/playwright test "$@" >"$LOG" 2>&1
STATUS=$?
set -e
SECONDS_TAKEN=$(($(date +%s) - START))

if [[ ! -f e2e-results/results.json ]]; then
  # Global setup failed before any test ran; its message is in the log (with no URL in it).
  tail -20 "$LOG"
  exit "$STATUS"
fi

python3 - "$ALIAS" "$SECONDS_TAKEN" <<'PY'
import json
import re
import sys

alias, seconds = sys.argv[1], int(sys.argv[2])
data = json.load(open("e2e-results/results.json"))
counts = {"passed": 0, "failed": 0, "skipped": 0, "flaky": 0}
failures, skips, notes = [], {}, []


def walk(suite, path):
    for spec in suite.get("specs", []):
        name = " > ".join(path + [spec["title"]])
        for test in spec["tests"]:
            results = test.get("results", [])
            outcome = test.get("status")  # expected, unexpected, skipped, flaky
            if outcome == "skipped":
                counts["skipped"] += 1
                reason = next((a.get("description", "") for a in test.get("annotations", [])
                               if a.get("type") == "skip"), "")
                skips[reason] = skips.get(reason, 0) + 1
            elif outcome == "unexpected":
                counts["failed"] += 1
                error = results[-1].get("error", {}) if results else {}
                message = re.sub(r"\x1b\[[0-9;]*m", "", error.get("message") or "").strip().splitlines()
                failures.append((name, [line for line in message if line.strip()][:8]))
            elif outcome == "flaky":
                counts["flaky"] += 1
            else:
                counts["passed"] += 1
            for a in test.get("annotations", []):
                if a.get("type") == "console":
                    notes.append((name, a.get("description", "")))
    for child in suite.get("suites", []):
        walk(child, path + [child["title"]] if child.get("title") and not child["title"].endswith(".js") else path)


for suite in data.get("suites", []):
    walk(suite, [suite["title"]])

for error in data.get("errors", []):
    failures.append(("(run)", [(error.get("message") or "").splitlines()[0]]))

print(f"E2E on {alias}: {counts['passed']} passed, {counts['failed']} failed, "
      f"{counts['skipped']} skipped, {counts['flaky']} flaky in {seconds // 60}m {seconds % 60}s")
if skips:
    print("Skipped:")
    for reason, n in sorted(skips.items(), key=lambda item: -item[1]):
        print(f"  {n} x {reason}")
if notes:
    print("Other console errors (not failed; check they are platform noise):")
    for name, text in notes:
        print(f"  {name}: {text[:300]}")
if failures:
    print("Failures:")
    for name, lines in failures:
        print(f"  {name}")
        for line in lines:
            print(f"      {line[:300]}")
PY

exit "$STATUS"
