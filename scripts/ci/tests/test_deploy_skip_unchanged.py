"""deploy-packages.sh: combined stages, and skipping packages unchanged since the last deploy to
the same org (D-142).

A fake `sf` on PATH answers every call, so no org is needed. Each test works in a clone of the
committed HEAD, so the tree is clean and package changes can be committed freely.
"""

import json
import os
import shutil
import signal
import subprocess
import tempfile
import textwrap
import time
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
    def event(kind, detail):
        with open(os.path.join(state, "events.jsonl"), "a") as log:
            log.write(json.dumps([kind, detail]) + "\n")
    if args[:2] == ["apex", "run"]:
        event("apex", sys.stdin.read())
        out({})
    elif args[:3] == ["org", "assign", "permset"]:
        event("assign", args[args.index("--name") + 1])
        out({})
    elif args[:2] == ["data", "query"] and "AsyncApexJob" in args[args.index("--query") + 1]:
        jobs = []
        if os.environ.get("FAKE_SCHEDULED_JOB"):
            jobs = [{"CronTriggerId": "08e000000000001AAA", "ApexClass": {"Name": "TabAccessScheduler"},
                     "CronTrigger": {"CronJobDetail": {"Name": "BarnCRM Tab Access Check"},
                                     "CronExpression": "0 0 * * * ?", "State": "WAITING"}}]
        out({"records": jobs})
    elif args[:2] == ["org", "display"]:
        out({"id": os.environ["FAKE_ORG_ID"]})
    elif args[:3] == ["project", "deploy", "start"]:
        known = ids()
        new = "0Af%015dAAA" % len(known)
        with open(path, "w") as f:
            json.dump([new] + known, f)
        dirs = [args[i + 1] for i, a in enumerate(args) if a in ("--source-dir", "--metadata-dir")]
        with open(os.path.join(state, "deploy-log.jsonl"), "a") as log:
            log.write(json.dumps(dirs) + "\n")
        event("deploy", dirs)
        if os.environ.get("FAKE_HOLD_DEPLOY") and "packages/core/main/default/classes" in dirs:
            import time
            time.sleep(60)
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

    def run_script(self, *args, org=None, apex_always="1", **extra_env):
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
        env.update(extra_env)
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

    def events(self):
        with open(os.path.join(self.fake, "events.jsonl"), encoding="utf-8") as f:
            return [json.loads(line) for line in f]

    def test_scheduled_jobs_are_paused_around_each_apex_stage(self):
        self.run_script("--core-only", FAKE_SCHEDULED_JOB="1")
        events = self.events()
        core_apex = next(
            i for i, (kind, detail) in enumerate(events)
            if kind == "deploy" and "packages/core/main/default/classes" in detail
        )
        before = [d for kind, d in events[:core_apex] if kind == "apex"]
        after = [d for kind, d in events[core_apex + 1:] if kind == "apex"]
        self.assertIn("System.abortJob('08e000000000001AAA');", before[-1])
        self.assertIn(
            "System.schedule('BarnCRM Tab Access Check', '0 0 * * * ?', "
            "(Schedulable) Type.forName('TabAccessScheduler').newInstance());",
            after[0],
        )

    def test_an_interrupted_deploy_still_schedules_the_paused_jobs_again(self):
        for sig in (signal.SIGINT, signal.SIGTERM):
            events_path = os.path.join(self.fake, "events.jsonl")
            if os.path.exists(events_path):
                os.remove(events_path)
            env = dict(
                os.environ,
                PATH=self.fake + os.pathsep + os.environ["PATH"],
                FAKE_SF_DIR=self.fake,
                FAKE_ORG_ID=self.org,
                DEPLOY_STATE_DIR=self.state_dir,
                DEPLOY_APEX_ALWAYS="1",
                SOURCE_POST_INSTALL="0",
                POLL_SECONDS="0",
                FAKE_SCHEDULED_JOB="1",
                FAKE_HOLD_DEPLOY="1",
            )
            proc = subprocess.Popen(
                ["bash", "scripts/org/deploy-packages.sh", "fake-org", "--core-only"],
                cwd=self.repo, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, start_new_session=True,
            )
            try:
                # Wait until the Apex stage is under way, so the jobs are paused.
                deadline = time.time() + 60
                while time.time() < deadline:
                    if os.path.exists(events_path) and any(
                        kind == "deploy" and "packages/core/main/default/classes" in detail
                        for kind, detail in self.events()
                    ):
                        break
                    time.sleep(0.1)
                else:
                    self.fail("the Apex stage never started")
                os.killpg(proc.pid, sig)
                output, _ = proc.communicate(timeout=60)
            finally:
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGKILL)
            self.assertEqual(proc.returncode, 130 if sig == signal.SIGINT else 143, output[-2000:])
            applied = [d for kind, d in self.events() if kind == "apex"]
            self.assertIn("System.abortJob('08e000000000001AAA');", applied[0])
            self.assertIn("System.schedule('BarnCRM Tab Access Check'", applied[-1], output[-2000:])
            self.assertEqual(
                sum("System.schedule(" in d for d in applied), 1, "restored exactly once"
            )

    def test_no_scheduled_job_means_no_abort(self):
        self.run_script("--core-only")
        self.assertFalse([d for kind, d in self.events() if kind == "apex" and "abortJob" in d])

    def test_the_deploying_admin_gets_barncrm_admin_before_post_install(self):
        self.run_script("--core-only", SOURCE_POST_INSTALL="1")
        events = self.events()
        assign = events.index(["assign", "BarnCRM_Admin"])
        post_install = next(
            i for i, (kind, d) in enumerate(events)
            if kind == "apex" and "CorePostInstall.runAsSourceDeploy" in d
        )
        self.assertLess(assign, post_install)


if __name__ == "__main__":
    unittest.main()
