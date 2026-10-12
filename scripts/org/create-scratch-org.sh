#!/usr/bin/env bash
# create-scratch-org.sh <shape> [alias] [--days N] [--no-sample-data] [--replace]
#
# Creates a scratch org of the given shape, deploys Core, assigns Core's permission sets, and
# (for the platform-only shape) verifies that a Salesforce Platform license user can use every
# packaged permission set. See docs/contributor-guide/scratch-orgs.md for the full explanation.
#
# Shapes (see config/scratch-defs/):
#   platform-only     Developer edition, no Sales/Service objects available to the org's
#                      standard users. See the PLATFORM-ONLY VERIFICATION comment below for why
#                      this shape needs an extra check that the others do not.
#   sales-cloud        Enterprise edition, standard Sales Cloud objects available.
#   npsp                Enterprise edition, NPSP installed on top (scripts/org/install-npsp.sh).
#   person-accounts     Enterprise edition with Person Accounts enabled.
#   nonprofit-cloud     Enterprise edition with Person Accounts and the Nonprofit Cloud
#                      feature. Needs a Dev Hub that carries the Nonprofit Cloud entitlement:
#                      an ordinary Developer Edition Dev Hub cannot create this shape, and
#                      says so by listing the features it can grant. See
#                      docs/contributor-guide/scratch-orgs.md before using it.

set -euo pipefail

usage() {
  echo "Usage: create-scratch-org.sh <shape> [alias] [--days N] [--no-sample-data] [--replace]" >&2
  echo "  --days N     1 to 30. Salesforce caps a scratch org at 30 days; there is no" >&2
  echo "               permanent scratch org. For a long lived development org use" >&2
  echo "               --days 30 --replace and re-run it monthly, or use a Developer" >&2
  echo "               Edition org instead. See docs/contributor-guide/scratch-orgs.md." >&2
  echo "  --replace    Delete an existing scratch org with the same alias first, so a" >&2
  echo "               refresh does not leave the old one consuming an active org slot." >&2
  echo "  shape: platform-only | sales-cloud | npsp | person-accounts | nonprofit-cloud" >&2
  exit 1
}

SHAPE="${1:-}"
[[ -z "$SHAPE" ]] && usage
shift || true

ALIAS=""
DAYS=7
LOAD_SAMPLE_DATA=1
REPLACE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)
      DAYS="${2:-7}"
      shift 2
      ;;
    --no-sample-data)
      LOAD_SAMPLE_DATA=0
      shift
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

DEF_FILE="config/scratch-defs/${SHAPE}.json"
if [[ ! -f "$DEF_FILE" ]]; then
  echo "Unknown shape '${SHAPE}'. Expected one of: platform-only, sales-cloud, npsp, person-accounts, nonprofit-cloud" >&2
  echo "(no scratch-def file found at ${DEF_FILE})" >&2
  exit 1
fi

if [[ -z "$ALIAS" ]]; then
  ALIAS="barncrm-${SHAPE}"
fi

# Salesforce caps a scratch org at 30 days and deletes it when it expires. Catching a
# larger number here says so plainly, rather than letting the API reject it later.
if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || (( DAYS < 1 || DAYS > 30 )); then
  echo "--days must be between 1 and 30. Salesforce caps a scratch org at 30 days:" >&2
  echo "there is no permanent scratch org. For a long lived development org, use" >&2
  echo "--days 30 --replace and re-run this monthly, or use a Developer Edition org." >&2
  echo "See docs/contributor-guide/scratch-orgs.md, 'A development org that lasts'." >&2
  exit 1
fi

if [[ "$REPLACE" -eq 1 ]]; then
  if sf org display --target-org "$ALIAS" >/dev/null 2>&1; then
    echo "== Deleting the existing org aliased ${ALIAS} (--replace) =="
    sf org delete scratch --target-org "$ALIAS" --no-prompt || true
  else
    echo "No existing org aliased ${ALIAS}; nothing to replace."
  fi
fi

echo "== Creating scratch org: shape=${SHAPE} alias=${ALIAS} days=${DAYS} =="
sf org create scratch \
  --definition-file "$DEF_FILE" \
  --alias "$ALIAS" \
  --duration-days "$DAYS" \
  --set-default \
  --wait 15

