# BarnCRM Fundraising

The package is `BarnCRM Giving` in `sfdx-project.json` and lives in `packages/giving`; every
user-visible place calls the module BarnCRM Fundraising (short name Fundraising, D-210). API
names, class names and developer names use `Giving`.

## Purpose

Gifts, funds and allocations, commitments (pledges and recurring gifts) and installments, soft
credits, tributes, matching gifts, appeals, acknowledgments and receipts, giving rollups and
dashboards, and gift batches. Also the gift bridges to standard Salesforce and Nonprofit Cloud
objects and outside systems (N-15, ADR-NEXT mirror independence): the Opportunity mirror,
Campaign sync, the Gift Transaction mirror, the inbound gift REST API, the accounting export
and the NPSP and Nonprofit Cloud gift migration kits.

## First ships in

Iteration **0.2**.

## Depends on

- BarnCRM Core
- BarnCRM Rollup Builder

Not on BarnCRM Mirror: Fundraising installs and runs on a Platform-only org and on an org without
Nonprofit Cloud. Nonprofit Edition.

## What is here now

Features G-01 (gifts, allocations, funds), G-04 (refunds and write-offs) and G-05 (appeals):

- **Objects:** `Gift__c`, `Gift_Allocation__c`, `Fund__c`, `Appeal__c`, plus the giving rollup
  target fields on Account and Contact and the module's settings object `Giving_Settings__c`
  (canonical model Sections 18 to 21A and 26).
- **Services:** `GiftService` (household derivation, default allocations, allocation totals,
  refunds and write-offs), the selectors that hold every query, and `GiftController` for the
  screens that come next.
- **Automation:** one trigger per object, each calling the Core dispatcher, with a handler
  registered in `Automation_Registry__mdt` so an administrator can switch it off from the
  console.

Admin guides: [gifts](../../docs/admin-guide/gifts.md),
[funds](../../docs/admin-guide/funds.md), [appeals](../../docs/admin-guide/appeals.md),
[refunds](../../docs/admin-guide/refunds.md).

Permission set entries this package still needs are listed in
[integration/g-01-g-04-g-05.permissions.md](integration/g-01-g-04-g-05.permissions.md).

## Gift mirrors and integrations

Standard objects (Opportunity, Campaign, CampaignMember, OpportunityContactRole) and Nonprofit
Cloud objects (GiftTransaction and its designations) are reached only by name through describe
and dynamic SOQL, never as an SObject type, a static query or a metadata field. Each feature is
off by default and reports itself unavailable where its object does not exist, so the package
installs where those objects do not. `scripts/ci/check-standard-objects.sh` allows these names
only in the gift mirror classes listed in it.

- **Inbound gift API (X-03).** `InboundGiftResource` (REST, `POST .../v1/gifts`) and
  `InboundGiftAction` (the Record Inbound Gift Flow action), both thin over
  `InboundGiftService`, which checks each gift through `InboundGiftRequest`. `InboundGift` and
  `InboundGiftResult` are the request and result. These four are the package's only `global`
  classes and are permanent (ADR-0051). Contract: `docs/api/inbound-gift-api.md`. Permission
  set: `Inbound_Gifts` (both classes and every record grant).
- **Accounting export (X-04).** Permission set: `Accounting_Export`, which also reads the gift,
  allocation and fund fields the file shows. See `docs/admin-guide/accounting-export.md`.
- **Access (ADR-0194).** `Salesforce_Records_Sync` opens the Campaign sync, Opportunity mirror
  and Gift Transaction mirror pages; `Inbound_Gifts` is the integration user's set. Both are
  Access Add-On rows.
- **Campaign sync (X-02).** The `Campaign_Sync` automation on Appeal (`CampaignSyncTriggerHandler`
  over `CampaignSyncService`) copies each appeal to a Campaign before it is saved, and stores the
  link in `Appeal__c.Campaign_Id__c`. `CampaignSyncBatch` is Sync all appeals, started from the
  `campaignSync` page. Off until `Giving_Settings__c.Campaign_Sync_Enabled__c` is switched on.
  See `docs/admin-guide/campaign-sync.md` and canonical model Section 29B.
- **Opportunity mirror (X-01).** The `Opportunity_Mirror` automation on Gift
  (`OpportunityMirrorTriggerHandler` over `OpportunityMirrorService`) copies each gift to its
  Opportunity before it is saved, in Gifts to Opportunities, and stores the link in
  `Gift__c.Opportunity_Id__c`. `OpportunityMirrorBatch` is Run now and the nightly run
  (`OpportunityMirrorSchedulable`); in Opportunities to Gifts it makes gifts through
  `OpportunityGiftService`. `OpportunityMirrorReconciliation` compares a date range. Off until
  `Giving_Settings__c.Opportunity_Mirror_Direction__c` is chosen. Shared pieces with Campaign
  sync are in `MirrorSync`. See `docs/admin-guide/opportunity-mirror.md` and canonical model
  Section 29C.
- **Gift Transaction mirror (X-07).** Copies each received gift to a Nonprofit Cloud Gift
  Transaction, with designations for funds that carry a `Gift_Designation_Id__c`, in runs only:
  `GiftTransactionMirrorBatch` is Run Now and the nightly run (`GiftTransactionMirrorSchedulable`,
  01:35), over `GiftTransactionMirrorService`. The link is `Gift__c.Gift_Transaction_Id__c`.
  Every Nonprofit Cloud object is named only in `GiftTransactionMirrorSchema` and resolved
  through describe; tests use its stand-ins. Off until
  `Giving_Settings__c.Gift_Transaction_Mirror_Direction__c` is chosen and a start date is set.
  See `docs/admin-guide/gift-transaction-mirror.md` and canonical model Section 29C1.
- **Gift migration kits (MIG-05).** `NpspGiftsKit` and `NpcGiftsKit` with their Migration Kit and
  Import Template Default rows. See `docs/admin-guide/migrating-from-npsp.md` and
  `docs/admin-guide/migrating-from-nonprofit-cloud.md`.
- **Nightly and Health Check.** `GivingNightlyJobProvider` adds the two mirror runs to BarnCRM
  Nightly Jobs; `GivingHealthCheckExtension` adds `GiftMirrorHealthChecks`, which reports a
  stalled run. `MirrorSettingsWriter` records each run on `Giving_Settings__c`. Help text is in
  `BarnHelp_Giving.json`.

## Post-install script

`GivingPostInstall` implements `InstallHandler`. It runs after the package is installed and
after every upgrade. Among its steps it calls `RollupService.ensureDefaultsDuringInstall`, which
creates the giving rollup definitions this package ships and leaves every definition already in
the org exactly as the administrator left it (R-R6, ADR-0029), and
`AutomationControl.ensureDefaultsDuringInstall`, which creates the Automation page's switches,
the gift mirrors' among them.

Core cannot do this on Fundraising's behalf. Core installs first, and its own post-install call
correctly skips every giving row because the objects those rows name are not in the org
yet. This package's script is the first moment both are present. It never throws: a failure
goes to the Error Log, and the Restore shipped rollups button on the Rollups page creates the
same records on demand.

## Testing it alone

```bash
npm run check:apex
sf code-analyzer run --workspace packages --rule-selector Recommended --severity-threshold 2
```

Deploy Core, Rollup Builder and then this package (`scripts/org/deploy-packages.sh`). The
Campaign sync, Opportunity mirror and Gift Transaction mirror tests check that nothing happens on
an org without Campaign, Opportunity or Nonprofit Cloud, and exercise the copy where they exist.
