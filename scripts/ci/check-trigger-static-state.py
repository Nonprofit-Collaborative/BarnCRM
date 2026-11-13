#!/usr/bin/env python3
"""Flags a trigger handler that replaces its static before-to-after state (QA review Q4, D-200).

A handler that notes something in a before event and reads it in the after event keeps it in a
static collection, because the before and after events run in different handler instances.
Assigning a new collection to that static in a before method (`departing = new Map...`) or
clearing it there loses what an earlier chunk noted: a save of more than 200 rows runs the
trigger once per 200, every before runs before any after in some paths, and a dispatcher that
retries the rows that did not fail runs the before again. Defect D1 (ContactTriggerHandler and
AccountTriggerHandler beforeDelete) was this. Add to the collection instead, keyed by record Id,
as VolunteerPersonDeleteHandler does, and remove what the after event has used.

A class is a trigger handler when it extends or implements a `TriggerHandler`. Its static
`Map`, `Set` and `List` fields are checked in every method whose name starts with `before`.
A deliberate reset is listed in scripts/ci/trigger-static-state-allowlist.txt as
`ClassName.fieldName # reason`.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import is_test_class, strip  # noqa: E402

ALLOWLIST = "scripts/ci/trigger-static-state-allowlist.txt"
HANDLER = re.compile(r"\b(?:extends|implements)\s+[\w.]*TriggerHandler\b")
CLASS_NAME = re.compile(r"\bclass\s+(\w+)")
STATIC_FIELD = re.compile(
    r"\bstatic\s+(?:final\s+)?(?:Map|Set|List)\s*<[^;(){}]*?>\s+(\w+)\s*[=;]"
)
BEFORE = re.compile(r"\bvoid\s+(before\w*)\s*\([^)]*\)\s*\{")


def body_end(text, start):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(text)


def problems_in(path):
    with open(path, encoding="utf-8") as handle:
        raw = handle.read()
    if is_test_class(raw):
        return []
    text = strip(raw)
    if not HANDLER.search(text):
        return []
    owner = CLASS_NAME.search(text)
    owner = owner.group(1) if owner else os.path.basename(path)[:-4]
    fields = set(STATIC_FIELD.findall(text))
    found = []
    for method in BEFORE.finditer(text):
        open_brace = method.end() - 1
        body = text[open_brace : body_end(text, open_brace)]
        for field in fields:
            replaced = re.search(
                r"(?<![\w.])" + re.escape(field) + r"\s*=(?!=)|(?<![\w.])"
                + re.escape(field) + r"\s*\.\s*clear\s*\(",
                body,
            )
            if replaced:
                line = text.count("\n", 0, open_brace + replaced.start()) + 1
                found.append((f"{owner}.{field}", path, line, method.group(1)))
    return found


def read_allowlist():
    entries = {}
    if os.path.exists(ALLOWLIST):
        with open(ALLOWLIST, encoding="utf-8") as handle:
            for line in handle:
                if line.strip() and not line.lstrip().startswith("#"):
                    name, _, reason = line.partition("#")
                    entries[name.strip()] = reason.strip()
    return entries


def main():
    allowed = read_allowlist()
    problems = []
    for path in sorted(glob.glob("packages/*/main/**/*.cls", recursive=True)):
        for key, where, line, method in problems_in(path):
            if allowed.get(key):
                continue
            problems.append(
                f"{where}:{line}: {method} replaces or clears the static {key}, which carries "
                "state from the before event to the after event; add to it, keyed by record Id, "
                f"or list it in {ALLOWLIST} with the reason."
            )
    if problems:
        print("\n".join(problems))
        return 1
    print("check-trigger-static-state: no trigger handler replaces its before-to-after state.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
