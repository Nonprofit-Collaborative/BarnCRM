#!/usr/bin/env python3
"""Flags a local, parameter or loop variable named like a constant of the same class.

Apex names are case-insensitive, so a local `draft` hides the class's `DRAFT` for the rest of
its block. The compiler then reads `DRAFT` as the local: an assignment of the wrong type fails
to compile, and a call that happens to fit compiles and does the wrong thing silently. Batch Q
hit both (ConnectorRecipes saveDraft, ConnectorTriggers EVERY, where `EVERY.contains(every)`
quietly became String.contains). Rename the local.

A constant is a `static final` field declared in the file. Every other declaration in the file
whose name matches one, ignoring case, is a finding. A deliberate one is listed in
scripts/ci/shadowed-constants-allowlist.txt as `ClassName.name # reason`.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

ALLOWLIST = "scripts/ci/shadowed-constants-allowlist.txt"
TYPE = r"[A-Za-z_][\w.]*(?:\s*<[^;(){}=]*?>)?(?:\s*\[\s*\])?"
CONSTANT = re.compile(r"\bstatic\s+final\s+" + TYPE + r"\s+(\w+)\s*[=;]", re.IGNORECASE)
CONSTANT_ALT = re.compile(r"\bfinal\s+static\s+" + TYPE + r"\s+(\w+)\s*[=;]", re.IGNORECASE)
DECLARATION = re.compile(r"(?<![\w.])(" + TYPE + r")\s+([A-Za-z_]\w*)\s*(?=[=;:,)])")
NOT_TYPES = {
    "return", "new", "else", "throw", "case", "when", "insert", "update", "delete", "upsert",
    "undelete", "merge", "instanceof", "in", "and", "or", "not", "like", "select", "from",
    "where", "order", "by", "limit", "as", "with", "on",
}


def allowlist():
    entries = set()
    if os.path.exists(ALLOWLIST):
        with open(ALLOWLIST, encoding="utf-8") as handle:
            for line in handle:
                entry = line.split("#", 1)[0].strip()
                if entry:
                    entries.add(entry.lower())
    return entries


def scope(text, position):
    """Where a declaration ending at `position` hides the constant: a parameter's method body or
    a loop variable's loop body, or, for a local, the rest of its block after its own statement
    (its initializer still reads the constant; checked with anonymous Apex, 2026-11-21)."""
    rest = text[position:].lstrip()
    if rest[:1] in ("=", ";"):
        position = text.find(";", position) + 1
    elif rest[:1] in (")", ",", ":"):
        opening = text.find("{", position)
        semicolon = text.find(";", position)
        if opening < 0 or (0 <= semicolon < opening):
            return position, position
        position = opening + 1
    depth = 0
    for index in range(position, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth < 0:
                return position, index
    return position, len(text)


def problems_in(path, allowed):
    with open(path, encoding="utf-8") as handle:
        return problems_in_source(path, handle.read(), allowed)


def problems_in_source(path, source, allowed):
    text = strip(source)
    owner = os.path.basename(path)[:-4]
    constants = {}
    declared_at = set()
    for pattern in (CONSTANT, CONSTANT_ALT):
        for match in pattern.finditer(text):
            constants[match.group(1).lower()] = match.group(1)
            declared_at.add(match.start(1))
    if not constants:
        return []
    found = []
    for match in DECLARATION.finditer(text):
        kind, name = match.group(1), match.group(2)
        if kind.split(".")[0].lower() in NOT_TYPES or match.start(2) in declared_at:
            continue
        key = name.lower()
        if key not in constants or f"{owner.lower()}.{key}" in allowed:
            continue
        constant = constants[key]
        start, end = scope(text, match.end(2))
        if name != constant and re.search(r"(?<![\w.])" + re.escape(constant) + r"\b", text[start:end]):
            line = text.count("\n", 0, match.start(2)) + 1
            found.append(f"{path}:{line}: '{name}' hides the constant {constants[key]} (Apex names ignore case)")
    return found


def main():
    allowed = allowlist()
    problems = []
    for path in sorted(glob.glob("packages/**/classes/*.cls", recursive=True)):
        problems.extend(problems_in(path, allowed))
    for problem in problems:
        print(problem)
    if problems:
        print(f"{len(problems)} declaration(s) hide a constant of their class. Rename them.")
        return 1
    print("No declaration hides a constant of its class.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
