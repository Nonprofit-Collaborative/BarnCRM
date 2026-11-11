#!/usr/bin/env bash
# check-standard-objects.sh
#
# Fails (exit 1) if any file under packages/core, packages/rollups, packages/giving,
# packages/volunteers, packages/programs, packages/logicmodels, packages/funders, packages/forms,
# packages/contactpoints, packages/events, packages/portal, packages/corporatehub, packages/lwcbuilder, packages/scholarships or packages/territory (excluding README.md files; see the Contact Point
# Sync note below)
# references, as whole
# words, case-sensitive: Opportunity, Campaign, Lead, Case, OpportunityContactRole,
# CampaignMember, PersonAccount, IsPersonAccount, or any Industries GiftTransaction / __dlm
# name. Those objects and fields may only be referenced from packages/mirror, and even there
# behind dynamic Apex (see docs/product-plan.md Section 4.2).
#
# Mirror's object and field declarations
# ---------------------------------------
# Mirror's Apex may name these objects, as strings resolved through describe, but its
# metadata may not: a lookup to Campaign, a formula through Opportunity, or a field declared
# on Opportunity is resolved at deploy time and refuses the install on an org without the
# object (ADR-0013, ADR-0056, ADR-0058). So everything under packages/mirror/**/objects/ is
# checked too: a folder named after one of these objects fails, and so does one of these
# names anywhere in an object, field or list view file outside its prose (label, description,
# help text, and other human-readable values, which are text, not references). This is why
# Appeal__c.Campaign_Id__c is a Text field, not a lookup.
#
# A second pattern covers the Nonprofit Cloud surface: the fundraising objects, the objects a
# household is actually built out of there (PartyRelationshipGroup and AccountContactRelation),
# and the contact point objects that are its answer to an address. It is checked in Apex and
# metadata only, because a Lightning component's JavaScript cannot reference an SObject and
# our own component class names collide with several of these words.
#
# This half was added after an audit found the gate matched GiftTransaction alone. Core could
# have named PartyRelationshipGroup, the object that decides whether an Account is a Nonprofit
# Cloud household, and CI would have passed it.
#
# Detection-only exemptions
# -------------------------
# Detecting that an object exists is not depending on it. Core has to be able to tell an
# administrator what is installed in their org (Health Check, plan Section 4.8), and that
# means holding a few of these names as String constants passed to Schema.getGlobalDescribe
# or to a field map, never as a compile-time reference.
#
# An Apex line (*.cls or *.trigger) that carries the comment
#
#     // detection-only: <reason>
#
# is exempt from this check. Every exempted line is printed on each run so a reviewer sees
# the whole list without going looking for it. The marker is only honored in Apex, only on
# the line it appears on, and it never exempts a compile-time reference: writing
# Opportunity.Name with the marker appended still means Core will not deploy on a
# Platform-only org. Use it on constant declarations and nowhere else, and keep the reason
# specific enough that the next reader can judge it.
#
# See docs/contributor-guide/ci.md, "Detection-only exemptions".
#
# Import template column headings
# -------------------------------
# A shipped import template (customMetadata/Import_Template_Default.*.md-meta.xml) names the
# columns of a file exported from another system, and a Data Loader export of NPSP or Nonprofit
# Cloud heads its columns with that system's field paths, for example
# GiftTransaction.OriginalAmount. Those words are text the importer compares with a file's
# header row; nothing resolves them against this org's schema, so they are not a reference to
# the object and cannot refuse a deployment. Such files are listed on each run, like the
# detection-only lines, and are not failures. Every other file type, and every other custom
# metadata type, is still checked. The test is on the file's path (the part of grep's output
# before the first colon), never on its content, so an Apex comment naming such a path is not
# exempted.
#
# The exemption covers whole files. That is safe only while Import_Template_Default has no
# MetadataRelationship field: such a field is resolved against the org at deploy time, so a
# value naming another system's object would be a real reference. If the type ever gains one,
# revisit this exemption.
#
# Match sources
# -------------
# A shipped match source (customMetadata/Match_Source.*.md-meta.xml) names a related object
# such as ContactPointEmail as text. MatchSourceService resolves it through describe at run
# time and skips a source whose object is absent, so the word refuses no deployment (ADR-0133,
# 0133-related-record-matching.md). These files are listed with the template headings, by
# path, on the same terms: safe only while Match_Source has no MetadataRelationship field.
#
# D-194: a shipped Integration App (customMetadata/Integration_App.*.md-meta.xml) names the other
# product's objects in Detection Objects as text, such as GiftTransaction for Nonprofit Cloud
# Fundraising. IntegrationAppService only looks the names up in the global describe to tell
# whether the product is installed (MIG-10), so the word refuses no deployment. Listed by path
# on the same terms: safe only while Integration_App has no MetadataRelationship field.

