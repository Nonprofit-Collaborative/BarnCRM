#!/usr/bin/env python3
"""Flags @AuraEnabled methods that Lightning Data Service or GraphQL can do (ADR-0093).

A method whose body is one user-mode query over one object, with no aggregate, describe,
service call or system-mode work, is a read the LWC can make with a GraphQL wire or getRecord.
A method whose body is one single-record DML statement with no query and no service call is
a write uiRecordApi (createRecord, updateRecord, deleteRecord) does. Each one is Apex the org
must carry, and one more @AuraEnabled entry point to review, for no gain.

The heuristic follows the classification in the alternative architectures review (classes R
and W): the method body plus same-class static helpers it calls is classed by what it does.
A method that is a justified exception is listed in scripts/ci/aura-lds-allowlist.txt as
Class.method. Entries are removed as methods are converted; a stale entry (the method is gone
or no longer matches) fails the check so the list only shrinks.

    python3 scripts/ci/check-aura-lds.py            the check
    python3 scripts/ci/check-aura-lds.py --list     every match, as allowlist lines
"""

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from apex_source import is_test_class, strip, without_comments  # noqa: E402

SOURCES = "packages/*/main/**/*.cls"
ALLOWLIST = os.path.join(HERE, "aura-lds-allowlist.txt")

SIG = re.compile(
    r"@AuraEnabled[^\n]*\n\s*(?:public|global)\s+static\s+([\w<>,\s\.\[\]]+?)\s+(\w+)\s*\(([^)]*)\)\s*\{",
    re.S,
)
HELPER = re.compile(r"\n\s*(?:private|public)\s+static\s+[\w<>,\s\.\[\]]+?\s+(\w+)\s*\([^)]*\)\s*\{")
QUERY = re.compile(r"\[\s*SELECT|Database\.(?:query|queryWithBinds)\(", re.I)
USER_MODE = re.compile(r"USER_MODE|SECURITY_ENFORCED", re.I)
DML = re.compile(
    r"\b(?:insert|update|upsert|delete|undelete)\s+[\w\.\(\)\[\]]"
    r"|Database\.(?:insert|update|upsert|delete|undelete|merge)|\bmerge\s+\w",
    re.I,
)
AGGREGATE = re.compile(r"\b(?:COUNT|SUM|AVG|MIN|MAX)\s*\(|GROUP BY|countQuery", re.I)
HEAVY = re.compile(
    r"HttpRequest|new Http\(|enqueueJob|executeBatch|EventBus|Messaging\.|getDescribe"
    r"|getGlobalDescribe|describeSObjects|Metadata\.|Type\.forName|Cursor|FOR UPDATE"
    r"|SYSTEM_MODE|without sharing",
    re.I,
)
PLAIN = {
    "System", "String", "Id", "Math", "Date", "Datetime", "Decimal", "Integer", "JSON", "UserInfo",
    "Limits", "Database", "AccessLevel", "Security", "NamespaceUtil", "List", "Set", "Map", "Label",
    "AuraHandledException",
}
SERVICE_SUFFIX = re.compile(
    r"(Service|Handler|Selector|Engine|Job|Batch|Calculator|Matcher|Importer|Detector|Planner"
    r"|Dispatcher|Queue|Builder|Runner|Processor|Generator|Scanner|Analyzer|Merger|Writer"
    r"|Loader|Mover|Kit|Api|Sync)$"
)
SINGLE_DML_MAX = 900


def body_of(src, start):
    depth, i = 1, start
    while depth and i < len(src):
        depth += (src[i] == "{") - (src[i] == "}")
        i += 1
    return src[start : i - 1]


def lds_candidates(raw):
    """Return {method name: 'read' or 'write'} for the methods in one Apex class source."""
    if is_test_class(raw) or "@AuraEnabled" not in raw:
        return {}
    src = without_comments(raw)
    helpers = {m.group(1): body_of(src, m.end()) for m in HELPER.finditer(src)}
    found = {}
    for m in SIG.finditer(src):
        name = m.group(2)
        code = body_of(src, m.end())
        inlined = code
        for called in set(re.findall(r"(?<![\.\w])(\w+)\s*\(", code)):
            if called in helpers and called != name:
                inlined += helpers[called]
        services = {
            s
            for s in set(re.findall(r"\b([A-Z]\w+)\.\w+\s*\(", inlined)) - PLAIN
            if SERVICE_SUFFIX.search(s) and "FeatureSwitch" not in s
        }
        queries = len(QUERY.findall(inlined))
        # DML is counted with string literals blanked, so a message such as 'Bulk update
        # fields' is not a write; queries keep them, since a dynamic query is a string.
        writes = len(DML.findall(strip(inlined)))
        if HEAVY.search(inlined) or AGGREGATE.search(inlined) or services:
            continue
        if queries == 1 and writes == 0 and USER_MODE.search(inlined):
            found[name] = "read"
        elif queries == 0 and writes == 1 and len(code) < SINGLE_DML_MAX:
            found[name] = "write"
    return found


def load_allowlist(path=ALLOWLIST):
    entries = set()
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if line:
                    entries.add(line)
    return entries


def find_all(root="."):
    """Return {'Class.method': kind} across every package."""
    result = {}
    for path in sorted(glob.glob(os.path.join(root, SOURCES), recursive=True)):
        with open(path, errors="ignore") as f:
            raw = f.read()
        cls = os.path.basename(path)[:-4]
        for method, kind in lds_candidates(raw).items():
            result[f"{cls}.{method}"] = kind
    return result


def evaluate(found, allowed):
    """Return (new matches not allowed, allowlist entries that no longer match)."""
    new = sorted(k for k in found if k not in allowed)
    stale = sorted(a for a in allowed if a not in found)
    return new, stale


def main(argv):
    found = find_all()
    if "--list" in argv:
        for key in sorted(found):
            print(key)
        return 0
    new, stale = evaluate(found, load_allowlist())
    for key in new:
        print(
            f"{key}: an @AuraEnabled method that is only a single {found[key]} of one object."
            " Use Lightning Data Service or a GraphQL wire in the LWC (ADR-0093), or add"
            " Class.method to scripts/ci/aura-lds-allowlist.txt with a reason.",
            file=sys.stderr,
        )
    for key in stale:
        print(
            f"{key}: in scripts/ci/aura-lds-allowlist.txt but no longer a match. Remove the line.",
            file=sys.stderr,
        )
    if new or stale:
        print(f"check-aura-lds.py: FAILED, {len(new) + len(stale)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-aura-lds.py: OK, {len(found)} allowlisted candidate(s) left to convert")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
