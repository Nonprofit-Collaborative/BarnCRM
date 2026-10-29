#!/usr/bin/env python3
"""Lists the Apex test classes the incremental org gate runs, one per line.

    select-org-tests.py <base commit> [<head commit, default HEAD>]

run-org-tests.sh (incremental mode, plan D-142) runs these with RunSpecifiedTests after the
staged deploy. A test class is selected when it is:

  1. a test class changed (added or modified) between base and head;
  2. a test class whose @IsTest(testFor=...) names a class or trigger changed in that range;
  3. a test class whose source mentions a changed class by name (comments ignored): the test
     calls it directly, or through a changed test utility such as TestDataFactory;
  4. an @IsTest(critical=true) class, which runs every time.

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


def test_classes():
    """{name: (stripped source, testFor targets, critical)} for every test class with a test method."""
    found = {}
    for path in relevance.tracked("packages/*.cls"):
        name = os.path.basename(path)[:-4]
        with open(path, encoding="utf-8") as handle:
            source = relevance.strip_comments(handle.read())
        match = relevance.CLASS_ANNOTATION.search(source)
        if not match or match.group("name").lower() != name.lower():
            continue
        if not relevance.TEST_METHOD.search(source, match.end()):
            continue  # a test utility: never run itself, but a change to it selects its users
        params = match.group("params") or ""
        targets = set()
        test_for = relevance.TEST_FOR.search(params)
        if test_for:
            for entry in test_for.group(1).split(","):
                parsed = relevance.ENTRY.match(entry.strip())
                if parsed:
                    targets.add(parsed.group(2).lower())
        found[name] = (source, targets, bool(relevance.CRITICAL.search(params)))
    return found


def select(base, head="HEAD"):
    tests = test_classes()
    changed = {os.path.basename(f).rsplit(".", 1)[0] for f in changed_apex(base, head)}
    lowered = {c.lower() for c in changed}
    mention = None
    if changed:
        mention = re.compile(r"\b(" + "|".join(sorted(map(re.escape, changed))) + r")\b", re.I)
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
