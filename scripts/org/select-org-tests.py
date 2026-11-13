#!/usr/bin/env python3
"""Lists the Apex test classes the incremental org gate runs, one per line.

    select-org-tests.py <base commit> [<head commit, default HEAD>]

run-org-tests.sh (incremental mode, plan D-142) runs these with RunSpecifiedTests after the
staged deploy. A test class is selected when it is:

  1. a test class changed (added or modified) between base and head;
  2. a test class whose @IsTest(testFor=...) names a class or trigger changed in that range;
  3. a test class whose source mentions a changed class by name (comments ignored): the test
     calls it directly, or through a changed test utility such as TestDataFactory;
  4. an @IsTest(critical=true) class, which runs every time;
  5. a test class whose source names changed metadata (QA review Q9), so a change with no Apex
     in it still runs the tests that depend on it:
       - an object or anything under it (field, validation rule, record type, list view): a
         custom object (`__c`, `__mdt`, `__e`) by its API name; on a standard object, the
         changed field's API name, since nearly every test names Contact or Account;
       - a permission set, permission set group or custom permission: its API name;
       - a flow: its API name, and the custom object it starts on;
       - a custom metadata record: its type (`Type__mdt`) and its record name.
     A test utility (an @IsTest class with no test method, such as TestUsers) that names the
     metadata counts as changed too, so its users are selected: a change to BarnCRM_Admin
     reaches every test that runs as TestUsers.admin().

The vendored rollup engine (packages/core/vendor/) is never selected, as in the release run.
The tree read is the working tree, which the gate has already checked matches HEAD.

Why not RunRelevantTests: on landing batches 9 and 10 a deploy of 83 changed Apex files (about
60 of them test classes) with --test-level RunRelevantTests ran only the 5 critical classes
(153 tests). The selection is beta and did not honour testFor or the test classes in the
payload, so the gate passed without running the changed tests. See docs/contributor-guide/ci.md,
"The incremental gate".
"""

import importlib.util
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "check_test_relevance", os.path.join(HERE, "..", "ci", "check-test-relevance.py")
)
relevance = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(relevance)

VENDOR = "packages/core/vendor/"


def changed_apex(base, head):
    out = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=d", base, head, "--",
         "packages/*.cls", "packages/*.trigger"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [f for f in out.split("\n") if f]


CUSTOM_SUFFIX = re.compile(r"__(c|mdt|e)$", re.I)
FLOW_OBJECT = re.compile(r"<start>.*?<object>(\w+)</object>", re.S)


def changed_metadata(base, head):
    """Changed (added or modified) packaged files other than Apex."""
    out = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=d", base, head, "--", "packages/"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [
        f for f in out.split("\n")
        if f and not f.endswith((".cls", ".trigger", ".cls-meta.xml", ".trigger-meta.xml"))
        and not f.startswith(VENDOR)
    ]


def metadata_names(path):
    """The API names a test would use to depend on this changed metadata file."""
    parts = path.split("/")
    file_name = parts[-1]
    stem = file_name.split(".", 1)[0]
    if "objects" in parts:
        position = parts.index("objects")
        if position + 1 >= len(parts):
            return set()
        object_name = parts[position + 1]
        if CUSTOM_SUFFIX.search(object_name):
            return {object_name}
        if "fields" in parts and stem.endswith("__c"):
            return {stem}
        return set()
    if "permissionsets" in parts or "permissionsetgroups" in parts or "customPermissions" in parts:
        return {stem}
    if "flows" in parts:
        names = {stem}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                found = FLOW_OBJECT.search(handle.read())
            if found and CUSTOM_SUFFIX.search(found.group(1)):
                names.add(found.group(1))
        return names
    if "customMetadata" in parts:
        type_name, _, record = file_name[: -len(".md-meta.xml")].partition(".")
        return {type_name + "__mdt", record} - {""}
    return set()


def test_classes():
    """{name: (stripped source, testFor targets, critical)} for every test class with a test method."""
    return scan()[0]


def scan():
    """The test classes, as test_classes() gives them, and {name: stripped source} of the test
    utilities (@IsTest classes with no test method)."""
    found = {}
    utilities = {}
    for path in relevance.tracked("packages/*.cls"):
        name = os.path.basename(path)[:-4]
        with open(path, encoding="utf-8") as handle:
            source = relevance.strip_comments(handle.read())
        match = relevance.CLASS_ANNOTATION.search(source)
        if not match or match.group("name").lower() != name.lower():
            continue
        if not relevance.TEST_METHOD.search(source, match.end()):
            utilities[name] = source  # never run itself, but a change to it selects its users
            continue
        params = match.group("params") or ""
        targets = set()
        test_for = relevance.TEST_FOR.search(params)
        if test_for:
            for entry in test_for.group(1).split(","):
                parsed = relevance.ENTRY.match(entry.strip())
                if parsed:
                    targets.add(parsed.group(2).lower())
        found[name] = (source, targets, bool(relevance.CRITICAL.search(params)))
    return found, utilities


def mentioning(names):
    return re.compile(r"\b(" + "|".join(sorted(map(re.escape, names))) + r")\b", re.I)


def select(base, head="HEAD"):
    tests, utilities = scan()
    changed = {os.path.basename(f).rsplit(".", 1)[0] for f in changed_apex(base, head)}
    metadata = set()
    for path in changed_metadata(base, head):
        metadata |= metadata_names(path)
    if metadata:
        named = mentioning(metadata)
        changed |= {name for name, source in utilities.items() if named.search(source)}
        changed |= metadata
    lowered = {c.lower() for c in changed}
    mention = None
    if changed:
        mention = mentioning(changed)
    selected = set()
    for name, (source, targets, critical) in tests.items():
        if (
            critical
            or name.lower() in lowered
            or targets & lowered
            or (mention and mention.search(source))
        ):
            selected.add(name)
    return sorted(selected)


def main(argv):
    if len(argv) not in (2, 3):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    for name in select(argv[1], argv[2] if len(argv) == 3 else "HEAD"):
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
