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
        for path in sorted(glob.glob(os.path.join(CORE, "tabs", "*.tab-meta.xml"))):
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
