# ADR-NEXT: Fewer, more inclusive roles and extra permissions

**Status:** Accepted (Brandon, 2026-11-09, plan D-191: D1, D2, D4 and D5 as proposed; D3
modified so Programs is excluded; the Bulk Update class gap fix approved)
**Date:** 2026-11-09
**Source:** Brandon, 2026-11-09: "Please simplify permissions by combining them into more
intuitive and inclusive sets." Builds on ADR-0013 (Core runs alone), ADR-0050 and ADR-0121
(license-limited permissions in optional sets), ADR-0059 (Core names no module set), ADR-0123
(neutral role names), ADR-0124 and ADR-0141 (tab and app sets follow features), ADR-0127,
ADR-0131 (module sets follow roles), ADR-0132 (Access Add-On rows), ADR-0142 (BarnCRM Admin
sees every person), plan D-34 and D-44. Amends ADR-0123, ADR-0127 decision 3, ADR-0131 and
ADR-0132 decision 4 where D1 to D4 say so. Decided in plan D-191.

## Context

### Inventory (main at 203130d9)

BarnCRM ships 55 permission sets and 5 permission set groups (60 in all) across 12 packages.
They fall into six kinds:

| Kind | Sets | Who assigns them |
|---|---|---|
| Roles (groups) | Core: `BarnCRM_Admin_Group` (BarnCRM Admin Group), `Program_Staff` (Team Member), `Volunteer_Coordinator` (Coordinator), `Read_Only` (Read Only). Giving: `Fundraising_Staff` | Admin, on the Access page or the Setup Assistant (`AccessService.ROLE_DEVELOPER_NAMES`) |
| Role building blocks | `BarnCRM_Admin`, `BarnCRM_Staff`, `BarnCRM_Read_Only` | Through the roles; every Core group holds exactly one of them |
| Automatic visibility | 6 tab sets `BarnCRM_Tab_*`, `BarnCRM_Households`, 4 app sets `BarnCRM_App_*` (11) | `TabAccessService` only (AUDIENCE map), by feature and App Navigation Style; "do not assign by hand" |
| Core extra permissions | `BarnCRM_Find_And_Export`, `BarnCRM_Bulk_Update`, `BarnCRM_Bulk_Delete`, `BarnCRM_Erase_People`, `BarnCRM_Duplicate_Review`, `BarnCRM_Metadata_Admin` (Access page, `ADD_ON_PERMISSION_SETS`); `BarnCRM_Access_Manager` (Setup only) | Admin, per person |
| Module persona sets | Admin, Staff and Read Only for Events, Forms, Funders, Giving, Logic Models, Programs and Volunteers (plus `Volunteers_Coordinator`); `Rollup_Builder_Admin`, `Rollup_Builder_User`; `Contact_Point_Sync_Admin`; `Portal_Admin` (26) | Each module's `<Module>AccessSync` (ADR-0131) gives them to holders of a role or Core set; Giving's are per person (Access Add-On rows), except Giving Staff inside Fundraising Staff (D-44) |
| Integration and feature sets | Mirror: `Campaign_Sync`, `Opportunity_Mirror`, `Gift_Transaction_Mirror`, `Accounting_Export`, `Inbound_Gift_API`, `Record_Inbound_Gift_Action`; `Forms_Public_Guest`; `Portal_Integration` (8) | Admin, per person (Mirror through Access Add-On rows; the guest and portal user sets in Setup) |

Grants, in brief (object permissions C R E D, V = View All, M = Modify All):

- `BarnCRM_Admin`: 26 objects, CREDVM on Account and Contact (ADR-0142), 245 fields, 52
  classes, 10 tabs, custom permissions Manage BarnCRM Settings, Manage BarnCRM Metadata, Find
  And Export Records, Bulk Update Records, the org connection principal, View Setup and View
  Roles. `BarnCRM_Staff`: 15 objects, CRE on Account and Contact, 148 fields (73 edit), 30
  classes. `BarnCRM_Read_Only`: 13 objects read, 99 fields, 27 classes. Read Only is a strict
  subset of Staff, and Staff of Admin.
