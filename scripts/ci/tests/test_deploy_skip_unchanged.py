"""deploy-packages.sh: skipping packages unchanged since the last deploy to the same org.

A fake `sf` on PATH answers every call, so no org is needed. Each test works in a clone of the
committed HEAD, so the tree is clean and package changes can be committed freely.
"""

import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

FAKE_SF = textwrap.dedent(
    r'''
    #!/usr/bin/env python3
    import json, os, sys
    state = os.environ["FAKE_SF_DIR"]
    args = sys.argv[1:]
    def ids():
        path = os.path.join(state, "deploys.json")
        return json.load(open(path)) if os.path.exists(path) else ["0Af000000000000AAA"]
    def out(result):
        print(json.dumps({"status": 0, "result": result}))
    if args[:2] == ["org", "display"]:
        out({"id": os.environ["FAKE_ORG_ID"]})
    elif args[:2] == ["project", "deploy"] and args[2] == "start":
        known = ids()
        new = "0Af%015dAAA" % len(known)
        json.dump([new] + known, open(os.path.join(state, "deploys.json"), "w"))
        dirs = [args[i + 1] for i, a in enumerate(args) if a in ("--source-dir", "--metadata-dir")]
        with open(os.path.join(state, "deploy-log.jsonl"), "a") as log:
            log.write(json.dumps(dirs) + "\n")
        out({"id": new})
    elif args[:2] == ["project", "deploy"] and args[2] == "report":
        out({"status": "Succeeded", "done": True, "startDate": "now",
             "numberComponentsDeployed": 1, "numberComponentsTotal": 1, "numberComponentErrors": 0})
    elif args[:2] == ["data", "query"]:
        query = args[args.index("--query") + 1]
        limit = 2 if "LIMIT 2" in query else 1
        out({"records": [{"Id": i} for i in ids()[:limit]]})
    else:
        out({})
    '''
).lstrip()


