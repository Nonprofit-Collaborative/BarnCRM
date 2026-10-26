#!/usr/bin/env bash
# deploy-packages.sh <alias> [--core-only]
#
# Deploys the packages to an org in stages, smallest blast radius first.
#
# WHY IN STAGES. The first deploy this project ever attempted sent all 982 components in one
# request and came back with UNKNOWN_EXCEPTION, zero components deployed, zero component
# errors, and a Salesforce ErrorId. A failure with no component attached tells you nothing
# about which of 982 things caused it. Deploying Core before Giving means the next such
# failure names a stage.
#
# It also matches how the packages actually depend on each other: the Rollup Builder module
# depends on Core, and Giving depends on both.
#
# WHY CORE IS SEVERAL STAGES. docs/contributor-guide/ci.md records this same failure
# hitting the undivided Core stage four times across four separate runs before 2026-09-09:
# always UNKNOWN_EXCEPTION, always zero components deployed, always zero component errors,
# always the same trailing code -315522575 behind a different leading number, which is why
# that page calls it a deterministic fault rather than a flake and says a re-run proves
# nothing. It recurred twice more on 2026-09-09, on two separate pushes to main, both times
# on the same undivided Core stage, which by then held 904 components in one request: the
# same shape as the original 982-component failure this file was written to avoid, just
# smaller.
#
# Splitting Core into three (data model, Apex, UI and permissions) followed Salesforce's own
# deploy dependency order and named a stage instead of nothing: the very next run, still on
# 2026-09-09, failed on data model alone, at 853 components. That is the load-bearing data
# point. 853 is close enough to 904 and 982 that a specific bad component stopped being the
# more likely explanation: three deploys of very different content (mostly Apex classes the
# first time, mostly custom fields the second) all failed in the same shape once they got
# into the same few-hundred-to-thousand range. That reads as a size effect, not a component
# defect, though it is still not proven, because nothing about this failure can be proven
# from the client side. It just stopped being a coin flip.
#
# So data model became three stages of its own: `balanced_split` divided
# packages/core/main/default/objects by file count into two roughly equal halves at runtime
# (a hand-written list of object names would go stale the first time someone adds one), and
# customMetadata, labels, static resources and custom permissions formed a third, smaller
# stage. That halving stopped being useful evidence on 2026-09-09: the two halves it produces
# are stable across runs (nothing but file *content* changed in between, and balanced_split
# only looks at file *counts*), and across four consecutive pushes that all fixed real
# component-level errors in "objects B" (139 files, 10 objects), that stage kept failing with
# the same zero-component UNKNOWN_EXCEPTION every single time, while "objects A" (144 files,
# 11 objects, comparable size) deployed clean every one of those four runs. Two same-sized
# groups behaving oppositely and consistently is not a size effect; it is evidence the fault
# tracks something specific to one or more objects inside "objects B".
#
# Objects now deploy one at a time, each its own stage, rather than split into another pair
# of same-content halves that would just repeat this result. That worked immediately: every
# object deployed clean, and it was Address__c's own real component errors (Street__c's
# invalid length, a text area field in a compact layout) that had been hiding behind the
# opaque failure the whole time, not the platform fault recurring on an object.
#
# With objects clear, the platform fault moved to the next stage in line: the four config
# directories (customMetadata, labels, staticresources, customPermissions), deployed together,
# hit it at 568 components. File count there is a badly misleading proxy: around 70 files
# across all four looked nothing like a risk, but `packages/core/main/default/labels/CustomLabels.labels-meta.xml`
# is one file holding 388 individual label components. Config is now three stages: custom
# metadata, labels (isolating that one file), and static resources with custom permissions
# together, since both are a handful of components on any count.
#
# Apex and UI/permissions are unchanged, because neither has failed yet and there is no
# evidence pointing at either.
#
# WHY A PAUSE BETWEEN STAGES. Custom metadata alone, split out from the rest of config,
# still hit the same zero-component UNKNOWN_EXCEPTION at 61 files, confirmed identical on a
# manual re-run (same ErrorId trailing code, same zero components, zero errors). 61 is nowhere
# near the few-hundred-to-thousand range every prior failure has carried, and this is the
# first time a stage that small has failed on its own, so size stops being a workable
# explanation for this occurrence specifically: something else has to be going on. Every stage
# in this script runs as its own blocking `sf project deploy start --wait 30` call, one after
# another, against the one persistent org, with no gap between a stage finishing and the next
# one starting. If the org's deploy engine needs a moment to settle after reporting a deploy
# Done before it can safely accept the next one, back to back calls with no pause would be
# exactly the condition to trigger that. Untested, and not the only remaining explanation, but
# cheap and non-destructive to try: every deploy_stage call now pauses for
# $STAGE_PAUSE_SECONDS after a successful deploy, before the next stage starts.
#
# WHY ASYNC WITH A STALL CHECK. From 2026-09-24 about 13:00 UTC, one stage per run on
# oi-test (a different one each time) sat as a DeployRequest in Status Pending with no
# StartDate until the blocking --wait 30 gave up, so the whole gate failed after 30 minutes.
# Cancelling such a request reports Canceled but leaves it Pending, and a fresh submission of
# the same stage deploys normally. So each stage is submitted with --async and followed with
# short report calls: a job still Pending with no start after STALL_SECONDS (300) is
# cancelled, best effort, and resubmitted once; a second stall fails the stage naming both
# job ids. A job that has started keeps the old 30 minute limit (DEPLOY_WAIT_MINUTES). Each
# report call is abandoned after REPORT_TIMEOUT_SECONDS (60): one hung for 290s on 2026-09-24.
# A transient client error (fetch failed, ECONNRESET, a 5xx) on a submit or a report is
# retried, not taken as a failure: the same day one stage failed on "fetch failed" while the
# org reported that deploy Succeeded. After a submit error, the newest DeployRequest from the
# last minute is followed if there is one, so a stage is never deployed twice.
# POLL_SECONDS sets the report interval. `sf` is found on PATH, so a fake one can drive this
# logic in a test.
#
# WHAT THE STAGES COST, AND THE FAST DEFAULTS. About 36 stages, each followed by a 15 second
# pause, cost about 9 minutes of sleep per run plus the submit and poll overhead of every
# stage. The two faults that justified the split have since been explained by real defects
# (the Account to Import_Batch__c order, which the order below fixes, and the unparseable
# custom metadata of 2026-09-22). So the defaults are now the fast settings: no pause
# (STAGE_PAUSE_SECONDS=0) and every Core object in one request (DATA_MODEL_STAGES=combined),
# falling back to one object per stage only when that request fails with no component error
# (the platform's opaque UNKNOWN_EXCEPTION). The full gate at these settings took about 12
# minutes end to end on oi-test on 2026-10-13, clean. STAGE_PAUSE_SECONDS=15 and
# DATA_MODEL_STAGES=per-object bring back the old behaviour: see docs/contributor-guide/ci.md,
# "Faster deploys".
#
# Exit codes: 0 = every stage deployed, non-zero = the first stage that failed.

