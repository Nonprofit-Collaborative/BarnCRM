#!/usr/bin/env bash
# seed-sample-data.sh <alias>
#
# Loads the C-10 sample data set (200 households, 440 contacts, 25 organizations, their
# connections and affiliations, and the Giving gifts where Giving is installed) into the
# target org and waits for it to actually finish.
#
# SampleDataLoader.load() runs as Batch Apex (SampleDataStageBatch, one stage per execute:
# the accounts, each chunk of contacts, the connections, then each module's stages in a
# batch of their own), so the Apex call returns as soon as the batch is queued, not once
# loading is done. Stage one
# inserts all 200 households in a single DML, so counting households proves nothing about
# the contacts. This polls both the contact count (target read from the generated JSON)
# and AsyncApexJob, and reports success only when every contact is in and no load job is
# still queued or running. See docs/admin-guide/sample-data.md and data/sample/README.md.
#
# Safe to call before scripts/org/load-sample-data.apex exists; it just prints a note
# and exits successfully so callers (create-scratch-org.sh) do not fail.

set -euo pipefail

ALIAS="${1:-}"

if [[ -z "$ALIAS" ]]; then
  echo "Usage: seed-sample-data.sh <org-alias>" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APEX_FILE="$REPO_ROOT/scripts/org/load-sample-data.apex"
SAMPLE_JSON="$REPO_ROOT/packages/core/main/default/staticresources/SampleData.json"
POLL_INTERVAL_SECONDS=5
# The chain is longer than it was: five contact chunks, the connection stage, and then the
# Giving stages (reference data plus one job per hundred gifts), each waiting its turn in
# the queue, so a scratch org with Giving installed needs minutes rather than one minute.
MAX_WAIT_SECONDS=900

if [[ ! -f "$APEX_FILE" ]]; then
  echo "sample data not yet available (C-10)"
  exit 0
fi

# The expected contact count is the number of household members in the generated
# resource, so it never drifts from the data the loader actually inserts.
EXPECTED_CONTACTS="$(node -e "
  const fs = require('fs');
  const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  const total = data.households.reduce((sum, h) => sum + h.members.length, 0);
  console.log(total);
" "$SAMPLE_JSON")"

# Reads a COUNT() query result from the sf CLI JSON envelope, 0 if anything went wrong.
count_query() {
  sf data query --target-org "$ALIAS" --query "$1" --json | node -e "
    let data = '';
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => {
      try {
        console.log(JSON.parse(data).result.totalSize);
      } catch (e) {
        console.log(0);
      }
    });
  "
}

echo "Starting the sample data load in ${ALIAS} (runs in the background as Batch Apex)..."
sf apex run --target-org "$ALIAS" --file "$APEX_FILE"

echo "Waiting for ${EXPECTED_CONTACTS} sample contacts and for the load jobs to finish (up to ${MAX_WAIT_SECONDS}s)..."

# Every stage, Core's and Giving's, runs in SampleDataStageBatch, and each batch queues the
# next before it ends: waiting only on the contact stages would report success while the
# connections and the gifts were still being written.
RUNNING_JOB_QUERY="SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'SampleDataStageBatch' AND JobType = 'BatchApex' AND Status IN ('Queued', 'Preparing', 'Processing', 'Holding')"

ELAPSED=0
while [[ "$ELAPSED" -lt "$MAX_WAIT_SECONDS" ]]; do
  CONTACTS="$(count_query "SELECT COUNT() FROM Contact WHERE Sample_Data__c = true")"
  RUNNING_JOBS="$(count_query "$RUNNING_JOB_QUERY")"

  echo "  ${CONTACTS} / ${EXPECTED_CONTACTS} contacts loaded, ${RUNNING_JOBS} load job(s) still running (${ELAPSED}s elapsed)"

  if [[ "$CONTACTS" -ge "$EXPECTED_CONTACTS" && "$RUNNING_JOBS" -eq 0 ]]; then
    HOUSEHOLDS="$(count_query "SELECT COUNT() FROM Account WHERE Sample_Data__c = true AND RecordType.DeveloperName = 'Household'")"
    ORGANIZATIONS="$(count_query "SELECT COUNT() FROM Account WHERE Sample_Data__c = true AND RecordType.DeveloperName = 'Organization'")"
    echo "Sample data load complete: ${HOUSEHOLDS} households, ${CONTACTS} contacts, ${ORGANIZATIONS} organizations."
    exit 0
  fi

  sleep "$POLL_INTERVAL_SECONDS"
  ELAPSED=$((ELAPSED + POLL_INTERVAL_SECONDS))
done

echo "Sample data load did not finish within ${MAX_WAIT_SECONDS}s." >&2
echo "Check Setup > Apex Jobs, or open BarnCRM Settings > Sample Data in the org, for progress." >&2
exit 1
