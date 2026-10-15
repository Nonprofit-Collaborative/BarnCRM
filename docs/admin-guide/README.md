# Admin Guide

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

## Required page structure

Every feature page has these four sections, in this order (plan Section 7.4):

### 1. What it does

Two or three sentences in plain language that fits the reader's organization. What problem
it solves, and for whom. No architecture, no object names.

### 2. How to turn it on

The exact steps to enable and configure the feature, all of them inside the app. If a
step requires Salesforce Setup, say why it cannot be avoided and link to the Setup
Assistant step that deep-links there. A feature that needs Setup for normal use has not
met the definition of done.

### 3. A five-minute walkthrough

A numbered path from nothing to a working result, with the sample data as the starting
point, that a person can complete in five minutes. This doubles as the manual acceptance
script Brandon runs before an iteration is promoted (plan Section 7.3).

### 4. Common mistakes

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

## Style rules

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

Each feature adds its row here when its page is written.

The Package column says what has to be installed for the page to apply. BarnCRM Core on
its own is the Standard Edition, the full core suite of tools for any organization, so a Core page
describes only what every organization has: its wording is neutral, and anything about
gifts, donors or receipts on a Core page is marked as coming from Giving (C-29), and anything
about NPSP or Nonprofit Cloud is marked as applying only when that product is in the org.

