#!/usr/bin/env bash
# release-gate.sh [--analyzer-only] [--multi-currency <alias>]
#
# The version end-to-end run (plan D-142, widened by D-200 QA review Q2 and Q6), in one command,
# from the pushed HEAD of a landing batch whose versions are done:
#
#   1. Code Analyzer with the AppExchange selector and the Graph Engine (sfge) over every package,
#      as the security review runs it. No org is needed; it fails on any finding of severity 2
#      (High) or worse. The Graph Engine needs Java 11 or later on PATH.
#   2. run-org-tests.sh <alias> --release on every org in RELEASE_ORGS, in parallel, each from its
#      own detached worktree at HEAD and under its own lock, so two runs never share a
#      test-results folder or an org. The default covers every org shape BarnCRM supports:
#        barn-sales     Sales Cloud shape, contacts only
#        oi-test        Person Accounts
#        barn-platform  Platform-only (ADR-0013: Core must run there)
#        barn-npsp      NPSP installed (scripts/org/install-npsp.sh, config/scratch-defs/npsp.json)
#   3. With --multi-currency <alias>, the same release run on a multi-currency org
#      (config/scratch-defs/multi-currency.json), once per version.
#
# This script never creates an org. An alias that is not authenticated on this machine stops the
# run before anything deploys; set RELEASE_ORGS to the orgs that exist (for example while
# barn-npsp waits for its approval) and say which shape was left out in the release notes.
# Creating barn-npsp or a multi-currency scratch org needs Brandon's approval first.
#
# Exit codes: 0 when the analyzer and every org passed; 1 otherwise. Each org's own log is in
# test-results/release-gate/<alias>.log, and each run posts its own "Org tests (local)" status.

set -euo pipefail

RELEASE_ORGS="${RELEASE_ORGS:-barn-sales oi-test barn-platform barn-npsp}"
ANALYZER_ONLY=0
MULTI_CURRENCY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --analyzer-only) ANALYZER_ONLY=1 ;;
    --multi-currency)
      shift
      MULTI_CURRENCY="${1:-}"
      ;;
    *)
      echo "Usage: release-gate.sh [--analyzer-only] [--multi-currency <alias>]" >&2
      exit 2
      ;;
  esac
  shift
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "release-gate.sh: the working tree has uncommitted changes; the gate tests HEAD only." >&2
  exit 1
fi
SHA="$(git rev-parse HEAD)"
OUT="$REPO_ROOT/test-results/release-gate"
mkdir -p "$OUT"

echo "== Code Analyzer: AppExchange selector and Graph Engine, every package"
if ! sf code-analyzer run --workspace packages \
  --rule-selector AppExchange --rule-selector sfge \
  --severity-threshold 2 \
  --output-file "$OUT/code-analyzer.html" --output-file "$OUT/code-analyzer.json"; then
  echo "release-gate.sh: Code Analyzer found High or Critical issues; see $OUT/code-analyzer.html" >&2
  exit 1
fi
[[ "$ANALYZER_ONLY" -eq 1 ]] && exit 0

ORGS=($RELEASE_ORGS)
[[ -n "$MULTI_CURRENCY" ]] && ORGS+=("$MULTI_CURRENCY")

# Local auth only (no call to the org): stop before any deploy when an org is missing.
KNOWN="$(sf org list --json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin).get("result", {})
names = set()
for group in data.values():
    for org in group if isinstance(group, list) else []:
        names.add(org.get("alias") or "")
        names.add(org.get("username") or "")
print(" ".join(sorted(n for n in names if n)))
')"
for alias in "${ORGS[@]}"; do
  if [[ " $KNOWN " != *" $alias "* ]]; then
    echo "release-gate.sh: no authenticated org '$alias'. Set RELEASE_ORGS to the orgs that exist;" >&2
    echo "creating a new org needs Brandon's approval." >&2
    exit 1
  fi
done

# Parallel arrays, not an associative array: macOS ships bash 3.2.
PIDS=()
for alias in "${ORGS[@]}"; do
  lock="${TMPDIR:-/tmp}/barncrm-org-lock-$alias"
  if ! mkdir "$lock" 2>/dev/null; then
    echo "release-gate.sh: $alias is locked by another run ($lock); wait for it or remove the lock." >&2
    exit 1
  fi
  tree="${TMPDIR:-/tmp}/barncrm-release-$alias-${SHA:0:9}"
  git worktree add --detach --force "$tree" "$SHA" >/dev/null
  (
    # Keep the run's results (org-tests.json, coverage.tsv) before the worktree goes.
    trap 'cp -R "$tree/test-results" "$OUT/$alias-results" 2>/dev/null; rmdir "$lock";
      git -C "$REPO_ROOT" worktree remove --force "$tree"' EXIT
    cd "$tree" && bash scripts/org/run-org-tests.sh "$alias" --release
  ) >"$OUT/$alias.log" 2>&1 &
  PIDS+=($!)
  echo "== $alias: release run started (log: $OUT/$alias.log)"
done

FAILED=0
for i in "${!ORGS[@]}"; do
  alias="${ORGS[$i]}"
  if wait "${PIDS[$i]}"; then
    echo "PASS $alias"
  else
    echo "FAIL $alias (see $OUT/$alias.log)"
    FAILED=1
  fi
done
exit "$FAILED"
