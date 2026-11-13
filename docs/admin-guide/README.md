# Admin Guide

Applies to: BarnCRM landing/batch-d-i bf7f0eff1 (the integrated Batch D to I build, on top of v1.0 and Batch C). Pre-release: no package version exists yet; this tracks the newest code on main. The page list is in the [Index](#index).

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

Every page in this folder is listed once, below, grouped by what you are trying to do. A feature that adds a page adds its row here in the same pull request, and the version line is refreshed with it. For a short description of what BarnCRM is and which modules exist, read the [Overview](../overview.md). Staff who use BarnCRM daily (and are not administrators) have the [User Guide](../user-guide/README.md); someone checking a build step by step has the [Testing Guide](../testing-guide/README.md).

The Package column says what has to be installed for the page to apply. BarnCRM Core on its own is the Standard Edition, the full core suite of tools for any organization, so a Core page describes only what every organization has: its wording is neutral, and anything about gifts, donors or receipts on a Core page is marked as coming from Giving (C-29), and anything about NPSP or Nonprofit Cloud is marked as applying only when that product is in the org.

### Set Up BarnCRM

| Feature | Page | Package |
|---|---|---|
| Installing BarnCRM: supported editions, room needed, install pre-check, production install, upgrades | [installing.md](installing.md) | Every package |
| C-03 BarnCRM Apps, Navigation and Setup Checklist | [barncrm-app.md](barncrm-app.md) | Core |
| C-12 Setup Assistant | [setup-assistant.md](setup-assistant.md) | Core, with steps from Giving |
| C-30 Editions | [editions.md](editions.md) | Core |
| C-24 Module Manager | [module-manager.md](module-manager.md) | Core |
| Integrations roadmap page, detected apps and migration links (MIG-10) | [integrations.md](integrations.md) | Core |
| MIG-01 Migration Assistant: kits from another app in the same org, ordered steps, verification, undo, retire checklist; adding a kit | [migration-assistant.md](migration-assistant.md) | Core, kits in modules |
| C-03 BarnCRM Settings console | [barncrm-settings.md](barncrm-settings.md) | Core |
| Plan 6.1 item 9 Custom metadata (CMDT Manager) | [custom-metadata.md](custom-metadata.md) | Core |
| C-06 Access | [access.md](access.md) | Core (the Fundraising Staff role comes with Giving) |
| Q-09 Automatic access | [automatic-access.md](automatic-access.md) | Core, with policies for Giving |
| C-10 Sample data loader | [sample-data.md](sample-data.md) | Core |
| C-08 Record pages | [record-pages.md](record-pages.md) | Core |
| C-27 What's new after an upgrade | [whats-new.md](whats-new.md) | Core, with notes from any module |
| Q-10 In-app tips | [in-app-guidance.md](in-app-guidance.md) | Core |
| C-47 Brands and Legal Entities: brand records, assignments, brand-aware receipts, receipt numbering per brand, optional brand-restricted visibility | [brands.md](brands.md) | Core, with brand fields in Giving, Volunteers, Programs and Portal Builder |

### People, Households and Relationships

| Feature | Page | Package |
|---|---|---|
| C-01 Household model | [households.md](households.md) | Core |
| C-01, C-22 Household members and people stored as person accounts | [household-members.md](household-members.md) | Core |
| C-02 Household names and greetings | [household-naming.md](household-naming.md) | Core |
| C-09 Household merge and split | [household-merge-split.md](household-merge-split.md) | Core |
| C-07 Coexistence mode | [coexistence-mode.md](coexistence-mode.md) | Core |
| X-09 Nonprofit Cloud households, MIG-02b Household Model and conversion | [nonprofit-cloud-households.md](nonprofit-cloud-households.md) | Core (guards, Household Model, the conversion section) and Mirror (conversion source, kit, drift report), only in an org with Nonprofit Cloud |
| X-05 Adopt NPSP households | [npsp-households.md](npsp-households.md) | Core, only in an org with NPSP |
| C-15 Relationships | [relationships.md](relationships.md) | Core |
| C-16 Affiliations | [affiliations.md](affiliations.md) | Core |
| C-17, C-18 Addresses and seasonal addresses | [addresses.md](addresses.md) | Core |
| C-25 Multiple email addresses on a person | [emails.md](emails.md) | Core |
| C-25, C-43 Preferred phone on a person | [preferred-phone.md](preferred-phone.md) | Core |
| C-39 Interaction notes | [interaction-notes.md](interaction-notes.md) | Core |
| C-64 Engagement score (a nightly 0 to 100 score and meter from gifts, hours, events and activity, admin-weighted) | [engagement-score.md](engagement-score.md) | Core (Giving, Volunteers and Event Management add their parts) |
| Erase a person | [erase-a-person.md](erase-a-person.md) | Core (Giving extension) |

### Data Tools

| Feature | Page | Package |
|---|---|---|
| Data Manager (one place to start a data task, and every job's Undo) | [data-manager.md](data-manager.md) | Core |
| C-14, C-19, C-32, C-33 Importing, import undo, matching rules and Load one object | [importing.md](importing.md) | Core |
| C-49d Creating a new field from an import | [import-new-fields.md](import-new-fields.md) | Core |
| C-49b Super Importer rows: browse, correct and retry import rows | [import-rows.md](import-rows.md) | Core |
| C-34, C-36 Find and export | [find.md](find.md) | Core |
| C-41, C-41b Grid and saved grids | [grid.md](grid.md) | Core |
| C-35 Super Transformer runs and undo | [bulk-update.md](bulk-update.md) | Core |
| C-50 Super Transformer (bulk change without a file or a Find query) | [super-transform.md](super-transform.md) | Core |
| C-37 Bulk delete | [bulk-delete.md](bulk-delete.md) | Core |
| C-67 Archive by Query (save old records to a file in Files, then delete them; optionally empty the Recycle Bin) | [archive-by-query.md](archive-by-query.md) | Core |
| C-66 Backup Sets (saved Find queries saved to files in Files on demand; restore through Load one object) | [backup-sets.md](backup-sets.md) | Core |
| C-70 Import Files (a zip with a manifest loaded into Files linked to records, with dry run and undo) | [files-import.md](files-import.md) | Core |
| Org Optimizer (Data Quality, Field Use, Data Dictionary, Health Check, Errors, Storage and Limits, Unused Setup, Setup Changes, Access Explorer) | [org-optimizer.md](org-optimizer.md) | Core |
| C-28 Data Quality (the Data Quality section of Org Optimizer) | [data-hygiene.md](data-hygiene.md) | Core |
| C-20 Duplicates (the Duplicate Matching tab: review and matching logic) | [duplicates.md](duplicates.md) | Core |
| Field Use (formerly Field Utilization) | [field-utilization.md](field-utilization.md) | Core |
| C-52 Data Dictionary (the Data Dictionary section of Org Optimizer) | [data-dictionary.md](data-dictionary.md) | Core |
| C-53 and C-53b Access Explorer, with Compare Two and the Modify All Report (a section of Org Optimizer) | [access-explorer.md](access-explorer.md) | Core |
| C-65 Field Access Manager (give or remove Read and Edit across permission sets, with a preview and undo; Access Explorer's Change Field Access view) | [field-access-manager.md](field-access-manager.md) | Core |
| C-56 Setup Changes (who changed what in Setup, kept beyond 180 days; the Setup Changes section of Org Optimizer) | [setup-changes.md](setup-changes.md) | Core |
| C-55 Record Inspector (every readable field of one record, on a page of its own opened from record pages) | [record-inspector.md](record-inspector.md) | Core |
| C-59 Where Used and Retire a Field (which BarnCRM setup uses a field or object; from the Data Dictionary, Field Use and the Record Inspector) | [where-used.md](where-used.md) | Core |
| C-68 Field History (changes to chosen fields of BarnCRM's own objects, beyond 20 fields, with restore) | [field-history.md](field-history.md) | Core |
| AIR-01 AI-Readiness Export (the AI-Readiness Export section of Org Optimizer) | [ai-readiness-export.md](ai-readiness-export.md) | Core |

### Automation, Totals and Health

| Feature | Page | Package |
|---|---|---|
| C-04 Automation control, C-23 automatic pause expiry | [automation-control.md](automation-control.md) | Core |
| ADR-0040 Your own version of an automation | [flow-templates.md](flow-templates.md) | Core |
| C-13 Rollups | [rollups.md](rollups.md) | BarnCRM Rollup Builder (Core until ADR-0125) |
| C-05, C-23 Error Log and error digest | [error-log.md](error-log.md) | Core |
| C-11, C-21 Health Check | [health-check.md](health-check.md) | Core, with findings from Giving, Mirror, Rollup Builder and Volunteers |
| Q-04 Job notifications | [job-notifications.md](job-notifications.md) | Core |
| RT-10 Nightly jobs | [nightly-jobs.md](nightly-jobs.md) | Core, with jobs from every module |
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
| G-21, G-31 Stock, planned and donor-advised fund gifts | [stock-planned-and-daf-gifts.md](stock-planned-and-daf-gifts.md) | Giving |
| G-07, G-11 Commitments | [commitments.md](commitments.md) | Giving |
| G-08 Soft credits | [soft-credits.md](soft-credits.md) | Giving |
| G-09 Tributes | [tributes.md](tributes.md) | Giving |
| G-10 Matching gifts | [matching-gifts.md](matching-gifts.md) | Giving |
| G-05 Appeals | [appeals.md](appeals.md) | Giving |
| G-12 Acknowledgments | [acknowledgments.md](acknowledgments.md) | Giving |
| G-30 Pledge reminders | [pledge-reminders.md](pledge-reminders.md) | Giving |
| G-13 Receipts and year-end statements | [receipts.md](receipts.md) | Giving |
| G-14 Donor levels | [donor-levels.md](donor-levels.md) | Giving |
| G-15 Stewardship plans | [stewardship-plans.md](stewardship-plans.md) | Giving |
| G-26 Ask pipeline | [ask-pipeline.md](ask-pipeline.md) | Giving |
| G-29 Ask cadence reminders | [ask-cadence.md](ask-cadence.md) | Giving |
| G-16 Retention reports | [retention-reports.md](retention-reports.md) | Giving |
| G-28 Donor segments | [donor-segments.md](donor-segments.md) | Giving |
| G-27 Recurring donor health | [recurring-donor-health.md](recurring-donor-health.md) | Giving |
| G-19 Donor scoring | [donor-scoring.md](donor-scoring.md) | Giving |
| G-32 Wealth screening data | [wealth-screening.md](wealth-screening.md) | Giving |
| G-20 Posting and closed periods | [posting-and-closed-periods.md](posting-and-closed-periods.md) | Giving |
| G-02, ADR-0064 A donor's giving on their record | [donor-records.md](donor-records.md) | Giving |
| G-06 Giving dashboard | [giving-dashboard.md](giving-dashboard.md) | Giving |
| pg-22, vis-core-18 Fundraising Home and report charts | [fundraising-home.md](fundraising-home.md) | Giving |
| G-23, G-24 Importing gifts and donation matching | [gift-import.md](gift-import.md) | Giving |

### Mirror (Connections to Other Systems)

| Feature | Page | Package |
|---|---|---|
| X-01 Opportunity mirror | [opportunity-mirror.md](opportunity-mirror.md) | Mirror |
| X-07 Gift Transaction mirror | [gift-transaction-mirror.md](gift-transaction-mirror.md) | Mirror |
| D-201 Cases sent to a service provider: the named credential, the setting, the nightly run and flow action, Provider Requests | [mirror-case-requests.md](mirror-case-requests.md) | Mirror |
| X-02 Campaign sync | [campaign-sync.md](campaign-sync.md) | Mirror |
| X-03, X-06 Inbound gift API | [inbound-gift-api.md](inbound-gift-api.md) | Mirror |
| X-04 Accounting export | [accounting-export.md](accounting-export.md) | Mirror |

### Volunteers

| Feature | Page | Package |
|---|---|---|
| V-01 to V-08 Volunteers: install, roles, settings, jobs, shifts, sign-ups, hours, skills, requirements, recurring shifts, letters, dashboard | [volunteers.md](volunteers.md) | BarnCRM Volunteers |

### Programs

| Feature | Page | Package |
|---|---|---|
| P-01 Programs: install, roles, programs, services, enrollments, the Program Roster panel; P-10 service plans and goals, P-11 cohorts, sessions and mass enrollment, P-12 service counts without names, P-13 referrals, P-14 eligibility screening rules | [programs.md](programs.md) | BarnCRM Programs |

### Logic Models

| Feature | Page | Package |
|---|---|---|
| L-01 to L-04 Logic Models: install, roles, the Logic Model Builder, arrows and assumptions, indicators with baselines, targets and results by period, results typed in, imported or computed from a saved query, the Logic Model Report | [logic-models.md](logic-models.md) | BarnCRM Logic Models |

### Funders

| Feature | Page | Package |
|---|---|---|
| F-01 Funders: install, roles, grants and their stages, the program a grant pays for, the Grant Pipeline tab | [funders.md](funders.md) | BarnCRM Funders |
| F-02 Reporting requirements and deadlines: grant requirements, morning reminder tasks and emails, the Funders settings, overdue requirements in Health Check | [funders.md](funders.md#grant-requirements) | BarnCRM Funders |
| F-05 Multi-year award schedules: payments, Build Schedule, Mark Received | [funders.md](funders.md#award-schedules) | BarnCRM Funders |
| F-03 Restricted fund tracking: the restricted ledger, its balance, received payments entered for you, the Giving fund a grant is booked to | [funders.md](funders.md#restricted-funds) | BarnCRM Funders |
| F-08 Deadline calendar: the Grant Calendar tab | [funders.md](funders.md#the-grant-calendar-tab) | BarnCRM Funders |
| F-04 Government award fields: funding source, federal agency, Assistance Listing number, award number, indirect cost rate, match | [funders.md](funders.md#government-awards) | BarnCRM Funders |
| F-14 Answer and boilerplate library: Grant Answers | [funders.md](funders.md#answer-library) | BarnCRM Funders |
| L-06 Link outcomes to grant deliverables: the Logic Model Outcomes card on a requirement | [funders.md](funders.md#outcomes-a-requirement-reports-on) | BarnCRM Funders |
| F-06 Funder report merge template: Funder Report Templates | [funders.md](funders.md#funder-report-templates) | BarnCRM Funders |
| F-07 Board dashboard: the Board Dashboard tab | [funders.md](funders.md#the-board-dashboard-tab) | BarnCRM Funders |
| C-45 Contact Point Sync: copying email, phone and addresses to Salesforce Contact Points, the settings, the backfill | [contact-point-sync.md](contact-point-sync.md) | BarnCRM Contact Point Sync |
| C-46 Address Verification: the org's own Smarty or Google key, checks on save and nightly, corrections, the nightly limit, Health Check | [address-verification.md](address-verification.md) | BarnCRM Address Verification |

### Forms

| Feature | Page | Package |
|---|---|---|
| C-42a to C-42c Forms: install, roles, the Form Builder (steps, questions, records to write, conditions, preview, publish), filling in a form, matching people and organizations, public forms on a Salesforce Site (Site setup, Health Check checks, processing, integrations), files and save for later, form submissions and Process Again | [forms.md](forms.md) | BarnCRM Forms |

### Event Management

| Feature | Page | Package |
|---|---|---|
| EV-01 Events: install, roles, the Events page, Repeat Event, the event page; EV-03 ticket types and promo codes; EV-04 the Agenda Builder; EV-05 speakers; EV-06 the call for speakers; EV-09 sponsorship; EV-02 registrations, the waitlist and the Forms link; EV-11 the event dashboard and templates; EV-15 appointments; EV-08 volunteers; EV-12 check-in and QR codes; EV-14 settings, reminders, follow-ups and no-shows; EV-10 the Summit Events import | [events.md](events.md) | BarnCRM Event Management |
| PB-01 Portal Builder: the integration user and its license, the External Client App, portals and templates, sign-in settings, the WordPress plugin | [portal-builder.md](portal-builder.md) | BarnCRM Portal Builder |

### Corporate Hub

| Feature | Page | Package |
|---|---|---|
| CH-01 to CH-08 Corporate Hub: install, access, settings, the shipped templates (not legal advice), Library Documents and versions, policy acknowledgments, the compliance calendar and completed cycles, agreements and renewals, data protection (processing activities, data subject requests, breaches), reminders, reports | [corporate-hub.md](corporate-hub.md) | BarnCRM Corporate Hub |

### Payments

| Feature | Page | Package |
|---|---|---|
| PAY-01 Payments: install, roles, the Site, connecting Stripe and PayPal, Payments Setup and keys, test and live mode, processing, payment statuses and refunds, Health Check checks, the seam for module builders | [payments.md](payments.md) | BarnCRM Payments |
| MIG-06 Online giving through Zapier: recipes for Givebutter, Donorbox and similar tools into Giving gifts | [online-giving-zapier.md](online-giving-zapier.md) | Giving (Mirror for recipe B) |

### LWC Builder

| Feature | Page | Package |
|---|---|---|
| LB-01 to LB-06 LWC Builder: install, access, settings, the grid canvas builder, placing the packaged component, blocks, buttons, visibility rules, export as LWC source, moving components between orgs | [lwc-builder.md](lwc-builder.md) | BarnCRM LWC Builder |

### Project Management

| Feature | Page | Package |
|---|---|---|
| PM-01 to PM-05 Project Management: install, access, settings, projects, phases, tasks and milestones, templates (Salesforce Implementation, Program Launch, your own), time entries, assignments, budgets, utilization, Export Billable Time, health, status updates, the Projects at Risk card, reports | [projects.md](projects.md) | BarnCRM Project Management |
| PM-06 to PM-12 Project Management PSA: settings per part, who approves, rate cards, timesheets and approvals, expenses, resources and staffing, billing types and invoices, Pay Online through BarnCRM Payments, financials and recognized revenue, change requests | [projects-psa.md](projects-psa.md) | BarnCRM Project Management |
| D-201 Project Management requests and issues: settings, assigning and queues, the request life cycle, shared and internal comments, Create Task and Create Change Request, requesters in the portal, requests from another organization, reports | [projects-requests.md](projects-requests.md) | BarnCRM Project Management |

### Scholarships and Outbound Grants

| Feature | Page | Package |
|---|---|---|
| SG-01 to SG-10, PB-06 Scholarships and Outbound Grants: install, access, settings, programs and cycles, eligibility rules, rubrics, reviewer panels and Assign Reviewers, blind review, applications from Forms, the review board and decisions, award letters, disbursements and conditions, the accounting export, recipient reports and renewals, the applicant portal, reports | [scholarships.md](scholarships.md) | BarnCRM Scholarships and Outbound Grants |

### Territory Management

| Feature | Page | Package |
|---|---|---|
| C-40 Territory Management: install, access, territories, rules and priority, preview, assign and undo, the nightly assignment; C-40b owner routing by territory owner, round robin and capacity | [territory-management.md](territory-management.md) | BarnCRM Territory Management |

### Memberships

| Feature | Page | Package |
|---|---|---|
| G-22a to G-22e, PAY-02, PB-09 Memberships: install, roles, levels and benefits, membership terms and their status, renewing by hand, from Giving gifts and recurring gifts, and online through Payments, lapse handling and reminders, the member directory portal, Memberships Essentials, certifications and continuing credits, erasure | [memberships.md](memberships.md) | BarnCRM Memberships (Giving, Payments and Portal Builder optional) |

### Moving From Another System

| Feature | Page | Package |
|---|---|---|
| NPSP import templates | [migrating-from-npsp.md](migrating-from-npsp.md) | Giving |
| Nonprofit Cloud import templates | [migrating-from-nonprofit-cloud.md](migrating-from-nonprofit-cloud.md) | Giving |
| DonorPerfect, Bloomerang, Little Green Light, Neon, CiviCRM and Raiser's Edge NXT gift templates | [moving-from-another-crm.md](moving-from-another-crm.md) | Giving |
| Moving rollups from Rollup Helper by hand | [moving-from-rollup-helper.md](moving-from-rollup-helper.md) | BarnCRM Rollup Builder |
| C-31 Moving a pilot to the managed packages | [moving-to-managed-packages.md](moving-to-managed-packages.md) | Every installed package |

## Report a Bug or Give Feedback

If a page here is wrong, missing or unclear, or a feature does not behave as described, open an issue at https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new/choose (a free GitHub account is needed). Issues are read and may shape the roadmap. See [SUPPORT.md](../../SUPPORT.md) for which template to use and what to include, and never post personal or donor data. Report security problems privately, as described in [SECURITY.md](../../SECURITY.md).
