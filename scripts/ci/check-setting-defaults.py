#!/usr/bin/env python3
"""Checks that every checkbox setting which ships switched on is actually switched on.

A checkbox field can declare `<defaultValue>true</defaultValue>`. That default is what the
platform applies when a record is created through the user interface. It is not what Apex
reads: `BarnCRM_Settings__c.getOrgDefaults()` on an org that has never saved its settings
returns a materialized record with every checkbox false, not null and not the declared
default. So a feature guarded by such a setting does nothing at all on every fresh install,
raises nothing, and logs nothing.

That is not hypothetical. C-15 shipped the relationship reciprocal upkeep behind
`Relationship_Auto_Reciprocal__c`, whose metadata and admin guide both say it ships on. The
first org run this project ever had found thirteen failures, every count exactly half of what
was expected, because the other side of a relationship was never written. No offline check
could see it: the field metadata was right, the Apex compiled, and the assumption that joined
them was invisible.

The gate, for Core: a checkbox on `BarnCRM_Settings__c` that declares a default of true has
to be registered in `SHIPPED_DEFAULTS` in SettingsService, which puts the value on the record
for an org that has never saved one, or be listed in KNOWN_UNREGISTERED below with a reason.
The listed ones are also checked, so an entry cannot outlive the field it excuses.

For a module's settings object, Core cannot name the fields, so a first save takes the
checkbox defaults from the field metadata itself (`SettingsService.firstSaveRecord`), and the
module's readers treat a missing record as the shipped value. What can still go wrong is a
module class saving the record `getOrgDefaults()` returned, with its checkboxes false, which
is how Giving switched three shipped features off. So the gate also fails on a class outside
the tests that takes a settings record from `getOrgDefaults()` and hands it to DML: such a
save goes through `OrgSettingsSystemWriter` instead.

The third trap (QA-F2): an org that saved its settings before a ship-on checkbox existed gets
the new field as false on its stored record, so neither default reaches it. Every ship-on
checkbox has to be either listed in SHIPPED_BEFORE_UPGRADE_STEP below (the ones that predate
the upgrade step; the list is closed) or registered in a `SHIPPED_ON_ADDED_IN_UPGRADES` list in
the package's post-install class, which passes it to `ShippedDefaultUpgrades.apply` to turn it
on once in such an org.

Modules in the settings store (ADR-0238 settings as custom metadata, phase 2): a module that
ships a `Setting_Module__mdt` record reads every row of its group from the store, where an
unsaved setting is its `Default_Value__c` and nothing else. So its Checkbox, Number and
Picklist rows must ship one, a row whose legacy field declares a default must ship the same,
and each must parse as JSON. The store names a value by the definition's DeveloperName and
every package shares one namespace, so DeveloperNames (and group plus key) are unique across
packages, and each registry record names its own group and prefix.
"""

import glob
import html
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"
SETTINGS_SERVICE = "packages/core/main/default/classes/SettingsService.cls"
CORE_SETTINGS = "BarnCRM_Settings__c"

# Checkboxes that ship on and are deliberately not registered, with the reason. An entry here
# says the shipped default is not applied for that field today: it is a known gap, recorded
# rather than hidden, and it is checked, so it cannot name a field that no longer qualifies.
KNOWN_UNREGISTERED = {}

