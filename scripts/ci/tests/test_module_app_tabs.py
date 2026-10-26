import importlib.util
import json
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "mat", os.path.join(HERE, "..", "..", "org", "module-app-tabs.py")
)
mat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mat)

NS = {"m": mat.NS}
CORE = "packages/core/main/default"

STANDARD = """<?xml version="1.0" encoding="UTF-8" ?>
<CustomApplication xmlns="http://soap.sforce.com/2006/04/metadata">
  <actionOverrides>
    <actionName>View</actionName>
    <content>Contact_Record_Page</content>
    <formFactor>Large</formFactor>
    <type>Flexipage</type>
    <pageOrSobjectType>Contact</pageOrSobjectType>
  </actionOverrides>
  <label>{name}</label>
  <navType>Standard</navType>
  <tabs>BarnCRM_Home</tabs>
  <uiType>Lightning</uiType>
</CustomApplication>
"""
CONSOLE = STANDARD.replace("Standard</navType>", "Console</navType>").replace(
    "</uiType>", "</uiType>\n  <workspaceConfig>\n    <mappings>\n      <tab>BarnCRM_Home</tab>\n    </mappings>\n  </workspaceConfig>"
)
MODULE_APP = """<?xml version="1.0" encoding="UTF-8" ?>
<CustomApplication xmlns="http://soap.sforce.com/2006/04/metadata">
  <actionOverrides>
    <actionName>View</actionName>
    <content>Gift_Record_Page</content>
    <formFactor>Large</formFactor>
    <type>Flexipage</type>
    <pageOrSobjectType>Gift__c</pageOrSobjectType>
  </actionOverrides>
  <actionOverrides>
    <actionName>View</actionName>
    <content>Giving_Contact_Record_Page</content>
    <formFactor>Large</formFactor>
    <type>Flexipage</type>
    <pageOrSobjectType>Contact</pageOrSobjectType>
  </actionOverrides>
  <label>Fundraising</label>
  <tabs>Gift__c</tabs>
</CustomApplication>
"""


def record(folder, order, staff="", admin="", app=""):
    values = [
        ("Package_Folder__c", folder),
        ("Sort_Order__c", str(order)),
        ("Staff_Tabs__c", staff),
        ("Admin_Tabs__c", admin),
        ("App_Name__c", app),
    ]
    body = "".join(
        f"<values><field>{field}</field><value>{value}</value></values>" for field, value in values
    )
    return f'<CustomMetadata xmlns="{mat.NS}">{body}</CustomMetadata>'


def write(root, rel, content=""):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)


def repo():
    root = tempfile.mkdtemp()
    write(root, "sfdx-project.json", json.dumps({"sourceApiVersion": "67.0"}))
    for app in mat.STAFF_APPS + mat.ADMIN_APPS:
        body = CONSOLE if app in ("BarnCRM", "BarnCRM_Admin_Console") else STANDARD
        write(root, f"{CORE}/applications/{app}.app-meta.xml", body.format(name=app))
    write(
        root,
        f"{CORE}/customMetadata/BarnCRM_Module.Giving.md-meta.xml",
        record("giving", 10, "Gift__c;Not_Shipped", "Giving_Nightly_Jobs", "Fundraising"),
    )
    write(root, f"{CORE}/customMetadata/BarnCRM_Module.Rollups.md-meta.xml", record("rollups", 5, admin="Rollup_Builder"))
    for rel in (
        "packages/giving/main/default/tabs/Gift__c.tab-meta.xml",
        "packages/giving/main/default/tabs/Giving_Nightly_Jobs.tab-meta.xml",
        "packages/giving/main/default/objects/Gift__c/Gift__c.object-meta.xml",
        "packages/rollups/main/default/tabs/Rollup_Builder.tab-meta.xml",
    ):
        write(root, rel)
    write(root, "packages/giving/main/default/applications/Fundraising.app-meta.xml", MODULE_APP)
    return root


def parsed(out, app):
    return ET.parse(os.path.join(out, "applications", app + ".app")).getroot()


def tabs(app):
    return [t.text for t in app.findall("m:tabs", NS)]


