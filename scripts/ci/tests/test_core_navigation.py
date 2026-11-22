"""Core app navigation and tab icons (UX PR 2, D-135, D-140).

A tab's icon comes from the number in its motif ("Custom20: ..." is always the airplane); the
name after the colon is only a note, so a guessed name hides a wrong icon. Each Core tab's
motif must pair its number with the icon Salesforce documents for it, and no two Core tabs may
share one. Core ships console apps only: BarnCRM Console lists records and then Data Manager last
(module tabs follow it), Error Log is BarnCRM Admin Console's last tab, and BarnCRM Members and
Partners holds only the closing tabs its modules fill.
"""

import glob
import os
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CORE = os.path.join(ROOT, "packages/core/main/default")
NS = {"m": "http://soap.sforce.com/2006/04/metadata"}

# The Metadata API's documented motif values (CustomTab.motif), Custom1 to Custom100.
MOTIFS = (
    "Heart Fan Sun Hexagon Leaf Triangle Square Diamond Lightning Moon Star Circle Box Hands "
    "People Bank Sack Form Wrench Airplane Computer Telephone Envelope Building Alarmclock Flag "
    "Laptop Cellphone PDA Radardish Car Factory Desk Insect Microphone Train Bridge Camera "
    "Telescope Creditcard Cash Treasurechest Jewel Hammer Ticket Stamp Knight Trophy CD/DVD "
    "Bigtop Apple Balls Bell Boat Books Bottle BuildingBlock Caduceus Can Umbrella Castle "
    "Chalkboard Chip Compass Cup Dice Gears Globe Guitar Handsaw Headset Helicopter HighwaySign "
    "HotAirBalloon IPPhone Keys Locked Map MeasuringTape Motorcycle MusicalNote Whistle Pencil "
    "Presenter RealEstateSign RedCross Safe Sailboat Saxophone Scales Shield Ship ShoppingCart "
    "Stethoscope Stopwatch StreetSign Thermometer Truck TVCRT TVWidescreen"
).split()


def tabs(app):
    root = ET.parse(os.path.join(CORE, "applications", app + ".app-meta.xml")).getroot()
    return [tab.text for tab in root.findall("m:tabs", NS)]


class CoreTabMotifs(unittest.TestCase):
    def test_each_core_tab_names_its_real_icon_once(self):
        self.assertEqual(len(MOTIFS), 100)
        seen = {}
        # Every package's tabs (UX-F3): module tabs follow the Core rule. Salesforce has only 100
        # motifs and BarnCRM used them all in the combined build (2026-11-11), so a module tab may
        # share a number with a tab in another module, never with a Core tab and never within its
        # own package (D-193; docs/contributor-guide/tab-icons.md).
        pattern = os.path.join(ROOT, "packages", "*", "main", "default", "tabs", "*.tab-meta.xml")
        for path in sorted(glob.glob(pattern)):
            name = os.path.basename(path).replace(".tab-meta.xml", "")
            package = path.split(os.sep + "packages" + os.sep, 1)[1].split(os.sep, 1)[0]
            motif = ET.parse(path).getroot().findtext("m:motif", namespaces=NS) or ""
            match = re.fullmatch(r"Custom(\d+): (\S+)", motif.strip())
            self.assertIsNotNone(match, f"{name}: motif {motif!r} is not 'CustomN: Name'")
            number, label = int(match.group(1)), match.group(2)
            self.assertEqual(
                label, MOTIFS[number - 1], f"{name}: Custom{number} is {MOTIFS[number - 1]}"
            )
            for other_package, other in seen.get(number, []):
                self.assertFalse(
                    other_package == package or "core" in (package, other_package),
                    f"{name} and {other} share Custom{number}",
                )
            seen.setdefault(number, []).append((package, name))


def tab_numbers():
    numbers = {}
    pattern = os.path.join(ROOT, "packages", "*", "main", "default", "tabs", "*.tab-meta.xml")
    for path in glob.glob(pattern):
        motif = ET.parse(path).getroot().findtext("m:motif", namespaces=NS) or ""
        match = re.match(r"Custom(\d+):", motif.strip())
        if match:
            numbers[os.path.basename(path).replace(".tab-meta.xml", "")] = int(match.group(1))
    return numbers


def card_icon_rows():
    """The Card Icons table of docs/contributor-guide/tab-icons.md: (package, component, icon) to tab."""
    path = os.path.join(ROOT, "docs", "contributor-guide", "tab-icons.md")
    section = open(path, encoding="utf-8").read().split("## Card Icons", 1)[-1]
    rows = {}
    for line in section.splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) == 4 and cells[2].startswith("custom:"):
            rows[(cells[0], cells[1], cells[2])] = cells[3]
    return rows


