#!/usr/bin/env python3
"""Checks the packaged help text catalogs (ADR-0164 help-text-json).

Help and guidance prose lives in one JSON static resource per package, BarnHelp_<Package>
(packages/<dir>/main/default/staticresources/BarnHelp_<Package>.json), shaped
{"languages": ["en", ...], "texts": {"<key>": "<text>"}}, not in custom labels: every label
of an unmanaged or source install counts toward the org's 5,000. A translation is
BarnHelp_<Package>_<language>.json, listed in the English file's "languages".

Fails when:
- a catalog is not that shape, sits in another package's folder, or holds an empty text;
- any text holds an em or en dash;
- code names a key its catalog does not hold: helpText('<Package>', '<key>') in JavaScript,
  BarnHelp.text('<Package>', '<key>') in Apex, help-package="<Package>" help-key="<key>" in
  markup (a missing key shows nothing, so only this check notices);
- a call names its package or key with anything but a quoted literal (outside the loader
  itself), so neither this check nor a reader could find it;
- code reads another module's catalog (only its own package's and Core's are certain to be
  installed);
- an English key is used nowhere, a translation holds a key English does not, or a key is
  also a custom label.
"""

import glob
import json
import os
import re
import subprocess
import sys

PACKAGES = {
    "core": "Core",
    "rollups": "Rollups",
    "giving": "Giving",
    "volunteers": "Volunteers",
    "programs": "Programs",
    "logicmodels": "LogicModels",
    "funders": "Funders",
    "forms": "Forms",
    "contactpoints": "ContactPoints",
    "events": "Events",
    "portal": "Portal",
    "mirror": "Mirror",
    "corporatehub": "CorporateHub",
}
DASHES = (chr(0x2014), chr(0x2013))  # em and en dash, written by code point
LOADER_FILES = (
    "packages/core/main/default/lwc/barnHelp/",
    "packages/core/main/default/lwc/barnHelpText/",
    "packages/core/main/default/lwc/barnHelpCatalog/",
    "packages/core/main/default/classes/BarnHelp.cls",
    "packages/core/main/default/classes/BarnHelpTest.cls",
    "packages/core/test/jest-mocks/",
)
JS_CALL = re.compile(r"\bhelpText\(\s*([^,)]*?)\s*,\s*([^,)]*?)\s*[,)]")
APEX_CALL = re.compile(r"\bBarnHelp\.text\(\s*([^,)]*?)\s*,\s*([^,)]*?)\s*[,)]")
MARKUP = re.compile(r"<c-barn-help\b[^>]*>", re.S)
LITERAL = re.compile(r"^'([A-Za-z0-9_]+)'$")


def label_names():
    names = set()
    for path in glob.glob("packages/*/main/default/labels/*.labels-meta.xml"):
        names.update(re.findall(r"<fullName>\s*([A-Za-z0-9_]+)\s*</fullName>", open(path, encoding="utf-8").read()))
    return names


def load_catalogs(problems):
    english = {}
    translations = []
    for path in sorted(glob.glob("packages/*/main/default/staticresources/BarnHelp_*.json")):
        folder = path.split("/")[1]
        name = os.path.basename(path)[: -len(".json")]
        owner = PACKAGES.get(folder)
        base = "BarnHelp_" + (owner or "?")
        if name != base and not name.startswith(base + "_"):
            problems.append(f"{path}: a catalog in packages/{folder} is named {base} or {base}_<language>")
            continue
        try:
            data = json.load(open(path, encoding="utf-8"))
        except ValueError as error:
            problems.append(f"{path}: not valid JSON ({error})")
            continue
        texts = data.get("texts") if isinstance(data, dict) else None
        if not isinstance(texts, dict):
            problems.append(f'{path}: needs a "texts" object of key to text')
            continue
        for key, value in texts.items():
            if not isinstance(value, str) or not value.strip():
                problems.append(f"{path}: {key} has no text")
            elif any(dash in value for dash in DASHES):
                problems.append(f"{path}: {key} holds an em or en dash; use a colon, comma or parentheses")
        if name == base:
            languages = data.get("languages")
            if not isinstance(languages, list) or "en" not in languages:
                problems.append(f'{path}: needs "languages" listing "en" and every translation')
                languages = ["en"]
            english[owner] = {"path": path, "texts": texts, "languages": languages}
        else:
            translations.append((path, owner, name[len(base) + 1:], texts))
    for path, owner, language, texts in translations:
        base = english.get(owner)
        if not base:
            problems.append(f"{path}: a translation with no English BarnHelp_{owner}.json")
            continue
        if language not in base["languages"]:
            problems.append(f'{path}: "{language}" is not in {base["path"]} "languages", so it is never read')
        for key in sorted(set(texts) - set(base["texts"])):
            problems.append(f"{path}: {key} is not in the English catalog")
    return english


def references(problems):
    files = subprocess.run(["git", "ls-files", "packages"], capture_output=True, text=True, check=True).stdout.split()
    found = []
    for path in files:
        if not path.endswith((".js", ".cls", ".html")):
            continue
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        loader = path.startswith(LOADER_FILES)
        calls = []
        if path.endswith(".js"):
            calls = JS_CALL.findall(text)
        elif path.endswith(".cls"):
            calls = APEX_CALL.findall(text)
        for pkg, key in calls:
            p, k = LITERAL.match(pkg), LITERAL.match(key)
            if p and k:
                found.append((path, p.group(1), k.group(1)))
            elif not loader:
                problems.append(f"{path}: help text named by {pkg}, {key}; write the package and key as quoted literals")
        if path.endswith(".html"):
            for tag in MARKUP.findall(text):
                key = re.search(r'help-key="([A-Za-z0-9_]+)"', tag)
                if key:
                    pkg = re.search(r'help-package="([A-Za-z0-9_]+)"', tag)
                    found.append((path, pkg.group(1) if pkg else "Core", key.group(1)))
                elif "help-key=" in tag:
                    problems.append(f"{path}: help-key must be a literal key, not an expression")
    return found


def main():
    problems = []
    english = load_catalogs(problems)
    labels = label_names()
    used = set()
    for path, pkg, key in references(problems):
        folder = path.split("/")[1]
        if pkg not in PACKAGES.values():
            problems.append(f"{path}: {pkg} is not a package with a help catalog")
            continue
        if pkg not in ("Core", PACKAGES.get(folder)) and not path.startswith(LOADER_FILES):
            problems.append(f"{path}: reads {pkg} help, but only its own package's and Core's are sure to be installed")
        if path.startswith(LOADER_FILES):
            continue  # the loader's own tests use example keys
        used.add((pkg, key))
        if key not in english.get(pkg, {}).get("texts", {}):
            problems.append(f"{path}: help key {key} is not in BarnHelp_{pkg}.json")
    for pkg, catalog in sorted(english.items()):
        for key in sorted(catalog["texts"]):
            if (pkg, key) not in used:
                problems.append(f"{catalog['path']}: {key} is used nowhere; remove it")
            if key in labels:
                problems.append(f"{catalog['path']}: {key} is also a custom label; keep one")

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-help-text.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    total = sum(len(c["texts"]) for c in english.values())
    print(f"check-help-text.py: OK, {total} help texts in {len(english)} catalogs, every key used and present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
