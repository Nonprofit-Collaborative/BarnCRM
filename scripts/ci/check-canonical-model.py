#!/usr/bin/env python3
"""Consistency checks for docs/architecture/canonical-model.md.

Four checks, all cheap enough to run on every pull request:

1. No em dashes anywhere (house style, CLAUDE.md).
2. No API name is declared twice for the same object. Declarations live in the
   "### Salesforce implementation" subsection of each entity, in tables whose
   header row contains "API name", grouped by the bullet that introduces them.
3. Every `Something__c` name used in prose, rules, or the rollup tables was
   declared in some implementation subsection, in the settings key table, or in
   the shipped-defaults section. This is the misspelling check: a field named one
   way in an attribute table and another way in an implementation table fails
   here.
4. The reverse direction: every packaged object (any folder under
   `packages/*/main/default/objects/`) is named in the model, and every custom field
   it ships is named in backticks in a top-level section of the model that also names
   that object. A custom object, metadata type or platform event counts as named when
   its API name appears in backticks; a standard object (Account, Contact) when its
   name appears as a word. This is canonical model rule 1 ("no field without a
   canonical entry") enforced rather than reviewed: without it, a field added straight
   to the metadata silently ends the model's claim to be complete, and with it the
   portability promise (plan Section 4.4).

Exit code 1 on any finding.
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOC = os.path.join(ROOT, "docs", "architecture", "canonical-model.md")
OBJECTS = os.path.join(ROOT, "packages", "*", "main", "default", "objects", "*")
CUSTOM_SUFFIXES = ("__c", "__mdt", "__e")
FIELD_SUFFIX = ".field-meta.xml"


def packaged_objects():
    """Map each packaged object's API name to the custom fields shipped on it.

    Several packages extend the same object (Contact, Gift__c), so fields are merged.
    Files the synced folder duplicated (`name 2.ext`) are not real metadata and are
    skipped.
    """
    objects = {}
    for folder in glob.glob(OBJECTS):
        name = os.path.basename(folder)
        if " " in name or not os.path.isdir(folder):
            continue
        fields = objects.setdefault(name, set())
        for path in glob.glob(os.path.join(folder, "fields", "*" + FIELD_SUFFIX)):
            field = os.path.basename(path)[: -len(FIELD_SUFFIX)]
            if " " not in field:
                fields.add(field)
    return objects


def names_object(section, name):
    if name.endswith(CUSTOM_SUFFIXES):
        return ("`%s`" % name) in section
    return re.search(r"\b%s\b" % re.escape(name), section) is not None


def undeclared_metadata(text):
    """Findings for packaged objects and fields the model does not name (check 4)."""
    sections = re.split(r"^(?=## )", text, flags=re.M)
    findings = []
    for name, fields in sorted(packaged_objects().items()):
        mentioned = [section for section in sections if names_object(section, name)]
        if not mentioned:
            findings.append("packaged object missing from the model: %s" % name)
            continue
        for field in sorted(fields):
            if not any(("`%s`" % field) in section for section in mentioned):
                findings.append(
                    "packaged field missing from the model: %s.%s (name it in backticks in "
                    "a section that names %s)" % (name, field, name)
                )
    return findings

API = re.compile(r"`([A-Za-z][A-Za-z0-9_]*__(?:c|mdt))`")
SECTION = re.compile(r"^## (\d+)\. (.+)$")
EM_DASH = "\u2014"


def blocks(lines):
    """Yield (section title, implementation-subsection lines)."""
    title = "(preamble)"
    inside = False
    buf = []
    for line in lines:
        m = SECTION.match(line)
        if m:
            if inside:
                yield title, buf
            title, inside, buf = m.group(0)[3:].strip(), False, []
            continue
        if line.startswith("### "):
            if inside:
                yield title, buf
            inside = line.strip() == "### Salesforce implementation"
            buf = []
            continue
        if inside:
            buf.append(line)
    if inside:
        yield title, buf


def main():
    text = open(DOC, encoding="utf-8").read()
    lines = text.splitlines()
    findings = []

    for number, line in enumerate(lines, 1):
        if EM_DASH in line:
            findings.append("em dash on line %d: %s" % (number, line.strip()))

    declared = set()
    for title, body in blocks(lines):
        group = "(object)"
        seen = {}
        header_is_api = False
        for line in body:
            declared.update(API.findall(line))
            if line.startswith("- **") or line.startswith("**"):
                group = line.strip()
                seen = {}
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 2 and cells[1] == "API name":
                header_is_api = True
                continue
            if not header_is_api or len(cells) < 2 or not line.strip().startswith("|"):
                continue
            names = API.findall(cells[1])
            if not names:
                continue
            name = names[0]
            if name in seen:
                findings.append(
                    "duplicate API name %s in section %r, group %r" % (name, title, group)
                )
            seen[name] = True

    # settings keys and shipped-default field names are declared in their own sections
    for chunk in re.split(r"^## ", text, flags=re.M):
        if chunk.startswith("12. BarnCRM Settings") or chunk.startswith("13. Shipped defaults"):
            declared.update(API.findall(chunk))

    used = set(API.findall(text))
    unknown = sorted(used - declared)
    for name in unknown:
        findings.append("used but never declared: %s" % name)

    findings.extend(undeclared_metadata(text))

    if findings:
        print("canonical model check failed:")
        for finding in findings:
            print("  " + finding)
        return 1
    print("canonical model check passed: %d API names declared" % len(declared))
    return 0


if __name__ == "__main__":
    sys.exit(main())
