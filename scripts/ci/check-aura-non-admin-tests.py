#!/usr/bin/env python3
"""Fails when an @AuraEnabled controller has no test that runs as a non-admin user (QA review Q1).

About 5,075 test calls ran as an admin and 370 as anyone else, so a staff path that breaks for
the people who use it (a missing field permission, a class grant, a sharing rule) passed every
test. Each class with an `@AuraEnabled` method needs at least one test class that calls it
(`ClassName.` in the test) and builds a user that is not an admin, with one of:

    TestUsers.standardUser(...)            TestUsers.standardUserWith(...)
    TestUsers.peopleReaderWith(...)        TestUsers.minimumAccessUserWith(...)
    TestUsers.newStandardUser(...)         TestDataFactory.createUser(...)
    a User on TestUsers.readOnlyProfileId(), standardProfileId() or minimumAccessProfileId()

`TestUsers.admin()`, `adminWith(...)`, `withPermissionSets(...)` and `onRunningProfileWith(...)`
keep the running user's (administrator's) profile, so they do not count.

A controller only an administrator ever calls (a setup console, a settings page behind
Manage BarnCRM Settings) is listed in scripts/ci/aura-non-admin-allowlist.txt as
`ClassName # admin only: reason`. Controllers not yet covered are listed there as
`ClassName # not yet` (the ratchet): that list only shrinks, so an entry fails once the class
has a non-admin test (take the line out), and a new controller is never added to it.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import is_test_class, strip  # noqa: E402

ALLOWLIST = "scripts/ci/aura-non-admin-allowlist.txt"
AURA = re.compile(r"@AuraEnabled\b", re.I)
CLASS_NAME = re.compile(r"\bclass\s+(\w+)", re.I)
NON_ADMIN = re.compile(
    r"\bTestUsers\s*\.\s*(?:standardUser|standardUserWith|peopleReaderWith|minimumAccessUserWith"
    r"|newStandardUser|readOnlyProfileId|standardProfileId|minimumAccessProfileId)\s*\("
    r"|\bTestDataFactory\s*\.\s*createUser\s*\(",
    re.I,
)
VENDORED = os.path.join("packages", "rollups", "main", "default", "classes", "vendor")


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def sources():
    controllers, tests = {}, []
    for path in sorted(glob.glob("packages/*/main/**/*.cls", recursive=True)):
        if VENDORED in path:
            continue
        raw = read(path)
        text = strip(raw)
        if is_test_class(raw):
            tests.append(text)
        elif AURA.search(text):
            match = CLASS_NAME.search(text)
            if match:
                controllers[match.group(1)] = path
    return controllers, tests


def covered(controllers, tests):
    """The controllers some test calls while building a non-admin user."""
    found = set()
    staff_tests = [text for text in tests if NON_ADMIN.search(text)]
    for name in controllers:
        call = re.compile(r"\b" + re.escape(name) + r"\s*\.\s*\w+\s*\(")
        if any(call.search(text) for text in staff_tests):
            found.add(name)
    return found


def read_allowlist():
    entries = {}
    if not os.path.exists(ALLOWLIST):
        return entries
    for number, line in enumerate(read(ALLOWLIST).splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        name, _, reason = line.partition("#")
        entries[name.strip()] = (reason.strip(), number)
    return entries


def main():
    controllers, tests = sources()
    found = covered(controllers, tests)
    allowed = read_allowlist()
    problems = []
    for name in sorted(set(controllers) - found - set(allowed)):
        problems.append(
            f"{controllers[name]}: no test calls {name} as a non-admin user (TestUsers.standardUserWith "
            f"with BarnCRM_Staff or BarnCRM_Read_Only, for example). Add one, or list it in {ALLOWLIST} "
            "as '# admin only: reason' when only an administrator can reach it."
        )
    for name, (reason, number) in sorted(allowed.items()):
        if not reason:
            problems.append(f"{ALLOWLIST}:{number}: {name} needs a reason after '#'.")
        elif name not in controllers:
            problems.append(f"{ALLOWLIST}:{number}: {name} has no @AuraEnabled method now; remove it.")
        elif reason.startswith("not yet") and name in found:
            problems.append(f"{ALLOWLIST}:{number}: {name} now has a non-admin test; remove its line.")
    if problems:
        print("\n".join(problems))
        return 1
    pending = sum(1 for reason, _ in allowed.values() if reason.startswith("not yet"))
    print(
        f"check-aura-non-admin-tests: {len(found)} of {len(controllers)} controllers have a "
        f"non-admin test; {len(allowed) - pending} admin only, {pending} not yet."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
