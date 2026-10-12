# BarnCRM Connect

## Purpose

Adapters that bridge BarnCRM to other systems: Opportunity mirror (NPSP and Sales Cloud),
Campaign sync, Gift Transaction mirror (Agentforce Nonprofit), an inbound gift REST API, and an
accounting export. All references to Opportunity, Campaign, and Industries objects live only
here, and only behind dynamic Apex, so Connect installs cleanly where those objects do not
exist and degrades gracefully.

## First ships in

Iteration **0.6**.

## Depends on

- BarnCRM Core
- BarnCRM Giving

## Status

Built so far (iteration 0.6):

- **Inbound gift API (X-03).** `InboundGiftResource` (REST, `POST .../v1/gifts`) and
  `InboundGiftAction` (the Record Inbound Gift Flow action), both thin over
  `InboundGiftService`, which checks each gift through `InboundGiftRequest`. `InboundGift` and
  `InboundGiftResult` are the request and result.
  These four are the package's only `global` classes and are permanent (ADR-0051). Contract:
  `docs/api/inbound-gift-api.md`. Permission set: `Inbound_Gift_API`.
- **Accounting export (X-04).** See `docs/admin-guide/accounting-export.md`.
- **Campaign sync (X-02).** The `Campaign_Sync` automation on Appeal (`CampaignSyncTriggerHandler`
  over `CampaignSyncService`) copies each appeal to a Campaign before it is saved, and stores
  the link in `Appeal__c.Campaign_Id__c`, a field Connect adds to Giving's object.
  `CampaignSyncBatch` is Sync all appeals, started from the `campaignSync` page. Campaign is
  reached only through describe. Off until `Connect_Settings__c.Campaign_Sync_Enabled__c` is
  switched on. `ConnectPostInstall` creates Connect's automation switches. Permission set:
  `Campaign_Sync`. See `docs/admin-guide/campaign-sync.md` and canonical model Section 29B.
- **Opportunity mirror (X-01).** The `Opportunity_Mirror` automation on Gift
  (`OpportunityMirrorTriggerHandler` over `OpportunityMirrorService`) copies each gift to its
  Opportunity before it is saved, in Gifts to Opportunities, and stores the link in
  `Gift__c.Opportunity_Id__c`. `OpportunityMirrorBatch` is Run now and the nightly run
  (`OpportunityMirrorSchedulable`); in Opportunities to Gifts it makes gifts through
  `OpportunityGiftService`. `OpportunityMirrorReconciliation` compares a date range. All are
  started from the `opportunityMirror` page. Off until
  `Connect_Settings__c.Opportunity_Mirror_Direction__c` is chosen. Shared pieces with Campaign
  sync are in `ConnectSync`. Permission set: `Opportunity_Mirror`. See
  `docs/admin-guide/opportunity-mirror.md` and canonical model Section 29C.

## How to test it alone

Deploy Core, Giving and then Connect (`scripts/org/deploy-packages.sh` does all three), then
run the `InboundGift*Test`, `AccountingExport*Test`, `CampaignSync*Test`, `ConnectSyncTest`,
`OpportunityMirror*Test` and `ConnectPostInstallTest` classes. The Campaign sync and Opportunity
mirror tests check that nothing happens on an org without Campaign or Opportunity, and exercise
the copy where they exist.
