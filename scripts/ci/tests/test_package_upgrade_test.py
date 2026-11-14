"""The package install-and-upgrade test script, in --plan mode.

No org, Dev Hub or sf CLI is needed: --plan prints the steps and runs none of them. The script
is pointed at a temporary copy of sfdx-project.json with a made-up namespace, as it will read
the real one once the namespace is registered (plan D-87, D-173).
"""

import json
import os
import re
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCRIPT = os.path.join(ROOT, "scripts", "org", "package-upgrade-test.sh")
FAKE_NAMESPACE = "barntest"


def run(*args):
    return subprocess.run(["bash", SCRIPT, *args], cwd=ROOT, capture_output=True, text=True)


def steps(output, prefix):
    return re.findall(r"^\s+\[" + re.escape(prefix) + r":([a-z]+)\]", output, re.M)


class PackageUpgradePlanTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, "sfdx-project.json"), encoding="utf-8") as handle:
            cls.project = json.load(handle)
        cls.tmp = tempfile.TemporaryDirectory()
        cls.project_file = os.path.join(cls.tmp.name, "sfdx-project.json")
        fake = dict(cls.project, namespace=FAKE_NAMESPACE)
        with open(cls.project_file, "w", encoding="utf-8") as handle:
            json.dump(fake, handle)
        cls.keys = [os.path.basename(d["path"]) for d in cls.project["packageDirectories"]]
        by_name = {d["package"]: os.path.basename(d["path"]) for d in cls.project["packageDirectories"]}
        cls.deps = {
            os.path.basename(d["path"]): [by_name[x["package"]] for x in d.get("dependencies", [])]
            for d in cls.project["packageDirectories"]
        }

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def plan(self, *extra):
        result = run("--plan", "--project", self.project_file, "--from", "HEAD", "--to", "HEAD", *extra)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result.stdout

    def assert_dependency_order(self, order):
        for position, key in enumerate(order):
            for dep in self.deps[key]:
                self.assertIn(dep, order[:position], f"{key} is installed before {dep}, which it needs")

    def test_install_and_upgrade_follow_the_package_directories_dependency_order(self):
        output = self.plan("--shapes", "platform")
        installs = steps(output, "install-n1")
        self.assertEqual(installs, self.keys, "every package, in sfdx-project.json order")
        self.assert_dependency_order(installs)
        self.assertEqual(steps(output, "upgrade"), self.keys)
        self.assertEqual(steps(output, "build-n1"), self.keys)
        self.assertIn(f"Namespace: {FAKE_NAMESPACE}", output)
        self.assertIn(f"{FAKE_NAMESPACE}__Error_Log__c", output)

    def test_each_shape_gets_its_own_org_from_its_definition(self):
        output = self.plan("--shapes", "platform,npc")
        self.assertEqual(output.count("[create-org]"), 2)
        self.assertIn("--definition-file config/scratch-defs/platform-only.json", output)
        self.assertIn("--definition-file config/scratch-defs/nonprofit-cloud.json", output)
        self.assertIn("--no-namespace", output)
        self.assertEqual(output.count("[delete-org]"), 2)

    def test_a_module_brings_the_packages_it_needs_in_order(self):
        output = self.plan("--shapes", "platform", "--packages", "giving")
        self.assertEqual(steps(output, "install-n1"), ["core", "rollups", "giving"])

    def test_plan_touches_nothing(self):
        before = subprocess.run(["git", "worktree", "list"], cwd=ROOT, capture_output=True, text=True).stdout
        report = os.path.join(self.tmp.name, "report")
        self.plan("--shapes", "platform", "--report", report)
        after = subprocess.run(["git", "worktree", "list"], cwd=ROOT, capture_output=True, text=True).stdout
        self.assertEqual(before, after, "no worktree is added")
        self.assertFalse(os.path.exists(report), "no report is written")

    def test_managed_beta_from_a_ref_is_refused_unless_promoted(self):
        output = self.plan("--shapes", "platform")
        self.assertIn("REFUSED for managed", output)
        self.assertNotIn("[promote-n1:", output)
        promoted = self.plan("--shapes", "platform", "--promote-from")
        self.assertEqual(steps(promoted, "promote-n1"), self.keys)
        self.assertIn("PROMOTION IS PERMANENT", promoted)

    def test_unlocked_runs_each_post_install_as_the_admin(self):
        output = self.plan("--shapes", "platform", "--type", "unlocked", "--packages", "giving")
        self.assertEqual(steps(output, "setup-n1"), ["core", "rollups", "giving"])
        self.assertEqual(steps(output, "setup-n"), ["core", "rollups", "giving"])
        self.assertNotIn("[setup-n1:", self.plan("--shapes", "platform", "--packages", "giving"))

    def test_a_04t_file_skips_the_build(self):
        ids = os.path.join(self.tmp.name, "n1.txt")
        with open(ids, "w", encoding="utf-8") as handle:
            handle.write("# released\ncore 04t000000000001AAA\n")
        result = run("--plan", "--project", self.project_file, "--from", ids, "--to", "HEAD",
                     "--packages", "core", "--shapes", "platform")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("[build-n1:", result.stdout)
        self.assertIn("--package 04t000000000001AAA", result.stdout)

    def test_refuses_to_run_while_the_namespace_is_empty(self):
        if self.project.get("namespace"):
            self.skipTest("the namespace is registered")
        result = run("--from", "HEAD", "--to", "HEAD")
        self.assertEqual(result.returncode, 2)
        self.assertIn("namespace", result.stderr)

    def test_refuses_without_readiness_or_approval(self):
        result = run("--project", self.project_file, "--from", "HEAD", "--to", "HEAD", "--devhub", "hub",
                     "--shapes", "platform")
        self.assertEqual(result.returncode, 2)
        self.assertIn("MISSING", result.stdout)

    def test_uninstall_check_needs_a_module_nothing_chosen_depends_on(self):
        result = run("--plan", "--project", self.project_file, "--from", "HEAD", "--to", "HEAD",
                     "--packages", "mirror", "--uninstall-check=giving")
        self.assertEqual(result.returncode, 2)
        self.assertIn("mirror", result.stderr)
        output = self.plan("--shapes", "platform", "--packages", "volunteers", "--uninstall-check")
        self.assertIn("[uninstall:volunteers]", output)
        self.assertIn("--absent BarnCRM Volunteers", output)


if __name__ == "__main__":
    unittest.main()