- Each module's Read Only is a strict subset of its Staff, and Staff of its Admin. Staff
  differs from Admin mainly by Delete on the top record (event, form, grant, program record,
  logic model, gift, job) and by View All and Modify All where the module has them.
- `BarnCRM_Find_And_Export` and `BarnCRM_Metadata_Admin` are strict subsets of `BarnCRM_Admin`.
  `BarnCRM_Bulk_Update` adds to Admin only the `BulkUpdateController` and
  `BulkDeleteController` classes. `BarnCRM_Bulk_Delete` adds those classes and the Bulk Delete
  Records permission. `BarnCRM_Erase_People` adds `PersonErasureController` and Erase People.
- The three Mirror sync sets each grant one page, one class, one or two external ID fields and
  (for two) a "use" custom permission; none grants a standard object. `Inbound_Gift_API` is
  the integration user's whole set; `Record_Inbound_Gift_Action` is one class "given with
  Giving Staff".

Who checks what by name (everything else checks a custom permission, so it is untouched by
regrouping): `AccessService` (roles, Core add-ons), `TabAccessService` (AUDIENCE map),
`HealthCheckService` (roles and building blocks that mean "uses BarnCRM"), nine module
`AccessSync` classes, `VolunteersHealthCheckExtension` (the Coordinator group and set),
`TestUsers` (module admin sets), `BarnCRMShippedPermissionSets` (generated), the Access Add-On
rows, `scripts/ci/check-permission-sets.py` (optional license-limited sets), and the admin,
testing and contributor guides.

### What makes it hard to use

1. **Two roles nobody can tell apart.** Team Member and Coordinator both hold `BarnCRM_Staff`
   and nothing else. Five of the six module syncs that know them map both to the same set.
   Only Volunteers tells them apart (Volunteers Staff against Volunteers Coordinator). In a
   Standard Edition org, or any org without Volunteers, the Access page offers two roles that
   do exactly the same thing.
2. **Uneven inclusiveness.** Every module gives its Admin set to BarnCRM Admin holders except
   Giving, whose Admin set reaches only the person who turned Giving on; the rest need it by
   hand. Team Member gets the Events, Forms, Funders, Logic Models, Programs and Volunteers
   staff sets automatically, but Fundraising Staff gets only Events and Funders: a fundraiser
   cannot fill in a form or log a volunteer's hours that a Team Member can.
3. **Extra permissions that only work in pairs.** Bulk Update and Bulk Delete say "give it
   together with Find and Export"; Record Inbound Gift Action says "with Giving Staff";
   Accounting Export says "with a Giving set that reads gifts". An admin who misses the pair
   gives a permission that does nothing.
4. **Three Mirror sets for one job.** Campaign Sync, Opportunity Mirror and Gift Transaction
   Mirror are the same shape (open one page, edit one external ID); two inbound gift sets serve
   one integration. Nine module rows on the Access page for Giving and Mirror.
5. **Labels that collide in Setup.** The role "BarnCRM Admin Group" holds the set "BarnCRM
   Admin"; "Read Only" holds "BarnCRM Read Only"; eleven automatic sets sit among them with no
   sign that BarnCRM manages them.
6. **A likely gap.** `BarnCRM_Admin` grants Bulk Update Records and the Bulk Update tab but not
   `BulkUpdateController`, so a BarnCRM Admin who is not a system administrator (no class access
   from the profile) is probably refused when the page calls Apex. Not yet proven in an org.

### Constraints that stay

- ADR-0013 and ADR-0059: a Core group cannot contain a module set, and Core names no module
  set. Module sets reach roles only through the module's own access sync or the module's own
  group (as Fundraising Staff does).
- ADR-0121 and ADR-0050: Duplicate Review and Access Manager stay optional and outside every
  role, because a Salesforce Platform license refuses what they grant.
- ADR-0124 and ADR-0141: a tab disappears only when no assigned set grants it, so each tab
  or app that follows a feature or a setting keeps its own set.
- Standard Edition (Core without Giving) and Platform-only orgs keep working with Core alone.
- Packaged groups and sets cannot be renamed by API name (ADR-0123); a removed component needs
  a destructive deploy, and Salesforce refuses to delete a set or group that is still assigned.

