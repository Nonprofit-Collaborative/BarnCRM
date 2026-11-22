#!/usr/bin/env python3
"""Writes copies of the apps that host module tabs, with each deployed module's tabs added.

    python3 scripts/org/module-app-tabs.py [--all] OUT_DIR FOLDER [FOLDER ...]

An app may not name a tab its own package does not ship: a deploy of that package alone would
fail on the missing tab, and each package runs without the modules that do not depend on it
(ADR-0013). So module tabs reach an app in another package from outside that app's metadata
(ADR-0137). Each module's `BarnCRM_Module__mdt` record names its tabs and its app, and the app
it names decides where the tabs go (ADR-0237, nine console apps):

- `App_Name__c` names an app another package ships (a host app: Core's BarnCRM Members and
  Partners for Memberships and Corporate Hub, Funders' BarnCRM Grants for Scholarships): the
  module's `Staff_Tabs__c` and `Admin_Tabs__c` join that app, when its package was deployed too.
  A host app outside Core (BarnCRM Grants) is one the module's own permission sets cannot show,
  so its `Staff_Tabs__c` join BarnCRM Console as well, and its staff always keep an app.
- `App_Name__c` names the module's own app (BarnCRM Events, BarnCRM Fundraising): the app
  already lists the tabs, so they join no other app.
- `App_Name__c` is empty, or names a host app whose package was not deployed: `Staff_Tabs__c`
  join BarnCRM Console.
- `Admin_Tabs__c` always join BarnCRM Admin Console as well, so every admin tool is in one app.

Tabs are added in the catalog's sort order, before the app's first Reports, Dashboards or Error
Log tab (Error Log is always an app's last tab, D-135), so a host app opens on its first module's
home. FOLDER is a package folder under packages/ that the deploy has just put in the org (for
example `giving`); a module whose folder is not named is left out, and so is a named tab its
package does not ship. BarnCRM Console also takes the record page assignments a module's own app
(`App_Name__c`) makes for the module's own objects, so a gift opened in BarnCRM Console shows the
gift page; Core's household and person pages stay as they are.

The repository's app files are never changed. OUT_DIR receives a metadata-format package
(`package.xml` and `applications/<App>.app`) holding only the apps that changed, ready for
`sf project deploy start --metadata-dir OUT_DIR`. Nothing is written when nothing changes, and
the script prints how many apps it wrote, so the caller can skip the deploy.

With --all, every host app whose package was deployed (Core's always) is written, changed or
not, so the deploy leaves each app holding exactly its own tabs plus those of the folders named.
That is how a removed module's tabs leave the apps: name only the modules kept (ADR-0192).
"""

import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORE = "packages/core/main/default"
STAFF_APP = "BarnCRM"
ADMIN_APP = "BarnCRM_Admin_Console"
ERROR_LOG_TAB = "Error_Log__c"
# An app's closing tabs: module tabs go before the first of these.
TRAILING_TABS = ("standard-report", "standard-Dashboard", ERROR_LOG_TAB)

ET.register_namespace("", NS)


def q(tag):
    return f"{{{NS}}}{tag}"


def catalog(root):
    """Each module record's values by field, in Sort_Order__c order, then by file path so
    records with the same order come out the same way on every run."""
    rows = []
    pattern = os.path.join(root, CORE, "customMetadata", "BarnCRM_Module.*.md-meta.xml")
    for path in glob.glob(pattern):
        values = {}
        for value in ET.parse(path).getroot().findall(q("values")):
            values[value.findtext(q("field"))] = (value.findtext(q("value")) or "").strip()
        rows.append((float(values.get("Sort_Order__c") or 0), path, values))
    return [values for _order, _path, values in sorted(rows, key=lambda row: (row[0], row[1]))]


def names(text):
    """The tab names in a catalog field. An entry may carry its label after a colon
    (`Donor_Levels:Donor Level Ladder`) for the Setup Assistant; only the name is used here."""
    return [part.split(":")[0].strip() for part in (text or "").split(";") if part.strip()]


def app_path(root, folder, app_name):
    return os.path.join(root, "packages", folder, "main/default/applications", app_name + ".app-meta.xml")


def app_folder(root, app_name):
    """The package folder that ships the app, or None."""
    if not app_name:
        return None
    found = glob.glob(app_path(root, "*", app_name))
    return found[0].split(os.sep + "packages" + os.sep, 1)[1].split(os.sep, 1)[0] if found else None


def host_apps(root):
    """Every app module tabs may join, by app name: the two Core role apps, and each app a
    catalog row names that a package other than the row's own ships."""
    hosts = {STAFF_APP: "core", ADMIN_APP: "core"}
    for row in catalog(root):
        app = row.get("App_Name__c", "")
        folder = app_folder(root, app)
        if folder and folder != row.get("Package_Folder__c"):
            hosts[app] = folder
    return hosts


