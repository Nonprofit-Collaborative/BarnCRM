# Admin Guide

Applies to: BarnCRM main as of 2026-10-29 (landing batch 13). Pre-release: no package version exists yet; this tracks the newest code on main. The page list is in the [Index](#index).

> **Not for production orgs:** BarnCRM is in pilot. We do not recommend installing pilot or testing versions in a production Salesforce org. Use a sandbox, a free Developer Edition org or a scratch org.

## Purpose

One page per feature, written **before** the Lightning web component that implements it,
for Maria.

Maria is the Operations Manager who installs and configures BarnCRM. She is
comfortable with spreadsheets and modern web apps. She has no technical background, no
full-time Salesforce administrator to call, and no budget for a consultant. If she cannot
do the thing by following the page, the feature is not done (Principle 1, plan Section
1.3).

Writing the page first is a design tool, not a documentation chore. Plan Section 9.3 puts
it plainly: **write the admin-guide page before the LWC; if the page is hard to write,
the feature is too complicated.** A page that needs six screenshots and a warning box is
telling you to redesign the feature.

The page is also part of the definition of done (plan Section 7.4) and part of review:
the reviewer must try the feature as Maria with only this page as instructions (plan
Section 9.2).

## Required Page Structure

Every feature page has these four sections, in this order (plan Section 7.4):

### 1. What It Does

Two or three sentences in plain language that fits the reader's organization. What problem
it solves, and for whom. No architecture, no object names.

### 2. How to Turn It On

The exact steps to enable and configure the feature, all of them inside the app. If a
step requires Salesforce Setup, say why it cannot be avoided and link to the Setup
Assistant step that deep-links there. A feature that needs Setup for normal use has not
met the definition of done.

### 3. A Five-Minute Walkthrough

A numbered path from nothing to a working result, with the sample data as the starting
point, that a person can complete in five minutes. This doubles as the manual acceptance
script Brandon runs before an iteration is promoted (plan Section 7.3).

### 4. Common Mistakes

The three or four things that actually go wrong, each with how to recognize it and how to
fix it. Write these from what the tests and the walkthrough surfaced, not from
imagination.

## Personas

Use these names, from plan Section 2.2. They appear in user stories, in tests, and in
these pages, so that everyone is talking about the same person.

| Persona | Role |
|---|---|
| **Maria** | Operations Manager: installs and configures the package, the administrator |
| **David** | Development Director: runs fundraising, enters gifts, sends receipts |
| **Priya** | Program Coordinator: runs services and volunteers |
| **Tom** | Executive Director: accountable to the board and to funders |
| **Jen** | Board Treasurer or Bookkeeper: reconciles with accounting |
| **Sam** | Contributor: open source developer or administrator who contributes |

## Style Rules

- **Plain language, not Salesforce language.** Use the words the reader's organization
  uses: "household" and "person", not "Account" and "Contact record". A Core page is
  neutral, because Core alone serves organizations that are not nonprofits: no gifts,
  donors, receipts or fundraising unless the passage is marked as applying with Giving, and
  no Salesforce product name (NPSP, Nonprofit Cloud) unless the passage is marked as
  applying when that product is in the org (ADR-0062,
  `0062-core-names-other-products-only-when-detected.md`). Giving pages use giving
  language: "Gift" not "Donation Transaction", "Fund" not "General Accounting Unit",
  "Appeal" not "Campaign" (plan Sections 7.1 and 13).
- **No API names in prose.** Maria never needs to know one (plan Section 2.3). Say "the
  household's formal greeting", not the field's API name. Where a page genuinely must
  name a field for a report builder, put it in a table at the end, not in the
  instructions.
- **No namespace prefixes anywhere**, in prose or in tables.
- **No em dashes.** Use colons, commas, or parentheses.
- **Second person, present tense, active voice.** "Open BarnCRM Settings and choose
  Households."
- **Say what to do, then what you will see.** Every step ends in a result the reader can
  check against.
- **Every error message quoted in the guide matches the message in the product**, word
  for word, so a search finds the page.
- **Screenshots are optional and expensive.** Prefer a clear step. A screenshot that goes
  stale is worse than no screenshot.

## Index

Applies to: BarnCRM main as of 2026-10-29 (landing batch 13). Pre-release: no package version exists yet; this tracks the newest code on main.

Every page in this folder is listed once, below, grouped by what you are trying to do. A feature that adds a page adds its row here in the same pull request, and the version line is refreshed with it. For a short description of what BarnCRM is and which modules exist, read the [Overview](../overview.md). Staff who use BarnCRM daily (and are not administrators) have the [User Guide](../user-guide/README.md); someone checking a build step by step has the [Testing Guide](../testing-guide/README.md).

The Package column says what has to be installed for the page to apply. BarnCRM Core on its own is the Standard Edition, the full core suite of tools for any organization, so a Core page describes only what every organization has: its wording is neutral, and anything about gifts, donors or receipts on a Core page is marked as coming from Giving (C-29), and anything about NPSP or Nonprofit Cloud is marked as applying only when that product is in the org.

### Set Up BarnCRM

| Feature | Page | Package |
|---|---|---|
| C-03 BarnCRM Apps, Navigation and Setup Checklist | [barncrm-app.md](barncrm-app.md) | Core |
| C-12 Setup Assistant | [setup-assistant.md](setup-assistant.md) | Core, with steps from Giving |
| C-30 Editions | [editions.md](editions.md) | Core |
| C-24 Module Manager | [module-manager.md](module-manager.md) | Core |
| Integrations roadmap page | [integrations.md](integrations.md) | Core |
| C-03 BarnCRM Settings console | [barncrm-settings.md](barncrm-settings.md) | Core |
| Plan 6.1 item 9 Custom metadata (CMDT Manager) | [custom-metadata.md](custom-metadata.md) | Core |
| C-06 Access | [access.md](access.md) | Core (the Fundraising Staff role comes with Giving) |
| Q-09 Automatic access | [automatic-access.md](automatic-access.md) | Core, with policies for Giving |
| C-10 Sample data loader | [sample-data.md](sample-data.md) | Core |
| C-08 Record pages | [record-pages.md](record-pages.md) | Core |
| C-27 What's new after an upgrade | [whats-new.md](whats-new.md) | Core, with notes from any module |
| Q-10 In-app tips | [in-app-guidance.md](in-app-guidance.md) | Core |

### People, Households and Relationships

| Feature | Page | Package |
|---|---|---|
| C-01 Household model | [households.md](households.md) | Core |
| C-01, C-22 Household members and people stored as person accounts | [household-members.md](household-members.md) | Core |
| C-02 Household names and greetings | [household-naming.md](household-naming.md) | Core |
| C-09 Household merge and split | [household-merge-split.md](household-merge-split.md) | Core |
| C-07 Coexistence mode | [coexistence-mode.md](coexistence-mode.md) | Core |
| X-09 Nonprofit Cloud households | [nonprofit-cloud-households.md](nonprofit-cloud-households.md) | Core, only in an org with Nonprofit Cloud |
| C-15 Relationships | [relationships.md](relationships.md) | Core |
| C-16 Affiliations | [affiliations.md](affiliations.md) | Core |
| C-17, C-18 Addresses and seasonal addresses | [addresses.md](addresses.md) | Core |
| C-25 Multiple email addresses on a person | [emails.md](emails.md) | Core |
| C-25, C-43 Preferred phone on a person | [preferred-phone.md](preferred-phone.md) | Core |
| C-39 Interaction notes | [interaction-notes.md](interaction-notes.md) | Core |
| Erase a person | [erase-a-person.md](erase-a-person.md) | Core (Giving extension) |

### Data Tools

| Feature | Page | Package |
|---|---|---|
| Data Manager (one place to start a data task, and every job's Undo) | [data-manager.md](data-manager.md) | Core |
| C-14, C-19, C-32, C-33 Importing, import undo, matching rules and Load one object | [importing.md](importing.md) | Core |
| C-49d Creating a new field from an import | [import-new-fields.md](import-new-fields.md) | Core |
| C-49b Super Importer rows: browse, correct and retry import rows | [import-rows.md](import-rows.md) | Core |
| C-34, C-36 Find and export | [find.md](find.md) | Core |
| C-35 Bulk update | [bulk-update.md](bulk-update.md) | Core |
| C-50 Super Transform (bulk change without a file or a Find query) | [super-transform.md](super-transform.md) | Core |
| C-37 Bulk delete | [bulk-delete.md](bulk-delete.md) | Core |
| Org Optimizer (Data Quality, Field Utilization, Health Check, Errors, Storage and Limits, Unused Setup) | [org-optimizer.md](org-optimizer.md) | Core |
| C-28 Data Quality (the Data Quality section of Org Optimizer) | [data-hygiene.md](data-hygiene.md) | Core |
| C-20 Duplicates (the Duplicate Matching tab: review and matching logic) | [duplicates.md](duplicates.md) | Core |
| Field utilization | [field-utilization.md](field-utilization.md) | Core |
| C-52 Data Dictionary (the Data Dictionary section of Org Optimizer) | [data-dictionary.md](data-dictionary.md) | Core |

### Automation, Totals and Health

| Feature | Page | Package |
|---|---|---|
| C-04 Automation control, C-23 automatic pause expiry | [automation-control.md](automation-control.md) | Core |
| ADR-0040 Your own version of an automation | [flow-templates.md](flow-templates.md) | Core |
| C-13 Rollups | [rollups.md](rollups.md) | BarnCRM Rollup Builder (Core until ADR-0125) |
| C-05, C-23 Error Log and error digest | [error-log.md](error-log.md) | Core |
| C-11, C-21 Health Check | [health-check.md](health-check.md) | Core, with findings from Giving, Mirror, Rollup Builder and Volunteers |
| Q-04 Job notifications | [job-notifications.md](job-notifications.md) | Core |
| X-03, Q-14 Using BarnCRM actions with your own AI assistant | [using-barncrm-actions-with-ai.md](using-barncrm-actions-with-ai.md) | Core, Mirror |

### Giving

| Feature | Page | Package |
|---|---|---|
| G-01 Gifts | [gifts.md](gifts.md) | Giving |
| G-01 Funds | [funds.md](funds.md) | Giving |
| G-03 Quick gift entry | [quick-gift-entry.md](quick-gift-entry.md) | Giving |
| G-17 Gift batches | [gift-batches.md](gift-batches.md) | Giving |
| G-04 Refunds and write-offs | [refunds.md](refunds.md) | Giving |
| G-18 In-kind gifts | [in-kind-gifts.md](in-kind-gifts.md) | Giving |
| G-07, G-11 Commitments | [commitments.md](commitments.md) | Giving |
| G-08 Soft credits | [soft-credits.md](soft-credits.md) | Giving |
| G-09 Tributes | [tributes.md](tributes.md) | Giving |
| G-10 Matching gifts | [matching-gifts.md](matching-gifts.md) | Giving |
| G-05 Appeals | [appeals.md](appeals.md) | Giving |
| G-12 Acknowledgments | [acknowledgments.md](acknowledgments.md) | Giving |
| G-13 Receipts and year-end statements | [receipts.md](receipts.md) | Giving |
| G-14 Donor levels | [donor-levels.md](donor-levels.md) | Giving |
| G-15 Stewardship plans | [stewardship-plans.md](stewardship-plans.md) | Giving |
| G-16 Retention reports | [retention-reports.md](retention-reports.md) | Giving |
| G-20 Posting and closed periods | [posting-and-closed-periods.md](posting-and-closed-periods.md) | Giving |
| G-02, ADR-0064 A donor's giving on their record | [donor-records.md](donor-records.md) | Giving |
| G-06 Giving dashboard | [giving-dashboard.md](giving-dashboard.md) | Giving |
| G-23, G-24 Importing gifts and donation matching | [gift-import.md](gift-import.md) | Giving |

### Mirror (Connections to Other Systems)

| Feature | Page | Package |
|---|---|---|
| X-01 Opportunity mirror | [opportunity-mirror.md](opportunity-mirror.md) | Mirror |
| X-02 Campaign sync | [campaign-sync.md](campaign-sync.md) | Mirror |
| X-03, X-06 Inbound gift API | [inbound-gift-api.md](inbound-gift-api.md) | Mirror |
| X-04 Accounting export | [accounting-export.md](accounting-export.md) | Mirror |

### Volunteers

| Feature | Page | Package |
|---|---|---|
| V-01 to V-08 Volunteers: install, roles, settings, jobs, shifts, sign-ups, hours, skills, requirements, recurring shifts, letters, dashboard | [volunteers.md](volunteers.md) | BarnCRM Volunteers |

### Logic Models

| Feature | Page | Package |
|---|---|---|
| L-01 and L-02 Logic Models: install, roles, the Logic Model Builder, arrows and assumptions, indicators with baselines, targets and results by period | [logic-models.md](logic-models.md) | BarnCRM Logic Models |

### Moving From Another System

| Feature | Page | Package |
|---|---|---|
| NPSP import templates | [migrating-from-npsp.md](migrating-from-npsp.md) | Giving |
| Nonprofit Cloud import templates | [migrating-from-nonprofit-cloud.md](migrating-from-nonprofit-cloud.md) | Giving |
| Moving rollups from Rollup Helper by hand | [moving-from-rollup-helper.md](moving-from-rollup-helper.md) | BarnCRM Rollup Builder |
| C-31 Moving a pilot to the managed packages | [moving-to-managed-packages.md](moving-to-managed-packages.md) | Every installed package |

## Report a Bug or Give Feedback

If a page here is wrong, missing or unclear, or a feature does not behave as described, open an issue at https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new/choose (a free GitHub account is needed). Issues are read and may shape the roadmap. See [SUPPORT.md](../../SUPPORT.md) for which template to use and what to include, and never post personal or donor data. Report security problems privately, as described in [SECURITY.md](../../SECURITY.md).
