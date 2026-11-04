#!/usr/bin/env python3
"""Checks an org before BarnCRM is installed into it, and changes nothing.

    install-precheck.py <org alias> [--modules core,giving,...] [--apex-limit 6000000]

<org alias> is an org you have already connected with `sf org login web --alias <alias>`.
--modules names the packages you plan to install (folders under packages/: core, rollups,
giving, volunteers, programs, logicmodels, funders, mirror); the packages they depend on are
added. The default is every package. --apex-limit is the org's Apex code limit in characters,
when Salesforce support has raised it from the default 6,000,000.

Every call is read-only (`sf data query`, `sf org list metadata`, `sf sobject describe`), and
nothing about the org's login or session is printed. It prints one line per check, PASS, WARN
or FAIL, and exits 1 when anything failed:

  Edition       Enterprise, Unlimited, Performance and Developer Edition are supported
                (Nonprofit Cloud and Power of Us orgs are Enterprise). Professional Edition
                and Platform Starter are not: Apex runs there only in a security-reviewed
                managed package, and Starter users hold only 10 custom objects.
  Apex          the org's own non-test Apex plus the chosen packages against the limit.
  Labels        the org's own custom labels plus the chosen packages' against 5,000.
  Objects       the org's own custom objects and settings plus the chosen packages' against
                the edition's allowance.
  Names         every object, standard-object field, list view, record type, class, trigger,
                label, tab, static resource, component, page, permission set and flow name
                the chosen packages ship, against the org's own (unmanaged) components. A
                deploy silently updates a same-named component (architect review L-03).
  Test fit      active validation rules and required custom fields on Account and Contact,
                which BarnCRM's tests may trip during a production deploy.

See the Admin Guide, Installing BarnCRM.
"""

import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


budget = load("check_apex_budget", os.path.join(ROOT, "scripts", "ci", "check-apex-budget.py"))
manifest = load("build_destructive_manifest", os.path.join(HERE, "build-destructive-manifest.py"))

SUPPORTED = {"Enterprise Edition", "Unlimited Edition", "Performance Edition", "Developer Edition"}
UNSUPPORTED = {
    "Professional Edition": "Apex runs only in a security-reviewed managed package",
    "Team Edition": "Group Edition has no Apex",
    "Base Edition": "Essentials and Starter editions have no Apex",
    "Personal Edition": "Personal Edition has no Apex",
}
OBJECT_ALLOWANCE = {
    "Enterprise Edition": 200,
    "Unlimited Edition": 2000,
    "Performance Edition": 2000,
    "Developer Edition": 400,
}
LABEL_LIMIT = 5000
# Types compared by name. Children of BarnCRM's own objects are covered by the object itself.
NAME_TYPES = [
    "CustomObject", "CustomField", "ListView", "RecordType", "ValidationRule", "CompactLayout",
    "QuickAction", "ApexClass", "ApexTrigger", "CustomLabel", "CustomTab", "StaticResource",
    "LightningComponentBundle", "AuraDefinitionBundle", "ApexPage", "PermissionSet",
    "PermissionSetGroup", "FlexiPage", "CustomApplication", "Flow", "CustomPermission",
    "Layout", "CustomNotificationType", "ExternalCredential",
]
STANDARD_CHILDREN = {"CustomField", "ListView", "RecordType", "ValidationRule", "CompactLayout",
                     "QuickAction", "Layout"}


class OrgError(Exception):
    pass


def sf(alias, *args):
    """Runs a read-only sf command and returns its JSON result; never echoes credentials."""
    proc = subprocess.run(["sf", *args, "--target-org", alias, "--json"],
                          capture_output=True, text=True, cwd=ROOT)
    try:
        data = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError:
        raise OrgError(f"sf {args[0]} {args[1]} returned no readable result")
    if data.get("status", 1) != 0:
        raise OrgError(f"{data.get('name', 'Error')}: {data.get('message', 'no message')}"[:300])
    return data.get("result")


def query(alias, soql, tooling=False):
    args = ["data", "query", "--query", soql] + (["--use-tooling-api"] if tooling else [])
    return (sf(alias, *args) or {}).get("records", [])


def list_metadata(alias, kind):
    result = sf(alias, "org", "list", "metadata", "--metadata-type", kind) or []
    return result if isinstance(result, list) else [result]