def own_record_pages(root, folder, app_name):
    """The module app's record page overrides for the module's own objects."""
    path = app_path(root, folder, app_name)
    if not app_name or not os.path.exists(path):
        return []
    objects = os.path.join(root, "packages", folder, "main/default/objects")
    return [
        override
        for override in ET.parse(path).getroot().findall(q("actionOverrides"))
        if os.path.isdir(os.path.join(objects, override.findtext(q("pageOrSobjectType")) or "-"))
    ]


def changes(root, folders):
    """The tabs and record page overrides to add to each host app whose package is deployed,
    and the named tabs not shipped."""
    hosts = {app: folder for app, folder in host_apps(root).items() if folder == "core" or folder in folders}
    tabs = {app: [] for app in hosts}
    overrides = {app: [] for app in hosts}
    missing = []
    for row in catalog(root):
        folder = row.get("Package_Folder__c", "")
        if folder not in folders:
            continue
        app = row.get("App_Name__c", "")
        home = app if hosts.get(app, folder) != folder and app not in (STAFF_APP, ADMIN_APP) else None
        own = not home and bool(app) and os.path.exists(app_path(root, folder, app))
        # The module's sets cannot show a host app outside Core, so its staff tabs join the Console too.
        staff_apps = ([home] + ([STAFF_APP] if hosts[home] != "core" else [])) if home else ([] if own else [STAFF_APP])
        admin_apps = [ADMIN_APP] + ([home] if home else [])
        tab_dir = os.path.join(root, "packages", folder, "main/default/tabs")
        for key, apps in (("Staff_Tabs__c", staff_apps), ("Admin_Tabs__c", admin_apps)):
            for tab in names(row.get(key)):
                if not os.path.exists(os.path.join(tab_dir, tab + ".tab-meta.xml")):
                    missing.append(f"{folder}/{tab}")
                    continue
                for target in apps:
                    if tab not in tabs[target]:
                        tabs[target].append(tab)
        if names(row.get("Staff_Tabs__c")):
            overrides[STAFF_APP].extend(own_record_pages(root, folder, app))
    return hosts, tabs, overrides, missing


def key(override):
    return tuple(override.findtext(q(tag)) for tag in ("actionName", "formFactor", "pageOrSobjectType"))


def insert_at(items, name_of):
    """The index of the first closing tab (Reports, Dashboards, Error Log), else the end."""
    for index, item in enumerate(items):
        if name_of(item) in TRAILING_TABS:
            return index
    return len(items)


def changed_app(app_path_, tabs, overrides, write_all=False):
    """The app's XML with the tabs added before its first closing tab (or last), with a console
    workspace mapping for each, and the overrides first; None when nothing is new, unless
    write_all asks for the app as it is."""
    app = ET.parse(app_path_).getroot()
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
        return ET.tostring(app, encoding="unicode", xml_declaration=True) if write_all else None
    tab_positions = [i for i, child in enumerate(children) if child.tag == q("tabs")]
    closing = insert_at([children[i] for i in tab_positions], lambda child: child.text)
    start = tab_positions[closing] if closing < len(tab_positions) else max(tab_positions) + 1
    for offset, tab in enumerate(new_tabs):
        element = ET.Element(q("tabs"))
        element.text, element.tail = tab, "\n  "
        app.insert(start + offset, element)
    workspace = app.find(q("workspaceConfig"))
    if workspace is not None:
        at = insert_at(list(workspace), lambda mapping: mapping.findtext(q("tab")))
        for offset, tab in enumerate(new_tabs):
            mapping = ET.Element(q("mappings"))
            ET.SubElement(mapping, q("tab")).text = tab
            mapping.tail = "\n    " if at + offset < len(list(workspace)) else "\n  "
            workspace.insert(at + offset, mapping)
    for override in new_overrides:
        override.tail = "\n  "
        app.insert(0, override)
    return ET.tostring(app, encoding="unicode", xml_declaration=True)


def api_version(root):
    with open(os.path.join(root, "sfdx-project.json"), encoding="utf-8") as handle:
        return json.load(handle)["sourceApiVersion"]


def write_package(root, out_dir, folders, write_all=False):
    """Writes the changed host apps (every deployed one with write_all) and their package.xml;
    returns the app names written."""
    hosts, tabs, overrides, missing = changes(root, folders)
    for name in missing:
        print(f"Skipped {name}: the catalog names it but the package ships no such tab.")
    written = []
    for app in [STAFF_APP, ADMIN_APP] + sorted(set(hosts) - {STAFF_APP, ADMIN_APP}):
        xml = changed_app(app_path(root, hosts[app], app), tabs[app], overrides[app], write_all)
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
    write_all = "--all" in argv
    argv = [arg for arg in argv if arg != "--all"]
    if len(argv) < (1 if write_all else 2):
        print("Usage: module-app-tabs.py [--all] OUT_DIR FOLDER [FOLDER ...]", file=sys.stderr)
        return 2
    written = write_package(ROOT, argv[0], set(argv[1:]), write_all)
    print(f"{len(written)} app(s) written: {', '.join(written) or 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