# Ship-on checkboxes that existed before the upgrade step (QA-F2, 2026-11-02), plus those the
# packages' SHIPPED_ON_ADDED_IN_UPGRADES lists held when they were reset at the namespaced
# cut-over (D-199, D-200, 2026-11-12): the managed release is a fresh install everywhere, so
# every one of these reaches an org through its shipped default. Closed: a new ship-on checkbox
# goes in its package's SHIPPED_ON_ADDED_IN_UPGRADES list instead.
SHIPPED_BEFORE_UPGRADE_STEP = {
    ("Address_Verification_Settings__c", "Verify_On_Save__c"),
    ("BarnCRM_Settings__c", "Auto_Create_Households__c"),
    ("BarnCRM_Settings__c", "Error_Digest_Include_Admin_Summary__c"),
    ("BarnCRM_Settings__c", "Job_Notifications__c"),
    ("BarnCRM_Settings__c", "Relationship_Auto_Reciprocal__c"),
    ("Contact_Point_Sync_Settings__c", "Sync_Addresses__c"),
    ("Contact_Point_Sync_Settings__c", "Sync_Emails__c"),
    ("Contact_Point_Sync_Settings__c", "Sync_Phones__c"),
    ("Corporate_Hub_Settings__c", "Reminders_Enabled__c"),
    ("Funders_Settings__c", "Grant_Finder_Enabled__c"),
    ("Funders_Settings__c", "Reminder_Tasks_Enabled__c"),
    ("Giving_Settings__c", "Ask_Reminders_Enabled__c"),
    ("Giving_Settings__c", "Auto_Apply_Gifts_To_Installments__c"),
    ("Giving_Settings__c", "Automatic_Household_Soft_Credits__c"),
    ("Giving_Settings__c", "Receipt_Print_Logo__c"),
    ("LWC_Builder_Settings__c", "Components_Enabled__c"),
    ("LWC_Builder_Settings__c", "Source_Export__c"),
    ("Memberships_Settings__c", "Renew_From_Gifts__c"),
    ("Projects_Settings__c", "Time_Tracking_Enabled__c"),
    ("Scholarships_Settings__c", "Reminders_Enabled__c"),
    ("Volunteer_Settings__c", "Attendance_Creates_Hours__c"),
    ("Volunteer_Settings__c", "Hours_Require_Approval__c"),
}
UPGRADE_LIST = "SHIPPED_ON_ADDED_IN_UPGRADES"
UPGRADE_CALL = "ShippedDefaultUpgrades.apply("

APEX_CLASSES = "packages/*/main/default/classes/*.cls"
# The one class allowed to write a settings record it was handed.
SYSTEM_WRITER = "OrgSettingsSystemWriter.cls"


def q(tag):
    return f"{{{NS}}}{tag}"


def text_of(element, tag):
    child = element.find(q(tag))
    return (child.text or "").strip() if child is not None and child.text else ""


def hierarchy_setting_objects():
    """Every hierarchy custom setting object in the repository, as (object name, fields dir)."""
    found = []
    for path in sorted(glob.glob("packages/*/main/default/objects/*/*.object-meta.xml")):
        root = ET.parse(path).getroot()
        if text_of(root, "customSettingsType") != "Hierarchy":
            continue
        directory = os.path.dirname(path)
        found.append((os.path.basename(directory), os.path.join(directory, "fields")))
    return found


def ships_on(fields_dir):
    """The checkbox fields in one settings object that declare a default of true."""
    on = []
    for path in sorted(glob.glob(os.path.join(fields_dir, "*.field-meta.xml"))):
        root = ET.parse(path).getroot()
        if text_of(root, "type") != "Checkbox":
            continue
        if text_of(root, "defaultValue").lower() != "true":
            continue
        on.append(text_of(root, "fullName"))
    return on


DEFINITIONS = "packages/*/main/default/customMetadata/Setting_Definition.*.md-meta.xml"
# Core keys whose blank default is deliberate: blank means nobody has chosen yet.
BLANK_BY_DESIGN = {"Coexistence_Mode__c", "Household_Membership_Mode__c"}


def definition_value(text, field):
    found = re.search(
        r"<field>" + field + r"</field>\s*<value[^>]*?(?:/>|>(.*?)</value>)", text, re.DOTALL
    )
    return found.group(1).strip() if found and found.group(1) else ""


def registered_defaults():
    """Core's shipped defaults, from Default_Value__c on its Setting Definition rows (ADR-0238
    settings as custom metadata): checkbox keys as booleans, every key's raw JSON alongside."""
    pairs = {}
    raw = {}
    for path in sorted(glob.glob(DEFINITIONS)):
        text = open(path, encoding="utf-8").read()
        if definition_value(text, "Settings_Object__c") != CORE_SETTINGS:
            continue
        key = definition_value(text, "Setting_Key__c")
        if not key:
            continue
        default = definition_value(text, "Default_Value__c")
        raw[(CORE_SETTINGS, key)] = default
        if default in ("true", "false"):
            pairs[(CORE_SETTINGS, key)] = default == "true"
    return pairs, raw


