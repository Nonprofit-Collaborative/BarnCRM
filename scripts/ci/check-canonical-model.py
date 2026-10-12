#!/usr/bin/env python3
"""Consistency checks for docs/architecture/canonical-model.md.

Three checks, all cheap enough to run on every pull request:

1. No em dashes anywhere (house style, CLAUDE.md).
2. No API name is declared twice for the same object. Declarations live in the
   "### Salesforce implementation" subsection of each entity, in tables whose
   header row contains "API name", grouped by the bullet that introduces them.
3. Every `Something__c` name used in prose, rules, or the rollup tables was
   declared in some implementation subsection, in the settings key table, or in
   the shipped-defaults section. This is the misspelling check: a field named one
   way in an attribute table and another way in an implementation table fails
   here.

Exit code 1 on any finding.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOC = os.path.join(ROOT, "docs", "architecture", "canonical-model.md")

API = re.compile(r"`([A-Za-z][A-Za-z0-9_]*__(?:c|mdt))`")
SECTION = re.compile(r"^## (\d+)\. (.+)$")
EM_DASH = "\u2014"


def blocks(lines):
    """Yield (section title, implementation-subsection lines)."""
    title = "(preamble)"
    inside = False
    buf = []
    for line in lines:
        m = SECTION.match(line)
        if m:
            if inside:
                yield title, buf
            title, inside, buf = m.group(0)[3:].strip(), False, []
            continue
        if line.startswith("### "):
            if inside:
                yield title, buf
            inside = line.strip() == "### Salesforce implementation"
            buf = []
            continue
        if inside:
            buf.append(line)
    if inside:
        yield title, buf


def main():
    text = open(DOC, encoding="utf-8").read()
    lines = text.splitlines()
    findings = []

    for number, line in enumerate(lines, 1):
        if EM_DASH in line:
            findings.append("em dash on line %d: %s" % (number, line.strip()))

    declared = set()
    for title, body in blocks(lines):
        group = "(object)"
        seen = {}
        header_is_api = False
        for line in body:
            declared.update(API.findall(line))
            if line.startswith("- **") or line.startswith("**"):
                group = line.strip()
                seen = {}
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 2 and cells[1] == "API name":
                header_is_api = True
                continue
            if not header_is_api or len(cells) < 2 or not line.strip().startswith("|"):
                continue
            names = API.findall(cells[1])
            if not names:
                continue
            name = names[0]
            if name in seen:
                findings.append(
                    "duplicate API name %s in section %r, group %r" % (name, title, group)
                )
            seen[name] = True

    # settings keys and shipped-default field names are declared in their own sections
    for chunk in re.split(r"^## ", text, flags=re.M):
        if chunk.startswith("12. BarnCRM Settings") or chunk.startswith("13. Shipped defaults"):
            declared.update(API.findall(chunk))

    used = set(API.findall(text))
    unknown = sorted(used - declared)
    for name in unknown:
        findings.append("used but never declared: %s" % name)

    if findings:
        print("canonical model check failed:")
        for finding in findings:
            print("  " + finding)
        return 1
    print("canonical model check passed: %d API names declared" % len(declared))
    return 0


if __name__ == "__main__":
    sys.exit(main())