## Decision

The model admins see becomes: **four roles, each including everything that role needs in every
installed module, plus a short list of self-sufficient extra permissions.** Sets that exist only
as plumbing are labelled as such.

### 1. Roles

| Role (label) | API name | Contains | Gets automatically from each installed module |
|---|---|---|---|
| **BarnCRM Admin** (relabelled from BarnCRM Admin Group) | `BarnCRM_Admin_Group` | BarnCRM Admin Access | Every module's Admin set, Giving Admin included (D2) |
| **Team Member** | `Program_Staff` | BarnCRM Staff Access | Every module's Staff set except Giving's |
| **Fundraising Staff** (Giving) | `Fundraising_Staff` | BarnCRM Staff Access, Giving Staff, Rollup Builder User | Everything Team Member gets except Programs Staff (D3) |
| **Read Only** | `Read_Only` | BarnCRM Read Only Access | Every module's Read Only set except Giving's |

**D1: Coordinator is retired.** Its holders become Team Members and keep Volunteers
Coordinator as a direct assignment; Volunteers Coordinator becomes an extra permission on the
Access page ("approve and correct everyone's volunteer hours"). This reverses the Coordinator
half of ADR-0123 and the Coordinator line of ADR-0127 decision 3 and ADR-0131.

Giving Read Only and Giving Staff stay per person for everyone else: donor amounts, receipts and
tax statements are the one area where the Access page's receipt table is deliberately narrower
than the role (see access.md, "Who can read a donor's receipts").

### 2. Extra permissions (Access page)

| Extra permission | Package | Change |
|---|---|---|
| BarnCRM Find and Export | Core | Unchanged |
| BarnCRM Bulk Update | Core | Includes Find and Export's grants (D5); no pair needed |
| BarnCRM Bulk Delete | Core | Includes Find and Export's grants (D5); no pair needed; keeps the warning |
| BarnCRM Erase People | Core | Unchanged; keeps the warning |
| BarnCRM Duplicate Review | Core | Unchanged (license-limited) |
| BarnCRM Metadata Admin | Core | Unchanged |
| Giving Admin, Giving Staff, Giving Read Only | Giving | Unchanged (Giving Admin is now also automatic for BarnCRM Admin) |
| **Salesforce Records Sync** (new, `Salesforce_Records_Sync`) | Mirror | Replaces Campaign Sync, Opportunity Mirror and Gift Transaction Mirror (D4) |
| **Inbound Gifts** (new, `Inbound_Gifts`) | Mirror | Replaces Inbound Gift API and Record Inbound Gift Action (D4); self-sufficient |
| Accounting Export | Mirror | Adds read on the gift, allocation and fund fields it exports (D4); no pair needed |
| **Volunteers Coordinator** | Volunteers | Newly listed (D1) |

BarnCRM Access Manager stays assigned in Setup (ADR-0121). Forms Public Guest and Portal
Builder Integration stay assigned in Setup to their one site guest or integration user.

### 3. Plumbing, relabelled only

API names stay; labels change so Setup reads clearly:

- Building blocks: "BarnCRM Admin Access", "BarnCRM Staff Access", "BarnCRM Read Only Access";
  descriptions start "Part of the X role. Give the role, not this set."
- Automatic sets: prefix "BarnCRM Auto:", for example "BarnCRM Auto: Find Tab", "BarnCRM Auto:
  Households Tab", "BarnCRM Auto: BarnCRM Console App".
- "Rollup Builder User" becomes "Rollup Builder Read Only", matching every other module.

### 4. Gap fix

`BarnCRM_Admin` gains `BulkUpdateController` class access, so the Bulk Update tab it already
shows works for an admin who is not a system administrator. (`BulkDeleteController` stays with
Bulk Delete, per D-34.)

### Old to new mapping

Before: 55 sets and 5 groups (60). After: 52 sets and 4 groups (56). What admins choose from:
roles 5 to 4, Access page extra permissions 15 to 13, "give it together with" pairs 4 to 0.

