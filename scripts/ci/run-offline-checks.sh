#!/usr/bin/env bash
# Runs every check that needs no org and prints one line per check, plus the last 30 lines of
# output for each failure. Exit status is non-zero if any check failed.
#
#   bash scripts/ci/run-offline-checks.sh [--fast] [--allow-adr-next] [--analyzer]
#
#   --fast            skip Jest and Code Analyzer
#   --allow-adr-next  a check-adrs.py failure caused only by unnumbered ADR-NEXT files passes
#   --analyzer        also run Code Analyzer on files changed against origin/main
#                     (--severity-threshold 2); slow, so off by default

set -u

FAST=0
ALLOW_NEXT=0
ANALYZER=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    --allow-adr-next) ALLOW_NEXT=1 ;;
    --analyzer) ANALYZER=1 ;;
    -h | --help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (use --fast, --allow-adr-next, --analyzer)" >&2
      exit 2
      ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Run this from inside the BarnCRM repository." >&2
  exit 2
}
cd "$ROOT" || exit 2

if [ ! -d node_modules ]; then
  echo "node_modules is missing. Run: npm ci" >&2
  exit 2
fi

OUT=$(mktemp -d "${TMPDIR:-/tmp}/offline-checks.XXXXXX")
trap 'rm -rf "$OUT"' EXIT

FAILED=0
COUNT=0

# record NAME STATUS LOGFILE: print one line, and the log tail for a failure.
record() {
  if [ "$2" -eq 0 ]; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    tail -n 30 "$3" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi
}

# run NAME COMMAND...: run one check with its output sent to a temp file.
run() {
  name=$1
  shift
  COUNT=$((COUNT + 1))
  log="$OUT/$COUNT.log"
  "$@" >"$log" 2>&1
  record "$name" $? "$log"
}

# check-adrs.py fails by design while a branch holds unnumbered ADR-NEXT files. With
# --allow-adr-next, it passes when every problem it printed is one of those.
run_adrs() {
  COUNT=$((COUNT + 1))
  log="$OUT/$COUNT.log"
  python3 scripts/ci/check-adrs.py >"$log" 2>&1
  status=$?
  if [ "$status" -ne 0 ] && [ "$ALLOW_NEXT" -eq 1 ]; then
    others=$(grep -v -e 'still an ADR-NEXT placeholder' -e 'cites ADR-NEXT, which was never' \
      -e '^check-adrs.py: FAILED, ' -e '^NEXT-.* is not listed in the index' "$log" | grep -c . || true)
    if [ "$others" -eq 0 ]; then
      status=0
    fi
  fi
  record "scripts/ci/check-adrs.py" "$status" "$log"
}

no_em_dashes() {
  hits=$(git grep -n -I $'\xe2\x80\x94' -- . ':!package-lock.json')
  status=$?
  if [ "$status" -eq 0 ]; then
    echo "$hits"
    echo "Em dash characters found in tracked files."
    return 1
  fi
  [ "$status" -eq 1 ]
}

for f in scripts/ci/*.py; do
  if [ "$(basename "$f")" = "check-adrs.py" ]; then
    run_adrs
  else
    run "$f" python3 "$f"
  fi
done
for f in scripts/ci/check-*.sh; do
  [ "$(basename "$f")" = "check-apex-offline.sh" ] && continue
  run "$f" bash "$f"
done
run "scripts/ci/check-apex-offline.sh" bash scripts/ci/check-apex-offline.sh
[ -f scripts/ci/check-openapi.js ] && run "scripts/ci/check-openapi.js" node scripts/ci/check-openapi.js
[ -d scripts/migration/tests ] && run "migration kit tests" python3 -m unittest discover -s scripts/migration/tests
[ -d scripts/data/tests ] && run "scale data generator tests" python3 -m unittest discover -s scripts/data/tests
run "em dash characters" no_em_dashes
run "npm run lint" npm run lint
run "npm run prettier:verify" npm run prettier:verify
if grep -q '"lint:slds"' package.json; then
  run "npm run lint:slds" npm run lint:slds
fi

if [ "$FAST" -eq 0 ]; then
  run "sfdx-lwc-jest" npx sfdx-lwc-jest --silent
fi

if [ "$ANALYZER" -eq 1 ] && [ "$FAST" -eq 0 ]; then
  if ! command -v sf >/dev/null 2>&1; then
    COUNT=$((COUNT + 1))
    echo "sf: command not found" >"$OUT/$COUNT.log"
    record "code-analyzer" 1 "$OUT/$COUNT.log"
  else
    set --
    for f in $(git diff --name-only --diff-filter=d origin/main -- packages | grep -E '\.(cls|trigger|js)$'); do
      set -- "$@" --target "$f"
    done
    if [ "$#" -eq 0 ]; then
      echo "PASS code-analyzer (no changed Apex or JS)"
    else
      run "code-analyzer (changed files)" sf code-analyzer run --workspace packages \
        --rule-selector Recommended --severity-threshold 2 "$@"
    fi
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "All $COUNT offline checks passed."
  exit 0
fi
echo "$FAILED of $COUNT offline checks failed."
exit 1
