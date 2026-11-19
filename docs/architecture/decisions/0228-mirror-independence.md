# ADR-0228: Mirror depends on Core only; the gift mirrors are part of Fundraising, with dynamic-only standard-object references; the Case status check runs hourly while Cases are open

**Status:** Accepted
**Date:** 2026-11-14
**Source:** Owner decisions 2026-11-14 on ADR-0221's open questions. N-09: "No, using nonprofit
modules should never be required". N-10: "Hourly if cases exist". N-15 (plan D-210): "Can Mirror
for Giving just be included in Giving? And I'd prefer Fundraising over Giving." Amends ADR-0013
`0013-platform-only-org-shape-verification.md` (which packages may name standard objects),
ADR-0126 `0126-rename-connect-to-mirror.md` (Mirror as one package), ADR-0194
`0194-simpler-permission-sets.md` (the Salesforce Records Sync set) and ADR-0221
`0221-projects-requests-and-issues.md` decision 7 and open questions 1 and 2. Notes D-99 (Mirror's
editions).

## Context

Mirror held two kinds of work. The gift parts (Campaign Sync, Opportunity Mirror, Gift
Transaction Mirror, Accounting Export, the Inbound Gift API, the NPSP and Nonprofit Cloud gift
migration kits and their import templates) read and write Giving's Gift, Appeal and Fund, so
Mirror depended on Core, Rollup Builder and Giving. The rest (the Case bridge to a service
provider, Nonprofit Cloud households and relationships) needs Core alone. An org that only wants
to send its Cases to a provider had to install two nonprofit modules first, which the owner
ruled out.

N-09 first moved the gift parts to a separate package, BarnCRM Mirror for Giving, depending on
Core, Rollup Builder, Giving and Mirror. The owner then asked for them to be part of Giving
itself, and for the Giving module to be called Fundraising (N-15, D-210). Nothing had been
packaged, so the intermediate package left nothing behind to migrate.

The Case status pull ran once a night at 01:40, so a requester waited up to a day to see the
provider's answer.

## Decision

### 1. Mirror is Core only; the gift mirrors are part of Fundraising

- **Mirror** (`packages/mirror`, module key `Mirror`) depends on Core only. It keeps the Case
  bridge (`CaseProviderRequests`, `CaseProviderRequestAction`, `CaseProviderRequestsHourly`,
  `Provider_Request__c` and its tab), the Nonprofit Cloud households and relationships kits and
  their two import templates, the household drift Health Check finding, and `Mirror_Settings__c`
  with only the Case request fields (`Case_Requests_Enabled__c`, `Case_Requests_Type__c`).
  Offered in both editions (Standard and Nonprofit).
- **Fundraising** (`packages/giving`, the package still named `BarnCRM Giving` in
  `sfdx-project.json`, module key `Giving`) depends on Core and Rollup Builder, never on Mirror.
  It holds every gift part listed above: their classes, pages, tabs, labels, custom permissions,
  permission sets, Automation Registry rows, Setting Definitions, the fields and list views on
  Gift, Appeal and Fund, and their help text (merged into `BarnHelp_Giving.json`).
- No duplicate module plumbing: the gift mirror switches are created by `GivingPostInstall`, the
  two nightly mirror runs are steps of `GivingNightlyJobProvider`, and the stalled-run findings
  come from `GiftMirrorHealthChecks`, which `GivingHealthCheckExtension` calls. Core's Health
  Check marker for the gift mirrors is `GivingHealthCheckExtension` and the module key `Giving`.
- The gift mirror settings (`Campaign_Sync_Enabled__c`, `Opportunity_Mirror_Direction__c`,
  `Opportunity_Mirror_Start__c`, `Opportunity_Mirror_Record_Types__c`,
  `Opportunity_Mirror_Last_Run__c`, `Opportunity_Mirror_Last_Summary__c`,
  `Gift_Transaction_Mirror_Direction__c`, `Gift_Transaction_Mirror_Start__c`,
  `Gift_Transaction_Mirror_Status__c`, `Gift_Transaction_Mirror_Last_Run__c`,
  `Gift_Transaction_Mirror_Last_Summary__c`) are fields of `Giving_Settings__c`, shown in the
  Fundraising settings section's Gift Mirrors and Exports box. Nothing was packaged, so no stored
  value moves.
- Every gift mirror stays off by default, as before.
- No capability is removed: every class, page, setting and permission moves whole.

### 2. Standard objects: dynamic only, in Fundraising's gift mirror classes (amends ADR-0013)

Mechanism 1 now allows two places to name standard objects (Opportunity, Campaign,
CampaignMember, OpportunityContactRole, Case, Lead) and the Nonprofit Cloud gift objects
(GiftTransaction, its designations and the like): Mirror, as before, and the gift mirror classes
of Fundraising. In Fundraising the rule is stricter than in Mirror, because Fundraising is the
module most orgs install and must stay installable on a Platform-only org and on any org without
Nonprofit Cloud:

