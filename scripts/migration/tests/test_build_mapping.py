"""Tests for build_mapping.py. Run: python3 -m unittest discover scripts/migration/tests"""

import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import build_mapping  # noqa: E402

FIELD = """<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>{name}</fullName>
  {extra}
  <type>{type}</type>
</CustomField>
"""
OBJECT = """<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  {extra}
</CustomObject>
"""
AUTO_NAME = "<nameField><label>Number</label><type>AutoNumber</type></nameField>"
TEXT_NAME = "<nameField><label>Name</label><type>Text</type></nameField>"


class FixtureRepo:
    """A throwaway packages/ tree with only the files a test names."""

    def __init__(self):
        self.root = tempfile.mkdtemp()

    def obj(self, package, name, extra=""):
        folder = os.path.join(self.root, "packages", package, "main", "default", "objects", name)
        os.makedirs(os.path.join(folder, "fields"), exist_ok=True)
        if name.endswith("__c"):
            with open(os.path.join(folder, name + ".object-meta.xml"), "w") as handle:
                handle.write(OBJECT.format(extra=extra))
        return folder

    def field(self, package, obj, name, type_, extra=""):
        folder = self.obj(package, obj) if not os.path.isdir(self._dir(package, obj)) else self._dir(package, obj)
        with open(os.path.join(folder, "fields", name + ".field-meta.xml"), "w") as handle:
            handle.write(FIELD.format(name=name, type=type_, extra=extra))

    def record_type(self, package, obj, name):
        folder = os.path.join(self._dir(package, obj), "recordTypes")
        os.makedirs(folder, exist_ok=True)
        open(os.path.join(folder, name + ".recordType-meta.xml"), "w").close()

    def _dir(self, package, obj):
        return os.path.join(self.root, "packages", package, "main", "default", "objects", obj)

    def lookup(self, package, obj, name, target, required=False, master=False):
        extra = f"<referenceTo>{target}</referenceTo><required>{str(required).lower()}</required>"
        self.field(package, obj, name, "MasterDetail" if master else "Lookup", extra)

    def cleanup(self):
        shutil.rmtree(self.root)


class BuildMappingTest(unittest.TestCase):
    def setUp(self):
        self.repo = FixtureRepo()
        self.addCleanup(self.repo.cleanup)

    def build(self, packages=("core",), overrides=None):
        return build_mapping.build(list(packages), overrides or {}, repo=self.repo.root)

    def entry(self, mapping, name):
        return next(o for o in mapping["objects"] if o["name"] == name)

    def test_formula_and_auto_number_fields_are_left_out(self):
        self.repo.obj("core", "Thing__c", TEXT_NAME)
        self.repo.field("core", "Thing__c", "Amount__c", "Currency")
        self.repo.field("core", "Thing__c", "Doubled__c", "Currency", "<formula>Amount__c * 2</formula>")
        self.repo.field("core", "Thing__c", "Number__c", "AutoNumber")
        entry = self.entry(self.build(), "Thing__c")
        self.assertEqual([f["name"] for f in entry["fields"]], ["Amount__c"])
        self.assertEqual(entry["name_field"], "text")
        self.assertTrue(entry["owner"])

    def test_metadata_types_and_events_hold_no_records(self):
        self.repo.obj("core", "Shipped__mdt")
        self.repo.obj("core", "Happened__e")
        self.repo.obj("core", "Thing__c", AUTO_NAME)
        self.assertEqual([o["name"] for o in self.build()["objects"]], ["Thing__c"])

    def test_parent_loads_before_child_and_master_detail_child_has_no_owner(self):
        self.repo.obj("core", "Aa_Child__c", AUTO_NAME)
        self.repo.obj("core", "Zz_Parent__c", TEXT_NAME)
        self.repo.lookup("core", "Aa_Child__c", "Parent__c", "Zz_Parent__c", master=True)
        mapping = self.build()
        self.assertEqual([o["name"] for o in mapping["objects"]], ["Zz_Parent__c", "Aa_Child__c"])
        self.assertFalse(self.entry(mapping, "Aa_Child__c")["owner"])

    def test_a_cycle_of_optional_lookups_is_broken_and_required_edges_hold(self):
        self.repo.obj("core", "Aa__c", AUTO_NAME)
        self.repo.obj("core", "Bb__c", AUTO_NAME)
        self.repo.lookup("core", "Aa__c", "Bb__c", "Bb__c")
        self.repo.lookup("core", "Bb__c", "Aa__c", "Aa__c", required=True)
        self.assertEqual([o["name"] for o in self.build()["objects"]], ["Aa__c", "Bb__c"])

    def test_a_cycle_of_required_lookups_stops_the_build(self):
        self.repo.obj("core", "Aa__c", AUTO_NAME)
        self.repo.obj("core", "Bb__c", AUTO_NAME)
        self.repo.lookup("core", "Aa__c", "Bb__c", "Bb__c", required=True)
        self.repo.lookup("core", "Bb__c", "Aa__c", "Aa__c", required=True)
        with self.assertRaises(SystemExit):
            self.build()

    def test_self_lookup_is_not_an_edge(self):
        self.repo.obj("core", "Aa__c", AUTO_NAME)
        self.repo.lookup("core", "Aa__c", "Parent__c", "Aa__c")
        self.assertEqual([o["name"] for o in self.build()["objects"]], ["Aa__c"])

    def test_standard_objects_come_first_with_fields_from_every_package_and_record_types(self):
        self.repo.obj("core", "Thing__c", AUTO_NAME)
        self.repo.field("core", "Account", "Greeting__c", "Text")
        self.repo.record_type("core", "Account", "Household")
        self.repo.field("giving", "Account", "Total__c", "Currency")
        self.repo.field("mirror", "Thing__c", "Link_Id__c", "Text")
        mapping = self.build(("core", "giving", "mirror"))
        self.assertEqual([o["name"] for o in mapping["objects"]], ["Account", "Thing__c"])
        account = self.entry(mapping, "Account")
        self.assertEqual([f["name"] for f in account["fields"]], ["Greeting__c", "Total__c"])
        self.assertEqual(account["record_types"], ["Household"])
        self.assertFalse(account["owner"])
        self.assertEqual(self.entry(mapping, "Thing__c")["package"], "core")
        self.assertEqual([f["name"] for f in self.entry(mapping, "Thing__c")["fields"]], ["Link_Id__c"])

    def test_hierarchy_settings_are_listed_not_loaded(self):
        self.repo.obj("core", "Org_Settings__c", "<customSettingsType>Hierarchy</customSettingsType>")
        self.repo.field("core", "Org_Settings__c", "On__c", "Checkbox")
        mapping = self.build()
        self.assertEqual(mapping["objects"], [])
        self.assertEqual([s["name"] for s in mapping["settings"]], ["Org_Settings__c"])

    def test_skip_and_upsert_overrides(self):
        self.repo.obj("core", "Staged__c", AUTO_NAME)
        self.repo.obj("core", "Switch__c", TEXT_NAME)
        unique = "<externalId>true</externalId><unique>true</unique>"
        self.repo.field("core", "Switch__c", "Key__c", "Text", unique)
        mapping = self.build(overrides={"skip": {"Staged__c": "why"}, "upsert_keys": {"Switch__c": "Key__c"}})
        self.assertEqual(mapping["skipped"], [{"name": "Staged__c", "reason": "why"}])
        self.assertEqual(self.entry(mapping, "Switch__c")["upsert_key"], "Key__c")

    def test_an_upsert_key_must_be_a_unique_external_id(self):
        self.repo.obj("core", "Switch__c", TEXT_NAME)
        self.repo.field("core", "Switch__c", "Key__c", "Text")
        with self.assertRaises(SystemExit):
            self.build(overrides={"upsert_keys": {"Switch__c": "Key__c"}})


