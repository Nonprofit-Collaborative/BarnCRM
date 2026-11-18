#!/usr/bin/env python3
"""Lists the Apex test classes of the packages you deploy, for a RunSpecifiedTests deploy.

    list-package-tests.py <package> [<package> ...]

A package is a folder under packages/ (core, rollups, giving, volunteers, programs,
logicmodels, funders, events, mirror). Name every package the deploy carries. It prints one class
name per line, so in bash or zsh:

    sf project deploy validate ... --test-level RunSpecifiedTests \\
      --tests $(python3 scripts/org/list-package-tests.py core rollups giving)

Why: a production deploy with Apex runs every local test in the org by default, the org's own
failing tests included, and needs 75% coverage across the org. RunSpecifiedTests runs only
these and needs 75% for each class and trigger in the deploy, which BarnCRM's own tests give
(architect review L-06, RT-02; Admin Guide, Installing BarnCRM).

A test class is an @IsTest class with at least one test method; a test utility such as
TestDataFactory has none and is left out.
"""

import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "check_test_relevance", os.path.join(HERE, "..", "ci", "check-test-relevance.py")
)
relevance = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(relevance)


def package_paths(root):
    with open(os.path.join(root, "sfdx-project.json"), encoding="utf-8") as handle:
        project = json.load(handle)
    return {os.path.basename(e["path"]): e["path"] for e in project["packageDirectories"]}


def test_classes(path):
    names = []
    for rel in relevance.tracked(f"{path}/*.cls"):
        with open(rel, encoding="utf-8") as handle:
            source = relevance.strip_comments(handle.read())
        match = relevance.CLASS_ANNOTATION.search(source)
        name = os.path.basename(rel)[:-4]
        if match and match.group("name").lower() == name.lower() and relevance.TEST_METHOD.search(
            source, match.end()
        ):
            names.append(name)
    return sorted(names)


def main(argv):
    packages = list(argv)
    root = os.path.abspath(os.path.join(HERE, "..", ".."))
    os.chdir(root)
    paths = package_paths(root)
    unknown = [p for p in packages if p not in paths]
    if not packages or unknown:
        print(
            f"Usage: list-package-tests.py <package> ... (packages: {', '.join(paths)})"
            + (f"; unknown: {', '.join(unknown)}" if unknown else ""),
            file=sys.stderr,
        )
        return 2
    names = [n for p in packages for n in test_classes(paths[p])]
    print("\n".join(names))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
