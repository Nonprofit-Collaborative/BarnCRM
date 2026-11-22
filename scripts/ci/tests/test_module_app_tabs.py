import glob
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
CORE_ROLE_APPS = (mat.STAFF_APP, mat.ADMIN_APP)

CONSOLE = """<?xml version="1.0" encoding="UTF-8" ?>
<CustomApplication xmlns="http://soap.sforce.com/2006/04/metadata">
  <actionOverrides>
    <actionName>View</actionName>
    <content>Contact_Record_Page</content>
    <formFactor>Large</formFactor>
    <type>Flexipage</type>
    <pageOrSobjectType>Contact</pageOrSobjectType>
  </actionOverrides>
  <label>{name}</label>
  <navType>Console</navType>
  {tabs}
  <uiType>Lightning</uiType>
  <workspaceConfig>
    {mappings}
  </workspaceConfig>
</CustomApplication>
"""
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
  <navType>Console</navType>
  <tabs>Gift__c</tabs>
</CustomApplication>
"""


def console(name, tabs):
    return CONSOLE.format(
        name=name,
        tabs="\n  ".join(f"<tabs>{tab}</tabs>" for tab in tabs),
        mappings="\n    ".join(f"<mappings>\n      <tab>{tab}</tab>\n    </mappings>" for tab in tabs),
    )


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
    """Core's two role apps and a host app; Giving with its own app; Rollups and Logic Models with
    none; Memberships and Corporate Hub hosted by Core's app; Scholarships hosted by Funders'."""
    root = tempfile.mkdtemp()
    write(root, "sfdx-project.json", json.dumps({"sourceApiVersion": "67.0"}))
    write(root, f"{CORE}/applications/BarnCRM.app-meta.xml", console("BarnCRM", ["BarnCRM_Home"]))
    write(
        root,
        f"{CORE}/applications/BarnCRM_Admin_Console.app-meta.xml",
        console("BarnCRM_Admin_Console", ["BarnCRM_Settings", "Error_Log__c"]),
    )
    write(
        root,
        f"{CORE}/applications/BarnCRM_Members_Partners.app-meta.xml",
        console("BarnCRM_Members_Partners", ["standard-report", "Error_Log__c"]),
    )
    write(
        root,
        "packages/funders/main/default/applications/BarnCRM_Funders.app-meta.xml",
        console("BarnCRM_Funders", ["Funders_Board", "Grant__c", "standard-report", "Error_Log__c"]),
    )
    write(root, "packages/giving/main/default/applications/BarnCRM_Fundraising.app-meta.xml", MODULE_APP)
    rows = {
        "Giving": record("giving", 10, "Gift__c;Not_Shipped", "Giving_Nightly_Jobs", "BarnCRM_Fundraising"),
        "Rollups": record("rollups", 5, admin="Rollup_Builder"),
        "LogicModels": record("logicmodels", 35, staff="Logic_Model__c"),
        "Funders": record("funders", 40, staff="Grant__c", app="BarnCRM_Funders"),
        "Scholarships": record("scholarships", 42, staff="Scholarships;Award__c", app="BarnCRM_Funders"),
        "Memberships": record("memberships", 48, "Memberships_Home", "Membership_Level__c", "BarnCRM_Members_Partners"),
        "CorporateHub": record("corporatehub", 49, staff="Corporate_Hub", app="BarnCRM_Members_Partners"),
    }
    for name, body in rows.items():
        write(root, f"{CORE}/customMetadata/BarnCRM_Module.{name}.md-meta.xml", body)
    for rel in (
        "giving/main/default/tabs/Gift__c",
        "giving/main/default/tabs/Giving_Nightly_Jobs",
        "rollups/main/default/tabs/Rollup_Builder",
        "logicmodels/main/default/tabs/Logic_Model__c",
        "funders/main/default/tabs/Grant__c",
        "scholarships/main/default/tabs/Scholarships",
        "scholarships/main/default/tabs/Award__c",
        "memberships/main/default/tabs/Memberships_Home",
        "memberships/main/default/tabs/Membership_Level__c",
        "corporatehub/main/default/tabs/Corporate_Hub",
    ):
        write(root, f"packages/{rel}.tab-meta.xml")
    write(root, "packages/giving/main/default/objects/Gift__c/Gift__c.object-meta.xml")
    return root


def parsed(out, app):
    return ET.parse(os.path.join(out, "applications", app + ".app")).getroot()


def tabs(app):
    return [t.text for t in app.findall("m:tabs", NS)]


def mapped(app):
    return [m.text for m in app.findall("m:workspaceConfig/m:mappings/m:tab", NS)]


class ModuleAppTabsTest(unittest.TestCase):
    def test_a_module_with_no_app_puts_its_staff_tabs_in_the_console(self):
        root, out = repo(), tempfile.mkdtemp()
        written = mat.write_package(root, out, {"logicmodels"})

        self.assertEqual(written, ["BarnCRM"])
        self.assertEqual(tabs(parsed(out, "BarnCRM")), ["BarnCRM_Home", "Logic_Model__c"])
        self.assertEqual(mapped(parsed(out, "BarnCRM")), ["BarnCRM_Home", "Logic_Model__c"])

    def test_a_module_with_its_own_app_adds_staff_tabs_nowhere_and_admin_tabs_to_the_admin_console(self):
        root, out = repo(), tempfile.mkdtemp()
        mat.write_package(root, out, {"giving", "rollups"})

        self.assertEqual(
            tabs(parsed(out, "BarnCRM_Admin_Console")),
            ["BarnCRM_Settings", "Rollup_Builder", "Giving_Nightly_Jobs", "Error_Log__c"],
            "Rollups sorts before Giving, Error Log stays last, a tab not shipped is left out",
        )
        self.assertEqual(tabs(parsed(out, "BarnCRM")), ["BarnCRM_Home"], "Gift__c is in Fundraising only")

    def test_the_console_takes_the_module_record_pages_for_its_own_objects_only(self):
        root, out = repo(), tempfile.mkdtemp()
        mat.write_package(root, out, {"giving"})

        pages = [
            o.findtext("m:pageOrSobjectType", namespaces=NS)
            for o in parsed(out, "BarnCRM").findall("m:actionOverrides", NS)
        ]
        self.assertEqual(sorted(pages), ["Contact", "Gift__c"], "Core's Contact page stays the only one")
        admin = parsed(out, "BarnCRM_Admin_Console").findall("m:actionOverrides", NS)
        self.assertEqual(len(admin), 1, "The admin console takes no module record page")

    def test_a_core_host_app_opens_on_its_first_modules_home(self):
        root, out = repo(), tempfile.mkdtemp()
        written = mat.write_package(root, out, {"memberships", "corporatehub"})

        self.assertIn("BarnCRM_Members_Partners", written)
        host = parsed(out, "BarnCRM_Members_Partners")
        self.assertEqual(
            tabs(host),
            ["Memberships_Home", "Membership_Level__c", "Corporate_Hub", "standard-report", "Error_Log__c"],
            "Memberships first, its admin tabs too, before Reports and Error Log",
        )
        self.assertEqual(set(mapped(host)), set(tabs(host)))
        self.assertEqual(
            tabs(parsed(out, "BarnCRM_Admin_Console")),
            ["BarnCRM_Settings", "Membership_Level__c", "Error_Log__c"],
            "Admin tabs still join the admin console",
        )
        self.assertNotIn("BarnCRM", written, "Hosted staff tabs do not join the console")

    def test_either_module_alone_fills_the_core_host_app(self):
        root, out = repo(), tempfile.mkdtemp()
        mat.write_package(root, out, {"corporatehub"})

        self.assertEqual(
            tabs(parsed(out, "BarnCRM_Members_Partners")), ["Corporate_Hub", "standard-report", "Error_Log__c"]
        )

    def test_a_host_app_in_another_module_takes_the_tabs_after_its_own(self):
        root, out = repo(), tempfile.mkdtemp()
        written = mat.write_package(root, out, {"funders", "scholarships"})

        self.assertIn("BarnCRM_Funders", written)
        self.assertEqual(
            tabs(parsed(out, "BarnCRM_Funders")),
            ["Funders_Board", "Grant__c", "Scholarships", "Award__c", "standard-report", "Error_Log__c"],
            "Grants Home first, Scholarships after Grants' own tabs",
        )
        self.assertEqual(
            tabs(parsed(out, "BarnCRM")),
            ["BarnCRM_Home", "Scholarships", "Award__c"],
            "Scholarships' sets cannot show Grants, so its staff tabs stay in the Console too",
        )

    def test_a_core_host_app_keeps_the_tabs_out_of_the_console(self):
        root, out = repo(), tempfile.mkdtemp()
        written = mat.write_package(root, out, {"memberships"})

        self.assertIn("BarnCRM_Members_Partners", written)
        self.assertNotIn("BarnCRM", written)

    def test_without_the_host_package_the_tabs_fall_back_to_the_console(self):
        root, out = repo(), tempfile.mkdtemp()
        written = mat.write_package(root, out, {"scholarships"})

        self.assertNotIn("BarnCRM_Funders", written, "Funders was not deployed, so its app is not written")
        self.assertEqual(tabs(parsed(out, "BarnCRM")), ["BarnCRM_Home", "Scholarships", "Award__c"])

    def test_nothing_is_written_when_no_module_was_deployed_and_the_repo_is_untouched(self):
        root, out = repo(), tempfile.mkdtemp()
        source = os.path.join(root, CORE, "applications", "BarnCRM.app-meta.xml")
        before = read(source)

        self.assertEqual(mat.write_package(root, out, {"volunteers"}), [])
        self.assertFalse(os.path.exists(os.path.join(out, "package.xml")))
        mat.write_package(root, out, {"logicmodels"})
        self.assertEqual(read(source), before)

    def test_all_writes_every_deployed_host_app_so_a_module_left_out_leaves_them(self):
        root, out = repo(), tempfile.mkdtemp()
        written = mat.write_package(root, out, {"funders"}, write_all=True)

        self.assertEqual(written, ["BarnCRM", "BarnCRM_Admin_Console", "BarnCRM_Funders", "BarnCRM_Members_Partners"])
        self.assertEqual(tabs(parsed(out, "BarnCRM_Funders")), ["Funders_Board", "Grant__c", "standard-report", "Error_Log__c"])
        manifest = ET.parse(os.path.join(out, "package.xml")).getroot()
        self.assertEqual(len(list(manifest.iter(f"{{{mat.NS}}}members"))), 4)
        self.assertEqual(manifest.findtext("m:version", namespaces=NS), "67.0")
        self.assertNotIn("BarnCRM_Funders", mat.write_package(root, tempfile.mkdtemp(), set(), write_all=True))

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

    def test_every_catalog_app_is_shipped(self):
        """App_Name__c names an app some package ships: the module's own, or a host app."""
        root = os.path.join(HERE, "..", "..", "..")
        for row in mat.catalog(root):
            app = row.get("App_Name__c")
            if app:
                self.assertIsNotNone(mat.app_folder(root, app), f"{row.get('Package_Folder__c')}: no app {app}")

    def test_universal_modules_never_join_a_nonprofit_app(self):
        """Memberships, Corporate Hub, Forms, Events and Projects serve every organization, so
        their tabs never join Fundraising, Grants, Programs or Volunteers (D-221)."""
        root = os.path.join(HERE, "..", "..", "..")
        nonprofit_apps = {"BarnCRM_Fundraising", "BarnCRM_Funders", "BarnCRM_Programs", "BarnCRM_Volunteers"}
        for row in mat.catalog(root):
            if row.get("Package_Folder__c") in ("memberships", "corporatehub", "forms", "events", "projects"):
                self.assertNotIn(row.get("App_Name__c"), nonprofit_apps, row.get("Package_Folder__c"))

    def test_every_quick_link_opens_a_shipped_tab_or_object(self):
        """Quick_Links__c (D-200 R7): each Target:Label:Line names a tab the module ships, or
        one of its objects with .new, and carries a label."""
        root = os.path.join(HERE, "..", "..", "..")
        for row in mat.catalog(root):
            folder = row.get("Package_Folder__c")
            for entry in [p.strip() for p in (row.get("Quick_Links__c") or "").split(";") if p.strip()]:
                parts = [part.strip() for part in entry.split(":")]
                self.assertTrue(2 <= len(parts) <= 3 and parts[1], f"{folder}: {entry} needs Target:Label[:Line]")
                target = parts[0]
                if target.endswith(".new"):
                    path = os.path.join(root, "packages", folder, "main/default/objects", target[: -len(".new")])
                    self.assertTrue(os.path.isdir(path), f"{folder} ships no object {target}")
                else:
                    path = os.path.join(root, "packages", folder, "main/default/tabs", target + ".tab-meta.xml")
                    self.assertTrue(os.path.exists(path), f"{folder} ships no tab {target}")


