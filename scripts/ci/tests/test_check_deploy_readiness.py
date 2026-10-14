import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cdr", os.path.join(HERE, "..", "check-deploy-readiness.py"))
cdr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cdr)

OBJ = """<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
%s</CustomObject>
"""
FULL = "<label>X</label><pluralLabel>Xs</pluralLabel><nameField><label>N</label><type>Text</type></nameField>"


def write(root, rel, content):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)


def repo(folders, staged="objects classes", objects=None):
    root = tempfile.mkdtemp()
    write(root, cdr.SCRIPT, f"CORE_STAGED=({staged}\n  lwc)\n")
    for folder in folders:
        os.makedirs(os.path.join(root, cdr.CORE_DIR, folder))
    for name, body in (objects or {}).items():
        write(root, f"packages/core/main/default/objects/{name}/{name}.object-meta.xml", OBJ % body)
    return root


class StagedFolders(unittest.TestCase):
    def test_passes_when_all_staged(self):
        self.assertEqual(cdr.check_staged(repo(["objects", "lwc"])), [])

    def test_fails_on_unstaged_folder(self):
        problems = cdr.check_staged(repo(["objects", "prompts"]))
        self.assertEqual(len(problems), 1)
        self.assertIn("prompts", problems[0])


class ApiFlags(unittest.TestCase):
    def test_passes_when_all_equal(self):
        body = FULL + "<enableSharing>true</enableSharing><enableBulkApi>true</enableBulkApi><enableStreamingApi>true</enableStreamingApi>"
        self.assertEqual(cdr.check_objects(repo([], objects={"A__c": body})), [])

    def test_fails_when_mixed(self):
        body = FULL + "<enableSharing>true</enableSharing><enableBulkApi>true</enableBulkApi><enableStreamingApi>false</enableStreamingApi>"
        problems = cdr.check_objects(repo([], objects={"A__c": body}))
        self.assertEqual(len(problems), 1)
        self.assertIn("all true or all false", problems[0])


class NameField(unittest.TestCase):
    def test_passes_with_name_field(self):
        self.assertEqual(cdr.check_objects(repo([], objects={"A__c": FULL})), [])

    def test_passes_for_custom_setting(self):
        body = "<customSettingsType>List</customSettingsType>"
        self.assertEqual(cdr.check_objects(repo([], objects={"A__c": body})), [])

    def test_fails_without_name_field(self):
        problems = cdr.check_objects(repo([], objects={"A__c": "<label>X</label><pluralLabel>Xs</pluralLabel>"}))
        self.assertEqual(len(problems), 1)
        self.assertIn("nameField", problems[0])


if __name__ == "__main__":
    unittest.main()
