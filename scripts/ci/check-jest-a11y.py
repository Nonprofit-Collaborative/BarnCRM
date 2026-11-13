#!/usr/bin/env python3
"""Keeps the accessibility assertion spreading through the component tests (QA review Q5, D-200).

Every LWC with a template (an .html file named for its bundle) should have a Jest test that
calls `expectAccessible(` from `barn/a11y` (packages/core/test/jest-helpers/a11y.js), which
checks every control has a name a screen reader can read, every img has alt and no positive
tabindex, and runs @sa11y/jest when it is installed.

Components that do not yet are listed in scripts/ci/jest-a11y-baseline.txt, one bundle name a
line. The list only shrinks: a component missing from it fails when its tests lack the
assertion, and an entry fails once its tests have it (take the line out) or the component is
gone. `--update` rewrites the list from what is there now; use it only to shrink the list.
"""

import glob
import os
import sys

BASELINE = "scripts/ci/jest-a11y-baseline.txt"
CALL = "expectAccessible("


def components():
    """Bundle name to bundle folder, for every LWC that renders a template."""
    found = {}
    for html in glob.glob("packages/*/main/default/lwc/*/*.html"):
        folder = os.path.dirname(html)
        name = os.path.basename(folder)
        if os.path.basename(html) == name + ".html":
            found[name] = folder
    return found


def asserts(folder):
    for test in glob.glob(os.path.join(folder, "__tests__", "*.js")):
        with open(test, encoding="utf-8") as handle:
            if CALL in handle.read():
                return True
    return False


def read_baseline():
    if not os.path.exists(BASELINE):
        return set()
    with open(BASELINE, encoding="utf-8") as handle:
        return {
            line.strip()
            for line in handle
            if line.strip() and not line.lstrip().startswith("#")
        }


def main():
    found = components()
    missing = {name for name, folder in found.items() if not asserts(folder)}
    if "--update" in sys.argv:
        with open(BASELINE, "w", encoding="utf-8") as handle:
            handle.write(
                "# Components whose Jest tests do not yet call expectAccessible (QA review Q5).\n"
                "# Only shrinks: scripts/ci/check-jest-a11y.py.\n"
            )
            handle.writelines(name + "\n" for name in sorted(missing))
        print(f"{BASELINE}: {len(missing)} components listed.")
        return 0
    baseline = read_baseline()
    problems = []
    for name in sorted(missing - baseline):
        problems.append(
            f"{found[name]}: no test calls expectAccessible() from 'barn/a11y'; add one "
            "(a new component is never added to the baseline)."
        )
    for name in sorted(baseline - missing):
        reason = "now asserts accessibility" if name in found else "no longer exists"
        problems.append(f"{BASELINE}: {name} {reason}; remove its line.")
    if problems:
        print("\n".join(problems))
        return 1
    print(
        f"check-jest-a11y: {len(found) - len(missing)} of {len(found)} components assert "
        f"accessibility; {len(missing)} still listed in the baseline."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