def chosen_packages(names):
    with open(os.path.join(ROOT, "sfdx-project.json"), encoding="utf-8") as handle:
        dirs = json.load(handle)["packageDirectories"]
    by_package = {d["package"]: os.path.basename(d["path"]) for d in dirs}
    deps = {os.path.basename(d["path"]): [by_package[x["package"]] for x in d.get("dependencies", [])]
            for d in dirs}
    unknown = [n for n in names if n not in deps]
    if unknown:
        raise SystemExit(f"Unknown package(s): {', '.join(unknown)}. Packages: {', '.join(deps)}")
    chosen, todo = set(), list(names)
    while todo:
        name = todo.pop()
        if name not in chosen:
            chosen.add(name)
            todo.extend(deps[name])
    return [d for d in deps if d in chosen]


class Report:
    def __init__(self):
        self.counts = {"PASS": 0, "WARN": 0, "FAIL": 0}

    def line(self, status, check, text, details=()):
        self.counts[status] += 1
        print(f"{status}  {check}: {text}")
        for detail in details:
            print(f"        {detail}")


def share(used, limit):
    return f"{used:,} of {limit:,} ({100 * used / limit:.0f}%)"


def check_edition(alias, report):
    org = query(alias, "SELECT OrganizationType, IsSandbox FROM Organization")[0]
    edition = org["OrganizationType"]
    where = "sandbox" if org.get("IsSandbox") else "production or Developer Edition"
    if edition in SUPPORTED:
        report.line("PASS", "Edition", f"{edition} ({where}) is supported")
    elif edition in UNSUPPORTED:
        report.line("FAIL", "Edition", f"{edition} is not supported: {UNSUPPORTED[edition]}")
    else:
        report.line("WARN", "Edition", f"{edition} is not one BarnCRM has been checked on")
    starter = [r for r in query(alias, "SELECT Name, UsedLicenses FROM UserLicense")
               if "Starter" in (r.get("Name") or "") and (r.get("UsedLicenses") or 0) > 0]
    for lic in starter:
        report.line("WARN", "Licenses", f"{lic['UsedLicenses']} user(s) on {lic['Name']}: Platform"
                    " Starter is not supported (10 custom objects per user; BarnCRM roles need more)")
    return edition


def check_apex(alias, report, packages, sizes, limit):
    try:
        classes = query(alias, "SELECT Name, LengthWithoutComments, Body FROM ApexClass"
                        " WHERE NamespacePrefix = null", tooling=True)
        triggers = query(alias, "SELECT Name, LengthWithoutComments FROM ApexTrigger"
                         " WHERE NamespacePrefix = null", tooling=True)
    except OrgError as error:
        report.line("FAIL", "Apex", f"Apex could not be read, so it is likely not available: {error}")
        return
    ours = {n for p in packages for n in sizes[p]["classes"]}
    own = sum(c["LengthWithoutComments"] or 0 for c in classes
              if c["Name"] not in ours and not budget.is_test_class(c.get("Body") or ""))
    own += sum(t["LengthWithoutComments"] or 0 for t in triggers if t["Name"] not in ours)
    needed = sum(sizes[p]["size"] for p in packages)
    total = own + needed
    detail = (f"the org's own code {own:,} plus BarnCRM {needed:,}"
              f" ({', '.join(f'{p} {sizes[p]['size']:,}' for p in packages)}) = {share(total, limit)}")
    if total > limit:
        report.line("FAIL", "Apex", f"does not fit: {detail}. Install fewer modules, or ask"
                    " Salesforce support for a higher Apex limit (Admin Guide, Installing BarnCRM)")
    elif total > 0.85 * limit:
        report.line("WARN", "Apex", f"fits with little room: {detail}. Salesforce advises acting"
                    " above 80 to 85%")
    else:
        report.line("PASS", "Apex", f"fits: {detail}")


def check_count(report, check, own, ours, limit, what):
    total = own + ours
    text = f"the org's own {own:,} plus BarnCRM {ours:,} = {share(total, limit)} {what}"
    status = "FAIL" if total > limit else "WARN" if total > 0.9 * limit else "PASS"
    report.line(status, check, text)


def unmanaged(rows):
    return {r["fullName"] for r in rows if not r.get("namespacePrefix")}


