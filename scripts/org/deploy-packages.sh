#!/usr/bin/env bash
# deploy-packages.sh <alias> [--core-only] [--full]
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
# Batch testing (D-141, 2026-10-28) made two more cuts that cost no coverage. Reports are polled
# every 5 seconds, not 15: a stage of a handful of components finished in a few seconds but was
# not seen as done until the first report, so every small stage cost about 17 seconds. And a
# stage that succeeded is no longer followed by a second, human-readable report call that lists
# every component (about 1 MB of log per run and one more CLI round trip per stage);
# DEPLOY_SHOW_COMPONENTS=1 brings it back. A failed stage still prints its full report.
#
# The D-141 amendment of 2026-10-28 (D-142) made three more cuts: Core's three config stages go
# in one request and every module in one request, each falling back to separate stages on the
# opaque failure only; and a package unchanged since the last successful deploy to the same org
# is not deployed again ("SKIPPING UNCHANGED PACKAGES" below; --full or DEPLOY_FULL=1 deploys
# everything). CONFIG_STAGES=separate and MODULE_STAGES=separate bring back the old stages.
#
# Usage: deploy-packages.sh <alias> [--core-only] [--full]
#
# Exit codes: 0 = every stage deployed, non-zero = the first stage that failed.

set -uo pipefail

STAGE_PAUSE_SECONDS="${STAGE_PAUSE_SECONDS:-0}"
DATA_MODEL_STAGES="${DATA_MODEL_STAGES:-combined}"
STALL_SECONDS="${STALL_SECONDS:-300}"
POLL_SECONDS="${POLL_SECONDS:-5}"
DEPLOY_SHOW_COMPONENTS="${DEPLOY_SHOW_COMPONENTS:-0}"
DEPLOY_WAIT_MINUTES="${DEPLOY_WAIT_MINUTES:-30}"
REPORT_TIMEOUT_SECONDS="${REPORT_TIMEOUT_SECONDS:-60}"
REPORT_FAILURE_LIMIT="${REPORT_FAILURE_LIMIT:-20}"
RETRY_BACKOFF_SECONDS="${RETRY_BACKOFF_SECONDS:-5}"
# 1 runs Core's post-install steps once Core is in (CorePostInstall.runAsSourceDeploy); 0 skips
# them. run-org-tests.sh passes 0: the Apex tests assume an org that has never saved BarnCRM
# Settings (they insert their own), and a test org marked as a new install has every feature off.
SOURCE_POST_INSTALL="${SOURCE_POST_INSTALL:-1}"
STALLS_RECOVERED=0

CONFIG_STAGES="${CONFIG_STAGES:-combined}"
MODULE_STAGES="${MODULE_STAGES:-combined}"
DEPLOY_FULL="${DEPLOY_FULL:-0}"
# 1 (the default) deploys every package's classes and triggers even when the package is unchanged,
# because the release gate's coverage check relies on that recompile. The incremental gate checks
# no coverage, so run-org-tests.sh passes 0 there.
DEPLOY_APEX_ALWAYS="${DEPLOY_APEX_ALWAYS:-1}"
DEPLOY_STATE_DIR="${DEPLOY_STATE_DIR:-${HOME}/.local/state/barncrm/deploy-state}"

ALIAS="${1:-}"
if [[ -z "$ALIAS" || "$ALIAS" == --* ]]; then
  echo "Usage: deploy-packages.sh <alias> [--core-only] [--full]" >&2
  exit 1
fi
shift || true

CORE_ONLY=0
ADOPT_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --core-only) CORE_ONLY=1 ;;
    --full) DEPLOY_FULL=1 ;;
    --adopt)
      ADOPT_ID="${2:-}"
      shift
      ;;
    *)
      echo "Unknown option ${1}. Usage: deploy-packages.sh <alias> [--core-only] [--full]" >&2
      exit 1
      ;;
  esac
  shift
