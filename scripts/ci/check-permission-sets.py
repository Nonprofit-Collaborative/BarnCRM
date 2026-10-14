#!/usr/bin/env python3
"""Checks that every permission set grants access to metadata that exists.

A permission set naming a class, tab, application, object, field or custom permission that
the packages do not ship fails the whole deployment with a component error, and so does a
permission set group naming a set that is not there. Nothing else in
the check suite sees it: the offline Apex compiler does not read permission sets, and the
canonical model check reads objects and fields rather than who is granted them.

This ran because BarnCRM_Admin granted a Household_Member__c tab that had never been
created. The integration contract asked for that tab, the grant was added, and the tab was
not, so the permission set had been undeployable for as long as it had existed.

The permission sets are assembled by hand at each merge from the integration files, which is
exactly the process that produces this mistake, so it is worth a gate rather than care.

Standard objects and fields are not checked: they exist in the org rather than in this
repository. Only custom API names, which end in __c, are resolved against the packages.

One grant that resolves is still checked, because it cannot be given: View All Records or
Modify All Records on the detail side of a master-detail relationship. Record access to a
detail object comes from its master, and a permission set that asks for it anyway risks
losing the whole objectPermissions entry, and with it the create and edit access the
feature actually needs. BarnCRM_Admin asked for both on Import Row, and the first org run
of the import tests failed on staging a row.

One more grant resolves and still breaks ADR-0013: an object only some licenses may be given.
Salesforce grants DuplicateRecordSet and DuplicateRecordItem only to Sales Cloud and Service
Cloud licenses, so a permission set granting them cannot be assigned to a Salesforce Platform
user. Such objects may appear only in the optional sets named for them, and those sets may be
in no permission set group, because a role has to be assignable to everybody. The same holds
for user permissions the Salesforce Platform license cannot hold: Assign Permission Sets and
View All Users made BarnCRM_Admin unassignable to a Platform user on barn-core, so they live
only in BarnCRM_Access_Manager (ADR-NEXT).

scripts/org/create-scratch-org.sh reads the optional sets from this file
(--list-optional-license-sets), so its Platform user check expects exactly these to be refused.

Two limits the platform enforces only at deploy time are checked too: a permission set's label
may be at most 80 characters and its description at most 255, counted as the platform counts
them, with the line breaks and indentation the XML carries. Opportunity_Mirror's description
broke the Connect deploy on oi-test at 272 characters while every static check passed.
"""

import glob
import os
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"

# Objects and user permissions a Salesforce Platform license cannot be granted, and the
# optional sets allowed to grant them (C-20, ADR-0050 on duplicate detection; ADR-NEXT on
# the Access page's Salesforce permissions).
LICENSE_LIMITED_OBJECTS = {"DuplicateRecordSet", "DuplicateRecordItem"}
LICENSE_LIMITED_USER_PERMISSIONS = {"AssignPermissionSets", "ViewAllUsers"}
OPTIONAL_LICENSE_SETS = {"BarnCRM_Duplicate_Review", "BarnCRM_Access_Manager"}

# The platform's own limits on a permission set's label and description (Metadata API).
LABEL_MAX = 80
DESCRIPTION_MAX = 255


def q(tag):
    return f"{{{NS}}}{tag}"


def exists(pattern):
    return bool(glob.glob(pattern))


def controlled_by_parent(obj):
    """Whether this custom object is the detail side of a master-detail relationship."""
    for path in glob.glob(f"packages/*/main/default/objects/{obj}/{obj}.object-meta.xml"):
        root = ET.parse(path).getroot()
        model = root.find(q("sharingModel"))
        if model is not None and model.text == "ControlledByParent":
            return True
    return False


