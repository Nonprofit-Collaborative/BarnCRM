#!/usr/bin/env python3
"""Allowlist gate: Core and the modules may name only the standard objects listed here.

Why this exists, next to check-standard-objects.sh
--------------------------------------------------
`check-standard-objects.sh` is a denylist. It fails the build when source names one of
the object names somebody thought to write down. It cannot fail on an object nobody
thought of, which is the failure mode that actually matters: a static Apex reference to
an object a subscriber org does not have is a compile error, and one compile error in one
class refuses the whole package. The product's central compatibility claim (ADR-0009,
ADR-0013, plan Section 4.2) is that Core installs on a Platform-only org, so the gate that
protects it has to be shaped the other way round: everything is forbidden unless it is
listed, and an unrecognized name fails loudly.

The vendored rollup engine (packages/core/vendor, ADR-0015) is inside this gate, not
outside it. It is third party source the project does not write, but it deploys inside
Core's package and a standard object it names is Core's deployment risk exactly like one
Core wrote itself. What the vendor tree gets is its own allowlist section, VENDOR_ONLY
below, with a reason recorded per name. The effect is that today's vendored references are
accepted deliberately and a future upstream upgrade that introduces a new standard object
fails this check instead of being discovered in a subscriber org.

What is scanned, and what is not
--------------------------------
Apex (`*.cls`, `*.trigger`) under every package directory, plus the names of the folders
under `objects/`, which is how a package declares that it extends a standard object.

Names are collected only from positions where a bare identifier can be an SObject type:

  new Name(...)          List<Name>   Set<Name>   Map<..., Name>
  Name.SObjectType       FROM Name    (SOQL, including SOQL inside a string literal)

That is deliberately narrower than every place an SObject can appear. A plain local
declaration (`Account a;`) is not matched, because the same shape is how every Apex system
type is declared and the noise would swamp the signal. Every reference of that kind seen
so far in this repository is accompanied by one of the positions above, so the narrower
set has cost nothing. If that ever stops being true, widen the patterns and extend
SYSTEM_TYPES with whatever falls out: an unknown name fails, so widening is safe.

Names defined in this repository (Apex classes, interfaces, enums, inner types), custom
API names (`__c`, `__mdt`, `__e`, `__x`, `__b`, `__Share`, `__History`) and relationship
names (`__r`) are removed before the allowlist is consulted.

Exit code 1 on any name that is not allowed for the file that names it.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACKAGES = os.path.join(ROOT, "packages")

# Apex system and namespace types that the patterns below can pick up. Not objects.
SYSTEM_TYPES = {
    "AggregateResult",
    "AuraHandledException",
    "Blob",
    "Boolean",
    "CalloutException",
    "Database",
    "Date",
    "Datetime",
    "Decimal",
    "DescribeFieldResult",
    "DescribeSObjectResult",
    "DmlException",
    "DMLException",
    "Double",
    "Exception",
    "FieldSetMember",
    "HttpRequest",
    "HttpResponse",
    "Id",
    "IllegalArgumentException",
    "Integer",
    "JSONGenerator",
    "JSONParser",
    "ListException",
    "Long",
    "Map",
    "MathException",
    "Messaging",
    "NoAccessException",
    "NoDataFoundException",
    "NullPointerException",
    "Object",
    "PageReference",
    "PicklistEntry",
    "QueryException",
    "RestRequest",
    "RestResponse",
    "SearchException",
    "SerializationException",
    "Schema",
    "SObject",
    "SObjectField",
    "SObjectType",
    "String",
    "StringException",
    "System",
    "Test",
    "Time",
    "TriggerOperation",
    "Type",
    "TypeException",
    "Version",
}

# Standard objects any package may name. One line per object, and the line says what
# breaks without it. Adding a name here is a product decision: it is a promise that every
# org BarnCRM claims to support has this object.
ALLOWED = {
    "Account": "the constituent and household record, plan Section 4.3. Core cannot exist without it.",
    "Contact": "the person record, plan Section 4.3. Same.",
    "ContentDocument": "receipt and acknowledgment files, G-13. Platform feature, every edition.",
    "ContentDocumentLink": "attaches a receipt file to its record, G-13.",
    "ContentVersion": "the file body a receipt is written into, G-13.",
    "EmailTemplate": "acknowledgment sending, ADR-0032. Platform feature.",
    "OrgWideEmailAddress": "the from address acknowledgments are sent as, ADR-0032.",
    "StaticResource": "packaged assets read by Apex.",
    "Task": "activity logging on constituents. Platform feature, not Sales Cloud.",
    "User": "the running user, ownership and assignment.",
    "Organization": "org level facts read by Health Check, plan Section 4.8.",
    "Profile": "user setup in tests, and Health Check reporting.",
    # Setup objects. These are how a package inspects or assigns its own access.
    "PermissionSet": "the packaged permission sets, plan Section 4.8.",
    "PermissionSetAssignment": "assigning them, and asserting the assignment in tests.",
    "PermissionSetGroup": "the packaged groups, C-06.",
    "ObjectPermissions": "read back by the access checks in C-06.",
    "FieldPermissions": "same.",
    "SetupEntityAccess": "class and custom permission grants inside a permission set.",
    "CustomPermission": "the packaged custom permissions.",
    "RecordType": "the Household record type, ADR-0005.",
    "UserRecordAccess": "sharing checks in user mode paths.",
    # Async plumbing.
    "AsyncApexJob": "asserting that a queueable or batch was enqueued.",
    "CronTrigger": "the scheduled jobs Core and Giving install.",
    "CronJobDetail": "their names, read back in tests.",
    # Duplicate management, C-20.
    "DuplicateRule": "which duplicate rules are active, read by the duplicate scan, C-20 (ADR-0050). Duplicate management is in every edition.",
    "DuplicateRecordSet": "a duplicate suggestion, written by the scan and read by the review panel, C-20.",
    "DuplicateRecordItem": "the records in a suggestion, C-20.",
    "DuplicateRecordItems": "not an object: the child relationship a subquery from DuplicateRecordSet names, C-20.",
}

# Standard objects only the vendored rollup engine names (ADR-0015,
# packages/core/vendor/apex-rollup/VENDOR.md). Everything here is upstream's own test
# fixture, never reached from BarnCRM code: RollupAdapter is the only caller of the
# engine and it names none of these. They are listed rather than excluded so that an
# upstream upgrade introducing a new one fails this check.
#
# All of them compile and accept DML in a bare Developer edition scratch org with no
# features requested, which is the shape config/scratch-defs/platform-only.json creates.
# The evidence is in VENDOR.md, "Platform-only deployability of the vendored tests".
VENDOR_ONLY = {
    "ContactPointAddress": "upstream's default test calc item after patch E moved the Sales Cloud objects off.",
    "ContactPointAddressChangeEvent": "upstream's change data capture rollup test, RollupTests.",
    "ContactPointAddressHistory": "upstream's negative test for a field that does not exist, RollupFlowTests.",
    "ContactPointConsent": "upstream's second test object, used for parent and grandparent paths.",
    "ContactPointEmail": "same.",
    "ContactPointPhone": "same.",
    "Name": "the polymorphic Name entity, used by RollupRelationshipFieldFinder to spot a polymorphic parent. Present on every org.",
    "Individual": "upstream's grandparent test target, reached through Contact.Individual.",
    "QuickText": "upstream's multi select picklist fixture, RollupCalculatorTests.",
    "Event": "upstream's polymorphic activity fixture.",
    "Asset": "the second child in RollupTests' grouping test, which needs a child that names its Account lookup AccountId as Contact does (patch E).",
    "CurrencyType": "named in a dynamic SOQL string, guarded by the multicurrency check in RollupCurrencyInfo.",
    "DatedConversionRate": "same, and only reached when dated conversion is on.",
}

APEX_SUFFIXES = ("__c", "__mdt", "__e", "__x", "__b", "__Share", "__History", "__r", "__ChangeEvent")

PATTERNS = [
    re.compile(r"\bnew\s+([A-Z][A-Za-z0-9_]*)\s*\("),
    re.compile(r"\b([A-Z][A-Za-z0-9_]*)\.SObjectType\b"),
    re.compile(r"\bFROM\s+([A-Z][A-Za-z0-9_]*)\b"),
    re.compile(r"\b(?:List|Set|Iterator)<\s*([A-Z][A-Za-z0-9_]*)\s*>"),
    re.compile(r"\bMap<\s*[A-Za-z0-9_.]+\s*,\s*([A-Z][A-Za-z0-9_]*)\s*>"),
]

TYPE_DECL = re.compile(r"\b(?:class|interface|enum)\s+([A-Za-z][A-Za-z0-9_]*)")

MARKER = "// detection-only:"


def apex_files():
    for dirpath, _dirnames, filenames in os.walk(PACKAGES):
        for name in filenames:
            if name.endswith((".cls", ".trigger")):
                yield os.path.join(dirpath, name)


def object_folders():
    """Folder names under any objects/ directory: how a package extends an object."""
    for dirpath, dirnames, _filenames in os.walk(PACKAGES):
        if os.path.basename(dirpath) != "objects":
            continue
        for name in dirnames:
            yield name, os.path.join(dirpath, name)


def repo_types(files):
    names = set()
    for path in files:
        names.add(os.path.basename(path).split(".")[0])
        with open(path, encoding="utf-8", errors="replace") as handle:
            for match in TYPE_DECL.finditer(handle.read()):
                names.add(match.group(1))
    return names


def is_vendor(path):
    return os.sep + "vendor" + os.sep in path


def main():
    files = sorted(apex_files())
    defined = repo_types(files)
    findings = {}

    def consider(name, path):
        if name.endswith(APEX_SUFFIXES) or name in defined or name in SYSTEM_TYPES:
            return
        if name in ALLOWED:
            return
        if name in VENDOR_ONLY:
            if is_vendor(path):
                return
            findings.setdefault(name, set()).add(
                os.path.relpath(path, ROOT) + " (allowed only under packages/core/vendor)"
            )
            return
        findings.setdefault(name, set()).add(os.path.relpath(path, ROOT))

    for path in files:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        for line in text.splitlines():
            # The same marker check-standard-objects.sh honours, and for the same reason.
            # A name held as a String constant, or inside the text of a query that is only
            # ever run through Database.query after a describe says the object is there, is
            # not a compile-time reference and cannot refuse a deployment. That is the
            # pattern ADR-0009 requires for an object a subscriber org may not have, so the
            # gate has to permit the one shape the architecture insists on. One marker, one
            # meaning, rather than a second exemption list that can disagree with the first.
            if MARKER in line:
                continue
            for pattern in PATTERNS:
                for match in pattern.finditer(line):
                    consider(match.group(1), path)

    for name, path in object_folders():
        consider(name, path)

    if findings:
        print("Objects named in packages/ that are not on the allowlist:", file=sys.stderr)
        for name in sorted(findings):
            print("  " + name, file=sys.stderr)
            for path in sorted(findings[name])[:5]:
                print("      " + path, file=sys.stderr)
        print("", file=sys.stderr)
        print("A standard object that a subscriber org may not have is a compile error,", file=sys.stderr)
        print("and one compile error refuses the whole package (ADR-0013).", file=sys.stderr)
        print("If the object is present on every org BarnCRM supports, add it to", file=sys.stderr)
        print("ALLOWED in scripts/ci/check-object-allowlist.py with the reason. If it", file=sys.stderr)
        print("arrived with an upstream vendor upgrade, add it to VENDOR_ONLY and record", file=sys.stderr)
        print("it in packages/core/vendor/apex-rollup/VENDOR.md.", file=sys.stderr)
        print("check-object-allowlist.py: FAILED", file=sys.stderr)
        return 1

    print("check-object-allowlist.py: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