set -uo pipefail

STAGE_PAUSE_SECONDS="${STAGE_PAUSE_SECONDS:-0}"
DATA_MODEL_STAGES="${DATA_MODEL_STAGES:-combined}"
STALL_SECONDS="${STALL_SECONDS:-300}"
POLL_SECONDS="${POLL_SECONDS:-15}"
DEPLOY_WAIT_MINUTES="${DEPLOY_WAIT_MINUTES:-30}"
REPORT_TIMEOUT_SECONDS="${REPORT_TIMEOUT_SECONDS:-60}"
REPORT_FAILURE_LIMIT="${REPORT_FAILURE_LIMIT:-20}"
RETRY_BACKOFF_SECONDS="${RETRY_BACKOFF_SECONDS:-5}"
# 1 runs Core's post-install steps once Core is in (CorePostInstall.runAsSourceDeploy); 0 skips
# them. run-org-tests.sh passes 0: the Apex tests assume an org that has never saved BarnCRM
# Settings (they insert their own), and a test org marked as a new install has every feature off.
SOURCE_POST_INSTALL="${SOURCE_POST_INSTALL:-1}"
STALLS_RECOVERED=0

ALIAS="${1:-}"
if [[ -z "$ALIAS" ]]; then
  echo "Usage: deploy-packages.sh <alias> [--core-only]" >&2
  exit 1
