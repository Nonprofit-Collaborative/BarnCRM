#!/usr/bin/env python3
"""Keeps the custom label count under a budget and fails on labels nothing uses.

Salesforce allows 5,000 custom labels per org. Labels in an installed managed package do not
count toward it ("Custom labels from managed packages don't count toward this limit",
Salesforce Help, Custom Labels), but every unpackaged source deploy does: barn-sales, oi-test,
barn-npc and mwdbdevsb all receive BarnCRM as source, beside each org's own labels. barn-sales
reached 4,996 on 2026-11-02 and a deploy failed with "custom label limit exceeded".

BUDGET is the total across every package directory: the count after help prose and then Core's
messages moved to the help catalogs (ADR-0164 help-text-json and D-172, 3,163 on 2026-11-04)
plus a small margin, so every label added is a choice. TARGET is where the total should settle;
above it the check passes and says by how much.

Help prose: help and guidance sentences live in the package's help catalog
(BarnHelp_<Package>.json, docs/contributor-guide/ux-kit.md, Help Text), never in a label. A
label is taken for help prose when its value is a sentence (six words or more, ending as a
sentence does) and the last word of its name is a help word (Intro, Help, Description, Hint,
Note, Notes, Empty, Why, What, Steps, Text, Tooltip, Explanation), unless the name says it is
an error or log line or the value has a {0} placeholder (a message about the current state).
PROSE_EXCEPTIONS lists the few that must stay labels, with the reason.

Unused: a label whose name appears in no file under packages/ other than the label files
(Markdown and code comments do not count). Apex, LWC, Aura, Visualforce, flows, FlexiPages
and custom metadata records all name a label in full, including the names read with
System.Label.get, so a whole-word search finds every real reference. A label referenced
only by a name built from pieces at run time would be missed: there is none, and building
one is not allowed (write the full name so this check, and a reader, can find it).
"""

import glob
import html
import re
import subprocess
import sys

# Raised from 3,215 on 2026-11-07 for Batch C's three new modules (Forms, Contact Point Sync,
# Event Management: 59 labels) and its Core and Volunteers items (C-61/C-63, C-69, V-10b); the
# check below already holds no unused label and no help prose. A module's labels reach an org
# only when that module is installed. Raised by 8 for EV-02's Registrations tab (11 short button
# and menu labels; its messages are help catalog text), and by 1 for EV-14's nightly step name
# and 1 for EV-10's.
# Batch C wave 2 landing: set to the merged total, 3,259: 17 Events labels, EV-02's Registrations
# tab and 11 button and menu labels, the EV-10 and EV-14 nightly step names, and the EV-06
# Applications, EV-09 Sponsors, EV-12 Check-In and EV-15 Appointments tab titles.
# Batch C wave 3 landing: set to the merged total, 3,261: the EV-13 Seating and EV-17 Badges tab
# titles (a flexipage tab title cannot read the help catalog).
# Batch C review: lowered to 3,255 after merging six labels that held the same name for the same
# thing (Super Importer, Opportunity Mirror, Gift Transaction Mirror, Seasonal Address Swap, "or").
BUDGET = 3255
TARGET = 3000
LABEL_FILES = "packages/*/main/default/labels/*.labels-meta.xml"

HELP_WORDS = {
    "Intro", "Help", "Description", "Hint", "Note", "Notes", "Empty", "Why", "What", "Steps",
    "Text", "Tooltip", "Explanation",
}
MESSAGE_WORDS = {"Error", "Errors", "Log"}
SENTENCE = re.compile(r"[.?!:)]\s*$|[.?!]\s+[A-Z(\"]")
PLACEHOLDER = re.compile(r"\{\d+\}")
# Sentences named like help that are content or messages, so they stay labels.
PROSE_EXCEPTIONS = {
    "Core_AiExport_ReadmeIntro": "written into the AI readiness pack's readme file",
    "Giving_AskReminder_Description": "written into the reminder task's description",
    "Core_RollupEase_FieldDescription": "written into a generated field's description",
    "Core_HealthCheck_OrphansNativeNote": "part of a Health Check finding",
    "Core_HealthCheck_NightlyOffFixHint": "part of a Health Check finding",
}


def help_prose(path):
    """Labels in a file that read as help prose, by the rule in the module docstring."""
    found = []
    for block in re.findall(r"<labels>(.*?)</labels>", open(path, encoding="utf-8").read(), re.S):
        name = re.search(r"<fullName>\s*(\w+)\s*</fullName>", block)
        value = re.search(r"<value>(.*?)</value>", block, re.S)
        if not name or not value or name.group(1) in PROSE_EXCEPTIONS:
            continue
        name, value = name.group(1), html.unescape(value.group(1)).strip()
        words = re.findall(r"[A-Z][a-z]*|[0-9]+", name.split("_")[-1])
        if not words or words[-1] not in HELP_WORDS or set(words) & MESSAGE_WORDS:
            continue
        if PLACEHOLDER.search(value) or len(value.split()) < 6 or not SENTENCE.search(value):
            continue
        found.append(name)
    return found


def label_names():
    names = {}
    for path in sorted(glob.glob(LABEL_FILES)):
        for name in re.findall(r"<fullName>\s*([A-Za-z0-9_]+)\s*</fullName>", open(path, encoding="utf-8").read()):
            names[name] = path
    return names


def strip_comments(path, text):
    if path.endswith((".cls", ".trigger", ".js")):
        text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
        text = re.sub(r"(?m)^\s*//.*$", " ", text)
    elif path.endswith((".html", ".xml", ".cmp", ".page", ".component")):
        text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
    return text


def referenced_names(names):
    files = subprocess.run(["git", "ls-files", "packages"], capture_output=True, text=True, check=True).stdout
    found = set()
    for path in files.splitlines():
        if path.endswith((".labels-meta.xml", ".md")):
            continue
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        for word in set(re.findall(r"[A-Za-z0-9_]+", strip_comments(path, text))):
            if word in names:
                found.add(word)
    return found


def main():
    names = label_names()
    problems = []
    total = len(names)
    if total > BUDGET:
        problems.append(
            f"{total} custom labels, over the budget of {BUDGET} (the org limit is 5,000 and an org's own"
            " labels need room). Remove unused labels, merge exact duplicates, or move help text"
            " into the package's help catalog before adding more."
        )
    for name in sorted(set(names) - referenced_names(names)):
        problems.append(f"{names[name]}: {name} is not referenced anywhere in packages/; remove it")
    for path in sorted(glob.glob(LABEL_FILES)):
        for name in help_prose(path):
            problems.append(
                f"{path}: {name} reads as help prose; put it in the package's help catalog"
                " (BarnHelp_<Package>.json, docs/contributor-guide/ux-kit.md, Help Text), not a label"
            )

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-label-budget.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    note = f", {total - TARGET} over the target of {TARGET}" if total > TARGET else ""
    print(f"check-label-budget.py: OK, {total} labels, budget {BUDGET}{note}, none unused")
    return 0


if __name__ == "__main__":
    sys.exit(main())
