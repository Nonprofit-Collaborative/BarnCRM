#!/usr/bin/env bash
# scale-test-tier1.sh <alias>            load the tier 1 scale data and record what happened
# scale-test-tier1.sh cleanup <alias> [--keep-funds]
#                                        hard delete the scale data, children first
#
# The v0.11 tier 1 scale test (docs/contributor-guide/scale-and-mobile-test-plan.md): 4,000
# households, 10,000 contacts and 30,000 gifts, then their soft credits, then a 70/30 split
# of 5% of the gifts across two funds (anonymous Apex, because Giving refuses a gift whose
# allocations do not total it, so a second allocation cannot be Bulk loaded). Loads use
# Bulk API 2.0 with Automation Control left on. Per load it records the job id, rows
# processed and failed (from `sf data bulk results`), elapsed seconds and the top error
# messages with counts; failed rows are saved under the work dir. Before and after it
# records the org limits the plan names and the record counts.
#
# Refuses any alias other than oi-test unless SCALE_TEST_ALLOW=1. Take the shared org lock
# first and do not run the org test gate at the same time. Run it from a dedicated worktree.
# Needs: sf, jq, python3. Generates the CSVs itself (scripts/data/generate-scale-data.py).
# Every gift gets an automatic allocation to the default fund. If the org has none, the
# generated "Scale test General" fund is loaded as the default; if its default resolves (an
# active fund the Giving settings point at), that stays the default. Cleanup never deletes
# the default fund (the next run reuses it).
#
# Environment: SCALE_TEST_DIR (default scale-test-data/ in the repo, git-ignored),
#              SCALE_TEST_WAIT_MINUTES (per load, default 120),
#              SCALE_TEST_GENERATOR_ARGS (for example "--gifts 20000" to shrink the run),
#              SCALE_TEST_SOFT_DELETE=1 (cleanup without --hard-delete, to the Recycle Bin,
#              for a user without the Bulk API Hard Delete permission),
#              SCALE_TEST_HARD_DELETE=1 (force hard delete; fail instead of falling back),
#              SCALE_TEST_ALLOW_EXISTING=1 (load even when scale records already exist).
# Cleanup tries hard delete first; if the first delete fails with HardDeletePermissionError
# it logs that and soft deletes (Recycle Bin) for that step and the rest.
# The load refuses to start when scale households, contacts or gifts already exist: run
# cleanup first.
# Exit status: nonzero when cleanup deletes nothing or leaves scale records behind.

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
  echo "Refusing to run against '$ALIAS': the scale test loads about 78,500 records and is only" >&2
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
  sf data query --target-org "$ALIAS" --query "$1" --json 2>/dev/null </dev/null | jq -r '.result.totalSize // "?"'
}

# record_counts <when>: logs the scale record counts; SCALE_REMAINING is left holding their
# sum, or -1 when a count could not be read (cleanup treats that as not clean).
SCALE_REMAINING=0
record_counts() {
  log ""
  log "Record counts ($1):"
  local label query n sum=0
  while IFS='|' read -r label query; do
    n="$(count_of "$query")"
    log "  $label $n"
    if [[ "$n" =~ ^[0-9]+$ ]]; then sum=$((sum + n)); else sum=-1000000000; fi
  done <<'EOF'
Account (scale households):|SELECT COUNT() FROM Account WHERE Sample_Data_Key__c LIKE 'SCALE-H-%'
Contact (scale contacts):  |SELECT COUNT() FROM Contact WHERE Sample_Data_Key__c LIKE 'SCALE-C-%'
Gift__c (scale gifts):     |SELECT COUNT() FROM Gift__c WHERE External_Id__c LIKE 'SCALE-G-%'
Soft_Credit__c:            |SELECT COUNT() FROM Soft_Credit__c WHERE Gift__r.External_Id__c LIKE 'SCALE-G-%'
Gift_Allocation__c:        |SELECT COUNT() FROM Gift_Allocation__c WHERE Gift__r.External_Id__c LIKE 'SCALE-G-%'
EOF
  if [[ "$sum" -lt 0 ]]; then SCALE_REMAINING=-1; else SCALE_REMAINING="$sum"; fi
}

