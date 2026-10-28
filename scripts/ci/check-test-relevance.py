#!/usr/bin/env python3
"""Fails if an Apex test class says nothing about which code it tests.

The incremental org gate (scripts/org/run-org-tests.sh, plan D-142) deploys a batch's changed
Apex with the RunRelevantTests test level, and Salesforce picks the tests to run. Its
own dependency analysis follows direct references only, so a test that reaches the
changed class through a trigger, a handler registry or Type.forName is missed. The
class-level @IsTest annotation closes that gap (API 66.0 and later):

    @IsTest(testFor='ApexClass:HouseholdService, ApexTrigger:ContactTrigger')
        runs this class whenever one of those is in the deployment
    @IsTest(critical=true)
        runs this class on every RunRelevantTests deployment (keep these few)

So every test class in packages/ (the vendored rollup engine excepted, it is not part
of the gate) has one of the two, or is named in scripts/ci/test-relevance-cross-cutting.txt
with a reason: a test of declarative metadata or of a test utility, which no Apex
change selects. A name in testFor has to exist in packages/, so a renamed class cannot
leave a test pointing at nothing. Test utilities (an @IsTest class with no test
method, such as TestDataFactory) are not tests and are skipped.

See docs/contributor-guide/ci.md, "Relevant tests".
"""

import os
import re
import subprocess
import sys

CROSS_CUTTING = "scripts/ci/test-relevance-cross-cutting.txt"
CLASS_ANNOTATION = re.compile(
    r"@IsTest\b\s*(?:\((?P<params>[^)]*)\))?(?P<between>(?:\s*@\w+(?:\s*\([^)]*\))?)*)\s*"
    r"(?:(?:public|private|global|virtual|abstract|with sharing|without sharing|inherited sharing)\s+)*"
    r"class\s+(?P<name>\w+)",
    re.I,
)
TEST_METHOD = re.compile(r"@IsTest\b|\btestMethod\b", re.I)
CRITICAL = re.compile(r"\bcritical\s*=\s*true\b", re.I)
TEST_FOR = re.compile(r"\btestFor\s*=\s*'([^']*)'", re.I)
ENTRY = re.compile(r"^(ApexClass|ApexTrigger):(\w+)$")


def strip_comments(source):
    source = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def tracked(pattern):
    out = subprocess.run(["git", "ls-files", pattern], capture_output=True, text=True, check=True).stdout
    return [f for f in out.split("\n") if f and not f.startswith("packages/core/vendor/")]


def load_cross_cutting():
    names = {}
    with open(CROSS_CUTTING, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name, _, reason = line.partition("#")
            names[name.strip()] = (number, reason.strip())
    return names


def main():
    classes = {os.path.basename(f)[:-4]: f for f in tracked("packages/*.cls")}
    triggers = {os.path.basename(f)[:-8] for f in tracked("packages/*.trigger")}
    cross = load_cross_cutting()
    problems = []
    tests = set()
    critical = []
    for name, path in sorted(classes.items()):
        with open(path, encoding="utf-8") as handle:
            source = strip_comments(handle.read())
        match = CLASS_ANNOTATION.search(source)
        if not match or match.group("name").lower() != name.lower():
            continue
        if not TEST_METHOD.search(source, match.end()):
            continue  # a test utility, not a test
        tests.add(name)
        line = source.count("\n", 0, match.start()) + 1
        params = match.group("params") or ""
        targets = TEST_FOR.search(params)
        if CRITICAL.search(params):
            critical.append(name)
        if targets:
            for entry in [e.strip() for e in targets.group(1).split(",")]:
                parsed = ENTRY.match(entry)
                if not parsed:
                    problems.append(f"{path}:{line}: testFor entry '{entry}' is not ApexClass:Name or ApexTrigger:Name")
                    continue
                kind, target = parsed.groups()
                known = classes if kind == "ApexClass" else triggers
                if target not in known:
                    problems.append(f"{path}:{line}: testFor names {kind}:{target}, which is not in packages/")
            if name in cross:
                problems.append(f"{CROSS_CUTTING}:{cross[name][0]}: {name} has a testFor, so take it off this list")
        elif not CRITICAL.search(params) and name not in cross:
            problems.append(
                f"{path}:{line}: {name} has no @IsTest(testFor='ApexClass:...') and no critical=true, "
                f"and is not in {CROSS_CUTTING}: name the classes it tests"
            )
    for name, (number, reason) in sorted(cross.items()):
        if name not in tests:
            problems.append(f"{CROSS_CUTTING}:{number}: {name} is not a test class in packages/")
        elif not reason:
            problems.append(f"{CROSS_CUTTING}:{number}: {name} needs a reason after '#'")
    for problem in problems:
        print(problem)
    if problems:
        print(f"{len(problems)} test relevance problem(s). See docs/contributor-guide/ci.md, \"Relevant tests\".")
        return 1
    print(
        f"Every one of the {len(tests)} test classes names what it tests, is critical, or is listed as cross-cutting. "
        f"Critical ({len(critical)}): {', '.join(critical)}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
