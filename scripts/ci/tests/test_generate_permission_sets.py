import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "gps", os.path.join(HERE, "..", "..", "permission-sets", "generate.py")
)
gps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gps)

STAFF = {
    "objectPermissions": {
        "Grant__c": {
            "allowCreate": "true",
            "allowDelete": "false",
            "allowEdit": "true",
            "allowRead": "true",
            "modifyAllRecords": "false",
            "object": "Grant__c",
            "viewAllRecords": "false",
        }
    },
    "fieldPermissions": {
        "Grant__c.Stage__c": {"editable": "true", "field": "Grant__c.Stage__c", "readable": "true"}
    },
    "classAccesses": {
        "BController": {"apexClass": "BController", "enabled": "true"},
        "DController": {"apexClass": "DController", "enabled": "true"},
    },
}


class GeneratePermissionSetsTest(unittest.TestCase):
    def test_read_only_rule_takes_away_writes(self):
        sections = gps.derive(STAFF, {"readOnly": True})
        grant = sections["objectPermissions"]["Grant__c"]
        self.assertEqual(grant["allowCreate"], "false")
        self.assertEqual(grant["allowEdit"], "false")
        self.assertEqual(grant["allowRead"], "true")
        self.assertEqual(sections["fieldPermissions"]["Grant__c.Stage__c"]["editable"], "false")

    def test_delta_sets_adds_and_removes(self):
        sections = gps.derive(
            STAFF,
            {
                "set": {"objectPermissions": {"Grant__c": {"allowDelete": "true"}}},
                "add": {"classAccesses": {"CController": {"enabled": "true"}}},
                "remove": {"fieldPermissions": ["Grant__c.Stage__c"]},
            },
        )
        self.assertEqual(sections["objectPermissions"]["Grant__c"]["allowDelete"], "true")
        self.assertEqual(list(sections["classAccesses"]), ["BController", "CController", "DController"])
        self.assertNotIn("fieldPermissions", sections)
        self.assertEqual(STAFF["objectPermissions"]["Grant__c"]["allowDelete"], "false")

    def test_bootstrap_reproduces_the_set(self):
        derived = gps.derive(
            STAFF,
            {
                "readOnly": True,
                "set": {"fieldPermissions": {"Grant__c.Stage__c": {"editable": "true"}}},
                "remove": {"classAccesses": ["DController"]},
            },
        )
        delta = gps.bootstrap(STAFF, {"label": "Read Only"}, derived, True)
        self.assertEqual(gps.derive(STAFF, delta), derived)

    def test_render_keeps_a_wrapped_description(self):
        text = gps.render({"label": "X", "description": ["One line,", "and another."]}, {})
        self.assertIn("  <description>\n    One line,\n    and another.\n  </description>\n", text)


if __name__ == "__main__":
    unittest.main()
