#!/usr/bin/env python3
"""Fails if an Apex test runs as whoever deploys or runs the tests.

From API version 67.0 a query or DML statement with no access mode runs in user
mode, in test classes too. A test that runs as the deploying user therefore passes
only where that person already holds the BarnCRM permission sets: the org test
gate assigns them, but a check-only deploy, a subscriber org or another
administrator does not, and such a test fails there with "fields being
inaccessible", "No such column" or "You need the Manage BarnCRM Settings
permission". A check-only deploy to a real sandbox failed 565 of 1008 Core tests
this way.

So in packages/core, packages/giving and packages/connect every @IsTest method
and every @TestSetup method calls System.runAs, normally as TestUsers.admin() or TestUsers.adminWith(...), which
creates a user holding the packaged permission sets inside the test
(docs/contributor-guide/ci.md, "Tests run as a user they create").

A test that touches no data and no permission dependent code may say so instead,
with a comment naming why:

    // runs-as: deploying user (pure logic: parses a filter document, no DML or SOQL)

placed anywhere in the class to cover every method, or inside one method (or on
the lines between the previous method and its annotation) to cover that method.
"""

import glob
import re
import sys

SOURCES = [
    "packages/core/main/**/*.cls",
    "packages/giving/main/**/*.cls",
    "packages/connect/main/**/*.cls",
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


def strip(source):
    """Blank out comments and string literals, keeping offsets and line numbers."""
    out = []
    i, n = 0, len(source)
    while i < n:
        c = source[i]
        if source.startswith("//", i):
            j = source.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif source.startswith("/*", i):
            j = source.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", source[i:j]))
            i = j
        elif c == "'":
            j = i + 1
            while j < n and source[j] != "'":
                j += 2 if source[j] == "\\" else 1
            out.append("''" + " " * max(0, j - i - 1))
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


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
    method_spans = [(start, close) for _, start, _, close in methods]
    class_opt_out = any(
        not any(start <= o.start() <= close for start, close in method_spans) for o in OPT_OUT.finditer(raw)
    )
    if class_opt_out:
        return problems
    previous_end = 0
    for name, start, body, close in methods:
        if RUN_AS.search(text, body, close):
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
        print(f"{total} test method(s) depend on the permission sets of whoever runs the tests.")
        return 1
    print(f"Every test in the {len(files)} Core, Giving and Connect Apex files runs as a user it creates, or says why not.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
