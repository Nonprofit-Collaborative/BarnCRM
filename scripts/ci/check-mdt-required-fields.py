#!/usr/bin/env python3
"""Fails when a custom metadata record leaves a required field of its type without a value.

The metadata API refuses such a record ("Required fields are missing"), and only at deploy time:
on 2026-11-12 Integration_App.Nonprofit_Cloud_Fundraising had no Link_Url__c and stopped the Core
config stage of the release gate on both orgs. This check finds it offline.
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "packages")


def main():
    required = {}
    for path in glob.glob(f"{ROOT}/*/main/default/objects/*__mdt/fields/*.field-meta.xml"):
        with open(path, encoding="utf-8") as handle:
            if "<required>true</required>" not in handle.read():
                continue
        type_name = path.split("/objects/")[1].split("/")[0][: -len("__mdt")]
        required.setdefault(type_name, set()).add(os.path.basename(path).split(".")[0])

    problems = []
    for path in sorted(glob.glob(f"{ROOT}/*/main/default/customMetadata/*.md-meta.xml")):
        type_name = os.path.basename(path).split(".")[0]
        if type_name not in required:
            continue
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        filled = set(re.findall(r"<field>([^<]+)</field>\s*<value(?![^>]*xsi:nil)", text))
        for field in sorted(required[type_name] - filled):
            problems.append(f"{os.path.relpath(path, os.path.join(ROOT, '..'))}: required field {field} has no value")

    for problem in problems:
        print(problem)
    if problems:
        print(f"check-mdt-required-fields.py: FAILED, {len(problems)} problem(s) above")
        return 1
    print("check-mdt-required-fields.py: OK, every custom metadata record fills its required fields")
    return 0


if __name__ == "__main__":
    sys.exit(main())
