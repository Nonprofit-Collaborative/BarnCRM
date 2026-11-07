# BarnCRM Overview

Applies to: BarnCRM landing/batch-b (v1.0 scope, releases 0.15 to 0.17), to be set to the final main merge commit at landing. Pre-release: no package version exists yet; this tracks the newest code on main.

## What BarnCRM Is

BarnCRM is a free, open source suite of apps that installs into your organization's Salesforce account and turns it into a working database for people, households, gifts and more. It is built for small and medium organizations with one to ten Salesforce users and no full-time Salesforce administrator. The person who sets it up is an operations manager, development director or executive director who is comfortable with spreadsheets.

Three promises shape it:

- **The numbers are right.** Totals show when they were last calculated, so they never go quietly stale.
- **Upgrades are safe.** Nothing you configure is overwritten by a new version, and nothing has to be cloned to be used.
- **It is open.** The source is public, the software is free, and no data leaves your Salesforce org.

Every setting an administrator needs lives on a page inside the app (BarnCRM Settings), not only in Salesforce Setup. The few changes only Setup can make are listed where they matter, each with numbered steps and a button that opens the right Setup page. Settings are named in plain sentence case, the save bar says which changes are in the section you are on, and a panel that saves itself says so.

BarnCRM is in development. No package version exists yet and nothing is installable from a listing, so this page describes what is built on the main branch of the source code. It installs from source into Enterprise, Unlimited and Developer Edition orgs, Nonprofit Cloud included, with Platform licenses supported; Professional Edition and Platform Starter are not. A read-only pre-check tells you first whether your org has room: see [Installing BarnCRM](admin-guide/installing.md).

> **Not for production orgs:** BarnCRM is in pilot. We do not recommend installing pilot or testing versions in a production Salesforce org. Use a sandbox, a free Developer Edition org or a scratch org.

## Two Editions

Both editions include the full core suite of tools: people, households, relationships, addresses, importing with undo (an admin can create a new field for a column), Find, Super Transformer and bulk delete, duplicate review, Org Optimizer, Health Check, settings and the Setup Assistant.

| Edition | For | What you get |
|---|---|---|
| **Standard Edition** | Any organization on Salesforce, including businesses and clubs | BarnCRM Core alone. No nonprofit wording or module is shown. |
| **Nonprofit Edition** | Nonprofits (any organization may choose it) | Core plus the nonprofit tools: Giving first, then the other modules as you turn them on. |

You choose the edition once, in the first-run setup window; the Setup Assistant shows that answer. You can change it later: see [Editions](admin-guide/editions.md). A module you never install leaves nothing behind in your org.

## Packages and Their State on Main

