#!/usr/bin/env bash
# run-org-tests.sh <org alias> [--relevant | --light]
# run-org-tests.sh --light-selfcheck      (no org, no GitHub: checks the --light allow-list)
#
# Three modes. The default (full) is the merge gate described below. --relevant (or
# ORG_TESTS_MODE=relevant) is a faster run for iteration: see "RELEVANT MODE" further down.
# --light (or ORG_TESTS_MODE=light) is the lighter gate for screen-only changes: see "LIGHT
# MODE" further down.
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
# RELEVANT MODE. Spring '26 added the RunRelevantTests test level, for deployments only
# (`sf apex run test` has no such level). After the same full staged deploy, this mode deploys
# again just the Apex this branch changed since its merge base with RELEVANT_BASE (default
# origin/main), plus the @IsTest(critical=true) classes, with --test-level RunRelevantTests:
# Salesforce runs the tests in that payload, the tests that depend directly on it, and every
# test class whose @IsTest(testFor=...) names a class in it or that is marked critical. The
# feature is beta and its selection misses indirect paths and changes to non-Apex metadata, so
# this is never the merge gate: it posts its own status context, "Org tests (relevant,
# local)", which the main ruleset does not require, and its description says "Relevant tests
# only". A fast run cannot satisfy "Org tests (local)".
#
# LIGHT MODE. Owner decision (Brandon, 2026-10-26): a change that touches only screens, labels
# or docs (no Apex, objects or permissions) does not need the ~3,600-test org run. Before any
# deploy, this mode lists the files changed since the merge base with RELEVANT_BASE (default
# origin/main) and REFUSES (exit 1, no status) unless every one is on LIGHT_ALLOWED_PATTERNS
# below. It then does the same staged deploy the full mode does (so the org ends in the same
# state), runs no Apex test, runs `npx jest --silent`, and posts the same required context,
# "Org tests (local)", with a description that starts "Light gate:" and says "no Apex-affecting
# changes; deploy and Jest passed", so a reviewer can tell it from a full run. Success needs
# both the deploy and Jest to pass; it posts failure otherwise. The full run still happens on
# every combined landing batch (a pull request that combines several branches) before merge:
# light mode is for a single screen-only branch, never for a batch. `--light-selfcheck` runs
# the allow-list against sample paths with no org and no GitHub.
#
# HOW COVERAGE IS CHECKED. Every full run checks code coverage (owner decision, 2026-10-13:
# due diligence happens automatically). The tests are enqueued with coverage on, so the org
# records it, but the results are fetched without it: `sf apex run test --code-coverage` used
# to pull per-test coverage into the result JSON (102 MB of a 313 MB file), which is what ran
# the CLI out of memory. Coverage is then read from the org's per-class totals
# (ApexCodeCoverageAggregate, Tooling API), a few hundred rows. The gate fails when BarnCRM's
# total is under COVERAGE_TOTAL_FLOOR (75) or a class is under COVERAGE_CLASS_FLOOR (75),
# except a class listed in scripts/org/coverage-floor-exceptions.txt, which may not fall below
# the figure recorded there. Per-class figures go to test-results/coverage.tsv.
#
# Exit codes: 0 = every test passed and the success status was posted; 1 = failure status
# posted or a precondition failed; 3 = the sf CLI crashed, no status posted, rerun.

set -euo pipefail

# LIGHT MODE ALLOW-LIST. The one place that says which paths a light run may cover. Each entry
# is a bash regex over a repo-relative path, and each is here because it cannot change the
# outcome of any Apex test, so skipping the Apex run loses nothing:
#   lwc, aura           browser-side bundles; Apex never reads them, and Jest covers the LWC ones
#   labels              a test fails on a label only if it asserts the label's text; the owner
#                       accepted that risk for screen text (2026-10-26)
#   flexipages          Lightning page layouts; no Apex reads a Lightning page
#   contentassets       images and similar files served to the UI; no Apex reads them
#   jest-mocks          Jest-only stubs; not deployed
#   docs/, *.md         documentation; not deployed
#   ISSUE_TEMPLATE      GitHub forms; not deployed
# Deliberately NOT here: staticresources (Apex reads SampleData and GivingSampleData), and
# every metadata type Apex can touch or the platform enforces (classes, triggers, objects,
# fields, permission sets and groups, custom metadata, flows, layouts, tabs, applications), plus
# scripts, config and sfdx-project.json. Any of those needs the full mode.
LIGHT_ALLOWED_PATTERNS=(
  '^packages/[^/]+/main/default/lwc/.+'
  '^packages/[^/]+/main/default/aura/.+'
  '^packages/[^/]+/main/default/labels/.+'
  '^packages/[^/]+/main/default/flexipages/.+'
  '^packages/[^/]+/main/default/contentassets/.+'
  '^packages/[^/]+/test/jest-mocks/.+'
  '^docs/.+'
  '\.md$'
  '^\.github/ISSUE_TEMPLATE/.+'
)

