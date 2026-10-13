#!/usr/bin/env python3
"""Checks shipped metadata against platform limits that only an org deploy reports.

Each of these failed a dry-run deploy of the landing branches on 2026-10-12, after every
offline check had passed: descriptions over 255 characters on LWC bundles and FlexiPages, an
Apex test whose constant shadowed the Account type, and two quick actions with the same sort
order in a layout's action list.

Limits checked, on the XML text with leading and trailing whitespace trimmed but the line
breaks and indentation inside it counted (filterBuilder's wrapped description, 256 characters
that way, was refused; duplicateReview's, 251, deployed):
- description 255: custom permission, permission set, permission set group, FlexiPage, LWC
  bundle (js-meta), custom tab, custom application
- field label 40, field inline help 510, field and object description 1000
- custom label value 1000
- Apex class, interface and enum names that are reserved Apex type names (a class named
  Page or an enum named Type compiles locally and fails in an org, or shadows the system type)
- layout action lists: no two actions with the same sort order or the same name
- record page visibility rules: none tests a lookup field itself (the platform refuses EQUAL
  and NE on a reference field; test a field across it, such as Donor_Account__r.Name)
- dynamic related list columns: one field per valueListItems, never several in one value
"""

import glob
import html
import re
import sys

DESCRIPTION_255 = [
    "packages/*/main/default/customPermissions/*.customPermission-meta.xml",
    "packages/*/main/default/permissionsets/*.permissionset-meta.xml",
    "packages/*/main/default/permissionsetgroups/*.permissionsetgroup-meta.xml",
    "packages/*/main/default/flexipages/*.flexipage-meta.xml",
    "packages/*/main/default/lwc/*/*.js-meta.xml",
    "packages/*/main/default/tabs/*.tab-meta.xml",
    "packages/*/main/default/applications/*.app-meta.xml",
]
FIELDS = "packages/*/main/default/objects/*/fields/*.field-meta.xml"
OBJECTS = "packages/*/main/default/objects/*/*.object-meta.xml"
LABELS = "packages/*/main/default/labels/*.labels-meta.xml"
LAYOUTS = "packages/*/main/default/layouts/*.layout-meta.xml"
APEX = "packages/**/*.cls"

RESERVED_TYPE_NAMES = {
    name.lower()
    for name in [
        "Page",
        "Package",
        "Type",
        "Object",
        "Limit",
        "Group",
        "Case",
        "Sort",
        "Select",
        "Trigger",
        "System",
        "Schema",
        "Database",
    ]
}


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def top_level(text, tag):
    """The text of a tag that is a direct child of the root element, or None.

    Nested elements (a FlexiPage component's own properties, a field's value set) sit deeper
    and are skipped by cutting every element below depth one before matching.
    """
    body = re.sub(r"<\?xml.*?\?>", "", text, flags=re.DOTALL)
    body = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL)
    root = re.search(r"<(\w+)[^>]*>(.*)</\1>", body, re.DOTALL)
    if not root:
        return None
    depth = 0
    inner = root.group(2)
    for match in re.finditer(r"<(/?)(\w+)[^>]*?(/?)>", inner):
        closing, name, self_closing = match.groups()
        if closing:
            depth -= 1
        elif self_closing:
            continue
        elif depth == 0 and name == tag:
            end = inner.find(f"</{tag}>", match.end())
            return html.unescape(inner[match.end() : end]).strip() if end >= 0 else None
        else:
            depth += 1
    return None


def check_length(problems, path, text, tag, limit):
    value = top_level(text, tag)
    if value is not None and len(value) > limit:
        problems.append(f"{path}: {tag} is {len(value)} characters, over {limit}")


def check_apex(problems, path):
    source = read(path)
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    source = re.sub(r"//[^\n]*", "", source)
    source = re.sub(r"'(?:\\.|[^'\\])*'", "''", source)
    for match in re.finditer(r"\b(class|interface|enum)\s+(\w+)", source, re.IGNORECASE):
        kind, name = match.groups()
        if name.lower() in RESERVED_TYPE_NAMES:
            problems.append(f"{path}: {kind.lower()} {name} uses a reserved Apex type name")


def check_layout(problems, path):
    text = read(path)
    for block in re.findall(r"<platformActionList>(.*?)</platformActionList>", text, re.DOTALL):
        context = re.search(r"<actionListContext>(.*?)</actionListContext>", block)
        where = context.group(1) if context else "action list"
        for tag in ("sortOrder", "actionName"):
            seen = set()
            for value in re.findall(rf"<{tag}>(.*?)</{tag}>", block):
                if value in seen:
                    problems.append(f"{path}: {where} has {tag} {value} more than once")
                seen.add(value)


def check_visibility_on_lookups(problems, path):
    """A record page visibility rule cannot test a lookup itself (EQUAL and NE both refused).

    Test a field across it instead, such as `{!Record.Donor_Account__r.Name}`.
    """
    text = read(path)
    sobject = top_level(text, "sobjectType")
    if not sobject:
        return
    for field in sorted(set(re.findall(r"<leftValue>\{!Record\.(\w+)\}</leftValue>", text))):
        definitions = glob.glob(f"packages/*/main/default/objects/{sobject}/fields/{field}.field-meta.xml")
        for definition in definitions:
            kind = top_level(read(definition), "type")
            if kind in ("Lookup", "MasterDetail", "Hierarchy"):
                problems.append(
                    f"{path}: visibility rule tests lookup {field}; test {field[:-1]}r.Name instead"
                )


def check_related_list_columns(problems, path):
    """Each related list column is its own valueListItems; one value naming several is refused."""
    text = read(path)
    pattern = r"<name>relatedListFieldAliases</name>\s*<valueList>(.*?)</valueList>"
    for block in re.findall(pattern, text, re.DOTALL):
        for value in re.findall(r"<value>(.*?)</value>", block, re.DOTALL):
            if len(value.split()) > 1:
                problems.append(f"{path}: related list column '{value}' names several fields")


def main():
    problems = []
    checked = 0

    for pattern in DESCRIPTION_255:
        for path in sorted(glob.glob(pattern)):
            checked += 1
            check_length(problems, path, read(path), "description", 255)

    for path in sorted(glob.glob("packages/*/main/default/flexipages/*.flexipage-meta.xml")):
        check_visibility_on_lookups(problems, path)
        check_related_list_columns(problems, path)

    for path in sorted(glob.glob(FIELDS)):
        checked += 1
        text = read(path)
        check_length(problems, path, text, "label", 40)
        check_length(problems, path, text, "inlineHelpText", 510)
        check_length(problems, path, text, "description", 1000)

    for path in sorted(glob.glob(OBJECTS)):
        checked += 1
        check_length(problems, path, read(path), "description", 1000)

    for path in sorted(glob.glob(LABELS)):
        for block in re.findall(r"<labels>(.*?)</labels>", read(path), re.DOTALL):
            checked += 1
            name = re.search(r"<fullName>(.*?)</fullName>", block)
            value = re.search(r"<value>(.*?)</value>", block, re.DOTALL)
            if value and len(html.unescape(value.group(1))) > 1000:
                label = name.group(1) if name else "(no fullName)"
                problems.append(f"{path}: label {label} value is over 1000 characters")

    for path in sorted(glob.glob(LAYOUTS)):
        checked += 1
        check_layout(problems, path)

    for path in sorted(glob.glob(APEX, recursive=True)):
        checked += 1
        check_apex(problems, path)

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-metadata-lengths.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-metadata-lengths.py: OK, {checked} components within the platform limits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
