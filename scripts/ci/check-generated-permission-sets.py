#!/usr/bin/env python3
"""Checks that every Admin and Read Only permission set is its Staff set plus its delta (D-200 S9a).

The Admin and Read Only sets of each role trio (ADR-0194) are written by
scripts/permission-sets/generate.py from the Staff set and scripts/permission-sets/deltas/<Prefix>.json.
A hand edit to a derived set, or a Staff change not carried through, fails here: change the Staff
set or the delta, then run the generator. Every package with a Staff set needs a delta file, so a
new trio cannot skip the generator.
"""

import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    problems = []
    for staff in sorted(glob.glob(os.path.join(ROOT, "packages", "*", "main", "default", "permissionsets", "*_Staff.permissionset-meta.xml"))):
        prefix = os.path.basename(staff)[: -len("_Staff.permissionset-meta.xml")]
        if not os.path.isfile(os.path.join(ROOT, "scripts", "permission-sets", "deltas", f"{prefix}.json")):
            problems.append(f"{os.path.relpath(staff, ROOT)}: no scripts/permission-sets/deltas/{prefix}.json")
    for problem in problems:
        print(problem, file=sys.stderr)
    generator = subprocess.run(
        [sys.executable, os.path.join(ROOT, "scripts", "permission-sets", "generate.py"), "--check"],
        capture_output=True,
        text=True,
    )
    sys.stderr.write(generator.stderr)
    if problems or generator.returncode:
        print("check-generated-permission-sets.py: FAILED", file=sys.stderr)
        return 1
    print(f"check-generated-permission-sets.py: OK, {len(glob.glob(os.path.join(ROOT, 'scripts', 'permission-sets', 'deltas', '*.json')))} trios match their Staff set plus delta")
    return 0


if __name__ == "__main__":
    sys.exit(main())
