#!/usr/bin/env python3
"""Checks that every Lightning web component the packages expose can actually be reached.

`isExposed` means an administrator *could* drop the component on a page. It does not mean the
package ships anywhere that does. A component nobody can reach is a feature that does not
exist: it deploys cleanly, it passes every other check, its Jest tests pass, and the admin
guide happily describes a card the administrator will never see.

This has happened four times in this project, which is why it is a gate rather than care:

  * relationshipPanel, affiliationPanel and addressPanel shipped with C-15 to C-17 on no page,
    while three admin guide walkthroughs said "scroll to the card".
  * receiptSettings was named in a Setting Definition Component row, which Core cannot import
    across the package boundary (ADR-0020), so the console rendered "not installed".
  * receiptActions shipped with G-13 on no page, while the receipts walkthrough said "click
    Issue receipt".
  * commitmentSchedulePreview shipped with G-07 on no page and was never mentioned in its guide.

A component counts as reachable when it is placed on a flexipage, invoked by a quick action,
nested inside another component's markup, or named in the settings console's own import
switch. Those are the four ways anything in this package reaches a screen.

The check deliberately says nothing about whether the *page* is reachable in turn: a flexipage
nobody assigns is a different problem, and `check-record-pages-assigned.py` is the gate for it.
"""

import glob
import os
import re
import sys

CONSOLE = "packages/core/main/default/lwc/settingsConsole/settingsConsole.js"
CONSOLE_CASE = re.compile(r"case '([A-Za-z0-9_]+)'")
COMPONENT_NAME = re.compile(r"<componentName>([A-Za-z0-9_]+)</componentName>")
QUICK_ACTION_LWC = re.compile(r"<lightningWebComponent>([A-Za-z0-9_]+)</lightningWebComponent>")
MARKUP_TAG = re.compile(r"<c-([a-z0-9-]+)")
JS_IMPORT = re.compile(r"from\s+'c/([A-Za-z0-9_]+)'")
EXPOSED = "<isExposed>true</isExposed>"


def camel(kebab):
    """`household-members-panel` is how markup names `householdMembersPanel`."""
    return re.sub(r"-([a-z0-9])", lambda m: m.group(1).upper(), kebab)


def reachable_names():
    names = set()

    for path in glob.glob("packages/*/main/default/flexipages/*.xml"):
        with open(path, encoding="utf-8") as handle:
            names.update(COMPONENT_NAME.findall(handle.read()))

    for path in glob.glob("packages/*/main/default/quickActions/*.xml"):
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        names.update(QUICK_ACTION_LWC.findall(text))
        names.update(COMPONENT_NAME.findall(text))

    # A component used inside another component's markup is reached through its parent.
    for path in glob.glob("packages/*/main/default/lwc/*/*.html"):
        with open(path, encoding="utf-8") as handle:
            names.update(camel(tag) for tag in MARKUP_TAG.findall(handle.read()))

    # A JavaScript library (no markup) exposed so another package can import it, such as
    # findCsv for Giving's donorSegments, is reached through the component that imports it.
    for path in glob.glob("packages/*/main/default/lwc/*/*.js"):
        with open(path, encoding="utf-8") as handle:
            names.update(JS_IMPORT.findall(handle.read()))

    if os.path.isfile(CONSOLE):
        with open(CONSOLE, encoding="utf-8") as handle:
            names.update(CONSOLE_CASE.findall(handle.read()))

    return names


def main():
    reachable = reachable_names()
    problems = []
    checked = 0

    for directory in sorted(glob.glob("packages/*/main/default/lwc/*")):
        if not os.path.isdir(directory):
            continue
        name = os.path.basename(directory)
        meta = os.path.join(directory, f"{name}.js-meta.xml")
        if not os.path.isfile(meta):
            continue
        with open(meta, encoding="utf-8") as handle:
            if EXPOSED not in handle.read():
                continue
        checked += 1
        if name not in reachable:
            problems.append(
                f"{directory}: {name} is exposed but nothing ships that reaches it. Put it on a "
                "flexipage, invoke it from a quick action, nest it in another component, or name "
                "it in the settings console import switch. An unreachable component is a feature "
                "that does not exist, however green its tests are."
            )

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            f"check-components-reachable.py: FAILED, {len(problems)} unreachable component(s) above",
            file=sys.stderr,
        )
        return 1

    print(f"check-components-reachable.py: OK, all {checked} exposed components are reachable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