def core_field_defaults(object_name=CORE_SETTINGS):
    """Each field of a settings object that declares a default, as the JSON its definition must
    ship (Core's by default; a registered module's legacy object while it still exists)."""
    expected = {}
    pattern = f"packages/*/main/default/objects/{object_name}/fields/*.field-meta.xml"
    for path in sorted(glob.glob(pattern)):
        root = ET.parse(path).getroot()
        name = text_of(root, "fullName")
        declared = text_of(root, "defaultValue")
        if not declared or (object_name == CORE_SETTINGS and name in BLANK_BY_DESIGN):
            continue
        kind = text_of(root, "type")
        if kind == "Checkbox":
            expected[name] = declared.lower()
        elif kind == "Number":
            expected[name] = declared
        elif declared.startswith('"') and declared.endswith('"'):
            expected[name] = '"' + declared[1:-1] + '"'
    return expected


REGISTRY = "packages/*/main/default/customMetadata/Setting_Module.*.md-meta.xml"
# Row types that always have a value to read, so a registered module ships it as the default.
DEFAULT_REQUIRED = {"Checkbox", "Number", "Picklist"}
PREFIX_SHAPE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")


def json_literal(text):
    """True when the text is one JSON literal (true, 7, "Both"), as the store parses it."""
    try:
        json.loads(text)
        return True
    except ValueError:
        return False


def registry_problems():
    """Setting Module records (ADR-0238 settings as custom metadata, phase 2): each names a
    settings group other than Core's and a prefix, and neither repeats. Returns the registered
    groups and the problems."""
    problems = []
    groups = {}
    prefixes = {}
    for path in sorted(glob.glob(REGISTRY)):
        text = open(path, encoding="utf-8").read()
        group = definition_value(text, "Settings_Object__c")
        prefix = definition_value(text, "Key_Prefix__c")
        if not group or not prefix:
            problems.append(f"{path}: a Setting Module names both Settings_Object__c and Key_Prefix__c.")
            continue
        if group == CORE_SETTINGS:
            problems.append(f"{path}: Core's settings are not a module's; register the module's own group.")
        if not PREFIX_SHAPE.match(prefix):
            problems.append(f"{path}: Key_Prefix__c {prefix!r} must be letters, digits and underscores.")
        if group.lower() in groups:
            problems.append(f"{path}: {group} is already registered by {groups[group.lower()]}.")
        if prefix.lower() in prefixes:
            problems.append(f"{path}: the prefix {prefix} is already used by {prefixes[prefix.lower()]}.")
        groups[group.lower()] = path
        prefixes[prefix.lower()] = path
    return set(groups), problems


# ModuleSettings reads a module's rows through SettingDefinitionSelector.getAllShortFields(),
# which cuts every long text area to 255 characters, so a longer Picklist_Values__c loses its
# last choices without a word. Core's rows are read in full.
SHORT_FIELD_LIMIT = 255


def picklist_length_problems(path, group, values):
    """A module (non-Core) row's Picklist_Values__c, unescaped, fits in SHORT_FIELD_LIMIT."""
    if group == CORE_SETTINGS or not values:
        return []
    length = len(html.unescape(values))
    if length <= SHORT_FIELD_LIMIT:
        return []
    return [
        f"{path}: Picklist_Values__c is {length} characters; a module's rows are read cut to "
        f"{SHORT_FIELD_LIMIT} (SettingDefinitionSelector.getAllShortFields), so its last "
        f"choices would be lost. Shorten the labels."
    ]