| Package | What it holds | State on main |
|---|---|---|
| **Core** | Households and people, relationships, affiliations, addresses, record pages with Details, Connections and Related tabs, the BarnCRM apps (everyday and admin, each with standard or console navigation), Settings console, Setup Assistant, Module Manager, access roles, Super Importer, Data Manager (one home for every data tool, with a "What do you want to do?" task search), Find, bulk delete, Super Transformer (bulk changes without a file, with saved step lists and a phone format), Org Optimizer, Duplicates, Health Check, Error Log, erase a person, one nightly run that takes every package's nightly jobs in turn | Built |
| **Rollup Builder** | The rollup engine and the Rollup Builder page where you manage totals | Built (offered in both editions; Giving depends on it) |
| **Giving** | Gifts, funds, Quick Gift Entry, gift batches, refunds, in-kind gifts, commitments, pledge reminders, soft credits, tributes, matching gifts, appeals, acknowledgments, receipts and year-end statements, donor levels, donor scores (recency, frequency, amount) and giving pattern, stewardship plans, the Ask Pipeline, retention reports, donor segments with export for email tools, posting and closed periods, gift import, the Giving dashboard, the BarnCRM Fundraising app opening on Fundraising Home (five "today" figures, Enter a Gift, the setup pages as tiles, giving report charts) | Built |
| **Mirror** | Opportunity mirror, Campaign sync, inbound gift API, accounting export, Gift Transaction mirror for Nonprofit Cloud (gifts and their designations, one way) | Built (Gift Transaction mirror in review for release 0.17, X-07) |
| **Volunteers** | Jobs, shifts, sign-ups, Close Shift, hours with approval and a Log Hours action, skills, requirements, recurring shifts with Create Shifts Now, shift reminder emails, suggested volunteers for a shift, hour letters and certificates (one person, or many from Approve Hours), the BarnCRM Volunteers app with Volunteers Home | Built and tested on main |
| **Programs** | Programs, services, enrollments with stages, the Program Roster panel, a person's Programs card, attendance and service delivery with the Service Delivery Log, intake and eligibility fields, private case notes, participant service plans with goals, steps and reviews (linked to Logic Models outcomes where installed), cohorts with mass enrollment, scheduled sessions with start and end times and attendance per session, repeating session schedules that keep sessions created a set number of weeks ahead (8 by default), counts of people served without names, referrals in and out, eligibility screening rules, a participant privacy preset, a program dashboard, a roster import template, sample data, the BarnCRM Programs app and its settings page | Built (release 0.12, P-01; release 0.13, P-02; release 0.14, P-04 to P-08; release 0.15, P-10 to P-14, in review) |
| **Logic Models** | The Logic Model Builder: inputs, activities, outputs, outcomes and impact with arrows and assumptions (by button or drag and drop), for the organization or a program, and indicators with a baseline and a target and result per period, results typed in, imported with the Indicator Results template or computed nightly from a Find saved query, and the Logic Model Report comparing periods as CSV or a printable page; the BarnCRM Logic Models app | Built (release 0.14, L-01 and L-02; release 0.15, L-03 and L-04) |
| **Funders** | Grants from funder organizations through the stages from prospect to awarded or declined, with amounts requested and awarded, stage dates, the program a grant pays for, funding source and government award fields, the Grant Pipeline board with totals and upcoming deadlines (move a grant by its menu or by dragging it), a grant page in tabs (Overview, Money, Reporting, Writing), a Grant Calendar of the month's deadlines and expected payments, the reports and deliverables each award requires with reminder tasks and emails before they are due, requirements linked to Logic Models outcomes with their results when both modules are installed, multi-year award schedules with payments marked received, a restricted ledger per grant with its balance, the Giving fund a grant is booked to (Giving optional), an answer library for applications, funder reports merged from templates as printable files, a Board Dashboard with the revenue mix, concentration and restricted balances that is the BarnCRM Funders app's home and prints for a board packet, the BarnCRM Funders app | Built (release 0.16, F-01, F-02, F-04 to F-07 and F-14; release 0.17, F-03, F-08 and L-06; in review) |
| **Events** | Simple event registration and attendance | Planned (after 1.0) |

The feature-by-feature list, with the status of each item, is the [feature catalog](barncrm-features.md).

## What an Org Gets Today

Install Core and run the Setup Assistant, and you can:

- Keep households and the people in them, with household names and greetings built for you and a warning when someone you are adding is already in BarnCRM, merge and split households, and record relationships, affiliations, addresses (including seasonal ones), several email addresses and a preferred phone. Each relationship, affiliation and address can be opened, edited or ended straight from its line on the person's page.
- Bring in a spreadsheet (CSV or Excel) with a preview, matching rules and one-click undo, find and export records (and keep a search to run again), change many records at once (Find hands its search to Super Transformer), and delete many records with a way back.
- Review duplicates (and set up BarnCRM's recommended duplicate rules for people and households in one step, through the org connection), check what needs attention in Org Optimizer (including Apex and flows on old API versions), document your fields, and the flows and Apex triggers that run on each kind of record, in a downloadable Data Dictionary, see which picklist values are still used, download an AI-Readiness Export pack for an AI tool you choose (BarnCRM never calls one itself), see who changed what in Setup long after Salesforce's 180 days, subscribe to BarnCRM's reports by email from one list, inspect every readable field of a record with the Record Inspector, see which BarnCRM setup uses a field before you retire it (Where Used), and run Health Check, with an Error Log that nothing fails silently into. Org Optimizer is the one home of Health Check and errors, with its sections listed like Settings (a Show box on a phone).
- Load data in bulk safely: when BarnCRM's automation fails on one record of a Data Loader, integration or import save, only that record is refused and the rest are saved; and let an integration user's or a migration consultant's saves skip automation (BarnCRM's and your own) while everyone else's run, all set on the Automation tab of the admin apps, which also lists your own flows with a switch and catches up afterwards with one button, and lists every automation in the org with whether Pause All covers it and how to make it, and can turn your own flows and validation rules off for a load, after saving a snapshot that Restore puts back exactly.
- Control who sees what with ready-made roles, see who can see or change what and why in Access Explorer (including a side-by-side compare of two people and a Modify All report), give or remove Read and Edit on fields across several permission sets at once with a preview and undo (Field Access Manager), load realistic sample data to try things out, and erase a person's personal data when you must.

