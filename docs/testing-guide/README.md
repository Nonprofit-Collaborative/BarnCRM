# BarnCRM Testing Guide

Applies to: BarnCRM main as of 2026-10-29 (landing batch 13). Pre-release: no package version exists yet; this tracks the newest code on main.

Manual, step-by-step test scripts for checking a build in a scratch org or sandbox, feature by
feature. Written for a tester: the project owner or a pilot org admin. Start with
[Before you test](before-you-test.md).

> **Not for production orgs:** BarnCRM is in pilot. We do not recommend installing pilot or testing versions in a production Salesforce org. Test in a sandbox, a free Developer Edition org or a scratch org.

**Report a bug or give feedback** through GitHub: open
<https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new/choose> and choose the bug report
template. [SUPPORT.md](../../SUPPORT.md) says what to include, and
[Report a failure](before-you-test.md#report-a-failure) says how to fill it in from a test
script. Never include donor or other personal data. Report a security problem privately, as
[SECURITY.md](../../SECURITY.md) describes.

## How This Relates to the Automated Tests

Two layers check every build.

| Layer | What it is | What it proves |
|---|---|---|
| Apex test gate | `scripts/org/run-org-tests.sh <alias>` deploys the checked-out commit and runs every Apex test class in it (about 3,500 tests), then posts the result to GitHub as the commit status the merge rule requires. See [CI](../contributor-guide/ci.md), "The org test gate". | Logic: triggers, services, rollups, validation, sharing, permission checks in code. |
| Manual scripts (this guide) | A person follows numbered steps in a real org and compares what they see with the expected result. | What the gate cannot see: that pages, tabs, buttons and labels are there and say the right thing, that setup flows work end to end, that a user without a permission set is refused in the UI, that undo really puts data back as a person sees it, and that pages work with a keyboard and on a phone. |

Run the gate first. A build that fails it is not ready for manual testing. Scale and the full
mobile audit have their own plan: [Scale and mobile test plan](../contributor-guide/scale-and-mobile-test-plan.md).

## Script IDs

Each script is `T-<AREA>-NN`, numbered from 01 within its page, for example `T-GIFT-04`. An ID
is never reused for a different test. A script added later takes the next free number on its
page, even if that puts it out of reading order.

## Pages

| Page | Area code | Scripts | Covers |
|---|---|---|---|
| [Before you test](before-you-test.md) | | | Test org, modules, sample data, test users, editions, recording and reporting results |
| [People and households](people-and-households.md) | HH | 20 | Households, members, naming and greetings, merge and split, preferred phone, interactions, record pages, record types |
| [Addresses](addresses.md) | ADDR | 19 | Address records, primary address, the Address Updates setting, Use for Whole Household and Update Everyone's Address, seasonal addresses and the nightly swap, address history (status, dates, former addresses, undeliverable) and Address Card Fields |
| [Relationships and affiliations](relationships-and-affiliations.md) | REL | 10 | Two-sided relationships, affiliations, primary affiliation |
| [Apps and Navigation](apps-and-navigation.md) | APP | 3 | The four BarnCRM apps, who sees each, their tabs, App Navigation Style, module pages in them |
| [Settings and Module Manager](settings-and-module-manager.md) | SET | 19 | BarnCRM Settings console, Access, Module Manager, editions, automation control, home page, organization address, values from Setup, Integrations, People and Households and boxes, keeping a shown default, Finish Setup |
| [Setup Assistant](setup-assistant.md) | SA | 11 | First-run setup, edition choice, Setup Assistant steps, sample data load and remove |
| [Imports](imports.md) | IMP | 21 | Import wizard, templates, row rules, matching (including match sources), several sheets, two-part headings, best guesses for near spellings, several objects in one file, new fields from a column, undo, row retention, correcting and retrying rows |
| [Find](find.md) | FIND | 10 | Query builder, typed queries, export, saved queries, summaries, Show More |
| [Bulk update and delete](bulk-update-and-delete.md) | BULK | 13 | Bulk update, bulk delete, edit in Find, undo, the bulk path, Super Transform |
| [Data Manager and job history](data-manager-and-job-history.md) | DM | 11 | Data Manager, data jobs and undo, data quality checks, field utilization and its snapshot history |
| [Duplicates](duplicates.md) | DUP | 17 | Duplicate scan, review and merge, match sources, similar names, merge rules, auto-merge and its undo |
| [Org Optimizer and Health Check](org-optimizer-and-health-check.md) | HC | 13 | Health Check findings and fixes, Org Optimizer sections, storage and limits, Data Dictionary, Access Explorer, Access compare and Modify All report, weekly admin summary |
| [Erase a person](erase-a-person.md) | ERASE | 8 | Person erasure, preview, permission |
| [Giving: gifts, funds and batches](giving-gifts-funds-batches.md) | GIFT | 15 | Funds, gifts, Quick Gift Entry, in-kind, appeals, gift batches, closed periods, gift import |
| [Giving: commitments](giving-commitments.md) | COM | 10 | Pledges, recurring gifts, payments, nightly jobs |
| [Giving: soft credits, tributes and matching](giving-soft-credits-tributes-matching.md) | CRED | 10 | Soft credits, tributes, matching gifts |
| [Giving: receipts and acknowledgments](giving-receipts-and-acknowledgments.md) | RCPT | 13 | Receipts, year-end statements, void and reissue, receipt lock, acknowledgments |
| [Giving: refunds and write-offs](giving-refunds.md) | REF | 7 | Refunds and their effect on totals |
| [Giving: rollups and dashboards](giving-rollups-and-dashboards.md) | GRD | 7 | Giving totals, recalculation, dashboards and reports |
| [Mirror](mirror.md) | MIR | 13 | Campaign sync, Opportunity mirror, accounting export, Inbound Gift API |
| [Volunteers](volunteers.md) | VOL | 13 | Jobs, shifts, sign-ups, hours and approval, skills |
| [Rollup Builder](rollup-builder.md) | RB | 26 | Building, recalculating and switching rollups, standard objects, parity options, export and import, instant totals on other objects |
| [Accessibility and mobile](accessibility-and-mobile.md) | A11Y | 9 | Keyboard, focus, screen reader labels, zoom, Salesforce mobile app |

## Smoke List (Every Build, About One Hour)

Run these in this order on one Person Accounts org set up as in
[Before you test](before-you-test.md), all modules deployed and sample data loaded. Some later
scripts use what an earlier one created, so keep the order.

**Core-only real-org sandbox (for example `mwdbdevsb`).** Run items 1 to 15 only; skip 16 to 25
(Giving, Volunteers and Rollup Builder are not deployed). Set up as in
[Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox): Core deployed
with `--core-only`, no sample data, work in the **BarnCRM** app, hold **BarnCRM Admin Group**,
and create the **Zztest** fixture first. Read Garcia as Zztest in every script. Extra
permissions: **BarnCRM Duplicate Review** for item 13 and **BarnCRM Erase People** for item
15 only, removed straight after. Item 15 erases a fixture contact you created (Luis Zztest),
never a real person. For item 3, give and remove the role on the other tester, never a real staff member. Item 1 (T-SA-01) is Skipped if setup was finished already, and its
steps 1 and 2 need a staff user, so run steps 3 to 8 only.
| # | Script | Checks |
|---|---|---|
| 1 | [T-SA-01](setup-assistant.md#t-sa-01-first-run-setup-every-feature-on), steps 3 to 8 | First-run setup, Nonprofit Edition. Run it on the test org the first time you open it, instead of a separate org; ignore the sentence about modules in step 3. |
| 2 | [T-SET-01](settings-and-module-manager.md) | Settings console opens |
| 3 | [T-SET-04](settings-and-module-manager.md) | Give and remove a role on the Access page |
| 4 | [T-HH-01](people-and-households.md) | A new person gets a household |
| 5 | [T-HH-02](people-and-households.md) steps 1 to 3, then [T-HH-07](people-and-households.md) | Add Ben to the Testwell household (T-HH-07 needs him), then merge two households |
| 6 | [T-ADDR-01](addresses.md) | Add a seasonal address |
| 7 | [T-REL-01](relationships-and-affiliations.md) | Two-sided relationship |
| 8 | [T-IMP-01](imports.md) | Import a contact list |
| 9 | [T-IMP-03](imports.md) | Undo an import |
| 10 | [T-FIND-01](find.md) | Build and run a query |
| 11 | [T-BULK-01](bulk-update-and-delete.md) | Bulk update |
| 12 | [T-BULK-02](bulk-update-and-delete.md) | Undo a bulk update |
| 13 | [T-DUP-01](duplicates.md) | Duplicate scan |
| 14 | [T-HC-03](org-optimizer-and-health-check.md) | Health Check report (skipped install steps add findings: see the script) |
| 15 | [T-ERASE-02](erase-a-person.md) | Erase a person (in a real-org sandbox: only Luis Zztest, with **BarnCRM Erase People** given for this script only) |
| 16 | [T-GIFT-01](giving-gifts-funds-batches.md) | Default fund (later Giving scripts need it) |
| 17 | [T-GIFT-04](giving-gifts-funds-batches.md) | Quick Gift Entry |
| 18 | [T-GIFT-08](giving-gifts-funds-batches.md) | Gift batch: enter, balance, post |
| 19 | [T-COM-01](giving-commitments.md) | Pledge and schedule |
| 20 | [T-CRED-01](giving-soft-credits-tributes-matching.md) | Household soft credits |
| 21 | [T-RCPT-01](giving-receipts-and-acknowledgments.md), [T-RCPT-02](giving-receipts-and-acknowledgments.md) | Receipt settings, then issue a receipt |
| 22 | [T-REF-01](giving-refunds.md) | Refund a gift |
| 23 | [T-GRD-01](giving-rollups-and-dashboards.md) | Recalculate giving totals |
| 24 | [T-VOL-02](volunteers.md), [T-VOL-03](volunteers.md) | Create a shift, sign people up |
| 25 | [T-RB-01](rollup-builder.md) | Rollup Builder opens, nightly run scheduled |

T-ERASE-02 and T-REF-01 change sample data that other scripts name; if you go on to the full
list in the same org, run them last or refresh the org first.

## Full Regression List

Every script on every page above, before a release or after a change that touches many areas.
Run Core pages first (People and households through Erase a person), then Giving, then Mirror,
Volunteers and Rollup Builder, then Accessibility and mobile. Within a page, run in ID order.

Run it on the Person Accounts shape, then repeat the Core pages and the Giving pages on the
platform-only shape (Mirror needs Opportunity and Campaign, so skip it there). Scripts that need
their own org (for example T-SA-01 and T-SA-02, which need an org never opened) say so in their
prerequisites.

Two scripts change org state that other scripts are hard to run after: closing an accounting
period (T-GIFT-10) blocks removing sample data, and erasing a person (T-ERASE pages) cannot be
undone. Each page notes this where it applies.

## Keeping This Guide Current

The guide tracks main. A pull request that adds or changes a feature visible in the UI updates
the matching page here in the same pull request, as it does the
[feature catalog](../barncrm-features.md). A new feature area gets a new page and a row in the
table above.
