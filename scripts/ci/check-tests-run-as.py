#!/usr/bin/env python3
"""Fails if an Apex test runs as whoever deploys or runs the tests.

From API version 67.0 a query or DML statement with no access mode runs in user
mode, in test classes too. A test that runs as the deploying user therefore passes
only where that person already holds the BarnCRM permission sets. The org test
gate assigns them to no one, and a check-only deploy, a subscriber org or another
administrator may not have them, and such a test fails there with "fields being
inaccessible", "No such column" or "You need the Manage BarnCRM Settings
permission". A check-only deploy to a real sandbox failed 565 of 1008 Core tests
this way.

So in packages/core, packages/rollups, packages/giving, packages/volunteers, packages/programs and packages/mirror every @IsTest method
and every @TestSetup method calls System.runAs, normally as TestUsers.admin() or TestUsers.adminWith(...), which
creates a user holding the packaged permission sets inside the test
(docs/contributor-guide/ci.md, "Tests run as a user they create").

A test that touches no data and no permission dependent code may say so instead,
with a comment naming why:

    // runs-as: deploying user (pure logic: parses a filter document, no DML or SOQL)

placed anywhere in the class to cover every method, or inside one method (or on
the lines between the previous method and its annotation) to cover that method.

A @TestSetup method whose body only calls TestUsers (creating the class's test
user once, so its test methods find it instead of each creating one) needs no
runAs. And a TestUsers call made in two or more test methods of a class must also
be made in a @TestSetup of that class: TestUsers keeps a user per transaction
only, so otherwise every test method inserts the user and its permission set
assignments again.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

SOURCES = [
    "packages/core/main/**/*.cls",
    "packages/rollups/main/**/*.cls",
    "packages/giving/main/**/*.cls",
    "packages/volunteers/main/**/*.cls",
    "packages/programs/main/**/*.cls",
    "packages/mirror/main/**/*.cls",
]
OPT_OUT = re.compile(r"//\s*runs-as:\s*deploying user\s*\(\s*\S[^\n]*\)", re.I)
OPT_OUT_LOOSE = re.compile(r"//\s*runs-as:", re.I)
ANNOTATION = re.compile(r"@(IsTest|TestSetup)\b(\s*\([^)]*\))?", re.I)
METHOD = re.compile(
    r"\s*(?:@\w+(?:\s*\([^)]*\))?\s*)*"
    r"(?:(?:public|private|global|protected|static|testmethod|override|virtual)\s+)*"
    r"void\s+(\w+)\s*\(\s*\)\s*\{",
    re.I,
)
LEGACY = re.compile(r"\b(?:static\s+testmethod|testmethod\s+static)\s+void\s+(\w+)\s*\(\s*\)\s*\{", re.I)
RUN_AS = re.compile(r"\bSystem\s*\.\s*runAs\s*\(", re.I)
TEST_SETUP = re.compile(r"@TestSetup\b", re.I)
TEST_USERS_CALL = re.compile(r"\bTestUsers\s*\.\s*\w+\s*\(", re.I)
# A @TestSetup whose body only creates the class's test users (TestUsers writes them in a
# context of its own) needs no runAs: there is nothing in it to run as anyone.
TEST_USERS_ONLY = re.compile(r"\s*(?:TestUsers\s*\.\s*\w+\s*\([^;]*\)\s*;\s*)+", re.I)


def creates_test_users_only(text, start, body, close):
    """True for a @TestSetup method whose body is only TestUsers calls."""
    return bool(TEST_SETUP.search(text, start, body)) and bool(TEST_USERS_ONLY.fullmatch(text, body + 1, close))


def test_users_calls(text, raw, start, end):
    """Each TestUsers call between start and end, as written, whitespace removed."""
    calls = set()
    for m in TEST_USERS_CALL.finditer(text, start, end):
        depth, k = 0, m.end() - 1
        while k < end:
            depth += {"(": 1, ")": -1}.get(text[k], 0)
            if depth == 0:
                break
            k += 1
        calls.add(re.sub(r"\s+", "", raw[m.start() : k + 1]))
    return calls


def setup_user_problems(raw, text, methods):
    """A TestUsers call made in two or more test methods must also be made in a @TestSetup.

    TestUsers keeps its users per transaction only, and each test method is a transaction
    of its own, so without a @TestSetup every method inserts the user and its permission
    set assignments again (about 330 ms each). A user created in @TestSetup is found again
    by username in every test method.
    """
    in_setup, first_line, count = set(), {}, {}
    for _, start, body, close in methods:
        calls = test_users_calls(text, raw, body, close)
        if TEST_SETUP.search(text, start, body):
            in_setup |= calls
            continue
        for call in calls:
            first_line.setdefault(call, raw.count("\n", 0, start) + 1)
            count[call] = count.get(call, 0) + 1
    return [
        (
            first_line[call],
            f"{call} is called in {count[call]} test methods: call it once in a @TestSetup method "
            "too, so the user is created once per class, not once per method",
        )
        for call in count
        if count[call] >= 2 and call not in in_setup
    ]


def closing(text, start):
    """Index of the brace that closes the one at text[start]."""
    depth = 0
    for k in range(start, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return k
    return len(text)


def test_methods(text):
    """(name, annotation start, body open, body close) for every test and test setup method."""
    found = {}
    for a in ANNOTATION.finditer(text):
        m = METHOD.match(text, a.end())
        if m:
            found.setdefault(m.end() - 1, (m.group(1), a.start()))
    for m in LEGACY.finditer(text):
        found.setdefault(m.end() - 1, (m.group(1), m.start()))
    return [(name, start, body, closing(text, body)) for body, (name, start) in sorted(found.items())]


def check(path):
    raw = open(path, encoding="utf-8").read()
    text = strip(raw)
    methods = test_methods(text)
    if not methods:
        return []
    problems = []
    for m in OPT_OUT_LOOSE.finditer(raw):
        line_end = raw.find("\n", m.start())
        if not OPT_OUT.match(raw, m.start(), line_end if line_end >= 0 else len(raw)):
            problems.append(
                (raw.count("\n", 0, m.start()) + 1, "runs-as comment must read '// runs-as: deploying user (reason)'")
            )
    problems.extend(setup_user_problems(raw, text, methods))
    method_spans = [(start, close) for _, start, _, close in methods]
    class_opt_out = any(
        not any(start <= o.start() <= close for start, close in method_spans) for o in OPT_OUT.finditer(raw)
    )
    if class_opt_out:
        return problems
    previous_end = 0
    for name, start, body, close in methods:
        if RUN_AS.search(text, body, close) or creates_test_users_only(text, start, body, close):
            previous_end = close
            continue
        if OPT_OUT.search(raw, previous_end, close):
            previous_end = close
            continue
        problems.append(
            (
                raw.count("\n", 0, start) + 1,
                f"{name} runs as the deploying user: wrap it in System.runAs(TestUsers.admin()) "
                "or say why not with '// runs-as: deploying user (reason)'",
            )
        )
        previous_end = close
    return problems


def main():
    files = sorted({f for pattern in SOURCES for f in glob.glob(pattern, recursive=True)})
    total = 0
    for f in files:
        for line, message in sorted(check(f)):
            print(f"{f}:{line}: {message}")
            total += 1
    if total:
        print(
            f"{total} problem(s): a test that depends on the permission sets of whoever runs the "
            "tests, or a test user created in every method instead of once in @TestSetup."
        )
        return 1
    print(f"Every test in the {len(files)} Core, Giving and Mirror Apex files runs as a user it creates, or says why not.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
