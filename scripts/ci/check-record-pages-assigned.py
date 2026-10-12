#!/usr/bin/env python3
"""Checks that every packaged Lightning record page is actually assigned to something.

`check-components-reachable.py` proves a component is on a page. It says so in its own
header, it deliberately says nothing about whether that page is ever shown, and that is the
hole this gate closes. A FlexiPage cannot name the record type it serves: the assignment
lives in a Lightning app's `actionOverrides`, or in the object's own `actionOverrides` for
the org default. Ship the page without one and Salesforce keeps showing the standard record
page, so the component is on a page nobody opens.

This is the same defect class as an unreachable component, one level up: it deploys, every
test passes, and the administrator sees none of it until they wire it up by hand in the
Lightning App Builder. It ran because `Household_Record_Page` carried `householdMembersPanel`
and `BarnCRM.app-meta.xml` carried no `actionOverrides` at all, so the household
walkthrough failed at step 4 on every fresh install, and because `Gift_Record_Page` and
`Commitment_Record_Page` were stranded the same way in the Fundraising app.

Two things are checked:

  1. Every RecordPage flexipage the packages ship is named by at least one assignment.
  2. An app that assigns a page covers every form factor the app itself declares. An app
     that declares Large and Small and assigns a page for Large only is a phone user looking
     at the standard page, which is the same defect on a smaller screen.

Vendored source is out of scope: the globs only reach `packages/*/main/default`.
"""

import glob
import os
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"


def q(tag):
    return f"{{{NS}}}{tag}"


def text(element, tag):
    child = element.find(q(tag))
    return (child.text or "").strip() if child is not None else ""


def record_pages():
    """The API name of every RecordPage flexipage the packages ship, by file path."""
    pages = {}
    for path in sorted(glob.glob("packages/*/main/default/flexipages/*.flexipage-meta.xml")):
        root = ET.parse(path).getroot()
        if text(root, "type") != "RecordPage":
            continue
        pages[os.path.basename(path).split(".")[0]] = path
    return pages


def flexipage_overrides(path):
    """Every Flexipage actionOverride in one application or object file."""
    root = ET.parse(path).getroot()
    return [
        override
        for override in root.findall(q("actionOverrides"))
        if text(override, "type") == "Flexipage" and text(override, "content")
    ]


def main():
    pages = record_pages()
    assigned = set()
    problems = []

    for path in sorted(glob.glob("packages/*/main/default/applications/*.app-meta.xml")):
        root = ET.parse(path).getroot()
        declared = {(element.text or "").strip() for element in root.findall(q("formFactors"))}
        covered = {}
        for override in flexipage_overrides(path):
            content = text(override, "content")
            assigned.add(content)
            key = (content, text(override, "recordType"), text(override, "pageOrSobjectType"))
            covered.setdefault(key, set()).add(text(override, "formFactor"))
        for (content, record_type, sobject), factors in sorted(covered.items()):
            missing = sorted(declared - factors)
            if missing:
                where = record_type or sobject
                problems.append(
                    f"{path}: assigns {content} for {where} on {', '.join(sorted(factors))} but "
                    f"not on {', '.join(missing)}, which the app declares. A form factor with no "
                    "assignment shows the standard record page instead."
                )

    for path in sorted(glob.glob("packages/*/main/default/objects/*/*.object-meta.xml")):
        for override in flexipage_overrides(path):
            assigned.add(text(override, "content"))

    for name, path in sorted(pages.items()):
        if name not in assigned:
            problems.append(
                f"{path}: {name} is a record page nothing assigns. Add a View actionOverride of "
                "type Flexipage naming it, in the Lightning app that should open it (one per "
                "record type and form factor) or in the object's own actionOverrides for the org "
                "default. An unassigned record page is never shown, however green its tests are."
            )

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            f"check-record-pages-assigned.py: FAILED, {len(problems)} problem(s) above",
            file=sys.stderr,
        )
        return 1

    print(f"check-record-pages-assigned.py: OK, all {len(pages)} record pages are assigned")
    return 0


if __name__ == "__main__":
    sys.exit(main())
