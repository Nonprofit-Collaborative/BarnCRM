#!/usr/bin/env python3
"""Exports BarnCRM records from a pilot org and reimports them after the managed install.

C-31, ADR-0088 (0088-unlocked-to-managed-migration-kit.md). The administrator's procedure is
docs/admin-guide/moving-to-managed-packages.md; how this works is
docs/contributor-guide/migration-kit.md.

  check     names every mapped field the org does not show to this user
  export    writes one CSV per object, without namespace, into --out
  reimport  loads the export back, translating every record Id, resumably
  verify    exports again and compares, record by record, through the Id map

Every org call goes through the Salesforce CLI (`sf`). Nothing here creates a package version.
"""

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import tempfile

API_VERSION = "67.0"
BATCH = 200
AUDIT_FIELDS = ["CreatedDate", "CreatedById", "LastModifiedDate", "LastModifiedById"]
NUMBER_TYPES = ("Currency", "Number", "Percent")
TEXT_TYPES = ("Text", "TextArea", "LongTextArea")
ID_PATTERN = re.compile(r"^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$")
RECORD_TYPE = "RecordType.DeveloperName"
csv.field_size_limit(sys.maxsize)


class Sf:
    """The Salesforce CLI, one org. Tests replace it with a fake."""

    def __init__(self, org):
        self.org = org

    def _run(self, args, body=None):
        command = ["sf", *args, "--target-org", self.org]
        result = subprocess.run(command, capture_output=True, text=True, input=body)
        if result.returncode != 0:
            raise SystemExit(f"sf {args[0]} {args[1]} failed: {result.stderr.strip() or result.stdout.strip()}")
        return result.stdout

    def describe(self, sobject):
        out = json.loads(self._run(["sobject", "describe", "--sobject", sobject, "--json"]))
        return {f["name"]: f for f in out["result"]["fields"]}

    def export(self, query, path):
        self._run(["data", "export", "bulk", "--query", query, "--output-file", path, "--result-format", "csv",
                   "--wait", "120", "--json"])
        return read_csv(path)

    def query(self, query):
        return json.loads(self._run(["data", "query", "--query", query, "--json"]))["result"]["records"]

    def rest(self, method, path, body):
        url = f"/services/data/v{API_VERSION}/{path}"
        args = ["api", "request", "rest", url, "--method", method, "--header", "Content-Type: application/json",
                "--body", "-"]
        return json.loads(self._run(args, body=json.dumps(body)))


def ns(name, namespace):
    """The org's API name for a mapped name: packaged custom names get the namespace."""
    if namespace and name.endswith("__c") and name.count("__") == 1:
        return f"{namespace}__{name}"
    return name


def strip_ns(name, namespace):
    return name[len(namespace) + 2:] if namespace and name.startswith(namespace + "__") else name


