#!/usr/bin/env bash
# install-npsp.sh
#
# Installs NPSP and its dependency packages, in order, into the target org/alias.
#
# NPSP requires installing, in this order:
#   1. Contacts & Organizations (npe01)
#   2. Households (npo02)
#   3. Recurring Donations (npe03)
#   4. Relationships (npe4)
#   5. Affiliations (npe5)
#   6. NPSP (npsp)
#
# IDs research (2026-09-07): attempted to source current 04t package version IDs from
# https://install.salesforce.org/products/npsp and https://github.com/SalesforceFoundation/NPSP/releases.
# The releases page surfaced only a beta version id for the main NPSP package (no confirmed
# GA id, and no ids at all for the five dependency packages npe01/npo02/npe03/npe4/npe5), and
# install.salesforce.org was not reachable from this environment. Per the hard rule to never
# invent package version IDs, NPSP_PACKAGE_IDS below is intentionally left empty.
#
# MANUAL STEP (until this script is updated with verified IDs):
#   Use the NPSP installer at https://install.salesforce.org/products/npsp, logged in against
#   the target scratch org, to install NPSP and its dependencies. See
#   docs/contributor-guide/scratch-orgs.md for the full walkthrough.
#
# Once verified 04t ids are available, populate NPSP_PACKAGE_IDS in the order above and this
# script will install each with:
#   sf package install --package <04t> --wait 30 --no-prompt --security-type AllUsers --target-org <alias>

set -euo pipefail

ALIAS="${1:-}"

if [[ -z "$ALIAS" ]]; then
  echo "Usage: install-npsp.sh <org-alias>" >&2
  exit 1
fi

# Ordered list of 04t package version IDs: npe01, npo02, npe03, npe4, npe5, npsp.
# PLACEHOLDER (QA review Q2, 2026-11-12): still empty, because no verified IDs are known. Fill
# it here once verified, or pass them for one run, space separated and in the order above:
#   NPSP_PACKAGE_IDS="04t... 04t... 04t... 04t... 04t... 04t..." install-npsp.sh barn-npsp
# The NPSP-shaped release gate org (barn-npsp, scripts/org/release-gate.sh) needs them, or the
# manual installer below.
# shellcheck disable=SC2206
NPSP_PACKAGE_IDS=(${NPSP_PACKAGE_IDS:-})

if [[ ${#NPSP_PACKAGE_IDS[@]} -eq 0 ]]; then
  echo "install-npsp.sh: no verified NPSP package version IDs are recorded yet."
  echo "Manual step required: install NPSP by hand using https://install.salesforce.org/products/npsp"
  echo "against org alias '${ALIAS}'. See docs/contributor-guide/scratch-orgs.md for details."
  exit 1
fi

for PKG_ID in "${NPSP_PACKAGE_IDS[@]}"; do
  echo "Installing package version ${PKG_ID} into ${ALIAS}..."
  sf package install --package "$PKG_ID" --wait 30 --no-prompt --security-type AllUsers --target-org "$ALIAS"
done

echo "NPSP install complete on ${ALIAS}."