class DeploySkipUnchanged(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.repo = os.path.join(self.tmp, "repo")
        subprocess.run(["git", "clone", "-q", "--shared", REPO, self.repo], check=True)
        self.fake = os.path.join(self.tmp, "fake")
        os.makedirs(self.fake)
        sf = os.path.join(self.fake, "sf")
        with open(sf, "w") as f:
            f.write(FAKE_SF)
        os.chmod(sf, 0o755)
        self.state_dir = os.path.join(self.tmp, "state")
        self.org = "00D000000000001AAA"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def deploy(self, *flags, org=None, apex_always="1"):
        log = os.path.join(self.fake, "deploy-log.jsonl")
        if os.path.exists(log):
            os.remove(log)
        env = dict(
            os.environ,
            PATH=self.fake + os.pathsep + os.environ["PATH"],
            FAKE_SF_DIR=self.fake,
            FAKE_ORG_ID=org or self.org,
            DEPLOY_STATE_DIR=self.state_dir,
            DEPLOY_APEX_ALWAYS=apex_always,
            SOURCE_POST_INSTALL="0",
            POLL_SECONDS="0",
        )
        result = subprocess.run(
            ["bash", "scripts/org/deploy-packages.sh", "fake-org", *flags],
            cwd=self.repo, env=env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout[-3000:] + result.stderr[-2000:])
        self.output = result.stdout
        if not os.path.exists(log):
            return []
        with open(log) as f:
            return [d for line in f for d in json.loads(line)]

    def record(self, org=None):
        return os.path.join(self.state_dir, (org or self.org) + ".json")

    def commit_change(self, path):
        full = os.path.join(self.repo, path)
        with open(full, "a") as f:
            f.write("\n")
        subprocess.run(["git", "-C", self.repo, "-c", "user.name=t", "-c", "user.email=t@t",
                        "commit", "-q", "-am", "change"], check=True)

    def test_first_run_deploys_everything_and_writes_a_record(self):
        dirs = self.deploy()
        self.assertIn("packages/core/main/default/objects", dirs)
        self.assertIn("packages/giving", dirs)
        rec = json.load(open(self.record()))
        self.assertEqual(rec["orgId"], self.org)
        self.assertIn("core", rec["packages"])
        self.assertIn("giving", rec["packages"])

    def test_unchanged_run_deploys_only_apex(self):
        self.deploy()
        dirs = self.deploy()
        self.assertNotIn("packages/core/main/default/objects", dirs)
        self.assertNotIn("packages/giving", dirs)
        self.assertIn("packages/core/main/default/classes", dirs)
        self.assertIn("packages/giving/main/default/classes", dirs)
        self.assertTrue(os.path.exists(self.record()))

    def test_unchanged_run_without_apex_deploys_no_package(self):
        self.deploy()
        dirs = self.deploy(apex_always="0")
        self.assertFalse([d for d in dirs if d.startswith("packages/")], dirs)

    def test_changed_package_deploys_in_full(self):
        self.deploy()
        self.commit_change("packages/giving/README.md")
        dirs = self.deploy()
        self.assertIn("packages/giving", dirs)
        self.assertNotIn("packages/rollups", dirs)
        self.assertNotIn("packages/core/main/default/objects", dirs)

    def test_a_deploy_by_anyone_else_forces_a_full_deploy(self):
        self.deploy()
        deploys = os.path.join(self.fake, "deploys.json")
        ids = json.load(open(deploys))
        json.dump(["0Af999999999999AAA"] + ids, open(deploys, "w"))
        self.assertIn("packages/core/main/default/objects", self.deploy())

    def test_another_org_or_full_flag_or_bad_record_forces_a_full_deploy(self):
        self.deploy()
        shutil.copy(self.record(), self.record("00D000000000002AAA"))
        self.assertIn("packages/giving", self.deploy(org="00D000000000002AAA"))
        self.assertIn("packages/giving", self.deploy("--full"))
        with open(self.record(), "w") as f:
            f.write("{not json")
        self.assertIn("packages/giving", self.deploy())

    def test_deploy_inputs_change_forces_a_full_deploy(self):
        self.deploy()
        self.commit_change("sfdx-project.json")
        self.assertIn("packages/core/main/default/objects", self.deploy())

    def test_uncommitted_change_deploys_everything_and_keeps_no_record(self):
        self.deploy()
        with open(os.path.join(self.repo, "packages/giving/README.md"), "a") as f:
            f.write("\n")
        self.assertIn("packages/core/main/default/objects", self.deploy())
        self.assertFalse(os.path.exists(self.record()))

    def test_adopt_keeps_the_record_only_for_the_next_deploy(self):
        self.deploy()
        deploys = os.path.join(self.fake, "deploys.json")
        ids = json.load(open(deploys))
        json.dump(["0Af888888888888AAA"] + ids, open(deploys, "w"))
        self.deploy_adopt("0Af888888888888")
        self.assertTrue(os.path.exists(self.record()))
        self.assertNotIn("packages/giving", self.deploy())
        # Two deploys since the record: the one adopted is not the only one, so the record goes.
        ids = json.load(open(deploys))
        json.dump(["0Af777777777777AAA", "0Af666666666666AAA"] + ids, open(deploys, "w"))
        self.deploy_adopt("0Af777777777777AAA")
        self.assertFalse(os.path.exists(self.record()))

    def deploy_adopt(self, deploy_id):
        env = dict(
            os.environ,
            PATH=self.fake + os.pathsep + os.environ["PATH"],
            FAKE_SF_DIR=self.fake,
            FAKE_ORG_ID=self.org,
            DEPLOY_STATE_DIR=self.state_dir,
        )
        result = subprocess.run(
            ["bash", "scripts/org/deploy-packages.sh", "fake-org", "--adopt", deploy_id],
            cwd=self.repo, env=env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_config_and_modules_are_one_request_each(self):
        log = os.path.join(self.fake, "deploy-log.jsonl")
        self.deploy()
        with open(log) as f:
            requests = [json.loads(line) for line in f]
        config = [r for r in requests if "packages/core/main/default/labels" in r]
        self.assertEqual(len(config), 1)
        self.assertIn("packages/core/main/default/customMetadata", config[0])
        modules = [r for r in requests if "packages/giving" in r]
        self.assertEqual(len(modules), 1)
        self.assertIn("packages/rollups", modules[0])
        self.assertIn("packages/mirror", modules[0])


if __name__ == "__main__":
    unittest.main()
