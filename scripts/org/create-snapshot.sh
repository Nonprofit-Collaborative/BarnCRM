#!/usr/bin/env bash
# create-snapshot.sh <source-alias> <snapshot-name> [--description TEXT] [--no-wait]
#
# Creates a scratch org snapshot from an existing, fully prepared scratch org (BarnCRM deployed,
# permission sets assigned). If a snapshot with that name already exists on the Dev Hub it is
# deleted first, because snapshot names are unique: this is the "refresh" path. The source org
# stays untouched. See docs/contributor-guide/scratch-orgs.md, "Snapshots".
#
# OWNER APPROVAL: a snapshot consumes Dev Hub snapshot capacity and is created from an org the
# owner already approved. Ask before running it. Nothing in CI runs this script.
#
# The names the definition files in config/scratch-defs/ expect:
#   BarnPA         config/scratch-defs/person-accounts-snapshot.json
#   BarnPlatform   config/scratch-defs/platform-only-snapshot.json

set -euo pipefail

usage() {
  echo "Usage: create-snapshot.sh <source-alias> <snapshot-name> [--description TEXT] [--no-wait]" >&2
  echo "  snapshot-name  Letters and numbers only, at most 15 characters (BarnPA, BarnPlatform)." >&2
  exit 1
}

SOURCE="${1:-}"
NAME="${2:-}"
[[ -z "$SOURCE" || -z "$NAME" ]] && usage
shift 2

DESCRIPTION="BarnCRM snapshot of ${SOURCE}, $(date +%Y-%m-%d)"
WAIT=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --description)
      DESCRIPTION="${2:-}"
      shift 2
      ;;
    --no-wait)
      WAIT=0
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

if ! [[ "$NAME" =~ ^[A-Za-z0-9]{1,15}$ ]]; then
  echo "Snapshot name '${NAME}' is not valid: use 1 to 15 letters or numbers." >&2
  exit 1
fi

if sf org get snapshot --snapshot "$NAME" >/dev/null 2>&1; then
  echo "== Deleting the existing snapshot ${NAME} (refresh) =="
  sf org delete snapshot --snapshot "$NAME" --no-prompt
fi

echo "== Creating snapshot ${NAME} from ${SOURCE} =="
sf org create snapshot \
  --source-org "$SOURCE" \
  --snapshot-name "$NAME" \
  --description "$DESCRIPTION"

if [[ "$WAIT" -eq 1 ]]; then
  echo "== Waiting for ${NAME} to become Active (up to 30 minutes) =="
  for _ in $(seq 1 60); do
    STATUS="$(sf org get snapshot --snapshot "$NAME" --json 2>/dev/null |
      python3 -c 'import json,sys; print(json.load(sys.stdin)["result"].get("Status",""))' 2>/dev/null || true)"
    echo "Status: ${STATUS:-unknown}"
    if [[ "$STATUS" == "Active" ]]; then
      echo "Snapshot ${NAME} is ready."
      exit 0
    fi
    if [[ "$STATUS" == "Error" ]]; then
      echo "Snapshot ${NAME} failed. Run: sf org get snapshot --snapshot ${NAME}" >&2
      exit 1
    fi
    sleep 30
  done
  echo "Snapshot ${NAME} is still not Active. Check: sf org get snapshot --snapshot ${NAME}" >&2
  exit 1
fi