if [[ "$SHAPE" == "npsp" ]]; then
  echo "== Installing NPSP (shape=npsp) =="
  scripts/org/install-npsp.sh "$ALIAS"
fi

# Deployed in stages by one script, shared with continuous integration, so a failure names
# a stage instead of leaving 982 components as suspects. See scripts/org/deploy-packages.sh.
scripts/org/deploy-packages.sh "$ALIAS" --core-only

echo "== Assigning Core permission sets to the default (deployment) user =="
PERMSET_DIR="packages/core/main/default/permissionsets"
FOUND_PERMSET=0
if [[ -d "$PERMSET_DIR" ]]; then
  for PS_FILE in "$PERMSET_DIR"/*.permissionset-meta.xml; do
    [[ -e "$PS_FILE" ]] || continue
    FOUND_PERMSET=1
    PS_NAME="$(basename "$PS_FILE" .permissionset-meta.xml)"
    echo "Assigning permission set: ${PS_NAME}"
    sf org assign permset --name "$PS_NAME" --target-org "$ALIAS"
  done
fi
if [[ "$FOUND_PERMSET" -eq 0 ]]; then
  echo "no permission sets yet"
fi

# PLATFORM-ONLY VERIFICATION
#
# Scratch orgs always provision Sales Cloud objects regardless of the requested edition or
# features; there is no scratch-org setting that removes them. So the platform-only shape
# cannot be verified simply by inspecting what exists in the org. Instead we verify it two ways:
#   (a) a CI static check (scripts/ci/check-standard-objects.sh) that fails if any file under
#       packages/core (or any other non-Connect package) references a Sales/Service/Industries
#       object, so the source itself never depends on what a real Platform-only org lacks; and
#   (b) here, at org-creation time for the platform-only shape only: we create a user with the
#       "Salesforce Platform" user license and the "Standard Platform User" profile, then assign
#       every Core permission set to that user. The "Standard Platform User" profile cannot see
#       Sales/Service objects, so if any Core permission set grants access to an object that
#       license cannot see, the assignment fails loudly, which is exactly the signal we want.
if [[ "$SHAPE" == "platform-only" ]]; then
  echo "== Platform-only license check: creating Standard Platform User =="
  PLATFORM_USER_DEF="$(mktemp)"
  sed "s/<alias>/${ALIAS}/g" config/users/platform-user.json > "$PLATFORM_USER_DEF"
  sf org create user --definition-file "$PLATFORM_USER_DEF" --target-org "$ALIAS"
  rm -f "$PLATFORM_USER_DEF"

  PLATFORM_USERNAME="platformuser@${ALIAS}.barncrm.test"

  if [[ "$FOUND_PERMSET" -eq 1 ]]; then
    for PS_FILE in "$PERMSET_DIR"/*.permissionset-meta.xml; do
      [[ -e "$PS_FILE" ]] || continue
      PS_NAME="$(basename "$PS_FILE" .permissionset-meta.xml)"
      echo "Assigning ${PS_NAME} to ${PLATFORM_USERNAME} (Standard Platform User license check)"
      sf org assign permset --name "$PS_NAME" --target-org "$ALIAS" --on-behalf-of "$PLATFORM_USERNAME"
    done
  else
    echo "no permission sets yet; skipping Standard Platform User assignment check"
  fi
fi

if [[ "$LOAD_SAMPLE_DATA" -eq 1 ]]; then
  echo "== Seeding sample data =="
  scripts/org/seed-sample-data.sh "$ALIAS"
else
  echo "Skipping sample data (--no-sample-data)."
fi

echo "== Done =="
echo "Open the org with: sf org open --target-org ${ALIAS}"

# An expiry nobody has been told about is how a development org and its data get lost.
EXPIRY="$(sf org display --target-org "$ALIAS" --json 2>/dev/null |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["result"].get("expirationDate",""))' 2>/dev/null || true)"
if [[ -n "$EXPIRY" ]]; then
  echo "This scratch org expires on ${EXPIRY} and is deleted by Salesforce that day."
  echo "Refresh it with: scripts/org/create-scratch-org.sh ${SHAPE} ${ALIAS} --days ${DAYS} --replace"
fi
