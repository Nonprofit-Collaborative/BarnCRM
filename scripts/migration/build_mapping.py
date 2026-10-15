#!/usr/bin/env python3
"""Builds the migration kit's export and reimport mapping from the package source.

C-31, ADR-0088 (0088-unlocked-to-managed-migration-kit.md). The mapping lists every packaged
object and field whose records an uninstall deletes, in the order reimport loads them. It is
generated, never hand-edited, so a new object or field is covered by running this again. The
only hand-kept part is overrides.json beside this file.

Names are written without a namespace. migrate.py adds the namespace at run time.

Usage: python3 scripts/migration/build_mapping.py --packages core,rollups,giving,mirror --output mapping.json
"""

import argparse
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

NS = "{http://soap.sforce.com/2006/04/metadata}"
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
STANDARD_OBJECTS = ("Account", "Contact")
REFERENCE_TYPES = ("Lookup", "MasterDetail")
NOT_LOADED_TYPES = ("Summary", "AutoNumber")


def _text(root, tag):
    node = root.find(NS + tag)
    return (node.text or "").strip() if node is not None else ""


def read_field(path):
    """One field file as a mapping entry, or None when the field is never written."""
    root = ET.parse(path).getroot()
    field_type = _text(root, "type")
    if root.find(NS + "formula") is not None or field_type in NOT_LOADED_TYPES:
        return None
    field = {"name": _text(root, "fullName"), "type": field_type}
    if field_type in REFERENCE_TYPES:
        field["reference_to"] = _text(root, "referenceTo")
        field["required"] = field_type == "MasterDetail" or _text(root, "required") == "true"
    if _text(root, "externalId") == "true" and _text(root, "unique") == "true":
        field["unique_key"] = True
    return field


def read_object(object_dir):
    """The object-level facts the mapping needs from a <Name>.object-meta.xml file."""
    name = os.path.basename(object_dir)
    meta = os.path.join(object_dir, name + ".object-meta.xml")
    facts = {"name_field": None, "setting": False}
    if not os.path.exists(meta):
        return facts
    root = ET.parse(meta).getroot()
    facts["setting"] = bool(_text(root, "customSettingsType"))
    name_field = root.find(NS + "nameField")
    if name_field is not None:
        facts["name_field"] = "auto" if _text(name_field, "type") == "AutoNumber" else "text"
    return facts


def collect(packages, repo=REPO):
    """Every packaged object with records, merged across packages, keyed by object name."""
    objects = {}
    for package in packages:
        base = os.path.join(repo, "packages", package, "main", "default", "objects")
        if not os.path.isdir(base):
            raise SystemExit(f"No package source at {base}")
        for object_dir in sorted(glob.glob(os.path.join(base, "*"))):
            name = os.path.basename(object_dir)
            if not (name.endswith("__c") or name in STANDARD_OBJECTS):
                continue  # custom metadata types and platform events hold no org records
            entry = objects.setdefault(
                name,
                {
                    "name": name,
                    "package": package,
                    "kind": "standard" if name in STANDARD_OBJECTS else "custom",
                    "name_field": None,
                    "fields": [],
                    "record_types": [],
                },
            )
            facts = read_object(object_dir)
            if facts["setting"]:
                entry["kind"] = "setting"
            if facts["name_field"]:
                entry["name_field"] = facts["name_field"]
            for path in sorted(glob.glob(os.path.join(object_dir, "fields", "*.field-meta.xml"))):
                field = read_field(path)
                if field and field["name"] not in {f["name"] for f in entry["fields"]}:
                    entry["fields"].append(field)
            for path in sorted(glob.glob(os.path.join(object_dir, "recordTypes", "*.recordType-meta.xml"))):
                entry["record_types"].append(os.path.basename(path).split(".")[0])
    return objects


def load_order(objects):
    """Custom object names, each after the objects it must find already loaded.

    A master-detail or required lookup is a hard edge. Other lookups are soft: kept when they
    can be, dropped where they form a cycle (reimport fills those in its second pass). A self
    lookup is never an edge.
    """
    names = sorted(n for n, o in objects.items() if o["kind"] == "custom")
    hard = {n: set() for n in names}
    soft = {n: set() for n in names}
    for name in names:
        for field in objects[name]["fields"]:
            target = field.get("reference_to")
            if target in hard and target != name:
                (hard if field["required"] else soft)[name].add(target)
    order, placed = [], set()
    while len(order) < len(names):
        ready = [n for n in names if n not in placed and (hard[n] | soft[n]) <= placed]
        if not ready:
            ready = [n for n in names if n not in placed and hard[n] <= placed]
        if not ready:
            stuck = [n for n in names if n not in placed]
            raise SystemExit(f"Master-detail or required lookups form a cycle among {stuck}")
        order.append(ready[0])
        placed.add(ready[0])
    return order


def build(packages, overrides, repo=REPO):
    objects = collect(packages, repo)
    skip = overrides.get("skip", {})
    upsert_keys = overrides.get("upsert_keys", {})
    skipped = [{"name": n, "reason": skip[n]} for n in sorted(objects) if n in skip]
    for name in skip:
        objects.pop(name, None)
    for name, key in upsert_keys.items():
        if name in objects:
            fields = {f["name"]: f for f in objects[name]["fields"]}
            if not fields.get(key, {}).get("unique_key"):
                raise SystemExit(f"Upsert key {name}.{key} is not a unique external Id field")
            objects[name]["upsert_key"] = key
    for entry in objects.values():
        entry["owner"] = entry["kind"] == "custom" and not any(
            f["type"] == "MasterDetail" for f in entry["fields"]
        )
    ordered = [n for n in STANDARD_OBJECTS if n in objects] + load_order(objects)
    return {
        "packages": list(packages),
        "objects": [objects[n] for n in ordered],
        "settings": [objects[n] for n in sorted(objects) if objects[n]["kind"] == "setting"],
        "related": overrides.get("related", []),
        "skipped": skipped,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--packages", required=True, help="comma separated, for example core,rollups,giving,mirror")
    parser.add_argument("--output", required=True)
    parser.add_argument("--overrides", default=os.path.join(HERE, "overrides.json"))
    args = parser.parse_args(argv)
    with open(args.overrides, encoding="utf-8") as handle:
        overrides = json.load(handle)
    mapping = build([p.strip() for p in args.packages.split(",") if p.strip()], overrides)
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(mapping, handle, indent=2)
        handle.write("\n")
    for entry in mapping["objects"]:
        print(f"copy    {entry['name']}: {len(entry['fields'])} fields")
    for entry in mapping["settings"]:
        print(f"list    {entry['name']}: settings, re-entered by hand")
    for entry in mapping["skipped"]:
        print(f"skip    {entry['name']}: {entry['reason']}")
    for entry in mapping["related"]:
        print(f"related {entry['object']} on {entry['link_field']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
