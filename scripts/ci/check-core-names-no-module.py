#!/usr/bin/env python3
"""Fails if Core's code names a class, trigger or component another package ships.

Core installs alone and depends on no module (plan Section 4.1, ADR-0003, ADR-NEXT
`NEXT-rollup-builder-module.md`). It reaches a module only by class name at run time
(`HealthCheckExtensions`, `NightlyJobs`, `RollupEngineExtensions` and the other resolvers),
and those names are string literals. So Core's Apex, with comments and string literals blanked,
must name no module class, and Core's components must import no module component or module
Apex. A static reference compiles only where the module is installed, so a Core-only deploy
would fail, and nothing else would notice until it did.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

CORE = "packages/core"


def module_names():
    """Every Apex class, trigger and component a non-Core package ships, by name."""
    classes = set()
    components = set()
    for package in sorted(glob.glob("packages/*/")):
        if os.path.normpath(package) == CORE:
            continue
        for path in glob.glob(os.path.join(package, "**", "*.cls"), recursive=True):
            classes.add(os.path.basename(path)[: -len(".cls")])
        for path in glob.glob(os.path.join(package, "**", "*.trigger"), recursive=True):
            classes.add(os.path.basename(path)[: -len(".trigger")])
        for path in glob.glob(os.path.join(package, "**", "lwc", "*", "*.js-meta.xml"), recursive=True):
            components.add(os.path.basename(os.path.dirname(path)))
    return classes, components


def kebab(name):
    return re.sub(r"([A-Z])", lambda m: "-" + m.group(1).lower(), name)


def main():
    classes, components = module_names()
    problems = []
    if classes:
        word = re.compile(r"\b(" + "|".join(sorted(map(re.escape, classes))) + r")\b")
        for path in sorted(
            glob.glob(os.path.join(CORE, "**", "*.cls"), recursive=True)
            + glob.glob(os.path.join(CORE, "**", "*.trigger"), recursive=True)
        ):
            code = strip(open(path, encoding="utf-8").read())
            for number, line in enumerate(code.split("\n"), 1):
                for name in sorted(set(word.findall(line))):
                    problems.append(f"{path}:{number}: names module class {name}")
    lwc_files = glob.glob(os.path.join(CORE, "**", "lwc", "*", "*.js"), recursive=True)
    lwc_files += glob.glob(os.path.join(CORE, "**", "lwc", "*", "*.html"), recursive=True)
    for path in sorted(lwc_files):
        if "__tests__" in path:
            continue
        text = open(path, encoding="utf-8").read()
        for name in sorted(components):
            if re.search(r"['\"]c/" + re.escape(name) + r"['\"]", text) or (
                path.endswith(".html") and re.search(r"<c-" + re.escape(kebab(name)) + r"[\s>]", text)
            ):
                problems.append(f"{path}: uses module component {name}")
        for name in sorted(classes):
            if f"@salesforce/apex/{name}." in text:
                problems.append(f"{path}: calls module Apex {name}")
    for problem in problems:
        print(problem)
    if problems:
        print(f"check-core-names-no-module.py: FAILED, {len(problems)} reference(s) above")
        return 1
    print(
        f"check-core-names-no-module.py: OK, Core names none of {len(classes)} module classes "
        f"and {len(components)} module components"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