class CoreAppsTest(unittest.TestCase):
    """Core's apps between them hold every tab Core ships, and only tabs that exist, so a tab
    added on one branch (Duplicate Matching) or removed on another is not missed in the apps.
    A console app maps every one of its tabs to a workspace. Find, Import and Bulk Update are in
    no app: they open from their Data Manager cards (D-135)."""

    # Import_Row__c opens from Super Importer's results (admin-22), not from an app's nav.
    # Record_Inspector opens from the Inspect This Record button only (D-183).
    # Brand__c and Legal_Entity__c open from BarnCRM Settings, Organization (C-47): brands ship
    # off, so no app gains a tab an org that never uses brands would see (ADR-0202 brand management).
    DATA_MANAGER_ONLY = {
        "Find", "Import", "Bulk_Update", "Import_Row__c", "Record_Inspector", "Brand__c", "Legal_Entity__c"
    }

    def core_apps(self):
        root = os.path.join(HERE, "..", "..", "..")
        paths = glob.glob(os.path.join(root, CORE, "applications", "*.app-meta.xml"))
        return {os.path.basename(p)[: -len(".app-meta.xml")]: ET.parse(p).getroot() for p in paths}

    def test_every_core_tab_is_in_a_core_app_and_every_app_tab_exists(self):
        root = os.path.join(HERE, "..", "..", "..")
        tab_dir = os.path.join(root, CORE, "tabs")
        shipped = {name[: -len(".tab-meta.xml")] for name in os.listdir(tab_dir)}
        in_apps = set()
        apps = self.core_apps()
        self.assertEqual(set(apps), {"BarnCRM", "BarnCRM_Admin_Console", "BarnCRM_Members_Partners"})
        for app_name, app in apps.items():
            tabs = [tab.text for tab in app.findall("m:tabs", NS)]
            for tab in tabs:
                if not tab.startswith("standard-"):
                    self.assertIn(tab, shipped, f"{app_name} lists {tab}, which Core does not ship")
            self.assertEqual(app.findtext("m:navType", namespaces=NS), "Console", app_name)
            mapped_tabs = [m.findtext("m:tab", namespaces=NS) for m in app.findall("m:workspaceConfig/m:mappings", NS)]
            self.assertEqual(set(tabs), set(mapped_tabs), f"{app_name}: every tab has a workspace mapping")
            in_apps.update(tabs)
        self.assertEqual(
            self.DATA_MANAGER_ONLY,
            shipped - in_apps,
            "every Core tab is in at least one Core app, except those Data Manager opens",
        )
        for app_name in CORE_ROLE_APPS:
            self.assertIn("Data_Manager", [tab.text for tab in apps[app_name].findall("m:tabs", NS)], app_name)

    def test_error_log_is_the_last_tab_of_every_app_that_has_it(self):
        root = os.path.join(HERE, "..", "..", "..")
        pattern = os.path.join(root, "packages", "*", "main", "default", "applications", "*.app-meta.xml")
        paths = glob.glob(pattern)
        self.assertTrue(paths)
        for path in paths:
            app = ET.parse(path).getroot()
            tabs = [tab.text for tab in app.findall("m:tabs", NS)]
            if mat.ERROR_LOG_TAB in tabs:
                self.assertEqual(tabs[-1], mat.ERROR_LOG_TAB, f"{os.path.basename(path)}: Error Log is last")

    def test_duplicate_matching_is_in_the_admin_console(self):
        tabs = [tab.text for tab in self.core_apps()[mat.ADMIN_APP].findall("m:tabs", NS)]
        self.assertIn("Duplicate_Matching", tabs)
        self.assertLess(tabs.index("Data_Manager"), tabs.index("Duplicate_Matching"))


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


if __name__ == "__main__":
    unittest.main()