light_path_allowed() {
  local re
  for re in "${LIGHT_ALLOWED_PATTERNS[@]}"; do
    if [[ "$1" =~ $re ]]; then return 0; fi
  done
  return 1
}

# Reads paths on stdin, prints those the allow-list does not cover.
light_disallowed_paths() {
  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    light_path_allowed "$path" || echo "$path"
  done
}

# No org, no GitHub: feeds sample path lists to the allow-list and fails on any wrong verdict.
light_selfcheck() {
  local failures=0 path left
  check() { # check <allowed|refused> <path>
    local got=refused
    light_path_allowed "$2" && got=allowed
    if [[ "$got" != "$1" ]]; then
      echo "FAIL: $2 should be $1, was $got" >&2
      failures=$((failures + 1))
    fi
  }
  for path in \
    packages/core/main/default/lwc/barnConfirmModal/barnConfirmModal.js \
    packages/core/main/default/lwc/barnConfirmModal/__tests__/barnConfirmModal.test.js \
    packages/giving/main/default/aura/Foo/Foo.cmp \
    packages/core/main/default/labels/CustomLabels.labels-meta.xml \
    packages/core/main/default/flexipages/Home.flexipage-meta.xml \
    packages/core/main/default/contentassets/logo.asset-meta.xml \
    packages/core/test/jest-mocks/lightning/modal.js \
    docs/admin-guide/settings.md docs/images/shot.png README.md \
    packages/core/README.md .github/ISSUE_TEMPLATE/bug_report.yml; do
    check allowed "$path"
  done
  for path in \
    packages/core/main/default/classes/Foo.cls \
    packages/core/main/default/classes/Foo.cls-meta.xml \
    packages/core/main/default/triggers/Foo.trigger \
    packages/core/main/default/objects/Gift__c/Gift__c.object-meta.xml \
    packages/core/main/default/objects/Gift__c/fields/Amount__c.field-meta.xml \
    packages/core/main/default/permissionsets/Admin.permissionset-meta.xml \
    packages/core/main/default/permissionsetgroups/G.permissionsetgroup-meta.xml \
    packages/core/main/default/customMetadata/X.Y.md-meta.xml \
    packages/core/main/default/flows/F.flow-meta.xml \
    packages/core/main/default/layouts/L.layout-meta.xml \
    packages/core/main/default/tabs/T.tab-meta.xml \
    packages/core/main/default/applications/A.app-meta.xml \
    packages/core/main/default/staticresources/SampleData.json \
    packages/core/main/default/staticresources/SampleData.resource-meta.xml \
    scripts/org/run-org-tests.sh scripts/ci/check-labels.py config/project-scratch-def.json \
    sfdx-project.json package.json .github/workflows/ci.yml \
    packages/core/main/default/lwcx/x.js packages/core/main/default/lwc \
    xpackages/core/main/default/lwc/x.js docs-extra/x.txt notes.mdx; do
    check refused "$path"
  done
  # The list filter: only the uncovered paths come back, in order.
  left="$(printf '%s\n' docs/a.md packages/core/main/default/classes/A.cls \
    packages/core/main/default/lwc/x/x.html sfdx-project.json | light_disallowed_paths | paste -sd, -)"
  if [[ "$left" != "packages/core/main/default/classes/A.cls,sfdx-project.json" ]]; then
    echo "FAIL: light_disallowed_paths returned '${left}'" >&2
    failures=$((failures + 1))
  fi
  if [[ -n "$(printf '%s\n' docs/a.md packages/core/main/default/lwc/x/x.js | light_disallowed_paths)" ]]; then
    echo "FAIL: an all-allowed list was refused" >&2
    failures=$((failures + 1))
  fi
  if [[ "$failures" -ne 0 ]]; then
    echo "light-selfcheck: ${failures} failure(s)" >&2
    return 1
  fi
  echo "light-selfcheck: ok"
}

