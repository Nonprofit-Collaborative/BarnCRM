#!/usr/bin/env bash
# scale-test-tier1.sh <alias>            load the tier 1 scale data and record what happened
# scale-test-tier1.sh cleanup <alias> [--keep-funds]
#                                        hard delete the scale data, children first
#
# The v0.11 tier 1 scale test (docs/contributor-guide/scale-and-mobile-test-plan.md): 8,000
# households, 20,000 contacts and 60,000 gifts, then their soft credits and allocations,
# loaded with Bulk API 2.0 with Automation Control left on. Per load it records rows,
# elapsed seconds, failed rows and the first error in a results file; before and after it
# records the org limits the plan names and the record counts.
#
# Refuses any alias other than oi-test unless SCALE_TEST_ALLOW=1. Take the shared org lock
# first and do not run the org test gate at the same time. Run it from a dedicated worktree.
# Needs: sf, jq, python3. Generates the CSVs itself (scripts/data/generate-scale-data.py).
# Needs a default fund on the org (sample data or the Setup Assistant supplies one): every
# gift gets an automatic allocation to it.
#
# Environment: SCALE_TEST_DIR (default scale-test-data/ in the repo, git-ignored),
#              SCALE_TEST_WAIT_MINUTES (per load, default 120),
#              SCALE_TEST_GENERATOR_ARGS (for example "--gifts 20000" to shrink the run).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GENERATOR="$REPO_ROOT/scripts/data/generate-scale-data.py"
DIR="${SCALE_TEST_DIR:-$REPO_ROOT/scale-test-data}"
WAIT="${SCALE_TEST_WAIT_MINUTES:-120}"
LIMITS="DataStorageMB DailyAsyncApexExecutions DailyBulkV2QueryJobs DailyApiRequests"

usage() {
  echo "Usage: scale-test-tier1.sh <org-alias>" >&2
  echo "       scale-test-tier1.sh cleanup <org-alias> [--keep-funds]" >&2
  exit 1
}

MODE="run"
if [[ "${1:-}" == "cleanup" ]]; then
  MODE="cleanup"
  shift
fi
ALIAS="${1:-}"
KEEP_FUNDS=0
[[ "${2:-}" == "--keep-funds" ]] && KEEP_FUNDS=1
[[ -z "$ALIAS" ]] && usage

if [[ "$ALIAS" != "oi-test" && "${SCALE_TEST_ALLOW:-}" != "1" ]]; then
  echo "Refusing to run against '$ALIAS': the scale test loads about 150,000 records and is only" >&2
  echo "for oi-test. Set SCALE_TEST_ALLOW=1 to override." >&2
  exit 1
fi
for tool in sf jq python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 1; }
done

mkdir -p "$DIR/work"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS="$DIR/results-$MODE-$ALIAS-$STAMP.md"

log() { printf '%s\n' "$*" | tee -a "$RESULTS"; }

record_limits() {
  log ""
  log "Org limits ($1):"
  local json
  json="$(sf org list limits --target-org "$ALIAS" --json 2>/dev/null)"
  for name in $LIMITS; do
    log "  $name: $(printf '%s' "$json" | jq -r --arg n "$name" \
      '.result[] | select(.name == $n) | "remaining \(.remaining) of \(.max)"')"
  done
}

count_of() {
  sf data query --target-org "$ALIAS" --query "$1" --json 2>/dev/null | jq -r '.result.totalSize // "?"'
}

record_counts() {
  log ""
  log "Record counts ($1):"
  log "  Account (scale households): $(count_of "SELECT COUNT() FROM Account WHERE Sample_Data_Key__c LIKE 'SCALE-H-%'")"
  log "  Contact (scale contacts):   $(count_of "SELECT COUNT() FROM Contact WHERE Sample_Data_Key__c LIKE 'SCALE-C-%'")"
  log "  Gift__c (scale gifts):      $(count_of "SELECT COUNT() FROM Gift__c WHERE External_Id__c LIKE 'SCALE-G-%'")"
  log "  Soft_Credit__c:             $(count_of "SELECT COUNT() FROM Soft_Credit__c WHERE Gift__r.External_Id__c LIKE 'SCALE-G-%'")"
  log "  Gift_Allocation__c:         $(count_of "SELECT COUNT() FROM Gift_Allocation__c WHERE Gift__r.External_Id__c LIKE 'SCALE-G-%'")"
}

