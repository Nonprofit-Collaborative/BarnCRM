#!/usr/bin/env bash
# create-org-from-snapshot.sh <shape> [alias] [--days N] [--replace]
#
# Creates a scratch org from a snapshot instead of deploying BarnCRM from source, so the org is
# ready in minutes with Core deployed and permission sets set up. Shapes with a snapshot
# definition (config/scratch-defs/<shape>-snapshot.json): person-accounts, platform-only.
# See docs/contributor-guide/scratch-orgs.md, "Snapshots".
#
# OWNER APPROVAL: every scratch org needs the owner's approval, snapshot or not. Only the
# recreation of an expired approved org (oi-test, oi-pa, barn-core) is pre-approved.
#
# A snapshot is only as current as the metadata it was taken from. If packages/ changed since
# the snapshot was created, refresh it first (scripts/org/create-snapshot.sh), or the new org
# lacks those changes. This script warns when it can tell.

set -euo pipefail

usage() {
  echo "Usage: create-org-from-snapshot.sh <shape> [alias] [--days N] [--replace]" >&2
  echo "  shape: person-accounts | platform-only" >&2
  exit 1
}

SHAPE="${1:-}"
[[ -z "$SHAPE" ]] && usage
shift || true

ALIAS=""
DAYS=30
REPLACE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)
      DAYS="${2:-30}"
      shift 2
      ;;
    --replace)
      REPLACE=1
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$ALIAS" ]]; then
        ALIAS="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
done

DEF_FILE="config/scratch-defs/${SHAPE}-snapshot.json"
if [[ ! -f "$DEF_FILE" ]]; then
  echo "No snapshot definition at ${DEF_FILE}. Shapes with one: person-accounts, platform-only." >&2
  exit 1
fi
[[ -z "$ALIAS" ]] && ALIAS="barn-${SHAPE}"

if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || (( DAYS < 1 || DAYS > 30 )); then
  echo "--days must be between 1 and 30 (Salesforce caps a scratch org at 30 days)." >&2
  exit 1
fi

SNAPSHOT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["snapshot"])' "$DEF_FILE")"

STATUS="$(sf org get snapshot --snapshot "$SNAPSHOT" --json 2>/dev/null |
  python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; print(r.get("Status","")+" "+r.get("LastClonedDate",""))' 2>/dev/null || true)"
if [[ "$STATUS" != Active* ]]; then
  echo "Snapshot ${SNAPSHOT} is not Active (${STATUS:-not found}). Create or refresh it with" >&2
  echo "scripts/org/create-snapshot.sh <source-alias> ${SNAPSHOT}" >&2
  exit 1
fi

# Warn when metadata changed after the snapshot was taken.
SNAP_DATE="$(sf org get snapshot --snapshot "$SNAPSHOT" --json 2>/dev/null |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["result"].get("CreatedDate","")[:10])' 2>/dev/null || true)"
if [[ -n "$SNAP_DATE" ]] && [[ -n "$(git log --since="$SNAP_DATE" --oneline -- packages sfdx-project.json 2>/dev/null | head -1)" ]]; then
  echo "WARNING: packages/ changed since the snapshot was created on ${SNAP_DATE}." >&2
  echo "The new org will lack those changes. Refresh the snapshot if that matters." >&2
fi

if [[ "$REPLACE" -eq 1 ]]; then
  if sf org display --target-org "$ALIAS" >/dev/null 2>&1; then
    echo "== Deleting the existing org aliased ${ALIAS} (--replace) =="
    sf org delete scratch --target-org "$ALIAS" --no-prompt || true
  fi
fi

echo "== Creating scratch org from snapshot ${SNAPSHOT}: alias=${ALIAS} days=${DAYS} =="
sf org create scratch \
  --snapshot "$SNAPSHOT" \
  --definition-file "$DEF_FILE" \
  --alias "$ALIAS" \
  --duration-days "$DAYS" \
  --set-default \
  --wait 30

# Permission set assignments belong to the user, and the new org's admin user is a new user, so
# assign again. An already assigned set is not an error worth stopping for.
echo "== Assigning Core permission sets to the default user =="
for PS_FILE in packages/core/main/default/permissionsets/*.permissionset-meta.xml; do
  [[ -e "$PS_FILE" ]] || continue
  PS_NAME="$(basename "$PS_FILE" .permissionset-meta.xml)"
  sf org assign permset --name "$PS_NAME" --target-org "$ALIAS" >/dev/null 2>&1 \
    && echo "Assigned ${PS_NAME}" || echo "Skipped ${PS_NAME} (already assigned or failed; check by hand if unsure)"
done

echo "== Done =="
echo "Open the org with: sf org open --target-org ${ALIAS}"
echo "A new org has a new auth URL: update SF_TEST_ORG_AUTH_URL if this replaced oi-test."