# job_error_hint <text>: a hint when the error text points at the hard delete permission.
job_error_hint() {
  if grep -qiE 'hard.?delete|INSUFFICIENT_ACCESS|not authorized|insufficient access|permission' <<< "$1"; then
    log "  HINT: this looks like a permission problem. Hard delete needs the Bulk API Hard Delete"
    log "  permission on the running user (a profile or permission set system permission that is"
    log "  off by default, even for System Administrators). Grant it, or rerun cleanup with"
    log "  SCALE_TEST_SOFT_DELETE=1 to delete to the Recycle Bin instead."
  fi
}

# job_report <label> <sf --json output file> [verb]: reads the job id, asks
# `sf data bulk results` for the real counts and the failed rows, and logs them. Sets
# JOB_OK (1 when a job ran), JOB_PROCESSED, JOB_FAILED, JOB_SUCCESS (numbers, 0 when unknown).
# The CLI returns .result.jobId (import) or .result.jobInfo.id (bulk delete) on success and
# exits nonzero with the same under .data on partial failure.
JOB_OK=0 JOB_PROCESSED=0 JOB_FAILED=0 JOB_SUCCESS=0
job_report() {
  local label="$1" outfile="$2" id msg res failed_csv slug errors
  JOB_OK=0 JOB_PROCESSED=0 JOB_FAILED=0 JOB_SUCCESS=0
  id="$(jq -r '.result.jobId // .result.jobInfo.id // .data.jobId // .data.jobInfo.id // empty' "$outfile" 2>/dev/null)"
  if [[ -z "$id" ]]; then
    msg="$(jq -r '[.name, .message] | map(select(. != null)) | join(": ")' "$outfile" 2>/dev/null)"
    [[ -z "$msg" ]] && msg="$(head -c 400 "$outfile")"
    log "  FAILED to run (no job id): $(printf '%s' "$msg" | head -c 600)"
    job_error_hint "$msg"
    return
  fi
  JOB_OK=1
  log "  job: $id, state: $(jq -r '.data.state // .result.state // .result.jobInfo.state // .data.jobInfo.state // "see results"' "$outfile" 2>/dev/null)"
  # The CLI writes <job id>-success-records.csv and -failed-records.csv into the current dir.
  res="$( cd "$DIR/work" && sf data bulk results --job-id "$id" --target-org "$ALIAS" --json 2>&1 )"
  if ! printf '%s' "$res" | jq -e '.result' >/dev/null 2>&1; then
    log "  could not read the job results: $(printf '%s' "$res" | jq -r '.message // empty' 2>/dev/null | head -c 400)"
    JOB_FAILED=-1
    return
  fi
  JOB_PROCESSED="$(printf '%s' "$res" | jq -r '.result.processedRecords // 0')"
  JOB_SUCCESS="$(printf '%s' "$res" | jq -r '.result.successfulRecords // 0')"
  JOB_FAILED="$(printf '%s' "$res" | jq -r '.result.failedRecords // 0')"
  log "  rows processed: $JOB_PROCESSED, succeeded: $JOB_SUCCESS, failed: $JOB_FAILED"
  if [[ "$JOB_FAILED" != "0" ]]; then
    slug="$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '-')"
    failed_csv="$(ls "$DIR"/work/*"$id"*failed*.csv 2>/dev/null | head -n 1)"
    if [[ -n "$failed_csv" ]]; then
      cp "$failed_csv" "$DIR/work/failed-$slug.csv"
      log "  failed rows saved: $DIR/work/failed-$slug.csv"
      errors="$(python3 - "$failed_csv" <<'PY'
import collections, csv, sys
counts = collections.Counter()
with open(sys.argv[1], newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        counts[row.get("sf__Error", "").strip()[:200] or "(no message)"] += 1
for message, n in counts.most_common(5):
    print("    %6d x %s" % (n, message))
PY
)"
      log "  top errors:"
      log "$errors"
      job_error_hint "$errors"
    else
      log "  no failed-rows file found for job $id in $DIR/work"
    fi
  fi
}