class CardIcons(unittest.TestCase):
    """A card's header icon is its own tab's motif (vis-core-4, extends D-144)."""

    def test_each_card_uses_its_own_tabs_icon_and_no_utility_glyph(self):
        numbers, rows = tab_numbers(), card_icon_rows()
        self.assertTrue(rows, "tab-icons.md has no Card Icons table")
        pattern = os.path.join(ROOT, "packages", "*", "main", "default", "lwc", "*", "*.html")
        for path in sorted(glob.glob(pattern)):
            parts = path.split(os.sep)
            package, component = parts[-6], parts[-2]
            text = open(path, encoding="utf-8").read()
            for icon in re.findall(r"<lightning-card\b[^>]*?icon-name=\"([^\"]+)\"", text, re.S):
                self.assertFalse(icon.startswith("utility:"), f"{component}: card header uses {icon}")
                if icon.startswith("custom:"):
                    self.assertIn(
                        (package, component, icon), rows, f"{component}: {icon} not in Card Icons"
                    )
        for (package, component, icon), tab in rows.items():
            self.assertIn(tab, numbers, f"{component}: no tab {tab}")
            self.assertEqual(
                icon, f"custom:custom{numbers[tab]}", f"{component}: {tab} is Custom{numbers[tab]}"
            )
            folder = os.path.join(ROOT, "packages", package, "main", "default", "lwc", component)
            source = "".join(
                open(os.path.join(folder, name), encoding="utf-8").read()
                for name in os.listdir(folder)
                if name.endswith((".html", ".js"))
            )
            # The icon as a literal, or from the registry by its tab (iconFor('Gift__c')).
            self.assertRegex(
                source, rf"['\"]({icon}|{tab})['\"]", f"{component} does not use {icon}"
            )


class IconRegistry(unittest.TestCase):
    """c/barnIcons (the Visual Standard's icon registry) maps every tab to its own motif."""

    def test_registry_lists_every_tab_with_its_motif(self):
        path = os.path.join(CORE, "lwc", "barnIcons", "barnIcons.js")
        with open(path, encoding="utf-8") as handle:
            entries = dict(re.findall(r"^\s+(\w+): '(\w+:\w+)',?$", handle.read(), re.M))
        numbers = tab_numbers()
        for name, number in numbers.items():
            self.assertEqual(entries.get(name), f"custom:custom{number}", f"barnIcons.js: {name}")
        for name, icon in entries.items():
            if icon.startswith("custom:"):
                self.assertIn(name, numbers, f"barnIcons.js: {name} names no tab")


class AppHeaderColor(unittest.TestCase):
    def test_every_app_uses_the_barncrm_header_colors(self):
        # ADR-0224 (Patch brand): every app, admin and module apps included, has the Barn Navy
        # header #1E2A3A, so switching apps stays in BarnCRM; the logo says which app.
        pattern = os.path.join(ROOT, "packages", "*", "main", "default", "applications", "*.app-meta.xml")
        for path in sorted(glob.glob(pattern)):
            color = ET.parse(path).getroot().findtext("m:brand/m:headerColor", namespaces=NS)
            self.assertEqual(color, "#1E2A3A", os.path.basename(path))

    def test_every_app_logo_is_a_shipped_patch_asset(self):
        # A changed image needs a new ContentAsset name, so every logo is a Patch asset that
        # the app's own package ships.
        pattern = os.path.join(ROOT, "packages", "*", "main", "default", "applications", "*.app-meta.xml")
        for path in sorted(glob.glob(pattern)):
            logo = ET.parse(path).getroot().findtext("m:brand/m:logo", namespaces=NS)
            self.assertTrue(logo.startswith("BarnCRM_Patch_"), os.path.basename(path))
            assets = os.path.join(os.path.dirname(os.path.dirname(path)), "contentassets")
            self.assertTrue(
                os.path.isfile(os.path.join(assets, logo + ".asset-meta.xml")), os.path.basename(path)
            )


