#!/usr/bin/env python3
"""Checks that the Module Manager's uninstall report names every object a module owns.

The report (C-24) tells an administrator how many records uninstalling a module would delete.
Core cannot see a module's schema, so `ModuleManagerService.ownedObjects` lists each module's
objects by name. A module that gains an object and is not added there makes the report say
less than the uninstall deletes, and nothing else would notice.

A module owns an object when its package ships the object's own `.object-meta.xml`. Custom
settings and custom metadata types are left out: they hold configuration, not records an
administrator would miss. Folders that only add fields to another package's object are not
owned. A module the list does not name, and a package folder with no objects, are skipped,
so a module with no package yet does not fail the check.
"""

import glob
import os
import re
import sys

SERVICE = "packages/core/main/default/classes/ModuleManagerService.cls"


def listed():
    text = open(SERVICE, encoding="utf-8").read()
    block = text[text.index("ownedObjects") :]
    block = block[: block.index("};") + 2]
    modules = {}
    for name, body in re.findall(r"'(\w+)'\s*=>\s*new List<String>\{(.*?)\}", block, re.DOTALL):
        modules[name] = set(re.findall(r"'(\w+)'", body))
    for name in re.findall(r"'(\w+)'\s*=>\s*new List<String>\(\)", block):
        modules[name] = set()
    return modules


def owned(module):
    found = set()
    pattern = os.path.join("packages", module.lower(), "main/default/objects/*/*.object-meta.xml")
    for path in glob.glob(pattern):
        name = os.path.basename(os.path.dirname(path))
        if not name.endswith("__c"):
            continue
        if "<customSettingsType>" in open(path, encoding="utf-8").read():
            continue
        found.add(name)
    return found


def main():
    problems = []
    modules = listed()
    if not modules:
        problems.append(f"{SERVICE}: ownedObjects not found")
    for module, names in sorted(modules.items()):
        shipped = owned(module)
        for missing in sorted(shipped - names):
            problems.append(f"{module}: ships {missing}, which the uninstall report does not count")
        for extra in sorted(names - shipped):
            problems.append(f"{module}: the uninstall report counts {extra}, which {module} does not ship")
    for problem in problems:
        print(problem)
    if problems:
        print(f"check-module-objects.py: FAILED, {len(problems)} problem(s) above")
        return 1
    print(f"check-module-objects.py: OK, {len(modules)} modules list exactly the objects they own")
    return 0


if __name__ == "__main__":
    sys.exit(main())
