# Open Impact: Product Plan and Development Handoff

**Working name:** Open Impact (see Decision D-01; name and namespace must be verified before any public use)
**Document version:** 1.1, 2026-09-06 (name changed to Open Impact; namespace deferred)
**Author:** Brandon Mead (product owner) with Claude (product management)
**Audience:** The Claude Code session (and its sub-agents) that will build this, plus future human and AI contributors. This document is written to be self-contained. Assume the reader has no access to any prior conversation.

**Canonical copy:** this BMemory document is the source of truth for the plan (Brandon's rule, 2026-09-06: where a document exists in BMemory, the BMemory version is read and updated, never the repository copy). `docs/product-plan.md` in `Nonprofit-Collaborative/OpenImpact` is a mirror refreshed from this record after each change here.

---

## 0. How to use this document

This is the single source of truth for the project. It is maintained here in BMemory and mirrored into the repository as `docs/product-plan.md`.

Read it in this order:

1. **Section 1 (Vision and principles)** tells you what we are building and why. Every later decision should be traceable to it.
2. **Section 2 (Who this is for)** tells you who must be able to use the result without help.
3. **Section 3 (Lessons from NPSP)** tells you what to copy and what to avoid.
4. **Section 4 (Architecture)** gives the technical decisions that are settled. Do not re-open them without a written decision record (Section 12).
5. **Section 5 (Feature catalog)** lists everything by module.
6. **Section 6 (Roadmap)** sequences the catalog into iterations. Build in this order.
7. **Sections 7 to 11** cover quality, AppExchange readiness, working agreements for AI agents, risks, and open questions.

**Rule for the builder:** when this document and a Salesforce platform constraint disagree, the platform wins, and you record the deviation in the decision log (Section 12) with what you did instead and why. When this document and a nice idea disagree, this document wins. Put the idea in the parking lot (Section 11.3).

---

## 1. Vision and principles

### 1.1 The one-paragraph vision

Open Impact is a free, open source, AppExchange-listed suite of managed packages that gives small and medium nonprofits an easy, complete, and trustworthy way to run fundraising, constituents, and programs on Salesforce, on whatever Salesforce licenses they already have (Agentforce Nonprofit, Sales/Service Cloud, or plain Platform licenses), with no professional implementation required. It takes the best of NPSP (the household model, the data importer, the opinionated defaults, the community), the best of Nonprofit Cloud (the cleaner gift model, program and outcome thinking), and fills the gaps neither product closes (receipting and year-end statements, funder pipeline, front-end settings, modular enablement, upgrade-safe administration). It is built so that a two-person development office can install it on a Tuesday and enter gifts on Wednesday.

### 1.2 The problem

Salesforce stopped developing NPSP in March 2023 and, since December 2025, no longer bundles it for new Power of Us applicants. The replacement, Agentforce Nonprofit (formerly Nonprofit Cloud), is architecturally more capable but is widely reported as hard to set up and administer: G2 rates it 6.1 for ease of setup and 6.8 for ease of admin against 8.0 for meeting requirements. Its Person Account requirement is irreversible, its rollups run through the Data Processing Engine (scheduled batch, consumes compute credits, not admin-friendly), its permission model requires cloning managed permission sets that are overwritten every release, it lacks NPSP's household conventions, address history, donor levels, and engagement plans, and every implementation re-creates the same defaults from scratch. Small and medium nonprofits, the majority of the sector, have neither the budget for implementation partners nor the staff to absorb this complexity. They are stuck between a frozen product and an over-engineered one.

### 1.3 Principles (in priority order)

1. **A nonprofit administrator with no technical background must be able to install, configure, and operate it.** If a feature needs Setup, Apex, Flow Builder, or a consultant to be useful, it is not done. "Easy" is defined concretely in Section 2.3.
2. **Numbers must be right.** Giving totals, receipts, and fund balances are the product's reputation. Correctness beats speed; visible freshness beats silent staleness. Every rollup shows when it was last calculated.
3. **Turn on only what you use.** A module that is off leaves nothing behind in the org: no objects, no tabs, no triggers. This is achieved with separate packages, not hidden features (Decision D-03).
4. **Compatible by design, dependent on nothing special.** Runs on Platform licenses; uses no Industries objects, no OmniStudio, no Data Cloud, no Person Account requirement. Where standard Salesforce objects exist (Opportunity, Campaign, Case), integration is optional and configurable, never required.
5. **Opinionated defaults, every default overridable.** Ship a working configuration on install. Let the admin change it from the app, not from Setup.
6. **Upgrade-safe.** Nothing an admin configures is overwritten by a package upgrade. Nothing the package ships is something an admin has to clone.
7. **Built to be contributed to.** Small modules, clear contracts between them, a scratch-org story that works in under ten minutes, and documentation written as part of every feature, not after.
8. **Nothing is built that already exists and is good.** Standard platform features first (record types, dynamic forms, Flow, reports). Well-maintained open source second (vendored under license where packaging requires). Custom code last.

### 1.4 What "done" means for the whole project

- **v1.0 = listed on AppExchange, passed security review, installed in at least 25 real nonprofit orgs, with the Core package plus Giving and Import, and at least one optional module (Volunteers or Programs).**
- A nonprofit administrator can go from a fresh org to their first correctly-rolled-up gift, receipt, and household in under two hours, using only the in-app Setup Assistant and documentation.
- At least three contributors outside the original author have merged pull requests.

### 1.5 Explicit non-goals (for this project's lifetime, not just v1)

- **Not a standalone product and not a multi-platform product.** The canonical data model is designed to be portable (Section 4.4), but no non-Salesforce runtime is built here. That is a possible future project, deliberately separate.
- **Not an online giving platform, payment processor, email marketing tool, or donor portal.** We integrate with these (inbound gift API, export formats); we do not replace them. Experience Cloud portals are out of scope because they carry license cost the target customer cannot bear.
- **Not a replacement for Agentforce Nonprofit's Industries features.** Orgs that want DPE, OmniStudio, Grantmaking as a funder, or Agentforce agents keep them. We coexist (Section 4.5).
- **Not a consulting accelerator or migration tool for partners.** A nonprofit can migrate itself from NPSP with our importer; agency tooling is not the audience.
- **Not a general CRM.** No sales pipeline, no B2B features beyond organizational donors and funders.

---

## 2. Who this is for

### 2.1 Primary customer

Small and medium nonprofits: roughly $250K to $10M annual revenue, 2 to 50 staff, one to ten Salesforce users, typically on ten free Power of Us licenses plus a handful of paid ones. They have no full-time Salesforce admin. The person configuring the system is a development director, operations manager, or executive director who is comfortable with spreadsheets and modern web apps.

Secondary: organizations up to $50M who are cost-sensitive, and larger organizations using one module (for example Volunteers) alongside other systems.

**First customers (owner decision, 2026-09-07):** the initial target is organizations already on Salesforce Nonprofit Cloud / Agentforce Nonprofit (Person Accounts enabled, Industries objects present), not NPSP orgs. NPSP orgs are a later audience. Consequences: the Agentforce Nonprofit coexistence mode (Section 4.5) and junction membership (Section 4.6) are first-class from v0.1, the Person Accounts org shape is the primary CI shape, the Gift Transaction mirror (X-07) is sequenced before NPSP coexistence (X-05), and Agentforce Nonprofit import templates ship before NPSP templates. See Section 6.3.

### 2.2 Personas (use these names in user stories, tests, and docs)

| Persona | Role | What they need | What they must never have to do |
|---|---|---|---|
| **Maria, Operations Manager** | Installs and configures the package; the "admin" | Install, enable modules, set defaults, assign access, import the old spreadsheet, fix mistakes | Open Setup for routine configuration; write a formula; call a consultant |
| **David, Development Director** | Runs fundraising | Enter gifts fast, see accurate donor totals, send receipts, know who lapsed, report to the board | Wait overnight for totals; wonder if a number is right; export to Excel to get a pledge balance |
| **Priya, Program Coordinator** | Runs services and volunteers | Track participants, enrollments, attendance, volunteer shifts and hours | Use the fundraising screens; learn a separate system |
| **Tom, Executive Director** | Accountable to the board and funders | Dashboards that are correct without asking; restricted fund balances; funder deadlines | Ask staff to build a report |
| **Jen, Board Treasurer / Bookkeeper** | Reconciles with accounting | Export gifts by fund and date; year-end totals matching the bank | Reconcile by hand |
| **Sam, Contributor** | Open source developer or admin who contributes | Clone, spin up a scratch org, run tests, understand one module without reading all of them | Read the whole codebase; guess conventions |

### 2.3 What "easy" means, concretely (acceptance bar for the whole product)

- **Install to first gift entered: under 30 minutes** with the Setup Assistant, no documentation required.
- **Every setting is on a page in the app**, reachable from a single "Nonprofit Settings" tab, editable by any user with the `Manage Nonprofit Settings` custom permission. Setup is needed only for things Salesforce does not allow apps to do (user creation, org-wide email addresses, some sharing settings), and the Setup Assistant deep-links to those with instructions.
- **No setting requires knowing an API name.** Pick lists show labels. Field selection uses a picker.
- **Every error is human-readable**, says what to do, and is logged where the admin can find it (in-app Error Log, not debug logs).
- **Every module has a "Turn on / Turn off" action and a five-minute walkthrough.**
- **The package can be installed by a user who has never seen Salesforce Setup**, following one screen at a time.
- **Every screen is usable on a phone**, because development staff enter gifts from events.

### 2.4 The five needs this serves (market evidence, summarized)

These are the data-backed needs of the segment, used to justify priority calls throughout:

1. **Revenue resilience.** Donor counts have declined every year since 2021 (down 3.6% in 2025) while dollars rose 5%, meaning dependence on fewer, larger donors; overall retention is around 43%, and converting a first gift to a second is the sector's largest unsolved problem (Fundraising Effectiveness Project, Q4 2025). Government-funded organizations face grant terminations and freezes (one in three affected in 2025, per Urban Institute). **Implication:** retention analytics, stewardship plans, and a funder pipeline are core, not optional.
2. **Staff capacity.** 95% of nonprofit leaders are concerned about burnout; 46% of staff report manually re-entering data across platforms and 48% report time wasted on repetitive tasks (Momentive 2026). **Implication:** automation of acknowledgment, receipting, and rollups; an importer that eliminates re-keying.
3. **Data unification.** Most organizations' constituent data lives in more than one system. **Implication:** an importer and an inbound API that make Salesforce the system of record without a consultant.
4. **Trustworthy numbers for funders and boards.** Outcome tracking is described as very rare in the sector; boards increasingly ask about concentration risk. **Implication:** shipped dashboards and KPI definitions (retention, LYBUNT/SYBUNT, restricted balances) that are correct by construction.
5. **AI readiness without AI dependency.** 92% of nonprofits use AI, 7% see major impact; the difference is clean, governed data. **Implication:** the clean data model is the AI strategy; no AI features are built in v1.

---

## 3. Lessons from NPSP (and from Nonprofit Cloud)

### 3.1 How NPSP was built (for comparison)

- **Origin and stewardship.** Started in 2008 as the Nonprofit Starter Pack by the Salesforce Foundation, later Salesforce.org, later absorbed into Salesforce. Open source under BSD-3-Clause on GitHub (`SalesforceFoundation/NPSP`). Product management was in-house; the community contributed issues, ideas, testing, and some code. Feature development ended March 2023.
- **Packaging.** Grew as five independent managed packages with separate namespaces (`npe01` Contacts and Organizations, `npo02` Households, `npe03` Recurring Donations, `npe4` Relationships, `npe5` Affiliations), later unified under a sixth package, `npsp` ("Cumulus"), that depends on the five. The result was six namespaces, overlapping settings, and legacy objects nobody could remove. Installers needed a special installer or the "NPSP installer" flow.
- **Data model.** Contact plus Account, with Households as Accounts (record type) and Contact.AccountId as membership. Donations as Opportunities with Payments (`npe01__OppPayment__c`), General Accounting Units and Allocations, Recurring Donations, Relationships, Affiliations, Addresses (with seasonal addresses and change management), Levels, Engagement Plans, Soft Credits via Opportunity Contact Roles plus Partial Soft Credits.
- **Administration.** A Visualforce-based "NPSP Settings" tab (this was the right instinct; it just aged), a Trigger Handler table that let admins disable specific automation (loved by admins; keep this), Customizable Rollups (declarative, with batch and real-time), Health Check, and a Data Import object plus Batch Gift Entry with Advanced Mapping in custom metadata.
- **Engineering.** Built with CumulusCI (Salesforce.org's open source build tool), Apex unit tests in the thousands, Robot Framework browser tests, a release every two weeks pushed to all orgs, release notes in the Power of Us Hub, and a "Prerelease" sandbox program.

### 3.2 What to copy from NPSP

1. **The household model as an Account.** Standard object, standard features (activities, reports, addresses), understood by every AppExchange app. Keep it. (Section 4.6.)
2. **Opinionated defaults**: household naming and greetings, default soft credit roles, standard rollups on install. People succeeded with NPSP because it worked on day one.
3. **The Data Import pattern**: a staging object holding one "row" that can create or match a household, contacts, an organization, a gift, and a payment in one pass, with dry run, error reporting, and reprocessing. Keep the pattern; fix the configuration (Section 4.9).
4. **Trigger bypass by an admin, from a table.** Keep it, put it on the front end.
5. **Customizable rollups that admins own.** Keep the concept; make freshness visible.
6. **Push upgrades on a cadence, with release notes written for admins.**
7. **A prerelease program** so contributors and brave orgs see releases early.

### 3.3 What to avoid from NPSP

1. **Multiple namespaces.** One namespace across all packages (2GP allows this).
2. **Settings that only an admin who knew NPSP could find.** Ours are on the front end with search and plain-language descriptions.
3. **Silent nightly batches.** Every rollup shows "last calculated" and the app warns when a schedule has not run.
4. **Everything always installed.** Modules are separate packages.
5. **Opportunity as the gift record.** It ties the product to Sales Cloud licenses and drags in sales pipeline semantics (Stage, Probability, Close Date) that confuse nonprofit staff. See Decision D-04 for the trade-off and mitigation; this is the single most consequential architectural choice.
6. **Documentation as a separate effort.** Docs ship with the feature.

### 3.4 What to copy from Nonprofit Cloud

1. **Separating the gift transaction from the commitment and the designation.** Pledge, schedule, transaction, and fund restriction are different things.
2. **Program, service, benefit, and outcome as first-class concepts** rather than bolt-ons.
3. **Donor scoring (recency, frequency, monetary value)** shipped as a default.
4. **Interaction summaries for major gift work** (a lightweight version).

### 3.5 What to avoid from Nonprofit Cloud

Person Account dependency, batch-only rollups with compute credits, permission sets that must be cloned, setup pages that are invisible until a license is assigned, capability shipped without opinion, and row multiplication that raises storage cost.

---

## 4. Architecture

### 4.1 Packaging model

**Second-generation managed packages (2GP), one namespace, a Core package plus optional module packages that depend on Core.**

| Package | Contains | Depends on |
|---|---|---|
| **Core** | Constituent model (Contacts, Accounts, Households, Relationships, Affiliations, Addresses), the Nonprofit Hub app, Settings framework and UI, Module Manager, permission sets, trigger framework, error log, rollup engine, Import framework, health check | (none) |
| **Giving** | Gifts, funds and allocations, commitments and installments, soft credits, tributes, matching gifts, appeals, acknowledgments and receipts, giving rollups and dashboards, gift batches | Core |
| **Volunteers** | Volunteer profiles, jobs, shifts, sign-ups, hours, skills | Core |
| **Programs** | Programs, services, enrollments, attendance, service deliveries, light case notes | Core |
| **Logic Models** | Logic models the organization builds itself (inputs, activities, outputs, outcomes, impact), indicators with baselines, targets and results by period, evidence, logic model reports. Separate from Programs on purpose (Section 5.7) | Core |
| **Funders** | Funder pipeline (grants received and applied for), reporting deadlines, restricted fund tracking, government award compliance fields | Core, Giving |
| **Connect** | Adapters: Opportunity mirror (NPSP and Sales Cloud), Campaign sync, Gift Transaction mirror (Agentforce Nonprofit), inbound gift REST API, accounting export | Core, Giving |
| **Events** (post-1.0) | Simple event registration and attendance for non-fundraising events | Core |

**Suites and packaging (owner decision, Brandon, 2026-09-23).** The product's tentative name is BarnCRM (Section 8.3). It ships as two suites built from the same packages:

- **Impact Suite** (nonprofits): Core plus Giving, with Programs, Logic Models, Volunteers, Funders and Connect offered as further modules.
- **Community Suite** (for-profit and other organizations that are not nonprofits): Core alone, with the modules that fit (for example Volunteers, and Events later) offered. Nonprofit-only modules are never offered.
- **One install to start, guided installs after.** An administrator installs Core. The Setup Assistant's first step asks which suite; turning on the Nonprofit Edition opens Salesforce's installer for Giving, and the other modules are offered the same way (C-24, C-30). A package cannot install another silently, so each module is one administrator click in Salesforce's installer, and an org that never turns the Nonprofit Edition on never carries gifts, receipts or tax fields.
- **Core is neutral.** Households, relationships, affiliations, addresses, import, rollups, settings, Health Check and the Setup Assistant carry no nonprofit wording. The nonprofit app and wording, the giving and receipt settings, and the nonprofit Setup Assistant steps live in Giving (C-29). Core is still never split into a base package it depends on: the Community Suite is simply Core.
- **Unlocked now, managed at listing.** Packages are built and piloted as unlocked packages under the namespace (registered once the name is verified), and every component follows managed-package rules from the start: anything `global` is treated as permanent, nothing relies on a subscriber editing a packaged component, and no namespace is hard-coded. The same source then becomes second-generation managed packages for the AppExchange listing, with identical API names. Salesforce offers no conversion of an installed unlocked package to a managed one, so production pilots on unlocked packages are allowed, and each moves to managed through a supported migration (export, uninstall, install managed, reimport), built and rehearsed before the listing (C-31).

Reasoning: Principle 3 requires that an unused module leave nothing in the org. Only separate packages achieve that on the platform. Multiple 2GP packages can share one namespace, so cross-package Apex and object references work as if in one package. The cost is multi-package install and upgrade orchestration; that cost is paid by the Module Manager (Section 4.8), not by the admin.

**Minor features inside a package are feature-flagged** (a hierarchy custom setting per feature, exposed as a toggle in Settings). Flags are for behavior, not for hiding schema.

### 4.2 Platform and license compatibility

The product must install and function fully on any of these, verified by CI against each org shape:

| Org shape | Licenses | Notes |
|---|---|---|
| **Platform only** | Salesforce Platform (or Lightning Platform Plus) | No Opportunity, Lead, Campaign, Case, Product objects available. This is the floor, and the cheapest path for the target customer beyond the ten free licenses. Everything in Core, Giving, Volunteers, Programs, and Funders must work here. |
| **Sales/Service Cloud** | Enterprise Edition via Power of Us | Standard objects available. Connect module can mirror gifts to Opportunities and appeals to Campaigns. |
| **NPSP installed** | Sales Cloud plus NPSP packages | Coexistence mode: adopt existing NPSP household accounts; mirror gifts to Opportunities so NPSP rollups and NPSP-dependent apps keep working during transition. |
| **Agentforce Nonprofit** | Nonprofit Cloud licenses, Person Accounts likely enabled | Household junction mode (Section 4.6); optional Gift Transaction mirror so native donor summaries still function. Never require any Industries permission set license. |

Hard rules that follow:

- **No hard reference to Opportunity, Campaign, Case, Lead, or any Industries object in Core, Giving, Volunteers, Programs, Logic Models, or Funders.** References to those objects live only in Connect, and even there behind dynamic Apex (`Schema.getGlobalDescribe`, `Type.forName`) and `sObject` generic code, so Connect can be installed where the objects exist and its features degrade gracefully where they do not.
- **No dependency on Person Accounts**, but full support when enabled.
- **No dependency on any paid add-on** (Data Cloud, OmniStudio, CRM Analytics, Experience Cloud, Marketing Cloud). Standard reports and dashboards only.
- **Multi-currency and Platform Encryption awareness**: not supported in v1, must not break when present; detect and warn in Health Check.

### 4.3 Tooling and repository

- **Salesforce CLI (`sf`) with scratch orgs, source-tracked metadata (SFDX source format), GitHub Actions CI.** CumulusCI is not required; a contributor who knows only `sf` must be able to work. (CumulusCI may be adopted later if multi-package orchestration becomes painful; record as a decision if so.)
- **Repository layout (monorepo, one package directory per package):**

```
open-impact/
  sfdx-project.json          # all packageDirectories, one namespace
  packages/
    core/
    giving/
    volunteers/
    programs/
    logic-models/
    funders/
    connect/
  config/
    scratch-defs/            # platform-only.json, sales-cloud.json, npsp.json, npc.json
  scripts/
    org/                     # create-scratch-org, install-dependencies, seed-sample-data
    release/
  data/
    sample/                  # sample data plans per module
  docs/
    product-plan.md          # this document
    architecture/            # ADRs live here as docs/architecture/decisions/NNNN-title.md
    admin-guide/             # one page per feature, written with the feature
    contributor-guide/
    release-notes/
  tests/
    ui/                      # Playwright end-to-end (optional, post-0.6)
  .github/
    workflows/               # ci.yml (lint, unit tests on 4 org shapes), release.yml
    ISSUE_TEMPLATE/, PULL_REQUEST_TEMPLATE.md
  LICENSE, CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, README.md
```

- **Namespace:** deferred by Brandon's decision (2026-09-06). Candidate: `openimpact` (verify availability; it is immutable once used). Until it is registered, **develop namespace-agnostic**: no namespace prefix hard-coded anywhere (Apex, SOQL, LWC imports, Flow, custom labels, static resource references, permission set files); use relative references inside the package and `Schema` describes for anything dynamic; keep `sfdx-project.json` `namespace` empty and packaged directories in source format so the namespace can be added with one field change. Do not create any 2GP package versions until the namespace is set; scratch orgs and unmanaged deploys are fine. Add a CI check (grep) that fails if the candidate namespace string or `__c` references with an explicit namespace appear in source.
- **Dev Hub:** the Partner Business Org (PBO) obtained through the Salesforce Partner Program (free for ISVs listing free apps; verify current terms). Until the PBO exists, use a Developer Edition Dev Hub and migrate; package IDs are tied to the Dev Hub, so create the real Dev Hub before creating package versions that will be promoted.
- **Branching:** trunk-based. `main` is always releasable. Feature branches per issue, squash-merged. Release branches `release/0.x` only if a hotfix is needed on a promoted version.
- **Versioning:** `0.<iteration>.<patch>` until AppExchange listing, then `1.<minor>.<patch>`. The `versionNumber` in `sfdx-project.json` for each package tracks the iteration in which that package last changed.

### 4.4 The canonical data model (platform-neutral layer)

The data model is written once as a platform-neutral specification in `docs/architecture/canonical-model.md` (entities, fields, relationships, rules) and then implemented as Salesforce objects. This is what keeps the far-future standalone option open at near-zero cost, and it is also the best possible documentation for contributors and for AI agents. Every object below cites its canonical entity. The rule: **no field is added to a Salesforce object that is not first added to the canonical model with a one-line definition.**

### 4.5 Coexistence modes (a single org-level setting, chosen in the Setup Assistant, changeable later)

| Mode | When chosen | Household membership | Gift system of record | Connect behavior |
|---|---|---|---|---|
| **Standalone** (default) | Fresh org, Platform or Sales/Service licenses | Contact.AccountId (NPSP-style) | `Gift__c` | Optional Opportunity mirror off by default |
| **NPSP coexistence** | NPSP detected | Adopt NPSP household Accounts (record type mapping) | `Gift__c`, with Opportunity mirror **on** so NPSP rollups and dependent apps keep working | Opportunity mirror one-way `Gift__c` to Opportunity by default; "Opportunity is source" option for orgs whose online giving writes Opportunities |
| **Agentforce Nonprofit coexistence** | Industries objects or Person Accounts detected | Junction (`Household_Member__c`) | `Gift__c`, optional Gift Transaction mirror | Mirror off by default; enable if the org uses native donor summaries |

Detection is automatic in the Setup Assistant (describe calls for `npsp__` objects, `GiftTransaction`, Person Account enablement) with the admin confirming.

### 4.6 Household model (Core; must ship in v0.1)

**Purpose:** give nonprofits an easier alternative to Party Relationship Groups and a faithful, improved successor to NPSP households.

- **Household = Account with record type `Household`.** Organizations are Accounts with record type `Organization`. Both record types are packaged with compact layouts and share one Lightning record page built with Dynamic Forms, whose field sections show or hide by record type where Household and Organization differ. Each object keeps one minimal fallback page layout, and no profile layout assignments are packaged (owner decision, Brandon, 2026-09-23).
- **Membership has two modes**, abstracted behind one Apex service (`HouseholdService`) so no other code cares which is in use:
  - **Contact mode** (default): `Contact.AccountId` points to the Household Account. Simple, reportable, NPSP-compatible, compatible with every AppExchange app that assumes Contact belongs to Account.
  - **Junction mode** (required when Person Accounts are enabled; optional otherwise): `Household_Member__c` junction with lookups to Contact (for business contacts) or Account (for Person Accounts), plus `Role__c`, `Is_Primary__c`, `Start_Date__c`, `End_Date__c`. Enables one person in multiple households (divorced parents, students) and full history.
- **Automatic household creation**: on Contact insert with no Account (contact mode), create a Household named per the naming rules. Toggle per org; default on.
- **Naming and greetings** computed by the package: Household Name (`The Smith Family`, `Smith and Jones Household`), Formal Greeting (`Mr. and Mrs. John Smith`), Informal Greeting (`John and Jane`). Rules are configurable on the front end with a live preview; per-household override with a "custom name, do not recompute" flag. Support for hyphenated names, different surnames, deceased members (excluded from greetings, optional "the late"), and member ordering.
- **Primary contact** on the household; anniversary and other household-level fields.
- **Household address** with change propagation to members (Section 4.7).
- **Household merge and split tools** on the front end (move a contact to a new or existing household; merge two households with rollup recalculation).
- **Household rollups**: total giving, first and last gift, largest gift, gift count, this year, last year, two years ago, pledge balance, soft credit totals, membership count. Provided by the rollup engine (Section 4.10) as packaged default definitions.

### 4.7 Addresses (Core)

NPC has no address object; NPSP's was one of its most valued features for donor mail.

- `Address__c` related to Household or Organization Account (and to a Contact for "personal" addresses), with type (Home, Work, Mailing, Seasonal, Other), seasonal date ranges (start month/day, end month/day), verification status placeholder, and `Is_Default__c`.
- The current default address is copied to the standard Account and Contact address fields so every standard feature and third-party app still works; seasonal addresses swap in automatically by a daily scheduled job with a visible "last run."
- Address change on a Contact can (setting) update the household and all members, or create a new personal address.
- Third-party verification is out of scope; the object is designed so a verification app can update it.

### 4.8 Settings, Setup Assistant, and Module Manager (Core)

- **Nonprofit Hub app** (Lightning app) with tabs: Home (Setup Assistant and health), Households, Contacts, Organizations, Gifts (from Giving), Data (import, find and bulk update, Section 4.9), Reports, and **Nonprofit Settings**.
- **Nonprofit Settings** is a single LWC-based settings console with a left navigation grouped by module, search across all settings, and plain-language descriptions with "Learn more" links to the admin guide. Access is governed by the `Manage_Nonprofit_Settings` custom permission (packaged in the Admin permission set).
- **Storage strategy** (settled, Decision D-06):
  - *Simple org-wide toggles and values* (feature flags, naming rule selections, default record types): **protected hierarchy Custom Settings**, written synchronously by Apex from the console. Cached in Platform Cache with cache invalidation on write.
  - *Structured configuration the admin manages as lists* (rollup definitions, import templates and mappings, level definitions, acknowledgment rules, stewardship plan templates): **custom objects** in the package (for example `Rollup_Definition__c`), so they are reportable, exportable, and editable with standard record UI where useful.
  - *Package-shipped defaults* (default rollups, default import templates, default levels): **Custom Metadata Types**, read-only to admins, copied into the corresponding custom object records by the post-install script on first install and on "Restore defaults." Upgrades update the metadata defaults without touching the admin's records. This is how Principle 6 (upgrade-safe) is achieved.
- **Setup Assistant**: a guided checklist on the Hub home page, run by Maria in under 30 minutes: (1) confirm coexistence mode, (2) confirm household naming with preview, (3) pick default fund and appeal, (4) assign access to users (in-app, via `PermissionSetAssignment` inserts), (5) set organization identity for receipts (name, EIN, address, logo, signature), (6) choose which modules to turn on, (7) import your first spreadsheet or load sample data, (8) verify with a "first gift" walkthrough. Each step records completion; the checklist stays visible until done and can be re-run.
- **Module Manager**: lists every module with status (Not installed, Installed and off, On), version, and an action. "Install" opens the package install URL for the module in a new tab with instructions (the platform does not allow an app to install another package silently; the Module Manager checks back via describe when the user returns). "Turn on" runs the module's post-install configuration and assigns permission sets. "Turn off" disables its automation and hides its tabs; "Uninstall" links to the platform uninstall with a pre-flight report of data that would be lost.
- **Access page**: assign packaged permission set groups (`Nonprofit Admin`, `Fundraising Staff`, `Program Staff`, `Volunteer Coordinator`, `Read Only`) to users from the front end. Packaged permission sets are never meant to be cloned; org-specific additions go in the admin's own permission sets layered on top.
- **Trigger and automation control**: a table of every packaged automation with a description and an on/off switch, plus a global "Pause all Open Impact automation" for bulk loads, auto-expiring after a set time.
- **Automation approach (owner decision, Brandon, 2026-09-22; ADR-0040):** simple business rules ship as packaged Flows so customers can read and copy them; engine logic (household naming, merge and split, rollups, membership mode guards) stays in Apex and is offered to Flow as invocable actions. Every packaged automation, Flow or Apex, is registered in the Automation Registry with its on/off switch, and a packaged Flow checks that switch as its first step rather than relying on activation state, which an upgrade can change. Customization is "switch ours off, run yours": each switchable automation has a Flow template a customer can Save As and own, and customers build their own record-triggered flows rather than editing packaged ones. A registry entry that runs a customer-named Flow is added only when a real need for ordering between packaged and customer automation is named.
- **Error Log** (`Error_Log__c`): every caught exception with context, user, record, and a plain-language message; surfaced as a Hub tile and an optional daily digest email to the admin.
- **Health Check**: detects org shape, license shape, missing permission assignments, rollup schedules not running, orphaned records, and coexistence conflicts; each finding has a fix action where possible.

### 4.9 Data management (Core; import, bulk update, and find)

**Purpose:** let Maria load the old spreadsheet and every later export, fix many records at once, and find and export exactly the records she needs, without a consultant, Setup, API names or an outside tool, and with every change previewed, recorded and reversible. The engine is neutral and lives in Core, so the Community Suite gets import, update and find; gift meaning, donation matching and gift templates live in Giving. Tags **[v1]** and **[later]** mark what ships before 1.0 and what is planned after it (Section 6). The scope and its phasing are an owner decision (Brandon, 2026-09-23; D-13): NPSP Data Importer parity, a Jetstream-style find and bulk update, and the useful dataimporter.io capabilities, with the most useful in v1 and the rest later.

**What we deliberately do not build.** Metadata deploy, anonymous Apex, permission management, API exploration, org-wide automation switches, org-to-org migration and backup. Setup, Data Loader and Jetstream do these well for the rare technical user; inside a package they would add security review risk and nothing Maria needs. Jetstream's code is not reused (Apache-2.0 with the Commons Clause, not an open source license); its ideas are.

**Objects.**
- `Import_Template__c`: a reusable mapping (source columns to canonical targets, matching rules, defaults) [v1, built].
- `Import_Batch__c`: one data job, whether a file import or a bulk update, with status, counts, run log, undo deadline, and a new `Operation__c` (Import, Update; Delete [later]). A bulk update stores its definition (the query document and the assignments) in `Operation_JSON__c` and has no template [v1]. The API names stay as they are; only the tab and labels change, to "Data jobs" (owner decision, 2026-09-23).
- `Import_Row__c`: the staging row for a file import: raw values as JSON plus resolved lookups to Core records (`Household__c`, `Contact_1__c`, `Contact_2__c`, `Person_1_Account__c`, `Person_2_Account__c`, `Organization__c`) and **record identifiers, not lookups**, for Giving records (`Gift_Id__c`, `Soft_Credit_Id__c`, ADR-0014) [built].
- `Import_Journal__c`: per-chunk pages recording every value a job changed on a record it did not create, before and after, and what an undo kept or could not put back (canonical model Section 17A) [built in C-19]. A bulk update journals through the same pages and adds a Failed entry per record that did not save.
- `Saved_Query__c`: a named query document, owner, object, and a shared flag [v1].

**Import flow** (unchanged where built): upload CSV or XLSX, read in the browser with no third-party script (ADR-0049) → suggested mapping from the column library → two-column picker with sample values → matching rules in plain language → **per-file values** ("every row is appeal Gala 2026") [v1] → **dry run** with counts and an exceptions file → commit → results with links → **undo** within the stamped window.

**Row semantics** (the NPSP insight): one row can describe a household, up to two people, an organization, an affiliation, and, with Giving installed, a gift with allocations, a soft credit and a tribute. Core resolves organization, household, people and affiliation [v1: affiliation moves into Core, C-32]; Giving resolves the rest through `ImportEntityProcessor` [v1: G-23, in v0.5]. Resolution is idempotent per row. Gift import comes early because it does not work today: no package implements `ImportEntityProcessor` (Core looks up a `GiftImportProcessor` class that does not exist), and the first customers must migrate their gifts. Undoing a gift import keeps any gift with an issued receipt and journals the reason (ADR-0010, ADR-0024).

**Templates ship for:** NPSP (Contacts, Accounts, Opportunities, Payments, Allocations, Recurring Donations, Relationships, Affiliations, Addresses), Agentforce Nonprofit (Gift Transaction and related), a generic donor list, a generic gift list, an event attendee list, and a volunteer hours sheet. Templates are custom object records and can be shared as JSON files in the repository's `data/import-templates/` so the community can contribute processor-specific templates. Gift templates load gifts once G-23 exists; module templates (volunteer hours, program rosters) load through C-33.

**Matching** [v1, C-32]: per entity (people, organizations), choose Email exact, Name plus postal code, or an external ID field picked from the object's external ID and unique fields; for organizations, Name exact or an external ID field. Every rule says in one sentence what it risks. When a key finds more than one record, the template says what happens: **reject the row** (the default, by owner decision 2026-09-23, because a wrong merge is harder to notice than a rejected row) or **use the most recently changed record**; the dry run lists every such row either way. Matching through the org's own duplicate rules [later, C-37].

**Donation matching (Giving)** [v1: G-24, in v0.5]: an incoming gift is matched, in order, to an existing gift by external ID (idempotence), then to an open installment of the same donor (Contact or Account, or anyone in the household) whose expected date is within the template's date window (default 7 days) and whose amount is within its tolerance (default exact). The template's behaviour is one of **Always create**, **Match or create** (default), **Match only** (reject when nothing matches) or **Never match** (reject when something does); among several candidates the closest date wins, and a tie is rejected with both named. A matched installment is linked and its commitment's paid-to-date and balance update through the normal rollups. Control totals (expected count and amount for the file) are optional and checked in the dry run (G-23).

**Load one object** [v1, C-33]: a template can instead load one object, including custom objects: insert, update by record Id, or upsert by an external ID field. A lookup column can name its parent by Id, by an external ID, or by any unique field the admin picks, with the same "none or several matches" choice. This is the path for exports fixed in Excel, for the Community Suite, and for module templates such as volunteer hours and program rosters. It uses the same batch, dry run, journal and undo.

**Find** [v1, C-34]: a visual builder over one object at a time: fields and parent fields (two levels), filters in the rollup filter document (canonical model R-R2) extended with relative dates (this year, last N days) and parent fields, sort, and a row limit. The generated SOQL is shown read only, so a trained admin can check it or copy it into another tool; v1 accepts no typed SOQL (owner decision, 2026-09-23). Results show in a grid; Maria can save the query, share it with other users of the tool (each person still sees only what their own access allows), **export to CSV** (UTF-8 with a byte-order mark so Excel opens it cleanly; CSV is the only export format in v1, by owner decision 2026-09-23), or **send the results to bulk update**. Child subqueries, "with or without related records" filters, aggregates, typed SOQL, inline edit of results and XLSX export are [later, C-36].

**Bulk update** [v1, C-35]: choose records with a Find query (or a saved one), then for up to five fields choose **set to a value**, **clear**, or **copy from another field** of a compatible type on the same record. The preview shows the number of records and a sample of before and after values; Maria confirms that number. The job then runs in Batch Apex under her own permissions, processes only records that still match, and refuses to start if more records match than she confirmed. Every change is journaled; undo puts back each value nobody has changed since, within the same window as imports. Formulas and find-and-replace [later, C-37]. Bulk delete is [later, C-37] by owner decision (2026-09-23), and only with the journal recording each deleted Id so an undo can undelete from the recycle bin, a hard cap per job, and its own permission.

**Fields that can never be bulk updated or imported over:** fields the package computes (every Rollup Definition target, household name and greetings, `Last calculated` values), fields locked by an issued receipt (the receipt lock triggers still run and refuse the change), formula, auto-number and system fields, and the package's own bookkeeping objects (import, journal, error log, settings, setting changes, receipts). The list is built at run time from describe and the Rollup Definitions, so a new rollup is protected without code.

**Ongoing imports:** a recurring template names its source and the Hub shows the last load date (R-IT6); a person still uploads, dry-runs and commits. **Scheduled imports and connections to other systems** (SFTP, cloud storage, databases, other orgs) are a planned post-1.0 release (C-38) by owner decision (2026-09-23); they supersede R-IT6's "nothing loads on a schedule" only for that release and will need Named Credentials, outbound callouts documented for security review, and an unattended-run safety design (a scheduled dry run that commits only when its counts fall inside limits the admin set).

**Architecture decisions.**
- **Everything runs inside the org, with no call to Salesforce's own APIs** [v1]. A Lightning session cannot call the REST or Bulk API, and the workaround (a Named Credential with an External Client App calling the org from Apex) needs Setup steps Section 2.3 forbids, a stored token, and a documented self-callout at security review. Batch Apex is enough at our scale (the Section 7.3 scale test is a 250,000-row file): 200 rows a chunk is 1,250 executions, well inside the daily asynchronous limit. No Bulk API or Named Credential path is built in v1 or 1.x (owner decision, 2026-09-23); it is revisited only with C-38, which needs Named Credentials anyway, and only if the 1M-gift scale test shows Batch Apex too slow.
- **Staging only where it earns its storage.** File imports stage rows because dry run, exceptions and explanation need them. Staged rows are purged when the job commits, except rejected rows, which stay for the undo window: undo reads the tags and the journal, never the rows (C-19), and 250,000 staged rows would hold roughly half a gigabyte of a small nonprofit's data storage. Bulk update stages nothing: its criteria, its confirmed count and the journal are the record.
- **Queries are built from a document, never from text.** Find, bulk update and saved queries share one Core query document (object, fields, filter per R-R2, order, limit). A `QueryCompiler` turns it into SOQL only from names taken out of describe results (an object or field not in the running user's describe is refused), puts every value in a bind variable, and runs `Database.queryWithBinds` with `AccessLevel.USER_MODE`, so CRUD, FLS and sharing apply to every read. Updates run `Database.update(records, false, AccessLevel.USER_MODE)`. The only system-mode writes are the job record and the journal, under ADR-0021. The SOQL the admin sees is rendered from the document for display; the server never accepts SOQL text. Typed SOQL is not in v1 (owner decision, 2026-09-23). If C-36 allows it later, it is parsed into the same document in the browser and the server checks it exactly as before, so there is no second enforcement path; it needs its own ADR, because it is the first exception to Section 4.10's rule against SOQL typed by admins.
- **Core names no standard object.** The object list comes from describe at run time, so an org with Opportunity or Campaign can find and update them, and Core still compiles and runs on a Platform-only org (Section 4.2, ADR-0013).
- **Export is paged by the browser** in Id order through the same selector, up to an export limit set in the console (default 50,000 rows); a server-side export for larger sets is [later, C-36].
- **Automation still runs.** Imports and bulk updates fire triggers, flows, validation rules and duplicate rules as any save does. They never pause automation themselves; the admin's pause (C-23) remains a deliberate, expiring choice.

**Settings (Nonprofit Settings console, Data section):** rows per chunk [built], days a job can be undone [built], maximum records per bulk update (default 50,000), export row limit (default 50,000), default date window and amount tolerance for donation matching (Giving).

**Permissions** (owner decision, 2026-09-23): import stays with the settings permission (`Manage_Nonprofit_Settings`) for now. Two new custom permissions, in the admin permission set and assignable alone: `Find_And_Export_Records` and `Bulk_Update_Records`, so an organization can let staff export without letting them update. Neither grants access to any record: both only open tools that act with the user's own access.

**Bulk performance:** Batch Apex with the configurable chunk size; progress on the job record; results and undo on the History page.

### 4.10 Rollup engine (Core; used by every module)

- `Rollup_Definition__c`: source object, target object, relationship path (supports the household membership abstraction), aggregate (SUM, COUNT, MIN, MAX, FIRST, LAST, AVG), filters (declarative, with a filter builder UI, no SOQL typed by admins; Find (Section 4.9) likewise compiles its queries from a document and does not accept typed SOQL in v1, and typed SOQL (C-36) would need its own ADR), fiscal-year awareness (fiscal year start month setting), and **mode**: Real-time (trigger-driven, for small volumes), Scheduled (batch, default nightly), or Both (real-time with nightly reconciliation). Every target field shows a `Last calculated` sibling value in the rollup UI.
- Packaged default definitions for households, contacts, organizations, funds, appeals, and commitments are shipped as custom metadata and materialized as records on install (Section 4.8).
- The engine must be governor-limit safe (queueable chaining, platform events for fan-out) and idempotent (a recalculation of any record set produces the same result).
- **Build vs. reuse decision:** before writing a rollup engine, evaluate vendoring an existing well-maintained open source Apex rollup library under a compatible license (MIT-licensed libraries exist). Criteria: 2GP-packageable as source, supports parent-child and lookup rollups, has a declarative metadata model we can drive from our UI, and has tests. Record the outcome as a decision. Do not build a lesser version of something that already exists.
- **Freshness surfacing**: the Hub shows "Rollups last completed" and a warning tile if the schedule has not run in 36 hours.

### 4.11 Giving model (Giving package)

Canonical entities and their Salesforce objects:

| Entity | Object | Notes |
|---|---|---|
| Gift (a received transaction) | `Gift__c` | Donor (Contact or Account, one required), household (derived), date, amount, type (Cash, Check, Card, ACH, Stock, In-kind, Grant, Other), status (Received, Pending, Refunded, Written off, Cancelled), appeal, acknowledgment status and date, receipt number, tribute, matching gift link, commitment link, external ID, payment reference. Auto-named. |
| Allocation | `Gift_Allocation__c` | Gift to Fund with amount or percent; default allocation rules by appeal or donor; must total 100%. |
| Fund | `Fund__c` | The restriction or designation (NPSP General Accounting Unit, NPC Gift Designation). Active flag, restricted flag, accounting code, rollups. |
| Commitment | `Commitment__c` | Pledges and recurring gifts in one object with `Type__c`: Pledge (fixed total, installments) or Recurring (open-ended schedule). Frequency, amount, start, end, day of month, status, expected total, paid to date, balance. |
| Installment | `Installment__c` | Scheduled expected payments generated from the commitment; a Gift links to the installment it fulfills; overdue and upcoming reports come from here. |
| Soft credit | `Soft_Credit__c` | Contact or Account, gift, role (Household Member, Matched Donor, Solicitor, Honoree, Influencer, custom), amount or percent. Automatic household-member soft credits (setting). |
| Tribute | `Tribute__c` | In honor of or in memory of; honoree name or contact; notification recipient; notification sent flag. |
| Matching gift | field on `Gift__c` | `Matched_Gift__c` lookup to the employer's gift plus employer on Contact; matching gift company data is out of scope. |
| Appeal | `Appeal__c` | The nonprofit's "campaign" (year-end mailing, gala, spring appeal) with goal, cost, dates, parent appeal, response rollups. Optional link to standard Campaign in Connect. |
| Acknowledgment rule | `Acknowledgment_Rule__c` | Criteria (amount range, gift type, appeal, first gift) to template and channel (email, letter, none). |
| Receipt | `Receipt__c` | Numbered, immutable once issued, PDF stored as a File; per-gift or consolidated year-end statement per household or organization. |
| Gift batch | `Gift_Batch__c` | Manual entry screen: enter twenty checks in a grid with defaults, validate totals against a control total, post. Has its own line object rather than staging through the Import framework (ADR-0045): posting is synchronous and all or nothing, and creates ordinary gifts. |

Design rules: a Gift's donor is either a Contact (with household derived) or an Account (organization or household directly); never both. Refunds are new Gifts with negative amount linked to the original, not edits. A Pending gift that will never be paid is set to Cancelled, a non-money step: no negative gift, excluded from rollups, the accounting export, receipts and retention reports, and not blocked by the G-20 posting flag or period lock, because it was never in the books; Written off is kept for gifts that were Received. This replaces the admin-guide advice to delete unpaid Pending gifts (G-04 amendment, owner decision 2026-09-24; built on G-20 in v0.6, D-14). Amounts never change after a receipt is issued; a correction voids and reissues.

### 4.12 Connect adapters (Connect package)

- **Opportunity mirror**: one-way `Gift__c` to Opportunity (record type `Donation`, Stage Closed Won, Close Date = gift date, Amount, Account, Primary Contact Role, Campaign from appeal link) so NPSP rollups, NPSP soft credits, and Opportunity-dependent apps keep working. Option "Opportunity is source": when an online giving tool writes Opportunities, create `Gift__c` from them instead. Conflict rule: exactly one direction per org, chosen in Settings, with a reconciliation report.
- **Campaign sync**: `Appeal__c` to Campaign one-way, so Campaign Members and marketing tools work.
- **Gift Transaction mirror** (Agentforce Nonprofit): one-way `Gift__c` to `GiftTransaction` plus designation, so native donor summaries and Agentforce actions still see gifts. Dynamic Apex only; feature hidden when the objects are absent.
- **Inbound gift API**: a namespaced REST endpoint (`/services/apexrest/<namespace>/v1/gifts`, versioned, with no product name in the path so a rename never breaks a sender) accepting a simple JSON gift with donor matching, plus a Flow-invocable action, so any processor or integration platform can post gifts without knowing our objects. Idempotent by external ID.
- **Accounting export**: gifts by fund, date range, and payment method as CSV in a QuickBooks-friendly layout. The export only reads and marks no gift; the posting flag per gift and the period lock belong to Giving (G-20).

### 4.13 Security and sharing

- Ship with private OWD recommended for Gifts and Commitments, public read for Households and Contacts; the Setup Assistant explains the choice and offers a one-click "small team: everyone sees everything" configuration.
- All Apex runs `with sharing` unless a documented reason exists; CRUD and FLS checked via `Security.stripInaccessible` and `WITH USER_MODE`.
- No hard-coded IDs, no `without sharing` utilities exposed to LWC, no secrets in metadata. These are security review requirements and CI enforces them with Salesforce Code Analyzer.

### 4.14 Internationalization and accessibility

- All labels in Custom Labels from day one; English only in v1, translation-ready.
- Currency and date formatting via platform locale.
- LWC built to WCAG 2.1 AA; use base Lightning components; no custom color-only status indicators.

---

## 5. Feature catalog

Priority: **P0** must ship before v1.0; **P1** should ship before v1.0 if the iteration holds; **P2** post-1.0. "Iter" is the planned iteration from Section 6. Major features (M) are multi-week efforts with their own admin-guide page; minor features (m) are days of work.

### 5.1 Core package

| ID | Feature | Size | Pri | Iter | Notes |
|---|---|---|---|---|---|
| C-01 | Household model: Account record type, automatic creation, contact and junction membership modes behind `HouseholdService` | M | P0 | 0.1 | Section 4.6 |
| C-02 | Household naming and greetings with live preview and per-record override | M | P0 | 0.1 | Handles deceased, differing surnames, ordering |
| C-03 | Nonprofit Hub app, Settings console, `Manage_Nonprofit_Settings` permission | M | P0 | 0.1 | Section 4.8 |
| C-04 | Trigger framework with per-automation admin bypass and global pause | M | P0 | 0.1 | Vendor or write; must be tiny |
| C-05 | Error Log object, Hub tile, daily digest | m | P0 | 0.1 | |
| C-06 | Packaged permission sets and groups; in-app access assignment page | m | P0 | 0.1 | Never require cloning |
| C-07 | Coexistence mode setting with automatic detection | m | P0 | 0.1 | Section 4.5 |
| C-08 | Record types, page layouts, compact layouts, list views for Contact and Account | m | P0 | 0.1 | Lightning record pages with Dynamic Forms; one minimal fallback layout per object; no Chatter feed, activity panel kept |
| C-09 | Household merge and split tools | m | P0 | 0.1 | Recalculates rollups |
| C-10 | Sample data loader (a realistic 200-household demo set) | m | P0 | 0.1 | Used by tests, demos, and the Setup Assistant |
| C-11 | Health Check v1 (org shape, license shape, access gaps) | m | P0 | 0.1 | |
| C-12 | Setup Assistant (guided, resumable checklist) | M | P0 | 0.2 | Skeleton in 0.1, full in 0.2 |
| C-13 | Rollup engine with declarative definitions, modes, filter builder, freshness | M | P0 | 0.2 | Section 4.10; build-vs-vendor decision first |
| C-14 | Import framework v1: upload, auto-mapping, dry run, commit, results | M | P0 | 0.2 | Section 4.9; gift rows need G-23 |
| C-15 | Relationships (contact to contact, reciprocal, typed) | M | P0 | 0.3 | NPSP `npe4` successor |
| C-16 | Affiliations (contact to organization, role, primary, dates) | m | P0 | 0.3 | NPSP `npe5` successor |
| C-17 | Addresses object with default propagation to standard fields | M | P0 | 0.3 | Section 4.7 |
| C-18 | Seasonal address swap job with visible last run | m | P0 | 0.4 | |
| C-19 | Import 2.0: undo, journaling, recurring sources, XLSX | M | P0 | 0.5 | |
| C-20 | Duplicate detection and merge suggestions (households and contacts) | m | P0 | 0.5 | Uses platform duplicate rules where present |
| C-21 | Health Check v2 with fix actions | m | P0 | 0.5 | |
| C-22 | Junction membership hardening with Person Accounts (Agentforce Nonprofit coexistence) | M | P0 | 0.5 | |
| C-23 | Automation pause with auto-expiry; error digest email | m | P0 | 0.6 | |
| C-24 | Module Manager (install links, on, off, uninstall pre-flight) | M | P0 | 0.8 | Needed once a second package exists |
| C-25 | Multiple email addresses on a person (personal, work, alternate, with a preferred choice that keeps the standard Email in step) | S | P1 | 0.5 | Added 2026-09-15 for Sales Cloud readiness; built on `feature/c-25-multiple-emails` |
| C-26 | Telemetry, opt-in, anonymous (installed modules, org shape, error counts) | m | P1 | 0.11 | Informs the roadmap; default off |
| C-27 | In-app "What's new" after upgrade | m | P1 | 0.12 | |
| C-28 | Data hygiene console (orphans, missing households, bad addresses) | m | P2 | 1.x | Uses C-34 saved queries |
| C-29 | Neutral Core: nonprofit wording, the nonprofit app, the giving and receipt settings, and the nonprofit Setup Assistant steps move out of Core into Giving, so Core alone is the Community Suite | M | P0 | 0.6 | Owner decision (Brandon, 2026-09-23), Section 3 "Suites and packaging" |
| C-30 | Suite choice in the Setup Assistant: the first step asks Impact Suite or Community Suite; the Nonprofit Edition toggle opens Salesforce's installer for Giving and then offers the other modules | m | P0 | 0.8 | Built with C-24; a package cannot install another silently |
| C-31 | Unlocked-to-managed migration kit for production pilots: export, uninstall the unlocked packages, install the managed ones, reimport, verified against a pilot copy | M | P0 | 0.11 | Salesforce offers no conversion of an installed unlocked package |
| C-32 | Import matching and per-file values: matching per entity with a chosen external ID field, organization matching, a rule for several matches (reject the row by default), per-file values, Affiliation resolved in Core, staged rows purged on commit except rejects | m | P0 | 0.7 | **[v1]** Amends C-14 and C-19 scope; NPSP Data Importer parity for Core |
| C-33 | Load one object: insert, update by Id, upsert by external ID, for any object including custom ones, lookups by Id, external ID or any unique field; same dry run, journal and undo | M | P0 | 0.7 | **[v1]** Jetstream and dataimporter.io load; Community Suite import; used by V-06 and P-06 templates |
| C-34 | Find: visual query builder over one object with parent fields, R-R2 filters with relative dates, sort and limit; SOQL shown read only; saved and shared queries; CSV export; send to bulk update | M | P1 | 0.7 | **[v1]** Jetstream query builder, narrowed; no typed SOQL (owner decision 2026-09-23); `Find_And_Export_Records` permission |
| C-35 | Bulk update: set, clear or copy up to five fields on the records a Find query returns; count preview and confirmation; Batch Apex in user mode; journaled and undoable with the C-19 journal | M | P1 | 0.7 | **[v1]** Jetstream Update Records plus undo; `Import_Batch__c.Operation__c`; `Bulk_Update_Records` permission |
| C-36 | Find, advanced: typed SOQL checked through the same query document, child subqueries and "with or without related" filters, aggregates, XLSX export, inline edit of results, server-side export | M | P2 | 1.x | **[later]** Owner decision 2026-09-23; typed SOQL needs its own ADR (Section 4.10) |
| C-37 | Data transforms and dedupe: formulas and find-and-replace in mappings and bulk update; matching through the org's duplicate rules; bulk delete with undelete from the journal | M | P2 | 1.x | **[later]** dataimporter.io and Jetstream; bulk delete later by owner decision 2026-09-23 |
| C-38 | Scheduled imports and external sources (SFTP, cloud storage, databases, other systems), with a scheduled dry run that commits only inside admin-set limits | M | P2 | 1.x | **[later]** Owner decision 2026-09-23; Section 6.1 theme; supersedes R-IT6 for that release; the only path that may add Named Credentials or the Bulk API |
| C-39 | Interaction notes (lightweight major-gift contact reports on Contact and Account) | m | P1 | 0.9 | Copies the useful part of NPC Interaction Summaries |

### 5.2 Giving package

| ID | Feature | Size | Pri | Iter | Notes |
|---|---|---|---|---|---|
| G-01 | Gift, Allocation, Fund objects with auto-naming, donor rules, default allocation | M | P0 | 0.2 | Section 4.11 |
| G-02 | Default giving rollups (household, contact, organization, fund) via engine | m | P0 | 0.2 | Ships as metadata defaults |
| G-03 | Quick gift entry form (mobile-friendly) | m | P0 | 0.2 | One screen, defaults from settings |
| G-04 | Refund and write-off as linked negative gifts | m | P0 | 0.2 | Amended 2026-09-24: an unpaid Pending gift is Cancelled, not written off (Section 4.11, D-14); built with G-20 in v0.6 |
| G-05 | Appeal object with goal, cost, dates, parent, response rollups | m | P0 | 0.2 | |
| G-06 | Giving dashboard v1 (by month, by fund, by appeal, top donors) | m | P0 | 0.2 | Standard reports and dashboard, packaged |
| G-07 | Commitments (pledge and recurring) with generated installments, balances, overdue and upcoming views | M | P0 | 0.3 | |
| G-08 | Soft credits with automatic household-member credits (setting) | M | P0 | 0.3 | |
| G-09 | Tributes (honor, memorial, notification recipient) | m | P0 | 0.3 | |
| G-10 | Matching gift linkage (employer gift to employee gift) | m | P0 | 0.3 | |
| G-11 | Pledge balance and commitment rollups | m | P0 | 0.3 | |
| G-12 | Acknowledgment rules and templates (email, letter merge) with sent tracking | M | P0 | 0.4 | Uses standard email templates where possible |
| G-13 | Receipts: numbered, immutable PDF per gift; consolidated year-end statements per household and organization; batch generation | M | P0 | 0.4 | The most-requested missing feature in the segment |
| G-14 | Donor levels (configurable tiers, auto-assign, previous level, movement) | M | P0 | 0.4 | NPSP Levels successor |
| G-15 | Stewardship plans (templates that generate tasks on trigger events) | m | P0 | 0.4 | NPSP Engagement Plans successor |
| G-16 | Retention reports: LYBUNT, SYBUNT, new vs retained, first-to-second conversion | m | P0 | 0.4 | Correct by construction; definitions documented |
| G-17 | Gift batch entry grid with control totals | M | P0 | 0.5 | Own batch line object, not the Import framework (ADR-0045) |
| G-18 | In-kind gifts with fair-market value and description | m | P0 | 0.4 | Receipt language differs |
| G-19 | Donor scoring (recency, frequency, monetary) as rollups | m | P1 | 0.9 | Copies NPC's good idea |
| G-20 | Accounting posting flag and period lock | m | P1 | 0.6 | Prevents edits to posted gifts. The Cancelled status for unpaid Pending gifts (G-04 amendment, D-14) is built on top of it; a Cancelled gift is never posted, so neither the flag nor the lock blocks it |
| G-21 | Stock and planned gift types with extra fields | m | P2 | 1.x | |
| G-22 | Membership tracking (levels with expiry, renewal reminders) | M | P2 | 1.x | Common ask; separate module candidate |
| G-23 | Gift import: Giving's `ImportEntityProcessor` resolves gift, allocations (split across funds by amount or percent), soft credit and tribute; tags and undoes its own records, keeping any gift with an issued receipt; control totals (expected count and amount) | M | P0 | 0.5 | **[v1]** Completes C-14's gift promise; Agentforce Nonprofit and NPSP gift templates depend on it; brought into v0.5 by owner decision (2026-09-23) because gift import does not work today |
| G-24 | Donation matching: match an incoming gift to an existing gift by external ID or to an open installment within a date window and amount tolerance; four behaviours; closest date wins, a tie is rejected | m | P0 | 0.5 | **[v1]** NPSP Donation Matching parity; owner decision 2026-09-23 |

### 5.3 Volunteers package

| ID | Feature | Size | Pri | Iter | Notes |
|---|---|---|---|---|---|
| V-01 | Volunteer profile on Contact; Jobs; Shifts | M | P0 | 0.8 | |
| V-02 | Sign-ups and staff-entered hours with approval | M | P0 | 0.8 | No portal in v1 |
| V-03 | Hours rollups to contact and household; coordinator dashboard | M | P0 | 0.8 | |
| V-04 | Skills, availability, interests | m | P0 | 0.8 | |
| V-05 | Onboarding status (application, background check, orientation) | m | P0 | 0.8 | |
| V-06 | Volunteer hours import template | m | P0 | 0.8 | Built on C-33 load one object |
| V-07 | Recurring shifts | m | P0 | 0.8 | |
| V-08 | Hour letters and certificates via the receipts engine | m | P0 | 0.8 | |
| V-09 | Public sign-up page (Sites, unauthenticated) | M | P2 | 1.x | Guest user security review burden |

### 5.4 Programs package

| ID | Feature | Size | Pri | Iter | Notes |
|---|---|---|---|---|---|
| P-01 | Program, Service, Enrollment | M | P0 | 0.9 | |
| P-02 | Attendance and service delivery logging (grid, mobile) | M | P0 | 0.9 | |
| P-03 | Moved to the Logic Models package as L-02 (owner decision, Brandon, 2026-09-23) | | | | Outcomes live in Logic Models only, so there is one outcome model |
| P-04 | Case notes (dated, typed, private by default) | m | P0 | 0.9 | Sharing preset for participant privacy |
| P-05 | Program dashboard | m | P0 | 0.9 | |
| P-06 | Program import template (roster) | m | P0 | 0.9 | Built on C-33 load one object |
| P-07 | Intake and eligibility fields with configurable picklists | m | P0 | 0.9 | |
| P-08 | Participant privacy sharing preset | m | P0 | 0.9 | |
| P-09 | Waitlists and capacity | m | P2 | 1.x | |

### 5.5 Funders package

| ID | Feature | Size | Pri | Iter | Notes |
|---|---|---|---|---|---|
| F-01 | Funder pipeline: opportunities applied for, awards, stages, amounts, decision dates | M | P0 | 0.10 | Funder is an Organization Account |
| F-02 | Reporting requirements and deadlines with reminders | M | P0 | 0.10 | Serves market need #1 |
| F-03 | Restricted fund tracking: received, released or spent entries, balance | M | P0 | 0.10 | Simple ledger, not accounting |
| F-04 | Government award fields (assistance listing number, award number, period, drawdowns) | m | P0 | 0.10 | |
| F-05 | Multi-year award schedules | m | P0 | 0.10 | Reuses Commitment and Installment |
| F-06 | Funder report merge template | m | P0 | 0.10 | |
| F-07 | Board dashboard (revenue mix, concentration, restricted balances) | m | P0 | 0.10 | |
| F-08 | Deadline calendar view | m | P0 | 0.10 | |

### 5.6 Connect package

| ID | Feature | Size | Pri | Iter | Notes |
|---|---|---|---|---|---|
| X-01 | Opportunity mirror, both directions, one active per org, reconciliation report | M | P0 | 0.6 | |
| X-02 | Campaign sync from Appeals | m | P0 | 0.6 | |
| X-03 | Inbound gift REST API and Flow-invocable action | M | P0 | 0.6 | Idempotent by external ID |
| X-04 | Accounting export (CSV by fund, date, method) | m | P0 | 0.6 | |
| X-05 | NPSP coexistence: adopt household accounts, map record types | m | P0 | 0.6 | |
| X-06 | API documentation and sample payloads | m | P0 | 0.6 | |
| X-07 | Gift Transaction mirror (Agentforce Nonprofit) | M | P0 | 0.10 | Dynamic Apex only |
| X-08 | Webhook receivers for common processors (community-contributed) | m | P2 | 1.x | Belongs to the community |

### 5.7 Logic Models package

Owner decision (Brandon, 2026-09-23): Logic Models is its own package, working alongside Programs rather than inside it. Programs records what the organization did and for whom. Logic Models records what changed and how the organization knows it, as a logic model the organization builds itself. Keeping them apart makes that difference visible, lets an organization build and report on its logic model before it tracks any services in Salesforce, and lets outcomes draw on volunteer hours or giving as well as program services. Logic Models depends on Core only, and neither Logic Models nor Programs references the other: a computed indicator reads its value from whatever object holds the activity. The package was first recorded as "Impact" and renamed the same day, so the name does not collide with the Impact Suite.

| ID | Feature | Size | Pri | Iter | Notes |
|---|---|---|---|---|---|
| L-01 | Logic model builder in the app: inputs, activities, outputs, outcomes (short, intermediate and long term), impact, and the assumptions between them; one for the organization and optionally one per program | M | P0 | 0.9 | Built in the Nonprofit Hub, never in Setup |
| L-02 | Indicators on outputs and outcomes: unit, baseline, target and result per period | M | P0 | 0.9 | Absorbs P-03 |
| L-03 | Indicator sources: manual entry, import, or computed from any object (service deliveries, attendance, volunteer hours, gifts) | M | P0 | 0.9 | No dependency on Programs, Volunteers or Giving. The computed source must be proven before v0.9 starts: the audit of 2026-09-23 found Core's rollup engine needs a lookup from the source record to the indicator period, which no source object has; try a standard report as the source first |
| L-04 | Logic model report, comparing periods, ready to send to a funder | m | P0 | 0.9 | |
| L-05 | Evidence log: what supports each assumption, with its source | m | P1 | 1.x | |
| L-06 | Link outcomes to grant deliverables when Funders is installed | m | P1 | 0.10 | No hard dependency in either direction |

---

## 6. Roadmap by iteration

Each iteration targets about three major and five minor features, plus engineering work. Iterations are not time-boxed to a calendar; they are done when the definition of done (Section 7.4) is met. Realistic pace for one architect with AI agents: two to four weeks per iteration. Do not start an iteration's features until the previous iteration's package version is promoted and installed in the test orgs.

| Iteration | Theme | Major | Minor | Engineering |
|---|---|---|---|---|
| **v0.1** | Foundation and households | C-01, C-02, C-03 | C-05, C-06, C-07, C-08, C-09 (plus C-04 trigger framework, C-10 sample data, C-11 health check as enabling work) | Namespace registered; Dev Hub; monorepo; CI on four scratch org shapes; Code Analyzer gate; first package version created |
| **v0.2** | Giving core | G-01, C-13, C-14 | G-02, G-03, G-04, G-05, G-06 (plus C-12 Setup Assistant full) | Rollup build-vs-vendor decision recorded; performance baseline (10k gifts) |
| **v0.3** | Commitments, relationships, addresses | G-07, C-15, C-17 | C-16, G-08, G-09, G-10, G-11 | NPSP import templates; second package (Giving) published |
| **v0.4** | Stewardship and receipting | G-12, G-13, G-14 | G-15, G-16, G-18, C-18, gift receipt PDF branding settings | PDF generation approach settled (Visualforce render as PDF vs LWC print) |
| **v0.5** | Import 2.0, gift import, and coexistence hardening | C-19, G-17, C-22, G-23 gift import | C-20, C-21, G-24 donation matching, NPC and NPSP import templates, XLSX support, undo retention setting | Person Account scratch org shape as a locally gated org: the long-lived `oi-pa` scratch org with Person Accounts (owner decision, 2026-09-24), tested through `scripts/org/run-org-tests.sh`, not a GitHub CI matrix. Four major features, above the usual three, because gift import does not work today (no package implements `ImportEntityProcessor`; the Core class looks up `GiftImportProcessor`, which does not exist) and the first customers must migrate gifts (owner decision, 2026-09-23) |
| **v0.6** | Connect | X-01, X-03, C-23 (as the third major-sized effort) | X-02, X-04, X-05, X-06, G-20, C-29 neutral Core | Connect package published; dynamic Apex conventions documented; Core installs alone with no nonprofit wording |
| **v0.7** | Data management | C-33, C-34, C-35 | C-32, admin-guide pages for Find and Bulk update | Security review notes for the query compiler; a 250,000-row import and a 50,000-record bulk update with undo in the scale org (owner decision, 2026-09-23) |
| **v0.8** | Volunteers | V-01, V-02, V-03, C-24 Module Manager with C-30 suite choice | V-04, V-05, V-06, V-07, V-08 | Volunteers package published; Module Manager and suite choice tested with install links |
| **v0.9** | Programs and Logic Models | P-01, P-02, L-01, L-02, L-03 | P-04, P-05, P-06, P-07, P-08, L-04 (plus C-39, G-19 if capacity) | Programs and Logic Models packages published; participant privacy sharing verified. Five major features, above the usual three, because Logic Models ships with Programs by owner decision (2026-09-23) |
| **v0.10** | Funders and Agentforce Nonprofit mirror | F-01, F-02, F-03, X-07 | F-04, F-05, F-06, F-07, F-08, L-06 | Funders package published |
| **v0.11** | Hardening | Security review remediation; scale test (100k contacts, 1M gifts) and fixes; complete admin and contributor docs; C-31 migration kit for production pilots | Accessibility fixes; mobile audit; translation readiness; upgrade-path tests from every prior version; C-26 telemetry | Code Analyzer and manual security checklist clean; security review submission prepared |
| **v0.12** | Beta | Beta cohort of at least ten orgs with structured feedback; Setup Assistant polish against measured time-to-first-gift; NPSP self-migration playbook validated on real orgs | C-27, release-notes automation, support triage process, community forum, sample data v2 | Security review submitted; Trailblazer Community group; issue templates tuned |
| **v0.13** | AppExchange | Listing content, screenshots, demo org; final review fixes; launch communications | Whatever the beta surfaced | **v1.0 tagged on listing approval** |

### 6.1 Post-1.0 themes (parking, ordered by expected demand)

1. Memberships (G-22) as its own package.
2. Events package (registration, attendance, simple ticketing without payments).
3. Public volunteer sign-up (V-09) after a guest-user security design.
4. Community-contributed processor webhooks (X-08).
5. Donor scoring maturity, interaction summaries, major-gift portfolios.
6. Multi-currency.
7. AI-readiness pack: documented export schemas and a canonical-model JSON export so any AI tool can be grounded in clean data.
8. Localization (Spanish first).
9. CMDT Manager (for consideration, not scheduled; Brandon, 2026-09-22): an in-app tab, in both editions, where holders of a CMDT Admin permission set add, edit and archive custom metadata records through a familiar list view and record view. Known constraints: saving a record is an asynchronous metadata deployment; an unlocked package needs the org setting "Deploy Metadata from Non-Certified Package Versions via Apex"; the editor needs Customize Application and Modify Metadata, which is why the permission set is an admin one; standard list views and record pages do not support custom metadata, so the UI is custom; the Apex Metadata API cannot delete records, so archive is a field on each editable type. Moving user-editable configuration to custom objects was offered as the simpler alternative and is not accepted yet.
10. Analytics module, with field utilization as its first feature (for consideration, not scheduled; Brandon, 2026-09-23). For each object, and each record type where one is used, the share of records that hold a value in each field, with trends from saved snapshots, so an administrator can see which fields nobody fills in, which are worth making required, and which can be retired. A batch job counts field values in the org and stores each run as snapshot records, reported through standard reports and dashboards, with no CRM Analytics dependency. It is neutral, so both suites get it. It works with the data hygiene console (C-28) and the data management tools: a low-use field can go straight into a query or a bulk update. "Where is this field used" (page layouts, record pages, reports, flows) needs the Tooling or Metadata API, which means a callout to the org's own API; that part waits for the same decision as connections to other systems.
11. Data management 2 (C-36 typed SOQL, subqueries, aggregates, XLSX export, inline edit; C-37 transforms, dedupe on import, bulk delete).
12. Scheduled imports and connections to other systems (C-38), owner decision 2026-09-23.

### 6.2 Priority rules used (so future re-prioritization stays consistent)

1. Anything Maria needs on day one (install, households, gifts, import) outranks everything.
2. Anything that protects the numbers (rollups, receipts, refunds as records) outranks convenience.
3. Features that serve the five market needs (Section 2.4) outrank features that are merely familiar from NPSP.
4. Compatibility adapters come after the native experience is solid; a mirror of a bad model is a bad mirror.
5. Every new package costs install friction; a package is justified only when its schema would clutter an org that does not need it.

---


### 6.3 Re-sequencing for the Agentforce Nonprofit first-customer focus (owner decision, 2026-09-07)

Because the first customers are Nonprofit Cloud / Agentforce Nonprofit orgs (Section 2.1), the following items move; the tables in Section 5 and 6 keep their original rows and this subsection governs where they differ:

- C-22 (junction membership hardening with Person Accounts) moves from v0.5 into v0.1 and v0.2: v0.1 ships junction mode as a working, tested path (Household_Member__c with Person Account members through dynamic field access, naming and greetings from Person Account name fields, sample data that loads as Person Accounts when they are enabled); v0.2 finishes hardening (merge, split, rollups through the junction).
- The Person Accounts org shape is the primary CI shape; a true Nonprofit Cloud scratch org shape (Industries features) is added as soon as the feature name is verified (owner follow-up).
- X-07 (Gift Transaction mirror) moves from v0.10 to v0.6; X-05 (NPSP coexistence: adopt household accounts) moves from v0.6 to v0.10. The NPSP org shape stays in CI but is not gating for v0.1 to v0.5 acceptance.
- Import templates: both sets, the NPC import templates (Nonprofit Cloud: Gift Transaction and related) and the NPSP import templates, ship together in v0.5 (owner decision, 2026-09-24). C-14 in v0.2 shipped only the generic donor and gift list templates; the NPC set was not built then.
- Every entity that references a person (Household Member, Gift donor, Soft Credit, Relationship, Affiliation, Address personal owner, Tribute honoree and recipient) carries both a Contact reference and an Account reference with the rule that exactly one is set, so Person Account people work everywhere without a compile-time dependency (Section 4.2 hard rules still apply: no Person Account field is referenced statically in Core).
- **Dependency rule reaffirmed by the owner (2026-09-07):** focusing on Nonprofit Cloud / Agentforce Nonprofit customers does not create a dependency on them. All core functionality depends only on this product and on functionality included with the Salesforce platform: no additional cloud, Industries object, permission set license, or add-on product is ever required (Principle 4, D-09). Integrations with other solutions (Nonprofit Cloud objects, NPSP, payment processors, accounting) live in the Connect package or later adapters and are optional. Vendored open source code is included as source under the project license, never as a package dependency.

## 7. Engineering standards, quality, and definition of done

### 7.1 Naming conventions

- **Objects and fields:** `PascalCase__c`, module-neutral names (no module prefix in the API name because the namespace already disambiguates and prefixes make labels ugly). Labels are plain English a nonprofit uses: "Gift" not "Donation Transaction," "Fund" not "General Accounting Unit."
- **Apex:** one class per responsibility. Prefixes by role: `*Service` (business logic, the only place other modules may call), `*Selector` (SOQL), `*Domain` or `*TriggerHandler` (record-level rules), `*Controller` (LWC-facing, `@AuraEnabled`), `*Batch`, `*Queueable`, `*Schedulable`, `*Test`. Cross-package calls go through `global` service interfaces only.
- **LWC:** `npc` prefix folder naming not required (namespace handles it); component names describe the screen: `settingsConsole`, `householdNamingPreview`, `importWizard`.
- **Custom labels:** `Module_Screen_Purpose` (for example `Giving_ReceiptPage_IssuedStamp`).
- **Custom permissions:** `Manage_Nonprofit_Settings`, `Enter_Gifts`, `Issue_Receipts`, `Manage_Volunteers`, `Manage_Programs`, `Manage_Logic_Models`, `View_Funder_Pipeline`.

### 7.2 Code rules (CI-enforced where possible)

- Apex: `with sharing` by default; `WITH USER_MODE` or `Security.stripInaccessible` on every DML and query that touches user-facing data; bulkified; no SOQL or DML in loops; no hard-coded IDs; no `Test.isRunningTest()` branches in production logic.
- Every trigger goes through the trigger framework; one trigger per object; handlers are bypassable.
- Every `@AuraEnabled` method validates input and returns a typed result or a structured error the UI can render.
- Governor-limit safety proven by tests that insert 200 records per DML context.
- LWC: no third-party JS except vetted static resources. None is used today: SheetJS's pre-approval for import parsing is unused, since C-19 reads XLSX in the browser without it (ADR-0049). Record any addition as a decision. Jest tests for every component with logic.
- Salesforce Code Analyzer (PMD, ESLint, retire-js, Graph Engine for FLS/CRUD) must pass with zero high or critical findings on every pull request. This is the single best predictor of passing security review.
- Apex test coverage target 90% per package; 75% is the platform minimum and is not the target.

### 7.3 Testing strategy

- **Unit tests** per class, data created through a shared `TestDataFactory` in Core (exposed `@IsTest global` so module packages can use it).
- **Org-shape matrix in CI:** every pull request runs tests on four scratch org definitions: Platform-only, Sales Cloud, Sales Cloud with NPSP installed, and Person Accounts enabled (simulating Agentforce Nonprofit shape; a true Nonprofit Cloud scratch org needs the Industries features flag, add it when available). Connect's dynamic Apex is verified by the Platform-only shape where the objects are absent.
- **Upgrade tests:** install version N-1, load sample data, upgrade to N, run assertions. Automated from v0.3 onward.
- **Scale tests** (v0.11): 100k contacts, 40k households, 1M gifts, rollup full recalculation within platform limits; import of a 250k-row file.
- **Manual acceptance:** each feature has a scripted walkthrough in its admin-guide page that a human (Brandon) performs before the iteration is promoted. Playwright end-to-end tests are optional and post-0.6.

### 7.4 Definition of done (per feature)

- [ ] Canonical model updated first (Section 4.4).
- [ ] Metadata, Apex, LWC complete with tests passing on all org shapes.
- [ ] Settings for the feature exposed in the Settings console with descriptions; no Setup step required for normal use.
- [ ] Permission sets updated; no new permission requires cloning.
- [ ] Error paths logged to Error Log with human-readable messages.
- [ ] Admin-guide page written (what it does, how to turn it on, a five-minute walkthrough, common mistakes).
- [ ] Release note line written.
- [ ] Sample data updated if the feature adds objects.
- [ ] Reviewed by a second agent or human against this checklist (Section 9.4).

### 7.5 Release process

1. Merge to `main` with CI green.
2. Create a package version (`sf package version create`) for each changed package; beta versions for testing.
3. Install beta into the internal test orgs (one per org shape) and the prerelease cohort.
4. Run upgrade tests and the manual walkthrough.
5. Promote (`sf package version promote`) and tag the repo `v0.N.0`.
6. Push upgrade to opted-in orgs (from v0.6; before that, manual installs). Push schedule: never on a Friday, never in the last week of December (year-end giving) or the first two weeks of January (year-end receipting).
7. Publish release notes written for Maria, not for developers.

---

## 8. AppExchange and open source readiness

### 8.1 AppExchange path (start in v0.1, not v0.11)

- Join the Salesforce Partner Program as an ISV and obtain the Partner Business Org; use it as the Dev Hub for all promoted package versions. (Verify current program terms and whether the security review fee is waived for free listings; historically it has been reduced or waived for free apps, but confirm in writing.)
- Package versions must be created from the Dev Hub that will own the listing; creating early versions from a throwaway Dev Hub means re-creating the package with new IDs later. Decide the Dev Hub before v0.1's first package version.
- Security review requirements to design for from the start: Code Analyzer clean, FLS and CRUD enforcement, no secrets, external callouts documented (we make none by default), REST endpoints with authentication documented, a test org with sample data and credentials for the review team, and an architecture document (this file plus `docs/architecture/`).
- License Management App (LMA) is optional for a free app; install it anyway so install counts and versions are visible.
- Listing assets: short description, long description, five screenshots, a two-minute video, a demo org, support URL (GitHub Discussions), documentation URL, and a privacy statement (no data leaves the org; telemetry is opt-in and anonymous).

### 8.2 Open source governance

- **License:** Apache-2.0 recommended (patent grant protects contributors and adopters); BSD-3-Clause is the NPSP precedent and an acceptable alternative. Decided 2026-09-22 (Brandon): Apache-2.0, recorded as Decision D-08.
- **Contribution:** Developer Certificate of Origin (DCO sign-off on commits) rather than a CLA; lower friction, adequate protection for a free product.
- **Steward entity:** the project needs a legal owner for the namespace, the PBO, the AppExchange listing, and the trademark. Options are a nonprofit (a revived Nonprofit Collaborative is a natural fit and aligns with "given to nonprofits for free"), an LLC, or a fiscal sponsor. This is a decision for Brandon, not the builder; it must be made before the PBO is created because the PBO is tied to a legal entity.
- **Governance model:** BDFL (Brandon) for v0.x; a maintainers group with a documented decision process by v1.0; a public roadmap in GitHub Projects.
- **Community surfaces:** GitHub Issues and Discussions, a Trailblazer Community group, quarterly community calls once there are users.
- **Contributor experience targets:** clone to running scratch org with sample data in under ten minutes via one script; every module has a `README.md` with its objects, services, and how to test it alone; `good first issue` labels maintained.

### 8.3 Name and trademark

**Update 2026-09-23 (Brandon):** "Open Impact" is not available. The tentative new name is BarnCRM, covering the Impact Suite (nonprofits) and the Community Suite (for-profit and other organizations). The same checks apply before any public use. The repository, labels and docs keep the working title until the name is verified, then are renamed in one pass.

**Name vetting behind BarnCRM (2026-09-23, Brandon with Claude).** About 900 candidates were screened by web search and DNS (not a legal clearance). Brandon's criteria: short, memorable, meaningful, natural (a word people already say; no suffix formulas such as -ly, no glued compounds, no uncommon words). His legal gate: any conflict, including a caution, rejects a name, because the project will not risk a legal dispute. Barn was the only strong name to pass. Story: the barn raising, where the whole community builds what no one could alone; also where you keep what matters and get work done. Positioning: simple and human, a calm contrast to AI-agent fatigue; pitched as simple, never as anti-AI, because the product lives on Salesforce's platform. Mascot: sea otters. Open items before public use: a full trademark search (USPTO classes 9, 35, 42, state and common law) with attention to Barnfox (a members app) and BARN OWL (computer services); register barncrm.org and barncrm.com (both showed no DNS on 2026-09-23); confirm the namespace in the Dev Hub; use "BarnCRM" consistently because "barn" alone is unsearchable. Rejected finalists, so they are not screened again: Raft (Raftr sells engagement software to nonprofits), Potluck (Potluck Inc software filing), Kindred (KINDRED software mark, Kindred CRM app), Hearth (Hearth sells CRM features), Meadow (MEADOW software registration, Meadow CRM), Kelp (Kelp Global CRM module), Nimbus (S-Nimbus AppExchange partner, TIBCO mark), Tend (TEND class 9 mark), Steward (Steward nonprofit CRM), Bandly (Naver BAND, getbandly.com), Barnly (barnly.app, barnly.life), Moyo (MOYO Salesforce partner), Comun (Común fintech), Impactly, OpenCRM; Skein, Everyhand, Manykin, Holdfast and the -ly coinages failed Brandon's taste; Stockpot, Bakesale, Clambake, Pledgehog and Lull passed the gate but scored lower.

**Re-opened 2026-09-06 (later the same day):** Brandon found that "Open Impact" is already in use, including by a foundation that funds open source work, which is too close to this project to share a name. "Open Impact" is now only a placeholder working title in the repository until a replacement is chosen and thoroughly vetted (USPTO, AppExchange, GitHub, npm, domains, social handles, Salesforce namespace). D-01 is therefore open again; the fallback "OpenCause" must go through the same vetting before use.

"Open Impact" was chosen by Brandon on 2026-09-06 after a web search found no Salesforce app, nonprofit software product, or consultancy of that name. Before any public repository, listing, or post: search the USPTO, the AppExchange listing directory, GitHub, npm, and domain registries; confirm the namespace is available. Fallback name if a conflict appears: OpenCause. Note that "impact" is heavily used across nonprofit technology, so the distinctiveness rests on the pair "Open Impact" and on a consistent visual identity. The namespace is immutable and the listing name is expensive to change.

---

## 9. Working agreements for the Claude Code session and sub-agents

This section exists because the builder is an AI session that will not have the context of the conversations that produced this plan.

### 9.1 First actions, in order (day one)

1. Read this document fully. Then read `docs/architecture/` if it exists.
2. Confirm with Brandon: license (D-08) and Dev Hub choice (Section 8.1). The namespace is deliberately deferred; build namespace-agnostic per Section 4.3 and do not create package versions until Brandon registers it.
3. Scaffold the monorepo exactly as Section 4.3 describes, with CI running an empty test suite on the four org shapes and Code Analyzer as a required check.
4. Write `docs/architecture/canonical-model.md` for the v0.1 entities (Household, Household Member, Contact, Organization) before creating any object.
5. Write the v0.1 ADRs in `docs/architecture/decisions/` from Section 12.
6. Build v0.1 per Section 6, feature by feature, each on its own branch, each meeting the definition of done.
7. Stop at the end of v0.1 and report (Section 9.5) before starting v0.2.

### 9.2 How to split work across sub-agents

Split by **module and layer**, never by "front end vs back end" across the same feature, because the interface between them is the thing that most often breaks.

- One agent owns the **canonical model and object metadata** for an iteration and publishes the field list before anyone codes against it.
- One agent per **feature** (service, trigger handler, tests, LWC, admin-guide page) working against the published metadata.
- One agent owns **CI, org shapes, and packaging** for the iteration.
- One agent acts as **reviewer** against Section 7.4 and Section 2.3 for every pull request, and must try the feature as Maria with only the admin-guide page as instructions.
- Shared metadata files (permission sets, the settings console navigation, custom labels, layouts) are merge-conflict magnets: assign one agent to integrate those from the feature agents' requests rather than letting every agent edit them.

### 9.3 Rules for agents

- Use the personas' names in tests and docs.
- When a platform limitation blocks the plan, record an ADR with the workaround and continue; do not silently change the design.
- Never add a dependency on a paid product, an Industries object, or a standard object outside Connect.
- Never put a setting in Setup that could be in the console.
- Prefer standard platform features over code (record types, dynamic forms, list views, standard reports, Flow for admin-editable logic) unless the standard feature cannot be packaged or would require Setup.
- Write the admin-guide page **before** the LWC; if the page is hard to write, the feature is too complicated.
- Keep pull requests under roughly 800 lines of change; larger ones are split.
- Every SOQL query is in a Selector; every DML that user input can reach is in user mode.
- Do not invent features. If something seems missing, add it to the parking lot (Section 11.3) with a sentence of justification and continue.

### 9.4 Review checklist (used by the reviewer agent and by Brandon)

- Does it meet the definition of done (Section 7.4)?
- Could Maria do this without Setup and without the docs? If not, why not, and is that recorded?
- Are the numbers right? (Rollups recalculated in tests after every path: insert, update, delete, undelete, reparent, merge.)
- Does it work on the Platform-only org shape?
- Does it degrade gracefully when a module is off or a standard object is absent?
- Is anything overwritten on upgrade that an admin might have changed?
- Is the label language a nonprofit's language?

### 9.5 Reporting format (end of each iteration)

A short markdown report in `docs/release-notes/v0.N.md` with: features completed against the plan, features deferred and why, ADRs added, test counts and coverage per package, org shapes passing, open risks, and the exact steps for Brandon to install and walk through the iteration in a fresh org. Brandon will review once per iteration; do not wait for him mid-iteration unless blocked by Section 9.1 item 2 or a decision in Section 11.4.

---


### 9.6 Concurrent iterations (owner decision, 2026-09-07)

Brandon directed the build session to run features from several iterations at once rather than waiting for each iteration's package version to be promoted (Section 6 sequencing rule relaxed because no Dev Hub or package versions exist yet and the owner is handling DevOps separately). Rules that still hold: the canonical model for an iteration's entities is published before its feature agents start; each feature is its own branch and pull request, reviewed against 7.4 and 9.4, and squash-merged to `main` when it passes; features from a later iteration may merge to `main` before the earlier iteration has been accepted, because `main` is unreleased. Each iteration is tagged (for example `v0.1.0-review`) when its features are complete so Brandon can QA that exact state in a fresh scratch org while `main` moves on; the iteration's release notes point at the tag. Package versions are still created only after the namespace and Dev Hub decisions.

## 10. v0.1 in detail (the first build)

### 10.1 User stories

- As Maria, I want to install one package and land on a home page that tells me what to do next, so that I never need to search for where to start.
- As Maria, I want new contacts to get a household automatically with a sensible name, so that I do not create households by hand.
- As Maria, I want to preview how household names and greetings will look before I commit to a naming rule, so that my mail merges are right the first time.
- As David, I want to override a specific household's name and greeting and have the system stop recomputing it, so that "The Reverend and Mrs. Smith" stays that way.
- As Maria, I want to move a contact to another household or merge two households from the record page, so that data cleanup takes minutes.
- As Maria, I want to give a colleague access by picking their name and a role, so that I never have to learn permission sets.
- As Maria, I want to pause an automation that is causing a problem during an import, so that I am never stuck.
- As Maria, I want to see errors in plain language in the app, so that I can fix them or ask for help with specifics.
- As Maria, when my org already has NPSP or Person Accounts, I want the app to notice and set itself up compatibly, so that I do not break what I have.
- As Sam, I want to clone the repo and have a scratch org with sample data in ten minutes, so that I can contribute.

### 10.2 Acceptance criteria (representative; the builder extends per feature)

**C-01 Household model**
- Given a fresh Platform-only org with the package installed, when a Contact is inserted with no Account, then a Household Account with record type Household is created and the Contact is attached, within the same transaction.
- Given junction mode is active and Person Accounts are enabled, when a Person Account is created, then no Household is created automatically unless the setting "Create households for person accounts" is on; when it is on, a `Household_Member__c` record links the Person Account to a new Household.
- Given a Contact is reparented to a different Household, then both households' membership counts and (once Giving is installed) giving rollups are recalculated, and the previous household is deleted if empty and the "delete empty households" setting is on.
- Given 200 Contacts are inserted in one DML, then all households are created without hitting limits.

**C-02 Naming and greetings**
- Given two members with surname Smith, then Household Name is "The Smith Family" (or the configured pattern), Formal Greeting uses configured salutations, and Informal Greeting is "John and Jane."
- Given members with differing surnames, then the name is "Smith and Jones Household" and greetings list both.
- Given a member marked deceased, then they are excluded from greetings and, if the setting is on, the name is unchanged.
- Given `Custom_Name__c` is checked on a Household, then no automatic recomputation changes Name, Formal Greeting, or Informal Greeting.
- Given the admin changes the naming pattern in the console, then a preview shows five sample households and a "Recompute all households" action runs as a batch with progress and a completion notice.

**C-03 Hub and Settings console**
- Given a user without `Manage_Nonprofit_Settings`, when they open Nonprofit Settings, then they see a read-only view with a message naming the permission.
- Given a setting is changed, then it takes effect on the next transaction without cache staleness beyond ten seconds, and the change is logged (who, when, old, new).
- Given the console search box, when "greeting" is typed, then the household naming settings appear.

**C-06 Access page**
- Given Maria selects a user and the role "Fundraising Staff," then the corresponding permission set group is assigned and the user appears in the role's list; removal works the same way.

**C-04 Automation control**
- Given "Pause all automation for 2 hours" is activated, then no packaged trigger logic runs for the org until expiry or manual resume, and the Hub shows a banner while paused.

**C-11 Health Check**
- Given NPSP is installed, then the Health Check reports "NPSP detected" and the coexistence setting defaults to NPSP coexistence with an explanation.

### 10.3 v0.1 metadata inventory (starting point; the canonical model governs)

- Account record types: Household, Organization. Contact: no packaged record type (owner decision, Brandon, 2026-09-23). The former Household Contact record type drove no behavior, and an org can add its own Contact record types without one.
- Account fields: `Household_Formal_Greeting__c`, `Household_Informal_Greeting__c`, `Custom_Name__c`, `Primary_Contact__c`, `Member_Count__c`, `Anniversary__c`.
- Contact fields: `Deceased__c`, `Household_Role__c` (Head, Spouse or Partner, Child, Other), `Exclude_From_Household_Name__c`, `Exclude_From_Greetings__c`, `Preferred_Name__c`.
- Objects: `Household_Member__c` (junction, used only in junction mode), `Error_Log__c`, `Automation_Setting__c` (or custom metadata plus custom setting per D-06), `Setting_Change__c` (audit).
- Custom settings: `Nonprofit_Settings__c` (hierarchy, protected).
- Custom metadata: `Automation_Registry__mdt`. (`Naming_Pattern__mdt` was removed on 2026-09-22, before the first package version: nothing read it, and naming reads the pattern fields on Nonprofit Settings.)
- Apex: `HouseholdService`, `HouseholdNamingService`, `HouseholdSelector`, `ContactTriggerHandler`, `AccountTriggerHandler`, `TriggerDispatcher`, `AutomationControl`, `ErrorLogger`, `SettingsService`, `AccessService`, `HealthCheckService`, `OrgShapeDetector`, `SampleDataLoader`, `TestDataFactory`, tests for each.
- LWC: `hubHome`, `setupAssistant`, `settingsConsole`, `settingsSearch`, `householdNamingSettings` (with preview), `householdMembersPanel` (record page), `householdMergeSplit`, `accessManager`, `automationControl`, `errorLogTile`, `healthCheckPanel`.
- Permission sets: `Nonprofit_Admin`, `Nonprofit_Staff`, `Nonprofit_Read_Only`; group per role.
- App: `Nonprofit Hub` with tabs Home, Households, Contacts, Organizations, Nonprofit Settings, Error Log (admin only).

---

## 11. Risks, open questions, and parking lot

### 11.1 Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Namespace or Dev Hub chosen wrong early, forcing package re-creation | Medium | High | Blocking decision before any package version (Section 9.1) |
| Custom `Gift__c` instead of Opportunity alienates NPSP-dependent apps and consultants | Medium | Medium | Opportunity mirror (X-01) in v0.6; document clearly; the Platform-license win is worth it |
| Security review takes months and finds structural issues | Medium | High | Code Analyzer gate from v0.1; user-mode everywhere; review-readiness in v0.11, not at the end |
| Multi-package install friction confuses Maria | High | Medium | Module Manager (C-24); Core plus Giving may ship as a bundled install link; measure time-to-first-gift in beta |
| Rollup engine correctness bugs damage trust | Medium | Very high | Vendor a proven library if criteria met; exhaustive path tests; nightly reconciliation mode |
| Salesforce changes the platform or Power of Us terms | Low | High | No Industries dependency; Platform-license floor is the hedge |
| Solo maintainer burnout; project stalls | High | High | Small modules; contributor guide from day one; steward entity; scope discipline (Section 1.5) |
| Person Account orgs behave differently in subtle ways | High | Medium | Dedicated CI org shape; junction mode isolated behind `HouseholdService` |
| Year-end receipt bug during December | Low | Very high | Release freeze windows (Section 7.5); receipt engine tests with fiscal-year fixtures |

### 11.2 Open questions for Brandon (blocking marked with **B**)

1. Namespace registration (deferred by Brandon; blocks package version creation only, not development).
2. **B** License: Apache-2.0 or BSD-3-Clause.
3. **B** Dev Hub: Partner Business Org now, or Developer Edition Dev Hub with a planned migration before the first promoted version.
4. Steward entity: Nonprofit Collaborative, a new entity, or personal for v0.x.
5. Should Core and Giving ship as one package for v1.0 (fewer installs) with Volunteers, Programs, Funders, and Connect separate? Current plan says separate; the argument for merging is that nearly every org needs both. Recommendation: keep separate in the repo, decide at v0.5 based on install-friction evidence. **Resolved 2026-09-23 (Brandon): separate.** The Community Suite is Core without Giving, and the guided install from the Setup Assistant (C-30) removes most of the install friction.
6. PDF generation for receipts: Visualforce render-as-PDF (mature, packageable, limited styling) versus browser print from LWC (better styling, no stored file without a callout). Recommendation: Visualforce render-as-PDF for stored, immutable receipts; decide at v0.4. **Update 2026-09-07 (ADR-0016, Proposed):** research confirmed the Visualforce rendering engine but found that `getContentAsPDF()` counts as a callout (ten documents per batch execute, unusable in triggers and tests), while `Blob.toPdf()` uses the same rendering service as plain Apex since the Summer '26 release update. Recommendation now: `Blob.toPdf()` behind a `ReceiptRenderer` seam, Visualforce page as fallback; OmniStudio Document Generation rejected (add-on license); LWC print rejected (no stored bytes). Two spikes gated before v0.4: batch metering of `Blob.toPdf()` and logo or signature image delivery to the renderer. **Resolved 2026-09-08: ADR-0016 accepted by the owner, which settles the v0.4 engineering prerequisite in Section 6.** The decision stands as proposed: `Blob.toPdf()` over package-composed HTML behind a `ReceiptRenderer` seam, with the Visualforce `renderAs="pdf"` page as the named fallback. The two spikes are not closed and cannot be until a Salesforce org is available, so G-13 is built to the accepted design with the fallback path kept viable, and both spikes are carried as open items on the feature rather than as blockers: ADR-0016 records that a receipt is legally valid with no images at all, so image delivery cannot block the feature.
7. Telemetry: include opt-in anonymous usage at all? Recommendation: yes, default off, disclosed on the listing.
8. **B** How a household names its primary person, once people can be accounts. Found by the household model review on 2026-09-09. Canonical rule R-M3 says the member marked Is Primary is mirrored to the household's Primary Contact. Nothing implements it, and nothing can as written: `Account.Primary_Contact__c` is a lookup to Contact, so it cannot name a Person Account at all. A household composed entirely of person accounts therefore has no primary contact permanently, and member ordering loses the tiebreak that R-H5 gives it. Options: add a second lookup to Account beside the existing one (two fields for one idea, but both stay reportable); make the primary a question only `HouseholdService` answers, reading the junction in junction mode and the field in contact mode (consistent with R-H3 and R-M5, and the reason this is the recommendation); or drop the mirror from R-M3 and let the two modes differ openly. The cost of the recommendation is real and should decide it: a lookup field is reportable and a service method is not, so any report or formula that names the primary person would need the field to stay for contact mode and would have nothing in junction mode. This is escalation territory under Section 11.4, which names changing the household membership abstraction. Recorded as a known gap in `docs/architecture/canonical-model.md` Section 30 in the meantime, so the rule and the code no longer disagree silently. **Resolved provisionally 2026-09-23 (Brandon delegated the choice, to be confirmed when he tests): none of the three options.** A Person Account has a Contact record of its own (its person contact), and a lookup to Contact can name it, so R-M3 is kept as written with the one existing field. `HouseholdService` stays the only writer: in contact mode it mirrors the primary Contact, and in junction mode the primary member's Contact, or, when the member is a Person Account, that account's person contact, read through dynamic Apex only in orgs that have Person Accounts, so Core keeps no dependency on them. One field, reportable in both modes; the known gap in canonical model Section 30 closes when C-22 ships.

9. **B** Party Relationship Group coexistence and migration. Found by the Sales Cloud and Nonprofit Cloud readiness audit on 2026-09-15. Today nothing stops the naming batch from renaming an Account that carries a native household group; the delete guard (ADR-0036) covers deletion only. Proposed design: one Account has exactly one household model (Open Impact never writes the name, greetings or address of an Account that carries a native group, and never auto-creates a duplicate for a person already in one), a drift report rather than any sync, and a supervised, reversible, one-time migration in Connect as feature X-09 that never deletes a native group, a membership relation or an Account. No two-way sync, because a computed name and a hand-edited name have no convergence rule. Roughly eight developer-days for the guards in Core and twelve for the migration in Connect; needs two ADRs and an `Account.Household_Model__c` field. Update 2026-09-15: detection and the four Core guards (naming on all three callers, auto-creation, address propagation, Health Check info plus collision warning) are built on `feature/household-readiness` (PR 41), using the weaker "is the person's account a native household" rule for auto-creation because native membership lives on an object Core may not query. Decision still open: guards only, or guards plus the Connect migration. **Resolved provisionally 2026-09-23 (Brandon delegated the choice, to be confirmed when he tests): guards only.** The guards already prevent the damage; the migration (about twelve developer-days) waits in the parking lot until a real org with native household groups asks for it.
10. **B** Changing the membership mode on an org that already holds household data. No migration exists in either direction. Junction to Contact makes every membership row invisible, so the next upkeep recounts households to zero, renames them to the placeholder, and deletes them when empty-household deletion is on. Contact to Junction strands everyone already on a household, because `withoutAHousehold` skips them and they never get a membership row. A guard that refuses a switch that would strand data, with a Health Check finding, is being added on 2026-09-15. Decision: keep the guard only, or build the migration both ways. **Resolved provisionally 2026-09-23 (Brandon delegated the choice, to be confirmed when he tests): keep the guard only.** A switch that would strand data is refused, with a Health Check finding that says why. If an org needs to switch, the first migration to build is contact mode to junction mode (an org that turns on Person Accounts after adopting), and only when one asks.
11. Professional Edition. **Resolved 2026-09-15 (Brandon): Professional Edition and below are not a target. Nothing has to be compatible with them, so the platform-event and permission-set-group concerns below are moot and no edition check is added to CI.** Kept for the audit trail: nothing in the repository verifies it. Field, object, record type and validation rule counts sit comfortably inside its limits; the exposure is feature availability. Permission set groups and custom platform events may be unavailable there, and `Error_Log_Event__e` is the entire error-logging path, so error logging could fail silently on that edition. Verified on 2026-09-15 from search snippets of the ISVforce Guide and release notes, not a direct read, so medium confidence: permission set groups work in that edition and packaged ones do not count against its cap of ten; objects and tabs from a security-reviewed package listed on AppExchange are exempt from its limits, which makes the exemption conditional on the listing, not on being open source; and `ErrorLogWriter` already falls back to a direct insert of `Error_Log__c` whenever publishing throws, so at runtime logging degrades rather than going silent. The one thing that could not be settled from documentation is whether a package that contains a platform event can install into Professional Edition at all, since the ISVforce Guide says platform events are not supported there. If that blocks installation, the whole package fails on that edition and the fix is to make the event optional in Core. Only a real Professional Edition trial org can answer it.
12. Housekeeping to settle before the first package version, since a custom metadata type is effectively permanent once packaged. `Naming_Pattern__mdt` (four fields, six shipped records) has no consumer anywhere; naming reads the three pattern fields on Nonprofit Settings instead. **Resolved 2026-09-22 (Brandon): remove it; removed from Core the same day.** Still open: three permission set groups, Fundraising Staff, Program Staff and Volunteer Coordinator, each contain only Nonprofit Staff. Recommendation: remove them before the first package version, since adding a packaged group later is easy and removing one is not. Decision needed before the first package version, not after.
13. Confirm the product name (Nonprofit Cloud vs Agentforce Nonprofit) and rename across the plan and docs. Raised 2026-09-24 (Brandon): he believes Agentforce Nonprofit was recently renamed back to Nonprofit Cloud. The import template sets are already called NPC import templates and NPSP import templates; nothing else is renamed until this is confirmed.
14. Shipped import templates: copied into the org at install, as Section 4 says (recommendation), or change the plan to match the code, which copies them at first use or from Health Check. Raised 2026-09-24.
15. Nonprofit Cloud gift loads into the same org: match donors by record ID, or offer a "match only, never create people" option (recommendation). Raised 2026-09-24.
16. Per-automation switches (ADR-0040): add an optional end date, or keep them off until an admin turns them back on (shipped). The org-wide pause already expires (ADR-0055). Raised 2026-09-24.
17. First-name matching: with only John Smith at a postal code, a "Jane Smith" row at the same code matches and renames John. Options: (a) create a new person when first names differ (recommendation); (b) keep today's behavior; (c) short-form matching (Bob and Robert). Raised 2026-09-24.
18. Campaign sync (X-02, ADR-0056) default: ships off, switched on in Open Impact Settings. Recommendation: keep off. Raised 2026-09-25.
19. Opportunity mirror (X-01, ADR-0058) in NPSP coexistence mode: Section 4.5 says the mirror is on there; it ships off in every mode until an admin picks a direction. Recommendation: NPSP mode pre-selects Gifts to Opportunities and asks the admin to confirm, recorded in an ADR. Raised 2026-09-25.
20. Opportunity mirror, gift deleted: ships leaving the Opportunity alone with a Warning naming it (recommendation), versus moving it to lost or deleting it. Raised 2026-09-25.
21. Opportunity mirror, double thanks: gifts made from Opportunities are ordinary gifts and get acknowledgments. Recommendation: a setting "Acknowledge gifts made from Opportunities", default off. Not built. Raised 2026-09-25.
22. Opportunity mirror record-type filter: built, empty by default (all won Opportunities after the start date become gifts, sales ones included). Keep empty, or default to donation record types. Raised 2026-09-25.
23. Neutral Core (C-29, ADR-0059): should Giving also ship a separate "Nonprofit Hub" app? Shipped: one app, "Open Impact", for both suites. Raised 2026-09-25.
24. Neutral Core names nonprofits now see: "Open Impact Settings", "Manage Open Impact Settings", "Open Impact Admin", "Open Impact Staff", "Open Impact Read Only", "Open Impact Duplicate Review". This departs from "identical labels for Core plus Giving". Acceptable? Raised 2026-09-25.
25. Rename the `Nonprofit_*` API names (`Nonprofit_Settings__c`, `Manage_Nonprofit_Settings`, the permission sets, the `Nonprofit_Hub_Home` and `Nonprofit_Settings` tabs) before the first package version; after it they are permanent. Raised 2026-09-25.
26. A Platform-only test org would not prove Core without the standard objects (ADR-0013: a Platform-only scratch org still contains them), so none was created. Both test orgs (`oi-test`, `oi-pa`) are the Person Accounts shape. Confirm the static checks plus review are enough. Raised 2026-09-25.
27. Plan corrections awaiting approval: the v0.3 row still lists "NPSP import templates" (now v0.5); Section 7.3 says CI runs four org shapes (it is one test org) and that `TestDataFactory` is `@IsTest global` (code uses `@NamespaceAccessible`, per ADR-0017); the X-07 row says 0.10 while Section 6.3 moves it to v0.6; D-14 does not cite ADR-0053 or ADR-0054; Section 4.1 still lists the Nonprofit Hub app in Core (C-29 moved it); the 2026-09-23 suites decision has no D-number; the C-25 note may be stale. Raised 2026-09-25.

### 11.3 Parking lot (good ideas, deliberately not now)

- Donor portal and online giving (license and PCI burden).
- Email marketing integration beyond export.
- Grantmaking as a funder (NPC does this well; different customer).
- Peer-to-peer fundraising.
- Wealth screening integration.
- Text-to-give.
- Multi-org or affiliate roll-up reporting.
- An "AI assistant" inside the app (the clean model is the AI strategy for v1).
- **Superseded 2026-09-23 (Brandon)** by Section 3, "Suites and packaging": the Community Suite is Core itself, made neutral by C-29, not a CI-built subset package. The earlier direction is kept for the record: A community Households edition for organizations that are not nonprofits (direction set by Brandon, 2026-09-22; not before Core's first package version). Nonprofits stay on one Core install with no extra step; Core is the primary product and is never split into a base package it depends on. The community edition is a separate unlocked package, installed from a link rather than listed as the nonprofit product, built by CI from Core's household source (a manifest names the shared files; nothing is maintained twice), with its own neutral labels. Packages start as unlocked packages with a registered namespace (Brandon, 2026-09-22), so a later move to managed keeps API names. Both editions use the same neutral namespace: several unlocked packages may share one, Salesforce recommends it, and it keeps the household objects' API names identical so conversion moves no data between objects. Whether Core can take ownership of the community edition's components in place is to be proven in a scratch org before the edition ships. One-way conversion from community to Core is a hidden or manual Setup Assistant step in Core that copies household data into Core's model, written with instructions when the edition exists; no conversion the other way.
- **Engineering follow-ups from the v0.5 and v0.6 reviews (recorded 2026-09-27, Brandon: "make sure they are detailed").** Not scheduled into an iteration; each is small enough for one PR under the usual rules (admin guide first where behavior changes, tests including a 200-row bulk case where records are touched, Code Analyzer clean). The repo copy of this list is the "Handoff: open work and what still needs testing" section of `docs/contributor-guide/ci.md`; remove an item from both when its PR merges.
  1. **Harden the settings writers and cap uncapped counts.** Why: a settings save can silently overwrite a concurrent admin's change, and Giving can switch three default-on features off the first time it saves.
     - `SettingsService.applyValues`, through `SettingsWriter.saveOrgDefault`, upserts the whole cached, unlocked `Nonprofit_Settings__c` record, so every field is written back from a possibly stale copy. Fix: update only the fields that changed, through `OrgSettingsSystemWriter` with the row read by `SettingsRecordSelector.lockStored()` (`FOR UPDATE`), per ADR-0021 and ADR-0035.
     - Giving makes raw first saves from `Giving_Settings__c.getOrgDefaults()` in `AcknowledgmentService` (about lines 426 to 435), `DonorLevelWriter` (about 26 to 33), `AccountingPeriodWriter` (line 22), `AcknowledgmentController` (line 179) and `CommitmentService` (lines 595 and 607). When no org default row exists yet, `getOrgDefaults()` returns field defaults of false, so the first save writes false into the checkboxes that ship true: `Auto_Apply_Gifts_To_Installments__c`, `Automatic_Household_Soft_Credits__c`, `Receipt_Print_Logo__c`. Fix: route every first save through the path that applies shipped defaults in Apex (ADR-0035), and add a test per writer that starts with no org default row and asserts the three checkboxes stay true.
     - `SettingsService.getSettingsForUpdate()` takes no lock despite its name; rename it (for example `getSettings`) so no caller assumes a lock, and use `lockStored()` where a lock is needed.
     - `HealthCheckSettingsChecks.countNew()` runs an uncapped `COUNT()`; cap it (`LIMIT` plus "N or more" wording) so a large error backlog cannot hit query-row limits.
  2. **Log unrecognized checkbox values in imports.** Why: today any value other than true, yes or 1 silently becomes false, so "Y", "x" or "checked" in a file clears a box with no trace. `ImportRowProcessor.convertCheckbox` (about line 2104; used by the comparison at about line 1561) changes to:
     - True: `true`, `yes`, `y`, `1`, `x`, `checked`, `on`, `t` (case-insensitive, trimmed).
     - False: `false`, `no`, `n`, `0`, `off`, `f`.
     - Blank: no change to the field.
     - Anything else: skip that field on that row and add a run-log note naming the column, row and value; the rest of the row still loads.
     - Order: admin guide import page first, then code; tests cover every accepted spelling, blank, an unrecognized value, and a 200-row bulk file.
  3. **Fix the dynamic Apex convention violations** (the conventions are in `docs/contributor-guide/dynamic-apex.md`, ADR-0013, ADR-0057, ADR-0058).
     - Bug: `HealthCheckOrgShapeChecks` (`CONNECT_MARKER_CLASS = 'ConnectService'`, line 18) looks for a class that Connect does not ship, so Health Check always reports Connect as not installed. Point it at a class Connect does ship (namespace first, then bare), add a test through the seam, and correct item 4 of `packages/core/integration/c-07-c-11.permissions.md`, which still says Connect must ship `ConnectService`.
     - Uncapped counts: `ReceiptGapSelector` (on `main`; C-29 replaces it with `ReceiptGenerationFailureSelector`, check that one instead once C-29 merges), `CampaignSyncSelector.countAppeals`, `HubErrorCountSelector.countNewErrors`, and `HealthCheckSettingsChecks.errorLogFinding` (switch to the existing `countNewUpTo`).
     - Describes inside loops: `ImportMatcher.firstNameOf`, `ImportUndoBatch.fieldMap`, and `SettingsService.hasKey` with `SettingsController.toSetting`. Hoist each describe out of the loop and cache it per transaction.
     - `HubErrorCountSelector`: add a field-level access check on `Status__c`, and resolve the object namespace first, then bare, like the other seams.
     - Extension classes of the wrong shape: `ImportEntityProcessors` and `SampleDataModules` silently ignore a class found by `Type.forName` that does not implement the expected interface; log it to the error log instead. `SampleDataModules` should also cache its lookups.
     - CI gaps: add a static check that fails on Person Account field references (`IsPersonAccount`, `PersonEmail`, `__pc` fields) outside the allowed seams; extend `scripts/ci/check-standard-objects.sh` to cover the object and field declarations inside `packages/connect`, not only Core and Giving. (The permission-set description length check was added with X-01.)
     - Tests: add a "Campaign unavailable" test seam so the Campaign-absent path is tested, not skipped; tests that return early when a feature is absent must assert both the present and the absent case.
  4. **Raise the sf CLI heap in the org test script.** Why: reading about 2,200 test results crashes the sf CLI with a JavaScript heap out-of-memory error, which the script then reports as a misleading "0 of 0 failed".
     - Export `NODE_OPTIONS=--max-old-space-size=8192` in `scripts/org/run-org-tests.sh`, and in `scripts/org/deploy-packages.sh` if a deploy shows the same crash.
     - Detect the out-of-memory signature in the CLI output and report "sf CLI crashed, rerun" rather than a test result, without posting a passing or failing `Org tests (local)` status.
     - Consider requesting a smaller result payload (for example omitting passing-test detail).
     - Update the heap paragraph in `docs/contributor-guide/ci.md`.
  5. **Smaller review follow-ups.**
     - X-01 Opportunity mirror: `OpportunityGiftService.isLinkDuplicate` checks the `DUPLICATE_VALUE` status code, but when the error names no fields it falls back to `error.getMessage().contains(<Opportunity_Id__c field name>)`, which a future field with a similar name could trip. Tighten the fallback (exact field token, or treat a field-less duplicate as not a link duplicate) and test both paths.
     - X-01 admin guide: warn against listing `Master` in the Opportunity record-type filter. It resolves to the Master record type's Id, but Opportunities without a record type carry a null value, so the run matches nothing and logs no warning. Alternatively, make the batch log a Warning when `Master` is listed.
     - C-29: optionally assert `Limits.getQueryRows()` in the receipt-cap test so the cap is proved, not only the result.

### 11.4 Decisions the builder must escalate rather than make

Adding any package dependency; adding a standard-object reference outside Connect; adding a required Setup step; changing the household membership abstraction; changing the versioning or namespace; anything touching receipt immutability or gift amount mutability.

---

## 12. Decision log (initial ADRs; copy each into `docs/architecture/decisions/`)

| ID | Decision | Alternatives rejected | Why |
|---|---|---|---|
| D-01 | Product name "Open Impact" (chosen 2026-09-06), namespace candidate `openimpact` deferred and subject to verification; fallback name OpenCause. **Name superseded 2026-09-23 (Brandon):** "Open Impact" is not available; BarnCRM is the tentative name, subject to the Section 8.3 checks; the namespace stays deferred (ADR-0046) | "Nonprofit Commons" (collides with Salesforce.org's Open Source Commons program), "Next Impact" (echoes Salesforce's "next generation of Nonprofit Cloud" language), "Barnraise" (strong metaphor, not self-explanatory), "OpenNPC" (confusable with the Salesforce product) | Self-explanatory, signals open source and purpose, no known product collision |
| D-02 | Second-generation managed packages with one shared namespace for the AppExchange listing; built and piloted as unlocked packages under the same namespace until then, following managed-package rules so the same source converts (amended 2026-09-23, Brandon, ADR-0046; production pilots move through the C-31 migration) | Unlocked packages only (no push upgrades, no AppExchange managed listing); 1GP (legacy tooling) | AppExchange listing, push upgrades, cross-package access under one namespace |
| D-03 | Core plus separate module packages for heavy domains; feature flags for minor behavior | Single package with hidden features | Principle 3: an unused module leaves no schema behind |
| D-04 | Custom `Gift__c` as the gift system of record; Opportunity and Gift Transaction as optional mirrors in Connect | Opportunity as the gift (NPSP); Gift Transaction (NPC) | Platform-license compatibility (large cost win for target customer), nonprofit semantics, no Industries dependency; mirrors preserve ecosystem compatibility |
| D-05 | Household as Account record type with two membership modes behind one service | Custom Household object; Party Relationship Groups | Standard object benefits and NPSP compatibility, while junction mode handles Person Accounts and multi-household membership |
| D-06 | Settings storage: protected hierarchy custom settings for toggles, custom objects for structured lists, custom metadata for shipped defaults materialized on install | All custom metadata (asynchronous writes, poor admin editing); all custom settings (not reportable, not versioned) | Synchronous front-end edits, upgrade-safe defaults, reportable configuration |
| D-07 | `sf` CLI plus GitHub Actions; CumulusCI optional later | CumulusCI from the start | Lower contributor barrier; revisit if multi-package orchestration becomes painful |
| D-08 | License: Apache-2.0 (confirmed by Brandon 2026-09-22) | BSD-3-Clause (NPSP precedent) | Explicit patent grant protects adopters and contributors |
| D-09 | No Person Account, Industries, OmniStudio, Data Cloud, or Experience Cloud dependency anywhere | Building on NPC primitives | Principle 4; the target customer cannot afford or administer them |
| D-10 | Receipts are immutable; corrections void and reissue; refunds are negative linked gifts | Editable amounts | Audit integrity; tax receipt correctness |
| D-11 | Rollup engine: evaluate vendoring a proven MIT-licensed Apex rollup library before building | Build from scratch first | Principle 8; correctness risk is highest in rollups |
| D-12 | Trunk-based development, squash merges, `main` always releasable | Git flow | Simplicity for a small team with AI agents |
| D-13 | Data management scope and phasing (Brandon, 2026-09-23; ADR-0047): an in-org tool with NPSP Data Importer parity, a Jetstream-style find and bulk update, and the useful dataimporter.io capabilities, the most useful in v1. Everything runs in the org with no call to Salesforce's own APIs; queries are compiled from a document and run in user mode, with no typed SOQL in v1 (C-36 later); bulk update is a journaled data job on `Import_Batch__c`, undoable through the import journal; gift import and donation matching (G-23, G-24) move to v0.5; a new v0.7 Data management iteration holds C-32 to C-35; bulk delete (C-37) and scheduled imports and connections to other systems (C-38) come after 1.0. Never built: Jetstream's metadata, Apex, permission and API tools, and dataimporter.io's org-to-org migration and backup | Leave data management to Data Loader, Jetstream and dataimporter.io; a Bulk API path through a Named Credential; typed SOQL from v1; bulk update with no undo; reusing Jetstream's code; folding C-34 and C-35 into Hardening instead of a new iteration | Maria works in labels, not API names, and needs a preview and an undo; every read and write runs with her own access and sharing; no connected app, stored token or third party holds donor data; a Lightning session cannot call the REST or Bulk API; Jetstream is Apache-2.0 with the Commons Clause, not open source, so its ideas are used and its code is not; a new iteration keeps the three-major rule and puts the tools in front of the beta cohort |
| D-14 | Cancelled status for unpaid Pending gifts (Brandon, 2026-09-24; amends G-04): a Pending gift that will never be paid is set to Cancelled, a non-money step with no negative gift, excluded from rollups, the accounting export, receipts and retention reports, and not blocked by the G-20 posting flag or period lock; Written off is kept for gifts that were Received. Built on top of G-20 in v0.6, with a new ADR amending ADR-0022 and the write-off and refund ADRs | Writing off an unpaid Pending gift as a linked negative gift; deleting unpaid Pending gifts (the admin-guide advice it replaces) | A gift that was never paid was never in the books, so it needs no reversing entry and no posting or period-lock check; deleting it loses the record |
| D-15 | Second long-lived test org (Brandon, 2026-09-24): a scratch org with Person Accounts enabled, alias `oi-pa`, kept until it expires and recreated after that, used for Person Account testing and as a backup gate org. It is the v0.5 Person Account org shape, gated locally through `scripts/org/run-org-tests.sh` | A Person Account shape in a GitHub CI matrix; Person Account testing only in short-lived scratch orgs | Org tests run locally, not in GitHub CI; Person Account orgs behave differently in subtle ways (Section 11.1), and a second gate org keeps testing possible when the main test org is unavailable |

---

## 13. Glossary (nonprofit and platform terms, for agents and contributors)

- **Appeal:** a fundraising effort (mailing, event, campaign). We avoid the word "campaign" in the UI because Salesforce's Campaign object means something specific and is unavailable on Platform licenses.
- **Commitment:** a promise to give, either a pledge (fixed total) or a recurring gift (open-ended).
- **Fund:** a designation or restriction on how money may be used (NPSP: General Accounting Unit; NPC: Gift Designation).
- **Hard credit:** the donor legally credited with a gift. **Soft credit:** recognition for influencing a gift without giving it (spouse, solicitor, honoree, matching employer relationship).
- **Household:** the unit of relationship and recognition for individual donors; one mailing, one greeting, one giving history.
- **LYBUNT / SYBUNT:** donors who gave Last Year But Unfortunately Not This year, and Some Year But Unfortunately Not This year; standard lapsed-donor lists.
- **Receipt:** the document a donor uses for tax purposes; in the US it must state the amount, date, organization, and whether goods or services were provided.
- **Restricted fund:** money a donor or funder limited to a purpose; the balance is a compliance obligation.
- **Stewardship plan:** a scheduled sequence of touches after a gift or milestone (NPSP: Engagement Plan).
- **Tribute:** a gift made in honor or in memory of someone.
- **2GP:** second-generation managed packaging. **PBO:** Partner Business Org. **Dev Hub:** the org that owns package definitions. **Push upgrade:** the publisher-initiated upgrade of installed orgs.
- **Org shape:** the license and package configuration of an org (Platform-only, Sales Cloud, NPSP, Agentforce Nonprofit) used in CI.

---

*End of document. Everything above is intended to be enough to begin. When in doubt, return to Section 1.3 and ask which principle the decision serves.*