if [[ "${1:-}" == "--light-selfcheck" ]]; then
  light_selfcheck
  exit $?
fi

ALIAS="${1:-}"
MODE="${ORG_TESTS_MODE:-full}"
case "${2:-}" in
  "") ;;
  --relevant) MODE=relevant ;;
  --light) MODE=light ;;
  *) ALIAS="" ;;
esac
if [[ -z "$ALIAS" || ! "$MODE" =~ ^(full|relevant|light)$ ]]; then
  echo "Usage: run-org-tests.sh <org alias> [--relevant | --light]   (ORG_TESTS_MODE=full|relevant|light)" >&2
  echo "       run-org-tests.sh --light-selfcheck" >&2
  exit 2
fi
RELEVANT_BASE="${RELEVANT_BASE:-origin/main}"
COVERAGE_TOTAL_FLOOR="${COVERAGE_TOTAL_FLOOR:-75}"
COVERAGE_CLASS_FLOOR="${COVERAGE_CLASS_FLOOR:-75}"
TEST_WAIT_MINUTES="${TEST_WAIT_MINUTES:-90}"
TEST_POLL_SECONDS="${TEST_POLL_SECONDS:-15}"

# The status context names the mode, so a relevant run can never stand in for the full gate
# that the main ruleset requires; the description names it too, for anyone reading the list.
if [[ "$MODE" == "full" ]]; then
  CONTEXT="Org tests (local)"
  MODE_LABEL="Full run"
elif [[ "$MODE" == "light" ]]; then
  CONTEXT="Org tests (local)"
  MODE_LABEL="Light gate"
else
  CONTEXT="Org tests (relevant, local)"
  MODE_LABEL="Relevant tests only, not the merge gate"
fi
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The working tree has uncommitted changes. Commit or stash them first: the status is" >&2
  echo "posted on HEAD, so the code tested has to be exactly the code at HEAD." >&2
  git status --short >&2
  exit 1
fi

# Light mode refuses before anything else runs, so nothing is deployed and no status is posted
# for a change that needs the full gate.
if [[ "$MODE" == "light" ]]; then
  if ! MERGE_BASE="$(git merge-base "$RELEVANT_BASE" HEAD)"; then
    echo "No merge base between ${RELEVANT_BASE} and HEAD. Fetch it, or set RELEVANT_BASE." >&2
    exit 1
  fi
  LIGHT_CHANGED="$(git diff --name-only --no-renames "$MERGE_BASE" HEAD)"
  if [[ -z "$LIGHT_CHANGED" ]]; then
    echo "No changes since ${MERGE_BASE:0:7} (${RELEVANT_BASE}), so a light gate has nothing to vouch for." >&2
    exit 1
  fi
  LIGHT_REFUSED="$(printf '%s\n' "$LIGHT_CHANGED" | light_disallowed_paths)"
  if [[ -n "$LIGHT_REFUSED" ]]; then
    echo "The light gate covers only screens, labels and docs. These changed paths need the full run" >&2
    echo "(run-org-tests.sh <alias> with no flag):" >&2
    printf '%s\n' "$LIGHT_REFUSED" | sed 's/^/  /' >&2
    exit 1
  fi
  if [[ ! -d node_modules ]]; then
    echo "node_modules is missing, and the light gate runs Jest. Run: npm ci" >&2
    exit 1
  fi
fi

SHA="$(git rev-parse HEAD)"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

if ! gh api "repos/${REPO}/commits/${SHA}" --silent 2>/dev/null; then
  echo "Commit ${SHA:0:7} is not on GitHub yet. Push it first, so the status has a commit to" >&2
  echo "attach to." >&2
  exit 1
fi

