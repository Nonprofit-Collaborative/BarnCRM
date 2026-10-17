#!/usr/bin/env python3
"""Checks that every switchable Core automation has a Flow template or a written reason.

ADR-0040 says customization is "switch ours off, run yours": each switchable automation has
a Flow template a customer can Save As and own. Some automations cannot be copied into a
flow faithfully, and for those the admin guide page says why (ADR-0090,
0090-flow-templates-which-automations-get-one.md). Nothing else notices when a new
automation ships with neither, so this check does.

For each Core Automation Registry row that is not marked Always Runs, one of these holds:

- a flow named Template_<registry DeveloperName> ships in Core, or
- the admin guide page docs/admin-guide/flow-templates.md has a table row whose first cell
  is the registry row's label and whose second cell starts with "None".

And every Template_*.flow-meta.xml in Core:

- is marked as a template (isTemplate true) and is not active (status Draft), because a
  template that runs would do the same work as ours a second time, and
- names a registry row (Template_<name> or Template_<name>_Delete), or one of the templates
  listed in NON_REGISTRY_TEMPLATES.

Scoped to Core. Giving's rows join when Giving's templates, or its reasons, are written.
"""

import glob
import os
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"
# Core and the Rollup Builder module, whose registry rows were Core's until ADR-0125
# (0125-rollup-builder-module.md) moved the engine out.
PACKAGES = ("core", "rollups", "volunteers")
REGISTRY_GLOBS = [
    f"packages/{package}/main/default/customMetadata/Automation_Registry.*.md-meta.xml"
    for package in PACKAGES
]
FLOW_DIRS = [f"packages/{package}/main/default/flows" for package in PACKAGES]
GUIDE = "docs/admin-guide/flow-templates.md"

# Templates that copy no registry row. The rollup template for an administrator's own object
# arrives with the rollup rework (slice S10) and is named here so this check accepts it.
NON_REGISTRY_TEMPLATES = {"Recalculate_Rollups"}


def q(tag):
    return f"{{{NS}}}{tag}"


def registry_rows():
    """(DeveloperName, label, always_runs) for every Core registry record."""
    rows = []
    for path in sorted(path for pattern in REGISTRY_GLOBS for path in glob.glob(pattern)):
        name = os.path.basename(path)[len("Automation_Registry.") : -len(".md-meta.xml")]
        root = ET.parse(path).getroot()
        label = (root.findtext(q("label")) or "").strip()
        always = False
        for values in root.findall(q("values")):
            if (values.findtext(q("field")) or "").strip() == "Always_Runs__c":
                always = (values.findtext(q("value")) or "").strip().lower() == "true"
        rows.append((name, label, always))
    return rows


def guide_without_template():
    """Labels the admin guide lists as having no template."""
    labels = set()
    if not os.path.exists(GUIDE):
        return labels
    with open(GUIDE, encoding="utf-8") as handle:
        for line in handle:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) >= 2 and cells[1].startswith("None"):
                labels.add(cells[0])
    return labels


def main():
    problems = []
    rows = registry_rows()
    names = {name for name, _, _ in rows}
    templates = {}
    flow_paths = [
        path
        for flow_dir in FLOW_DIRS
        for path in glob.glob(os.path.join(flow_dir, "Template_*.flow-meta.xml"))
    ]
    for path in sorted(flow_paths):
        templates[os.path.basename(path)[: -len(".flow-meta.xml")]] = path

    for flow, path in templates.items():
        root = ET.parse(path).getroot()
        if (root.findtext(q("isTemplate")) or "").strip() != "true":
            problems.append(f"{flow}: isTemplate must be true.")
        status = (root.findtext(q("status")) or "").strip()
        if status != "Draft":
            problems.append(f"{flow}: status is '{status}'; a template ships as Draft.")
        base = flow[len("Template_") :]
        if base.endswith("_Delete"):
            base = base[: -len("_Delete")]
        if base not in names and base not in NON_REGISTRY_TEMPLATES:
            problems.append(f"{flow}: names no Core Automation Registry row.")

    reasons = guide_without_template()
    checked = 0
    for name, label, always in rows:
        if always:
            continue
        checked += 1
        if f"Template_{name}" in templates:
            continue
        if label in reasons:
            continue
        problems.append(
            f"{name} ({label}): no flow Template_{name} and no 'None' row for it in {GUIDE}. "
            "Ship the template, or say in the guide why there is none."
        )

    for problem in problems:
        print(problem)
    if problems:
        print(f"check-flow-templates.py: FAILED, {len(problems)} problem(s) above")
        return 1
    print(
        f"check-flow-templates.py: OK, {checked} switchable Core automations each have a "
        f"template or a reason, {len(templates)} templates ship inactive"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
