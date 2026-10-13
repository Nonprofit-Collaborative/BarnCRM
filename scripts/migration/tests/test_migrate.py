"""Tests for migrate.py against a fake org. Run: python3 -m unittest discover -s scripts/migration/tests"""

import csv
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import migrate  # noqa: E402


def sid(prefix, n):
    """An 18 character source-style Id."""
    return f"{prefix}{n:012d}AAA"


MAPPING = {
    "objects": [
        {"name": "Account", "kind": "standard", "name_field": None, "owner": False, "record_types": ["Household"],
         "fields": [{"name": "Level__c", "type": "Lookup", "reference_to": "Level__c", "required": False},
                    {"name": "Greeting__c", "type": "Text"}]},
        {"name": "Fund__c", "kind": "custom", "name_field": "text", "owner": True, "record_types": [],
         "upsert_key": "Code__c",
         "fields": [{"name": "Code__c", "type": "Text", "unique_key": True},
                    {"name": "Active__c", "type": "Checkbox"}]},
        {"name": "Gift__c", "kind": "custom", "name_field": "auto", "owner": True, "record_types": [],
         "fields": [{"name": "Donor__c", "type": "Lookup", "reference_to": "Account", "required": True},
                    {"name": "Fund__c", "type": "Lookup", "reference_to": "Fund__c", "required": True},
                    {"name": "Amount__c", "type": "Currency"},
                    {"name": "Original__c", "type": "Lookup", "reference_to": "Gift__c", "required": False},
                    {"name": "Level_Id__c", "type": "Text"}]},
        {"name": "Level__c", "kind": "custom", "name_field": "text", "owner": True, "record_types": [],
         "fields": []},
    ],
    "settings": [{"name": "Org_Settings__c", "kind": "setting", "fields": [{"name": "On__c", "type": "Checkbox"}]}],
    "related": [{"object": "Task", "link_field": "WhatId", "fields": ["Subject"]}],
    "skipped": [],
}


