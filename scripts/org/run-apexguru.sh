#!/usr/bin/env bash
# run-apexguru.sh <org-alias> [report-dir]
#
# Runs the Code Analyzer ApexGuru engine against the Apex under packages/ and writes an HTML
# and a JSON report. ApexGuru is Salesforce's hosted analysis: the Apex files are zipped and
# sent to a Salesforce service, authenticated with the named org's CLI login, so this needs a
# logged-in org and cannot run in continuous integration. It is an optional, manual step.
#
# Report only: exit 0 when the scan ran, whatever it found. Exit 1 when it could not run
# (bad arguments, no CLI, org not logged in, or the engine skipped itself).

set -uo pipefail

ALIAS="${1:-}"
OUT_DIR="${2:-apexguru-results}"
if [ -z "$ALIAS" ]; then
  echo "Usage: $0 <org-alias> [report-dir]" >&2
  exit 1
fi
command -v sf >/dev/null || { echo "Salesforce CLI (sf) not found." >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$OUT_DIR"

# Fail early with a clear message instead of letting the engine skip itself quietly.
if ! sf org display --target-org "$ALIAS" >/dev/null 2>&1; then
  echo "Org '$ALIAS' is not logged in. Run: sf org login web --alias $ALIAS" >&2
  exit 1
fi

cd "$ROOT" || exit 1
LOG="$OUT_DIR/apexguru-run.log"
sf code-analyzer run \
  --config-file config/code-analyzer-apexguru.yml \
  --workspace packages \
  --rule-selector apexguru \
  --target-org "$ALIAS" \
  --output-file "$OUT_DIR/apexguru-results.html" \
  --output-file "$OUT_DIR/apexguru-results.json" 2>&1 | tee "$LOG"
RC=${PIPESTATUS[0]}

# The engine reports a skipped scan (expired session, no connection) as a warning, not a
# failure, so a green exit alone does not prove the scan ran.
if grep -qiE "skipped ApexGuru|NO_ORG_CONNECTION|INVALID_SESSION" "$LOG"; then
  echo "ApexGuru was skipped. See $LOG." >&2
  exit 1
fi
[ "$RC" -le 1 ] || exit 1
echo "Reports written to $OUT_DIR (apexguru-results.html and .json)."