| Old | Package | New home |
|---|---|---|
| `BarnCRM_Admin_Group` | core | Same group, label BarnCRM Admin |
| `Program_Staff` (Team Member) | core | Unchanged |
| `Volunteer_Coordinator` (Coordinator) | core | **Retired**: holders get Team Member; Volunteers Coordinator stays assigned (D1) |
| `Read_Only` | core | Unchanged |
| `Fundraising_Staff` | giving | Unchanged group; gains the module staff sets Team Member gets, except Programs Staff (D3) |
| `BarnCRM_Admin` | core | Same set, label BarnCRM Admin Access; gains `BulkUpdateController` |
| `BarnCRM_Staff` | core | Same set, label BarnCRM Staff Access |
| `BarnCRM_Read_Only` | core | Same set, label BarnCRM Read Only Access |
| `BarnCRM_Tab_Data_Manager`, `_Import`, `_Find`, `_Bulk_Update`, `_Data_Hygiene`, `_Duplicate_Matching` | core | Same sets, labels "BarnCRM Auto: ... Tab" |
| `BarnCRM_Households` | core | Same set, label BarnCRM Auto: Households Tab |
| `BarnCRM_App_Standard`, `_Console`, `_Admin_Standard`, `_Admin_Console` | core | Same sets, labels "BarnCRM Auto: ... App" |
| `BarnCRM_Find_And_Export` | core | Unchanged |
| `BarnCRM_Bulk_Update` | core | Same set; includes Find and Export (D5) |
| `BarnCRM_Bulk_Delete` | core | Same set; includes Find and Export (D5) |
| `BarnCRM_Erase_People` | core | Unchanged |
| `BarnCRM_Duplicate_Review` | core | Unchanged |
| `BarnCRM_Metadata_Admin` | core | Unchanged |
| `BarnCRM_Access_Manager` | core | Unchanged |
| `Giving_Admin` | giving | Unchanged; also given to BarnCRM Admin holders by a new `GivingAccessSync` (D2) |
| `Giving_Staff`, `Giving_Read_Only` | giving | Unchanged |
| `Events_*`, `Forms_Admin`, `Forms_Staff`, `Forms_Read_Only`, `Funders_*`, `Logic_Models_*`, `Programs_*` (15) | modules | Unchanged sets; Staff sets also follow Fundraising Staff (D3), except Programs Staff, which stays per person for fundraisers |
| `Volunteers_Admin`, `Volunteers_Staff`, `Volunteers_Read_Only` | volunteers | Unchanged; Staff also follows Fundraising Staff (D3) |
| `Volunteers_Coordinator` | volunteers | Unchanged set; now an extra permission, no longer tied to a role (D1) |
| `Rollup_Builder_Admin` | rollups | Unchanged |
| `Rollup_Builder_User` | rollups | Same set, label Rollup Builder Read Only |
| `Contact_Point_Sync_Admin` | contactpoints | Unchanged |
| `Portal_Admin`, `Portal_Integration` | portal | Unchanged |
| `Forms_Public_Guest` | forms | Unchanged |
| `Campaign_Sync` | mirror | **Retired** into `Salesforce_Records_Sync` |
| `Opportunity_Mirror` | mirror | **Retired** into `Salesforce_Records_Sync` |
| `Gift_Transaction_Mirror` | mirror | **Retired** into `Salesforce_Records_Sync` |
| `Inbound_Gift_API` | mirror | **Retired** into `Inbound_Gifts` |
| `Record_Inbound_Gift_Action` | mirror | **Retired** into `Inbound_Gifts` |
| `Accounting_Export` | mirror | Same set; adds the gift reads it needs |

### Fine-grained sets kept, and why