set -euo pipefail

DIRS=(packages/core packages/rollups packages/giving packages/volunteers packages/programs
  packages/logicmodels packages/funders packages/forms packages/contactpoints
  packages/events packages/portal packages/corporatehub packages/payments packages/lwcbuilder packages/scholarships packages/territory)

PATTERN='\b(Opportunity|OpportunityContactRole|Campaign|CampaignMember|Lead|Case|PersonAccount|IsPersonAccount|GiftTransaction)\b|__dlm\b'

# Apex and metadata only. See the note above on JavaScript.
NPC_PATTERN='\b(PartyRelationshipGroup|PartyRoleRelation|AccountAccountRelation|AccountContactRelation|ContactContactRelation|ContactPointAddress|ContactPointEmail|ContactPointPhone|ContactPointConsent|PersonLifeEvent|GiftTransactionDesignation|GiftDesignation|GiftDefaultDesignation|GiftCommitment|GiftCommitmentSchedule|GiftSoftCredit|GiftTribute|GiftRefund|GiftEntry|GiftBatch|OutreachSourceCode|OutreachSummary|DonorGiftSummary|ProgramEnrollment|BenefitAssignment|BenefitDisbursement|RecordAggregationDefinition)\b'
NPC_INCLUDES=(--include='*.cls' --include='*.trigger' --include='*.xml')

# Contact Point Sync (C-45, plan D-111, ADR-0176 contact point sync module)
# -------------------------------------------------------------------------
# packages/contactpoints exists to keep ContactPointEmail, ContactPointPhone and
# ContactPointAddress in step, so those three names, and only those, are allowed there. Its Apex
# reaches them through describe; its object and field metadata may not name them (checked with
# Mirror's declarations below), because such a reference refuses the install on an org without
# them. Every other name in both patterns is still forbidden in the package.
CONTACT_POINT_DIR=packages/contactpoints
CONTACT_POINT_NAMES='ContactPointAddress|ContactPointEmail|ContactPointPhone'
CONTACT_POINT_NPC_PATTERN="${NPC_PATTERN//|ContactPointAddress|ContactPointEmail|ContactPointPhone|/|}"

MARKER='// detection-only:'
TEMPLATE_HEADINGS='/customMetadata/Import_Template_Default.'
MATCH_SOURCES='/customMetadata/Match_Source.'
INTEGRATION_APPS='/customMetadata/Integration_App.'

FAILED=0
EXEMPTED=()
HEADINGS=()
VIOLATIONS=()

