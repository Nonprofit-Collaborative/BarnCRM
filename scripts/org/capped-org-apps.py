#!/usr/bin/env python3
"""Leaves some module apps out of a deploy to an org with a low custom app limit (ADR-NEXT).

    python3 scripts/org/capped-org-apps.py modules
    python3 scripts/org/capped-org-apps.py permission-sets OUT_DIR FOLDER [FOLDER ...]

Scratch orgs and Developer Edition orgs, which every test org is, refuse a custom app past about
10, and an app deployed from source counts toward that limit (architecture.md, Gotchas). Real
orgs (Enterprise Edition and up, and their sandboxes) and managed package installs do not hit
it. So the suite ships every module app, and `deploy-packages.sh`, on a capped org only, leaves
out the apps of the modules in LEFT_OUT. Their tabs still reach the BarnCRM apps
(`module-app-tabs.py`, ADR-0192), so nothing becomes unreachable.

`modules` prints the LEFT_OUT package folders, one per line, for the deploy script.

`permission-sets` writes every permission set of the named folders (each in LEFT_OUT) with the
`applicationVisibilities` entries for the left-out apps removed: a permission set that names an
app the org does not have fails to deploy. OUT_DIR receives a metadata-format package
(`package.xml` and `permissionsets/<Name>.permissionset`) for
`sf project deploy start --metadata-dir OUT_DIR`; nothing is written when no set is found. The
repository's files are never changed. Prints the number of sets written.

CAPPED_ORG_APP_BUDGET is how many suite apps a capped org may receive; a CI test keeps the apps
not left out within it, so a new app is either inside the budget or added to LEFT_OUT.
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NS = "http://soap.sforce.com/2006/04/metadata"
# The module folders whose app a capped org does not get: the five module apps added on
# 2026-11-13 (Event Management, Forms, Portal Builder, Corporate Hub, Project Management).
LEFT_OUT = ("events", "forms", "portal", "corporatehub", "projects")
CAPPED_ORG_APP_BUDGET = 9
BLOCK = re.compile(r"  <applicationVisibilities>(.*?)</applicationVisibilities>\n", re.S)
APP = re.compile(r"<application>([^<]*)</application>")


def left_out_apps(root):
    """The developer names of the apps the LEFT_OUT folders ship."""
    names = set()
    for folder in LEFT_OUT:
        pattern = os.path.join(root, "packages", folder, "main/default/applications", "*.app-meta.xml")
        for path in glob.glob(pattern):
            names.add(os.path.basename(path)[: -len(".app-meta.xml")])
    return names


def without_apps(text, apps):
    """The permission set XML with its visibility entries for the named apps removed."""

    def keep(match):
        named = APP.search(match.group(1))
        return "" if named and named.group(1).strip() in apps else match.group(0)

    return BLOCK.sub(keep, text)


def api_version(root):
    with open(os.path.join(root, "sfdx-project.json"), encoding="utf-8") as handle:
        return json.load(handle)["sourceApiVersion"]


def write_permission_sets(root, out_dir, folders):
    """Writes the folders' permission sets without the left-out apps; returns the names written."""
    unknown = [folder for folder in folders if folder not in LEFT_OUT]
    if unknown:
        raise SystemExit(f"Not a folder whose app is left out: {', '.join(unknown)}")
    apps = left_out_apps(root)
    written = []
    for folder in folders:
        pattern = os.path.join(root, "packages", folder, "main/default/permissionsets", "*.permissionset-meta.xml")
        for path in sorted(glob.glob(pattern)):
            name = os.path.basename(path)[: -len(".permissionset-meta.xml")]
            with open(path, encoding="utf-8") as handle:
                text = without_apps(handle.read(), apps)
            os.makedirs(os.path.join(out_dir, "permissionsets"), exist_ok=True)
            with open(os.path.join(out_dir, "permissionsets", name + ".permissionset"), "w", encoding="utf-8") as handle:
                handle.write(text)
            written.append(name)
    if written:
        members = "".join(f"    <members>{name}</members>\n" for name in written)
        with open(os.path.join(out_dir, "package.xml"), "w", encoding="utf-8") as handle:
            handle.write(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                f'<Package xmlns="{NS}">\n  <types>\n{members}'
                "    <name>PermissionSet</name>\n  </types>\n"
                f"  <version>{api_version(root)}</version>\n</Package>\n"
            )
    return written


def main(argv):
    if argv[:1] == ["modules"]:
        print("\n".join(LEFT_OUT))
        return 0
    if argv[:1] == ["permission-sets"] and len(argv) >= 3:
        written = write_permission_sets(ROOT, argv[1], argv[2:])
        print(f"{len(written)} permission set(s) written without the left-out apps")
        return 0
    print(
        "Usage: capped-org-apps.py modules | permission-sets OUT_DIR FOLDER [FOLDER ...]",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
