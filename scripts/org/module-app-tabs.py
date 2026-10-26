#!/usr/bin/env python3
"""Writes copies of the four Core apps with each deployed module's tabs added, for a deploy.

    python3 scripts/org/module-app-tabs.py OUT_DIR FOLDER [FOLDER ...]

Core may not name a module's tab in its own apps: a deploy of Core alone would fail on the
missing tab, and Core runs alone (ADR-0013). So the module tabs reach the BarnCRM apps from
outside Core's metadata (ADR-0136). Each module's
`BarnCRM_Module__mdt` record names its tabs: `Staff_Tabs__c` go to BarnCRM and BarnCRM Console,
`Admin_Tabs__c` to BarnCRM Admin and BarnCRM Admin Console, in the catalog's sort order. FOLDER
is a package folder under packages/ that the deploy has just put in the org (for example
`giving`); a module whose folder is not named is left out, and so is a named tab its package
does not ship. The everyday apps also take the record page assignments the module's own app
(`App_Name__c`) makes for the module's own objects, so a gift opened in BarnCRM shows the gift
page; Core's household and person pages stay as they are.

The repository's app files are never changed. OUT_DIR receives a metadata-format package
(`package.xml` and `applications/<App>.app`) holding only the apps that changed, ready for
`sf project deploy start --metadata-dir OUT_DIR`. Nothing is written when nothing changes, and
the script prints how many apps it wrote, so the caller can skip the deploy.
"""

import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORE = "packages/core/main/default"
STAFF_APPS = ("BarnCRM_Standard", "BarnCRM")
ADMIN_APPS = ("BarnCRM_Admin_Standard", "BarnCRM_Admin_Console")

ET.register_namespace("", NS)


def q(tag):
    return f"{{{NS}}}{tag}"


def catalog(root):
    """Each module record's values by field, in Sort_Order__c order."""
    rows = []
    pattern = os.path.join(root, CORE, "customMetadata", "BarnCRM_Module.*.md-meta.xml")
    for path in glob.glob(pattern):
        values = {}
        for value in ET.parse(path).getroot().findall(q("values")):
            values[value.findtext(q("field"))] = (value.findtext(q("value")) or "").strip()
        rows.append(values)
    return sorted(rows, key=lambda row: float(row.get("Sort_Order__c") or 0))


def names(text):
    """The tab names in a catalog field. An entry may carry its label after a colon
    (`Donor_Levels:Donor Level Ladder`) for the Setup Assistant; only the name is used here."""
    return [part.split(":")[0].strip() for part in (text or "").split(";") if part.strip()]


def own_record_pages(root, folder, app_name):
    """The module app's record page overrides for the module's own objects."""
    path = os.path.join(root, "packages", folder, "main/default/applications", app_name + ".app-meta.xml")
    if not app_name or not os.path.exists(path):
        return []
    objects = os.path.join(root, "packages", folder, "main/default/objects")
    return [
        override
        for override in ET.parse(path).getroot().findall(q("actionOverrides"))
        if os.path.isdir(os.path.join(objects, override.findtext(q("pageOrSobjectType")) or "-"))
    ]


def changes(root, folders):
    """The tabs and record page overrides to add to each Core app, and the named tabs not shipped."""
    tabs = {app: [] for app in STAFF_APPS + ADMIN_APPS}
    overrides = {app: [] for app in STAFF_APPS}
    missing = []
    for row in catalog(root):
        folder = row.get("Package_Folder__c", "")
        if folder not in folders:
            continue
        tab_dir = os.path.join(root, "packages", folder, "main/default/tabs")
        for key, apps in (("Staff_Tabs__c", STAFF_APPS), ("Admin_Tabs__c", ADMIN_APPS)):
            for tab in names(row.get(key)):
                if not os.path.exists(os.path.join(tab_dir, tab + ".tab-meta.xml")):
                    missing.append(f"{folder}/{tab}")
                    continue
                for app in apps:
                    if tab not in tabs[app]:
                        tabs[app].append(tab)
        if names(row.get("Staff_Tabs__c")):
            for app in STAFF_APPS:
                overrides[app].extend(own_record_pages(root, folder, row.get("App_Name__c")))
    return tabs, overrides, missing


def key(override):
    return tuple(override.findtext(q(tag)) for tag in ("actionName", "formFactor", "pageOrSobjectType"))


def changed_app(app_path, tabs, overrides):
    """The app's XML with the tabs added after its last tab (and a console workspace mapping for
    each) and the overrides after its last override; None when nothing is new."""
    app = ET.parse(app_path).getroot()
    children = list(app)
    present = {child.text for child in children if child.tag == q("tabs")}
    new_tabs = [tab for tab in tabs if tab not in present]
    held = {key(child) for child in children if child.tag == q("actionOverrides")}
    new_overrides = []
    for override in overrides:
        if key(override) not in held:
            held.add(key(override))
            new_overrides.append(override)
    if not new_tabs and not new_overrides:
        return None
    last_tab = max(i for i, child in enumerate(children) if child.tag == q("tabs"))
    for offset, tab in enumerate(new_tabs, start=1):
        element = ET.Element(q("tabs"))
        element.text, element.tail = tab, "\n  "
        app.insert(last_tab + offset, element)
    workspace = app.find(q("workspaceConfig"))
    if workspace is not None:
        for tab in new_tabs:
            mapping = ET.SubElement(workspace, q("mappings"))
            ET.SubElement(mapping, q("tab")).text = tab
            mapping.tail = "\n  "
    for override in new_overrides:
        override.tail = "\n  "
        app.insert(0, override)
    return ET.tostring(app, encoding="unicode", xml_declaration=True)


def api_version(root):
    with open(os.path.join(root, "sfdx-project.json"), encoding="utf-8") as handle:
        return json.load(handle)["sourceApiVersion"]


def write_package(root, out_dir, folders):
    """Writes the changed apps and their package.xml; returns the app names written."""
    tabs, overrides, missing = changes(root, folders)
    for name in missing:
        print(f"Skipped {name}: the catalog names it but the package ships no such tab.")
    written = []
    for app in STAFF_APPS + ADMIN_APPS:
        source = os.path.join(root, CORE, "applications", app + ".app-meta.xml")
        xml = changed_app(source, tabs[app], overrides.get(app, []))
        if xml is None:
            continue
        os.makedirs(os.path.join(out_dir, "applications"), exist_ok=True)
        with open(os.path.join(out_dir, "applications", app + ".app"), "w", encoding="utf-8") as f:
            f.write(xml + "\n")
        written.append(app)
    if written:
        members = "".join(f"    <members>{app}</members>\n" for app in written)
        with open(os.path.join(out_dir, "package.xml"), "w", encoding="utf-8") as handle:
            handle.write(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                f'<Package xmlns="{NS}">\n  <types>\n{members}'
                "    <name>CustomApplication</name>\n  </types>\n"
                f"  <version>{api_version(root)}</version>\n</Package>\n"
            )
    return written


def main(argv):
    if len(argv) < 2:
        print("Usage: module-app-tabs.py OUT_DIR FOLDER [FOLDER ...]", file=sys.stderr)
        return 2
    written = write_package(ROOT, argv[0], set(argv[1:]))
    print(f"{len(written)} app(s) written: {', '.join(written) or 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
