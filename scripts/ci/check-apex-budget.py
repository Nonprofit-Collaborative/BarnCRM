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
    # Batch C wave 3 landing: 2,073,413 measured (FormCatalogExtension seam EV-18,
    # PublicPageExtension seam EV-16, EventsSampleData registration C-10, portal action
    # registry PB-03 and PB-07), plus about 2%. Main's D-185 feature-off cards and the
    # Automation page's stopped marker merged in within that margin.
    # Combined build (landing/batch-d-i) 2026-11-11: 2,138,788 measured with C-62 Generic Merge,
    # C-67 Archive by Query, C-68 Field History and the MIG-01 Migration Assistant framework,
    # plus about 1%; the pre-batch review's trim pass looks at Core again.
    # Raised 2026-11-11 for C-47 multi-brand management (BrandService seam and defaulting,
    # BrandShareJob visibility upkeep, BrandTriggerHandler, BrandShareWriter): 2,160,448
    # measured, plus about 0.5%.
    # Raised 2026-11-11 for C-64 engagement score (EngagementScore, EngagementScoreJob, the
    # EngagementSignalExtension seam, EngagementScoreController): 2,175,829 measured, plus about 2%.
    # Raised 2026-11-12 for MIG-02b Nonprofit Cloud household conversion (the adoption service
    # and batch take a source key, join members in Junction mode and undo them; the Household
    # Model guard in HouseholdSelector): 2,221,240 measured, plus about 0.5%.
    # Raised 2026-11-12 for R1.21 namespace readiness (D-199, D-200: BarnInstallCheck, the setup
    # bootstrap and revisions, SetupObjectSelector, NamespaceUtil.field and describe; the
    # modules shrank by moving their lookups onto Core): 2,233,198 measured, plus about 0.3%.
    # W15 R1.22 (D-200 P5, P7, P12, P13) fit under it: 2,230,377 measured with them; with
    # AsyncStarter and its call sites (P9), 2,232,757; with address match keys (P6), 2,238,235.
    # With D-200 P4 and P10 (Error Log repeats coalesced, refused rows logged once, the rollup
    # write flag): 2,243,035 measured, raised by what they add plus about 0.1%.
    "core": 2_245_300,
    # Raised 2026-11-11 for MIG-08 Import From NPSP (RollupNpsp reads NPSP customizable rollups
    # into the DLRS shape, so the import, compare and same-field guard are reused, not copied)
    # and the rollup Migration Kits' check (RollupsMigrationKit, MIG-01): 381,657 measured
    # before the kit check, plus about 1%.
    # AR-01 (D-172): messages read with BarnHelp.text instead of Label; 386,438 measured, plus
    # about 0.5%.
    # Raised 2026-11-12 for D-200 P2 and P13 (the large parent throttle and the processor
    # request stamp, so a save queues totals without a query): 390,436 measured, plus about 0.5%.
    # D-200 P1 (RollupNightlyBatch: the weekly full sweep and the nightly pass over what changed)
    # on the batch-k AsyncStarter call sites: 403,678 measured, plus about 0.5%.
    "rollups": 405_700,
    # Giving raised for the v1.0 usability work: Edit Funds (GiftAllocationController),
    # Quick Gift Entry tribute, match and split (people-giving-13, 16, 23), and the New
    # Commitment screen's shared pledge builder (CommitmentEntry, people-giving-11), and
    # Giving at a Glance (GivingRecordGlanceExtension, people-giving-14), and the Thank-Yous
    # page's rule reorder and missing-template reason (people-giving-18), and the Ask
    # Pipeline's Recently Closed column and Reopen Ask (people-giving-19).
    # Combined build 2026-11-11: 610,858 measured with G-33's donor panel and G-37's pledge job,
    # plus room for G-27 still to come.
    # Release 1.15: G-34 donation pages and PAY-03 portal payments, 630,018 measured 2026-11-11,
    # plus room for G-27.
    # With G-27, C-47b/d/e brands and the C-64 signal: 645,083 measured 2026-11-11, plus about
    # 0.5%; the pre-batch review trims it.
    # AR-01 messages move (D-172): BarnHelp.text('Giving', key) in place of Label.<name>,
    # 654,593 measured 2026-11-12 with all five parts, plus about 0.5%.
    # Giving and Money review fixes (bulk payment listener, status stepping, card-testing
    # limits, portal payment guard, donation form Health Check): 663,899 measured 2026-11-12,
    # plus about 0.5%.
    # PAY-04 (D-196): the subscriptions listener and Update Card / automatic Pay Online,
    # 669,581 measured 2026-11-12, plus a small margin; both reuse the PAY-03 classes.
    # W14 QA defect D6: donor levels compare totals and rungs in the corporate currency in a
    # multi-currency org (reusing RollupCurrency), 672,127 measured 2026-11-12; raised by the
    # 2,546 added, plus about 2%. Plus 140 for PD3: the gift import's undo logs its failed
    # deletes in one statement (ErrorLogger.logEach). Plus 1,680 for W15 R1.22 (D-200 P12):
    # Health Check lookup skew on funds and appeals, gift ownership skew. Plus 270 for D-200
    # P9: buttons and nightly steps start their jobs through AsyncStarter.
    # D-200 P1: the nightly donor pass runs in full only when needed and otherwise rescores
    # donors crossing a recency cutoff; 676,573 measured, raised by the 2,283 added plus 2%.
    "giving": 676_620,
    # 2026-11-05: Log Hours, Create Shifts Now, Volunteer Letters (modules-14, 15, 20), Home.
    # Batch C landing 2026-11-07: 187,048 measured with the shift nudge (V-10b), plus 1.5%.
    # Batch C wave 2 landing: 189,775 measured (VolunteersEventExtension EV-08), plus about 2%.
    # Batch C wave 3 landing: 193,083 measured (VolunteersPortalExtension PB-03), plus about 2%.
    # VOL-2 (V-14, V-16): 206,823 measured with the shift waitlist, group and standing sign-ups
    # and the one self-booking path (VolunteerCapacity, VolunteerStanding, VolunteerBooking),
    # plus about 2%.
    # VOL-3 (V-12, V-13, V-15): 217,833 measured with the value of hours on Home and in letters,
    # the thank-you run (VolunteerRecognitionJob and its scheduler) and the minors check
    # (VolunteerMinors), plus about 2%.
    # VOL-4 (V-09): 230,699 measured with the public shift pages and personal page
    # (VolunteerPublicPage), the shift and profile forms (VolunteerFormAttachment) and the
    # reminder's personal link, plus about 2%.
    # C-47b brand letters and the C-64 signal: 235,670 measured 2026-11-11, plus about 0.5%.
    # AR-01 (D-172): messages read with BarnHelp.text instead of Label; 237,172 measured, plus
    # about 0.5%.
    # Lowered at the cut-over cleanup (D-200, release 1.21: the retired Coordinator check gone,
    # settings read through SettingsService): 230,596 measured 2026-11-12, plus about 2%.
    "volunteers": 235_300,
    # Raised 2026-11-05 for the Record Service action (modules-14, RecordServiceController).
    # Raised 2026-11-06 for repeating session schedules (modules-24, D-183): the run, nightly
    # batch, save job, trigger handler and selector, and the schedule page's controller methods.
    # VOL-2 (P-09): 172,177 measured with program capacity and the waitlist (EnrollmentCapacity),
    # plus about 2%.
    # Release 1.19 P-10/P-11 sample goals, cohort and sessions: 175,965 measured, plus about 1%.
    # AR-01 (D-172): messages read with BarnHelp.text instead of Label; 177,950 measured, plus
    # about 0.5%.
    "programs": 178_900,
    # Raised for the assumption evidence log (L-05): saveEvidence, evidence on each arrow and
    # the describe-built evidence words; 65,800 measured, plus about 1%. With L-04b's PDF method:
    # 66,645 measured 2026-11-11, plus about 0.5%.
    # AR-01 (D-172): messages read with BarnHelp.text instead of Label; 67,478 measured, plus
    # about 0.5%.
    "logicmodels": 67_800,
    # Raised from 95,000 for the Funders usability stage: Undo for Mark Received and Mark
    # Submitted, and the award period and Restricted in Record the Award (modules-16, 17).
    # Grant management (F-09 to F-13, release 1.11): 124,151 measured with the Grant Finder,
    # checklists, documents, budget lines and renewals, plus about 2%.
    # Lowered at the cut-over cleanup (D-200, release 1.21): 123,925 measured 2026-11-12, plus
    # about 2%.
    "funders": 126_500,
    # Forms engine and builder (C-42a, D-157): submit service, server rules, thin controllers.
    # Batch C landing 2026-11-07: 42,867 measured (C-42a), plus about 2.5%.
    # C-42b public forms (guest intake, allowlist, processor, Health Check, REST): 70,142
    # measured, plus about 2.5%.
    # C-42c files and save for later (FormFiles, the intake's drafts, resume and emailed link,
    # expired-draft cleanup, REST save and resume): 82,204 measured, plus about 2%.
    # Batch C wave 2 landing: 82,322 measured (C-42b, C-42c), plus about 2%.
    # Batch C wave 3 landing: 88,379 measured (FormsCatalogExtension EV-18, public event pages in
    # the intake, controller and REST EV-16), plus about 2%.
    # Batch C review: 91,118 measured (save-for-later caps per address and per form, REST
    # failures logged and answered Failed), plus about 2%. Batch C review landing: 91,142
    # measured with every review branch merged; 93,000 still leaves about 2%.
    "forms": 93_000,
    # New 2026-11-06 for Contact Point Sync (C-45, ADR-0176 contact point sync module):
    # 43,980 measured with the page and backfill, plus about 2 percent.
    # C-45e (D-186): 45,798 measured with person accounts and household-move sync, plus about 2%.
    # Batch C wave 2 landing: 49,330 measured (C-45e person accounts and household moves), plus
    # about 2%. Batch C gate fixes: 50,837 measured (sync reads each kind once per new person,
    # no adoption lookup on Individuals it created), plus about 2%. Large saves queued (ADR-0176
    # decision 16, describe cached once a transaction): 54,759 measured, plus about 2%.
    # Batch C review: 59,043 measured (fewer queries a sync, a second change in one transaction
    # synced, capitals counted as a change), plus about 2%. Erasure start seam (ADR-0193): 60,319
    # measured (one address sync per erasure), plus about 2%. Batch C review landing: 61,454
    # measured with every review branch merged (QA's per-values claim, perf's watched-field
    # reads, the erasure start seam), plus about 2%.
    "contactpoints": 62_700,
    # Event Management (ADR-0177, events module): events, tickets, agenda and speakers (EV-01,
    # EV-03 to EV-05).
    # Batch C landing 2026-11-07: 29,211 measured (EV-01, EV-03 to EV-05), plus about 2.5%.
    # Batch C wave 2 landing: 127,556 measured (EV-02, EV-06, EV-08 to EV-12, EV-14, EV-15),
    # plus about 2%.
    # Batch C wave 3 landing: 186,595 measured (sample data C-10, EV-13 seating, EV-17 badges,
    # EV-18 survey, EV-19 calendar, EV-16 public pages, PB-07 EventsPortalExtension), plus
    # about 2%.
    # Release 1.5 EVT-A (branch feature/evt-a-ev20-21-26-27): 217,924 measured (EV-20 paid
    # registration through Payments, EV-21 proposal scoring, EV-26 badge overrides, EV-27
    # session ratings), plus about 2%.
    # Releases 1.11 to 1.13 EVT-B (branches feature/evt-b-*): 247,001 measured (EV-22 attendee
    # app actions, EV-23 budget, EV-24 venue and room fills, EV-25 speaker checklist, EV-28
    # booth scans, EV-29 agenda picks and ratings), plus about 2%.
    "events": 252_000,
    # Portal Builder (PB-01, ADR-0185 portal builder): sign-in, sessions, template checks and the
    # person-scoped portal API. 49,205 measured at first build (the API is the security boundary,
    # so every check stays in Apex), plus about 2%.
    # Batch C wave 2 landing: 49,670 measured (PB-01 builder and client), plus about 2%.
    # Batch C wave 3 landing: 50,774 measured (PB-03, PB-07, PB-08 templates: the read-only
    # person link through one parent for the speaker's sessions), plus about 2%.
    # Batch C review: 53,465 measured (one answer for every wrong code, authenticator codes used
    # once, where values typed at parse time), plus about 2%. Batch C review landing: 54,467
    # measured (QA's sign-in fixes plus perf's and simplification's portal changes), plus about 2%.
    # Releases 1.11 to 1.13 EVT-B (branch feature/evt-b-r1-11-portal-engine): 59,734 measured
    # (personScope catalogs read and checked in Apex, calendar, download and scan options), plus
    # about 2%.
    "portal": 61_000,
    # Corporate Hub (CH-01 to CH-08, ADR-0196 corporate hub module): access sync, post-install,
    # the policy, compliance, reminder and template services and the page controller, 29,744
    # measured, plus about 2%. Board governance (CH-09 to CH-20, PB-02): HubBoard, the board and
    # meeting panel controller and the board portal actions, 51,443 measured, plus about 2%.
    # GDPR set (CH-05): processing activity templates, DPIA, request and breach reminders, the
    # erasure link and the page's Data Protection rows, about 57,100 measured, plus about 2%.
    # Quorum warning and immediate breach bell (CH-21, CH-22): 59,376 measured, plus about 2%.
    # Lowered at the cut-over cleanup (D-200, release 1.21): 59,285 measured 2026-11-12, plus
    # about 2%.
    "corporatehub": 60_500,
    # Payments (PAY-01, ADR-0201 payments module): checkout, receiver, processing and Health
    # Check measured 47,575 on 2026-11-11, plus about 2 percent; raised the same day for the
    # Payments Setup page's controller, measured 52,331.
    # Giving and Money review fixes (bulk listener call, abandon job, callout-time budget,
    # countRecent, PayPal refund capture, Schedule button): 55,965 measured 2026-11-12, plus
    # about 0.5%.
    # PAY-04 subscriptions (D-196, ADR-0218 payments subscriptions): Stripe and PayPal
    # subscription checkouts, renewals, subscription news to listeners and Update Card:
    # 69,202 measured 2026-11-12, plus about 0.5%.
    # PayPal plan reuse (D-198, ADR-0218 amendment): one shared product, plans found by key and
    # replaced when PayPal refuses them, 72,087 measured 2026-11-12; raised by the 2,702 added,
    # plus about 2%.
    # W14 QA defect D2: the PayPal receiver refuses posts while PayPal is not set up, checks
    # the resource and event type before storing, and caps per processor, 72,846 measured
    # 2026-11-12; raised by the 759 added, plus about 2%.
    "payments": 72_900,
    # LWC Builder (LB-01 to LB-06, ADR-0203 lwc builder module): the builder and renderer
    # controller, the App Builder picklist, access sync and post-install, 17,322 measured, plus
    # about 2%. LB-07 (D-196) charts by two groupings and three totals: 19,741 measured, plus
    # about 1%. Release 1.20 review: the chart walk over plain inputs so it can be unit tested:
    # 21,351 measured, plus about 2%. Lowered at the cut-over cleanup (D-200, release 1.21):
    # 20,959 measured 2026-11-12, plus about 2%.
    "lwcbuilder": 21_400,
    # Scholarships and Outbound Grants (SG-01 to SG-10, PB-06, ADR-0204 scholarships module):
    # reviews, awards, form intake, portal actions, reminders, the payment rule and the page
    # controller, plus the review and requirement DTOs (R1.21 namespace readiness, D-200 N3),
    # 51,267 measured (Prettier line breaks included), plus about 2%.
    "scholarships": 52_300,
    # Territory Management (C-40, C-40b, ADR-0205 territory management module): the model PR
    # ships no Apex (0 measured). The Apex PR: access sync, post-install, routing, the run
    # batch, the page controller and the nightly step, 31,041 measured, plus about 2%.
    # W10: chunk size by rule count, 31,845 measured, plus about 0.5%.
    "territory": 32_000,
    # Memberships (G-22a to G-22d, PAY-02, ADR-0206 memberships module): terms, renewals, the
    # nightly run, payment links, the Essentials kit, portal and erasure seams, 39,406 measured
    # on 2026-11-11, plus about 2 percent. PB-09's directory adds no Apex. Raised 2026-11-11 for
    # G-22e certifications (CertificationService, CertificationController, the erasure and
    # nightly expiry hooks): 47,443 measured, plus about 1 percent. Raised 2026-11-12 for the
    # erasure extension's system-mode find and access check (d96088f3d): 49,088 measured, plus
    # about 0.5 percent.
    "memberships": 49_340,
    # Project Management (PM-01 to PM-05, ADR-0208 project management module): access sync,
    # post-install, health, templates, reporting and the page controller, 32,637 measured,
    # plus about 2%. PSA model (D-197, ADR-0219 projects PSA): the PSA settings accessors,
    # 34,147 measured; each PSA builder raises it by what its own classes measure. Builder B
    # (PM-09 ProjectStaffingController and the utilization change): 7,751 measured. Builder A
    # (PM-06 to PM-08: rates, entry handler, timesheet and approvals): 17,221 measured. 59,119 in
    # all. Builder C billing (PM-10: ProjectBilling, ProjectBillingController,
    # ProjectInvoiceDocument, the return page default): +17,760. Pay Online through Payments by
    # name (ProjectInvoicePayments and its listener, R-PM22): +7,302. Financials and recognized
    # revenue (PM-11: ProjectFinancials, ProjectRevenue and its nightly step, health with change
    # hours): +12,766. 97,102 measured, plus about 2%. Review fixes (#1237: invoice delete guard,
    # row cap, resources helper) and the release-gate fixes (revenue Chunk queueable, rate query):
    # 99,230 measured, plus about 2%. Lowered at the cut-over cleanup (D-200, release 1.21:
    # settings read through SettingsService): 98,588 measured 2026-11-12, plus about 2%. The
    # ProjectViews DTOs (R1.21 namespace readiness, D-200 N3): 106,037 measured, plus about 2%.
    "projects": 108_200,
    # Address Verification (C-46, ADR-0209 address verification module): the Smarty and Google
    # lookups, the handler, the job, setup page controller and Health Check, measured 24,710 on
    # 2026-11-11, plus about 2 percent.
    "addressverification": 25_300,
    # Mirror: the NPSP gifts migration kit's extension (MIG-05), 187,295 measured, then the
    # Nonprofit Cloud gifts kit's (MIG-04), 195,957 measured, then the Nonprofit Cloud
    # relationships kit's (MIG-02), about 200,500 combined, plus about 1%.
    # AR-01 (D-172): Opportunity mirror messages read with BarnHelp.text instead of Label;
    # 202,751 measured, plus about 0.5%. With the other Mirror messages: 204,549 measured, plus
    # about 0.5%. MIG-02b Nonprofit Cloud households (NpcHouseholdSource, the drift finding):
    # 214,101 measured, plus about 0.5%. Release 1.20 review: per-field readable membership
    # reads and the member-count filter: 215,838 measured, plus about 2%. Lowered at the
    # cut-over cleanup (D-200, release 1.21: MirrorAccessSync and the five retired permission
    # sets removed): 212,177 measured 2026-11-12, plus about 2%.
    "mirror": 216_500,
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
