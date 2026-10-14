#!/usr/bin/env bash
# grant-person-record-type.sh <alias>
#
# Gives the System Administrator profile the org's person account record types, so the tests
# that need real person accounts run there instead of failing (PEOPLE-29). A Nonprofit Cloud
# trial, and some person account orgs, ship a Person Account record type that the System
# Administrator profile is not given; the platform then refuses every person account a test
# creates. PersonAccountTestShape fails a test in that state and names this script.
#
# Does nothing in an org without person accounts. Safe to run again: a profile deploy that
# names only record type visibility changes nothing else on the profile. The first person
# record type by developer name becomes the profile's person account default.
#
# Called by create-scratch-org.sh for the person-accounts and nonprofit-cloud shapes. Run it
# by hand for an existing org (oi-test, oi-pa) that was created before it existed.

set -euo pipefail

ALIAS="${1:-}"
if [[ -z "$ALIAS" ]]; then
  echo "Usage: grant-person-record-type.sh <alias>" >&2
  exit 1
fi

API_VERSION="$(python3 -c 'import json; print(json.load(open("sfdx-project.json"))["sourceApiVersion"])')"

TYPES="$(sf data query \
  --query "SELECT DeveloperName FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true ORDER BY DeveloperName" \
  --target-org "$ALIAS" --json 2>/dev/null |
  python3 -c 'import json,sys
data = json.load(sys.stdin)
for row in (data.get("result") or {}).get("records") or []:
    print(row["DeveloperName"])' || true)"

if [[ -z "$TYPES" ]]; then
  echo "No active person account record type in ${ALIAS}; nothing to grant."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/profiles"

{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<Profile xmlns="http://soap.sforce.com/2006/04/metadata">'
  FIRST=1
  while IFS= read -r NAME; do
    [[ -z "$NAME" ]] && continue
    if [[ "$FIRST" -eq 1 ]]; then DEFAULT=true; FIRST=0; else DEFAULT=false; fi
    echo '    <recordTypeVisibilities>'
    echo '        <default>false</default>'
    echo "        <personAccountDefault>${DEFAULT}</personAccountDefault>"
    echo "        <recordType>PersonAccount.${NAME}</recordType>"
    echo '        <visible>true</visible>'
    echo '    </recordTypeVisibilities>'
  done <<<"$TYPES"
  echo '</Profile>'
} >"$WORK/profiles/Admin.profile"

cat >"$WORK/package.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Admin</members>
        <name>Profile</name>
    </types>
    <version>${API_VERSION}</version>
</Package>
EOF

echo "== Giving the System Administrator profile the person record types in ${ALIAS}: $(echo "$TYPES" | tr '\n' ' ')=="
sf project deploy start --metadata-dir "$WORK" --target-org "$ALIAS" --wait 10
