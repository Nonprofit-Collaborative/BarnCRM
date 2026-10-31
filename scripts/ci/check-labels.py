#!/usr/bin/env python3
"""Checks every shipped custom label against the platform's length limits.

A label over a limit deploys nowhere, and only an org says so: 44 short descriptions
over 80 characters failed the Core labels stage on 2026-09-22, after the custom metadata
stage had finally deployed. Nothing offline reads label files, so this does.

Limits (Salesforce custom labels): name 80 characters, short description 1 to 80,
value 1 to 1000.

Translation readiness (v0.11): a translator sees the short description beside the value and
nothing else, so a Core label with placeholders must say in its description what each one
holds, writing each as it appears in the value ("{0} is the count"). The Rollup Builder
module's labels were Core's and were swept with them. Giving and Mirror join
PLACEHOLDER_PACKAGES once their labels are swept.
"""

import glob
import html
import re
import sys

LABEL = re.compile(r"<labels>(.*?)</labels>", re.DOTALL)
LIMITS = {"fullName": 80, "shortDescription": 80, "value": 1000}
PLACEHOLDER = re.compile(r"\{\d+\}")
PLACEHOLDER_PACKAGES = {"core", "rollups", "volunteers", "logicmodels"}


def text_of(block, tag):
    found = re.search(r"<" + tag + r"\s*>(.*?)</" + tag + r"\s*>", block, re.DOTALL)
    return html.unescape(found.group(1)) if found else None


def main():
    problems = []
    checked = 0
    for path in sorted(glob.glob("packages/*/main/default/labels/*.labels-meta.xml")):
        for block in LABEL.findall(open(path, encoding="utf-8").read()):
            checked += 1
            name = text_of(block, "fullName") or "(no fullName)"
            for tag, limit in LIMITS.items():
                value = text_of(block, tag)
                if not value:
                    problems.append(f"{path}: {name} has no {tag}")
                elif len(value) > limit:
                    problems.append(f"{path}: {name} {tag} is {len(value)} characters, over {limit}")
            if path.split("/")[1] in PLACEHOLDER_PACKAGES:
                described = text_of(block, "shortDescription") or ""
                unexplained = sorted(
                    set(PLACEHOLDER.findall(text_of(block, "value") or "")) - set(PLACEHOLDER.findall(described))
                )
                if unexplained:
                    problems.append(
                        f"{path}: {name} short description does not say what {', '.join(unexplained)} holds"
                    )

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-labels.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-labels.py: OK, {checked} labels within the platform limits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