# export_to <soql> <file>: a bulk export to CSV; leaves an empty file when nothing matches.
export_to() {
  local msg
  rm -f "$2"
  if ! msg="$(sf data export bulk --target-org "$ALIAS" --query "$1" --output-file "$2" \
    --result-format csv --wait "$WAIT" --json 2>&1 </dev/null)"; then
    log "  EXPORT FAILED ($1): $(printf '%s' "$msg" | jq -r '.message // empty' 2>/dev/null | head -c 300)"
  fi
  [[ -f "$2" ]] || : >"$2"
}

# load <label> <sobject> <csv>: one Bulk API 2.0 ingest job, recorded in the results file.
load() {
  local label="$1" sobject="$2" file="$3" start end outfile
  outfile="$DIR/work/last-load.json"
  log ""
  log "Load: $label ($sobject, $(($(wc -l <"$file") - 1)) rows in file)"
  start="$(date +%s)"
  # A partial failure exits nonzero but still prints the job in .data; both are read below.
  sf data import bulk --sobject "$sobject" --file "$file" --target-org "$ALIAS" \
    --wait "$WAIT" --json >"$outfile" 2>"$DIR/work/last-load.err" </dev/null
  end="$(date +%s)"
  job_report "$label" "$outfile"
  log "  elapsed: $((end - start)) s"
}

# split_gifts: the 5% two fund split. Giving refuses any save that leaves a gift's
# allocations not totalling the gift, and it checks after every DML statement (a mixed
# upsert too). Each generated script (about 200 gifts) pauses the Gift_Allocation_Totals
# automation, cuts the default allocation to 70% and adds the 30% row, then checks every gift
# with GiftService.validateAllocations and rolls the chunk back on any problem. The scripts
# print a SCALE_SPLIT line with the counts, collected here.
# split_field <line> <name>: the value after "name=" up to the next space ("" when absent).
split_field() {
  local rest="${1#*"$2"=}"
  [[ "$rest" == "$1" ]] && return
  printf '%s' "${rest%% *}"
}

split_gifts() {
  local script out start end line requested=0 skipped=0 rows=0 failed=0 first="" n=0 value
  log ""
  log "Split: second allocation (30%) on 5% of gifts, default allocation cut to 70%"
  start="$(date +%s)"
  for script in "$DIR"/split-apex/split-*.apex; do
    [[ -f "$script" ]] || continue
    n=$((n + 1))
    out="$DIR/work/last-split.json"
    sf apex run --file "$script" --target-org "$ALIAS" --json >"$out" 2>/dev/null </dev/null
    if [[ "$(jq -r '.result.success // false' "$out" 2>/dev/null)" != "true" ]]; then
      log "  $(basename "$script"): FAILED: $(jq -r '[.result.compileProblem, .result.exceptionMessage, .message] | map(select(. != null and . != "")) | join(" / ")' "$out" 2>/dev/null | head -c 500)"
      failed=$((failed + 1))
      continue
    fi
    # Only the USER_DEBUG line: the log also echoes the source line of the script.
    line="$(jq -r '.result.logs // ""' "$out" | grep 'USER_DEBUG.*SCALE_SPLIT ' | head -n 1)"
    line="${line#*SCALE_SPLIT }"
    if [[ -z "$line" ]]; then
      log "  $(basename "$script"): ran, but printed no SCALE_SPLIT line (log level?)"
      continue
    fi
    local v_req v_skip v_rows v_fail
    v_req="$(split_field "$line" requested)"; v_skip="$(split_field "$line" skipped)"
    v_rows="$(split_field "$line" rows)"; v_fail="$(split_field "$line" failedRows)"
    if [[ ! "$v_req" =~ ^[0-9]+$ || ! "$v_skip" =~ ^[0-9]+$ || ! "$v_rows" =~ ^[0-9]+$ || ! "$v_fail" =~ ^[0-9]+$ ]]; then
      log "  $(basename "$script"): FAILED: unreadable SCALE_SPLIT line: $(printf '%s' "$line" | head -c 200)"
      failed=$((failed + 1))
      continue
    fi
    requested=$((requested + v_req)); skipped=$((skipped + v_skip))
    rows=$((rows + v_rows)); failed=$((failed + v_fail))
    value="${line#*firstError=}"
    [[ "$value" == "$line" ]] && value=""
    [[ -z "$first" && -n "$value" ]] && first="$value"
  done
  end="$(date +%s)"
  log "  scripts run: $n, gifts requested: $requested, skipped (not loaded or not one allocation): $skipped"
  log "  allocation rows saved or attempted: $rows, failed rows or scripts: $failed"
  [[ -n "$first" ]] && log "  first error: $(printf '%s' "$first" | head -c 400)"
  log "  elapsed: $((end - start)) s"
}

