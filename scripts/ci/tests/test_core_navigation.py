"""Core app navigation and tab icons (UX PR 2, D-135, D-140).

A tab's icon comes from the number in its motif ("Custom20: ..." is always the airplane); the
name after the colon is only a note, so a guessed name hides a wrong icon. Each Core tab's
motif must pair its number with the icon Salesforce documents for it, and no two Core tabs may
share one. The four Core apps keep one order: the everyday apps list records and then Data
Manager last (module tabs follow it), the two admin apps hold the same tabs, and Error Log is
the admin apps' last tab.
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
        # Every package's tabs (UX-F3): module tabs follow the Core rule, and no number repeats
        # anywhere in BarnCRM (docs/contributor-guide/tab-icons.md lists them).
        pattern = os.path.join(ROOT, "packages", "*", "main", "default", "tabs", "*.tab-meta.xml")
        for path in sorted(glob.glob(pattern)):
            name = os.path.basename(path).replace(".tab-meta.xml", "")
            motif = ET.parse(path).getroot().findtext("m:motif", namespaces=NS) or ""
            match = re.fullmatch(r"Custom(\d+): (\S+)", motif.strip())
            self.assertIsNotNone(match, f"{name}: motif {motif!r} is not 'CustomN: Name'")
            number, label = int(match.group(1)), match.group(2)
            self.assertEqual(
                label, MOTIFS[number - 1], f"{name}: Custom{number} is {MOTIFS[number - 1]}"
            )
            self.assertNotIn(number, seen, f"{name} and {seen.get(number)} share Custom{number}")
            seen[number] = name


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
        # D-58: everyday apps #007A9E, admin apps #032D60, so switching apps stays in BarnCRM.
        pattern = os.path.join(ROOT, "packages", "*", "main", "default", "applications", "*.app-meta.xml")
        for path in sorted(glob.glob(pattern)):
            color = ET.parse(path).getroot().findtext("m:brand/m:headerColor", namespaces=NS)
            self.assertIn(color, ("#007A9E", "#032D60"), os.path.basename(path))


class CoreAppOrder(unittest.TestCase):
    def test_everyday_apps_list_records_then_data_manager(self):
        standard, console = tabs("BarnCRM_Standard"), tabs("BarnCRM")
        self.assertEqual(standard[-1], "Data_Manager")
        self.assertEqual(console[-1], "Data_Manager")
        # The console keeps the related-record tabs its subtab mappings need, after the
        # standard app's records.
        self.assertEqual(console[: len(standard) - 1], standard[:-1])

    def test_admin_apps_match_and_end_with_error_log(self):
        admin, admin_console = tabs("BarnCRM_Admin_Standard"), tabs("BarnCRM_Admin_Console")
        self.assertEqual(admin, admin_console)
        self.assertEqual(admin[-1], "Error_Log__c")
        for tool in ("Find", "Import", "Bulk_Update"):
            self.assertNotIn(tool, admin, f"{tool} opens from its Data Manager card (D-135)")


if __name__ == "__main__":
    unittest.main()
