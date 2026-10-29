"""deploy-packages.sh: combined stages, and skipping packages unchanged since the last deploy to
the same org (D-142).

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
    path = os.path.join(state, "deploys.json")
    def ids():
        if not os.path.exists(path):
            return ["0Af000000000000AAA"]
        with open(path) as f:
            return json.load(f)
    def out(result):
        print(json.dumps({"status": 0, "result": result}))
    if args[:2] == ["org", "display"]:
        out({"id": os.environ["FAKE_ORG_ID"]})
    elif args[:3] == ["project", "deploy", "start"]:
        known = ids()
        new = "0Af%015dAAA" % len(known)
        with open(path, "w") as f:
            json.dump([new] + known, f)
        dirs = [args[i + 1] for i, a in enumerate(args) if a in ("--source-dir", "--metadata-dir")]
        with open(os.path.join(state, "deploy-log.jsonl"), "a") as log:
            log.write(json.dumps(dirs) + "\n")
        out({"id": new})
    elif args[:3] == ["project", "deploy", "report"]:
        out({"status": "Succeeded", "done": True, "startDate": "now",
             "numberComponentsDeployed": 1, "numberComponentsTotal": 1, "numberComponentErrors": 0})
    elif args[:2] == ["data", "query"]:
        query = args[args.index("--query") + 1]
        out({"records": [{"Id": i} for i in ids()[:2 if "LIMIT 2" in query else 1]]})
    else:
        out({})
    '''
).lstrip()

OBJECTS = "packages/core/main/default/objects"


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_json(path, value):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(value, f)


class DeploySkipUnchanged(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.repo = os.path.join(self.tmp, "repo")
        subprocess.run(["git", "clone", "-q", "--shared", REPO, self.repo], check=True)
        self.fake = os.path.join(self.tmp, "fake")
        os.makedirs(self.fake)
        sf = os.path.join(self.fake, "sf")
        with open(sf, "w", encoding="utf-8") as f:
            f.write(FAKE_SF)
        os.chmod(sf, 0o755)
        self.log = os.path.join(self.fake, "deploy-log.jsonl")
        self.deploys = os.path.join(self.fake, "deploys.json")
        self.state_dir = os.path.join(self.tmp, "state")
        self.org = "00D000000000001AAA"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_script(self, *args, org=None, apex_always="1"):
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
            ["bash", "scripts/org/deploy-packages.sh", "fake-org", *args],
            cwd=self.repo, env=env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout[-3000:] + result.stderr[-2000:])

    def deploy(self, *flags, **kwargs):
        """Runs a deploy; returns the list of requests, each the list of directories it sent."""
        if os.path.exists(self.log):
            os.remove(self.log)
        self.run_script(*flags, **kwargs)
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding="utf-8") as f:
            return [json.loads(line) for line in f]

    def sent(self, *flags, **kwargs):
        return [d for request in self.deploy(*flags, **kwargs) for d in request]

    def record(self, org=None):
        return os.path.join(self.state_dir, (org or self.org) + ".json")

    def someone_deploys(self, *new_ids):
        write_json(self.deploys, list(new_ids) + read_json(self.deploys))

    def commit_change(self, path):
        with open(os.path.join(self.repo, path), "a", encoding="utf-8") as f:
            f.write("\n")
        subprocess.run(["git", "-C", self.repo, "-c", "user.name=t", "-c", "user.email=t@t",
                        "commit", "-q", "-am", "change"], check=True)

    def test_skip_lifecycle(self):
        # First run: no record, so everything; config and modules are one request each.
        requests = self.deploy()
        sent = [d for r in requests for d in r]
        self.assertIn(OBJECTS, sent)
        config = [r for r in requests if "packages/core/main/default/labels" in r]
        self.assertEqual(len(config), 1)
        self.assertIn("packages/core/main/default/customMetadata", config[0])
        modules = [r for r in requests if "packages/giving" in r]
        self.assertEqual(len(modules), 1)
        self.assertIn("packages/rollups", modules[0])
        self.assertIn("packages/mirror", modules[0])
        rec = read_json(self.record())
        self.assertEqual(rec["orgId"], self.org)
        self.assertIn("core", rec["packages"])
        self.assertIn("giving", rec["packages"])

        # Unchanged: only Apex, for the coverage recompile.
        sent = self.sent()
        self.assertNotIn(OBJECTS, sent)
        self.assertNotIn("packages/giving", sent)
        self.assertIn("packages/core/main/default/classes", sent)
        self.assertIn("packages/giving/main/default/classes", sent)

        # Unchanged, and no coverage read: no package at all.
        self.assertFalse([d for d in self.sent(apex_always="0") if d.startswith("packages/")])

        # One package changed: that package in full, the rest only Apex.
        self.commit_change("packages/giving/README.md")
        sent = self.sent()
        self.assertIn("packages/giving", sent)
        self.assertNotIn("packages/rollups", sent)
        self.assertNotIn(OBJECTS, sent)

        # The gate's own test deploy, adopted: the record stays good.
        self.someone_deploys("0Af888888888888AAA")
        self.run_script("--adopt", "0Af888888888888")
        self.assertTrue(os.path.exists(self.record()))
        self.assertNotIn("packages/giving", self.sent())

        # Another deploy came in before the adopted one: the record goes.
        self.someone_deploys("0Af777777777777AAA", "0Af666666666666AAA")
        self.run_script("--adopt", "0Af777777777777AAA")
        self.assertFalse(os.path.exists(self.record()))
        self.assertIn(OBJECTS, self.sent())

        # Anyone else's deploy since the record: everything.
        self.someone_deploys("0Af999999999999AAA")
        self.assertIn(OBJECTS, self.sent())

    def test_any_doubt_means_a_full_deploy(self):
        self.deploy()
        other = "00D000000000002AAA"
        shutil.copy(self.record(), self.record(other))
        self.assertIn("packages/giving", self.sent(org=other))
        self.assertIn("packages/giving", self.sent("--full"))
        with open(self.record(), "w", encoding="utf-8") as f:
            f.write("{not json")
        self.assertIn("packages/giving", self.sent())
        self.commit_change("sfdx-project.json")
        self.assertIn(OBJECTS, self.sent())
        # Uncommitted change: everything, and no record kept.
        with open(os.path.join(self.repo, "packages/giving/README.md"), "a", encoding="utf-8") as f:
            f.write("\n")
        self.assertIn(OBJECTS, self.sent())
        self.assertFalse(os.path.exists(self.record()))


if __name__ == "__main__":
    unittest.main()
