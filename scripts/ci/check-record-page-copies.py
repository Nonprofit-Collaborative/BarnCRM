#!/usr/bin/env python3
"""Checks that every module copy of Core's person and organization record pages keeps every
Core component.

A module that adds a panel to the Contact or Account page ships its own copy of Core's
`Contact_Record_Page` or `Account_Record_Page` (ADR-0064), because Core cannot place a module
component. The copy is a fork: a component Core adds later is missing from it until someone
adds it by hand, and in the module's app staff silently lose it. ADR-0064 named this check as
the next step if the copies drifted; they did (U11 in the 2026-11-12 review found the Programs
and Volunteers copies without `engagementMeter`, `recordGlance`, `recordInspectorButton` and
the tabset), so D-200 R2 made it a gate.

Checked: every `componentName` on Core's page appears on each module page named
`<Prefix>_Contact_Record_Page` or `<Prefix>_Account_Record_Page`. A module copy may add
components; it may not drop one.
"""

import glob
import os
import re
import sys

PAGES = ("Contact_Record_Page", "Account_Record_Page")
COMPONENT = re.compile(r"<componentName>([^<]+)</componentName>")


def components(path):
    with open(path, encoding="utf-8") as handle:
        return set(COMPONENT.findall(handle.read()))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    problems = []
    copies = 0
    for page in PAGES:
        core = os.path.join(root, "packages/core/main/default/flexipages", f"{page}.flexipage-meta.xml")
        if not os.path.exists(core):
            problems.append(f"Core's {page} is missing.")
            continue
        wanted = components(core)
        pattern = os.path.join(root, "packages/*/main/default/flexipages", f"*_{page}.flexipage-meta.xml")
        for path in sorted(glob.glob(pattern)):
            if "/packages/core/" in path.replace(os.sep, "/"):
                continue
            copies += 1
            missing = sorted(wanted - components(path))
            if missing:
                name = os.path.relpath(path, root)
                problems.append(f"{name} lacks Core's {', '.join(missing)}.")
    if problems:
        for problem in problems:
            print(problem)
        print(
            f"check-record-page-copies.py: FAILED, {len(problems)} problem(s). Add the Core "
            "component to the module copy, in the same place as on Core's page (ADR-0064)."
        )
        return 1
    print(f"check-record-page-copies.py: OK, {copies} module copies keep every Core component.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
