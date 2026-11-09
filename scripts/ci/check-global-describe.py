#!/usr/bin/env python3
"""Fails when packaged Apex calls Schema.getGlobalDescribe() anywhere but NamespaceUtil.

The org's global describe costs about 12 ms of CPU in an org with a thousand objects, and the
objects an org has cannot change within a transaction. NamespaceUtil.globalDescribe() reads it
once per transaction and running user and every class shares that copy (D-143). A class that
calls Schema.getGlobalDescribe() itself pays again; Batch C had drifted back in seven classes.

Test classes (a file whose name ends in Test.cls, or that is @IsTest) are exempt: they may
describe the org to check what the product sees.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

ALLOWED = {"NamespaceUtil.cls"}
CALL = re.compile(r"\bSchema\s*\.\s*getGlobalDescribe\s*\(", re.I)
TEST_CLASS = re.compile(r"^\s*@IsTest\b[^\n]*\n(\s*@\w+[^\n]*\n)*\s*(public|private|global)?\s*(with|without|inherited)?\s*(sharing)?\s*class\b", re.I | re.M)


def is_test(path, source):
    return path.endswith("Test.cls") or bool(TEST_CLASS.search(source))


def check_sources(sources):
    """sources: {path: stripped Apex}. Returns a list of problems."""
    problems = []
    for path, source in sorted(sources.items()):
        if os.path.basename(path) in ALLOWED or is_test(path, source):
            continue
        for number, line in enumerate(source.split("\n"), 1):
            if CALL.search(line):
                problems.append(
                    f"{path}:{number}: Schema.getGlobalDescribe() called directly: "
                    "use NamespaceUtil.globalDescribe(), read once per transaction"
                )
    return problems


def main():
    sources = {}
    for path in glob.glob("packages/*/main/default/classes/*.cls"):
        with open(path, encoding="utf-8") as handle:
            sources[path] = strip(handle.read())
    problems = check_sources(sources)
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-global-describe.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-global-describe.py: OK, {len(sources)} classes read the global describe only through NamespaceUtil")
    return 0


if __name__ == "__main__":
    sys.exit(main())