def check_names(alias, report, ours, edition):
    upgrade, already, clashed = False, [], False
    for kind in NAME_TYPES:
        wanted = {m for k, m in ours if k == kind
                  and (kind not in STANDARD_CHILDREN or "__" not in m.split(".")[0].split("-")[0])}
        if kind == "CustomObject":
            wanted = {m for m in wanted if "__" in m}
        try:
            existing = unmanaged(list_metadata(alias, kind))
        except OrgError as error:
            report.line("WARN", "Names", f"{kind} could not be listed: {error}")
            continue
        clash = sorted(wanted & existing)
        if kind == "CustomObject":
            upgrade = "BarnCRM_Settings__c" in existing
            own_objects = {o for o in existing if o.endswith("__c")} - wanted
            ours_objects = {m for m in wanted if m.endswith("__c")}
            check_count(report, "Objects", len(own_objects), len(ours_objects),
                        OBJECT_ALLOWANCE.get(edition, 200), "custom objects and settings")
        if kind == "CustomLabel":
            check_count(report, "Labels", len(existing - wanted), len(wanted), LABEL_LIMIT,
                        "custom labels")
        if clash and upgrade:
            already.append(f"{kind} {len(clash)}")
        elif clash:
            clashed = True
            shown = clash[:15] + ([f"... and {len(clash) - 15} more"] if len(clash) > 15 else [])
            report.line("FAIL", "Names", f"{len(clash)} {kind} name(s) the org already uses;"
                        " the deploy would update or fail on them", shown)
    if already:
        report.line("WARN", "Names", "BarnCRM is already in this org (BarnCRM_Settings__c exists),"
                    " so most names it ships are its own and the deploy updates them. A name the"
                    " org's own work shares with BarnCRM cannot be told apart here: run this check"
                    " before the first install", [", ".join(already)])
    elif not clashed:
        report.line("PASS", "Names", "no name the chosen packages ship is in use in the org")


def check_test_fit(alias, report):
    rules = query(alias, "SELECT ValidationName, EntityDefinition.QualifiedApiName FROM ValidationRule"
                  " WHERE Active = true AND EntityDefinition.QualifiedApiName IN ('Account','Contact')",
                  tooling=True)
    if rules:
        names = sorted(f"{r['EntityDefinition']['QualifiedApiName']}.{r['ValidationName']}" for r in rules)
        report.line("WARN", "Test fit", f"{len(rules)} active validation rule(s) on Account or"
                    " Contact. BarnCRM's tests cannot bypass them; a production deploy can fail on"
                    " one (Admin Guide, Installing BarnCRM, If a Test Fails)", names[:15])
    else:
        report.line("PASS", "Test fit", "no active validation rules on Account or Contact")
    for obj in ("Account", "Contact"):
        fields = (sf(alias, "sobject", "describe", "--sobject", obj) or {}).get("fields", [])
        required = sorted(f["name"] for f in fields if f.get("custom") and not f.get("nillable")
                          and f.get("createable") and not f.get("defaultedOnCreate"))
        lookups = sorted(f["name"] for f in fields if f["name"] in required and f["type"] == "reference")
        if lookups:
            report.line("WARN", "Test fit", f"{obj} requires lookup field(s) no test can fill",
                        lookups)
        elif required:
            report.line("PASS", "Test fit", f"{obj} requires {len(required)} custom field(s); BarnCRM's"
                        " test data factory fills them, tests that build records directly may not",
                        required[:15])


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    alias, modules, limit = argv[0], None, budget.ORG_LIMIT
    rest = argv[1:]
    while rest:
        if rest[0] == "--modules" and len(rest) > 1:
            modules = [m for m in rest[1].split(",") if m]
        elif rest[0] == "--apex-limit" and len(rest) > 1:
            limit = int(rest[1])
        else:
            print(f"Unknown option {rest[0]}", file=sys.stderr)
            return 2
        rest = rest[2:]
    os.chdir(ROOT)
    sizes = budget.package_sizes(ROOT)
    packages = chosen_packages(modules or list(sizes))
    ours, _ = manifest.components("HEAD", set(packages))
    print(f"BarnCRM install pre-check for {alias}: {', '.join(packages)} (read-only)")
    report = Report()
    try:
        edition = check_edition(alias, report)
        check_apex(alias, report, packages, sizes, limit)
        check_names(alias, report, ours, edition)
        check_test_fit(alias, report)
    except OrgError as error:
        report.line("FAIL", "Org", f"could not be read: {error}")
    c = report.counts
    print(f"\nResult: {c['FAIL']} fail, {c['WARN']} warn, {c['PASS']} pass."
          + (" Fix every FAIL before installing." if c["FAIL"] else " Read every WARN before installing."
             if c["WARN"] else " Ready to install."))
    return 1 if c["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
