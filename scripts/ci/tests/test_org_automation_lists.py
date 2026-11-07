"""The Automation tab's inventory names BarnCRM's own flows and its triggers that skip the
dispatcher by API name (C-60, D-184), because with no namespace nothing else tells them from an
org's own. These tests keep both lists in OrgAutomationInventory.cls in step with the packages.
"""
import glob
import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SERVICE = os.path.join(ROOT, "packages", "core", "main", "default", "classes", "OrgAutomationInventory.cls")


def listed(name):
    source = open(SERVICE, encoding="utf-8").read()
    block = re.search(name + r" = new Set<String>\{(.*?)\};", source, re.S)
    return set(re.findall(r"'([^']+)'", block.group(1)))


class OrgAutomationLists(unittest.TestCase):
    def test_barn_flows_match_the_packaged_flows(self):
        shipped = {
            os.path.basename(path).split(".")[0]
            for path in glob.glob(os.path.join(ROOT, "packages", "*", "main", "default", "flows", "*.flow-meta.xml"))
        }
        self.assertEqual(listed("BARN_FLOWS"), shipped)

    def test_barn_event_triggers_match_the_triggers_that_skip_the_dispatcher(self):
        skipping = set()
        for path in glob.glob(os.path.join(ROOT, "packages", "*", "main", "default", "triggers", "*.trigger")):
            with open(path, encoding="utf-8") as handle:
                if "TriggerDispatcher.run(" not in handle.read():
                    skipping.add(os.path.basename(path).split(".")[0])
        self.assertEqual(listed("BARN_EVENT_TRIGGERS"), skipping)


if __name__ == "__main__":
    unittest.main()
