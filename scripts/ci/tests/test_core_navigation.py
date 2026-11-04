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


def tab_motifs():
    """{tab name: (package, motif number)} for every BarnCRM tab."""
    found = {}
    for path in glob.glob(os.path.join(ROOT, "packages", "*", "main", "default", "tabs", "*.tab-meta.xml")):
        package = os.path.relpath(path, os.path.join(ROOT, "packages")).split(os.sep)[0]
        motif = ET.parse(path).getroot().findtext("m:motif", namespaces=NS) or ""
        match = re.match(r"Custom(\d+):", motif.strip())
        if match:
            found[os.path.basename(path).replace(".tab-meta.xml", "")] = (package, int(match.group(1)))
    return found


# Cards built before the icon rule that still borrow another package's tab motif (vis-modules-6,
# vis-core-4). The rollout removes each entry as the card takes its own tab's icon; never add one.
BORROWED_CARD_ICONS = {
    "grantAnswerLibrary",
    "grantOutcomes",
    "grantReport",
    "donorLevels",
    "donorSegments",
    "giftBatchEntry",
    "giftSoftCredits",
    "cohortMembers",
    "programRoster",
    "serviceDeliveryLog",
    "servicePlan",
    "shiftSignups",
    "volunteerHoursApproval",
    "volunteerSuggestions",
}


class IconRegistry(unittest.TestCase):
    """c/barnIcons maps every tab to its own motif, and a card never wears another package's."""

    def test_registry_lists_every_tab_with_its_motif(self):
        path = os.path.join(CORE, "lwc", "barnIcons", "barnIcons.js")
        with open(path, encoding="utf-8") as handle:
            entries = dict(re.findall(r"^\s+(\w+): '(\w+:\w+)',?$", handle.read(), re.M))
        tabs = tab_motifs()
        for name, (_, number) in tabs.items():
            self.assertEqual(entries.get(name), f"custom:custom{number}", f"barnIcons.js: {name}")
        for name, icon in entries.items():
            if icon.startswith("custom:"):
                self.assertIn(name, tabs, f"barnIcons.js: {name} names no tab")

    def test_card_icons_are_their_own_packages_tab_motifs(self):
        owner = {number: package for package, number in tab_motifs().values()}
        pattern = os.path.join(ROOT, "packages", "*", "main", "default", "lwc", "*", "*.html")
        for path in sorted(glob.glob(pattern)):
            package = os.path.relpath(path, os.path.join(ROOT, "packages")).split(os.sep)[0]
            component = os.path.basename(os.path.dirname(path))
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            for tag in re.finditer(r"<(lightning-card|c-barn-page-shell)\b([^>]*)>", text, re.S):
                icon = re.search(r'icon-name\s*=\s*"custom:custom(\d+)"', tag.group(2))
                if not icon or component in BORROWED_CARD_ICONS:
                    continue
                number = int(icon.group(1))
                self.assertEqual(
                    owner.get(number),
                    package,
                    f"{component}: Custom{number} is not a {package} tab's icon; use c/barnIcons",
                )


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
