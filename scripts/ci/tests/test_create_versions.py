"""scripts/packaging/create-versions.sh in --plan mode and its refusals. No org or sf CLI call."""

import json
import os
import re
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCRIPT = os.path.join(ROOT, "scripts", "packaging", "create-versions.sh")


def run(*args):
    return subprocess.run(["bash", SCRIPT, *args], cwd=ROOT, capture_output=True, text=True)


class CreateVersionsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, "sfdx-project.json"), encoding="utf-8") as handle:
            cls.project = json.load(handle)
        cls.tmp = tempfile.TemporaryDirectory()
        cls.ready = os.path.join(cls.tmp.name, "ready.json")
        aliases = {d["package"]: "0Ho" + str(i).zfill(15) for i, d in enumerate(cls.project["packageDirectories"])}
        with open(cls.ready, "w", encoding="utf-8") as handle:
            json.dump(dict(cls.project, namespace="barntest", packageAliases=aliases), handle)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_plan_builds_in_dependency_order_and_never_promotes(self):
        result = run("--plan", "--project", self.ready, "--devhub", "hub", "--packages", "mirror")
        self.assertEqual(result.returncode, 0, result.stderr)
        built = re.findall(r"^\s+\[(\w+)\] \$ sf package version create", result.stdout, re.M)
        self.assertEqual(built, ["core", "rollups", "giving", "mirror"])
        self.assertIn("Package2VersionCreates", result.stdout)
        self.assertLess(result.stdout.index("Package2VersionCreates"), result.stdout.index("[core]"))
        self.assertNotIn("Not ready", result.stdout)
        self.assertNotIn("version promote --", result.stdout)

    def test_refuses_while_the_namespace_is_empty_or_ids_are_missing(self):
        if self.project.get("namespace"):
            self.skipTest("the namespace is registered")
        result = run("--packages", "core", "--project", os.path.join(ROOT, "sfdx-project.json"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("namespace is empty", result.stdout)
        self.assertIn("sf package create --name \"BarnCRM Core\"", result.stdout)
        self.assertNotIn("remaining/max", result.stdout)


if __name__ == "__main__":
    unittest.main()
