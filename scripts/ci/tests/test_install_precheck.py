"""install-precheck.py: edition and name checks, with its sf calls replaced by canned answers."""

import importlib.util
import os
import unittest
from contextlib import redirect_stdout
from io import StringIO

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.abspath(os.path.join(HERE, "..", "..", "org", "install-precheck.py"))
_spec = importlib.util.spec_from_file_location("install_precheck", SCRIPT)
precheck = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(precheck)

OURS = {
    ("CustomObject", "Address__c"),
    ("CustomField", "Contact.Deceased__c"),
    ("CustomField", "Gift__c.Amount__c"),
    ("ApexClass", "GiftService"),
}


class PrecheckTest(unittest.TestCase):
    def run_check(self, answers):
        def fake_sf(alias, *args):
            key = " ".join(args)
            for prefix, value in answers.items():
                if key.startswith(prefix):
                    return value
            return []

        original = precheck.sf
        precheck.sf = fake_sf
        try:
            buffer = StringIO()
            with redirect_stdout(buffer):
                report = precheck.Report()
                edition = precheck.check_edition("org", report)
                precheck.check_names("org", report, OURS, edition)
            return report, buffer.getvalue()
        finally:
            precheck.sf = original

    def test_professional_edition_and_collisions_fail(self):
        report, text = self.run_check({
            "data query --query SELECT OrganizationType": {"records": [
                {"OrganizationType": "Professional Edition", "IsSandbox": False}]},
            "org list metadata --metadata-type CustomObject": [{"fullName": "Address__c"}],
            "org list metadata --metadata-type CustomField": [
                {"fullName": "Contact.Deceased__c"}, {"fullName": "Gift__c.Amount__c"},
                {"fullName": "Contact.Other__c", "namespacePrefix": "npsp"}],
        })
        self.assertIn("FAIL  Edition: Professional Edition", text)
        self.assertIn("1 CustomObject name(s)", text)
        self.assertIn("Contact.Deceased__c", text)
        self.assertNotIn("Gift__c.Amount__c", text, "a BarnCRM object's field is covered by the object")
        self.assertEqual(report.counts["FAIL"], 3)

    def test_an_earlier_install_warns_once(self):
        report, text = self.run_check({
            "data query --query SELECT OrganizationType": {"records": [
                {"OrganizationType": "Enterprise Edition", "IsSandbox": True}]},
            "org list metadata --metadata-type CustomObject": [
                {"fullName": "Address__c"}, {"fullName": "BarnCRM_Settings__c"}],
            "org list metadata --metadata-type ApexClass": [{"fullName": "GiftService"}],
        })
        self.assertEqual(report.counts["FAIL"], 0, text)
        self.assertEqual(text.count("WARN  Names"), 1, text)

    def test_clean_enterprise_org_passes(self):
        report, text = self.run_check({
            "data query --query SELECT OrganizationType": {"records": [
                {"OrganizationType": "Enterprise Edition", "IsSandbox": True}]},
        })
        self.assertEqual(report.counts["FAIL"], 0, text)
        self.assertIn("PASS  Names", text)


if __name__ == "__main__":
    unittest.main()