def store_definition_problems(registered_groups):
    """Setting Definition keys are unique across every package (the store names a value by the
    DeveloperName, and every package shares one namespace), as are group plus key; a registered
    module's rows ship their defaults: Checkbox, Number and Picklist always, any row whose legacy
    field declares a default the same value, each a JSON literal."""
    problems = []
    names = {}
    keys = {}
    legacy_defaults = {}
    for path in sorted(glob.glob(DEFINITIONS)):
        text = open(path, encoding="utf-8").read()
        name = os.path.basename(path)[len("Setting_Definition.") : -len(".md-meta.xml")]
        if name.lower() in names:
            problems.append(f"{path}: the key {name} is also shipped by {names[name.lower()]}.")
        names[name.lower()] = path
        group = definition_value(text, "Settings_Object__c") or CORE_SETTINGS
        key = definition_value(text, "Setting_Key__c")
        if key:
            pair = (group.lower(), key.lower())
            if pair in keys:
                problems.append(f"{path}: {group}.{key} is also edited by {keys[pair]}.")
            keys[pair] = path
        problems.extend(picklist_length_problems(path, group, definition_value(text, "Picklist_Values__c")))
        if group.lower() not in registered_groups:
            continue
        default = definition_value(text, "Default_Value__c")
        kind = definition_value(text, "Data_Type__c")
        if default and not json_literal(default):
            problems.append(f"{path}: Default_Value__c {default} is not a JSON literal, so it reads as no default.")
        if kind in DEFAULT_REQUIRED and not default:
            problems.append(
                f"{path}: a {kind} row of a module in the store ships no Default_Value__c, so an "
                f"org that never saved it reads nothing. Ship the default as a JSON literal."
            )
        if group not in legacy_defaults:
            legacy_defaults[group] = core_field_defaults(group)
        expected = legacy_defaults[group].get(key)
        if expected is not None and default != expected:
            problems.append(
                f"{path}: ships Default_Value__c {default or '(blank)'}, but {group}.{key} "
                f"declares {expected}. Carry-over and every reader use the definition's, so the "
                f"two have to agree."
            )
    return problems


def main():
    registered, raw_defaults = registered_defaults()

    problems = []
    registered_groups, module_problems = registry_problems()
    problems.extend(module_problems)
    problems.extend(store_definition_problems(registered_groups))
    for key, expected in sorted(core_field_defaults().items()):
        shipped = raw_defaults.get((CORE_SETTINGS, key))
        if shipped is None:
            continue
        if shipped != expected:
            problems.append(
                f"{CORE_SETTINGS}.{key}: its Setting Definition ships Default_Value__c "
                f"{shipped or '(blank)'}, but the field declares {expected}. Every reader of the "
                f"setting uses the definition's default, so the two have to agree."
            )
    checked = 0
    from_metadata = 0
    declared = set()
    settings_objects = []

    for object_name, fields_dir in hierarchy_setting_objects():
        settings_objects.append(object_name)
        for field_name in ships_on(fields_dir):
            checked += 1
            key = (object_name, field_name)
            declared.add(key)
            if object_name != CORE_SETTINGS and key not in registered:
                # A module's first save takes this default from the field metadata.
                from_metadata += 1
                continue
            if key in registered:
                if not registered[key]:
                    problems.append(
                        f"{object_name}.{field_name}: the field ships on, but SettingsService "
                        f"registers it as false. The two have to agree."
                    )
                continue
            if key in KNOWN_UNREGISTERED:
                continue
            problems.append(
                f"{object_name}.{field_name} declares defaultValue true, but Apex never sees "
                f"that default: getOrgDefaults() returns false for it until the org saves its "
                f"settings, so whatever this setting guards does nothing on a fresh install "
                f"and says nothing about it. Ship Default_Value__c true on its Setting Definition."
            )

    problems.extend(raw_settings_saves(settings_objects))
    upgrade_entries, upgrade_problems = upgrade_registries()
    problems.extend(upgrade_problems)
    for key in sorted(declared):
        if key not in upgrade_entries and key not in SHIPPED_BEFORE_UPGRADE_STEP:
            problems.append(
                f"{key[0]}.{key[1]} ships on but is in no {UPGRADE_LIST} list. An org that "
                f"saved these settings before the field existed gets it as false. Append it to "
                f"{UPGRADE_LIST} in the package's post-install class (QA-F2)."
            )
    for key in sorted(SHIPPED_BEFORE_UPGRADE_STEP | set(upgrade_entries)):
        if key not in declared:
            problems.append(
                f"{key[0]}.{key[1]} is listed as a ship-on checkbox "
                f"({upgrade_entries.get(key, 'SHIPPED_BEFORE_UPGRADE_STEP')}) but its field "
                f"metadata does not declare defaultValue true."
            )

    for key in sorted(KNOWN_UNREGISTERED):
        if key not in declared:
            problems.append(
                f"{key[0]}.{key[1]} is listed in KNOWN_UNREGISTERED but is no longer a checkbox "
                f"that ships on. Remove the entry."
            )

    for key in sorted(registered):
        if registered[key] and key not in declared:
            problems.append(
                f"{key[0]}.{key[1]} ships Default_Value__c true on its Setting Definition but its "
                f"field metadata does not declare defaultValue true. The console, the admin "
                f"guide and the code all read that metadata as the shipped default, so they "
                f"have to agree."
            )

    if problems:
        print("Settings whose shipped default would read wrong:")
        for problem in problems:
            print(f"  - {problem}")
        print("")
        print(
            "Background: a hierarchy custom setting read through getOrgDefaults() comes back "
            "materialized, with every checkbox false, not null. See ADR-0035."
        )
        return 1

    print(
        f"Checked {checked} checkbox settings that ship switched on: "
        f"{len(registered)} registered, {from_metadata} applied from module field metadata, "
        f"{len(KNOWN_UNREGISTERED)} recorded as known gaps; no raw settings saves."
    )
    return 0