class RealSourceTest(unittest.TestCase):
    """The shipped overrides against the real package source."""

    def setUp(self):
        with open(os.path.join(build_mapping.HERE, "overrides.json"), encoding="utf-8") as handle:
            self.overrides = json.load(handle)
        self.mapping = build_mapping.build(["core", "rollups", "giving", "mirror"], self.overrides)

    def test_every_override_names_a_real_object(self):
        names = {o["name"] for o in self.mapping["objects"]} | {s["name"] for s in self.mapping["skipped"]}
        for name in list(self.overrides["skip"]) + list(self.overrides["upsert_keys"]):
            self.assertIn(name, names)

    def test_upsert_keys_are_applied(self):
        keyed = {o["name"]: o.get("upsert_key") for o in self.mapping["objects"]}
        for name, key in self.overrides["upsert_keys"].items():
            self.assertEqual(keyed[name], key)

    def test_no_name_carries_a_namespace(self):
        text = json.dumps(self.mapping)
        for entry in self.mapping["objects"]:
            for field in entry["fields"]:
                self.assertEqual(field["name"].count("__"), 1, field["name"])
        self.assertNotIn("barncrm__", text.lower())

    def test_every_required_parent_loads_first(self):
        position = {o["name"]: i for i, o in enumerate(self.mapping["objects"])}
        for entry in self.mapping["objects"]:
            for field in entry["fields"]:
                target = field.get("reference_to")
                if field.get("required") and target in position and target != entry["name"]:
                    self.assertLess(position[target], position[entry["name"]], f"{entry['name']}.{field['name']}")

    def test_main_writes_the_mapping(self):
        out = os.path.join(tempfile.mkdtemp(), "mapping.json")
        self.addCleanup(shutil.rmtree, os.path.dirname(out))
        with open(os.devnull, "w") as devnull:
            stdout, sys.stdout = sys.stdout, devnull
            try:
                self.assertEqual(build_mapping.main(["--packages", "core", "--output", out]), 0)
            finally:
                sys.stdout = stdout
        with open(out, encoding="utf-8") as handle:
            self.assertEqual(json.load(handle)["packages"], ["core"])


if __name__ == "__main__":
    unittest.main()