Add Giving and you can also record and receipt gifts, split a gift across funds from its own page, run appeals and stewardship, get a task when it is time to ask a donor again, import gifts from NPSP or Nonprofit Cloud exports, and watch the Giving dashboard. Add Volunteers and you can schedule shifts and approve hours. Add Mirror to keep Opportunities and Campaigns in step, accept gifts from a giving page, or export gifts for accounting.

BarnCRM runs on Platform-only licenses, Sales and Service Cloud, an org with NPSP installed, and an org on Agentforce Nonprofit. In an org with NPSP, BarnCRM can adopt NPSP's existing households in place, with a preview and an undo, rather than create a second household for every family. BarnCRM's own Households feature waits until NPSP has stopped making households, so the two never both make one for the same person.
Every tab in every BarnCRM app, Core and module, has its own icon.


## Coming Next

This is the plan as recorded in the product plan (Section 6 and 6.0). Dates are not promised.

- **Finishing the Core quality pass.** Existing Core features are being tested, tightened and simplified before new modules start. Related-record duplicate matching (duplicate scan and import matching) is in progress.
- **Super Importer.** The import tool has one name everywhere (the tab, the page title, Data Jobs) and says "preview" and "kind of record" instead of "dry run" and "object". Its file steps show a dashed area to drop a file on, its commit button says how many rows it imports, and a finished import's **See Every Row** link opens all of its rows. Import grows in slices: the first (built, not yet released) reads several sheets of a workbook at once, maps headings that name the object and the field together, suggests the object from the file, and shows example values beside each column. The second (built, not yet released) loads several objects from one upload, a sheet for each or several on one row, linked and loaded parents first; it replaces the older related-records load. Closer heading matching follows.
- **BarnCRM Contact Point Sync.** An optional module, approved but not yet scheduled, for orgs that use Salesforce Contact Points: it keeps them in step with a person's email and phone and with their addresses, so Core itself never touches those objects.
- **BarnCRM Address Verification.** An optional module, approved but not yet scheduled, that verifies addresses with your own provider key (set in BarnCRM Settings) and records each address's verification status and date. No provider is bundled.
- **Programs and Logic Models.** Track programs, services, enrollments and attendance, and build logic models with indicators and a report you can send to a funder.
- **Funders.** A grant and funder pipeline with reporting deadlines and reminders, award schedules, restricted fund tracking and a deadline calendar (in progress).
- **Scheduled imports and connections.** On hold until the owner starts the next version.
- **Hardening, beta and listing.** Security review, scale testing, a beta with real organizations, then the Salesforce AppExchange listing and version 1.0.

## Where to Read Next

| If you want to | Read |
|---|---|
| Set up and run BarnCRM | [Admin Guide](admin-guide/README.md) |
| Use BarnCRM every day (enter gifts, look people up, manage households, log volunteer hours) | [User Guide](user-guide/README.md) |
| Check a build, step by step, in a test org | [Testing Guide](testing-guide/README.md) |
| See every feature and its status | [Feature catalog](barncrm-features.md) |
| Build or contribute | [Contributor guide](contributor-guide/environment.md) |

## Report a Bug or Give Feedback

Open an issue at https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new/choose (a free GitHub account is needed). Issues are read and may shape the roadmap. See [SUPPORT.md](../SUPPORT.md) for which template to use and what to include, and never post personal or donor data. Report security problems privately, as described in [SECURITY.md](../SECURITY.md).
