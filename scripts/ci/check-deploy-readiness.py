#!/usr/bin/env python3
"""Offline checks for deploy errors that otherwise surface only in the org gate's deploy step.

Rules (each is a certain platform or script requirement, not a style preference):

1. Every folder under packages/core/main/default must be named in CORE_STAGED in
   scripts/org/deploy-packages.sh. That script refuses to run when a folder is unstaged, so a
   new folder (notificationtypes, contentassets, prompts) stopped the org gate before any
   deploy. The list is parsed from the script, never copied here.
2. A CustomObject that sets enableSharing, enableBulkApi or enableStreamingApi must set all
   those it sets to the same value. Salesforce rejects a mix: the three are all true or all
   false (Erasure__c had streaming false beside sharing and bulk true).
3. A custom object (a __c object that is not a custom setting) must carry a nameField,
   label and pluralLabel. The Metadata API rejects a custom object without them.

Usage: check-deploy-readiness.py [repo_root]   (default: the current directory)
"""

import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

NS = "{http://soap.sforce.com/2006/04/metadata}"
CORE_DIR = "packages/core/main/default"
SCRIPT = "scripts/org/deploy-packages.sh"
API_FLAGS = ("enableSharing", "enableBulkApi", "enableStreamingApi")


def core_staged(root):
    with open(os.path.join(root, SCRIPT), encoding="utf-8") as handle:
        text = handle.read()
    match = re.search(r"^CORE_STAGED=\(([^)]*)\)", text, re.M)
    if not match:
        return None
    return match.group(1).split()


def check_staged(root):
    staged = core_staged(root)
    if staged is None:
        return [f"{SCRIPT}: could not find the CORE_STAGED=(...) array."]
    base = os.path.join(root, CORE_DIR)
    folders = sorted(d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)))
    return [
        f"{CORE_DIR}/{d} is not named in CORE_STAGED in {SCRIPT}. "
        "Add it to a stage and to CORE_STAGED, or the org gate refuses to run."
        for d in folders
        if d not in staged
    ]


def check_objects(root):
    problems = []
    pattern = os.path.join(root, "packages", "*", "main", "default", "objects", "*", "*.object-meta.xml")
    for path in sorted(glob.glob(pattern)):
        rel = os.path.relpath(path, root)
        tree = ET.parse(path).getroot()

        def text(tag):
            node = tree.find(NS + tag)
            return None if node is None else (node.text or "").strip()

        flags = {tag: text(tag) for tag in API_FLAGS if text(tag) is not None}
        if len(set(flags.values())) > 1:
            shown = ", ".join(f"{k}={v}" for k, v in flags.items())
            problems.append(
                f"{rel}: {shown}. Salesforce requires enableSharing, enableBulkApi and "
                "enableStreamingApi to be all true or all false."
            )
        name = os.path.basename(path)[: -len(".object-meta.xml")]
        if name.endswith("__c") and text("customSettingsType") is None:
            for tag in ("nameField", "label", "pluralLabel"):
                if tree.find(NS + tag) is None:
                    problems.append(f"{rel}: custom object has no {tag}, which the Metadata API requires.")
    return problems


def main(argv):
    root = argv[1] if len(argv) > 1 else "."
    problems = check_staged(root) + check_objects(root)
    for problem in problems:
        print(f"::error::{problem}" if os.environ.get("GITHUB_ACTIONS") else problem, file=sys.stderr)
    if problems:
        return 1
    print("Deploy readiness checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
