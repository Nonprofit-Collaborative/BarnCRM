#!/usr/bin/env bash
# run-org-tests.sh <org alias>
#
# The merge gate for main. Deploys the commit you have checked out to an org, runs every
# Apex test class in that commit's source there, and posts the result to GitHub as the commit status
# "Org tests (local)" on that exact commit. The main branch ruleset requires that status,
# so a pull request that changes deployable source cannot merge until this has passed on
# its head commit. See docs/contributor-guide/ci.md, "The org test gate".
#
# WHY A LOCAL RUN POSTS THE STATUS. Org tests used to run in GitHub Actions on every push
# to main, against one shared org. They now run from a contributor's machine against an
# org the contributor controls, which is faster to iterate on and costs no CI minutes. A
# local run proves nothing to a reviewer unless it leaves a record, and a record is only
# worth trusting if it names the commit that was tested. A commit status is exactly that:
# it belongs to one SHA, so a later push has no status until someone runs this again.
#
# WHY IT REFUSES A DIRTY TREE. The status is posted on HEAD. If the working tree held
# changes, the code deployed and tested would not be the code at HEAD, and the status
# would vouch for a commit that was never run. The same goes for an unpushed commit, which
# GitHub cannot attach a status to anyway, so that is checked before the long part starts
# rather than after it.
#
# Exit codes: 0 = every test passed and the success status was posted; 1 = failure status
# posted or a precondition failed; 3 = the sf CLI crashed, no status posted, rerun.

set -euo pipefail

ALIAS="${1:-}"
if [[ -z "$ALIAS" ]]; then
  echo "Usage: run-org-tests.sh <org alias>" >&2
  exit 2
fi

# The sf CLI runs out of memory reading about 2,200 test results (a JavaScript heap
# out-of-memory abort). Give Node 8 GB, but respect a caller-supplied heap: keep a larger
# --max-old-space-size, and keep every other NODE_OPTIONS flag.
HEAP_MB=8192
ensure_node_heap() {
  local opts="${NODE_OPTIONS:-}" current
  current="$(sed -nE 's/.*--max-old-space-size=([0-9]+).*/\1/p' <<< "$opts" | tail -n 1)"
  if [[ -n "$current" && "$current" -ge "$HEAP_MB" ]]; then
    return 0
  fi
  opts="$(sed -E 's/(^| )--max-old-space-size=[0-9]+//g; s/^ +//' <<< "$opts")"
  export NODE_OPTIONS="${opts:+${opts} }--max-old-space-size=${HEAP_MB}"
}
ensure_node_heap

CONTEXT="Org tests (local)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The working tree has uncommitted changes. Commit or stash them first: the status is" >&2
  echo "posted on HEAD, so the code tested has to be exactly the code at HEAD." >&2
  git status --short >&2
  exit 1
fi

SHA="$(git rev-parse HEAD)"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

if ! gh api "repos/${REPO}/commits/${SHA}" --silent 2>/dev/null; then
  echo "Commit ${SHA:0:7} is not on GitHub yet. Push it first, so the status has a commit to" >&2
  echo "attach to." >&2
  exit 1
fi

post_status() {
  local state="$1" description="$2"
  gh api "repos/${REPO}/statuses/${SHA}" --silent \
    -f state="$state" \
    -f context="$CONTEXT" \
    -f description="${description:0:140}"
}

echo "== Testing ${SHA:0:7} on ${ALIAS} =="
bash scripts/org/check-org-expiry.sh "$ALIAS"

if ! bash scripts/org/deploy-packages.sh "$ALIAS"; then
  post_status failure "Deploy to ${ALIAS} failed, so no test ran"
  exit 1
fi

# A real install gives the installing administrator the admin roles, and the tests run as
# that user in user mode, so they need the same roles here. "Duplicate" means the role is
# already assigned, which is the normal case after the first run.
for ps in BarnCRM_Admin Giving_Admin; do
  sf org assign permset --name "$ps" --target-org "$ALIAS" --json > "${TMPDIR:-/tmp}/assign.json" || true
  if jq -e '.result.failures[]? | select(.message | test("Duplicate") | not)' \
    "${TMPDIR:-/tmp}/assign.json" > /dev/null; then
    cat "${TMPDIR:-/tmp}/assign.json" >&2
    post_status failure "Could not assign ${ps} on ${ALIAS}, so no test ran"
    exit 1
  fi
done

# Run the test classes this commit holds, not every test class in the org. The test org is
# shared: another branch's deploy can leave its own test classes there, and its permission sets
# are overwritten by the next deploy, so a run of everything fails on code this commit does not
# contain. Naming the classes from the tracked source makes the status vouch for exactly the
# tests at HEAD.
TEST_ARGS=()
while IFS= read -r file; do
  if grep -qi "@istest" "$file"; then
    TEST_ARGS+=(--class-names "$(basename "$file" .cls)")
  fi