def read_csv(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv(path, rows, columns):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def columns(entry, audit=True):
    """Every column exported for one mapping entry, unprefixed."""
    cols = ["Id"]
    if entry["name_field"] == "text":
        cols.append("Name")
    if entry["owner"]:
        cols.append("OwnerId")
    if entry["record_types"]:
        cols.append(RECORD_TYPE)
    cols += [f["name"] for f in entry["fields"]]
    if audit and entry["kind"] == "custom":
        cols += AUDIT_FIELDS
    return cols


def key15(value):
    return value[:15] if value and ID_PATTERN.match(value) else None


class Kit:
    def __init__(self, sf, mapping, namespace, folder):
        self.sf, self.mapping, self.namespace, self.folder = sf, mapping, namespace, folder
        os.makedirs(folder, exist_ok=True)

    def path(self, name):
        return os.path.join(self.folder, name)

    # check ---------------------------------------------------------------------------------
    def check(self, writable=False):
        problems = []
        for entry in self.mapping["objects"]:
            api = ns(entry["name"], self.namespace)
            fields = self.sf.describe(api)
            for col in columns(entry, audit=False)[1:]:
                name = "RecordTypeId" if col == RECORD_TYPE else ns(col, self.namespace)
                field = fields.get(name)
                if field is None:
                    problems.append(f"{api}.{name}: not visible to this user")
                elif writable and not (field.get("updateable") if entry["kind"] == "standard"
                                       else field.get("createable")):
                    problems.append(f"{api}.{name}: this user cannot write it")
        return problems

    # export --------------------------------------------------------------------------------
    def export_object(self, entry, folder):
        api = ns(entry["name"], self.namespace)
        cols = columns(entry)
        select = ", ".join(c if c == RECORD_TYPE else ns(c, self.namespace) for c in cols)
        path = os.path.join(folder, entry["name"] + ".csv")
        rows = self.sf.export(f"SELECT {select} FROM {api}", path)
        rows = [{strip_ns(k, self.namespace): v for k, v in row.items()} for row in rows]
        rows.sort(key=lambda r: (r.get("CreatedDate", ""), r["Id"]))
        write_csv(path, rows, cols)
        return rows

    def export(self, folder=None):
        folder = folder or self.folder
        os.makedirs(folder, exist_ok=True)
        counts, ids = {}, []
        for entry in self.mapping["objects"]:
            rows = self.export_object(entry, folder)
            counts[entry["name"]] = len(rows)
            if entry["kind"] == "custom":
                ids += [r["Id"] for r in rows]
        if folder == self.folder:
            self.export_settings()
            for related in self.mapping["related"]:
                counts[related["object"]] = self.export_related(related, ids)
        return counts

    def export_settings(self):
        lines = []
        for entry in self.mapping["settings"]:
            api = ns(entry["name"], self.namespace)
            select = ", ".join(["SetupOwnerId"] + [ns(f["name"], self.namespace) for f in entry["fields"]])
            try:
                records = self.sf.query(f"SELECT {select} FROM {api}")
            except SystemExit as error:
                lines.append({"setting": entry["name"], "owner": "", "field": "", "value": f"not readable: {error}"})
                continue
            for record in records:
                for field in entry["fields"]:
                    value = record.get(ns(field["name"], self.namespace))
                    lines.append({"setting": entry["name"], "owner": record.get("SetupOwnerId"),
                                  "field": field["name"], "value": "" if value is None else value})
        write_csv(self.path("settings.csv"), lines, ["setting", "owner", "field", "value"])

    def export_related(self, related, ids):
        name, link = related["object"], related["link_field"]
        cols = ["Id", link] + related["fields"]
        rows = []
        for start in range(0, len(ids), BATCH):
            quoted = ", ".join(f"'{i}'" for i in ids[start:start + BATCH])
            rows += self.sf.query(f"SELECT {', '.join(cols)} FROM {name} WHERE {link} IN ({quoted})")
        write_csv(self.path(name + ".csv"), rows, cols)
        return len(rows)

    # reimport ------------------------------------------------------------------------------
    def load_id_map(self):
        id_map = {}
        for row in read_csv(self.path("id-map.csv")):
            id_map[key15(row["source_id"])] = row["target_id"]
        return id_map

    def record_types(self):
        clause = f"= '{self.namespace}'" if self.namespace else "= null"
        rows = self.sf.query(f"SELECT Id, DeveloperName, SobjectType FROM RecordType WHERE NamespacePrefix {clause}")
        return {(r["SobjectType"], r["DeveloperName"]): r["Id"] for r in rows}

    def value(self, field, raw):
        if raw in (None, ""):
            return None
        if field["type"] == "Checkbox":
            return raw.lower() == "true"
        if field["type"] in NUMBER_TYPES:
            return float(raw)
        return raw

    def reimport(self, keep_audit=False):
        id_map = self.load_id_map()
        position = {}  # every copied record's source Id, to the index of its object in load order
        for index, entry in enumerate(self.mapping["objects"]):
            if entry["kind"] == "custom":
                for row in read_csv(self.path(entry["name"] + ".csv")):
                    position[key15(row["Id"])] = index
        record_types = self.record_types()
        id_log = open(self.path("id-map.csv"), "a", newline="", encoding="utf-8")
        log = csv.writer(id_log)
        if id_log.tell() == 0:
            log.writerow(["object", "source_id", "target_id"])
        refused, summary, new = [], {}, set()  # new: source Ids first mapped by this run

        # Pass one: every record, with any Id it holds translated if that record is loaded already.
        for index, entry in enumerate(self.mapping["objects"]):
            api = ns(entry["name"], self.namespace)
            records = []
            for row in read_csv(self.path(entry["name"] + ".csv")):
                if entry["kind"] == "standard" or key15(row["Id"]) not in id_map:
                    record = self.first_pass_record(entry, api, row, id_map, position, record_types, keep_audit)
                    if record:
                        records.append((row["Id"], record))
            loaded = self.send(entry, api, records, refused)
            for source, target in loaded:
                if entry["kind"] == "custom":
                    id_map[key15(source)] = target
                    new.add(key15(source))
                    log.writerow([entry["name"], source, target])
            id_log.flush()
            summary[entry["name"]] = (len(loaded), len(records) - len(loaded))

        # Pass two: an Id left blank in pass one because its record loaded later (a cycle, a self
        # lookup, an object loaded later), or because its record was refused by an earlier run.
        for index, entry in enumerate(self.mapping["objects"]):
            api = ns(entry["name"], self.namespace)
            updates = []
            for row in read_csv(self.path(entry["name"] + ".csv")):
                source = key15(row["Id"])
                target = row["Id"] if entry["kind"] == "standard" else id_map.get(source)
                if not target:
                    continue
                record = {"attributes": {"type": api}, "Id": target}
                for field in entry["fields"]:
                    key = key15(row.get(field["name"]))
                    if key not in id_map or field["type"] == "MasterDetail" or not holds_id(field):
                        continue
                    if position.get(key, -1) >= index or (key in new and source not in new):
                        record[ns(field["name"], self.namespace)] = id_map[key]
                if len(record) > 2:
                    updates.append((row["Id"], record))
            linked = self.send(entry, api, updates, refused, update=True)
            if len(linked) < len(updates):  # a refused fill-in leaves a lookup blank: count it
                loaded, failed = summary.get(entry["name"], (0, 0))
                summary[entry["name"]] = (loaded, failed + len(updates) - len(linked))

        for related in self.mapping["related"]:
            summary[related["object"]] = self.reimport_related(related, id_map, log, refused)
        id_log.close()
        write_csv(self.path("refused.csv"), refused, ["object", "source_id", "errors"])
        return summary

    def first_pass_record(self, entry, api, row, id_map, position, record_types, keep_audit):
        """One export row as a record to send, or None for a person or organization row that
        carries nothing BarnCRM added."""
        record = {"attributes": {"type": api}}
        if entry["kind"] == "standard":
            record["Id"] = row["Id"]
        if entry["name_field"] == "text" and row.get("Name"):
            record["Name"] = row["Name"]
        if entry["owner"] and row.get("OwnerId"):
            record["OwnerId"] = row["OwnerId"]
        if record_types.get((entry["name"], row.get(RECORD_TYPE))):
            record["RecordTypeId"] = record_types[(entry["name"], row[RECORD_TYPE])]
        if keep_audit and entry["kind"] == "custom":
            record.update({f: row[f] for f in AUDIT_FIELDS if row.get(f)})
        for field in entry["fields"]:
            raw = row.get(field["name"])
            key = key15(raw)
            if holds_id(field) and key in position:
                raw = id_map.get(key)  # blank until pass two when its record is not loaded yet
            record[ns(field["name"], self.namespace)] = self.value(field, raw)
        if entry["kind"] == "standard" and all(
            v in (None, False) for k, v in record.items() if k not in ("attributes", "Id")
        ):
            return None
        return record

    def send(self, entry, api, records, refused, update=False):
        """Loads (source_id, record) pairs 200 at a time; returns (source_id, new_id) pairs."""
        loaded = []
        key = entry.get("upsert_key")
        for start in range(0, len(records), BATCH):
            chunk = records[start:start + BATCH]
            body = {"allOrNone": False, "records": [r for _, r in chunk]}
            if update or entry["kind"] == "standard":
                results = self.sf.rest("PATCH", "composite/sobjects", body)
            elif key and all(r.get(ns(key, self.namespace)) for _, r in chunk):
                results = self.sf.rest("PATCH", f"composite/sobjects/{api}/{ns(key, self.namespace)}", body)
            elif key:  # a mixed chunk: keyed rows upsert, unkeyed rows insert, order kept
                keyed = [pair for pair in chunk if pair[1].get(ns(key, self.namespace))]
                plain = [pair for pair in chunk if not pair[1].get(ns(key, self.namespace))]
                loaded += self.send(entry, api, keyed, refused) + self.send(dict(entry, upsert_key=None), api,
                                                                            plain, refused)
                continue
            else:
                results = self.sf.rest("POST", "composite/sobjects", body)
            for (source, _), result in zip(chunk, results):
                if result.get("success"):
                    loaded.append((source, result.get("id")))
                else:
                    errors = "; ".join(e.get("message", "") for e in result.get("errors", []))
                    refused.append({"object": entry["name"], "source_id": source, "errors": errors})
        return loaded

    def reimport_related(self, related, id_map, log, refused):
        name, link = related["object"], related["link_field"]
        records = []
        for row in read_csv(self.path(name + ".csv")):
            if key15(row["Id"]) in id_map:
                continue
            target = id_map.get(key15(row[link]))
            if not target:
                refused.append({"object": name, "source_id": row["Id"], "errors": "its record was not loaded"})
                continue
            record = {"attributes": {"type": name}, link: target}
            record.update({f: row[f] for f in related["fields"] if row.get(f) not in (None, "")})
            records.append((row["Id"], record))
        entry = {"name": name, "kind": "related"}
        loaded = self.send(entry, name, records, refused)
        for source, target in loaded:
            id_map[key15(source)] = target
            log.writerow([name, source, target])
        return (len(loaded), len(records) - len(loaded))

    # verify --------------------------------------------------------------------------------
    def verify(self):
        id_map = self.load_id_map()
        after = os.path.join(self.folder, "verify")
        self.export(after)
        differences = []
        for entry in self.mapping["objects"]:
            now = {r["Id"][:15]: r for r in read_csv(os.path.join(after, entry["name"] + ".csv"))}
            for row in read_csv(self.path(entry["name"] + ".csv")):
                target = row["Id"] if entry["kind"] == "standard" else id_map.get(key15(row["Id"]))
                current = now.get((target or "")[:15])
                if current is None:
                    differences.append({"object": entry["name"], "source_id": row["Id"], "field": "",
                                        "expected": "the record", "found": "nothing"})
                    continue
                for field in [{"name": c, "type": "Text"} for c in ("Name", RECORD_TYPE)
                              if c in columns(entry, audit=False)] + entry["fields"]:
                    expected, found = row.get(field["name"], ""), current.get(field["name"], "")
                    if key15(expected) in id_map:
                        expected = id_map[key15(expected)]
                    if not same(field, expected, found):
                        differences.append({"object": entry["name"], "source_id": row["Id"], "field": field["name"],
                                            "expected": expected, "found": found})
        write_csv(self.path("verify-differences.csv"), differences,
                  ["object", "source_id", "field", "expected", "found"])
        return differences


def holds_id(field):
    """A lookup, or a text field that may hold a record Id as text (ADR-0014)."""
    return bool(field.get("reference_to")) or field["type"] in TEXT_TYPES


def same(field, expected, found):
    if field["type"] in NUMBER_TYPES and expected and found:
        return abs(float(expected) - float(found)) < 1e-9
    if key15(expected) and key15(found):
        return expected[:15] == found[:15]
    return (expected or "") == (found or "")


def main(argv=None, sf_factory=Sf):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=["check", "export", "reimport", "verify"])
    parser.add_argument("--org", required=True, help="the org alias given to sf org login")
    parser.add_argument("--mapping", required=True, help="the file build_mapping.py wrote")
    parser.add_argument("--namespace", default="", help="the installed packages' namespace; empty for none")
    parser.add_argument("--out", "--in", dest="folder", default="pilot-export", help="the export folder")
    parser.add_argument("--writable", action="store_true", help="check: also check this user can write")
    parser.add_argument("--keep-audit-fields", action="store_true", help="reimport: keep created and modified stamps")
    args = parser.parse_args(argv)
    with open(args.mapping, encoding="utf-8") as handle:
        mapping = json.load(handle)
    kit = Kit(sf_factory(args.org), mapping, args.namespace, args.folder)
    if args.command == "check":
        problems = kit.check(args.writable)
        print("\n".join(problems) or "Every mapped field is visible.")
        return 1 if problems else 0
    if args.command == "export":
        for name, count in kit.export().items():
            print(f"{name}: {count} exported")
        return 0
    if args.command == "reimport":
        summary = kit.reimport(args.keep_audit_fields)
        for name, (loaded, failed) in summary.items():
            print(f"{name}: {loaded} loaded, {failed} refused")
        failed = sum(f for _, f in summary.values())
        print(f"{failed} refused in all; see {kit.path('refused.csv')}" if failed else "Nothing refused.")
        return 1 if failed else 0
    differences = kit.verify()
    print(f"{len(differences)} differences; see {kit.path('verify-differences.csv')}"
          if differences else "No differences.")
    return 1 if differences else 0


if __name__ == "__main__":
    sys.exit(main())