| Set | Why it stays separate |
|---|---|
| BarnCRM Erase People | Irreversible removal of a person; opt-in by design (ADR-0110), warning on the page |
| BarnCRM Bulk Delete | Most destructive tool; opt-in, never in a role (D-34) |
| BarnCRM Bulk Update | Owner decision 2026-09-23: an org can let staff export without letting them update |
| BarnCRM Find and Export | Same decision: export of whatever the person can see is a choice per person |
| BarnCRM Metadata Admin | Changes org metadata and carries the org connection principal; the only route for a non-admin; already inside BarnCRM Admin |
| BarnCRM Duplicate Review, BarnCRM Access Manager | Salesforce Platform license refuses what they grant (ADR-0050, ADR-0121) |
| Tab, Households and app sets (11) | The only way to hide a tab or app while its feature is off or another navigation style is chosen (ADR-0124, ADR-0141) |
| Module Admin, Staff and Read Only (per module) | A Core group cannot hold a module set (ADR-0013, ADR-0059); three levels per package is the persona pattern itself |
| Volunteers Coordinator | View All and Modify All on everyone's hours (approval), more than Staff and less than Admin |
| Giving Staff and Giving Read Only for other roles | Donor amounts, receipts and the org's tax ID stay per person |
| Accounting Export | Marks gifts posted; the bookkeeper often holds nothing else |
| Inbound Gifts, Portal Builder Integration, Forms Public Guest | One integration or guest user each; a person never holds them |
| Contact Point Sync Admin | The module's only set; given to BarnCRM Admin by its sync |

No new fine-grained set is added. Data-wide access stays inside BarnCRM Admin (ADR-0142, with
a muting set as the documented opt-out), and case notes stay inside Programs Staff, because
splitting either out would take something away from people who have it today.

### Capability check

Nothing anyone can do today is lost. Every retired set or group has a successor that grants
everything it granted, and every holder receives the successor before the old assignment is
removed (Migration, below). Team Member grants exactly what Coordinator granted in Core and in
five modules; the sixth (Volunteers) keeps its Coordinator set as a direct assignment.

These change what some people can do **more**, so each was Brandon's call (decided 2026-11-09,
plan D-191):

| Id | Expansion | Who gains what |
|---|---|---|
| D1 | Retire Coordinator | Former Coordinators also get Volunteers Staff (a subset of what they hold): nothing new |
| D2 | Giving Admin follows BarnCRM Admin | Every BarnCRM Admin gets Giving Admin (gifts, funds, appeals, receipts; still no View All on gifts) |
| D3 (modified) | Fundraising Staff gets Team Member's module sets except Programs | Fundraisers get Forms, Logic Models and Volunteers staff sets (Events and Funders they already had); Programs Staff, and with it case notes, stays assigned per person |
| D4 | Mirror merges | A holder of one mirror set can open the other two pages and edit their external ID fields (each page still needs the standard object access from Setup to do anything); the flow user also gets the Inbound Gift REST class; a bookkeeper with no Giving set can read the gift fields the export already shows |
| D5 | Bulk Update and Bulk Delete include Find and Export | A holder of either without Find and Export gets Find and Export |
| Gap fix | `BulkUpdateController` in BarnCRM Admin | Restores what BarnCRM Admin already claims to give |

Outcome (Brandon, 2026-11-09, "Whatever you recommend", plan D-191): D1, D2, D4, D5 and the
gap fix are approved as proposed. D3 is approved as modified: Fundraising Staff gets every
module staff set Team Member gets except Programs Staff, so case notes do not widen to
fundraisers; a fundraiser who works a program is given Programs Staff per person on the Access
page, as today.

## Migration (expand, then contract)

Two releases, at least one deployed release apart, so no person is ever without access.

**Release N (expand).** Additive only.

1. New sets ship (`Salesforce_Records_Sync`, `Inbound_Gifts`); old sets and the Coordinator
   group stay, their descriptions saying "Retired: replaced by X; removed in the next release".
2. The Access page stops offering Coordinator (`ROLE_DEVELOPER_NAMES` drops it; a
   `RETIRED_ROLES` list keeps it readable for Health Check and migration) and lists the new
   Mirror rows and the Volunteers Coordinator row instead of the five old Mirror rows.
3. **Core** (`CorePostInstall`, and the hourly tab access check during release N): every active
   holder of `Volunteer_Coordinator` gets `Program_Staff`, through `TabAccessService`'s group
   path, never taking anything away.
4. **Volunteers**: its sync keeps the Coordinator group to Volunteers Coordinator line for
   release N, so anyone given Coordinator in Setup still gets the set; it adds the Fundraising
   Staff line (D3).