# PARALLEL GATES (D-141, 2026-10-28). A landing batch is gated on two orgs at once, and both
# runs post the same context on the same commit, where GitHub shows only the newest. So a
# success never replaces a failure that another org posted on this commit: that status stays
# until the failing org is rerun (its own success may replace it) or the batch gets a new
# head. A failure always posts. If the statuses cannot be read, the success is posted.
post_status() {
  local state="$1" description="$2" held=""
  if [[ "$state" == "success" ]]; then
    held="$(gh api "repos/${REPO}/commits/${SHA}/statuses?per_page=100" 2>/dev/null \
      | jq -r --arg c "$CONTEXT" --arg a "$ALIAS" \
        'map(select(.context == $c))[0] // empty
          | select(.state == "failure" or .state == "error")
          | select((.description // "") | contains($a) | not) | .description' 2>/dev/null)" || true
    if [[ -n "$held" ]]; then
      echo "== Held: this run passed on ${ALIAS}, but \"${CONTEXT}\" on ${SHA:0:7} already shows another" >&2
      echo "   org's failure, which a success from here must not hide: ${held}" >&2
      echo "   Success was not posted. Fix that failure or rerun that org's gate. ==" >&2
      return 0
    fi
  fi
  gh api "repos/${REPO}/statuses/${SHA}" --silent \
    -f state="$state" \
    -f context="$CONTEXT" \
    -f description="${description:0:140}"
}

echo "== Testing ${SHA:0:7} on ${ALIAS} =="
bash scripts/org/check-org-expiry.sh "$ALIAS"

# No post-install steps: the tests assume an org that has never saved BarnCRM Settings.
if ! SOURCE_POST_INSTALL=0 bash scripts/org/deploy-packages.sh "$ALIAS"; then
  post_status failure "Deploy to ${ALIAS} failed, so no test ran"
  exit 1
fi

# WHY NO PERMISSION SET IS ASSIGNED. Every test runs inside System.runAs as a user that
# TestUsers creates with the permission sets it needs (check-tests-run-as.py enforces it), so
# the user running this script needs none of the BarnCRM, Giving or Mirror permission sets.
# The gate used to assign BarnCRM_Admin and Giving_Admin first, which hid any test that still
# leaned on the running user's access; a subscriber or another administrator holds none of
# them. Running without them makes the gate prove the suite is self-contained.

RESULTS_DIR="test-results"
mkdir -p "$RESULTS_DIR"

if [[ "$MODE" == "light" ]]; then
  # The staged deploy above is the same one the full mode does, and it runs no Apex test, so the
  # org ends in the same state. Jest is the only test the light gate adds.
  echo ""
  echo "== Light gate: no Apex tests; running Jest =="
  if npx jest --silent > "${RESULTS_DIR}/jest-light.log" 2>&1; then
    tail -n 8 "${RESULTS_DIR}/jest-light.log"
    post_status success "${MODE_LABEL}: no Apex-affecting changes; deploy and Jest passed on ${ALIAS}"
    echo "== Posted \"${CONTEXT}\": success on ${SHA:0:7} (light gate). A landing batch still needs the full run. =="
    exit 0
  fi
  tail -n 40 "${RESULTS_DIR}/jest-light.log" >&2
  post_status failure "${MODE_LABEL}: Jest failed after a good deploy to ${ALIAS}"
  echo "== Jest failed. Posted \"${CONTEXT}\": failure on ${SHA:0:7}. Full output: ${RESULTS_DIR}/jest-light.log ==" >&2
  exit 1
fi

if [[ "$MODE" == "relevant" ]]; then
  # The payload: the Apex this branch changed since it left RELEVANT_BASE, and the critical
  # classes, so a branch that changed no Apex still runs the smoke tests. Everything is already
  # in the org from the staged deploy above; this second deploy exists to carry the test level.
  if ! MERGE_BASE="$(git merge-base "$RELEVANT_BASE" HEAD)"; then
    echo "No merge base between ${RELEVANT_BASE} and HEAD. Fetch it, or set RELEVANT_BASE." >&2
    exit 1
  fi
  PAYLOAD=()
  while IFS= read -r file; do
    [[ -f "$file" ]] && PAYLOAD+=(--source-dir "$file")
  done < <({
    git diff --name-only --diff-filter=d "$MERGE_BASE" HEAD -- 'packages/*.cls' 'packages/*.trigger'
    git grep -liE '@IsTest[[:space:]]*\([^)]*critical[[:space:]]*=[[:space:]]*true' -- 'packages/*.cls'
  } | sort -u)
  if [[ ${#PAYLOAD[@]} -eq 0 ]]; then
    post_status failure "${MODE_LABEL}: no changed Apex and no critical test class at ${SHA:0:7}"
    exit 1
  fi
  echo ""
  echo "== Deploying $(( ${#PAYLOAD[@]} / 2 )) Apex file(s) with RunRelevantTests: those changed since ${MERGE_BASE:0:7} (${RELEVANT_BASE}), and the critical tests =="
  sf project deploy start --target-org "$ALIAS" "${PAYLOAD[@]}" --test-level RunRelevantTests \
    --ignore-conflicts --wait 90 --json > "${RESULTS_DIR}/org-tests-relevant.json" \
    2> "${RESULTS_DIR}/org-tests-relevant.err" || true
  # The deploy result is under .result on success and, depending on the CLI version, under
  # .result or .data when the deploy failed.
  read -r STATUS RAN FAILING < <(jq -r '(.result // .data // {}) as $r
    | "\($r.status // "Unknown") \($r.details.runTestResult.numTestsRun // $r.numberTestsCompleted // 0) \($r.details.runTestResult.numFailures // $r.numberTestErrors // 0)"' \
    "${RESULTS_DIR}/org-tests-relevant.json" 2>/dev/null || echo "Unknown 0 0") || true
  STATUS="${STATUS:-Unknown}" RAN="${RAN:-0}" FAILING="${FAILING:-0}"
  if [[ "$STATUS" == "Unknown" ]]; then
    cat "${RESULTS_DIR}/org-tests-relevant.err" >&2
    echo "== sf CLI gave no readable deploy result, rerun. No \"${CONTEXT}\" status was posted. ==" >&2
    exit 3
  fi
  if [[ "$STATUS" == "Succeeded" && "$FAILING" -eq 0 && "$RAN" -gt 0 ]]; then
    post_status success "${MODE_LABEL}: ${RAN}/${RAN} passed on ${ALIAS}"
    echo "== ${RAN}/${RAN} relevant tests passed. Posted \"${CONTEXT}\": success on ${SHA:0:7}."
    echo "   This is not the merge gate: run without --relevant before merging. =="
    exit 0
  fi
  if [[ "$FAILING" -gt 0 ]]; then
    post_status failure "${MODE_LABEL}: ${FAILING} of ${RAN} failed on ${ALIAS}"
  else
    post_status failure "${MODE_LABEL}: deploy ${STATUS} with ${RAN} tests run on ${ALIAS}"
  fi
  echo "== Relevant run ${STATUS}, ${FAILING} of ${RAN} tests failed. Posted \"${CONTEXT}\": failure on ${SHA:0:7} ==" >&2
  jq -r '(.result // .data // {}) as $r
    | ([$r.details.runTestResult.failures // empty] | flatten | .[] | "  \(.name).\(.methodName): \(.message // "")"),
      ([$r.details.componentFailures // empty] | flatten | .[] | "  \(.fullName): \(.problem // "")"),
      ([$r.details.runTestResult.codeCoverageWarnings // empty] | flatten | .[] | "  coverage: \(.name // ""): \(.message // "")"),
      ($r.errorMessage // empty)' \
    "${RESULTS_DIR}/org-tests-relevant.json" 2>/dev/null | cut -c1-200 >&2 || true
  echo "Full results: ${RESULTS_DIR}/org-tests-relevant.json" >&2
  exit 1
fi

# Run the test classes this commit holds, not every test class in the org. The test org is
# shared: another branch's deploy can leave its own test classes there, and its permission sets
# are overwritten by the next deploy, so a run of everything fails on code this commit does not
# contain. Naming the classes from the tracked source makes the status vouch for exactly the
# tests at HEAD.
#
# The vendored rollup engine's own tests (531 methods, about 70 seconds) are left out: no
# BarnCRM runtime path calls the engine any more, ADR-0082 deletes it in slice S9, and its
# tests prove the upstream project, not this one. Its classes are still deployed.
TEST_ARGS=()
while IFS= read -r file; do
  if grep -qi "@istest" "$file"; then
    TEST_ARGS+=(--class-names "$(basename "$file" .cls)")
  fi
done < <(git ls-files 'packages/*.cls' ':(exclude)packages/core/vendor/**')
if [[ ${#TEST_ARGS[@]} -eq 0 ]]; then
  post_status failure "No test classes found in the source at ${SHA:0:7}"
  exit 1
fi

TEST_RETRY_WAIT_SECONDS="${TEST_RETRY_WAIT_SECONDS:-300}"
# Enqueue with coverage on (so the org records it), wait for the run in the org, then fetch the
# results without coverage (see "HOW COVERAGE IS CHECKED" above). A run still going after
# TEST_WAIT_MINUTES leaves no result file, which reads below as "no result, rerun".
run_tests() {
  local run_id="" state="" started="$SECONDS"
  : > "${RESULTS_DIR}/org-tests.json"
  sf apex run test \
    --target-org "$ALIAS" \
    --test-level RunSpecifiedTests \
    "${TEST_ARGS[@]}" \
    --code-coverage \
    --wait 0 \
    --json > "${RESULTS_DIR}/org-tests-enqueue.json" 2> "${RESULTS_DIR}/org-tests.err" || true
  run_id="$(jq -r '.result.testRunId // empty' "${RESULTS_DIR}/org-tests-enqueue.json" 2>/dev/null)" || true
  if [[ -z "$run_id" ]]; then
    cp "${RESULTS_DIR}/org-tests-enqueue.json" "${RESULTS_DIR}/org-tests.json"
  else
    echo "== Test run ${run_id} enqueued; checking every ${TEST_POLL_SECONDS}s =="
    while (( SECONDS - started < TEST_WAIT_MINUTES * 60 )); do
      sleep "$TEST_POLL_SECONDS"
      state="$(sf data query --target-org "$ALIAS" --json \
        --query "SELECT Status FROM AsyncApexJob WHERE Id = '${run_id}'" 2>/dev/null \
        | jq -r '.result.records[0].Status // empty' 2>/dev/null)" || true
      [[ "$state" =~ ^(Completed|Aborted|Failed)$ ]] && break
    done
    if [[ "$state" =~ ^(Completed|Aborted|Failed)$ ]]; then
      sf apex get test --target-org "$ALIAS" --test-run-id "$run_id" --result-format json \
        > "${RESULTS_DIR}/org-tests.json" 2>> "${RESULTS_DIR}/org-tests.err" || true
    else
      echo "Test run ${run_id} was still ${state:-unreported} after ${TEST_WAIT_MINUTES} minutes." \
        >> "${RESULTS_DIR}/org-tests.err"
    fi
  fi
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
# A Node out-of-memory abort (seen when the results carried per-test coverage) leaves one of
# these in the CLI output. The same wall is hit on a retry, so it is neither retried nor
# reported as a test result.
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
  echo "   so no \"${CONTEXT}\" status was posted on ${SHA:0:7}. ==" >&2
  echo "Output: ${RESULTS_DIR}/org-tests.err and ${RESULTS_DIR}/org-tests.json" >&2
  exit 3
fi

if [[ "$OUTCOME" == "Passed" && "$FAILING" -eq 0 && "$RAN" -gt 0 ]]; then
  # Coverage, from the org's per-class totals. The deploy above recompiled every class, which
  # clears its coverage, so the totals are this run's. Only Apex in this commit's source counts
  # (not test classes, the vendored engine, or what another branch left in the shared org).
  COVERAGE_FILE="${RESULTS_DIR}/coverage.tsv"
  sf data query --use-tooling-api --target-org "$ALIAS" --json --query \
    "SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate" \
    > "${RESULTS_DIR}/coverage-aggregate.json" 2>> "${RESULTS_DIR}/org-tests.err" || true
  sf data query --use-tooling-api --target-org "$ALIAS" --json --query \
    "SELECT PercentCovered FROM ApexOrgWideCoverage" \
    > "${RESULTS_DIR}/coverage-org-wide.json" 2>> "${RESULTS_DIR}/org-tests.err" || true
  git ls-files 'packages/*.cls' 'packages/*.trigger' ':(exclude)packages/core/vendor/**' \
    > "${RESULTS_DIR}/coverage-sources.txt"
  COVERAGE_RC=0
  python3 - "${RESULTS_DIR}/coverage-aggregate.json" "${RESULTS_DIR}/coverage-org-wide.json" \
    scripts/org/coverage-floor-exceptions.txt "$COVERAGE_TOTAL_FLOOR" "$COVERAGE_CLASS_FLOOR" \
    "$COVERAGE_FILE" "${RESULTS_DIR}/coverage-sources.txt" \
    > "${RESULTS_DIR}/coverage-verdict.txt" <<'PYEOF' || COVERAGE_RC=$?
import json, os, re, sys

aggregate, org_wide, exceptions_file, total_floor, class_floor, out, sources = sys.argv[1:8]
total_floor, class_floor = float(total_floor), float(class_floor)
try:
    rows = json.load(open(aggregate))["result"]["records"]
except Exception:
    print("no coverage: the ApexCodeCoverageAggregate query gave no readable result")
    sys.exit(2)
try:
    org_pct = json.load(open(org_wide))["result"]["records"][0]["PercentCovered"]
except Exception:
    org_pct = None
covered = {}
for r in rows:
    name = (r.get("ApexClassOrTrigger") or {}).get("Name")
    if name:
        c, u = r.get("NumLinesCovered") or 0, r.get("NumLinesUncovered") or 0
        prev = covered.get(name, (0, 0))
        covered[name] = (max(c, prev[0]), max(c + u, prev[1]))
exceptions = {}
for line in open(exceptions_file, encoding="utf-8"):
    line = line.split("#", 1)[0].split()
    if len(line) >= 2:
        exceptions[line[0]] = float(line[1].rstrip("%"))
lines = ["class\tcovered\ttotal\tpercent\tfloor\tresult"]
under, total_c, total_l = [], 0, 0
for path in open(sources, encoding="utf-8").read().split("\n"):
    if not path:
        continue
    source = open(path, encoding="utf-8").read()
    if re.search(r"@istest", source, re.I):
        continue
    name = os.path.basename(path).rsplit(".", 1)[0]
    if path.endswith(".cls") and re.search(r"\binterface\s+" + name + r"\b", source):
        continue  # no executable lines
    c, l = covered.get(name, (0, None))
    if l == 0:
        continue  # nothing executable, such as an exception class
    pct = 0.0 if not l else 100.0 * c / l
    total_c, total_l = total_c + c, total_l + (l or 0)
    floor = exceptions.get(name, class_floor)
    result = "ok" if pct >= floor else "UNDER"
    if l is None:
        result += " (no coverage row: no test ran it)"
    if result.startswith("UNDER"):
        under.append(f"{name} {pct:.0f}% (floor {floor:.0f}%)")
    elif name in exceptions and pct >= class_floor:
        result += f" (now over {class_floor:.0f}%: take it off the exceptions list)"
    lines.append(f"{name}\t{c}\t{l or 0}\t{pct:.1f}\t{floor:.0f}\t{result}")
total = 100.0 * total_c / total_l if total_l else 0.0
lines.append(f"BarnCRM total\t{total_c}\t{total_l}\t{total:.1f}\t{total_floor:.0f}\t{'ok' if total >= total_floor else 'UNDER'}")
lines.append(f"org-wide (information only)\t\t\t{org_pct if org_pct is not None else 'unknown'}\t\t")
open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
for u in under:
    print("  under the floor: " + u, file=sys.stderr)
summary = f"coverage {total:.0f}%, {len(under)} class(es) under floor"
print(summary)
sys.exit(1 if under or total < total_floor else 0)
PYEOF
  COVERAGE_VERDICT="$(head -n 1 "${RESULTS_DIR}/coverage-verdict.txt")"
  if [[ "$COVERAGE_RC" -ne 0 ]]; then
    post_status failure "${MODE_LABEL}: ${PASSING}/${RAN} passed on ${ALIAS}, but ${COVERAGE_VERDICT:-coverage unreadable}"
    echo "== Tests passed, coverage did not: ${COVERAGE_VERDICT:-unreadable}. Posted \"${CONTEXT}\": failure on ${SHA:0:7} ==" >&2
    echo "Per-class coverage: ${COVERAGE_FILE}" >&2
    exit 1
  fi
  post_status success "${MODE_LABEL}: ${PASSING}/${RAN} passed on ${ALIAS}, ${COVERAGE_VERDICT}"
  echo "== ${PASSING}/${RAN} passed, ${COVERAGE_VERDICT}. Posted \"${CONTEXT}\": success on ${SHA:0:7} =="
  echo "Per-class coverage: ${COVERAGE_FILE}"
  exit 0
fi

post_status failure "${MODE_LABEL}: ${FAILING} of ${RAN} failed on ${ALIAS}"
echo "== ${FAILING} of ${RAN} failed. Posted \"${CONTEXT}\": failure on ${SHA:0:7} ==" >&2
jq -r '.result.tests[] | select(.Outcome != "Pass") | "  \(.FullName): \(.Message // "")"' \
  "${RESULTS_DIR}/org-tests.json" 2>/dev/null | cut -c1-200 >&2 || true
echo "Full results: ${RESULTS_DIR}/org-tests.json" >&2
exit 1
