#!/usr/bin/env bash
# zap-baseline.sh <site base URL> [<form record Id>] [<event record Id>]
#
# OWASP ZAP baseline scan of BarnCRM's guest surfaces (QA review Q6, D-200), run once per
# version on a test org's Salesforce Site, never on a customer's. The baseline scan spiders for a
# minute and reports passive findings only (headers, cookies, information leaks, mixed content);
# it sends no attack payloads, so it is safe against a shared test org.
#
#   Forms     <site>/FormsPublic?form=<form Id> and /services/apexrest/barncrm/forms/v1/<form Id>
#   Events    <site>/FormsPublic?list=events and ?record=<event Id> (the public event page)
#   Payments  /services/apexrest/barncrm/payments/v1/stripe and /paypal (webhooks; GET only, so
#             ZAP sees what an unsigned caller gets back)
#   Portal    /services/apexrest/barncrm/portal/v1/login/start
#
# Needs Docker. Reports go to test-results/zap/<surface>.html and .json. Exit 0 when no scan
# reported a FAIL; WARN findings are listed for review in the security checklist.
# Example: scripts/org/zap-baseline.sh https://barn-sales.my.salesforce-sites.com a0X... a0Y...

set -euo pipefail

SITE="${1:-}"
FORM_ID="${2:-}"
EVENT_ID="${3:-}"
if [[ -z "$SITE" ]]; then
  echo "Usage: zap-baseline.sh <site base URL> [<form record Id>] [<event record Id>]" >&2
  exit 2
fi
SITE="${SITE%/}"
IMAGE="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:stable}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
OUT="$REPO_ROOT/test-results/zap"
mkdir -p "$OUT"
REST="$SITE/services/apexrest/barncrm"

TARGETS=(
  "events-list|$SITE/FormsPublic?list=events"
  "payments-stripe|$REST/payments/v1/stripe"
  "payments-paypal|$REST/payments/v1/paypal"
  "portal-login|$REST/portal/v1/login/start"
)
if [[ -n "$FORM_ID" ]]; then
  TARGETS+=("forms-page|$SITE/FormsPublic?form=$FORM_ID" "forms-api|$REST/forms/v1/$FORM_ID")
fi
[[ -n "$EVENT_ID" ]] && TARGETS+=("events-page|$SITE/FormsPublic?record=$EVENT_ID")

FAILED=0
for target in "${TARGETS[@]}"; do
  name="${target%%|*}"
  url="${target#*|}"
  echo "== $name: $url"
  # zap-baseline.py exits 0 clean, 1 on FAIL, 2 on WARN only, 3 on an error.
  set +e
  docker run --rm -v "$OUT:/zap/wrk:rw" "$IMAGE" zap-baseline.py \
    -t "$url" -m 1 -r "$name.html" -J "$name.json"
  code=$?
  set -e
  case "$code" in
    0) echo "PASS $name" ;;
    2) echo "WARN $name (review test-results/zap/$name.html)" ;;
    *)
      echo "FAIL $name (exit $code; see test-results/zap/$name.html)"
      FAILED=1
      ;;
  esac
done
exit "$FAILED"