5. **Mirror** (`MirrorPostInstall.runSetup`, which also runs at each source deploy and from
   Finish Setup): every holder of any of the three sync sets gets `Salesforce_Records_Sync`,
   every holder of either inbound set gets `Inbound_Gifts`. Mirror names only its own sets.
6. **Giving** (D2): new `GivingAccessSync` (found by convention, ADR-0131) gives Giving Admin to
   holders of `BarnCRM_Admin`.
7. Forms and Logic Models syncs add Fundraising Staff to their Staff lines (D3); Events and
   Funders already have it; Programs does not add it (D3 as modified).
8. Steps 3 and 5 carry over active holders only. An inactive holder, or any assignment
   Salesforce refuses, is skipped and logged to the Error Log by name with the successor to
   give on reactivation; the post-install never fails because of it. Whether Salesforce refuses
   a set for an inactive user is still to be confirmed in a real org.

**Release N+1 (contract).**

1. Core removes every `Volunteer_Coordinator` group assignment after checking the person holds
   `Program_Staff`; Mirror removes assignments of the five retired sets after checking the
   successor. Both log any person they skip (for example a user Salesforce will not change) to
   the Error Log, and Health Check lists them.
2. The six module syncs and Health Check drop `Volunteer_Coordinator`; the Volunteers Health
   Check finding about coordinators counts holders of Volunteers Coordinator or Volunteers Admin
   instead of the group.
3. The five set files and the group file are deleted from source;
   `scripts/org/build-destructive-manifest.py <N> <N+1>` lists them in
   `destructiveChangesPost.xml`, deployed after the post-install steps (Contributor Guide, CI,
   "Release destructive manifest").
4. Inactive users: Salesforce may refuse to assign a set to an inactive user, and an assignment
   left on one blocks the delete. The contract step removes their old assignments and writes one
   Error Log row per person naming the successor, so an admin can give it on reactivation. This
   is the only case where an assignment is not carried over automatically; to verify in a
   scratch org during the build.