generate() {
  local extra=""
  # A second default fund would move the org's default and rewrite Giving settings.
  [[ "${ORG_HAS_DEFAULT:-0}" == "1" ]] && extra="--no-default-fund"
  local code
  for code in ${SKIP_FUND_CODES:-}; do extra="$extra --skip-fund-code $code"; done
  # shellcheck disable=SC2086
  python3 "$GENERATOR" --tier1 --out-dir "$DIR" $extra ${SCALE_TEST_GENERATOR_ARGS:-} 2>&1 | tee -a "$RESULTS"
  python3 "$GENERATOR" --import-file --out-dir "$DIR" | tee -a "$RESULTS"
}

# resolve <in> --out <file> ...: the generator's resolve step. It reports how many rows it
# dropped (a parent that did not load); both its lines go into the results file.
resolve() {
  local note
  log ""
  log "Resolve: $(basename "$1")"
  note="$(python3 "$GENERATOR" --resolve "$@" 2>&1)" || { log "$note"; exit 1; }
  log "$(printf '%s\n' "$note" | sed 's/^/  /')"
}

run() {
  log "BarnCRM tier 1 scale test load: org $ALIAS, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "Reminder: hold the org lock; no org test gate at the same time."
  # Every gift gets an automatic allocation to the default fund. An org whose default
  # resolves keeps it; an org with none (or a setting pointing at a missing, deleted or
  # inactive fund) gets the generated "Scale test General" fund as its default.
  local setting_fund resolved
  setting_fund="$(sf data query --target-org "$ALIAS" --json \
    --query "SELECT Default_Fund__c FROM Giving_Settings__c" 2>/dev/null </dev/null \
    | jq -r '[.result.records[]?.Default_Fund__c | select(. != null and . != "")] | first // empty')"
  ORG_HAS_DEFAULT=0
  if [[ -z "$setting_fund" ]]; then
    log "Giving settings name no default fund on $ALIAS."
  elif [[ ! "$setting_fund" =~ ^[A-Za-z0-9]{15,18}$ ]]; then
    log "Giving settings hold an unreadable default fund value; treating the org as having no default."
  else
    # A query skips deleted rows, so this is the non-deleted, active, default-flagged fund.
    resolved="$(count_of "SELECT COUNT() FROM Fund__c WHERE Id = '$setting_fund' AND Active__c = true AND Is_Default__c = true")"
    if [[ "$resolved" == "1" ]]; then
      ORG_HAS_DEFAULT=1
    else
      log "Giving settings point at fund $setting_fund, which is missing, deleted, inactive or not"
      log "flagged default (matching funds: $resolved). Treating the org as having no default."
    fi
  fi
  if [[ "$ORG_HAS_DEFAULT" == "1" ]]; then
    log "Org already has a default fund ($setting_fund); it stays the default."
  else
    log "No usable default fund on $ALIAS: the generated 'Scale test General' fund is loaded as the default."
  fi
  # A SCALE-* fund still in the org (a kept default) must not be loaded a second time.
  SKIP_FUND_CODES="$(sf data query --target-org "$ALIAS" --json \
    --query "SELECT Accounting_Code__c FROM Fund__c WHERE Accounting_Code__c LIKE 'SCALE-%'" 2>/dev/null </dev/null \
    | jq -r '[.result.records[]?.Accounting_Code__c] | join(" ")')"
  [[ -n "$SKIP_FUND_CODES" ]] && log "Funds with these codes already exist and are not loaded again: $SKIP_FUND_CODES"
  generate
  record_limits "before"
  record_counts "before"
  if [[ "$SCALE_REMAINING" -ne 0 && "${SCALE_TEST_ALLOW_EXISTING:-}" != "1" ]]; then
    log ""
    log "REFUSING TO LOAD: scale households, contacts or gifts already exist on $ALIAS"
    log "(count $SCALE_REMAINING; -1 means a count could not be read). Loading on top of them"
    log "produces duplicate failures. Run 'scale-test-tier1.sh cleanup $ALIAS' first, or set"
    log "SCALE_TEST_ALLOW_EXISTING=1 to load anyway."
    exit 1
  fi

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

  # Soft credits only for gifts that loaded (and contacts that loaded); the split scripts
  # find their gifts by External_Id__c and skip any that are missing.
  export_to "SELECT External_Id__c FROM Gift__c WHERE External_Id__c LIKE 'SCALE-G-%'" \
    "$DIR/work/gift-ids.csv"
  resolve "$DIR/soft_credits.csv" --out "$DIR/work/soft_credits.csv" \
    --map "$DIR/work/contact-ids.csv" --key-col Contact_Key --id-col Contact__c \
    --only-col "Gift__r.External_Id__c" --only-from "$DIR/work/gift-ids.csv"
  load "soft credits" Soft_Credit__c "$DIR/work/soft_credits.csv"
  split_gifts

  record_limits "after"
  record_counts "after"
  log ""
  log "Results file: $RESULTS"
  log "Next: the runs table in the plan. Then 'scale-test-tier1.sh cleanup $ALIAS'."
}