fi
shift || true

CORE_ONLY=0
[[ "${1:-}" == "--core-only" ]] && CORE_ONLY=1
if [[ ! "$DATA_MODEL_STAGES" =~ ^(per-object|combined)$ ]]; then
  echo "DATA_MODEL_STAGES must be per-object or combined, not ${DATA_MODEL_STAGES}." >&2
  exit 1
fi

# Run a command with its output in a file, abandoning it (and the node process under the
# sf wrapper) after $1 seconds. On 2026-09-24 a single `sf project deploy report` call hung
# for about 290 seconds on oi-test while the deploy itself finished in 2, so no call is
# allowed to hold up the stall check. macOS has no `timeout`; a polling loop is used rather
# than a watchdog subshell, which could outlive the call it guarded.
run_capped() {
  local secs="$1" out="$2" pid kids ticks=0
  shift 2
  "$@" > "$out" 2> /dev/null &
  pid=$!
  while kill -0 "$pid" 2> /dev/null; do
    if (( ticks >= secs * 5 )); then
      # The parent first, so the wrapper cannot carry on once its child is gone.
      kids="$(pgrep -P "$pid")"
      kill "$pid" 2> /dev/null
      [[ -n "$kids" ]] && kill $kids 2> /dev/null
      : > "$out"
      break
    fi
    sleep 0.2
    ticks=$(( ticks + 1 ))
  done
  wait "$pid" 2> /dev/null
  return 0
}

# A client side error that says nothing about the deploy: the request or its answer was lost
# on the way. On 2026-09-24 a stage on oi-pa failed with "Error (10): fetch failed" while
# the org's own report for that deploy said Succeeded.
TRANSIENT_PATTERN='fetch failed|ECONNRESET|ETIMEDOUT|ECONNREFUSED|ENOTFOUND|EAI_AGAIN|socket hang up|network|Service Unavailable|Bad Gateway|Gateway Time-?out|Internal Server Error|\b5[0-9][0-9]\b'

# After a submit that errored in transit, find the deploy the org may have created anyway:
# the newest DeployRequest created since a minute before the submit. The org lock means no
# one else deploys meanwhile. Prints the id, or nothing.
find_recent_deploy() {
  local since="$1" capture
  capture="$(mktemp)"
  run_capped "$REPORT_TIMEOUT_SECONDS" "$capture" sf data query --use-tooling-api --target-org "$ALIAS" --json \
    --query "SELECT Id FROM DeployRequest WHERE CreatedDate >= ${since} ORDER BY CreatedDate DESC LIMIT 1"
  jq -r '.result.records[0].Id // empty' "$capture" 2> /dev/null
  rm -f "$capture"
}

