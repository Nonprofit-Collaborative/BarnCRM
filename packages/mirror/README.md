# BarnCRM Mirror

## Purpose

Bridges from BarnCRM to standard Salesforce objects and other orgs that need no nonprofit
module: Cases sent to a service provider running BarnCRM Project Management, and the Nonprofit
Cloud households and relationships migration kits. References to Case and Industries objects
live only here (and, for the gift mirrors, in BarnCRM Fundraising, `packages/giving`), and only
behind dynamic Apex, so Mirror installs cleanly where those objects do not exist and degrades
gracefully.

The gift features (Opportunity mirror, Campaign sync, Gift Transaction mirror, the inbound gift
API, the accounting export and the gift migration kits) are part of **BarnCRM Fundraising**
(`packages/giving`) (N-09, N-15, ADR-NEXT mirror independence).

## First ships in

Iteration **0.6**.

## Depends on

- BarnCRM Core

No nonprofit module (owner decision 2026-11-14: "using nonprofit modules should never be
required"). Offered in both editions.

## Status

- **Cases sent to a service provider (D-201, N-10).** `CaseProviderRequests` (queueable,
  callouts to `callout:Barn_Request_Provider`) sends open Cases of the chosen Type and pulls the
  status of every open request onto `Provider_Request__c`. `CaseProviderRequestAction` is the
  flow action. `CaseProviderRequestsHourly` is the one scheduled job (`BarnCRM Mirror: Case
  requests hourly`, at 15 minutes past each hour): a `LIMIT 1` guard first, so an hour with no
  open request or Case makes no callout and no Error Log entry. The nightly step
  (`MirrorNightlyJobProvider`, 01:40) keeps it scheduled, shows whether it is, and its switch
  stops it. Off until `Mirror_Settings__c.Case_Requests_Enabled__c`. Permission set:
  `Provider_Requests` (read on the tab), an Access Add-On row. See
  `docs/admin-guide/mirror-case-requests.md` and canonical model Section 29C2.
- **Nonprofit Cloud households and relationships (X-09, MIG-02b).** `NpcHouseholdSource` (the
  conversion's source and the drift finding in `MirrorHealthCheckExtension`) and
  `NpcRelationsKit`, with the `NPC_Households` and `NPC_Relations` migration kits and their two
  import templates. See `docs/admin-guide/nonprofit-cloud-households.md`.
- **Settings.** `Mirror_Settings__c` holds the Case request settings only. The gift mirror
  settings are fields of Fundraising's `Giving_Settings__c`.
- `MirrorPostInstall` marks the module's setup as run.

## How to test it alone

Deploy Core and then Mirror (`sf project deploy start --source-dir packages/mirror`), then run
`CaseProviderRequestsTest`, `CaseProviderRequestsHourlyTest`, `NpcHouseholdSourceTest`,
`NpcRelationsKitTest` (which also covers `MirrorHealthCheckExtension`) and
`MirrorPostInstallTest`. None needs Fundraising or Rollup Builder.