# delete_where <label> <sobject> <where clause>: bulk export the Ids, then hard delete them.
delete_where() {
  local file="$DIR/work/delete-$2.csv" n start end flag outfile="$DIR/work/last-delete.json" slug
  log ""
  log "Delete: $1 ($2)"
  export_to "SELECT Id FROM $2 WHERE $3" "$file"
  n=$(($(wc -l <"$file") - 1))
  if [[ "$n" -le 0 ]]; then
    log "  nothing to delete"
    return
  fi
  slug="$(printf '%s' "delete $1" | tr -c 'A-Za-z0-9' '-')"
  while :; do
    flag="--hard-delete"
    [[ "$DELETE_SOFT" == "1" ]] && flag=""
    if [[ -n "$flag" ]]; then log "  $n Ids to delete (hard delete)"; else log "  $n Ids to delete (soft delete, Recycle Bin)"; fi
    start="$(date +%s)"
    rm -f "$DIR/work/failed-$slug.csv"
    # shellcheck disable=SC2086
    sf data delete bulk --sobject "$2" --file "$file" --target-org "$ALIAS" $flag \
      --wait "$WAIT" --json >"$outfile" 2>"$DIR/work/last-delete.err" </dev/null
    end="$(date +%s)"
    job_report "delete $1" "$outfile"
    log "  elapsed: $((end - start)) s"
    # No hard delete permission: the first delete says so. Fall back to soft delete for this
    # and the remaining steps unless the user forced hard delete.
    if [[ -n "$flag" && "$FORCE_HARD" != "1" && "$JOB_SUCCESS" -le 0 ]] \
      && grep -qis 'HardDeletePermissionError' "$outfile" "$DIR/work/last-delete.err" "$DIR/work/failed-$slug.csv"; then
      DELETE_SOFT=1
      log "  HardDeletePermissionError: the user lacks Bulk API Hard Delete. Falling back to soft"
      log "  delete (Recycle Bin) for this and the remaining steps."
      continue
    fi
    break
  done
  if [[ "$JOB_OK" != "1" || "$JOB_FAILED" != "0" || "$JOB_SUCCESS" -le 0 ]]; then
    CLEANUP_FAILED=1
    log "  NOTHING OR NOT EVERYTHING WAS DELETED for $1 ($JOB_SUCCESS of $n)."
    log "  stderr: $(head -c 300 "$DIR/work/last-delete.err" 2>/dev/null)"
    job_error_hint "$(cat "$outfile" "$DIR/work/last-delete.err" 2>/dev/null | head -c 2000)"
  fi
}

