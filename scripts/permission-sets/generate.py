#!/usr/bin/env python3
"""Generates each package's Admin and Read Only permission sets from its Staff set (D-200 S9a).

Every package with a role trio (ADR-0194) ships `<Prefix>_Staff`, `<Prefix>_Admin` and
`<Prefix>_Read_Only`. The Admin and Read Only sets are the Staff set plus a small delta, kept in
`scripts/permission-sets/deltas/<Prefix>.json`. The committed XML stays the deployed source: this
script writes it, nothing builds it at deploy time, and ADR-0194's permission model is unchanged.

A delta, per derived set (`Admin`, `Read_Only`):

- `label`, `description`: the set's own words.
- `readOnly`: true takes every create, edit, delete and Modify All grant and every field edit
  away, the Read Only rule; the entries below then record where the set differs from the rule.
- `set`: per section (`objectPermissions`, `fieldPermissions`, `tabSettings`, ...), per entry,
  the values that differ from the Staff entry (after the rule).
- `add`: per section, per entry, the whole entry the Staff set does not have.
- `remove`: per section, the entries of the Staff set this set leaves out.

Output is deterministic: sections in metadata order, entries by name, values by name, the way
the committed files are written.

  python3 scripts/permission-sets/generate.py           writes the derived sets
  python3 scripts/permission-sets/generate.py --check   fails when a committed set differs
  python3 scripts/permission-sets/generate.py --bootstrap PREFIX
      writes the delta that reproduces today's committed sets for PREFIX, to start one
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DELTAS = os.environ.get("PERMISSION_SET_DELTAS") or os.path.join(ROOT, "scripts", "permission-sets", "deltas")
DERIVED = ("Admin", "Read_Only")
# Each section's naming element; sections are written in this (alphabetical) order.
SECTIONS = {
    "applicationVisibilities": "application",
    "classAccesses": "apexClass",
    "customPermissions": "name",
    "externalCredentialPrincipalAccesses": "externalCredentialPrincipal",
    "fieldPermissions": "field",
    "objectPermissions": "object",
    "tabSettings": "tab",
    "userPermissions": "name",
}
HEADER = ("hasActivationRequired", "label", "description")
READ_ONLY_RULE = {
    "objectPermissions": {
        "allowCreate": "false",
        "allowDelete": "false",
        "allowEdit": "false",
        "modifyAllRecords": "false",
    },
    "fieldPermissions": {"editable": "false"},
}
WIDTH = 100
BLOCK = re.compile(r"^  <(\w+)>(.*?)</\1>\n", re.S | re.M)
VALUE = re.compile(r"<(\w+)>([^<]*)</\1>")


def unescape(text):
    return text.replace("&lt;", "<").replace("&gt;", ">").replace("&apos;", "'").replace("&quot;", '"').replace("&amp;", "&")


def escape(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def parse(path):
    """The set's header values and its sections: {section: {name: {element: value}}}."""
    text = open(path, encoding="utf-8").read()
    header, sections = {}, {}
    for match in BLOCK.finditer(text):
        tag, body = match.group(1), match.group(2)
        if tag in SECTIONS:
            values = dict(VALUE.findall(body))
            sections.setdefault(tag, {})[values[SECTIONS[tag]]] = values
        elif tag in HEADER:
            # A wrapped description keeps its lines, so regenerating never rewraps it.
            lines = [line.strip() for line in body.split("\n") if line.strip()]
            header[tag] = [unescape(l) for l in lines] if "\n" in body else unescape(body)
        else:
            raise SystemExit(f"{path}: unexpected element {tag}")
    return header, sections


def text_element(tag, value):
    """One text element: a string on one line, a list of lines wrapped as given."""
    if isinstance(value, str):
        return f"  <{tag}>{escape(value)}</{tag}>\n"
    lines = "".join(f"    {escape(line)}\n" for line in value)
    return f"  <{tag}>\n{lines}  </{tag}>\n"


def render(header, sections):
    out = ['<?xml version="1.0" encoding="UTF-8" ?>\n', '<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">\n']
    for tag in HEADER:
        if tag in header:
            out.append(text_element(tag, header[tag]))
    for section in SECTIONS:
        for name in sections.get(section, {}):
            values = sections[section][name]
            out.append(f"  <{section}>\n")
            for element in sorted(values):
                out.append(f"    <{element}>{values[element]}</{element}>\n")
            out.append(f"  </{section}>\n")
    out.append("</PermissionSet>\n")
    return "".join(out)


def derive(staff_sections, delta):
    sections = {s: {n: dict(v) for n, v in entries.items()} for s, entries in staff_sections.items()}
    if delta.get("readOnly"):
        for section, rule in READ_ONLY_RULE.items():
            for values in sections.get(section, {}).values():
                values.update(rule)
    for section, names in delta.get("remove", {}).items():
        for name in names:
            sections[section].pop(name)
    for section, entries in delta.get("set", {}).items():
        for name, values in entries.items():
            sections[section][name].update(values)
    for section, entries in delta.get("add", {}).items():
        for name, values in entries.items():
            sections[section] = insert(sections.get(section, {}), name, {SECTIONS[section]: name, **values})
    return {s: e for s, e in sections.items() if e}


