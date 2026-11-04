"""The release tools: Apex size measuring and the destructive manifest.

No org is needed: the manifest test builds a small git repository.
"""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO

HERE = os.path.dirname(os.path.abspath(__file__))
CI = os.path.abspath(os.path.join(HERE, ".."))
ORG = os.path.abspath(os.path.join(HERE, "..", "..", "org"))
sys.path.insert(0, CI)
from apex_source import is_test_class, without_comments  # noqa: E402


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


manifest = load("build_destructive_manifest", os.path.join(ORG, "build-destructive-manifest.py"))


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True).stdout


class ApexSizeTest(unittest.TestCase):
    def test_comments_go_and_strings_stay(self):
        source = "String a = 'x // not a comment'; // gone\n/* gone */Integer b;"
        self.assertEqual(without_comments(source), "String a = 'x // not a comment'; \nInteger b;")

    def test_test_class_is_the_outer_class_annotation(self):
        self.assertTrue(is_test_class("/** doc */\n@IsTest(testFor='ApexClass:A')\nprivate class ATest {}"))
        self.assertTrue(is_test_class("@IsTest\n@NamespaceAccessible\npublic class Factory {}"))
        self.assertFalse(is_test_class("public class A { @IsTest static void t() {} }"))
        self.assertFalse(is_test_class("/* @IsTest */ public class A {}"))


class DestructiveManifestTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = self.tmp.name
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "test@example.com")
        git(self.repo, "config", "user.name", "Test")
        self.write("sfdx-project.json", '{"sourceApiVersion": "67.0", "packageDirectories": []}')
        base = "packages/core/main/default"
        self.write(f"{base}/classes/Keep.cls", "public class Keep {}")
        self.write(f"{base}/classes/Gone.cls", "public class Gone {}")
        self.write(f"{base}/classes/Gone.cls-meta.xml", "<x/>")
        self.write(f"{base}/classes/Moved.cls", "public class Moved {}")
        self.write(f"{base}/objects/Old__c/Old__c.object-meta.xml", "<x/>")
        self.write(f"{base}/objects/Old__c/fields/A__c.field-meta.xml", "<x/>")
        self.write(f"{base}/objects/Contact/fields/Gone__c.field-meta.xml", "<x/>")
        self.write(f"{base}/objects/Account/recordTypes/Old.recordType-meta.xml", "<x/>")
        self.write(f"{base}/lwc/oldPanel/oldPanel.js", "")
        self.write(f"{base}/labels/CustomLabels.labels-meta.xml",
                   "<labels><fullName>Keep_Label</fullName></labels><labels><fullName>Gone_Label</fullName></labels>")
        self.old = self.commit("old")
        for path in ("classes/Gone.cls", "classes/Gone.cls-meta.xml", "classes/Moved.cls",
                     "objects/Old__c/Old__c.object-meta.xml", "objects/Old__c/fields/A__c.field-meta.xml",
                     "objects/Contact/fields/Gone__c.field-meta.xml",
                     "objects/Account/recordTypes/Old.recordType-meta.xml", "lwc/oldPanel/oldPanel.js"):
            git(self.repo, "rm", "-q", f"{base}/{path}")
        self.write("packages/giving/main/default/classes/Moved.cls", "public class Moved {}")
        self.write(f"{base}/labels/CustomLabels.labels-meta.xml", "<labels><fullName>Keep_Label</fullName></labels>")
        self.new = self.commit("new")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        path = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def commit(self, message):
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", message)
        return git(self.repo, "rev-parse", "HEAD").strip()

    def test_lists_removed_components_only(self):
        cwd = os.getcwd()
        out = os.path.join(self.repo, "out")
        try:
            os.chdir(self.repo)
            with redirect_stdout(StringIO()):
                status = manifest.main([self.old, self.new, "--out", out])
        finally:
            os.chdir(cwd)
        with open(os.path.join(out, "destructiveChangesPost.xml"), encoding="utf-8") as handle:
            text = handle.read()
        for member in ("Gone", "Old__c", "Contact.Gone__c", "oldPanel", "Gone_Label"):
            self.assertIn(f"<members>{member}</members>", text)
        for member in ("Keep", "Moved", "Old__c.A__c", "Account.Old", "Keep_Label"):
            self.assertNotIn(f"<members>{member}</members>", text)
        self.assertEqual(status, 1, "a removed record type is a step by hand")


if __name__ == "__main__":
    unittest.main()