# export_to <soql> <file>: a bulk export to CSV; leaves an empty file when nothing matches.
export_to() {
  rm -f "$2"
  sf data export bulk --target-org "$ALIAS" --query "$1" --output-file "$2" \
    --result-format csv --wait "$WAIT" >/dev/null 2>&1 || true
  [[ -f "$2" ]] || : >"$2"
}

# load <label> <sobject> <csv>: one Bulk API 2.0 ingest job, recorded in the results file.
load() {
  local label="$1" sobject="$2" file="$3" start end out job processed failed state id first
  log ""
  log "Load: $label ($sobject, $(($(wc -l <"$file") - 1)) rows in file)"
  start="$(date +%s)"
  out="$(sf data import bulk --sobject "$sobject" --file "$file" --target-org "$ALIAS" \
    --wait "$WAIT" --json 2>&1)"
  end="$(date +%s)"
  job="$(printf '%s' "$out" | jq -c '.result.jobInfo // .data.jobInfo // empty' 2>/dev/null)"
  if [[ -z "$job" ]]; then
    log "  FAILED to run: $(printf '%s' "$out" | jq -r '.message // empty' 2>/dev/null | head -c 400)"
    log "  elapsed: $((end - start)) s"
    return
  fi
  id="$(printf '%s' "$job" | jq -r '.id')"
  state="$(printf '%s' "$job" | jq -r '.state')"
  processed="$(printf '%s' "$job" | jq -r '.numberRecordsProcessed')"
  failed="$(printf '%s' "$job" | jq -r '.numberRecordsFailed')"
  first=""
  if [[ "$failed" != "0" && "$failed" != "null" ]]; then
    # The CLI writes <job id>-failed-records.csv into the current directory.
    ( cd "$DIR/work" && sf data bulk results --job-id "$id" --target-org "$ALIAS" --json >/dev/null 2>&1 )
    first="$(python3 - "$DIR/work" "$id" <<'PY'
import csv, glob, sys
for path in glob.glob("%s/*%s*failed*.csv" % (sys.argv[1], sys.argv[2])):
    with open(path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            print(row.get("sf__Error", "")[:400])
            sys.exit(0)
PY
)"
  fi
  log "  job: $id, state: $state"
  log "  rows processed: $processed, failed rows: $failed"
  log "  elapsed: $((end - start)) s"
  [[ -n "$first" ]] && log "  first error: $first"
}

generate() {
  # shellcheck disable=SC2086
  python3 "$GENERATOR" --tier1 --out-dir "$DIR" ${SCALE_TEST_GENERATOR_ARGS:-} 2>&1 | tee -a "$RESULTS"
  python3 "$GENERATOR" --import-file --out-dir "$DIR" | tee -a "$RESULTS"
}

resolve() { python3 "$GENERATOR" --resolve "$@" || exit 1; }