def insert(entries, name, values):
    """The entries with one more, before the first whose name sorts after it (Staff order kept)."""
    out, placed = {}, False
    for existing, existing_values in entries.items():
        if not placed and existing.lower() > name.lower():
            out[name], placed = values, True
        out[existing] = existing_values
    if not placed:
        out[name] = values
    return out


def bootstrap(staff_sections, header, sections, read_only):
    """The delta that turns the Staff set into this one."""
    delta = {"label": header["label"], "description": header.get("description")}
    if read_only:
        delta["readOnly"] = True
    base = derive(staff_sections, {"readOnly": read_only})
    for section in SECTIONS:
        ours, theirs = sections.get(section, {}), base.get(section, {})
        removed = sorted(set(theirs) - set(ours))
        if removed:
            delta.setdefault("remove", {})[section] = removed
        for name in sorted(ours):
            if name not in theirs:
                values = {k: v for k, v in ours[name].items() if k != SECTIONS[section]}
                delta.setdefault("add", {}).setdefault(section, {})[name] = values
                continue
            changed = {k: v for k, v in ours[name].items() if theirs[name].get(k) != v}
            if set(theirs[name]) - set(ours[name]):
                raise SystemExit(f"{section} {name}: an element the derived set leaves out")
            if changed:
                delta.setdefault("set", {}).setdefault(section, {})[name] = changed
    return delta


def staff_path(prefix):
    found = glob.glob(os.path.join(ROOT, "packages", "*", "main", "default", "permissionsets", f"{prefix}_Staff.permissionset-meta.xml"))
    if len(found) != 1:
        raise SystemExit(f"{prefix}: expected one {prefix}_Staff permission set, found {len(found)}")
    return found[0]


def generated(prefix):
    """{path: text} of the derived sets for one delta file."""
    staff = staff_path(prefix)
    staff_header, staff_sections = parse(staff)
    deltas = json.load(open(os.path.join(DELTAS, f"{prefix}.json"), encoding="utf-8"))
    out = {}
    for kind in DERIVED:
        delta = deltas[kind]
        header = {"hasActivationRequired": staff_header["hasActivationRequired"], "label": delta["label"]}
        if delta.get("description"):
            header["description"] = delta["description"]
        path = staff.replace("_Staff.", f"_{kind}.")
        out[path] = render(header, derive(staff_sections, delta))
    return out


def prefixes():
    return sorted(os.path.basename(p)[: -len(".json")] for p in glob.glob(os.path.join(DELTAS, "*.json")))


def dumps(value, depth=0):
    """JSON with one line per entry: objects nest to the entry, and an entry's values stay inline."""
    leaf = not isinstance(value, dict) or all(not isinstance(v, (dict, list)) for v in value.values())
    if leaf or depth >= 4:
        return json.dumps(value, ensure_ascii=False) + ("\n" if depth == 0 else "")
    pad = "  " * (depth + 1)
    items = [f"{pad}{json.dumps(k)}: {dumps(v, depth + 1)}" for k, v in value.items()]
    text = "{\n" + ",\n".join(items) + "\n" + "  " * depth + "}"
    return text + ("\n" if depth == 0 else "")


def target(path, out):
    """Where to write a file: in place, or under --out at the same relative path."""
    if not out:
        return path
    moved = os.path.join(out, os.path.relpath(path, ROOT))
    os.makedirs(os.path.dirname(moved), exist_ok=True)
    return moved


def main(argv):
    out = None
    if "--out" in argv:
        at = argv.index("--out")
        out = os.path.abspath(argv[at + 1])
        argv = argv[:at] + argv[at + 2 :]
    if argv[:1] == ["--bootstrap"]:
        for prefix in argv[1:]:
            staff = staff_path(prefix)
            _, staff_sections = parse(staff)
            deltas = {}
            for kind in DERIVED:
                header, sections = parse(staff.replace("_Staff.", f"_{kind}."))
                deltas[kind] = bootstrap(staff_sections, header, sections, kind == "Read_Only")
            with open(target(os.path.join(DELTAS, f"{prefix}.json"), out), "w", encoding="utf-8") as handle:
                handle.write(dumps(deltas))
        return 0
    check = argv[:1] == ["--check"]
    stale = []
    for prefix in prefixes():
        for path, text in generated(prefix).items():
            current = open(path, encoding="utf-8").read() if os.path.exists(path) else None
            if current == text:
                continue
            if check:
                stale.append(os.path.relpath(path, ROOT))
            else:
                with open(target(path, out), "w", encoding="utf-8") as handle:
                    handle.write(text)
    if stale:
        for path in stale:
            print(f"{path}: differs from its Staff set plus its delta; run scripts/permission-sets/generate.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