# Submit one deploy asynchronously and follow it with short report calls. Sets JOB_ID.
# Returns 0 when it succeeded, 1 when it finished any other way (or ran past
# DEPLOY_WAIT_MINUTES, the old --wait 30), and 2 when it was still Pending with no start
# after STALL_SECONDS: a stall, which the caller cancels and resubmits. A job that has
# started is never a stall, however long it runs. A transient client error on the submit or
# on a report call is retried, never taken for a result.
submit_and_follow() {
  local out report state finished started deployed total shown="" submitted since message
  local capture try misses=0 verdict
  capture="$(mktemp)"
  JOB_ID=""
  for try in 1 2 3; do
    since="$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(seconds=60)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
    run_capped 300 "$capture" sf project deploy start "$@" --async --ignore-conflicts --target-org "$ALIAS" --json
    out="$(cat "$capture")"
    JOB_ID="$(jq -r '.result.id // empty' <<< "$out" 2> /dev/null)"
    [[ -n "$JOB_ID" ]] && break
    message="$(jq -r '.message // empty' <<< "$out" 2> /dev/null)"
    message="${message:-${out:-no output}}"
    if ! grep -qiE "$TRANSIENT_PATTERN" <<< "$message" && [[ -n "$out" ]]; then
      echo "The org did not accept the deploy:"
      echo "$message"
      rm -f "$capture"
      return 1
    fi
    echo "== Transient client error on submit (${message:0:120}). Checking whether the org created the deploy anyway =="
    JOB_ID="$(find_recent_deploy "$since")"
    if [[ -n "$JOB_ID" ]]; then
      echo "== The org did create it: following ${JOB_ID} rather than deploying the stage twice =="
      break
    fi
    if [[ "$try" -lt 3 ]]; then
      echo "== No deploy was created. Resubmitting in $(( try * 3 * RETRY_BACKOFF_SECONDS ))s =="
      sleep $(( try * 3 * RETRY_BACKOFF_SECONDS ))
    fi
  done
  if [[ -z "$JOB_ID" ]]; then
    echo "The deploy could not be submitted: three transient client errors in a row."
    rm -f "$capture"
    return 1
  fi
  submitted="$SECONDS"
  echo "Deploy ID: ${JOB_ID}"
  while true; do
    sleep "$POLL_SECONDS"
    : > "$capture"
    run_capped "$REPORT_TIMEOUT_SECONDS" "$capture" sf project deploy report --job-id "$JOB_ID" --target-org "$ALIAS" --json
    report="$(cat "$capture")"
    state="" finished="" started="" deployed="" total=""
    read -r state finished started deployed total < <(jq -r '.result // empty
      | "\(.status // "Unknown") \(.done // false) \(.startDate // "none") \(.numberComponentsDeployed // 0) \(.numberComponentsTotal // 0)"' \
      <<< "$report" 2> /dev/null)
    verdict=""
    if [[ -z "$state" ]]; then
      # No readable report: a hung or failed call. Retry after a short backoff; a report that
      # stays unreadable for REPORT_FAILURE_LIMIT calls in a row fails the stage.
      misses=$(( misses + 1 ))
      message="$(jq -r '.message // empty' <<< "$report" 2> /dev/null)"
      echo "Report call ${misses} gave no status (${message:-no answer within ${REPORT_TIMEOUT_SECONDS}s}). Retrying."
      if (( misses >= REPORT_FAILURE_LIMIT )); then
        echo "No readable report for ${JOB_ID} in ${misses} calls in a row."
        verdict=1
      else
        sleep $(( (misses < 4 ? misses : 4) * RETRY_BACKOFF_SECONDS ))
      fi
    else
      misses=0
      if [[ "${state} ${deployed}/${total}" != "$shown" ]]; then
        shown="${state} ${deployed}/${total}"
        echo "Status: ${state} (${deployed}/${total} components, $(( SECONDS - submitted ))s)"
      fi
      case "$state" in
        Succeeded) verdict=0 ;;
        SucceededPartial | Failed | Canceled) verdict=1 ;;
      esac
      [[ -z "$verdict" && "$finished" == "true" ]] && verdict=1
      if [[ -z "$verdict" && "$state" =~ ^(Pending|Queued)$ && "$started" == "none" && "$deployed" -eq 0 ]] \
        && (( SECONDS - submitted >= STALL_SECONDS )); then
        verdict=2
      fi
    fi
    if [[ -z "$verdict" ]] && (( SECONDS - submitted >= DEPLOY_WAIT_MINUTES * 60 )); then
      echo "Timed out after ${DEPLOY_WAIT_MINUTES} minutes with the deploy still ${state:-unreported}."
      verdict=1
    fi
    if [[ -n "$verdict" ]]; then
      rm -f "$capture"
      return "$verdict"
    fi
  done
}

# Deploy one or more directories as a single stage, and on failure ask the org what actually
# went wrong. A deploy can report only "Status: Failed" with no detail, which is why the
# report is asked for by job id and then again as JSON: the JSON carries errorMessage and
# every component error.
# True when packages/volunteers holds any file besides .gitkeep, so an empty module folder is a no-op.
volunteers_has_metadata() {
  [[ -n "$(find packages/volunteers/main -type f ! -name .gitkeep 2> /dev/null | head -1)" ]]
}

