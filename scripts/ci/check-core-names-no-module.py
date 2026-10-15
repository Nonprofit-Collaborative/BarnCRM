#!/usr/bin/env python3
"""Fails if Core names a class, component, object, field, label, tab, app or permission set
another package ships.

Core installs alone and depends on no module (plan Section 4.1, ADR-0003, ADR-NEXT
`NEXT-rollup-builder-module.md`). It reaches a module only by name at run time
(`HealthCheckExtensions`, `NightlyJobs`, `RollupEngineExtensions` and the other resolvers),
and those names are string literals. A static reference compiles or deploys only where the
module is installed, so a Core-only deploy would fail, and nothing else would notice until it
did. So:

- Core's Apex, with comments and string literals blanked, names no module class, object,
  field or label.
- Core's components import no module component, Apex, object, field or label.
- Core's metadata XML names no module class, object, field, label, tab, app or permission set.
- Core's Apex string literals name no module object, app or permission set, except in the
  files listed in ALLOWED_LITERALS, each of which holds such names as data on purpose.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

CORE = "packages/core"

# Core files whose string literals name module objects, apps or permission sets on purpose:
# names resolved by describe or by name at run time, never statically.
ALLOWED_LITERALS = {
    "ModuleManagerService.cls": "each module's owned objects and admin permission set (C-24)",
    "TestUsers.cls": "the module admin sets a test admin holds when the module is installed",
    "ModuleDetectionService.cls": "the detection-only probe objects for Giving (ADR-0009)",
    "ModuleDetectionServiceTest.cls": "asserts the detection probes",
    "NamespaceUtilTest.cls": "resolves a module object name without the module",
}

KINDS = ("class", "component", "object", "field", "label", "tab", "app", "permission set")


def files(package, pattern):
    return glob.glob(os.path.join(package, "**", pattern), recursive=True)


def suffixed(paths, suffix):
    return {os.path.basename(path)[: -len(suffix)] for path in paths}


def names_in(packages):
    """What the given packages ship, by kind. Fields are (object, field) pairs."""
    found = {kind: set() for kind in KINDS}
    for package in packages:
        found["class"] |= suffixed(files(package, "*.cls"), ".cls")
        found["class"] |= suffixed(files(package, "*.trigger"), ".trigger")
        found["component"] |= {
            os.path.basename(os.path.dirname(path))
            for path in files(package, os.path.join("lwc", "*", "*.js-meta.xml"))
        }
        found["object"] |= {
            os.path.basename(os.path.normpath(path))
            for path in files(package, os.path.join("objects", "*", ""))
        }
        for path in files(package, os.path.join("objects", "*", "fields", "*.field-meta.xml")):
            parent = os.path.basename(os.path.dirname(os.path.dirname(path)))
            found["field"].add((parent, os.path.basename(path)[: -len(".field-meta.xml")]))
        for path in files(package, os.path.join("labels", "*.labels-meta.xml")):
            text = open(path, encoding="utf-8").read()
            found["label"] |= set(re.findall(r"<fullName>([^<]+)</fullName>", text))
        found["tab"] |= suffixed(files(package, os.path.join("tabs", "*.tab-meta.xml")), ".tab-meta.xml")
        found["app"] |= suffixed(
            files(package, os.path.join("applications", "*.app-meta.xml")), ".app-meta.xml"
        )
        found["permission set"] |= suffixed(
            files(package, os.path.join("permissionsets", "*.permissionset-meta.xml")),
            ".permissionset-meta.xml",
        )
    return found


def module_names():
    """What the non-Core packages ship and Core does not."""
    modules = [p for p in sorted(glob.glob("packages/*/")) if os.path.normpath(p) != CORE]
    shipped = names_in(modules)
    core = names_in([CORE])
    for kind in KINDS:
        shipped[kind] -= core[kind]
    # Custom objects only: a module's folder for a standard object (Account) holds its fields.
    shipped["object"] = {name for name in shipped["object"] if re.search(r"__(c|e|mdt)$", name)}
    # A field name Core also uses on one of its own objects is not a module name.
    core_field_names = {name for _, name in core["field"]}
    shipped["field"] = {
        (parent, name)
        for parent, name in shipped["field"]
        if name.endswith("__c") and name not in core_field_names
    }
    return shipped


def word_pattern(words):
    if not words:
        return None
    alternatives = "|".join(sorted(map(re.escape, words), key=len, reverse=True))
    return re.compile(r"(?<![A-Za-z0-9_])(" + alternatives + r")(?![A-Za-z0-9_])")


def kind_of(names, name):
    for kind in ("class", "object", "label", "tab", "app", "permission set"):
        if name in names[kind]:
            return kind
    return "field"


def string_literals(source):
    """Each string literal of the Apex source with its line number, comments left out."""
    stripped = strip(source)
    i = 0
    while i < len(source):
        if source[i] == "'" and stripped.startswith("''", i):
            j = i + 1
            while j < len(source) and source[j] != "'":
                j += 2 if source[j] == "\\" else 1
            yield source.count("\n", 0, i) + 1, source[i + 1 : j]
            i = j + 1
        else:
            i += 1


def check_apex(names, problems):
    field_names = {name for _, name in names["field"]}
    static = word_pattern(names["class"] | names["object"] | field_names | names["label"])
    in_literals = word_pattern(names["object"] | names["app"] | names["permission set"])
    for path in sorted(files(CORE, "*.cls") + files(CORE, "*.trigger")):
        source = open(path, encoding="utf-8").read()
        if static:
            for number, line in enumerate(strip(source).split("\n"), 1):
                for name in sorted(set(static.findall(line))):
                    problems.append(f"{path}:{number}: names module {kind_of(names, name)} {name}")
        if in_literals and os.path.basename(path) not in ALLOWED_LITERALS:
            for number, literal in string_literals(source):
                for name in sorted(set(in_literals.findall(literal))):
                    problems.append(
                        f"{path}:{number}: string literal names module "
                        f"{kind_of(names, name)} {name}"
                    )


def kebab(name):
    return re.sub(r"([A-Z])", lambda m: "-" + m.group(1).lower(), name)


def check_components(names, problems):
    lwc_files = files(CORE, os.path.join("lwc", "*", "*.js")) + files(
        CORE, os.path.join("lwc", "*", "*.html")
    )
    field_refs = {f"{parent}.{name}" for parent, name in names["field"]}
    for path in sorted(lwc_files):
        if "__tests__" in path:
            continue
        text = open(path, encoding="utf-8").read()
        for name in sorted(names["component"]):
            if re.search(r"['\"]c/" + re.escape(name) + r"['\"]", text) or (
                path.endswith(".html") and re.search(r"<c-" + re.escape(kebab(name)) + r"[\s>]", text)
            ):
                problems.append(f"{path}: uses module component {name}")
        for name in sorted(names["class"]):
            if f"@salesforce/apex/{name}." in text:
                problems.append(f"{path}: calls module Apex {name}")
        for ref in re.findall(r"@salesforce/schema/([A-Za-z0-9_.]+)", text):
            if ref.split(".")[0] in names["object"] or ref in field_refs:
                problems.append(f"{path}: imports module schema {ref}")
        for label in re.findall(r"@salesforce/label/c\.([A-Za-z0-9_]+)", text):
            if label in names["label"]:
                problems.append(f"{path}: imports module label {label}")


def check_metadata(names, problems):
    field_refs = {f"{parent}.{name}" for parent, name in names["field"]}
    words = word_pattern(names["class"] | names["object"] | field_refs | names["label"])
    tags = {
        "tab": re.compile(r"<tab>\s*([^<\s]+)\s*</tab>"),
        "app": re.compile(r"<application>\s*([^<\s]+)\s*</application>"),
        "permission set": re.compile(r"<permissionSets>\s*([^<\s]+)\s*</permissionSets>"),
    }
    for path in sorted(files(CORE, "*.xml")):
        text = open(path, encoding="utf-8").read()
        for number, line in enumerate(text.split("\n"), 1):
            if words:
                for name in sorted(set(words.findall(line))):
                    problems.append(f"{path}:{number}: names module {kind_of(names, name)} {name}")
            for kind, tag in tags.items():
                for name in tag.findall(line):
                    if name in names[kind]:
                        problems.append(f"{path}:{number}: names module {kind} {name}")


def main():
    names = module_names()
    problems = []
    check_apex(names, problems)
    check_components(names, problems)
    check_metadata(names, problems)
    for problem in problems:
        print(problem)
    if problems:
        print(f"check-core-names-no-module.py: FAILED, {len(problems)} reference(s) above")
        return 1
    counts = ", ".join(f"{kind} {len(names[kind])}" for kind in KINDS)
    print(f"check-core-names-no-module.py: OK, Core names no module name ({counts})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
