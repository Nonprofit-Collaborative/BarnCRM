#!/usr/bin/env python3
"""Checks that every Apex class a shipped LWC calls is granted in a permission set of its package.

A component imports `@salesforce/apex/Class.method`. The platform refuses that call for a user
whose permission sets do not grant the class, and the component then fails for everyone who
has only the package's sets. That is how the Volunteers readiness card shipped broken: its
controller was in none of the four Volunteers sets, and its Jest test, which mocks the call,
passed.

For each component file (tests excepted) in each package this finds the imported classes that
have an @AuraEnabled method and requires each to appear in a `<classAccesses>` entry, enabled,
in at least one permission set of the package that holds the class or the package that holds
the component. A class that is deliberately reached some other way goes in
scripts/ci/aura-class-access-allowlist.txt, one `Class  reason` per line.
"""

import glob
import os
import re
import sys

ALLOWLIST = "scripts/ci/aura-class-access-allowlist.txt"
IMPORT = re.compile(r"@salesforce/apex/(\w+)\.(\w+)")
ACCESS = re.compile(
    r"<classAccesses>\s*<apexClass>(\w+)</apexClass>\s*<enabled>true</enabled>\s*</classAccesses>"
)


def read_allowlist():
    allowed = {}
    if not os.path.exists(ALLOWLIST):
        return allowed
    for line in open(ALLOWLIST, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) < 2:
            print(f"{ALLOWLIST}: '{line}' has no reason; every entry needs one")
            sys.exit(1)
        allowed[parts[0]] = parts[1]
    return allowed


def package_of(path):
    return path.split(os.sep)[1]


def granted_classes():
    """Package name -> set of class names granted in any of its permission sets."""
    granted = {}
    for path in glob.glob("packages/*/main/default/permissionsets/*.permissionset-meta.xml"):
        source = open(path, encoding="utf-8").read()
        granted.setdefault(package_of(path), set()).update(ACCESS.findall(source))
    return granted


def class_package(name):
    paths = glob.glob(f"packages/*/main/default/classes/{name}.cls")
    return package_of(paths[0]) if paths else None


def has_aura_method(name):
    paths = glob.glob(f"packages/*/main/default/classes/{name}.cls")
    return bool(paths) and "@AuraEnabled" in open(paths[0], encoding="utf-8").read()


def main():
    allowed = read_allowlist()
    granted = granted_classes()
    problems = []
    seen = set()
    for path in sorted(glob.glob("packages/*/main/default/lwc/*/*.js")):
        if "__tests__" in path:
            continue
        source = open(path, encoding="utf-8").read()
        for name, _method in IMPORT.findall(source):
            if name in allowed or (path, name) in seen or not has_aura_method(name):
                continue
            seen.add((path, name))
            packages = {package_of(path), class_package(name)}
            if not any(name in granted.get(package, set()) for package in packages):
                problems.append(
                    f"{path}: calls {name}, which no permission set of "
                    f"{' or '.join(sorted(p for p in packages if p))} grants, so the component "
                    "fails for every user who holds only the package's sets"
                )
    for problem in problems:
        print(problem)
    if problems:
        print(f"check-aura-class-access.py: FAILED, {len(problems)} problem(s) above")
        return 1
    print(f"check-aura-class-access.py: OK, {len(seen)} component-to-class calls are granted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