**Orgs.** barn-npc and mwdbdevsb get release N through the normal batch deploy (post-install
runs as `runAsSourceDeploy` and each module's `runSetup`), then N+1 with the destructive
manifest; each mwdbdevsb deploy needs Brandon's approval. Before N+1 on mwdbdevsb, Brandon
checks Setup for any user access policy naming `Volunteer_Coordinator` or a retired Mirror set
(the packaged samples name none). Scratch and gate orgs are created fresh and never hold the
old sets after N+1.

## Effects

- **Access syncs.** Three syncs (Forms, Logic Models, Volunteers) change one line each (D3) in N and drop Coordinator in N+1; one
  new `GivingAccessSync` (D2). `ModuleAccessSyncBase` and `TabAccessService` are unchanged
  apart from Core's one-time group step.
- **Tab Access Check.** Bulk Update and Bulk Delete holders already see Data Manager and Bulk
  Update. Built (PR 1): because D5 gives them Find and Export's permission, they are also added
  to the Find and Org Optimizer tab audiences, or a holder given Bulk Update alone would hold the
  Find permission with no Find tab to start a change from, and "no pair needed" would not hold.
- **TestUsers and tests.** `TestUsers` is unchanged (module admin sets stay). About 30 test
  classes name Coordinator or a retired Mirror set: the six module sync tests, TabAccessService,
  AccessService, Health Check, Volunteers Health Check, InboundGiftAccessTest and the Mirror
  controller tests. N adds tests for the two migration steps (using `@TestVisible` stand-in
  names, as Core's tests already do) and `GivingAccessSyncTest`.
- **Setup Assistant.** The access step lists roles from `ROLE_DEVELOPER_NAMES`, so it shows
  four (three without Giving) with no code change.
- **Settings console.** No setting changes; no new admin setting is needed.
- **Guides.** Admin: access.md (roles table, extra permissions tables, receipts table),
  automatic-access.md and the sample user access policies, setup-assistant.md,
  module-manager.md, mirror pages. Testing: before-you-test.md, mirror.md, volunteers pages.
  Overview, feature catalog, canonical model (Access Add-On rows), Mirror README, contributor
  tab-icons.md. Each "Applies to" line updated.
- **Label budget.** Access Add-On rows need a custom label each (ADR-0132): N removes five
  Mirror labels and adds three (two Mirror, one Volunteers); the Coordinator role sentence is
  removed. Net about minus three. Set labels and descriptions are not custom labels.
- **Apex budget.** Core about +120 lines (group migration), Mirror about +90, Giving about +40
  (new sync), Volunteers about 0. N+1 removes most of the migration code again.
- **CI.** `check-shipped-permission-sets.py --print` regenerates
  `BarnCRMShippedPermissionSets`; `check-permission-sets.py` and the Platform license check need
  no change (no license-limited grant moves). `check-core-names-no-module.py` stays green: Core
  names only its own group.

## Build plan

Each PR under about 800 changed lines, built after the current landing batch merges.

| PR | Release | Scope | Est. files | Est. lines |
|---|---|---|---|---|
| 1 Core | N | Relabels (14 sets, 1 group, 2 descriptions); Bulk Update and Bulk Delete include Find and Export; Admin gets `BulkUpdateController`; Access page drops Coordinator; group migration step plus test; Health Check retired list; access, setup assistant, automatic access guides; feature catalog; overview | 30 | 650 |
| 2 Modules | N | Volunteers Access Add-On row and label; D3 lines in three syncs plus tests; `GivingAccessSync` plus test (D2); Rollup Builder relabel; volunteers and giving guide lines | 22 | 500 |
| 3 Mirror | N | Two new sets; Accounting Export reads; Access Add-On rows swapped; migration step in `MirrorPostInstall` plus test; shipped-sets list; Mirror README; testing guide | 24 | 650 |
| 4 Contract | N+1 | Remove-old steps in Core and Mirror plus tests; drop Coordinator from six syncs, Health Check and tests; delete five sets and one group; release notes destructive step | 35 | 700 (mostly deletions) |

PRs 1 to 3 can be built in parallel (they touch different packages; PR 2 depends on nothing in
PR 1 except the relabel, which is text). If D2 or D3 is declined, PR 2 shrinks to about 200
lines. Release slots: PRs 1 to 3 in the next open release's batch, PR 4 in the batch after it
(plan Section 6.0a).

## Alternatives considered

- **One permission set group per persona per module** (for example "Events Team Member").
  Rejected: it multiplies groups instead of reducing them, and a person would need one per
  installed module.
- **Add module sets to Core's groups at run time** (`PermissionSetGroupComponent` DML), so each
  person holds one group. Rejected for now: an upgrade of a packaged group may reset its
  components, every change triggers an asynchronous group recalculation, and it is unproven
  for the managed listing (ADR-0046). Worth an org check before the namespace work.
- **Merge Find and Export and Bulk Update into one "Data Tools" set**, or put Find and Export
  in BarnCRM Staff. Rejected: reverses the 2026-09-23 owner decision and widens export to
  everyone.
- **Give Giving Read Only to the Read Only role and Giving Staff to Team Member.** Not
  recommended: the access guide promises that donor receipts and tax history stay with people
  given a Giving set.
- **Merge the tab or app sets** (for example the four Data Manager tabs into one). Rejected:
  Import must stay hidden from Find and Export holders, and the two app styles must hide
  independently; merging either shows tabs or apps people cannot use.
- **Split case notes or data-wide access into their own sets.** Rejected: it would take access
  away from Team Members and BarnCRM Admins who have it today.
- **Retire Metadata Admin into BarnCRM Admin.** Rejected: its non-admin holders would lose it
  unless made full admins.

## Consequences

- Admins choose from four roles and thirteen self-sufficient extra permissions; module sets
  follow the roles the same way in every module.
- ADR-0123's Coordinator label, ADR-0127 decision 3's Coordinator line and ADR-0131's
  Coordinator examples become history (D1 approved); ADR-0132 decision 4 gains
  Volunteers Coordinator as a per-person set and Giving Admin as both automatic and per person.
- Plan Section 5 C-06 and the Access page user stories name four roles.
- If any of D1 to D5 is declined, the rest still stands; the mapping row for a declined item
  reverts to "Unchanged".
