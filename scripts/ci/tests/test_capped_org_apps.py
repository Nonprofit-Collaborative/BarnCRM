import glob
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
spec = importlib.util.spec_from_file_location(
    "coa", os.path.join(HERE, "..", "..", "org", "capped-org-apps.py")
)
coa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coa)


def app_names(pattern):
    return {os.path.basename(p)[: -len(".app-meta.xml")] for p in glob.glob(os.path.join(ROOT, pattern))}


class CappedOrgApps(unittest.TestCase):
    def test_every_left_out_folder_ships_an_app(self):
        for folder in coa.LEFT_OUT:
            self.assertTrue(
                app_names(f"packages/{folder}/main/default/applications/*.app-meta.xml"),
                f"{folder} is in LEFT_OUT but ships no app",
            )

    def test_a_capped_org_gets_no_more_apps_than_the_budget(self):
        every = app_names("packages/*/main/default/applications/*.app-meta.xml")
        kept = every - coa.left_out_apps(ROOT)
        self.assertLessEqual(
            len(kept),
            coa.CAPPED_ORG_APP_BUDGET,
            f"A scratch or Developer Edition org would get {len(kept)} apps ({', '.join(sorted(kept))}); "
            "add the new app's folder to LEFT_OUT in scripts/org/capped-org-apps.py (ADR-0223)",
        )

    def test_only_left_out_folders_grant_a_left_out_app(self):
        # A set outside LEFT_OUT deploys unchanged, so naming a left-out app would fail there.
        apps = coa.left_out_apps(ROOT)
        for path in glob.glob(os.path.join(ROOT, "packages/*/main/default/permissionsets/*.xml")):
            folder = os.path.relpath(path, ROOT).split(os.sep)[1]
            if folder in coa.LEFT_OUT:
                continue
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            for app in apps:
                self.assertNotIn(f"<application>{app}</application>", text, path)

    def test_permission_sets_lose_only_the_left_out_visibilities(self):
        with tempfile.TemporaryDirectory() as out:
            written = coa.write_permission_sets(ROOT, out, ["events"])
            self.assertIn("Events_Staff", written)
            with open(os.path.join(out, "permissionsets", "Events_Staff.permissionset"), encoding="utf-8") as f:
                text = f.read()
            self.assertNotIn("BarnCRM_Events", text)
            self.assertIn("<classAccesses>", text)
            with open(os.path.join(out, "package.xml"), encoding="utf-8") as f:
                package = f.read()
            self.assertIn("<members>Events_Staff</members>", package)
            self.assertIn("<name>PermissionSet</name>", package)

    def test_other_apps_visibilities_stay(self):
        text = (
            "<PermissionSet>\n"
            "  <applicationVisibilities>\n    <application>Kept_App</application>\n"
            "    <visible>true</visible>\n  </applicationVisibilities>\n"
            "  <applicationVisibilities>\n    <visible>true</visible>\n"
            "    <application>Gone_App</application>\n  </applicationVisibilities>\n"
            "</PermissionSet>\n"
        )
        result = coa.without_apps(text, {"Gone_App"})
        self.assertIn("Kept_App", result)
        self.assertNotIn("Gone_App", result)

    def test_a_folder_not_left_out_is_refused(self):
        with tempfile.TemporaryDirectory() as out:
            with self.assertRaises(SystemExit):
                coa.write_permission_sets(ROOT, out, ["giving"])


if __name__ == "__main__":
    unittest.main()
