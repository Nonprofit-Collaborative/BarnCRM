#!/usr/bin/env python3
"""Fails if packaged Apex leaves its sharing or access mode to the platform default.

From API version 67.0 the defaults changed: database operations run in user mode
unless they say otherwise, and a class with no sharing keyword runs with sharing
(Apex Developer Guide, Versioned Behavior Changes, Version 67.0). Code written
when system mode was the default can silently start failing for limited users,
and code read without the version in mind is ambiguous. So every packaged class
states its sharing, and every query and DML statement states its access mode:

- a top-level class, outside test classes, interfaces and enums, declares
  with sharing, without sharing or inherited sharing;
- an inline SOQL or SOSL query carries WITH USER_MODE or WITH SYSTEM_MODE;
- a DML statement is written insert as user, update as system, and so on;
- a Database or Search method that takes an access level is passed one, or, when
  its query string carries its own WITH clause, says so in an "// Access mode:"
  comment on the line of the call or the line above.

An inner class does not take its outer class's sharing, so one that touches the
database states its own.

Test classes are not checked: they run as the test user and set up data on
purpose.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

SOURCES = ["packages/*/main/**/*.cls", "packages/*/main/**/*.trigger"]

DB_METHODS = (
    "query|getQueryLocator|countQuery|getCursor|getPaginationCursor|"
    "insert|update|upsert|delete|undelete|merge|convertLead|"
    "insertImmediate|updateImmediate|deleteImmediate|"
    "insertAsync|updateAsync|deleteAsync"
)
DB_CALL = re.compile(r"\b(Database\.(?:" + DB_METHODS + r")|Search\.query)\s*\(", re.I)
DML = re.compile(
    r"(?:^|[;{}]|\belse\b|\))\s*(insert|update|upsert|delete|undelete|merge)\b(?!\s*\()",
    re.I | re.M,
)
DML_MODE = re.compile(r"\s+as\s+(user|system)\b", re.I)
INLINE_QUERY = re.compile(r"\[\s*(SELECT|FIND)\b", re.I)
QUERY_MODE = re.compile(r"\bWITH\s+(USER_MODE|SYSTEM_MODE)\b", re.I)
CLASS_DECL = re.compile(
    r"^((?:\s*@\w+(?:\([^)]*\))?)*)\s*((?:\w+\s+)*?)(class|interface|enum)\s+(\w+)",
    re.I | re.M,
)
SHARING = re.compile(r"\b(with|without|inherited)\s+sharing\b", re.I)
MARKER = re.compile(r"//\s*Access mode:", re.I)


def closing(text, start, open_char, close_char):
    """Index just past the bracket that closes the one at text[start]."""
    depth = 0
    for k in range(start, len(text)):
        if text[k] == open_char:
            depth += 1
        elif text[k] == close_char:
            depth -= 1
            if depth == 0:
                return k + 1
    return len(text)


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def check(path):
    raw = open(path, encoding="utf-8").read()
    text = strip(raw)
    raw_lines = raw.split("\n")
    problems = []
    is_trigger = path.endswith(".trigger")
    is_test = re.search(r"@isTest\b", text, re.I) and not is_trigger
    first = CLASS_DECL.search(text)
    if is_test and first and re.search(r"@isTest", first.group(1), re.I):
        return problems
    if not is_trigger and first and first.group(3).lower() == "class":
        if not SHARING.search(first.group(2)):
            problems.append((line_of(text, first.start(4)), f"class {first.group(4)} has no sharing keyword"))
        # An inner class never takes its outer class's sharing, so one that
        # touches the database states its own.
        for inner in CLASS_DECL.finditer(text, first.end()):
            if inner.group(3).lower() != "class" or SHARING.search(inner.group(2)):
                continue
            body_start = text.find("{", inner.end())
            body = text[body_start:closing(text, body_start, "{", "}")]
            if INLINE_QUERY.search(body) or DML.search(body) or DB_CALL.search(body):
                problems.append(
                    (line_of(text, inner.start(4)), f"inner class {inner.group(4)} touches the database but has no sharing keyword")
                )
    for m in INLINE_QUERY.finditer(text):
        end = closing(text, m.start(), "[", "]")
        if not QUERY_MODE.search(text[m.start():end]):
            problems.append((line_of(text, m.start()), "inline query has no WITH USER_MODE or WITH SYSTEM_MODE"))
    for m in DML.finditer(text):
        if not DML_MODE.match(text, m.end(1)):
            problems.append((line_of(text, m.start(1)), f"{m.group(1)} statement has no 'as user' or 'as system'"))
    for m in DB_CALL.finditer(text):
        end = closing(text, m.end() - 1, "(", ")")
        args = text[m.end():end]
        line = line_of(text, m.start())
        # An inline query argument carries its own mode, checked above. A query string that
        # states its own WITH clause is marked by an "Access mode:" comment on the line or
        # the line above, since the string may be built far from the call.
        marked = any(MARKER.search(l) for l in raw_lines[max(0, line - 2):line])
        if "accesslevel" not in args.lower() and not INLINE_QUERY.search(args) and not marked:
            problems.append((line, f"{m.group(1)} has no AccessLevel argument"))
    return problems


def main():
    files = sorted({f for pattern in SOURCES for f in glob.glob(pattern, recursive=True)})
    total = 0
    for f in files:
        for line, message in sorted(check(f)):
            print(f"{f}:{line}: {message}")
            total += 1
    if total:
        print(f"{total} place(s) rely on the API 67.0 sharing or access mode default; state it explicitly.")
        return 1
    print(f"All {len(files)} packaged Apex files state their sharing and access modes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