for DIR in "${DIRS[@]}"; do
  [[ -d "$DIR" ]] || continue
  MATCHES=$(grep -rnwE "$PATTERN" "$DIR" --include='*' --exclude='README.md' 2>/dev/null || true)
  DIR_NPC_PATTERN="$NPC_PATTERN"
  if [[ "$DIR" == "$CONTACT_POINT_DIR" ]]; then
    DIR_NPC_PATTERN="$CONTACT_POINT_NPC_PATTERN"
  fi
  NPC_MATCHES=$(grep -rnwE "$DIR_NPC_PATTERN" "$DIR" "${NPC_INCLUDES[@]}" \
    --exclude='README.md' 2>/dev/null || true)
  if [[ -n "$NPC_MATCHES" ]]; then
    MATCHES=$(printf '%s\n%s' "$MATCHES" "$NPC_MATCHES")
  fi
  [[ -n "$MATCHES" ]] || continue
  while IFS= read -r LINE; do
    [[ -n "$LINE" ]] || continue
    FILE="${LINE%%:*}"
    if [[ "$FILE" == *.cls || "$FILE" == *.trigger ]] && [[ "$LINE" == *"$MARKER"* ]]; then
      EXEMPTED+=("$LINE")
    elif [[ "$FILE" == *"$TEMPLATE_HEADINGS"*.md-meta.xml ||
      "$FILE" == *"$MATCH_SOURCES"*.md-meta.xml ||
      "$FILE" == *"$INTEGRATION_APPS"*.md-meta.xml ]]; then
      HEADINGS+=("$FILE")
    elif [[ "$FILE" == packages/programs/* ]] &&
      ! printf '%s' "${LINE#*:*:}" | sed -E 's/Case Notes?([^A-Za-z0-9_]|$)/\1/g' | grep -qwE "$PATTERN"; then
      # The Programs module's Case Note (canonical model 29ZA1) is a name, not the standard Case
      # object: a line whose only match is "Case Note" or "Case Notes" passes.
      :
    else
      VIOLATIONS+=("$LINE")
    fi
  done <<< "$MATCHES"
done

if [[ "${#EXEMPTED[@]}" -gt 0 ]]; then
  echo "== Detection-only exemptions (${#EXEMPTED[@]}), review each one =="
  printf '%s\n' "${EXEMPTED[@]}"
fi

if [[ "${#HEADINGS[@]}" -gt 0 ]]; then
  echo "== Import template column headings and match sources, not references =="
  printf '%s\n' "${HEADINGS[@]}" | sort -u
fi

if [[ "${#VIOLATIONS[@]}" -gt 0 ]]; then
  printf '%s\n' "${VIOLATIONS[@]}"
  echo "FAIL: forbidden standard/Industries object reference(s) found above." >&2
  echo "  If the reference is a String constant used only to detect what is installed," >&2
  echo "  append '${MARKER} <reason>' to that Apex line." >&2
  FAILED=1
fi

# Mirror's object and field declarations: see the note at the top. The prose is removed in
# Python because a description spans lines, which grep cannot follow.
MIRROR_DECLARATIONS=$(
  PATTERN="$PATTERN" NPC_PATTERN="$NPC_PATTERN" python3 - <<'PY'
import os, re
names = re.compile(os.environ["PATTERN"] + "|" + os.environ["NPC_PATTERN"])
prose = re.compile(
    r"<(description|label|inlineHelpText|pluralLabel|errorMessage|value)\b[^>]*>.*?</\1>",
    re.DOTALL,
)
comment = re.compile(r"<!--.*?-->", re.DOTALL)
def blank(match):
    return re.sub(r"[^\n]", " ", match.group(0))
walked = [os.walk(root) for root in ("packages/mirror", "packages/contactpoints")]
for directory, subdirs, files in (entry for walk in walked for entry in walk):
    subdirs.sort()
    parts = directory.split(os.sep)
    if "objects" not in parts:
        continue
    index = parts.index("objects")
    if len(parts) > index + 1 and names.fullmatch(parts[index + 1]):
        print("%s: declares metadata on %s" % (directory, parts[index + 1]))
        subdirs[:] = []
        continue
    for name in sorted(files):
        if not name.endswith(".xml") or " 2." in name:
            continue
        path = os.path.join(directory, name)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        stripped = prose.sub(blank, comment.sub(blank, text)).split("\n")
        for number, line in enumerate(stripped, start=1):
            if names.search(line):
                print("%s:%d:%s" % (path, number, text.split("\n")[number - 1]))
PY
)
if [[ -n "$MIRROR_DECLARATIONS" ]]; then
  printf '%s\n' "$MIRROR_DECLARATIONS"
  echo "FAIL: a Mirror or Contact Point Sync object or field declaration names a" >&2
  echo "  standard/Industries object above." >&2
  echo "  Store the record ID as text and reach the object through dynamic Apex." >&2
  FAILED=1
fi

if [[ "$FAILED" -eq 1 ]]; then
  echo "check-standard-objects.sh: FAILED" >&2
  exit 1
fi

echo "check-standard-objects.sh: OK"
