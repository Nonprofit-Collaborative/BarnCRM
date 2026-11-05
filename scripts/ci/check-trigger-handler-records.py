#!/usr/bin/env python3
"""Fails when a TriggerHandler subclass reads Trigger.new, Trigger.old, Trigger.newMap or
Trigger.oldMap directly.

A handler reads its records through the TriggerHandler accessors (newRecords(), oldRecords(),
newRecordsById(), oldRecordsById()) because the dispatcher narrows them to the records the
handler is to see, and a handler that failed on one record is run again on the rest
(ADR-0165 dispatcher errors and Automation Control, rule 3). A direct read sees every record
in the save and defeats both. Only TriggerHandler itself reads them.

A file is a handler file when it declares a class that extends TriggerHandler, or extends a
class that does (found transitively), anywhere in packages/*/main/default/classes.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

BASE = "TriggerHandler"
DIRECT = re.compile(r"\bTrigger\s*\.\s*(new|old|newMap|oldMap)\b", re.I)


def handler_names(sources):
    """Every class name that extends TriggerHandler, directly or through another handler."""
    parents = {}
    for source in sources.values():
        for match in re.finditer(r"\bclass\s+(\w+)[^{]*?\bextends\s+(\w+)", source, re.I):
            parents[match.group(1).lower()] = match.group(2).lower()
    names = set()
    changed = True
    while changed:
        changed = False
        for child, parent in parents.items():
            if child not in names and (parent == BASE.lower() or parent in names):
                names.add(child)
                changed = True
    return names


def check_sources(sources):
    """sources: {path: stripped Apex}. Returns a list of problems."""
    handlers = handler_names(sources)
    problems = []
    for path, source in sorted(sources.items()):
        if os.path.basename(path) == BASE + ".cls":
            continue
        declares = any(
            re.search(r"\bclass\s+" + re.escape(name) + r"\b[^{]*\bextends\s+(\w+)", source, re.I)
            for name in handlers
        )
        if not declares:
            continue
        for number, line in enumerate(source.split("\n"), 1):
            for match in DIRECT.finditer(line):
                problems.append(
                    f"{path}:{number}: Trigger.{match.group(1)} read directly in a TriggerHandler "
                    "subclass: use newRecords(), oldRecords(), newRecordsById() or oldRecordsById()"
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
        print(f"check-trigger-handler-records.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-trigger-handler-records.py: OK, {len(handler_names(sources))} handler classes read records only through the accessors")
    return 0


if __name__ == "__main__":
    sys.exit(main())