class ModuleAppTabsTest(unittest.TestCase):
    def test_staff_and_admin_tabs_go_to_their_apps_in_catalog_order(self):
        root, out = repo(), tempfile.mkdtemp()
        written = mat.write_package(root, out, {"giving", "rollups"})

        self.assertEqual(set(written), set(mat.STAFF_APPS + mat.ADMIN_APPS))
        self.assertEqual(tabs(parsed(out, "BarnCRM_Standard")), ["BarnCRM_Home", "Gift__c"])
        self.assertEqual(
            tabs(parsed(out, "BarnCRM_Admin_Console")),
            ["BarnCRM_Home", "Rollup_Builder", "Giving_Nightly_Jobs"],
            "Rollups sorts before Giving; a tab the package does not ship is left out",
        )

    def test_a_console_app_gets_a_workspace_mapping_for_each_new_tab(self):
        root, out = repo(), tempfile.mkdtemp()
        mat.write_package(root, out, {"giving"})

        mapped = [m.text for m in parsed(out, "BarnCRM").findall("m:workspaceConfig/m:mappings/m:tab", NS)]
        self.assertEqual(mapped, ["BarnCRM_Home", "Gift__c"])
        self.assertIsNone(parsed(out, "BarnCRM_Standard").find("m:workspaceConfig", NS))

    def test_the_everyday_apps_take_the_module_record_pages_for_its_own_objects_only(self):
        root, out = repo(), tempfile.mkdtemp()
        mat.write_package(root, out, {"giving"})

        pages = [
            o.findtext("m:pageOrSobjectType", namespaces=NS)
            for o in parsed(out, "BarnCRM_Standard").findall("m:actionOverrides", NS)
        ]
        self.assertEqual(sorted(pages), ["Contact", "Gift__c"], "Core's Contact page stays the only one")
        admin = [o for o in parsed(out, "BarnCRM_Admin_Standard").findall("m:actionOverrides", NS)]
        self.assertEqual(len(admin), 1, "The admin apps take no module record page")

    def test_nothing_is_written_when_no_module_was_deployed_and_the_repo_is_untouched(self):
        root, out = repo(), tempfile.mkdtemp()
        source = os.path.join(root, CORE, "applications", "BarnCRM.app-meta.xml")
        before = read(source)

        self.assertEqual(mat.write_package(root, out, {"volunteers"}), [])
        self.assertFalse(os.path.exists(os.path.join(out, "package.xml")))
        mat.write_package(root, out, {"giving"})
        self.assertEqual(read(source), before)

    def test_the_package_manifest_names_each_written_app(self):
        root, out = repo(), tempfile.mkdtemp()
        written = mat.write_package(root, out, {"rollups"})

        manifest = ET.parse(os.path.join(out, "package.xml")).getroot()
        self.assertEqual(sorted(m.text for m in manifest.iter(f"{{{mat.NS}}}members")), sorted(written))
        self.assertEqual(manifest.findtext("m:version", namespaces=NS), "67.0")
        self.assertEqual(set(written), set(mat.ADMIN_APPS), "Rollups has admin tabs only")

    def test_an_entry_label_after_a_colon_is_not_part_of_the_tab_name(self):
        self.assertEqual(mat.names("Donor_Levels:Donor Level Ladder; Gift__c"), ["Donor_Levels", "Gift__c"])


class RealCatalogTest(unittest.TestCase):
    """The Setup Assistant shows each catalog tab by the label an entry carries, else by its
    name with spaces (an object tab is labelled from its object in Apex). For a page tab that
    must match the label App Manager shows, or the admin cannot find the page to add."""

    def test_every_catalog_tab_is_shipped_and_named_as_app_manager_names_it(self):
        root = os.path.join(HERE, "..", "..", "..")
        for row in mat.catalog(root):
            folder = row.get("Package_Folder__c")
            for field in ("Staff_Tabs__c", "Admin_Tabs__c"):
                for entry in [p.strip() for p in (row.get(field) or "").split(";") if p.strip()]:
                    name, _, written = (part.strip() for part in entry.partition(":"))
                    path = os.path.join(root, "packages", folder, "main/default/tabs", name + ".tab-meta.xml")
                    self.assertTrue(os.path.exists(path), f"{folder} ships no tab {name}")
                    if name.endswith("__c"):
                        self.assertEqual(written, "", f"{name}: an object tab takes its object's label")
                        continue
                    label = ET.parse(path).getroot().findtext("m:label", namespaces=NS)
                    self.assertEqual(written or name.replace("_", " "), label, f"{folder} {name}")


class CoreAppsTest(unittest.TestCase):
    """The four Core apps between them hold every tab Core ships, and only tabs that exist, so a
    tab added on one branch (Duplicate Matching) or removed on another is not missed in the apps.
    A console app maps every one of its tabs to a workspace."""

    def test_every_core_tab_is_in_a_core_app_and_every_app_tab_exists(self):
        root = os.path.join(HERE, "..", "..", "..")
        tab_dir = os.path.join(root, CORE, "tabs")
        shipped = {name[: -len(".tab-meta.xml")] for name in os.listdir(tab_dir)}
        in_apps = set()
        for app_name in mat.STAFF_APPS + mat.ADMIN_APPS:
            app = ET.parse(os.path.join(root, CORE, "applications", app_name + ".app-meta.xml")).getroot()
            tabs = [tab.text for tab in app.findall("m:tabs", NS)]
            for tab in tabs:
                if not tab.startswith("standard-"):
                    self.assertIn(tab, shipped, f"{app_name} lists {tab}, which Core does not ship")
            if app.findtext("m:navType", namespaces=NS) == "Console":
                mapped = [m.findtext("m:tab", namespaces=NS) for m in app.findall("m:workspaceConfig/m:mappings", NS)]
                self.assertEqual(set(tabs), set(mapped), f"{app_name}: every tab has a workspace mapping")
            in_apps.update(tabs)
        self.assertEqual(set(), shipped - in_apps, "every Core tab is in at least one Core app")

    def test_duplicate_matching_is_in_both_admin_apps(self):
        root = os.path.join(HERE, "..", "..", "..")
        for app_name in mat.ADMIN_APPS:
            app = ET.parse(os.path.join(root, CORE, "applications", app_name + ".app-meta.xml")).getroot()
            tabs = [tab.text for tab in app.findall("m:tabs", NS)]
            self.assertIn("Duplicate_Matching", tabs, app_name)
            self.assertLess(tabs.index("Data_Hygiene"), tabs.index("Duplicate_Matching"), app_name)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


if __name__ == "__main__":
    unittest.main()