done < <(git ls-files 'packages/*.cls')
if [[ ${#TEST_ARGS[@]} -eq 0 ]]; then
  post_status failure "No test classes found in the source at ${SHA:0:7}"
  exit 1
fi

RESULTS_DIR="test-results"
mkdir -p "$RESULTS_DIR"
TEST_RETRY_WAIT_SECONDS="${TEST_RETRY_WAIT_SECONDS:-300}"
run_tests() {
  sf apex run test \
    --target-org "$ALIAS" \
    --test-level RunSpecifiedTests \
    "${TEST_ARGS[@]}" \
    --code-coverage \
    --result-format json \
    --wait 90 > "${RESULTS_DIR}/org-tests.json" 2> "${RESULTS_DIR}/org-tests.err" || true
  cat "${RESULTS_DIR}/org-tests.err" >&2
  read -r OUTCOME RAN PASSING FAILING < <(jq -r \
    '.result.summary | "\(.outcome // "Unknown") \(.testsRan // 0) \(.passing // 0) \(.failing // 0)"' \
    "${RESULTS_DIR}/org-tests.json" 2>/dev/null || echo "Unknown 0 0 0") || true
  OUTCOME="${OUTCOME:-Unknown}" RAN="${RAN:-0}" PASSING="${PASSING:-0}" FAILING="${FAILING:-0}"
}

# A run that comes back with no results at all because of UNKNOWN_EXCEPTION, or a platform or
# network error, is retried once after a pause: that is a transient platform fault, not a test
# result. A run with any result, including real failures, is never retried.
# An empty output (the CLI died) counts as a platform or network error too.
# A Node out-of-memory abort leaves one of these in the CLI output. The same wall is hit on a
# retry, so it is neither retried nor reported as a test result.
OOM_PATTERN='JavaScript heap out of memory|FATAL ERROR: .*(heap limit|Allocation failed)|Reached heap limit|Allocation failed - JavaScript heap'
cli_crashed() {
  if grep -qE "$OOM_PATTERN" "${RESULTS_DIR}/org-tests.err" "${RESULTS_DIR}/org-tests.json" 2>/dev/null; then
    return 0
  fi
  # Empty or unparseable output with no tests run is a dead CLI, not "0 of 0 failed".
  [[ "$RAN" -eq 0 ]] && ! jq -e '.result.summary' "${RESULTS_DIR}/org-tests.json" > /dev/null 2>&1
}
transient_no_results() {
  [[ "$RAN" -eq 0 ]] || return 1
  if grep -qE "$OOM_PATTERN" "${RESULTS_DIR}/org-tests.err" "${RESULTS_DIR}/org-tests.json" 2>/dev/null; then
    return 1
  fi
  [[ ! -s "${RESULTS_DIR}/org-tests.json" ]] && return 0
  grep -qiE 'UNKNOWN_EXCEPTION|ECONNRESET|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|socket hang up|ServerUnavailable|Service Unavailable|ClientTimeout|timed? ?out|network' \
    "${RESULTS_DIR}/org-tests.json" "${RESULTS_DIR}/org-tests.err"
}
run_tests
if transient_no_results; then
  echo "== The test run returned no results (platform or network error). Retrying once in ${TEST_RETRY_WAIT_SECONDS}s ==" >&2
  sleep "$TEST_RETRY_WAIT_SECONDS"
  run_tests
fi

if cli_crashed; then
  echo "== sf CLI crashed (out of memory, or no readable output), rerun. No test result is known," >&2
  echo "   so no \"${CONTEXT}\" status was posted on ${SHA:0:7}. Heap was ${NODE_OPTIONS}. ==" >&2
  echo "Output: ${RESULTS_DIR}/org-tests.err and ${RESULTS_DIR}/org-tests.json" >&2
  exit 3
fi

if [[ "$OUTCOME" == "Passed" && "$FAILING" -eq 0 && "$RAN" -gt 0 ]]; then
  post_status success "${PASSING}/${RAN} passed on ${ALIAS}"
  echo "== ${PASSING}/${RAN} passed. Posted \"${CONTEXT}\": success on ${SHA:0:7} =="
  exit 0
fi

post_status failure "${FAILING} of ${RAN} failed on ${ALIAS}"
echo "== ${FAILING} of ${RAN} failed. Posted \"${CONTEXT}\": failure on ${SHA:0:7} ==" >&2
jq -r '.result.tests[] | select(.Outcome != "Pass") | "  \(.FullName): \(.Message // "")"' \
  "${RESULTS_DIR}/org-tests.json" 2>/dev/null | cut -c1-200 >&2 || true
echo "Full results: ${RESULTS_DIR}/org-tests.json" >&2
exit 1
