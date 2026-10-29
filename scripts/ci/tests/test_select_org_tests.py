"""select-org-tests.py: the test classes the incremental org gate runs for a range of commits.

Each test builds a small git repository of Apex classes in a temporary directory and runs the
real script there, so no org is needed.
"""

import os
import subprocess
import tempfile
import textwrap
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.abspath(os.path.join(HERE, "..", "..", "org", "select-org-tests.py"))
CLASSES = "packages/core/main/default/classes"


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True).stdout.strip()


class SelectOrgTestsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = self.tmp.name
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "test@example.com")
        git(self.repo, "config", "user.name", "Test")
        self.write("HouseholdService.cls", "public class HouseholdService { public static void run() {} }")
        self.write("GiftService.cls", "public class GiftService { public static void save() {} }")
        self.write("ContactTrigger.trigger", "trigger ContactTrigger on Contact (after insert) {}", folder="packages/core/main/default/triggers")
        self.write("TestDataFactory.cls", "@IsTest public class TestDataFactory { public static void make() {} }")
        self.write("HouseholdServiceTest.cls", self.apex_class("HouseholdServiceTest", "HouseholdService.run();", test_for="ApexClass:HouseholdService"))
        self.write("GiftServiceTest.cls", self.apex_class("GiftServiceTest", "GiftService.save();", test_for="ApexClass:GiftService"))
        self.write("ContactTriggerTest.cls", self.apex_class("ContactTriggerTest", "insert new Contact();", test_for="ApexTrigger:ContactTrigger"))
        self.write("SmokeTest.cls", self.apex_class("SmokeTest", "System.assert(true);", critical=True))
        self.write("CallerTest.cls", self.apex_class("CallerTest", "TestDataFactory.make(); GiftService.save();", test_for="ApexClass:SmokeTarget"))
        self.write("CommentOnlyTest.cls", self.apex_class("CommentOnlyTest", "// HouseholdService is not called here\n System.assert(true);", test_for="ApexClass:Other"))
        self.write("VendorTest.cls", self.apex_class("VendorTest", "GiftService.save();", test_for="ApexClass:GiftService"), folder="packages/core/vendor/classes")
        self.base = self.commit("base")

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def apex_class(name, body, test_for=None, critical=False):
        params = []
        if test_for:
            params.append(f"testFor='{test_for}'")
        if critical:
            params.append("critical=true")
        annotation = f"@IsTest({', '.join(params)})" if params else "@IsTest"
        return textwrap.dedent(
            f"""
            {annotation}
            private class {name} {{
                @IsTest
                static void works() {{
                    {body}
                }}
            }}
            """
        )

    def write(self, name, source, folder=CLASSES):
        path = os.path.join(self.repo, folder, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(source)

    def commit(self, message):
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", message)
        return git(self.repo, "rev-parse", "HEAD")

    def select(self):
        out = subprocess.run(
            ["python3", SCRIPT, self.base, "HEAD"], cwd=self.repo, capture_output=True, text=True, check=True
        ).stdout
        return set(out.split())

    def test_no_change_runs_only_the_critical_classes(self):
        self.assertEqual(self.select(), {"SmokeTest"})

    def test_changed_class_selects_its_test_for_and_its_callers(self):
        self.write("GiftService.cls", "public class GiftService { public static void save() { Integer i = 1; } }")
        self.commit("change GiftService")
        self.assertEqual(self.select(), {"SmokeTest", "GiftServiceTest", "CallerTest"})

    def test_changed_test_class_runs_itself(self):
        self.write("HouseholdServiceTest.cls", self.apex_class("HouseholdServiceTest", "HouseholdService.run(); HouseholdService.run();", test_for="ApexClass:HouseholdService"))
        self.commit("change a test")
        self.assertEqual(self.select(), {"SmokeTest", "HouseholdServiceTest"})

    def test_changed_trigger_selects_its_test_for(self):
        self.write("ContactTrigger.trigger", "trigger ContactTrigger on Contact (after insert, after update) {}", folder="packages/core/main/default/triggers")
        self.commit("change the trigger")
        self.assertEqual(self.select(), {"SmokeTest", "ContactTriggerTest"})

    def test_changed_test_utility_selects_its_users(self):
        self.write("TestDataFactory.cls", "@IsTest public class TestDataFactory { public static void make() { Integer i = 2; } }")
        self.commit("change the factory")
        self.assertEqual(self.select(), {"SmokeTest", "CallerTest"})

    def test_a_mention_in_a_comment_does_not_select(self):
        self.write("HouseholdService.cls", "public class HouseholdService { public static void run() { Integer i = 3; } }")
        self.commit("change HouseholdService")
        self.assertNotIn("CommentOnlyTest", self.select())

    def test_deleted_class_selects_nothing_of_its_own(self):
        os.remove(os.path.join(self.repo, CLASSES, "HouseholdService.cls"))
        self.commit("delete HouseholdService")
        self.assertEqual(self.select(), {"SmokeTest"})


if __name__ == "__main__":
    unittest.main()
