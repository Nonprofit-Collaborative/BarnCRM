import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cfr", os.path.join(HERE, "..", "check-field-references.py"))
cfr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cfr)

INDEX = cfr.Index(
    {
        "Integration_App__mdt": {"Link_Url__c", "Status__c"},
        "Gift__c": {"Amount__c", "Donor__c", "Appeal__c"},
        "Gift_Allocation__c": {"Gift__c", "Amount__c"},
        "Appeal__c": set(),
        "Contact": {"Household__c"},
        "Merge_Ready__e": {"Survivor_Id__c"},
    },
    relationships={"Gift_Allocations__r"},
    other_names={"Shared_With_Find_Users__c", "Gifts__c"},
)


def refs(rel, text):
    return [token for (_, token) in cfr.file_refs(INDEX, rel, text)]


CLS = "packages/core/main/default/classes/X.cls"


class Apex(unittest.TestCase):
    def test_removed_field_in_select_is_found(self):
        # The original bug: #681 selected a field #666 had removed.
        source = "List<Integration_App__mdt> rows = [\n  SELECT DeveloperName, Link_Url__c,\n    Install_Url__c\n  FROM Integration_App__mdt\n];"
        self.assertEqual(cfr.file_refs(INDEX, CLS, source), [(3, "Integration_App__mdt.Install_Url__c")])

    def test_select_of_existing_fields_passes(self):
        self.assertEqual(refs(CLS, "x = [SELECT Id, Link_Url__c, Status__c FROM Integration_App__mdt];"), [])

    def test_field_on_another_repo_object_is_wrong_in_scoped_query(self):
        self.assertEqual(refs(CLS, "x = [SELECT Household__c FROM Gift__c];"), ["Gift__c.Household__c"])

    def test_subquery_is_checked_against_its_own_from(self):
        source = "x = [SELECT Amount__c, (SELECT Amount__c, Bogus__c FROM Gift_Allocations__r) FROM Gift__c WHERE Donor__c IN (SELECT Id FROM Contact)];"
        self.assertEqual(refs(CLS, source), ["Bogus__c"])

    def test_relationship_paths(self):
        self.assertEqual(refs(CLS, "x = [SELECT Donor__r.Name, Gone__r.Name FROM Gift__c];"), ["Gift__c.Gone__r"])

    def test_qualified_token_on_repo_object(self):
        self.assertEqual(refs(CLS, "Schema.SObjectField f = Gift__c.Removed__c;"), ["Gift__c.Removed__c"])
        self.assertEqual(refs(CLS, "Schema.SObjectField f = Contact.Household__c;"), [])

    def test_variable_field_must_exist_somewhere(self):
        self.assertEqual(refs(CLS, "Decimal a = gift.Amount__c + gift.Removed__c;"), ["Removed__c"])

    def test_comments_and_strings_are_not_references(self):
        source = "// Removed__c was dropped\n/* Old__c */ String s = 'Gone__c'; Object v = r.get('Gone__c');"
        self.assertEqual(refs(CLS, source), [])

    def test_namespaced_and_foreign_objects_are_skipped(self):
        source = (
            "x = [SELECT npsp__Foo__c FROM Opportunity];\n"
            "y = [SELECT Org_Field__c FROM GiftTransaction];\n"
            "Schema.SObjectField f = GiftTransaction.Org_Field__c;\n"
            "Object z = GW_Volunteers__Volunteer_Job__c.SObjectType;"
        )
        self.assertEqual(refs(CLS, source), [])

    def test_unknown_custom_object_metadata_type_and_event(self):
        source = "x = [SELECT Id FROM Removed_Object__c]; Gone__mdt.getAll(); new Gone__e(); new Merge_Ready__e();"
        self.assertEqual(refs(CLS, source), ["Removed_Object__c", "Gone__mdt", "Gone__e"])

    def test_sharing_reasons_and_child_relationships_are_defined(self):
        source = "String r = Schema.Gift__Share.RowCause.Shared_With_Find_Users__c; List<SObject> a = g.Gift_Allocations__r;"
        self.assertEqual(refs(CLS, source), [])


