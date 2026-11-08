#!/usr/bin/env python3
"""Keeps each package's Apex code size under a budget.

Salesforce allows 6,000,000 characters of Apex per org (Apex Developer Guide, Size-Specific
Apex Limits; raisable by a support case). Comments, @IsTest classes and code in managed
packages do not count. BarnCRM installs as unmanaged source with no namespace (ADR-0001), so
every non-test class and trigger counts, beside the org's own code. On 2026-11-04 the full
suite measured 4,280,027 characters (71%), and one landing batch had added 12.5%: an org with
about 1.7M characters of its own Apex could no longer take it (architect review L-01, RT-01).
CI runs on scratch orgs, whose limit is 10,000,000, so no org test notices growth.

Size is measured the way the org measures it (ApexClass.LengthWithoutComments): every
character of a non-test class or trigger except comments. oi-test agreed within 2%.

CAPS is a ceiling per package a little above its measured size, so every addition is a
choice: raise a cap only in the pull request that needs it, and say why. TARGET is where the
trim pass should take the full suite and Core (decision 1, 2026-11-04), leaving an org at
least 2,400,000 characters of its own; above a target the check passes and says by how much.

    python3 scripts/ci/check-apex-budget.py            the check
    python3 scripts/ci/check-apex-budget.py --report   sizes per package, largest classes

scripts/org/install-precheck.py reads package_sizes() to compare an org's room with what
the chosen modules need.
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import is_test_class, without_comments  # noqa: E402

ORG_LIMIT = 6_000_000
CAPS = {
    # Set 2026-11-05 to each package's size with Apex indented by tabs (the org counts every
    # leading space, so tabs cut about 19 percent) plus about 2 percent.
    # Raised 2026-11-06 for the Automation tab's whole-org inventory (C-60, D-184:
    # OrgAutomationInventory and OrgAutomationController), then for Scan Org Automation through
    # the org connection (OrgToolingApi, OrgAutomationScan; ADR-0174, D-184), then for Deactivate
    # Org Flows and Validation Rules with its snapshot and Restore (OrgAutomationDeactivation,
    # the controller's deactivate and restore; ADR-0174, D-184), then for the D-184 household
    # changes landed with them (AddressDeleteHandler, Match Sources turned off by a setting,
    # the shipped Organization record type, RelationshipController.isFeatureOn), then for the
    # Form attachment seam (C-42a: FormAttachmentExtension, FormAttachmentExtensions, receipt).
    # Raised 2026-11-06 for the Duplicate Rules Starter (C-61, D-156: DuplicateRulesStarter and
    # OrgMetadataApi, the Metadata API through the org connection), then for Report Subscriptions
    # (C-63, D-156: ReportSubscriptions and OrgToolingApi.rest), then for Radius Find (C-69,
    # D-157: FindRadius, QueryCompiler's radius condition, FindController's center lookup).
    # Batch C landing 2026-11-07: 2,057,941 measured with C-42a, C-61, C-63, C-69, plus 0.4%.
    # Batch C wave 2 landing: 2,066,353 measured (LinkedRecords EV-09, Events settings section,
    # EventVolunteerExtension EV-08, PortalActionExtension PB-01), plus about 2%.
    "core": 2_108_000,
    "rollups": 374_000,
    # Giving raised for the v1.0 usability work: Edit Funds (GiftAllocationController),
    # Quick Gift Entry tribute, match and split (people-giving-13, 16, 23), and the New
    # Commitment screen's shared pledge builder (CommitmentEntry, people-giving-11), and
    # Giving at a Glance (GivingRecordGlanceExtension, people-giving-14), and the Thank-Yous
    # page's rule reorder and missing-template reason (people-giving-18), and the Ask
    # Pipeline's Recently Closed column and Reopen Ask (people-giving-19).
    "giving": 608_000,
    # 2026-11-05: Log Hours, Create Shifts Now, Volunteer Letters (modules-14, 15, 20), Home.
    # Batch C landing 2026-11-07: 187,048 measured with the shift nudge (V-10b), plus 1.5%.
    # Batch C wave 2 landing: 189,775 measured (VolunteersEventExtension EV-08), plus about 2%.
    "volunteers": 193_600,
    # Raised 2026-11-05 for the Record Service action (modules-14, RecordServiceController).
    # Raised 2026-11-06 for repeating session schedules (modules-24, D-183): the run, nightly
    # batch, save job, trigger handler and selector, and the schedule page's controller methods.
    "programs": 168_000,
    "logicmodels": 65_000,
    # Raised from 95,000 for the Funders usability stage: Undo for Mark Received and Mark
    # Submitted, and the award period and Restricted in Record the Award (modules-16, 17).
    "funders": 100_500,
    # Forms engine and builder (C-42a, D-157): submit service, server rules, thin controllers.
    # Batch C landing 2026-11-07: 42,867 measured (C-42a), plus about 2.5%.
    # C-42b public forms (guest intake, allowlist, processor, Health Check, REST): 70,142
    # measured, plus about 2.5%.
    # C-42c files and save for later (FormFiles, the intake's drafts, resume and emailed link,
    # expired-draft cleanup, REST save and resume): 82,204 measured, plus about 2%.
    # Batch C wave 2 landing: 82,322 measured (C-42b, C-42c), plus about 2%.
    # Batch C wave 3 landing: FORMS_WAVE3
    "forms": 95_000,
    # New 2026-11-06 for Contact Point Sync (C-45, ADR-0176 contact point sync module):
    # 43,980 measured with the page and backfill, plus about 2 percent.
    # C-45e (D-186): 45,798 measured with person accounts and household-move sync, plus about 2%.
    # Batch C wave 2 landing: 49,330 measured (C-45e person accounts and household moves), plus
    # about 2%.
    "contactpoints": 50_300,
    # Event Management (ADR-0177, events module): events, tickets, agenda and speakers (EV-01,
    # EV-03 to EV-05).
    # Batch C landing 2026-11-07: 29,211 measured (EV-01, EV-03 to EV-05), plus about 2.5%.
    # Batch C wave 2 landing: 127,556 measured (EV-02, EV-06, EV-08 to EV-12, EV-14, EV-15),
    # plus about 2%.
    # Batch C wave 3 landing: EVENTS_WAVE3
    "events": 200_000,
    # Portal Builder (PB-01, ADR-0185 portal builder): sign-in, sessions, template checks and the
    # person-scoped portal API. 49,205 measured at first build (the API is the security boundary,
    # so every check stays in Apex), plus about 2%.
    # Batch C wave 2 landing: 49,670 measured (PB-01 builder and client), plus about 2%.
    "portal": 50_700,
    "mirror": 182_000,
}
TARGET = {"full suite": 3_600_000, "core": 2_000_000}


def repo_root():
    return subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
    ).stdout.strip()


def package_dirs(root):
    """{short name: path} for every package directory, in sfdx-project.json order."""
    with open(os.path.join(root, "sfdx-project.json"), encoding="utf-8") as handle:
        project = json.load(handle)
    return {os.path.basename(entry["path"]): entry["path"] for entry in project["packageDirectories"]}


def apex_files(root, path):
    out = subprocess.run(
        ["git", "ls-files", "--", f"{path}/*.cls", f"{path}/*.trigger"],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout
    return [f for f in out.splitlines() if f]


def package_sizes(root=None):
    """{package: {"size": chars, "classes": {name: chars}}} for non-test Apex, comments removed."""
    root = root or repo_root()
    sizes = {}
    for package, path in package_dirs(root).items():
        classes = {}
        for rel in apex_files(root, path):
            with open(os.path.join(root, rel), encoding="utf-8") as handle:
                source = handle.read()
            if rel.endswith(".cls") and is_test_class(source):
                continue
            classes[os.path.splitext(os.path.basename(rel))[0]] = len(without_comments(source))
        sizes[package] = {"size": sum(classes.values()), "classes": classes}
    return sizes


def percent(chars):
    return f"{100 * chars / ORG_LIMIT:.0f}%"


def report(sizes):
    total = sum(s["size"] for s in sizes.values())
    for package, data in sizes.items():
        cap = CAPS.get(package)
        print(f"{package:12} {data['size']:>10,} chars  {percent(data['size']):>4}  cap {cap:,}" if cap
              else f"{package:12} {data['size']:>10,} chars  {percent(data['size']):>4}  no cap")
    print(f"{'full suite':12} {total:>10,} chars  {percent(total):>4}  of {ORG_LIMIT:,}")
    largest = sorted(((c, n) for d in sizes.values() for n, c in d["classes"].items()), reverse=True)
    print("largest: " + ", ".join(f"{n} {c:,}" for c, n in largest[:10]))


def main(argv):
    sizes = package_sizes()
    if "--report" in argv:
        report(sizes)
        return 0
    problems = []
    for package, data in sizes.items():
        cap = CAPS.get(package)
        if cap is None:
            problems.append(
                f"{package}: no Apex budget. Add it to CAPS in scripts/ci/check-apex-budget.py"
                f" (measured {data['size']:,} characters)."
            )
        elif data["size"] > cap:
            problems.append(
                f"{package}: {data['size']:,} characters of non-test Apex, over its budget of"
                f" {cap:,} by {data['size'] - cap:,}. The org limit is {ORG_LIMIT:,} for the"
                " org's own code and every BarnCRM package together. Trim, or raise the cap in"
                " this pull request and say why."
            )
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-apex-budget.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    total = sum(s["size"] for s in sizes.values())
    notes = []
    for name, value in (("full suite", total), ("core", sizes.get("core", {}).get("size", 0))):
        if value > TARGET[name]:
            notes.append(f"{name} {value - TARGET[name]:,} over its target of {TARGET[name]:,}")
    note = f"; {', '.join(notes)}" if notes else ""
    print(f"check-apex-budget.py: OK, full suite {total:,} characters ({percent(total)} of"
          f" {ORG_LIMIT:,}), every package under its cap{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
