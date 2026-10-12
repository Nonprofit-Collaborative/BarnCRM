#!/usr/bin/env bash
# check-namespace.sh
#
# Fails (exit 1) if:
#   - any file under packages/ (excluding .gitkeep) contains the literal string "barncrm__"
#   - any file under packages/ contains an explicit namespace prefix on a custom component,
#     i.e. a double-underscore-prefixed name followed by another double underscore
#     (namespace__Object__suffix), matched as [A-Za-z0-9]+__[A-Za-z0-9_]+__(c|r|mdt|e|b)
#   - sfdx-project.json has a non-empty "namespace" value
#
# Prints offending lines. Namespace-agnostic development is a hard requirement until the
# namespace is registered (see docs/product-plan.md Section 4.3).
#
# Import template column headings: a shipped import template
# (customMetadata/Import_Template_Default.*.md-meta.xml) names the columns of a file exported
# from another system, and an NPSP export heads its columns with NPSP's own prefixed field
# names, for example npe01__Payment_Amount__c. Those are text compared with a file's header
# row, never a reference to a component of this package, so the prefixed-component check
# lists them and does not fail on them. The literal 'barncrm__' check still covers them.
#
# The exemption is decided on the path part of each grep -rn line (path:line:text), anchored
# at the start, so a line in any other file that names such a path is still checked. For
# example this line in an Apex class fails:
#   // see customMetadata/Import_Template_Default.X.md-meta.xml: npe01__Payment__c
# It exempts whole files, which is safe only while the type has no MetadataRelationship
# field: such a value is resolved against the org at deploy time, so if the type ever gains
# one, revisit this exemption (check-standard-objects.sh carries the same note).

set -euo pipefail

FAILED=0

if [[ -d packages ]]; then
  echo "== Checking for literal 'barncrm__' =="
  if MATCHES=$(grep -rn "barncrm__" packages --include='*' --exclude='.gitkeep' 2>/dev/null); then
    echo "$MATCHES"
    echo "FAIL: found literal 'barncrm__' references above." >&2
    FAILED=1
  fi

  echo "== Checking for explicit namespace-prefixed custom components =="
  TEMPLATE_HEADINGS='^[^:]*/customMetadata/Import_Template_Default\.[^:/]*\.md-meta\.xml:'
  if MATCHES=$(grep -rnE '[A-Za-z0-9]+__[A-Za-z0-9_]+__(c|r|mdt|e|b)' packages --include='*' --exclude='.gitkeep' 2>/dev/null); then
    HEADINGS=$(printf '%s\n' "$MATCHES" | grep -E "$TEMPLATE_HEADINGS" | cut -d: -f1 | sort -u || true)
    MATCHES=$(printf '%s\n' "$MATCHES" | grep -vE "$TEMPLATE_HEADINGS" || true)
    if [[ -n "$HEADINGS" ]]; then
      echo "== Import template column headings, not references =="
      echo "$HEADINGS"
    fi
    if [[ -n "$MATCHES" ]]; then
      echo "$MATCHES"
      echo "FAIL: found explicit namespace-prefixed component references above." >&2
      FAILED=1
    fi
  fi
fi

echo "== Checking sfdx-project.json namespace =="
if [[ -f sfdx-project.json ]]; then
  NS=$(node -e "const p=require('./sfdx-project.json'); process.stdout.write(p.namespace === undefined ? '' : String(p.namespace));")
  if [[ -n "$NS" ]]; then
    echo "FAIL: sfdx-project.json namespace is non-empty: '${NS}'" >&2
    FAILED=1
  fi
fi

if [[ "$FAILED" -eq 1 ]]; then
  echo "check-namespace.sh: FAILED" >&2
  exit 1
fi

echo "check-namespace.sh: OK"
