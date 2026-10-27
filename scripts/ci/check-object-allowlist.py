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
    "Quiddity",
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
    "AppDefinition": "the Lightning app's DurableId for the Hub's module links (S5). Platform setup object, every edition.",
    "Contact": "the person record, plan Section 4.3. Same.",
    "ContentDocument": "receipt and acknowledgment files, G-13. Platform feature, every edition.",
    "ContentDocumentLink": "attaches a receipt file to its record, G-13; files about a person, counted by Erase a person (R-ER10).",
    "ContentVersion": "the file body a receipt is written into, G-13.",
    "EmailTemplate": "acknowledgment sending, ADR-0032. Platform feature.",
    "OrgWideEmailAddress": "the from address acknowledgments are sent as, ADR-0032.",
    "StaticResource": "packaged assets read by Apex.",
    "Task": "activity logging on constituents. Platform feature, not Sales Cloud.",
    "TaskRelation": "the people a shared task names, counted by Erase a person (R-ER10). Platform feature, every edition.",
    "Event": "events about a person, counted by Erase a person (R-ER10). Platform feature, every edition.",
    "EventRelation": "the people an event names, counted by Erase a person (R-ER10). Platform feature, every edition.",
    "User": "the running user, ownership and assignment.",
    "Organization": "org level facts read by Health Check, plan Section 4.8; the fiscal year start and name the settings console shows (ADR-0135).",
    "FiscalYearSettings": "whether the org defined a custom fiscal year, read by Health Check (ADR-0135). Platform setup object; queried dynamically, so it cannot break the compile.",
    "Profile": "user setup in tests, and Health Check reporting.",
    "Report": "reports not run for a year, read by Org Optimizer's Unused setup section (owner decision 2026-10-13). Platform feature, every edition; queried dynamically, so it cannot break the compile.",
    "PermissionSetGroupComponent": "which permission sets are inside a group, so Unused setup does not call them unassigned. Platform feature, every edition; queried dynamically.",
    "FlowDefinitionView":"inactive flows, read by Org Optimizer's Unused setup section (owner decision 2026-10-13). Platform feature, every edition; queried dynamically.",
    # Setup objects. These are how a package inspects or assigns its own access.
    "PermissionSet": "the packaged permission sets, plan Section 4.8.",
    "PermissionSetAssignment": "assigning them, and asserting the assignment in tests.",
    "PermissionSetGroup": "the packaged groups, C-06.",
    "PermissionSetGroupComponent": "what a packaged group contains, asserted in tests.",
    "UserPermissionAccess": "the running user's effective Assign Permission Sets, checked before the Access page gives an add-on. Every edition.",
    "ObjectPermissions": "read back by the access checks in C-06.",
    "FieldPermissions": "same.",
    "SetupEntityAccess": "class and custom permission grants inside a permission set.",
    "ApexClass": "the class a SetupEntityAccess grant names, asserted in tests. Every org with Apex.",
    "ApexTrigger": "whether a rollup trigger the admin deployed from the Rollup Builder is there and active (ADR-0138). Every org with Apex.",
    "EntityDefinition": "whether an object can carry an Apex trigger, and a custom object's name from its id, for generated rollup triggers (ADR-0138). Every edition.",
    "CustomPermission": "the packaged custom permissions.",
    "RecordType": "the Household record type, ADR-0005.",
    "UserRecordAccess": "sharing checks in user mode paths.",
    "Group": "the All Internal Users group a shared Find query is shared with, C-34. Platform feature, every edition.",
    # Async plumbing.
    "AsyncApexJob": "asserting that a queueable or batch was enqueued.",
    "BatchApexErrorEvent": "a full rollup recalculation chunk the platform stopped, queued again (R-R14). Platform feature, every edition with Apex.",
    "CronTrigger": "the scheduled jobs Core and Giving install.",
    "CronJobDetail": "their names, read back in tests.",
    # Duplicate management, C-20.
    "DuplicateRule": "which duplicate rules are active, read by the duplicate scan, C-20 (ADR-0050). Duplicate management is in every edition.",
    "DuplicateRecordSet": "a duplicate suggestion, written by the scan and read by the review panel, C-20.",
    "DuplicateRecordItem": "the records in a suggestion, C-20.",
    "DuplicateRecordItems": "not an object: the child relationship a subquery from DuplicateRecordSet names, C-20.",
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


def main():
    files = sorted(apex_files())
    defined = repo_types(files)
    findings = {}

    def consider(name, path):
        if name.endswith(APEX_SUFFIXES) or name in defined or name in SYSTEM_TYPES:
            return
        if name in ALLOWED:
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
        print("ALLOWED in scripts/ci/check-object-allowlist.py with the reason.", file=sys.stderr)
        print("check-object-allowlist.py: FAILED", file=sys.stderr)
        return 1

    print("check-object-allowlist.py: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