def check(path):
    """Every dangling reference in one permission set, as readable lines."""
    name = os.path.basename(path).replace(".permissionset-meta.xml", "")
    root = ET.parse(path).getroot()
    problems = []

    def report(kind, value):
        problems.append(f"{name}: {kind} {value}, which no package ships")

    for tag, limit in (("label", LABEL_MAX), ("description", DESCRIPTION_MAX)):
        element = root.find(q(tag))
        text = (element.text or "") if element is not None else ""
        if len(text) > limit:
            problems.append(
                f"{name}: {tag} is {len(text)} characters, over the platform's limit of "
                f"{limit}, so the deploy refuses the permission set"
            )

    for entry in root.findall(q("classAccesses")):
        value = entry.find(q("apexClass")).text
        if not exists(f"packages/*/main/default/classes/{value}.cls"):
            report("grants Apex class", value)

    for entry in root.findall(q("tabSettings")):
        value = entry.find(q("tab")).text
        if not exists(f"packages/*/main/default/tabs/{value}.tab-meta.xml"):
            report("grants tab", value)

    for entry in root.findall(q("applicationVisibilities")):
        value = entry.find(q("application")).text
        if not exists(f"packages/*/main/default/applications/{value}.app-meta.xml"):
            report("grants application", value)

    for entry in root.findall(q("customPermissions")):
        value = entry.find(q("name")).text
        if not exists(f"packages/*/main/default/customPermissions/{value}.customPermission-meta.xml"):
            report("grants custom permission", value)

    for entry in root.findall(q("objectPermissions")):
        value = entry.find(q("object")).text
        if value in LICENSE_LIMITED_OBJECTS and name not in OPTIONAL_LICENSE_SETS:
            problems.append(
                f"{name}: grants {value}, which a Salesforce Platform license cannot be given, "
                f"so this set could not be assigned in a Platform-only org (ADR-0013). Grant it "
                f"only in one of {sorted(OPTIONAL_LICENSE_SETS)}."
            )
        if value.endswith("__c") and not exists(f"packages/*/main/default/objects/{value}"):
            report("grants object", value)
        for flag in ("viewAllRecords", "modifyAllRecords"):
            element = entry.find(q(flag))
            if element is not None and element.text == "true" and controlled_by_parent(value):
                problems.append(
                    f"{name}: grants {flag} on {value}, which is the detail side of a "
                    f"master-detail relationship. Record access there comes from the master, "
                    f"so the platform has no such grant to give and the whole "
                    f"objectPermissions entry is at risk of being dropped, taking the "
                    f"ordinary create and edit access with it. Grant it on the master instead."
                )

    for entry in root.findall(q("userPermissions")):
        value = entry.find(q("name")).text
        enabled = entry.find(q("enabled"))
        granted = enabled is None or enabled.text == "true"
        if granted and value in LICENSE_LIMITED_USER_PERMISSIONS and name not in OPTIONAL_LICENSE_SETS:
            problems.append(
                f"{name}: grants user permission {value}, which a Salesforce Platform license "
                f"cannot hold, so this set could not be assigned in a Platform-only org "
                f"(ADR-0013). Grant it only in one of {sorted(OPTIONAL_LICENSE_SETS)}."
            )

    for entry in root.findall(q("recordTypeVisibilities")):
        value = entry.find(q("recordType")).text
        obj, _, record_type = value.partition(".")
        if obj.endswith("__c") or exists(f"packages/*/main/default/objects/{obj}"):
            if not exists(
                f"packages/*/main/default/objects/{obj}/recordTypes/{record_type}.recordType-meta.xml"
            ):
                report("grants record type", value)

    for entry in root.findall(q("fieldPermissions")):
        value = entry.find(q("field")).text
        obj, _, field = value.partition(".")
        if field.endswith("__c") and not exists(
            f"packages/*/main/default/objects/{obj}/fields/{field}.field-meta.xml"
        ):
            report("grants field", value)

    return problems


def check_group(path):
    """Every permission set a group names that no package ships.

    A permission set group is deployed with the sets it contains, and the packages deploy in
    stages: Core, then Giving. A Core group naming a Giving
    permission set would therefore be undeployable at the moment Core goes in, whatever the
    final org looks like once both packages are installed.
    """
    name = os.path.basename(path).replace(".permissionsetgroup-meta.xml", "")
    root = ET.parse(path).getroot()
    problems = []
    for entry in root.findall(q("permissionSets")):
        value = (entry.text or "").strip()
        if value in OPTIONAL_LICENSE_SETS:
            problems.append(
                f"{name}: contains {value}, which only some licenses can be assigned, so the "
                f"role could not be given to a Salesforce Platform user (ADR-0013)"
            )
        elif value and not exists(
            f"packages/*/main/default/permissionsets/{value}.permissionset-meta.xml"
        ):
            problems.append(
                f"{name}: contains permission set {value}, which no package ships"
            )
    return problems


def main():
    if sys.argv[1:] == ["--list-optional-license-sets"]:
        for name in sorted(OPTIONAL_LICENSE_SETS):
            print(name)
        return 0

    paths =sorted(glob.glob("packages/*/main/default/permissionsets/*.permissionset-meta.xml"))
    group_paths = sorted(
        glob.glob("packages/*/main/default/permissionsetgroups/*.permissionsetgroup-meta.xml")
    )
    problems = []
    for path in paths:
        problems.extend(check(path))
    for path in group_paths:
        problems.extend(check_group(path))

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            f"check-permission-sets.py: FAILED, {len(problems)} problem(s) above",
            file=sys.stderr,
        )
        return 1

    print(
        f"check-permission-sets.py: OK, {len(paths)} permission sets grant only what exists, "
        f"and {len(group_paths)} groups contain only sets that ship"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