class Lwc(unittest.TestCase):
    JS = "packages/core/main/default/lwc/x/x.js"
    HTML = "packages/core/main/default/lwc/x/x.html"

    def test_schema_imports(self):
        source = (
            "import AMOUNT from '@salesforce/schema/Gift__c.Amount__c';\n"
            "import GONE from '@salesforce/schema/Gift__c.Gone__c';\n"
            "import OBJ from '@salesforce/schema/Removed__c';\n"
            "import NAME from '@salesforce/schema/Gift__c.Donor__r.Name';\n"
            "import STD from '@salesforce/schema/Account.Name';\n"
        )
        self.assertEqual(refs(self.JS, source), ["Gift__c.Gone__c", "Removed__c"])

    def test_qualified_strings_only(self):
        source = "const F = ['Gift__c.Amount__c', 'Gift__c.Gone__c', 'Free_Text__c'];\n// 'Gift__c.Old__c'\n"
        self.assertEqual(refs(self.JS, source), ["Gift__c.Gone__c"])

    def test_html_field_name(self):
        source = '<lightning-input-field field-name="Amount__c"></lightning-input-field><lightning-input-field field-name="Gone__c"></lightning-input-field><x field-name={f}></x>'
        self.assertEqual(refs(self.HTML, source), ["Gone__c"])

    def test_jest_tests_are_skipped(self):
        self.assertEqual(refs("packages/core/main/default/lwc/x/__tests__/x.test.js", "'Gift__c.Gone__c'"), [])


class Metadata(unittest.TestCase):
    def test_permission_set_field(self):
        source = "<PermissionSet><fieldPermissions><field>Gift__c.Amount__c</field></fieldPermissions><fieldPermissions><field>Integration_App__mdt.Install_Url__c</field></fieldPermissions></PermissionSet>"
        self.assertEqual(refs("packages/core/main/default/permissionsets/P.permissionset-meta.xml", source), ["Integration_App__mdt.Install_Url__c"])

    def test_prose_and_comments_are_skipped(self):
        source = "<Flow><description>Reads Gone__c</description><!-- Old__c --><label>Old__c</label><field>Amount__c</field></Flow>"
        self.assertEqual(refs("packages/core/main/default/flows/F.flow-meta.xml", source), [])

    def test_custom_metadata_record_fields_belong_to_its_type(self):
        source = (
            "<CustomMetadata><values><field>Link_Url__c</field><value>https://x</value></values>"
            "<values><field>Install_Url__c</field><value>Gone__c</value></values>"
            "<values><field>Amount__c</field><value/></values></CustomMetadata>"
        )
        rel = "packages/core/main/default/customMetadata/Integration_App.Foo.md-meta.xml"
        self.assertEqual(refs(rel, source), ["Integration_App__mdt.Install_Url__c", "Integration_App__mdt.Amount__c"])

    def test_report_type_and_child_relationship(self):
        source = "<Report><reportType>Gifts__c</reportType><field>Gift__c.Gift_Allocations__r$Amount__c</field></Report>"
        self.assertEqual(refs("packages/giving/main/default/reports/R/X.report-meta.xml", source), [])
        self.assertEqual(refs("packages/giving/main/default/reports/R/X.report-meta.xml", "<reportType>Gone__c</reportType>"), ["Gone__c"])


class IndexAndAllowlist(unittest.TestCase):
    def test_build_index_and_scan_with_allowlist(self):
        with tempfile.TemporaryDirectory() as root:
            fields = os.path.join(root, "core", "main", "default", "objects", "Gift__c", "fields")
            os.makedirs(fields)
            with open(os.path.join(fields, "Amount__c.field-meta.xml"), "w", encoding="utf-8") as handle:
                handle.write("<CustomField><fullName>Amount__c</fullName></CustomField>")
            with open(os.path.join(fields, "Donor__c.field-meta.xml"), "w", encoding="utf-8") as handle:
                handle.write("<CustomField><relationshipName>Gifts</relationshipName></CustomField>")
            index = cfr.build_index(root)
            self.assertTrue(index.object_has("Gift__c", "Amount__c"))
            self.assertTrue(index.known("Gifts__r"))
            self.assertFalse(index.known("Gone__c"))
            classes = os.path.join(root, "core", "main", "default", "classes")
            os.makedirs(classes)
            with open(os.path.join(classes, "A.cls"), "w", encoding="utf-8") as handle:
                handle.write("x = [SELECT Amount__c, Gone__c FROM Gift__c];")
            with open(os.path.join(classes, "A 2.cls"), "w", encoding="utf-8") as handle:
                handle.write("x = [SELECT Other__c FROM Gift__c];")
            found = cfr.scan(root, index)
            self.assertEqual(len(found), 1)
            self.assertIn("(Gift__c.Gone__c)", found[0])
            rel = found[0].split(":")[0]
            allow = os.path.join(root, "allow.txt")
            with open(allow, "w", encoding="utf-8") as handle:
                handle.write("# header\n%s Gift__c.Gone__c  # test reason\n" % rel)
            self.assertEqual(cfr.scan(root, index, cfr.load_allowlist(allow)), [])


if __name__ == "__main__":
    unittest.main()
