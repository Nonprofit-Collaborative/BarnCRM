#!/usr/bin/env python3
"""Checks that the newest release-notes version has What's New entries (ADMIN-28).

The What's New card on BarnCRM Home shows the shipped Release Note custom metadata records
of the newest version (canonical model R-WN2). Nothing tied those records to the release
notes in docs/release-notes, so the card would keep showing the version it was built in.

The newest version is the highest v<major>.<minor> named by a file in docs/release-notes
(an iteration report v0.N.md or a draft v0.N-draft-*.md). It has entries when at least one
Release_Note.*.md-meta.xml in any package carries that Version__c.

During an iteration the drafts arrive before the entries are written, so by default a
missing version is a warning (a GitHub annotation) and the build passes. With --release,
which the release checklist in docs/release-notes/README.md runs before a package version is
created, it fails.
"""

import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"
XSI = "http://www.w3.org/2001/XMLSchema-instance"
NOTES_DIR = "docs/release-notes"
RECORD_GLOB = "packages/*/main/default/customMetadata/Release_Note.*.md-meta.xml"
VERSION_IN_NAME = re.compile(r"^v(\d+)\.(\d+)(?:\.md$|-)")


def newest_notes_version():
    versions = set()
    for name in os.listdir(NOTES_DIR):
        match = VERSION_IN_NAME.match(name)
        if match:
            versions.add((int(match.group(1)), int(match.group(2))))
    return max(versions) if versions else None


def as_tuple(text):
    """A version as whole-number parts with trailing zeros dropped, or None (R-WN3)."""
    parts = (text or "").strip().split(".")
    if not all(part.isdigit() for part in parts):
        return None
    numbers = [int(part) for part in parts]
    while len(numbers) > 2 and numbers[-1] == 0:
        numbers.pop()
    return tuple(numbers)


def shipped_versions():
    versions = {}
    for path in sorted(glob.glob(RECORD_GLOB)):
        root = ET.parse(path).getroot()
        for value in root.findall(f"{{{NS}}}values"):
            if value.findtext(f"{{{NS}}}field") == "Version__c":
                version = as_tuple(value.findtext(f"{{{NS}}}value"))
                if version is not None:
                    versions.setdefault(version, []).append(path)
    return versions


def main():
    release = "--release" in sys.argv[1:]
    newest = newest_notes_version()
    if newest is None:
        print("check-whats-new: no versioned release notes found, nothing to check.")
        return 0
    label = f"{newest[0]}.{newest[1]}"
    shipped = shipped_versions()
    if newest in shipped:
        print(
            f"check-whats-new: v{label} has {len(shipped[newest])} What's New "
            "entr" + ("y." if len(shipped[newest]) == 1 else "ies.")
        )
        return 0
    message = (
        f"The newest release notes are v{label}, and no Release Note record carries "
        f"Version {label}, so What's New would still show an older release. Add "
        f"Release_Note.*.md-meta.xml records for v{label} from the release notes "
        "(see docs/release-notes/README.md, Before a release)."
    )
    if release:
        print(f"check-whats-new: FAILED. {message}")
        return 1
    print(f"::warning title=What's New not refreshed::{message}")
    print(f"check-whats-new: warning only until the release. {message}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
