#!/usr/bin/env python3
"""Keeps each package's Apex code size under a budget.

Salesforce allows 6,000,000 characters of Apex per org (Apex Developer Guide, Size-Specific
Apex Limits; raisable by a support case). Comments, @IsTest classes and code in managed
packages do not count. BarnCRM installs as unmanaged source with no namespace (ADR-0001), so
every non-test class and trigger counts, beside the org's own code. On 2026-11-04 the full
suite measured 4,280,027 characters (71%), and one landing batch had added 12.5%: an org with
about 1.7M characters of its own Apex could no longer take it (architect review L-01, RT-01).
CI runs on scratch orgs, whose limit is 10,000,000, so no org test notices growth.

Size is measured the way the org measures it (ApexClass.LengthWithoutComments): every
character of a non-test class or trigger except comments. oi-test agreed within 2%.

CAPS is a ceiling per package a little above its measured size, so every addition is a
choice: raise a cap only in the pull request that needs it, and say why. TARGET is where the
trim pass should take the full suite and Core (decision 1, 2026-11-04), leaving an org at
least 2,400,000 characters of its own; above a target the check passes and says by how much.

    python3 scripts/ci/check-apex-budget.py            the check
    python3 scripts/ci/check-apex-budget.py --report   sizes per package, largest classes

scripts/org/install-precheck.py reads package_sizes() to compare an org's room with what
the chosen modules need.
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import is_test_class, without_comments  # noqa: E402

ORG_LIMIT = 6_000_000
CAPS = {
    # Set 2026-11-05 to each package's size with Apex indented by tabs (the org counts every
    # leading space, so tabs cut about 19 percent) plus about 2 percent.
    "core": 1_982_000,
    "rollups": 374_000,
    "giving": 587_000,
    "volunteers": 170_000,  # 2026-11-05: Log Hours action (modules-14)
    "programs": 148_000,
    "logicmodels": 65_000,
    "funders": 95_000,
    "mirror": 182_000,
}
TARGET = {"full suite": 3_600_000, "core": 2_000_000}


def repo_root():
    return subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
    ).stdout.strip()


def package_dirs(root):
    """{short name: path} for every package directory, in sfdx-project.json order."""
    with open(os.path.join(root, "sfdx-project.json"), encoding="utf-8") as handle:
        project = json.load(handle)
    return {os.path.basename(entry["path"]): entry["path"] for entry in project["packageDirectories"]}


def apex_files(root, path):
    out = subprocess.run(
        ["git", "ls-files", "--", f"{path}/*.cls", f"{path}/*.trigger"],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout
    return [f for f in out.splitlines() if f]


def package_sizes(root=None):
    """{package: {"size": chars, "classes": {name: chars}}} for non-test Apex, comments removed."""
    root = root or repo_root()
    sizes = {}
    for package, path in package_dirs(root).items():
        classes = {}
        for rel in apex_files(root, path):
            with open(os.path.join(root, rel), encoding="utf-8") as handle:
                source = handle.read()
            if rel.endswith(".cls") and is_test_class(source):
                continue
            classes[os.path.splitext(os.path.basename(rel))[0]] = len(without_comments(source))
        sizes[package] = {"size": sum(classes.values()), "classes": classes}
    return sizes


def percent(chars):
    return f"{100 * chars / ORG_LIMIT:.0f}%"


def report(sizes):
    total = sum(s["size"] for s in sizes.values())
    for package, data in sizes.items():
        cap = CAPS.get(package)
        print(f"{package:12} {data['size']:>10,} chars  {percent(data['size']):>4}  cap {cap:,}" if cap
              else f"{package:12} {data['size']:>10,} chars  {percent(data['size']):>4}  no cap")
    print(f"{'full suite':12} {total:>10,} chars  {percent(total):>4}  of {ORG_LIMIT:,}")
    largest = sorted(((c, n) for d in sizes.values() for n, c in d["classes"].items()), reverse=True)
    print("largest: " + ", ".join(f"{n} {c:,}" for c, n in largest[:10]))


def main(argv):
    sizes = package_sizes()
    if "--report" in argv:
        report(sizes)
        return 0
    problems = []
    for package, data in sizes.items():
        cap = CAPS.get(package)
        if cap is None:
            problems.append(
                f"{package}: no Apex budget. Add it to CAPS in scripts/ci/check-apex-budget.py"
                f" (measured {data['size']:,} characters)."
            )
        elif data["size"] > cap:
            problems.append(
                f"{package}: {data['size']:,} characters of non-test Apex, over its budget of"
                f" {cap:,} by {data['size'] - cap:,}. The org limit is {ORG_LIMIT:,} for the"
                " org's own code and every BarnCRM package together. Trim, or raise the cap in"
                " this pull request and say why."
            )
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-apex-budget.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    total = sum(s["size"] for s in sizes.values())
    notes = []
    for name, value in (("full suite", total), ("core", sizes.get("core", {}).get("size", 0))):
        if value > TARGET[name]:
            notes.append(f"{name} {value - TARGET[name]:,} over its target of {TARGET[name]:,}")
    note = f"; {', '.join(notes)}" if notes else ""
    print(f"check-apex-budget.py: OK, full suite {total:,} characters ({percent(total)} of"
          f" {ORG_LIMIT:,}), every package under its cap{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