def upgrade_registries():
    """Every SHIPPED_ON_ADDED_IN_UPGRADES entry as {(object, field): path}, and problems."""
    entries = {}
    problems = []
    pattern = re.compile(
        UPGRADE_LIST + r"\s*=\s*new\s+List<Schema\.SObjectField>\s*\{(.*?)\}", re.DOTALL
    )
    for path in sorted(glob.glob(APEX_CLASSES)):
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        match = pattern.search(source)
        if match is None:
            continue
        if UPGRADE_CALL not in source:
            problems.append(
                f"{path} declares {UPGRADE_LIST} but never passes it to {UPGRADE_CALL[:-1]}, "
                f"so its entries are never turned on."
            )
        for object_name, field_name in re.findall(r"(\w+__c)\.(\w+__c)", match.group(1)):
            entries[(object_name, field_name)] = path
    return entries, problems


def is_test_class(path, source):
    return path.endswith("Test.cls") or re.search(r"^\s*@IsTest\b", source, re.I | re.M)


def raw_settings_saves(settings_objects):
    """Classes that save a settings record taken from getOrgDefaults(), outside the tests."""
    names = "|".join(re.escape(name) for name in settings_objects)
    if not names:
        return []
    taken = re.compile(r"(\w+)\s*=\s*(?:" + names + r")\.getOrgDefaults\(\)")
    problems = []
    for path in sorted(glob.glob(APEX_CLASSES)):
        if os.path.basename(path) == SYSTEM_WRITER:
            continue
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        if is_test_class(path, source):
            continue
        variables = set(taken.findall(source))
        # A record wrapped in a list before the DML is the same save.
        for variable in list(variables):
            wrapped = r"(\w+)\s*=\s*new\s+List<\w+>\s*\{\s*" + variable + r"\s*\}"
            variables.update(re.findall(wrapped, source))
        for variable in sorted(variables):
            dml = (
                r"(Database\.(?:insert|update|upsert)\(\s*" + variable + r"\b"
                r"|\b(?:insert|update|upsert)\s+" + variable + r"\s*;)"
            )
            if re.search(dml, source, re.I):
                problems.append(
                    f"{path} saves `{variable}`, a settings record taken from getOrgDefaults(). "
                    f"On an org that has never saved, its checkboxes are false, so this save "
                    f"switches off every feature that ships on. Save only the keys through "
                    f"OrgSettingsSystemWriter.save(type, values) instead."
                )
    return problems


if __name__ == "__main__":
    sys.exit(main())
