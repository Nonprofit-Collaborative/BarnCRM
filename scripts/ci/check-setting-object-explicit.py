#!/usr/bin/env python3
"""Fails if a Setting Definition record does not state Settings_Object__c.

A custom metadata field default is applied only when a record is created. It is
not re-applied when a record that omits the field is redeployed or upgraded, so
an org keeps whatever value it first stored. When the default changed from
Nonprofit_Settings__c to BarnCRM_Settings__c, every row that relied on it stayed
pointed at the old object in orgs that already had it, and SettingsService
refused each save with "That setting does not exist in this org". Naming the
settings object on every row makes each deployment write it.
"""

import glob
import re
import sys

PATTERN = "packages/*/main/default/customMetadata/Setting_Definition.*.md-meta.xml"
STATED = re.compile(
    r"<field>Settings_Object__c</field>\s*<value(?:[^>]*/>|[^>]*>\s*[A-Za-z0-9_]+\s*</value>)"
)


def main():
    failures = [f for f in sorted(glob.glob(PATTERN)) if not STATED.search(open(f).read())]
    for f in failures:
        print(f"{f}: Settings_Object__c is missing; state the settings object explicitly")
    if failures:
        print(f"{len(failures)} Setting Definition record(s) rely on the field default.")
        return 1
    print("Every Setting Definition record states Settings_Object__c.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