class CoreAppOrder(unittest.TestCase):
    def test_core_ships_console_apps_only(self):
        # ADR-0237 (nine console apps): BarnCRM Console, BarnCRM Admin Console and BarnCRM
        # Members and Partners, each in console navigation.
        pattern = os.path.join(CORE, "applications", "*.app-meta.xml")
        names = sorted(os.path.basename(p)[: -len(".app-meta.xml")] for p in glob.glob(pattern))
        self.assertEqual(names, ["BarnCRM", "BarnCRM_Admin_Console", "BarnCRM_Members_Partners"])
        for name in names:
            root = ET.parse(os.path.join(CORE, "applications", name + ".app-meta.xml")).getroot()
            self.assertEqual(root.findtext("m:navType", namespaces=NS), "Console", name)

    def test_the_console_lists_records_then_data_manager(self):
        console = tabs("BarnCRM")
        self.assertEqual(console[0], "BarnCRM_Home")
        self.assertEqual(console[-1], "Data_Manager")
        # The related-record tabs its subtab mappings need follow the main records.
        self.assertEqual(console[1:5], ["standard-Contact", "Households", "Organizations", "standard-Account"])

    def test_members_and_partners_holds_only_closing_tabs_for_modules_to_fill(self):
        # Memberships and Corporate Hub add their tabs before these (module-app-tabs.py), so the
        # app opens on Memberships Home or Corporate Hub Home.
        # A staff app, so no Error Log (OD-17).
        self.assertEqual(tabs("BarnCRM_Members_Partners"), ["standard-report", "standard-Dashboard"])

    def test_admin_console_ends_with_error_log(self):
        admin = tabs("BarnCRM_Admin_Console")
        self.assertEqual(admin[-1], "Error_Log__c")
        for tool in ("Find", "Import", "Bulk_Update"):
            self.assertNotIn(tool, admin, f"{tool} opens from its Data Manager card (D-135)")
        # admin-22: the raw Import Rows tab opens from Super Importer's results, not the nav.
        self.assertNotIn("Import_Row__c", admin)
        # D-184: Automation is its own tab, before Error Log.
        # The Org Optimizer module adds its tab when installed (its catalog row's Admin_Tabs__c).
        self.assertEqual(admin, ["BarnCRM_Settings", "Data_Manager", "Duplicate_Matching", "Automation", "Error_Log__c"])
        # D-183: the Record Inspector is button only; its tab stays for the button to open, not in the nav.
        self.assertNotIn("Record_Inspector", admin)


# Every shipped permission set that showed an app before the nine console apps (ADR-0237, nine
# console apps). Each must still show at least one shipped app, so nobody who had an app loses
# it. BarnCRM_App_Standard and BarnCRM_App_Admin_Standard are gone: their holders get the Console
# sets from the same roles (TabAccessService).
SETS_THAT_SHOWED_AN_APP = (
    "BarnCRM_App_Admin_Console BarnCRM_App_Console Connector_Admin Connector_Viewer "
    "Corporate_Hub_Admin Corporate_Hub_Read_Only Corporate_Hub_Staff Events_Admin Events_Read_Only "
    "Events_Staff Forms_Admin Forms_Read_Only Forms_Staff Funders_Admin Funders_Read_Only "
    "Funders_Staff Giving_Admin Giving_Read_Only Giving_Staff Memberships_Admin "
    "Memberships_Read_Only Memberships_Staff Portal_Admin Programs_Admin Programs_Read_Only "
    "Programs_Staff Projects_Admin Projects_Read_Only Projects_Staff Scholarships_Admin "
    "Scholarships_Read_Only Scholarships_Staff Volunteers_Admin Volunteers_Coordinator "
    "Volunteers_Read_Only Volunteers_Staff"
).split()


class EveryAppHolderKeepsAnApp(unittest.TestCase):
    def test_every_set_that_showed_an_app_still_shows_a_shipped_app(self):
        shipped = {
            os.path.basename(path)[: -len(".app-meta.xml")]
            for path in glob.glob(os.path.join(ROOT, "packages/*/main/default/applications/*.app-meta.xml"))
        }
        sets = {
            os.path.basename(path)[: -len(".permissionset-meta.xml")]: path
            for path in glob.glob(os.path.join(ROOT, "packages/*/main/default/permissionsets/*.permissionset-meta.xml"))
        }
        for name in SETS_THAT_SHOWED_AN_APP:
            with self.subTest(permission_set=name):
                self.assertIn(name, sets, "a set that showed an app is no longer shipped")
                root = ET.parse(sets[name]).getroot()
                visible = [
                    entry.findtext("m:application", namespaces=NS)
                    for entry in root.findall("m:applicationVisibilities", NS)
                    if entry.findtext("m:visible", namespaces=NS) == "true"
                ]
                self.assertTrue(set(visible) & shipped, f"{name} shows no shipped app: {visible}")


if __name__ == "__main__":
    unittest.main()
