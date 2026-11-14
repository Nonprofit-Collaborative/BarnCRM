#!/usr/bin/env python3
"""Ratchet: test classes build Contacts and Accounts through the test data factories (D-200 S3).

A test that inserts `new Contact(LastName = 'Rivera')` fails in an org that requires a custom
field on Contact or has a blocking duplicate rule, which is how a production install runs the
suite (architect review RT-02, defect SD1). `TestDataFactory.pastDuplicateRules(record)` fills
the org's required custom fields and lets the record past duplicate rules, and the person,
organization and household helpers call it. Tests therefore create Contacts, Accounts and
households only through those helpers (`TestDataFactory.person`, `organization`, `household`,
`HouseholdTestDataFactory`, `AddressTestDataFactory`, `AccountKindsTestData`).

This check counts constructions `new Contact(...)` and `new Account(...)` in test classes
that are neither a factory (a class named `*TestData` or `*TestDataFactory`) nor an update
stub (`new Contact(Id = ...)`, which sets no required field) nor already wrapped in
`pastDuplicateRules(` or the person, organization or household helper. A construction that must stay raw (an in-memory record never saved,
or a test of the factory or of a raw insert) carries `// factory-ok: reason` on its line.
The count may not rise above BASELINE; lower BASELINE when it falls.

    python3 scripts/ci/check-test-data-factory.py          the check
    python3 scripts/ci/check-test-data-factory.py --list   every counted construction
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import is_test_class, strip  # noqa: E402

BASELINE = 0
CONSTRUCTION = re.compile(r"\bnew\s+(Contact|Account)\s*\(")
FACTORY_NAME = re.compile(r"TestData(Factory)?\.cls$")
UPDATE_STUB = re.compile(r"\s*Id\s*=")
WRAPPED = re.compile(
    r"(?:pastDuplicateRules|TestDataFactory\s*\.\s*(?:person|organization|household))\s*\(\s*$"
)


def findings():
    out = []
    for path in sorted(glob.glob("packages/*/main/default/classes/*.cls")):
        if FACTORY_NAME.search(path):
            continue
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        if not is_test_class(source):
            continue
        code = strip(source)
        lines = source.split("\n")
        for match in CONSTRUCTION.finditer(code):
            if UPDATE_STUB.match(code[match.end() : match.end() + 40]):
                continue
            if WRAPPED.search(code[max(0, match.start() - 60) : match.start()]):
                continue
            number = code.count("\n", 0, match.start()) + 1
            if "factory-ok" in lines[number - 1]:
                continue
            out.append("%s:%d: %s" % (path, number, lines[number - 1].strip()))
    return out


def main():
    found = findings()
    if "--list" in sys.argv:
        print("\n".join(found))
    print("check-test-data-factory.py: %d raw Contact/Account constructions in test classes (baseline %d)" % (len(found), BASELINE))
    if len(found) > BASELINE:
        print(
            "Create Contacts, Accounts and households with TestDataFactory.person, organization, "
            "household so the test passes in orgs with required fields or duplicate "
            "rules (scripts/ci/check-test-data-factory.py has the rule)."
        )
        print("\n".join(found[-20:]))
        return 1
    if len(found) < BASELINE:
        print("The count is below the baseline: lower BASELINE in the script to %d." % len(found))
    return 0


if __name__ == "__main__":
    sys.exit(main())