class FakeOrg:
    """Records rest calls and answers like the sObject Collections API."""

    def __init__(self, refuse=()):
        self.calls, self.refuse, self.count = [], set(refuse), 0
        self.exports = {}
        self.query_results = {}

    def describe(self, sobject):
        return {"Name": {"createable": True}}

    def export(self, query, path):
        rows = self.exports.get(query.split(" FROM ")[1], [])
        if rows:
            with open(path, "w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
        return rows

    def query(self, query):
        if query.startswith("SELECT Id, DeveloperName"):
            return [{"Id": "012NEW000000001AAA", "DeveloperName": "Household", "SobjectType": "Account"}]
        for key, rows in self.query_results.items():
            if key in query:
                return rows
        return []

    def rest(self, method, path, body):
        self.calls.append((method, path, body))
        results = []
        for record in body["records"]:
            name = record.get("Name") or record.get("Subject") or record.get("ns__Amount__c")
            if name in self.refuse:
                results.append({"success": False, "errors": [{"message": "refused by rule"}]})
                continue
            self.count += 1
            results.append({"success": True, "id": record.get("Id") or f"a0NEW{self.count:010d}AAA"})
        return results


class KitTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.folder)
        self.account = sid("001", 1)
        self.level = sid("a03", 1)
        self.fund = sid("a01", 1)
        self.write("Account", [{"Id": self.account, "RecordType.DeveloperName": "Household",
                                "Level__c": self.level, "Greeting__c": "Hi"},
                               {"Id": sid("001", 2), "RecordType.DeveloperName": "", "Level__c": "",
                                "Greeting__c": ""}])
        self.write("Fund__c", [{"Id": self.fund, "Name": "General", "OwnerId": sid("005", 1), "Code__c": "GEN",
                                "Active__c": "true"}])
        self.write("Level__c", [{"Id": self.level, "Name": "Gold", "OwnerId": sid("005", 1)}])
        self.write("Task", [{"Id": sid("00T", 1), "WhatId": sid("a02", 1), "Subject": "Thank"}])

    def write(self, name, rows):
        with open(os.path.join(self.folder, name + ".csv"), "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)

    def gifts(self, count):
        rows = []
        for n in range(1, count + 1):
            rows.append({"Id": sid("a02", n), "OwnerId": sid("005", 1), "Donor__c": self.account,
                         "Fund__c": self.fund, "Amount__c": str(n), "Original__c": sid("a02", 1) if n > 1 else "",
                         "Level_Id__c": self.level})
        self.write("Gift__c", rows)

    def kit(self, org):
        return migrate.Kit(org, MAPPING, "ns", self.folder)

    def sent(self, org, method, path_part):
        return [r for m, p, b in org.calls if m == method and path_part in p for r in b["records"]]

    def test_names_take_the_namespace_only_when_packaged(self):
        self.assertEqual(migrate.ns("Gift__c", "ns"), "ns__Gift__c")
        self.assertEqual(migrate.ns("Gift__c", ""), "Gift__c")
        self.assertEqual(migrate.ns("Name", "ns"), "Name")
        self.assertEqual(migrate.ns("other__Thing__c", "ns"), "other__Thing__c")
        self.assertEqual(migrate.strip_ns("ns__Gift__c", "ns"), "Gift__c")

    def test_two_hundred_and_one_gifts_load_in_two_calls_with_every_id_translated(self):
        self.gifts(201)
        org = FakeOrg()
        summary = self.kit(org).reimport()
        self.assertEqual(summary["Gift__c"], (201, 0))
        inserts = [c for c in org.calls if c[0] == "POST" and c[2]["records"][0]["attributes"]["type"] == "ns__Gift__c"]
        self.assertEqual([len(c[2]["records"]) for c in inserts], [200, 1])
        id_map = self.kit(org).load_id_map()
        first = inserts[0][2]["records"][0]
        self.assertEqual(first["ns__Donor__c"], self.account)  # Accounts keep their Ids
        self.assertEqual(first["ns__Fund__c"], id_map[self.fund[:15]])
        self.assertIsNone(first["ns__Level_Id__c"])  # Level loads later: pass two fills it
        self.assertEqual(first["ns__Amount__c"], 1.0)
        self.assertEqual(first["OwnerId"], sid("005", 1))
        self.assertNotIn("Name", first)  # auto-numbered

    def test_pass_two_fills_lookups_to_records_loaded_later_and_self_lookups(self):
        self.gifts(3)
        org = FakeOrg()
        self.kit(org).reimport()
        id_map = self.kit(org).load_id_map()
        updates = self.sent(org, "PATCH", "composite/sobjects")
        gift_updates = [u for u in updates if u["attributes"]["type"] == "ns__Gift__c"]
        self.assertEqual(len(gift_updates), 3)
        self.assertTrue(all(u["ns__Level_Id__c"] == id_map[self.level[:15]] for u in gift_updates))
        self.assertEqual(sum(1 for u in gift_updates if u.get("ns__Original__c") == id_map[sid("a02", 1)[:15]]), 2)
        account = [u for u in updates if u["attributes"]["type"] == "Account" and "ns__Level__c" in u and u["ns__Level__c"]]
        self.assertEqual(account[0]["ns__Level__c"], id_map[self.level[:15]])

    def test_accounts_are_updated_in_place_with_record_type_by_name_and_empty_rows_skipped(self):
        self.gifts(1)
        org = FakeOrg()
        self.kit(org).reimport()
        first_pass = [r for m, p, b in org.calls[:1] for r in b["records"]]
        self.assertEqual(len(first_pass), 1)
        self.assertEqual(first_pass[0]["Id"], self.account)
        self.assertEqual(first_pass[0]["RecordTypeId"], "012NEW000000001AAA")
        self.assertEqual(first_pass[0]["ns__Greeting__c"], "Hi")

    def test_a_keyed_object_is_upserted_on_its_key(self):
        self.gifts(1)
        org = FakeOrg()
        self.kit(org).reimport()
        upserts = [c for c in org.calls if c[1].endswith("composite/sobjects/ns__Fund__c/ns__Code__c")]
        self.assertEqual(len(upserts), 1)
        self.assertIs(upserts[0][2]["records"][0]["ns__Active__c"], True)

    def test_refused_records_are_listed_and_a_rerun_loads_only_them(self):
        self.gifts(3)
        org = FakeOrg(refuse={2.0})
        summary = self.kit(org).reimport()
        self.assertEqual(summary["Gift__c"], (2, 1))
        with open(os.path.join(self.folder, "refused.csv")) as handle:
            refused = list(csv.DictReader(handle))
        self.assertEqual([(r["object"], r["source_id"]) for r in refused], [("Gift__c", sid("a02", 2))])
        rerun = FakeOrg()
        summary = self.kit(rerun).reimport()
        self.assertEqual(summary["Gift__c"], (1, 0))
        self.assertEqual(summary["Fund__c"], (0, 0))
        self.assertEqual(summary["Task"], (0, 0))  # loaded by the first run

    def test_a_rerun_fills_a_lookup_to_a_record_the_first_run_refused(self):
        self.gifts(3)
        self.kit(FakeOrg(refuse={1.0})).reimport()
        rerun = FakeOrg()
        self.kit(rerun).reimport()
        id_map = self.kit(rerun).load_id_map()
        updates = [u for u in self.sent(rerun, "PATCH", "composite/sobjects")
                   if u["attributes"]["type"] == "ns__Gift__c" and u.get("ns__Original__c")]
        self.assertEqual({u["ns__Original__c"] for u in updates}, {id_map[sid("a02", 1)[:15]]})
        self.assertEqual(len(updates), 2)

    def test_related_tasks_follow_their_record_and_orphans_are_refused(self):
        self.gifts(1)
        self.write("Task", [{"Id": sid("00T", 1), "WhatId": sid("a02", 1), "Subject": "Thank"},
                            {"Id": sid("00T", 2), "WhatId": sid("a02", 9), "Subject": "Lost"}])
        org = FakeOrg()
        summary = self.kit(org).reimport()
        self.assertEqual(summary["Task"], (1, 0))
        task = [r for m, p, b in org.calls for r in b["records"] if r["attributes"]["type"] == "Task"][0]
        self.assertEqual(task["WhatId"], self.kit(org).load_id_map()[sid("a02", 1)[:15]])
        with open(os.path.join(self.folder, "refused.csv")) as handle:
            self.assertIn(sid("00T", 2), handle.read())

    def test_audit_fields_are_sent_only_when_asked(self):
        rows = [{"Id": sid("a02", 1), "OwnerId": "", "Donor__c": self.account, "Fund__c": self.fund,
                 "Amount__c": "5", "Original__c": "", "Level_Id__c": "", "CreatedDate": "2020-01-01T00:00:00.000Z"}]
        self.write("Gift__c", rows)
        org = FakeOrg()
        self.kit(org).reimport(keep_audit=True)
        gift = [r for r in self.sent(org, "POST", "composite") if r["attributes"]["type"] == "ns__Gift__c"][0]
        self.assertEqual(gift["CreatedDate"], "2020-01-01T00:00:00.000Z")

    def test_export_strips_the_namespace_sorts_by_creation_and_lists_settings(self):
        org = FakeOrg()
        org.exports["ns__Fund__c"] = [
            {"Id": sid("a01", 2), "Name": "B", "OwnerId": "", "ns__Code__c": "B", "ns__Active__c": "false",
             "CreatedDate": "2021-01-01T00:00:00.000Z", "CreatedById": "", "LastModifiedDate": "", "LastModifiedById": ""},
            {"Id": sid("a01", 1), "Name": "A", "OwnerId": "", "ns__Code__c": "A", "ns__Active__c": "true",
             "CreatedDate": "2020-01-01T00:00:00.000Z", "CreatedById": "", "LastModifiedDate": "", "LastModifiedById": ""},
        ]
        org.query_results["ns__Org_Settings__c"] = [{"SetupOwnerId": "00D000000000001AAA", "ns__On__c": True}]
        out = os.path.join(self.folder, "out")
        counts = migrate.Kit(org, MAPPING, "ns", out).export()
        self.assertEqual(counts["Fund__c"], 2)
        with open(os.path.join(out, "Fund__c.csv")) as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual([r["Code__c"] for r in rows], ["A", "B"])
        with open(os.path.join(out, "settings.csv")) as handle:
            self.assertEqual(list(csv.DictReader(handle))[0]["field"], "On__c")

    def test_an_unreadable_setting_is_noted_not_fatal(self):
        org = FakeOrg()

        def refuse(query):
            raise SystemExit("not visible")

        org.query = refuse
        kit = migrate.Kit(org, dict(MAPPING, related=[]), "ns", os.path.join(self.folder, "x"))
        kit.export_settings()
        with open(kit.path("settings.csv")) as handle:
            self.assertIn("not readable", handle.read())

    def test_verify_compares_through_the_id_map(self):
        self.gifts(2)
        org = FakeOrg()
        kit = self.kit(org)
        kit.reimport()
        id_map = kit.load_id_map()
        new = {k: v for k, v in id_map.items()}
        org.exports["ns__Gift__c"] = [
            {"Id": new[sid("a02", 1)[:15]], "OwnerId": sid("005", 1), "ns__Donor__c": self.account,
             "ns__Fund__c": new[self.fund[:15]], "ns__Amount__c": "1.0", "ns__Original__c": "",
             "ns__Level_Id__c": new[self.level[:15]], "CreatedDate": "1"},
            {"Id": new[sid("a02", 2)[:15]], "OwnerId": sid("005", 1), "ns__Donor__c": self.account,
             "ns__Fund__c": new[self.fund[:15]], "ns__Amount__c": "3", "ns__Original__c": new[sid("a02", 1)[:15]],
             "ns__Level_Id__c": new[self.level[:15]], "CreatedDate": "2"},
        ]
        differences = kit.verify()
        gift = [d for d in differences if d["object"] == "Gift__c"]
        self.assertEqual([(d["source_id"], d["field"]) for d in gift], [(sid("a02", 2), "Amount__c")])
        self.assertTrue(any(d["object"] == "Fund__c" and d["found"] == "nothing" for d in differences))

    def test_check_names_fields_the_user_cannot_see(self):
        problems = self.kit(FakeOrg()).check()
        self.assertIn("ns__Gift__c.ns__Amount__c: not visible to this user", problems)
        self.assertIn("Account.RecordTypeId: not visible to this user", problems)

    def test_main_reports_refusals_with_a_failing_exit(self):
        self.gifts(1)
        mapping_path = os.path.join(self.folder, "mapping.json")
        with open(mapping_path, "w") as handle:
            import json
            json.dump(MAPPING, handle)
        with open(os.devnull, "w") as devnull:
            stdout, sys.stdout = sys.stdout, devnull
            try:
                code = migrate.main(["reimport", "--org", "x", "--mapping", mapping_path, "--namespace", "ns",
                                     "--in", self.folder], sf_factory=lambda org: FakeOrg(refuse={1.0}))
            finally:
                sys.stdout = stdout
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