deploy_stage() {
  local label="$1"
  shift
  local dirs=()
  local dir
  for dir in "$@"; do
    if [[ -d "$dir" ]]; then
      dirs+=(--source-dir "$dir")
    fi
  done

  if [[ "${#dirs[@]}" -eq 0 ]]; then
    echo "== Skipping ${label}: none of the given directories exist =="
    return 0
  fi

  echo ""
  echo "== Deploying ${label} ($*) to ${ALIAS} =="
  local status attempt stalled=()
  for attempt in 1 2; do
    submit_and_follow "${dirs[@]}"
    status=$?
    [[ "$status" -ne 2 ]] && break
    stalled+=("$JOB_ID")
    echo "== STALLED DEPLOY: ${label}, job ${JOB_ID}, still Pending with no start after ${STALL_SECONDS}s. Cancelling it =="
    run_capped "$REPORT_TIMEOUT_SECONDS" /dev/null sf project deploy cancel --job-id "$JOB_ID" --target-org "$ALIAS" --async --json
    [[ "$attempt" -eq 1 ]] && echo "== Resubmitting ${label} once =="
  done

  if [[ "$status" -eq 2 ]]; then
    echo ""
    echo "== ${label} failed: its deploy stalled twice (Pending, never started), jobs ${stalled[*]} =="
    echo "A cancel was requested for each. This is the platform deploy queue, not a component error; see"
    echo "docs/contributor-guide/ci.md, \"Stalled deploys\"."
    return 1
  fi

  if [[ "$status" -ne 0 ]]; then
    echo ""
    echo "== ${label} failed. Asking the org for the component level detail =="
    if [[ -n "$JOB_ID" ]]; then
      sf project deploy report --job-id "$JOB_ID" --target-org "$ALIAS" || true
      # Only the failures and the overall message: the full JSON lists every deployed
      # component first, which pushed the failures out of reach of a log tail.
      sf project deploy report --job-id "$JOB_ID" --target-org "$ALIAS" --json \
        | jq '.result | {status, errorMessage, numberComponentErrors, componentFailures: .details.componentFailures}' \
        || true
    else
      sf project deploy report --use-most-recent --target-org "$ALIAS" || true
    fi
    echo ""
    echo "The stage that failed is ${label}. If the report above lists component failures,"
    echo "fix those components: that is an ordinary deploy error. If it shows UNKNOWN_EXCEPTION"
    echo "with zero component errors, suspect a file the metadata API could not parse at all"
    echo "(on 2026-09-22 that was an undeclared xsd prefix in custom metadata records) before"
    echo "suspecting the platform. See docs/contributor-guide/ci.md, \"Resolved 2026-09-22\"."
    return "$status"
  fi

  sf project deploy report --job-id "$JOB_ID" --target-org "$ALIAS" || true
  if [[ "${#stalled[@]}" -gt 0 ]]; then
    STALLS_RECOVERED=$(( STALLS_RECOVERED + ${#stalled[@]} ))
    echo "== Recovered: ${label} deployed on resubmission after stalled job ${stalled[*]} =="
  fi
  if [[ "$STAGE_PAUSE_SECONDS" != "0" ]]; then
    echo "== Pausing ${STAGE_PAUSE_SECONDS}s before the next stage =="
    sleep "$STAGE_PAUSE_SECONDS"
  fi
  return 0
}

# Every folder under Core's main/default has to be named by a stage below. A folder no stage
# names never reaches the org, so nothing that depends on it is ever tested: Core's flows went
# undeployed this way until 2026-10-13.
CORE_DIR="packages/core/main/default"
CORE_STAGED=(objects customMetadata labels staticresources customPermissions notificationtypes
  classes triggers contentassets permissionsets permissionsetgroups layouts flexipages applications
  tabs quickActions lwc prompts flows PlatformEventSubscriberConfigs)
unstaged=()
for dir in "$CORE_DIR"/*/; do
  dir="$(basename "$dir")"
  [[ " ${CORE_STAGED[*]} " == *" ${dir} "* ]] || unstaged+=("$dir")
done
if [[ ${#unstaged[@]} -gt 0 ]]; then
  echo "No deploy stage names ${CORE_DIR}/${unstaged[*]}. Add it to a stage and to CORE_STAGED." >&2
  exit 1
fi

# One stage per object, not a file-count split. The two-way file-count split this replaced
# produced the same two groups every run, since only file content had been changing, not
# file counts, and one of those two groups (10 objects, 139 files) failed with the platform's
# zero-component UNKNOWN_EXCEPTION on four consecutive pushes while the other (11 objects, 144
# files, comparable size) deployed clean every time. Same size, opposite and consistent
# outcomes: that is evidence against a size effect, not for one, so splitting into another
# same-content pair would not have told us anything the last four runs did not already show.
# Each object is small enough on its own (a handful of files to a few dozen) that the next
# failure, if there is one, names the exact object; if every object deploys clean individually,
# that is itself the finding, that it takes several specific objects deployed together in one
# request to trigger this.
#
# ORDER. The stages run in dependency order, not alphabetical order. A lookup field can only
# deploy once the object it points at exists, and one object per stage means nothing else in
# the request can supply it. Alphabetical order put Account before Import_Batch__c, which
# Account.Created_By_Import_Batch__c references, and a persistent org hid that for weeks
# because Import_Batch__c was already there from an earlier run: the first fresh org failed on
# it (2026-09-23). The order is computed from each field's referenceTo, not written down, so an
# object added later cannot reintroduce the same failure. Ties stay alphabetical, so the order
# is stable run to run. Standard objects are always in the org already, so a reference to one
# never constrains the order.
OBJECTS_DIR="packages/core/main/default/objects"
if ! OBJECT_ORDER=$(python3 - "$OBJECTS_DIR" <<'PYEOF'
import glob, os, re, sys
base = sys.argv[1]
objects = sorted(d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)))
needs = {o: set() for o in objects}
for o in objects:
    for f in glob.glob(os.path.join(base, o, "fields", "*.field-meta.xml")):
        for ref in re.findall(r"<referenceTo>([^<]+)</referenceTo>", open(f, encoding="utf-8").read()):
            # A custom object (its API name carries "__") has to be deployed first; a standard one is already there.
            if ref in needs and ref != o and "__" in ref:
                needs[o].add(ref)
done = []
while len(done) < len(objects):
    ready = [o for o in objects if o not in done and needs[o] <= set(done)]
    if not ready:
        left = [o for o in objects if o not in done]
        sys.exit("These objects look up each other in a cycle, so no one-object-per-stage "
                 "order can deploy them: " + ", ".join(left))
    done.append(ready[0])
print("\n".join(done))
PYEOF
); then
  echo "Could not work out a deploy order for ${OBJECTS_DIR}." >&2
  exit 1
fi
deploy_objects_one_by_one() {
  local object
  while IFS= read -r object; do
    deploy_stage "Core (data model, ${object})" "${OBJECTS_DIR}/${object}/" || return $?
  done <<< "$OBJECT_ORDER"
}
if [[ "$DATA_MODEL_STAGES" == "combined" ]]; then
  # One request for every object. A failure that names components is a real error and stops
  # the run; one that names none is the opaque platform fault, so the objects go again one by one.
  if ! deploy_stage "Core (data model, every object in one request)" "$OBJECTS_DIR"; then
    errors="$(sf project deploy report --job-id "$JOB_ID" --target-org "$ALIAS" --json 2> /dev/null \
      | jq -r '.result.numberComponentErrors // 0' 2> /dev/null)"
    [[ "$errors" =~ ^[0-9]+$ ]] || errors=1
    if [[ -z "$JOB_ID" || "${errors:-0}" -gt 0 ]]; then
      exit 1
    fi
    echo "== The one-request data model deploy failed with no component error. Falling back to one object per stage =="
    deploy_objects_one_by_one || exit $?
  fi
else
  deploy_objects_one_by_one || exit $?
fi
# One stage per config directory, not one stage for all four. Every object deployed clean
# individually (the finding the per-object split above was designed to produce), so the very
# next stage in line, the four config directories deployed together, is what hit the platform
# fault this time: 568 components in one request from a directory set whose file count (about
# 70 across all four) looked nowhere near that. The gap is CustomLabels.labels-meta.xml, one
# file holding 388 individual label components; file count is a proxy for component count,
# not the same number, and a single label file is the sharpest case yet of that proxy failing.
# Splitting by directory isolates that file's stage from the other three, which are small on
# any count (customMetadata's ~60 files are ~60 components, one per record; static resources
# and custom permissions are a handful each).
deploy_stage "Core (data model, custom metadata)" "packages/core/main/default/customMetadata" || exit $?
deploy_stage "Core (data model, labels)" "packages/core/main/default/labels" || exit $?
deploy_stage "Core (data model, static resources and custom permissions)" \
  "packages/core/main/default/staticresources" \
  "packages/core/main/default/customPermissions" \
  "packages/core/main/default/notificationtypes" || exit $?
deploy_stage "Core (Apex)" \
  "packages/core/main/default/classes" \
  "packages/core/main/default/triggers" \
  "packages/core/main/default/PlatformEventSubscriberConfigs" || exit $?
# After Apex, which a flow can call, and before the UI, which can launch a flow.
deploy_stage "Core (flows)" "packages/core/main/default/flows" || exit $?
deploy_stage "Core (UI and permissions)" \
  "packages/core/main/default/contentassets" \
  "packages/core/main/default/permissionsets" \
  "packages/core/main/default/permissionsetgroups" \
  "packages/core/main/default/layouts" \
  "packages/core/main/default/flexipages" \
  "packages/core/main/default/applications" \
  "packages/core/main/default/tabs" \
  "packages/core/main/default/quickActions" \
  "packages/core/main/default/lwc" \
  "packages/core/main/default/prompts" || exit $?

# A deployment is not an install, so CorePostInstall never runs and the org would start with
# every feature on before first-run setup, automatic households on, no nightly tab access check,
# no Automation switches or import templates, and nobody able to open BarnCRM Settings. This runs
# the same steps, as the person deploying. After the UI and permissions stage, because it gives
# that person the BarnCRM Admin permission set. Safe on an org that already has BarnCRM: one with
# saved settings or a household is treated as an upgrade, so nothing an administrator chose
# changes, and a second run changes nothing.
if [[ "$SOURCE_POST_INSTALL" == "1" ]]; then
  echo ""
  echo "== Running Core's post-install steps =="
  if ! printf '%s\n' 'CorePostInstall.runAsSourceDeploy();' | sf apex run --target-org "$ALIAS"; then
    echo "Core's post-install steps did not run. Run them by hand as anonymous Apex:"
    echo "  CorePostInstall.runAsSourceDeploy();"
  fi
fi

if [[ "$CORE_ONLY" -eq 0 ]]; then
  # The Rollup Builder module depends on Core only, and Giving depends on it (ADR-0125
  # 0125-rollup-builder-module.md), so it goes between them. --core-only leaves it out, which is
  # how a Core-only org (no rollup engine at all) is built.
  deploy_stage "Rollup Builder" "packages/rollups" || exit $?
  deploy_stage "Giving" "packages/giving" || exit $?
  # Volunteers depends on Core and the Rollup Builder module. While packages/volunteers holds
  # no metadata the stage is skipped (volunteers_has_metadata), so it costs nothing until PR4.
  if volunteers_has_metadata; then
    deploy_stage "Volunteers" "packages/volunteers" || exit $?
  else
    echo "== Skipping Volunteers: packages/volunteers holds no metadata yet =="
  fi
  # Mirror depends on Core and Giving (plan Section 4.1), so it goes last.
  deploy_stage "Mirror" "packages/mirror" || exit $?

  # A deployment is not an install, so no post-install script runs here and the shipped rollup
  # definitions would not exist in a development org (ADR-0029). This is the same call
  # RollupsPostInstall and GivingPostInstall make, run once the last stage is in, so a
  # development org holds the rollups a real install would have. It creates only what is
  # missing. A Core-only org has no engine, so there is nothing to call. The same step carries
  # over the rollup settings an org saved on Core before the module had its own settings object,
  # as RollupsPostInstall does at install, and gives an org with no Rollup Settings row one
  # holding the shipped defaults (Default Rollup Mode Both, processing Background).
  echo ""
  echo "== Creating the shipped rollup definitions =="
  if ! printf '%s\n' 'RollupsPostInstall.carryOverCoreSettings();' \
    'RollupsPostInstall.ensureSettingsRow();' 'RollupService.ensureDefaults();' |
    sf apex run --target-org "$ALIAS"; then
    echo "The rollup definitions were not created. Nothing else is affected: the Restore shipped"
    echo "rollups button in the Rollup Builder runs exactly the same step."
  fi

  # The same gap for every module's own post-install steps (Giving's starting fund, receipt
  # letters and import templates, each module's automation switches, its admin permission set
  # for the person deploying): a deployment runs no post-install. Each module's runSetup is
  # exactly what its install runs, safe on an org that already has them, and it records the
  # module in the setup marker so Health Check does not offer Finish Setup here (FS1). Skipped
  # with SOURCE_POST_INSTALL=0, because the Apex tests assume an org with no funds and no saved
  # BarnCRM Settings.
  if [[ "$SOURCE_POST_INSTALL" == "1" ]]; then
    SETUP_MODULES=(Rollups Giving)
    if volunteers_has_metadata; then
      SETUP_MODULES+=(Volunteers)
    fi
    SETUP_MODULES+=(Mirror)
    for module in "${SETUP_MODULES[@]}"; do
      echo ""
      echo "== Running the ${module} module's setup steps =="
      if ! printf '%s\n' "new ${module}PostInstall().runSetup(UserInfo.getUserId());" |
        sf apex run --target-org "$ALIAS"; then
        echo "The ${module} module's setup steps did not run. Run them from Health Check or the"
        echo "Modules page with Finish Setup, which runs exactly the same steps."
      fi
    done
  fi
fi

# The same gap for tabs: the five tool tabs live only in the BarnCRM_Tab_* permission sets, and
# a deployment runs no post-install, so users would not see them until TabAccessService next
# syncs. requestSync() queues that sync and never throws. It runs in Core, so --core-only
# keeps it.
echo ""
echo "== Queueing the tab access sync =="
if ! printf '%s\n' 'TabAccessService.requestSync();' | sf apex run --target-org "$ALIAS"; then
  echo "The tab access sync was not queued. Nothing else is affected: the nightly run syncs"
  echo "the tabs."
fi

if [[ "$CORE_ONLY" -eq 0 ]]; then
  # The same gap for the Rollup Builder permission sets (ADR-0125 D2): RollupsPostInstall gives
  # Rollup_Builder_Admin to BarnCRM_Admin holders and Rollup_Builder_User to BarnCRM_Staff and
  # BarnCRM_Read_Only holders, and a deployment runs no post-install, so administrators could not
  # open the Rollup Builder until the nightly run. requestSync() queues that sync and never
  # throws. --core-only leaves the module out, so it leaves this out too.
  echo ""
  echo "== Queueing the Rollup Builder access sync =="
  if ! printf '%s\n' 'RollupAccessSync.requestSync();' | sf apex run --target-org "$ALIAS"; then
    echo "The Rollup Builder access sync was not queued. Nothing else is affected: the nightly run"
    echo "syncs the access."
  fi

  # The same gap for the Volunteers permission sets (ADR-0127 decision 3): VolunteersPostInstall
  # gives each to its BarnCRM role, and a deployment runs no post-install.
  if volunteers_has_metadata; then
    echo ""
    echo "== Queueing the Volunteers access sync =="
    if ! printf '%s\n' 'new VolunteersAccessSync().requestSync();' | sf apex run --target-org "$ALIAS"; then
      echo "The Volunteers access sync was not queued. Nothing else is affected: the nightly access"
      echo "check syncs the access."
    fi
  fi
fi

echo ""
if [[ "$STALLS_RECOVERED" -gt 0 ]]; then
  echo "== ${STALLS_RECOVERED} stalled deploy(s) cancelled and resubmitted successfully =="
fi
echo "== Every stage deployed =="
