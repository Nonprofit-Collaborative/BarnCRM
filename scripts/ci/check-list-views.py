#!/usr/bin/env python3
"""Checks the list view standard: every custom object with a tab has an All view and a My view.

Product plan Section 4: every BarnCRM object ships list views (All, My, and Active or Inactive
where applicable). An All view is one with filterScope Everything; a My view is one with
filterScope Mine. An object that is controlled by its parent (a master-detail child) has no
owner, so Salesforce does not allow a Mine scope on it: it needs the All view only.

Fails for each object with a CustomTab in packages/*/main/default/tabs that lacks either.
"""

import glob
import os
import re
import sys

SCOPE = re.compile(r"<filterScope>\s*(\w+)\s*</filterScope>")


def has_owner(object_dir, name):
    """False when the object is controlled by its parent or has a master-detail field."""
    meta = os.path.join(object_dir, f"{name}.object-meta.xml")
    if os.path.exists(meta):
        with open(meta, encoding="utf-8") as handle:
            if "ControlledByParent" in handle.read():
                return False
    for field in glob.glob(os.path.join(object_dir, "fields", "*.field-meta.xml")):
        with open(field, encoding="utf-8") as handle:
            if "<type>MasterDetail</type>" in handle.read():
                return False
    return True


def main():
    problems = []
    for tab in sorted(glob.glob("packages/*/main/default/tabs/*__c.tab-meta.xml")):
        name = os.path.basename(tab).split(".")[0]
        object_dir = os.path.join(os.path.dirname(os.path.dirname(tab)), "objects", name)
        scopes = set()
        for view in glob.glob(os.path.join(object_dir, "listViews", "*.listView-meta.xml")):
            with open(view, encoding="utf-8") as handle:
                found = SCOPE.search(handle.read())
            if found:
                scopes.add(found.group(1))
        if "Everything" not in scopes:
            problems.append(f"{name}: no All list view (filterScope Everything)")
        if "Mine" not in scopes and has_owner(object_dir, name):
            problems.append(f"{name}: no My list view (filterScope Mine)")
    if problems:
        print("\n".join(problems))
        print(f"check-list-views.py: FAILED, {len(problems)} problem(s)")
        return 1
    print("check-list-views.py: every tabbed object has an All view and a My view")
    return 0


if __name__ == "__main__":
    sys.exit(main())