CLEANUP_FAILED=0
# DELETE_SOFT=1 means delete to the Recycle Bin; FORCE_HARD=1 means hard delete or fail.
DELETE_SOFT=0
FORCE_HARD=0
cleanup() {
  log "BarnCRM tier 1 scale test cleanup: org $ALIAS, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "${SCALE_TEST_HARD_DELETE:-}" == "1" ]]; then
    FORCE_HARD=1
    log "Hard delete forced (SCALE_TEST_HARD_DELETE=1): no fallback to soft delete."
  elif [[ "${SCALE_TEST_SOFT_DELETE:-}" == "1" ]]; then
    DELETE_SOFT=1
    log "Soft delete (SCALE_TEST_SOFT_DELETE=1): records go to the Recycle Bin."
  else
    log "Hard delete first; without the Bulk API Hard Delete permission it falls back to soft delete."
  fi
  record_counts "before cleanup"
  # Children first. Allocations are not deleted on their own: Giving refuses to delete a
  # gift's allocation while the gift remains (the gift would be under-allocated), so they go
  # with their gifts (master-detail cascade), as do soft credits; soft credits are deleted
  # first only so their count is reported separately.
  delete_where "soft credits" Soft_Credit__c "Gift__r.External_Id__c LIKE 'SCALE-G-%'"
  delete_where "gifts (with their allocations)" Gift__c "External_Id__c LIKE 'SCALE-G-%'"
  delete_where "contacts" Contact "Sample_Data_Key__c LIKE 'SCALE-C-%'"
  delete_where "households" Account "Sample_Data_Key__c LIKE 'SCALE-H-%'"
  if [[ "$KEEP_FUNDS" == "1" ]]; then
    log "  funds: kept (--keep-funds), needed by the import wizard file"
  else
    # Never the org's default fund: Giving settings point at it. Cleanup keeps it, and the
    # next run reuses it (and skips loading a fund with the same code).
    local kept
    kept="$(sf data query --target-org "$ALIAS" --json \
      --query "SELECT Accounting_Code__c FROM Fund__c WHERE Accounting_Code__c LIKE 'SCALE-%' AND Is_Default__c = true" \
      2>/dev/null </dev/null | jq -r '[.result.records[]?.Accounting_Code__c] | join(", ")')"
    [[ -n "$kept" ]] && log "  funds: kept the default fund ($kept); it is not deleted"
    delete_where "funds (not the default)" Fund__c "Accounting_Code__c LIKE 'SCALE-%' AND Is_Default__c = false"
  fi
  record_counts "after cleanup"
  log ""
  log "Gifts the import wizard created are not touched here: undo that import batch in the"
  log "wizard. Rerun scripts/org/seed-sample-data.sh $ALIAS if the sample data was removed."
  log "Results file: $RESULTS"
  if [[ "$CLEANUP_FAILED" == "1" || "$SCALE_REMAINING" != "0" ]]; then
    log ""
    log "CLEANUP INCOMPLETE: $SCALE_REMAINING scale records remain (-1 means a count could not be"
    log "read) or a delete job failed. See the job lines above."
    exit 1
  fi
}

if [[ "$MODE" == "cleanup" ]]; then
  cleanup
else
  run
fi
