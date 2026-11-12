#!/usr/bin/env python3
"""Fails when Apex fills in a help catalog text that has a lone apostrophe.

Apex String.format reads a single quote as the start of a quoted section, the way Java's
MessageFormat does: "The mirror's run since {0}" comes out as "The mirrors run since {0}", the
placeholder never filled and the apostrophe gone. A text read with arguments, through
String.format(BarnHelp.text('Pkg', 'Key'), ...) or BarnHelp.text('Pkg', 'Key', args), must write
each apostrophe twice (''), which String.format prints as one.

Only texts Apex reads with arguments are checked: a text read without them is shown as written,
so it keeps single apostrophes. Known defects not yet fixed are listed in
help-text-apostrophes-baseline.txt and skipped; any new one fails.
"""

import glob
import json
import os
import re
import sys

FORMATTED = re.compile(
    r"String\s*\.\s*format\s*\(\s*BarnHelp\s*\.\s*text\s*\(\s*'(\w+)'\s*,\s*'(\w+)'\s*\)", re.S
)
WITH_ARGS = re.compile(r"BarnHelp\s*\.\s*text\s*\(\s*'(\w+)'\s*,\s*'(\w+)'\s*,", re.S)
LONE_APOSTROPHE = re.compile(r"(?<!')'(?!')")


def formatted_keys(sources):
    """sources: {path: Apex}. Returns {(package, key): 'path:line'} for texts read with arguments."""
    found = {}
    for path, source in sorted(sources.items()):
        for pattern in (FORMATTED, WITH_ARGS):
            for match in pattern.finditer(source):
                line = source.count("\n", 0, match.start()) + 1
                found.setdefault((match.group(1), match.group(2)), f"{path}:{line}")
    return found


BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "help-text-apostrophes-baseline.txt")


def load_baseline(path=BASELINE):
    """The known defects still to fix, as 'Package.Key' strings."""
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as handle:
        return {line.strip() for line in handle if line.strip() and not line.startswith("#")}


def check(sources, catalogs, baseline=frozenset()):
    """catalogs: {package: {key: text}}; baseline: known 'Package.Key' defects. Returns problems."""
    problems = []
    for (package, key), where in sorted(formatted_keys(sources).items()):
        text = catalogs.get(package, {}).get(key)
        if f"{package}.{key}" in baseline:
            continue
        if text and LONE_APOSTROPHE.search(text):
            problems.append(
                f"{where}: help text {package}.{key} is read with arguments but has a lone "
                "apostrophe; String.format drops it. Write it twice ('') in "
                f"BarnHelp_{package}.json, or reword without one"
            )
    return problems


def load_catalogs():
    catalogs = {}
    for path in glob.glob("packages/*/main/default/staticresources/BarnHelp_*.json"):
        package = os.path.basename(path)[len("BarnHelp_") : -len(".json")]
        with open(path, encoding="utf-8") as handle:
            catalogs.setdefault(package, {}).update(json.load(handle).get("texts", {}))
    return catalogs


def main():
    sources = {}
    for path in glob.glob("packages/*/main/default/classes/*.cls"):
        with open(path, encoding="utf-8") as handle:
            sources[path] = handle.read()
    problems = check(sources, load_catalogs(), load_baseline())
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            f"check-help-text-apostrophes.py: FAILED, {len(problems)} problem(s) above",
            file=sys.stderr,
        )
        return 1
    print(
        f"check-help-text-apostrophes.py: OK, {len(formatted_keys(sources))} help texts read with "
        "arguments have no lone apostrophe"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