- Apex names those objects only in string literals resolved through describe or dynamic SOQL:
  no SObject type, no static query, no field token, no metadata field on those objects.
- `check-standard-objects.sh` keeps `packages/giving` in its strict scan. It exempts, by path,
  only the gift mirror classes (a fixed list of class name prefixes) and only after blanking
  their comments and string literals: any name left in code fails. It treats the mirror pages,
  labels, help catalog, settings rows, tabs and permission sets as text, and checks every
  object and field file of the package with Mirror's declaration rule (no folder or reference
  naming those objects outside prose). Every other giving file, and every other package, is
  checked exactly as before.

### 3. Permission sets (amends ADR-0194)

`Salesforce_Records_Sync` (the sync pages), `Accounting_Export` and `Inbound_Gifts` are
Fundraising's, without the `Provider_Request__c` grants. Mirror ships `Provider_Requests` (read
on Provider Request and its fields, and the tab), offered on the Access page as an add-on.
Holders of Salesforce Records Sync who read Provider Requests need the new set as well; no
automatic migration is built, because an org that uses the Case bridge has a handful of such
users.

### 4. Case status check: hourly, only while Cases are open (amends ADR-0221 decision 7)

- One scheduled job, `BarnCRM Mirror: Case requests hourly` (`CaseProviderRequestsHourly`, cron
  `0 15 * * * ?`), runs at 15 minutes past each hour.
- It first runs a cheap guard: one `LIMIT 1` query for a Provider Request not yet Resolved,
  Closed or Cancelled, and one for an open Case of the chosen Type. When neither exists it does
  nothing: no queueable, no callout, no Error Log entry.
- When either exists it queues the same `CaseProviderRequests` pass the nightly step ran (send,
  then pull status).
- The Mirror step on the Nightly Jobs card keeps its switch, Run Now and summary; the summary
  says whether the hourly check is scheduled. The nightly run itself only makes sure the job is
  scheduled (`ScheduledJobSelector.ensure`, the Tab Access Check pattern): safe to re-run, a job
  on another cron under the same name is replaced, and the job removes itself when the setting
  or the step switch is off. Post-install schedules nothing.

### 5. Editions (notes D-99)

Mirror's `BarnCRM_Module__mdt` row lists Standard and Nonprofit, since it no longer needs
Fundraising. Fundraising stays Nonprofit only, as Giving was. Reversible by editing the rows.

### 6. Names

The Giving module is called BarnCRM Fundraising (short name Fundraising) in every user-visible
place: the module catalog, the settings section, the settings object label, the permission set
labels (Fundraising Admin, Fundraising Staff, Fundraising Read Only), help text, guides and the
feature catalog. API names, the `giving` folder, class names, the `Giving` developer names and
the package name in `sfdx-project.json` stay, as the Funders to Grants rename did (N-01). The
scheduled job names become `BarnCRM Fundraising Opportunity Mirror` and `BarnCRM Fundraising
Gift Transaction Mirror`, the one style every Fundraising job uses (nothing is released, so no
old name is looked for).

## Alternatives considered

- **A separate Mirror for Giving package** (N-09 as first built). Rejected by the owner: one
  more package to install and keep in step, for features that only work with Fundraising
  anyway.
- **Keep the gift mirrors in Mirror, depending on Giving.** Rejected: Mirror's Case bridge must
  not need a nonprofit module.
- **A small package for the Case bridge only**, leaving Mirror as it was (ADR-0221 open
  question 2). Rejected: Nonprofit Cloud households and relationships also need no nonprofit
  module, and the owner's rule is about Mirror as a whole.
- **Exempt all of packages/giving from the standard-object check.** Rejected: Fundraising is the
  most installed module, and a static reference anywhere in it would refuse the install on a
  Platform-only org.
- **Keep the nightly pull and add a Run Now.** Rejected by the owner's decision.
- **A schedule every 15 minutes.** Rejected: four times the scheduled job executions for little
  gain; hourly is what the owner asked for.

## Consequences

- No new package: `sfdx-project.json`, the deploy order, the module catalog and every package
  list (deploy, apex budget, help text, tests run as, OpenAPI check path, async starter
  allowlist, API surface) name only Core, Mirror and Fundraising, as before N-09.
- Apex budget: Mirror's cap is 32,100. Fundraising's cap rises from 670,400 to 868,400: 864,050
  measured with the gift mirrors, 1,655 fewer than the two packages apart (669,576 and 196,129),
  because the separate post-install, nightly provider and Health Check extension are gone.
- One label added (`Mirror_Access_AddOnProviderRequests`); the label budget rises by 1.
- An org that installs Fundraising has the gift mirror pages and settings, all off until an
  administrator turns one on, and the Access page offers their permission sets as add-ons.
