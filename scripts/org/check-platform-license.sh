#!/usr/bin/env bash
# check-platform-license.sh <alias>
#
# The Platform user license check of ADR-0013 (mechanism 2): every Core permission set except
# the optional license-limited ones must be assignable to a user holding the Salesforce
# Platform license and the Standard Platform User profile. Salesforce refuses an assignment
# whose set grants an object or a user permission that license cannot have, so a refusal is
# the signal that something only a Salesforce license can hold has leaked into a role.
#
# The optional sets (BarnCRM_Duplicate_Review, BarnCRM_Access_Manager) are expected to be
# refused and are skipped. Their list lives in scripts/ci/check-permission-sets.py, which
# also keeps the license-limited grants out of every other set (ADR-0050, ADR-0121).
#
# Tries every set and reports every refusal, then exits 1 if there was one. Safe to run
# again: it creates the Platform user only when missing, and a set the user already holds
# counts as assignable. Called by create-scratch-org.sh for the platform-only shape; run it
# by hand to recheck an existing platform-only org (barn-core).

set -euo pipefail

ALIAS="${1:-}"
if [[ -z "$ALIAS" ]]; then
  echo "Usage: check-platform-license.sh <alias>" >&2
  exit 1
fi

cd "$(dirname "$0")/../.."

PERMSET_DIR="packages/core/main/default/permissionsets"
PLATFORM_USERNAME="platformuser@${ALIAS}.barncrm.test"
OPTIONAL_SETS="$(python3 scripts/ci/check-permission-sets.py --list-optional-license-sets)"

EXISTING="$(sf data query --target-org "$ALIAS" --json \
  --query "SELECT Id FROM User WHERE Username = '${PLATFORM_USERNAME}'" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["totalSize"])')"
if [[ "$EXISTING" == "0" ]]; then
  echo "== Platform-only license check: creating Standard Platform User =="
  PLATFORM_USER_DEF="$(mktemp)"
  sed "s/<alias>/${ALIAS}/g" config/users/platform-user.json > "$PLATFORM_USER_DEF"
  sf org create user --definition-file "$PLATFORM_USER_DEF" --target-org "$ALIAS"
  rm -f "$PLATFORM_USER_DEF"
else
  echo "== Platform-only license check: ${PLATFORM_USERNAME} already exists =="
fi

CHECKED=0
FAILED=()
for PS_FILE in "$PERMSET_DIR"/*.permissionset-meta.xml; do
  [[ -e "$PS_FILE" ]] || continue
  PS_NAME="$(basename "$PS_FILE" .permissionset-meta.xml)"
  if grep -qx "$PS_NAME" <<<"$OPTIONAL_SETS"; then
    echo "Skipping ${PS_NAME}: optional, needs a Salesforce license (expected to be refused)"
    continue
  fi
  CHECKED=$((CHECKED + 1))
  OUTPUT="$(sf org assign permset --name "$PS_NAME" --target-org "$ALIAS" \
    --on-behalf-of "$PLATFORM_USERNAME" 2>&1)" && STATUS=0 || STATUS=$?
  # A set the user already holds is reported as a failure naming a duplicate assignment.
  if [[ "$STATUS" -eq 0 ]] && ! grep -q "Failures" <<<"$OUTPUT" ||
    grep -q "Duplicate PermissionSetAssignment" <<<"$OUTPUT"; then
    echo "OK ${PS_NAME}"
  else
    echo "REFUSED ${PS_NAME}:"
    echo "$OUTPUT" | grep -v '^\s*$' | sed 's/^/    /'
    FAILED+=("$PS_NAME")
  fi
done

if [[ "$CHECKED" -eq 0 ]]; then
  echo "no permission sets yet; skipping Standard Platform User assignment check"
  exit 0
fi
if [[ "${#FAILED[@]}" -gt 0 ]]; then
  echo "Platform-only license check FAILED: ${#FAILED[@]} of ${CHECKED} Core permission sets" \
    "cannot be assigned to a Salesforce Platform user: ${FAILED[*]}" >&2
  exit 1
fi
echo "Platform-only license check passed: all ${CHECKED} Core permission sets assignable."
