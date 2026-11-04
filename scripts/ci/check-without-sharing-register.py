#!/usr/bin/env python3
"""Keeps docs/architecture/without-sharing-register.md in step with the code.

Every top-level non-test Apex class declared `without sharing` must have a row in the register
(the first column of a table row, as `| ClassName |`), and every class in the register must
still be declared `without sharing`. A security reviewer reads the register to see each path
that ignores sharing and why (architect review RT-14).
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import is_test_class, strip  # noqa: E402

REGISTER = "docs/architecture/without-sharing-register.md"
TOP_LEVEL = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:public|global|private)?\s*(?:abstract\s+|virtual\s+)*"
    r"without sharing\s+class\s+(\w+)",
    re.M | re.I,
)
ROW = re.compile(r"^\|\s*([A-Za-z]\w*)\s*\|\s*(?:Integrity|Upkeep|Org job|Org figure|Platform)\s*\|", re.M)


def main():
    in_code = set()
    for path in glob.glob("packages/*/main/default/classes/*.cls"):
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        if is_test_class(source):
            continue
        match = TOP_LEVEL.search(strip(source))
        if match:
            in_code.add(match.group(1))
    with open(REGISTER, encoding="utf-8") as handle:
        in_register = set(ROW.findall(handle.read()))
    problems = [f"{name} is declared without sharing but has no row in {REGISTER}: add one with"
                " its kind, what it reaches and the ADR that allows it" for name in sorted(in_code - in_register)]
    problems += [f"{name} is in {REGISTER} but is no longer a top-level without sharing class:"
                 " remove its row" for name in sorted(in_register - in_code)]
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-without-sharing-register.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-without-sharing-register.py: OK, {len(in_code)} without sharing classes, all registered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