run() {
  log "BarnCRM tier 1 scale test load: org $ALIAS, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "Reminder: hold the org lock; no org test gate at the same time."
  generate
  record_limits "before"
  record_counts "before"

  load "funds" Fund__c "$DIR/funds.csv"

  # Households and contacts. Accounts and Contacts have no external id, so each load's keys
  # are exported and swapped for Ids before the file that refers to them.
  local rt
  rt="$(sf data query --target-org "$ALIAS" --json \
    --query "SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND DeveloperName = 'Household'" \
    | jq -r '.result.records[0].Id // empty')"
  [[ -z "$rt" ]] && { log "No Household record type on Account; stopping."; exit 1; }
  resolve "$DIR/households.csv" --out "$DIR/work/households.csv" --const "RecordTypeId=$rt"
  load "households" Account "$DIR/work/households.csv"

  export_to "SELECT Id, Sample_Data_Key__c FROM Account WHERE Sample_Data_Key__c LIKE 'SCALE-H-%'" \
    "$DIR/work/account-ids.csv"
  resolve "$DIR/contacts.csv" --out "$DIR/work/contacts.csv" --map "$DIR/work/account-ids.csv" \
    --key-col Household_Key --id-col AccountId
  load "contacts" Contact "$DIR/work/contacts.csv"

  export_to "SELECT Id, Sample_Data_Key__c FROM Contact WHERE Sample_Data_Key__c LIKE 'SCALE-C-%'" \
    "$DIR/work/contact-ids.csv"
  resolve "$DIR/gifts.csv" --out "$DIR/work/gifts.csv" --map "$DIR/work/contact-ids.csv" \
    --key-col Contact_Key --id-col Donor_Contact__c
  load "gifts" Gift__c "$DIR/work/gifts.csv"

  resolve "$DIR/soft_credits.csv" --out "$DIR/work/soft_credits.csv" \
    --map "$DIR/work/contact-ids.csv" --key-col Contact_Key --id-col Contact__c
  load "soft credits" Soft_Credit__c "$DIR/work/soft_credits.csv"
  load "allocations (second allocation on 5% of gifts)" Gift_Allocation__c "$DIR/allocations.csv"

  record_limits "after"
  record_counts "after"
  log ""
  log "Results file: $RESULTS"
  log "Next: the runs table in the plan. Then 'scale-test-tier1.sh cleanup $ALIAS'."
}

# delete_where <label> <sobject> <where clause>: bulk export the Ids, then hard delete them.
delete_where() {
  local file="$DIR/work/delete-$2.csv" n start end out
  export_to "SELECT Id FROM $2 WHERE $3" "$file"
  n=$(($(wc -l <"$file") - 1))
  if [[ "$n" -le 0 ]]; then
    log "  $1: nothing to delete"
    return
  fi
  start="$(date +%s)"
  out="$(sf data delete bulk --sobject "$2" --file "$file" --target-org "$ALIAS" --hard-delete \
    --wait "$WAIT" --json 2>&1)"
  end="$(date +%s)"
  log "  $1: $n Ids, $(printf '%s' "$out" | jq -r \
    '(.result.jobInfo // .data.jobInfo // {}) | "processed \(.numberRecordsProcessed), failed \(.numberRecordsFailed), state \(.state)"' \
    2>/dev/null || echo "no job info"), $((end - start)) s"
}

cleanup() {
  log "BarnCRM tier 1 scale test cleanup: org $ALIAS, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "Hard delete needs the Bulk API Hard Delete permission on the running user."
  record_counts "before cleanup"
  log ""
  # Children first: the master-detail rows, then gifts, then people, then households.
  delete_where "soft credits" Soft_Credit__c "Gift__r.External_Id__c LIKE 'SCALE-G-%'"
  delete_where "allocations (including the automatic ones)" Gift_Allocation__c \
    "Gift__r.External_Id__c LIKE 'SCALE-G-%'"
  delete_where "gifts" Gift__c "External_Id__c LIKE 'SCALE-G-%'"
  delete_where "contacts" Contact "Sample_Data_Key__c LIKE 'SCALE-C-%'"
  delete_where "households" Account "Sample_Data_Key__c LIKE 'SCALE-H-%'"
  if [[ "$KEEP_FUNDS" == "1" ]]; then
    log "  funds: kept (--keep-funds), needed by the import wizard file"
  else
    delete_where "funds" Fund__c "Accounting_Code__c LIKE 'SCALE-%'"
  fi
  record_counts "after cleanup"
  log ""
  log "Gifts the import wizard created are not touched here: undo that import batch in the"
  log "wizard. Rerun scripts/org/seed-sample-data.sh $ALIAS if the sample data was removed."
  log "Results file: $RESULTS"
}

if [[ "$MODE" == "cleanup" ]]; then
  cleanup
else
  run
fi
