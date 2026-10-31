# BarnCRM Overview

Applies to: BarnCRM main as of 2026-10-31 (landing batch A head a8489572d, pending the squash commit on main). Pre-release: no package version exists yet; this tracks the newest code on main.

## What BarnCRM Is

BarnCRM is a free, open source suite of apps that installs into your organization's Salesforce account and turns it into a working database for people, households, gifts and more. It is built for small and medium organizations with one to ten Salesforce users and no full-time Salesforce administrator. The person who sets it up is an operations manager, development director or executive director who is comfortable with spreadsheets.

Three promises shape it:

- **The numbers are right.** Totals show when they were last calculated, so they never go quietly stale.
- **Upgrades are safe.** Nothing you configure is overwritten by a new version, and nothing has to be cloned to be used.
- **It is open.** The source is public, the software is free, and no data leaves your Salesforce org.

Every setting an administrator needs lives on a page inside the app (BarnCRM Settings), not only in Salesforce Setup. The few changes only Setup can make are listed where they matter, each with numbered steps and a button that opens the right Setup page.

BarnCRM is in development. No package version exists yet and nothing is installable from a listing, so this page describes what is built on the main branch of the source code.

> **Not for production orgs:** BarnCRM is in pilot. We do not recommend installing pilot or testing versions in a production Salesforce org. Use a sandbox, a free Developer Edition org or a scratch org.

## Two Editions

Both editions include the full core suite of tools: people, households, relationships, addresses, importing with undo (an admin can create a new field for a column), Find, bulk update and bulk delete, duplicate review, Org Optimizer, Health Check, settings and the Setup Assistant.

| Edition | For | What you get |
|---|---|---|
| **Standard Edition** | Any organization on Salesforce, including businesses and clubs | BarnCRM Core alone. No nonprofit wording or module is shown. |
| **Nonprofit Edition** | Nonprofits (any organization may choose it) | Core plus the nonprofit tools: Giving first, then the other modules as you turn them on. |

You choose the edition once, in the first-run setup window; the Setup Assistant shows that answer. You can change it later: see [Editions](admin-guide/editions.md). A module you never install leaves nothing behind in your org.

## Packages and Their State on Main

| Package | What it holds | State on main |
|---|---|---|
| **Core** | Households and people, relationships, affiliations, addresses, the BarnCRM apps (everyday and admin, each with standard or console navigation), Settings console, Setup Assistant, Module Manager, access roles, Import, Data Manager, Find, bulk update and delete, Super Transform (bulk changes without a file, with saved step lists and a phone format), Org Optimizer, Duplicates, Health Check, Error Log, erase a person | Built |
| **Rollup Builder** | The rollup engine and the Rollup Builder page where you manage totals | Built (offered in both editions; Giving depends on it) |
| **Giving** | Gifts, funds, Quick Gift Entry, gift batches, refunds, in-kind gifts, commitments, pledge reminders, soft credits, tributes, matching gifts, appeals, acknowledgments, receipts and year-end statements, donor levels, stewardship plans, the Ask Pipeline, retention reports, donor segments with export for email tools, posting and closed periods, gift import, the Giving dashboard, the Fundraising app | Built |
| **Mirror** | Opportunity mirror, Campaign sync, inbound gift API, accounting export | Built (the Gift Transaction mirror for Nonprofit Cloud is planned) |
| **Volunteers** | Jobs, shifts, sign-ups, hours with approval, skills, requirements, recurring shifts, shift reminder emails, suggested volunteers for a shift, hour letters and certificates, the BarnCRM Volunteers app | Built and tested on main |
| **Programs** | Programs, services, enrollments with stages, the Program Roster panel, a person's Programs card, attendance and service delivery with the Service Delivery Log, sample data, the BarnCRM Programs app | Built (release 0.12, P-01; release 0.13, P-02) |
| **Logic Models** | The Logic Model Builder: inputs, activities, outputs, outcomes and impact with arrows and assumptions, for the organization or a program, and indicators with a baseline and a target and result per period; the BarnCRM Logic Models app | Built (release 0.14, L-01 and L-02; indicator sources and the report are planned) |
| **Funders** | Funder pipeline, reporting deadlines, restricted fund tracking | Planned; the package is an empty placeholder |
| **Events** | Simple event registration and attendance | Planned (after 1.0) |

The feature-by-feature list, with the status of each item, is the [feature catalog](barncrm-features.md).

## What an Org Gets Today

Install Core and run the Setup Assistant, and you can:

- Keep households and the people in them, with household names and greetings built for you, merge and split households, and record relationships, affiliations, addresses (including seasonal ones), several email addresses and a preferred phone.
- Bring in a spreadsheet (CSV or Excel) with a preview, matching rules and one-click undo, find and export records, change many records at once, and delete many records with a way back.
- Review duplicates, check what needs attention in Org Optimizer, document your fields in a downloadable Data Dictionary, download an AI-Readiness Export pack for an AI tool you choose (BarnCRM never calls one itself), see who changed what in Setup long after Salesforce's 180 days, inspect every readable field of a record with the Record Inspector, and run Health Check, with an Error Log that nothing fails silently into.
- Control who sees what with ready-made roles, see who can see or change what and why in Access Explorer (including a side-by-side compare of two people and a Modify All report), load realistic sample data to try things out, and erase a person's personal data when you must.

Add Giving and you can also record and receipt gifts, run appeals and stewardship, get a task when it is time to ask a donor again, import gifts from NPSP or Nonprofit Cloud exports, and watch the Giving dashboard. Add Volunteers and you can schedule shifts and approve hours. Add Mirror to keep Opportunities and Campaigns in step, accept gifts from a giving page, or export gifts for accounting.

BarnCRM runs on Platform-only licenses, Sales and Service Cloud, an org with NPSP installed, and an org on Agentforce Nonprofit.

## Coming Next

This is the plan as recorded in the product plan (Section 6 and 6.0). Dates are not promised.

- **Finishing the Core quality pass.** Existing Core features are being tested, tightened and simplified before new modules start. Related-record duplicate matching (duplicate scan and import matching) is in progress.
- **Super Importer.** Import grows in slices: the first (built, not yet released) reads several sheets of a workbook at once, maps headings that name the object and the field together, suggests the object from the file, and shows example values beside each column. The second (built, not yet released) loads several objects from one upload, a sheet for each or several on one row, linked and loaded parents first; it replaces the older related-records load. Closer heading matching follows.
- **BarnCRM Contact Point Sync.** An optional module, approved but not yet scheduled, for orgs that use Salesforce Contact Points: it keeps them in step with a person's email and phone and with their addresses, so Core itself never touches those objects.
- **BarnCRM Address Verification.** An optional module, approved but not yet scheduled, that verifies addresses with your own provider key (set in BarnCRM Settings) and records each address's verification status and date. No provider is bundled.
- **Programs and Logic Models.** Track programs, services, enrollments and attendance, and build logic models with indicators and a report you can send to a funder.
- **Funders.** A grant and funder pipeline, reporting deadlines and restricted fund tracking.
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
