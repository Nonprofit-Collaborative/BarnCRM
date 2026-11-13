#!/usr/bin/env python3
"""Fails when packaged Apex starts background work without AsyncStarter (D-200 P9).

Database.executeBatch and System.enqueueJob throw when the flex queue is full or the queued
job limit is reached, and past the queued job limit the exception cannot be caught. A button
or nightly step that starts work through AsyncStarter.batch or AsyncStarter.queue checks
first, logs a refusal once and tells the person to try again. So every direct call outside
AsyncStarter must be in async-starter-allowlist.txt, which records, per file, how many direct
calls it may make and why: a job re-queuing itself while it runs, a trigger that must not
fail the save, a post-install step, or a batch whose type AsyncStarter does not take.

A file with more direct calls than its allowance fails; one with fewer fails too, so the
allowance is lowered as call sites move to AsyncStarter. Test classes are exempt.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ALLOWLIST = os.path.join(HERE, "async-starter-allowlist.txt")
STARTER = "AsyncStarter.cls"
CALL = re.compile(r"\b(Database\s*\.\s*executeBatch|System\s*\.\s*enqueueJob)\s*\(", re.I)
TEST_CLASS = re.compile(
    r"^\s*@IsTest\b[^\n]*\n(\s*@\w+[^\n]*\n)*\s*(public|private|global)?\s*(with|without|inherited)?\s*(sharing)?\s*class\b",
    re.I | re.M,
)


def is_test(path, source):
    return path.endswith("Test.cls") or bool(TEST_CLASS.search(source))


def read_allowlist(text):
    """'path count  # reason' lines; returns {path: count}."""
    allowed = {}
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            path, count = line.split()
            allowed[path] = int(count)
    return allowed


def check_sources(sources, allowed):
    """sources: {path: stripped Apex}; allowed: {path: count}. Returns a list of problems."""
    problems = []
    for path, source in sorted(sources.items()):
        if os.path.basename(path) == STARTER or is_test(path, source):
            continue
        found = len(CALL.findall(source))
        allowance = allowed.get(path, 0)
        if found > allowance:
            problems.append(
                f"{path}: {found} direct Database.executeBatch or System.enqueueJob call(s), "
                f"{allowance} allowed: start work through AsyncStarter.batch or AsyncStarter.queue"
            )
        elif found < allowance:
            problems.append(
                f"{path}: {found} direct call(s) but {allowance} allowed: lower its line in "
                "scripts/ci/async-starter-allowlist.txt"
            )
    for path in sorted(set(allowed) - set(sources)):
        problems.append(f"{path}: listed in async-starter-allowlist.txt but not found")
    return problems


def main():
    sources = {}
    for path in glob.glob("packages/*/main/default/classes/*.cls"):
        with open(path, encoding="utf-8") as handle:
            sources[path] = strip(handle.read())
    with open(ALLOWLIST, encoding="utf-8") as handle:
        allowed = read_allowlist(handle.read())
    problems = check_sources(sources, allowed)
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-async-starter.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-async-starter.py: OK, {len(sources)} classes start background work through AsyncStarter or are allowlisted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
