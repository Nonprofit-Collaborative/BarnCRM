#!/usr/bin/env bash
# probe-error-log.sh <alias>
#
# Proves the Error Log event path works on the org after a deploy: publishes one Info entry
# through ErrorLogger, waits for its Error_Log__c row, then deletes the row.
#
# WHY. Every packaged failure reaches the Error Log through the Error_Log_Event__e platform event
# and ErrorLogEventTrigger. Apex tests cannot see that path (Test.getEventBus delivers events in
# the test's own context), and on barn-sales the 2026-10-31 gate deploy left the trigger's
# subscription Running but never delivering (QA v21 D4): publishing kept succeeding and every
# entry was silently lost. Redeploying the trigger, even with a changed body, did not restart it;
# deploying it Inactive and then Active again did.
#
# Exit codes: 0 the row arrived, 1 it did not arrive in time or the probe could not run.

set -uo pipefail

ALIAS="${1:?usage: probe-error-log.sh <alias>}"
WAIT_SECONDS="${PROBE_WAIT_SECONDS:-120}"
CONTEXT="Gate probe $(date -u +%Y%m%dT%H%M%SZ)-$$"
PROBE_DIR="$(mktemp -d)"
APEX_FILE="${PROBE_DIR}/probe.apex"
trap 'rm -rf "$PROBE_DIR"' EXIT

count_rows() {
  sf data query --target-org "$ALIAS" --json \
    --query "SELECT COUNT() FROM Error_Log__c WHERE Context__c = '${CONTEXT}'" 2>/dev/null |
    python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t[t.index("{"):])["result"]["totalSize"])' 2>/dev/null ||
    echo "error"
}

printf "ErrorLogger.logMessage('Org gate probe: the Error Log event path works.', '%s', ErrorLogger.SEVERITY_INFO);\n" \
  "$CONTEXT" >"$APEX_FILE"
if ! sf apex run --target-org "$ALIAS" --file "$APEX_FILE" >/dev/null 2>&1; then
  echo "Error Log probe: could not publish the probe entry on ${ALIAS}." >&2
  exit 1
fi

deadline=$(($(date +%s) + WAIT_SECONDS))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ "$(count_rows)" = "1" ]; then
    printf "delete [SELECT Id FROM Error_Log__c WHERE Context__c = '%s'];\n" "$CONTEXT" >"$APEX_FILE"
    sf apex run --target-org "$ALIAS" --file "$APEX_FILE" >/dev/null 2>&1 ||
      echo "Error Log probe: the row arrived but could not be deleted (Context ${CONTEXT})." >&2
    echo "Error Log probe: the event path works on ${ALIAS}."
    exit 0
  fi
  sleep 10
done

echo "Error Log probe: no Error_Log__c row ${WAIT_SECONDS}s after publishing on ${ALIAS}." >&2
echo "ErrorLogEventTrigger is not receiving events. Restart its subscription: Setup, Platform" >&2
echo "Events, Error Log Event, Suspend then Resume; or deploy the trigger Inactive, then Active." >&2
exit 1