done
for setting in "DATA_MODEL_STAGES:per-object|combined" "CONFIG_STAGES:separate|combined" \
  "MODULE_STAGES:separate|combined" "DEPLOY_APEX_ALWAYS:0|1" "DEPLOY_FULL:0|1"; do
  name="${setting%%:*}"
  if [[ ! "${!name}" =~ ^(${setting#*:})$ ]]; then
    echo "${name} must be one of ${setting#*:}, not ${!name}." >&2
    exit 1
  fi
done

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
  if [[ "${1:-}" == "--metadata-dir" ]]; then
    # A metadata-format package written for this run, such as the module tabs in the apps.
    # No --single-package: the CLI zips the folder itself, so package.xml is not at the zip
    # root and the API answers "No package.xml found" (oi-test gate, 2026-10-26).
    [[ -f "$2/package.xml" ]] && dirs=(--metadata-dir "$2")
  else
    for dir in "$@"; do
      if [[ -d "$dir" ]]; then
        dirs+=(--source-dir "$dir")
      fi
    done
  fi

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

  if [[ "$DEPLOY_SHOW_COMPONENTS" == "1" ]]; then
    sf project deploy report --job-id "$JOB_ID" --target-org "$ALIAS" || true
  fi
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

# True when the stage that just failed named no component: the platform's opaque
# UNKNOWN_EXCEPTION (or a stage that stalled twice), which is what a combined request falls back
# on. A failure that names components is a real error and is never retried in smaller stages. An
# unreadable report counts as a real error, so the run stops rather than guessing.
last_failure_opaque() {
  local errors
  [[ -n "$JOB_ID" ]] || return 1
  errors="$(sf project deploy report --job-id "$JOB_ID" --target-org "$ALIAS" --json 2> /dev/null \
    | jq -r '.result.numberComponentErrors // 0' 2> /dev/null)"
  [[ "$errors" =~ ^[0-9]+$ ]] && [[ "$errors" -eq 0 ]]
}

# SCHEDULED JOBS. Salesforce refuses to deploy a schedulable class that has a scheduled job
# ("This schedulable class has jobs pending or in progress") unless the org's DeploymentSettings
# doesSkipAsyncApexValidation is on. Post-install schedules the hourly "BarnCRM Tab Access Check"
# (TabAccessScheduler) in every org, and an administrator may schedule others (Error Digest,
# Import Row Cleanup, Seasonal Addresses, Rollups), so without this every upgrade deploy over a
# set-up org without that setting failed at the first Apex stage. The refusal is not only for the
# scheduled class itself: a validation on barn-platform (2026-10-29) that sent TabAccessService
# but not TabAccessScheduler was refused on TabAccessService, a class the job uses. So a job of
# any BarnCRM class can block any Apex stage (a module's job uses Core classes). Before each Apex
# stage, every live scheduled job whose class is in any of the packages is recorded and aborted,
# and straight after the stage (deployed or not) each is scheduled again under its own name and
# cron expression, so an administrator's schedule is kept. Post-install would schedule the Tab Access Check again even if
# that restore failed; it finds the restored one by name and does not double it. A job is
# restored with its class's no-argument constructor, so one that was scheduled with arguments
# (the Rollup Builder's one-off full run, the automation pause's resume job) comes back as the
# class's default run, or, with no such constructor, is named as not scheduled again.
PAUSED_JOBS_FILE=""
pause_scheduled_jobs() {
  local classes capture apex
  classes="$(find "$@" -name '*.cls' 2> /dev/null | sed -e 's#.*/##' -e 's/\.cls$//' | sort -u)"
  [[ -n "$classes" ]] || return 0
  capture="$(mktemp)"
  run_capped "$REPORT_TIMEOUT_SECONDS" "$capture" sf data query --target-org "$ALIAS" --json \
    --query "SELECT CronTriggerId, CronTrigger.CronJobDetail.Name, CronTrigger.CronExpression, CronTrigger.State, ApexClass.Name FROM AsyncApexJob WHERE JobType = 'ScheduledApex' AND CronTriggerId != null AND ApexClass.NamespacePrefix = null LIMIT 2000"
  PAUSED_JOBS_FILE="$(mktemp)"
  if ! python3 - "$capture" "$PAUSED_JOBS_FILE" "$classes" <<'PYEOF'; then
import json, sys
capture, out, classes = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
records = json.load(open(capture, encoding="utf-8"))["result"]["records"]
live = {"WAITING", "ACQUIRED", "EXECUTING", "PAUSED", "BLOCKED", "PAUSED_BLOCKED"}
seen, rows = set(), []
for r in records:
    trigger = r.get("CronTrigger") or {}
    cls = (r.get("ApexClass") or {}).get("Name")
    name = (trigger.get("CronJobDetail") or {}).get("Name")
    if r["CronTriggerId"] in seen or cls not in classes or trigger.get("State") not in live or not name:
        continue
    seen.add(r["CronTriggerId"])
    rows.append("\t".join([r["CronTriggerId"], name, trigger["CronExpression"], cls]))
open(out, "w", encoding="utf-8").write("".join(row + "\n" for row in rows))
PYEOF
    echo "== Could not read ${ALIAS}'s scheduled jobs; deploying without pausing them =="
    : > "$PAUSED_JOBS_FILE"
  fi
  rm -f "$capture"
  [[ -s "$PAUSED_JOBS_FILE" ]] || return 0
  echo "== Pausing scheduled jobs whose class this stage deploys: $(cut -f2 "$PAUSED_JOBS_FILE" | paste -sd, -) =="
  apex="$(cut -f1 "$PAUSED_JOBS_FILE" | sed "s/.*/System.abortJob('&');/")"
  if ! printf '%s\n' "$apex" | sf apex run --target-org "$ALIAS" > /dev/null; then
    echo "== The scheduled jobs could not be aborted; the stage may fail with \"jobs pending\" =="
  fi
}
restore_scheduled_jobs() {
  local apex output status
  [[ -n "$PAUSED_JOBS_FILE" && -s "$PAUSED_JOBS_FILE" ]] || { rm -f "$PAUSED_JOBS_FILE"; return 0; }
  # Each job in its own try, so one whose class is gone does not stop the others.
  apex="$(python3 - "$PAUSED_JOBS_FILE" <<'PYEOF'
import sys
q = lambda s: "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"
for line in open(sys.argv[1], encoding="utf-8"):
    _, name, cron, cls = line.rstrip("\n").split("\t")
    print("try { System.schedule(%s, %s, (Schedulable) Type.forName(%s).newInstance()); } "
          "catch (Exception e) { System.debug(LoggingLevel.ERROR, 'NOT_RESCHEDULED ' + %s + ': ' + e.getMessage()); }"
          % (q(name), q(cron), q(cls), q(name)))
PYEOF
)"
  echo "== Scheduling the paused jobs again: $(cut -f2 "$PAUSED_JOBS_FILE" | paste -sd, -) =="
  # A failure is caught in the Apex (an uncaught one would undo the jobs that did schedule), so
  # it is found in the log rather than by the exit status. Only a USER_DEBUG line counts: the
  # output also echoes the Apex source, which names NOT_RESCHEDULED on every line.
  output="$(printf '%s\n' "$apex" | sf apex run --target-org "$ALIAS" 2>&1)" && status=0 || status=$?
  if [[ "$status" -ne 0 ]] || grep -q "|USER_DEBUG|.*NOT_RESCHEDULED" <<< "$output"; then
    grep "|USER_DEBUG|.*NOT_RESCHEDULED" <<< "$output" | sed 's/.*NOT_RESCHEDULED/Not scheduled again:/'
    echo "Check Scheduled Jobs in Setup. To schedule a missing job again, run as anonymous Apex:"
    printf '%s\n' "$apex"
  fi
  rm -f "$PAUSED_JOBS_FILE"
  PAUSED_JOBS_FILE=""
}
# Ctrl-C, TERM, or any exit that happens while jobs are paused (a stage that failed, a command
# that errored between the pause and the restore) schedules them again once. The restore clears
# PAUSED_JOBS_FILE when it finishes, so a normal run, which has already restored, does nothing
# here. INT and TERM only turn into an exit, which runs the EXIT trap with the right status.
restore_if_still_paused() {
  local code=$?
  trap '' INT TERM
  trap - EXIT
  if [[ -n "$PAUSED_JOBS_FILE" && -s "$PAUSED_JOBS_FILE" ]]; then
    echo ""
    echo "== The deploy ended while scheduled jobs were paused =="
    restore_scheduled_jobs
  fi
  exit "$code"
}
trap 'exit 130' INT
trap 'exit 143' TERM
trap restore_if_still_paused EXIT

# SKIPPING UNCHANGED PACKAGES (D-141 amendment, 2026-10-28; D-56 allows "deploy only changed
# metadata"). A package whose source is identical to what the last successful run of this script
# put in this same org is not deployed again, except its Apex: run-org-tests.sh reads coverage
# from ApexCodeCoverageAggregate and relies on the deploy recompiling every class to clear it, so
# every package's classes and triggers deploy on every run.
#
# The record is one JSON file per org, named by the org id, in DEPLOY_STATE_DIR (default
# ~/.local/state/barncrm/deploy-state/<org id>.json): outside every repository and worktree, so
# all gate worktrees on this machine share it, and a fresh worktree does not lose it. It holds the
# org id, the git tree id of each deployed package, a fingerprint of the deploy inputs outside the
# packages (sfdx-project.json, .forceignore, scripts/org), and the id of the org's newest
# DeployRequest once the run finished. Any doubt means a full deploy:
#   - no record, an unreadable record, or one whose org id is not this org's;
#   - a different fingerprint (the stages or the project settings changed);
#   - a newer DeployRequest in the org than the one recorded: someone deployed something since,
#     from any machine or branch, so the org no longer holds what the record says;
#   - uncommitted or untracked changes under packages or the deploy inputs (the tree ids would not
#     describe what is deployed);
#   - DEPLOY_FULL=1 or --full.
# The record is deleted before the first stage and written only after every stage deployed, so a
# run that fails partway leaves none. Tree ids, not commit ids, are compared, so a commit that
# changes nothing in a package (docs, scripts/ci) does not count as a change to it.
DEPLOY_INPUTS=(sfdx-project.json .forceignore scripts/org)
SKIP_PACKAGES=" "
STATE_FILE=""
TREE_CLEAN=0

org_id() {
  local capture
  capture="$(mktemp)"
  run_capped "$REPORT_TIMEOUT_SECONDS" "$capture" sf org display --target-org "$ALIAS" --json
  jq -r '.result.id // empty' "$capture" 2> /dev/null
  rm -f "$capture"
}

newest_deploy_request() {
  local capture
  capture="$(mktemp)"
  run_capped "$REPORT_TIMEOUT_SECONDS" "$capture" sf data query --use-tooling-api --target-org "$ALIAS" --json \
    --query "SELECT Id FROM DeployRequest ORDER BY CreatedDate DESC LIMIT 1"
  jq -r '.result.records[0].Id // empty' "$capture" 2> /dev/null
  rm -f "$capture"
}

deploy_fingerprint() {
  local input
  for input in "${DEPLOY_INPUTS[@]}"; do
    git rev-parse "HEAD:${input}" 2> /dev/null || echo "missing:${input}"
  done | paste -sd, -
}

# Prints "name=tree" for every package directory in the repository.
package_trees() {
  local dir
  for dir in packages/*/; do
    dir="$(basename "$dir")"
    echo "${dir}=$(git rev-parse "HEAD:packages/${dir}" 2> /dev/null)"
  done
}

package_skipped() {
  [[ "$SKIP_PACKAGES" == *" $1 "* ]]
}

decide_skips() {
  local id newest dirty
  id="$(org_id)"
  if [[ -n "$id" ]]; then
    STATE_FILE="${DEPLOY_STATE_DIR}/${id}.json"
  fi
  dirty="$(git status --porcelain -- packages "${DEPLOY_INPUTS[@]}" 2> /dev/null || echo unknown)"
  [[ -z "$dirty" ]] && TREE_CLEAN=1
  if [[ -z "$STATE_FILE" ]]; then
    echo "== Full deploy: could not read the org id of ${ALIAS}, so no deploy record applies =="
    return 0
  fi
  if [[ "$TREE_CLEAN" -ne 1 ]]; then
    echo "== Full deploy: uncommitted or untracked changes under packages or the deploy inputs; no record will be kept =="
  elif [[ "$DEPLOY_FULL" == "1" ]]; then
    echo "== Full deploy: requested (--full or DEPLOY_FULL=1) =="
  elif [[ ! -f "$STATE_FILE" ]]; then
    echo "== Full deploy: no deploy record for this org (${STATE_FILE}) =="
  else
    newest="$(newest_deploy_request)"
    SKIP_PACKAGES=" $(python3 - "$STATE_FILE" "$id" "$(deploy_fingerprint)" "$newest" \
      $(package_trees) <<'PYEOF' 2> /dev/null
import json, sys
state_file, org, fingerprint, newest = sys.argv[1:5]
try:
    rec = json.load(open(state_file, encoding="utf-8"))
    ok = (newest and rec["orgId"] == org and rec["fingerprint"] == fingerprint
          and rec["lastDeployRequest"] == newest and isinstance(rec["packages"], dict))
except Exception:
    ok = False
if not ok:
    sys.exit(0)
skip = []
for pair in sys.argv[5:]:
    name, _, tree = pair.partition("=")
    if tree and rec["packages"].get(name) == tree:
        skip.append(name)
print(" ".join(skip))
PYEOF
    ) "
    if [[ "$SKIP_PACKAGES" == " " ]]; then
      echo "== Full deploy: the deploy record does not match this org's current state, or every package changed =="
    else
      echo "== Unchanged since the last deploy to this org, so only their Apex deploys:${SKIP_PACKAGES}=="
    fi
  fi
  # Deleted before the first stage, so a run that fails partway leaves no record behind.
  rm -f "$STATE_FILE"
}

# Called once every stage has deployed. Records the packages this run left in the org (deployed in
# full, or unchanged and so already there). A failed lookup writes nothing: the next run deploys
# everything.
write_deploy_record() {
  local newest recorded=("$@") tmp
  [[ -n "$STATE_FILE" && "$TREE_CLEAN" -eq 1 ]] || return 0
  newest="$(newest_deploy_request)"
  if [[ -z "$newest" ]]; then
    echo "== No deploy record kept: the org's newest DeployRequest could not be read =="
    return 0
  fi
  mkdir -p "$DEPLOY_STATE_DIR" || return 0
  tmp="$(mktemp "${DEPLOY_STATE_DIR}/.record.XXXXXX")" || return 0
  if python3 - "$tmp" "$(basename "$STATE_FILE" .json)" "$ALIAS" "$(git rev-parse HEAD)" \
    "$(deploy_fingerprint)" "$newest" $(package_trees) "${recorded[@]/#/only=}" <<'PYEOF'; then
import datetime, json, sys
out, org, alias, commit, fingerprint, newest = sys.argv[1:7]
trees, only = {}, set()
for arg in sys.argv[7:]:
    key, _, value = arg.partition("=")
    if key == "only":
        only.add(value)
    else:
        trees[key] = value
json.dump({
    "orgId": org, "alias": alias, "commit": commit, "fingerprint": fingerprint,
    "lastDeployRequest": newest,
    "recordedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "packages": {k: v for k, v in trees.items() if k in only and v},
}, open(out, "w", encoding="utf-8"), indent=2)
PYEOF
    mv -f "$tmp" "$STATE_FILE" && echo "== Deploy record written: ${STATE_FILE} =="
  else
    rm -f "$tmp"
  fi
}

# deploy-packages.sh <alias> --adopt <deploy id>: for use after a deploy that resends Apex already
# in the org from the same commit (and is rolled back whole if a test fails), so the org still
# holds what the record says. No gate calls it now: the incremental gate runs its tests with
# `sf apex run test` and deploys nothing after the staged deploy. The record takes that
# deploy id as its newest only when the org's two newest DeployRequests are exactly that deploy
# and the one recorded: anything else came in between, and the record is deleted.
adopt_deploy() {
  local id org capture ids
  org="$(org_id)"
  [[ -n "$org" ]] || return 0
  STATE_FILE="${DEPLOY_STATE_DIR}/${org}.json"
  [[ -f "$STATE_FILE" ]] || return 0
  capture="$(mktemp)"
  run_capped "$REPORT_TIMEOUT_SECONDS" "$capture" sf data query --use-tooling-api --target-org "$ALIAS" --json \
    --query "SELECT Id FROM DeployRequest ORDER BY CreatedDate DESC LIMIT 2"
  ids="$(jq -r '[.result.records[].Id] | join(" ")' "$capture" 2> /dev/null)"
  rm -f "$capture"
  if python3 - "$STATE_FILE" "$org" "$1" $ids <<'PYEOF'; then
import json, os, sys
state_file, org, adopted = sys.argv[1:4]
ids = sys.argv[4:]
same = lambda a, b: bool(a) and bool(b) and a[:15] == b[:15]
rec = json.load(open(state_file, encoding="utf-8"))
if not (len(ids) == 2 and rec["orgId"] == org and same(ids[0], adopted)
        and same(ids[1], rec["lastDeployRequest"])):
    sys.exit(1)
rec["lastDeployRequest"] = ids[0]
tmp = state_file + ".tmp"
json.dump(rec, open(tmp, "w", encoding="utf-8"), indent=2)
os.replace(tmp, state_file)
PYEOF
    echo "== Deploy record kept: ${ALIAS}'s newest deploy is the gate's own test deploy =="
  else
    rm -f "$STATE_FILE"
    echo "== Deploy record removed: another deploy reached ${ALIAS}, so the next run deploys everything =="
  fi
}
if [[ -n "$ADOPT_ID" ]]; then
  adopt_deploy "$ADOPT_ID"
  exit 0
fi

# Every folder under Core's main/default has to be named by a stage below. A folder no stage
# names never reaches the org, so nothing that depends on it is ever tested: Core's flows went
# undeployed this way until 2026-10-13.
CORE_DIR="packages/core/main/default"
CORE_STAGED=(objects customMetadata labels staticresources customPermissions notificationtypes
  externalCredentials classes triggers contentassets permissionsets permissionsetgroups layouts flexipages applications
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
deploy_data_model() {
  if [[ "$DATA_MODEL_STAGES" == "combined" ]]; then
    # One request for every object. A failure that names components is a real error and stops
    # the run; one that names none is the opaque platform fault, so the objects go again one by one.
    if ! deploy_stage "Core (data model, every object in one request)" "$OBJECTS_DIR"; then
      last_failure_opaque || return 1
      echo "== The one-request data model deploy failed with no component error. Falling back to one object per stage =="
      deploy_objects_one_by_one || return $?
    fi
  else
    deploy_objects_one_by_one || return $?
  fi
}

# HISTORY OF THE CONFIG STAGES. Config was one stage per directory, as below, until 2026-10-28.
# Since then (D-141 amendment) the three go in one request by default (CONFIG_STAGES=combined),
# falling back to the three stages only on the opaque failure, as the data model does: both
# faults that justified the split were later traced to real defects. CONFIG_STAGES=separate
# brings back the three stages from the start.
#
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
deploy_config_separately() {
  deploy_stage "Core (data model, custom metadata)" "${CORE_DIR}/customMetadata" || return $?
  deploy_stage "Core (data model, labels)" "${CORE_DIR}/labels" || return $?
  deploy_stage "Core (data model, static resources and custom permissions)" \
    "${CORE_DIR}/staticresources" \
    "${CORE_DIR}/customPermissions" \
    "${CORE_DIR}/notificationtypes" \
    "${CORE_DIR}/externalCredentials" || return $?
}
deploy_config() {
  if [[ "$CONFIG_STAGES" == "combined" ]]; then
    if ! deploy_stage "Core (config: custom metadata, labels, static resources, custom permissions, notification types)" \
      "${CORE_DIR}/customMetadata" "${CORE_DIR}/labels" "${CORE_DIR}/staticresources" \
      "${CORE_DIR}/customPermissions" "${CORE_DIR}/notificationtypes" \
      "${CORE_DIR}/externalCredentials"; then
      last_failure_opaque || return 1
      echo "== The one-request config deploy failed with no component error. Falling back to three stages =="
      deploy_config_separately || return $?
    fi
  else
    deploy_config_separately || return $?
  fi
}

# Classes and triggers of a package, the part that deploys even when the package is unchanged.
apex_dirs() {
  local dir
  for dir in classes triggers PlatformEventSubscriberConfigs; do
    [[ -d "packages/$1/main/default/${dir}" ]] && echo "packages/$1/main/default/${dir}"
  done
}

decide_skips
# The packages whose source this run leaves in the org, for the deploy record.
RECORD_PACKAGES=(core)

if package_skipped core; then
  echo ""
  echo "== Core is unchanged since the last deploy to ${ALIAS}: skipping every Core stage but Apex =="
else
  deploy_data_model || exit $?
  deploy_config || exit $?
fi
if ! package_skipped core || [[ "$DEPLOY_APEX_ALWAYS" == "1" ]]; then
  pause_scheduled_jobs packages/*/main/default/classes
  deploy_stage "Core (Apex)" \
    "${CORE_DIR}/classes" \
    "${CORE_DIR}/triggers" \
    "${CORE_DIR}/PlatformEventSubscriberConfigs" && status=0 || status=$?
  restore_scheduled_jobs
  [[ "$status" -eq 0 ]] || exit "$status"
fi
if ! package_skipped core; then
  # After Apex, which a flow can call, and before the UI, which can launch a flow.
  deploy_stage "Core (flows)" "${CORE_DIR}/flows" || exit $?
  deploy_stage "Core (UI and permissions)" \
    "${CORE_DIR}/contentassets" \
    "${CORE_DIR}/permissionsets" \
    "${CORE_DIR}/permissionsetgroups" \
    "${CORE_DIR}/layouts" \
    "${CORE_DIR}/flexipages" \
    "${CORE_DIR}/applications" \
    "${CORE_DIR}/tabs" \
    "${CORE_DIR}/quickActions" \
    "${CORE_DIR}/lwc" \
    "${CORE_DIR}/prompts" || exit $?
fi

# A deployment is not an install, so CorePostInstall never runs and the org would start with
# every feature on before first-run setup, automatic households on, no hourly tab access check,
# no Automation switches or import templates, and nobody able to open BarnCRM Settings. This runs
# the same steps, as the person deploying. After the UI and permissions stage, because that is
# where the BarnCRM Admin permission set this person is given first arrives. Safe on an org that already has BarnCRM: one with
# saved settings or a household is treated as an upgrade, so nothing an administrator chose
# changes, and a second run changes nothing.
if [[ "$SOURCE_POST_INSTALL" == "1" ]]; then
  # The person deploying needs Manage BarnCRM Settings before the steps run, not after. The
  # steps can only queue the BarnCRM Admin grant (a setup object write cannot share their
  # transaction), so on a first deploy every settings save in them (coexistence mode, the
  # organization record type, the new-install feature list, each module's setup) was refused
  # with "You need the Manage BarnCRM Settings permission" and left in the Error Log. Assigned
  # here, in its own transaction; an assignment already held is reported as a duplicate.
  echo ""
  echo "== Giving the person deploying the BarnCRM Admin permission set =="
  output="$(sf org assign permset --name BarnCRM_Admin --target-org "$ALIAS" 2>&1)" && status=0 || status=$?
  if grep -q "Duplicate PermissionSetAssignment" <<< "$output"; then
    echo "Already assigned: BarnCRM_Admin"
  elif [[ "$status" -ne 0 ]]; then
    echo "$output"
    echo "BarnCRM_Admin was not assigned, so the post-install steps below may log permission errors."
  fi
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
  #
  # FEWER MODULE STAGES (D-141 amendment, 2026-10-28). By default (MODULE_STAGES=combined) every
  # module goes in one request: the Metadata API orders the components of one request itself. On
  # the opaque failure (no component error) the modules go again one per stage, in dependency
  # order; a failure that names components stops the run. MODULE_STAGES=separate deploys one per
  # stage from the start. A module unchanged since the last deploy to this org sends only its
  # Apex (or nothing, with DEPLOY_APEX_ALWAYS=0).
  # Volunteers depends on Core and the Rollup Builder module. While packages/volunteers holds
  # no metadata it is left out (volunteers_has_metadata).
  MODULES=(rollups giving)
  if volunteers_has_metadata; then
    MODULES+=(volunteers)
  else
    echo "== Skipping Volunteers: packages/volunteers holds no metadata yet =="
  fi
  # Logic Models depends on Core only (ADR-NEXT, logic models module).
  MODULES+=(logicmodels)
  # Mirror depends on Core and Giving (plan Section 4.1), so it goes last.
  MODULES+=(mirror)
  RECORD_PACKAGES+=("${MODULES[@]}")
  module_dirs() {
    if ! package_skipped "$1"; then
      echo "packages/$1"
    elif [[ "$DEPLOY_APEX_ALWAYS" == "1" ]]; then
      apex_dirs "$1"
    fi
  }
  deploy_modules_separately() {
    local module dirs
    for module in "${MODULES[@]}"; do
      dirs=()
      while IFS= read -r dir; do [[ -n "$dir" ]] && dirs+=("$dir"); done < <(module_dirs "$module")
      if [[ ${#dirs[@]} -eq 0 ]]; then
        echo "== Skipping module ${module}: unchanged since the last deploy to ${ALIAS} =="
        continue
      fi
      deploy_stage "Module ${module}" "${dirs[@]}" || return $?
    done
  }
  deploy_modules() {
    if [[ "$MODULE_STAGES" == "combined" ]]; then
      ALL_MODULE_DIRS=()
      for module in "${MODULES[@]}"; do
        while IFS= read -r dir; do [[ -n "$dir" ]] && ALL_MODULE_DIRS+=("$dir"); done < <(module_dirs "$module")
      done
      if [[ ${#ALL_MODULE_DIRS[@]} -eq 0 ]]; then
        echo "== Skipping the modules: every one is unchanged since the last deploy to ${ALIAS} =="
      elif ! deploy_stage "Modules (${MODULES[*]}) in one request" "${ALL_MODULE_DIRS[@]}"; then
        last_failure_opaque || return 1
        echo "== The one-request module deploy failed with no component error. Falling back to one module per stage =="
        deploy_modules_separately || return $?
      fi
    else
      deploy_modules_separately || return $?
    fi
  }
  # A scheduled job (the Rollup Builder's "BarnCRM Rollups", Giving's acknowledgments) blocks a
  # module's deploy as Core's does, so the jobs are paused around the module stages the same way
  # (see SCHEDULED JOBS). Post-install has rescheduled the Tab Access Check by now.
  pause_scheduled_jobs packages/*/main/default/classes
  deploy_modules && status=0 || status=$?
  restore_scheduled_jobs
  [[ "$status" -eq 0 ]] || exit "$status"

  # Core may not name a module's tab in its own apps (a Core-only deploy would fail on the
  # missing tab, ADR-0013), so each deployed module's tabs join the BarnCRM apps here, from its
  # BarnCRM_Module__mdt record (ADR-0137). The app
  # copies are written to a temporary metadata-format package; the repository's app files are
  # never changed. Nothing is deployed when no module names a tab.
  deployed_modules=(rollups giving mirror logicmodels)
  volunteers_has_metadata && deployed_modules+=(volunteers)
  APP_TABS_DIR="$(mktemp -d)"
  python3 scripts/org/module-app-tabs.py "$APP_TABS_DIR" "${deployed_modules[@]}" || exit 1
  deploy_stage "Module tabs in the BarnCRM apps" --metadata-dir "$APP_TABS_DIR" || exit $?
  rm -rf "$APP_TABS_DIR"

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
    SETUP_MODULES+=(LogicModels Mirror)
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

  # The same gap for the Logic Models permission sets (ADR-NEXT, logic models module, decision 7).
  echo ""
  echo "== Queueing the Logic Models access sync =="
  if ! printf '%s\n' 'new LogicModelsAccessSync().requestSync();' | sf apex run --target-org "$ALIAS"; then
    echo "The Logic Models access sync was not queued. Nothing else is affected: the hourly access"
    echo "check syncs the access."
  fi
fi

echo ""
if [[ "$STALLS_RECOVERED" -gt 0 ]]; then
  echo "== ${STALLS_RECOVERED} stalled deploy(s) cancelled and resubmitted successfully =="
fi
echo "== Every stage deployed =="
write_deploy_record "${RECORD_PACKAGES[@]}"
