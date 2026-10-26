#!/usr/bin/env python3
"""Checks every shipped custom metadata record against its type definition.

A record that names a field the type does not define deploys nowhere: the
metadata API refuses the whole deployment. The offline Apex compiler does not
see custom metadata records, so nothing else in the check suite catches it.
This ran because three Automation Registry records reached main naming
Default_Enabled__c, a field that belongs to Naming Pattern, not to that type.

It also checks a Setting Definition row against the org it would be installed
into: the field its Setting_Key__c names has to be defined on the settings
object it points at, and its Section__c has to be a section name Core knows.
A row naming a field that is not there deploys cleanly and then tells the
administrator "That setting does not exist in this org" the first time anybody
saves that panel, and a row in a section Core does not know is a section the
Setup Assistant cannot send anybody to.

It also checks the other half of a Setting Definition row whose Data_Type__c is
Component: the settings console can only render a component it names in its own
import switch, because dynamic imports must be statically analyzable. A row
naming a component the console does not import deploys cleanly and then shows
"not installed" to the administrator, which is a defect only a person opening
that page in an org would ever see.

It also checks the shape of every record, because the metadata API reports these
badly or not at all. A record that writes xsi:type="xsd:string" without declaring
the xsd prefix fails the whole deployment with UNKNOWN_EXCEPTION and no component
error, which is what kept every org run red at the custom metadata stage until
2026-09-22. A label longer than 40 characters, or one given as an attribute
instead of a <label> element, fails only in an org.

It also checks every shipped migration import template (Template_Key__c starting
npc_ or npsp_) against its sample export in docs/admin-guide/samples/, named
after the key (npc_gift_transactions reads npc-gift-transactions.csv). The Apex
tests build their rows from the template's own headings, so a heading misspelt
in the template would pass them and then match no column of a real export. The
sample is written the way the export heads its columns: every sample heading has
to be one of the template's source headings, and every template heading has to
be in the sample, except the Fund 2 to Fund 5 and Amount 2 to Amount 5 columns
an administrator adds by hand for a split gift. Headings compare ignoring
capitals, as the importer compares them.
"""

import csv
import glob
import json
import os
import re
import sys
from html import unescape

LABEL = re.compile(r"<label>([^<]*)</label>")
LABEL_LIMIT = 40
FIELD = re.compile(r"<field>([^<]+)</field>")
VALUE_FOR = (
    lambda field: re.compile(
        r"<field>" + field + r"</field>\s*<value[^>]*>([^<]*)</value>", re.DOTALL
    )
)
CONSOLE = "packages/core/main/default/lwc/settingsConsole/settingsConsole.js"
SETUP_VALUE_SELECTOR = "packages/core/main/default/classes/SetupValueSelector.cls"
CONSOLE_CASE = re.compile(r"case '([A-Za-z0-9_]+)':")
SECTIONS = "packages/core/main/default/classes/SettingSections.cls"
SECTION_CONSTANT = re.compile(r"public static final String [A-Z_]+ = '([^']+)';")
SETTING_DEFINITIONS = "packages/*/main/default/customMetadata/Setting_Definition.*.md-meta.xml"
CORE_SETTINGS_OBJECT = "BarnCRM_Settings__c"
IMPORT_TEMPLATES = "packages/*/main/default/customMetadata/Import_Template_Default.*.md-meta.xml"
MIGRATION_KEY = re.compile(r"^(npc|npsp)_")
SAMPLES = "docs/admin-guide/samples"
ADDED_BY_HAND = re.compile(r"^(fund|amount) [2-5]$")


def type_definitions():
    """Every custom metadata type in the repo, by name without the __mdt suffix."""
    return {
        os.path.basename(path)[: -len("__mdt")]: path
        for path in glob.glob("packages/*/main/default/objects/*__mdt")
    }


def defined_fields(type_path):
    return {
        os.path.basename(path)[: -len(".field-meta.xml")]
        for path in glob.glob(f"{type_path}/fields/*.field-meta.xml")
    }


def value_of(text, field):
    """The value of one field in a custom metadata record, or None."""
    found = VALUE_FOR(field).search(text)
    return found.group(1).strip() if found else None


def console_components():
    """Every component name the settings console can actually import."""
    return set(CONSOLE_CASE.findall(open(CONSOLE, encoding="utf-8").read()))


def check_console_components(problems):
    """Every Component setting row names a component the console imports.

    Every package, not only Core. This scanned Core's directory alone until a Giving row named
    `receiptSettings`, a Giving component, and the Receipts panel rendered as not installed for
    every administrator while the check passed. The rows most likely to get this wrong are
    exactly the ones this used to skip, because a module author is the person who has a
    component Core cannot import (ADR-0020).
    """
    importable = console_components()
    for record in sorted(
        glob.glob("packages/*/main/default/customMetadata/Setting_Definition.*.md-meta.xml")
    ):
        text = open(record, encoding="utf-8").read()
        if value_of(text, "Data_Type__c") != "Component":
            continue
        component = value_of(text, "Component__c")
        if not component:
            # A Component row with no component navigates away instead, which is ADR-0020.
            continue
        if component not in importable:
            problems.append(
                f"{record}: names the component {component}, which settingsConsole.js "
                "does not import, so the settings console would show it as not installed"
            )


def settings_objects():
    """Every custom object in the repo, with the fields it defines, by name."""
    objects = {}
    for path in glob.glob("packages/*/main/default/objects/*"):
        objects[os.path.basename(path)] = defined_fields(path)
    return objects


