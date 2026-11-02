#!/usr/bin/env python3
"""Keeps the custom label count under a budget and fails on labels nothing uses.

Salesforce allows 5,000 custom labels per org. Labels in an installed managed package do not
count toward it ("Custom labels from managed packages don't count toward this limit",
Salesforce Help, Custom Labels), but every unpackaged source deploy does: barn-sales, oi-test,
barn-npc and mwdbdevsb all receive BarnCRM as source, beside each org's own labels. barn-sales
reached 4,996 on 2026-11-02 and a deploy failed with "custom label limit exceeded".

BUDGET is the total across every package directory. It leaves 500 for an org's own labels
and for labels a deploy has left behind (a source deploy never deletes a label). TARGET is
where the total should settle; above it the check passes and says by how much.

Unused: a label whose name appears in no file under packages/ other than the label files
(Markdown and code comments do not count). Apex, LWC, Aura, Visualforce, flows, FlexiPages
and custom metadata records all name a label in full, including the names read with
System.Label.get, so a whole-word search finds every real reference. A label referenced
only by a name built from pieces at run time would be missed: there is none, and building
one is not allowed (write the full name so this check, and a reader, can find it).
"""

import glob
import re
import subprocess
import sys

BUDGET = 4500
TARGET = 4000
LABEL_FILES = "packages/*/main/default/labels/*.labels-meta.xml"


def label_names():
    names = {}
    for path in sorted(glob.glob(LABEL_FILES)):
        for name in re.findall(r"<fullName>\s*([A-Za-z0-9_]+)\s*</fullName>", open(path, encoding="utf-8").read()):
            names[name] = path
    return names


def strip_comments(path, text):
    if path.endswith((".cls", ".trigger", ".js")):
        text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
        text = re.sub(r"(?m)^\s*//.*$", " ", text)
    elif path.endswith((".html", ".xml", ".cmp", ".page", ".component")):
        text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
    return text


def referenced_names(names):
    files = subprocess.run(["git", "ls-files", "packages"], capture_output=True, text=True, check=True).stdout
    found = set()
    for path in files.splitlines():
        if path.endswith((".labels-meta.xml", ".md")):
            continue
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        for word in set(re.findall(r"[A-Za-z0-9_]+", strip_comments(path, text))):
            if word in names:
                found.add(word)
    return found


def main():
    names = label_names()
    problems = []
    total = len(names)
    if total > BUDGET:
        problems.append(
            f"{total} custom labels, over the budget of {BUDGET} (the org limit is 5,000 and an org's own"
            " labels need room). Remove unused labels, merge exact duplicates, or move long help text"
            " into the guides before adding more."
        )
    for name in sorted(set(names) - referenced_names(names)):
        problems.append(f"{names[name]}: {name} is not referenced anywhere in packages/; remove it")

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-label-budget.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    note = f", {total - TARGET} over the target of {TARGET}" if total > TARGET else ""
    print(f"check-label-budget.py: OK, {total} labels, budget {BUDGET}{note}, none unused")
    return 0


if __name__ == "__main__":
    sys.exit(main())