| Feature | Page | Package | Iteration |
|---|---|---|---|
| C-04 | [Automation control](automation-control.md) | Core | v0.1 |
| C-05 | [Error Log](error-log.md) | Core | v0.1 |
| C-06 | [Access](access.md) | Core (the Fundraising Staff role comes with Giving) | v0.1 |
| Q-09 Automatic access | [automatic-access.md](automatic-access.md) | Core, with policies for Giving | Core quality pass |
| C-01 Household model | [households.md](households.md) | Core | v0.1 |
| C-02 Household names and greetings | [household-naming.md](household-naming.md) | Core | v0.1 |
| C-07 | [Coexistence mode](coexistence-mode.md) | Core | v0.1 |
| C-09 Household merge and split | [household-merge-split.md](household-merge-split.md) | Core | v0.1 |
| C-10 Sample data loader | [sample-data.md](sample-data.md) | Core | v0.1 |
| C-11 | [Health Check](health-check.md) | Core, with findings from Giving and Connect | v0.1 |
| C-03 BarnCRM app and setup checklist | [barncrm-app.md](barncrm-app.md) | Core | v0.1 |
| C-03 BarnCRM Settings console | [barncrm-settings.md](barncrm-settings.md) | Core | v0.1 |
| C-12 Setup Assistant | [setup-assistant.md](setup-assistant.md) | Core, with steps from Giving | v0.2 |
| C-30 Editions | [editions.md](editions.md) | Core | Core quality pass |
| C-24 Module Manager | [module-manager.md](module-manager.md) | Core | v0.8 |
| Plan 6.1 item 9 Custom metadata (CMDT Manager) | [custom-metadata.md](custom-metadata.md) | Core | Shipped |
| C-13 Rollups | [rollups.md](rollups.md) | BarnCRM Rollup Builder (Core until ADR-0125) | v0.2 |
| C-14 Importing | [importing.md](importing.md) | Core | v0.2 |
| C-31 Moving a pilot to the managed packages | [moving-to-managed-packages.md](moving-to-managed-packages.md) | Every installed package | v0.6 |
| G-01 Gifts | [gifts.md](gifts.md) | Giving | v0.2 |
| G-03 Quick gift entry | [quick-gift-entry.md](quick-gift-entry.md) | Giving | v0.2 |
| G-01 Funds | [funds.md](funds.md) | Giving | v0.2 |
| G-05 Appeals | [appeals.md](appeals.md) | Giving | v0.2 |
| G-06 Giving dashboard | [giving-dashboard.md](giving-dashboard.md) | Giving | v0.2 |
| G-04 Refunds and write-offs | [refunds.md](refunds.md) | Giving | v0.2 |
| G-07 and G-11 Commitments | [commitments.md](commitments.md) | Giving | v0.3 |
| C-17 Addresses | [addresses.md](addresses.md) | Core | v0.3 |
| C-15 Relationships | [relationships.md](relationships.md) | Core | v0.3 |
| C-16 Affiliations | [affiliations.md](affiliations.md) | Core | v0.3 |
| G-08 Soft credits | [soft-credits.md](soft-credits.md) | Giving | v0.3 |
| G-09 Tributes | [tributes.md](tributes.md) | Giving | v0.3 |
| G-10 Matching gifts | [matching-gifts.md](matching-gifts.md) | Giving | v0.3 |
| G-12 Acknowledgments | [acknowledgments.md](acknowledgments.md) | Giving | v0.4 |
| G-13 Receipts and year-end statements | [receipts.md](receipts.md) | Giving | v0.4 |
| G-14 Donor levels | [donor-levels.md](donor-levels.md) | Giving | v0.4 |
| G-15 Stewardship plans | [stewardship-plans.md](stewardship-plans.md) | Giving | v0.4 |
| G-16 Retention reports | [retention-reports.md](retention-reports.md) | Giving | v0.4 |
| G-18 In-kind gifts | [in-kind-gifts.md](in-kind-gifts.md) | Giving | v0.4 |
| C-25 Multiple email addresses on a person | [emails.md](emails.md) | Core | v0.5 |
| G-17 Gift batches | [gift-batches.md](gift-batches.md) | Giving | v0.5 |
| C-20 Duplicates | [duplicates.md](duplicates.md) | Core | v0.5 |
| G-23 and G-24 Importing gifts and donation matching | [gift-import.md](gift-import.md) | Giving | v0.5 |
| NPC import templates | [migrating-from-nonprofit-cloud.md](migrating-from-nonprofit-cloud.md) | Giving | v0.5 |
| NPSP import templates | [migrating-from-npsp.md](migrating-from-npsp.md) | Giving | v0.5 |
| C-01 Household members | [household-members.md](household-members.md) | Core | v0.1 |
| X-09 Nonprofit Cloud households | [nonprofit-cloud-households.md](nonprofit-cloud-households.md) | Core, only in an org with Nonprofit Cloud | v0.6 |
| X-02 Campaign sync | [campaign-sync.md](campaign-sync.md) | Connect | v0.6 |
| X-01 Opportunity mirror | [opportunity-mirror.md](opportunity-mirror.md) | Connect | v0.6 |
| X-03 Inbound gift API | [inbound-gift-api.md](inbound-gift-api.md) | Connect | v0.6 |
| X-03, Q-14 Using BarnCRM actions with your own AI assistant | [using-barncrm-actions-with-ai.md](using-barncrm-actions-with-ai.md) | Core, Connect | v0.7 |
| X-04 Accounting export | [accounting-export.md](accounting-export.md) | Connect | v0.6 |
| G-20 Posting and closed periods | [posting-and-closed-periods.md](posting-and-closed-periods.md) | Giving | v0.6 |
| UX review item 2 | [A donor's giving on their record](donor-records.md) | Giving | v0.6 |
| C-34 Find and export | [find.md](find.md) | Core | v0.7 |
| C-35 Bulk update | [bulk-update.md](bulk-update.md) | Core | v0.7 |
| C-37 Bulk delete | [bulk-delete.md](bulk-delete.md) | Core | Shipped (#219) |
| Erase a person | [erase-a-person.md](erase-a-person.md) | Core (Giving extension) | Shipped (#377) |
| C-28 Data hygiene | [data-hygiene.md](data-hygiene.md) | Core | v0.7 |
| Field utilization (plan Section 6.1 item 10) | [field-utilization.md](field-utilization.md) | Core | Shipped (#377) |
| Q-04 Job notifications | [job-notifications.md](job-notifications.md) | Core | Core quality pass |
| C-27 What's new after an upgrade | [whats-new.md](whats-new.md) | Core, with notes from any module | v0.6 |
| Q-10 In-app tips | [in-app-guidance.md](in-app-guidance.md) | Core | Core quality pass |
| C-39 Interaction notes | [interaction-notes.md](interaction-notes.md) | Core | v0.9 |
| ADR-0040 Your own version of an automation | [flow-templates.md](flow-templates.md) | Core | v0.6 |