def known_sections():
    """Every section name Core knows, read from the one class that names them."""
    return set(SECTION_CONSTANT.findall(open(SECTIONS, encoding="utf-8").read()))


def check_setting_rows(problems):
    """Every Setting Definition row names a real field, on a real object, in a known section.

    This ran because a settings panel can only refuse what it cannot find: `SettingsService`
    throws "That setting does not exist in this org" for a key its settings object does not
    define, and nothing before this point compares the two. `Section__c` is checked in the same
    pass because `SettingSections` is the vocabulary a Setup Assistant step and a shipped row
    have to agree on, and a row can quietly invent a section name that no step can target.
    """
    objects = settings_objects()
    sections = known_sections()
    setup_values = set(re.findall(r"KEY_\w+ = '(\w+)'", open(SETUP_VALUE_SELECTOR).read()))
    for record in sorted(glob.glob(SETTING_DEFINITIONS)):
        text = open(record, encoding="utf-8").read()
        section = value_of(text, "Section__c")
        if section and section not in sections:
            problems.append(
                f"{record}: is in the section {section}, which SettingSections.cls does not "
                "name, so no setup step can send anybody to it"
            )
        if value_of(text, "Data_Type__c") == "Component":
            continue
        if value_of(text, "Data_Type__c") == "SetupValue":
            # A value Setup holds, shown read only (ADR-0135). The console shows only the keys
            # SetupValueSelector lists and silently leaves any other row out, so check it here.
            key = value_of(text, "Setting_Key__c")
            if value_of(text, "Settings_Object__c") != "Organization" or key not in setup_values:
                problems.append(
                    f"{record}: is a SetupValue row naming Organization.{key}, which "
                    "SetupValueSelector does not show, so the console would leave it out"
                )
            continue
        if value_of(text, "Data_Type__c") == "Number" and not (
            value_of(text, "Min_Value__c") and value_of(text, "Max_Value__c")
        ):
            # ADMIN-27: a number with no range is saved as typed and then clamped by whatever
            # reads it, so the console shows a value that is not in effect.
            problems.append(
                f"{record}: is a Number row without both Min_Value__c and Max_Value__c, so "
                "the console would accept a value BarnCRM does not use"
            )
        key = value_of(text, "Setting_Key__c")
        if not key:
            problems.append(f"{record}: is not a Component row and names no Setting_Key__c")
            continue
        settings_object = value_of(text, "Settings_Object__c") or CORE_SETTINGS_OBJECT
        fields = objects.get(settings_object)
        if fields is None:
            problems.append(
                f"{record}: names the settings object {settings_object}, "
                "which no package in this repo defines"
            )
            continue
        if key not in fields:
            problems.append(
                f"{record}: names the setting {key}, which {settings_object} does not define, "
                "so saving that panel would tell the administrator the setting does not exist"
            )


def check_migration_samples(problems):
    """Each migration template's headings against the sample export the admin guide ships."""
    for record in sorted(glob.glob(IMPORT_TEMPLATES)):
        text = open(record, encoding="utf-8").read()
        key = value_of(text, "Template_Key__c")
        if not key or not MIGRATION_KEY.match(key):
            continue
        sample = os.path.join(SAMPLES, key.replace("_", "-") + ".csv")
        if not os.path.exists(sample):
            problems.append(f"{record}: migration template {key} has no sample export {sample}")
            continue
        try:
            mapping = json.loads(unescape(value_of(text, "Column_Mapping_JSON__c") or ""))
            sources = {column["source"].strip().lower() for column in mapping["columns"]}
        except (ValueError, KeyError, TypeError):
            problems.append(f"{record}: Column_Mapping_JSON__c cannot be read")
            continue
        with open(sample, encoding="utf-8", newline="") as handle:
            header = {heading.strip().lower() for heading in next(csv.reader(handle), [])}
        for heading in sorted(header - sources):
            problems.append(f"{sample}: heading {heading!r} is not a column {key} reads")
        for heading in sorted(sources - header):
            if not ADDED_BY_HAND.match(heading):
                problems.append(f"{record}: heading {heading!r} is not in the sample export {sample}")


def main():
    types = type_definitions()
    problems = []
    checked = 0

    for record in sorted(glob.glob("packages/*/main/default/customMetadata/*.md-meta.xml")):
        type_name = os.path.basename(record).split(".")[0]
        type_path = types.get(type_name)
        if type_path is None:
            problems.append(f"{record}: no {type_name}__mdt definition in any package")
            continue
        fields = defined_fields(type_path)
        checked += 1
        text = open(record, encoding="utf-8").read()
        if "xsd:" in text and 'xmlns:xsd="http://www.w3.org/2001/XMLSchema"' not in text:
            problems.append(f"{record}: uses the xsd: prefix without declaring xmlns:xsd on the root element")
        label = LABEL.search(text)
        if label is None:
            problems.append(f"{record}: has no <label> element")
        elif not label.group(1).strip():
            problems.append(f"{record}: has an empty label")
        elif len(label.group(1)) > LABEL_LIMIT:
            problems.append(
                f"{record}: label is {len(label.group(1))} characters, over the platform limit of {LABEL_LIMIT}"
            )
        for named in FIELD.findall(text):
            if named not in fields:
                problems.append(f"{record}: names {named}, which {type_name}__mdt does not define")

    check_console_components(problems)
    check_setting_rows(problems)
    check_migration_samples(problems)

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-custom-metadata.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-custom-metadata.py: OK, {checked} records match their type")
    return 0


if __name__ == "__main__":
    sys.exit(main())
