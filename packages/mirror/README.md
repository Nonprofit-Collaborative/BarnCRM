# BarnCRM Mirror

## Purpose

Adapters that bridge BarnCRM to other systems: Opportunity mirror (NPSP and Sales Cloud),
Campaign sync, Gift Transaction mirror (Nonprofit Cloud), an inbound gift REST API, and an
accounting export. All references to Opportunity, Campaign, and Industries objects live only
here, and only behind dynamic Apex, so Mirror installs cleanly where those objects do not
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
  `docs/api/inbound-gift-api.md`. Permission set: `Inbound_Gifts` (both classes and every
  record grant).
- **Accounting export (X-04).** Permission set: `Accounting_Export`, which also reads the gift,
  allocation and fund fields the file shows. See `docs/admin-guide/accounting-export.md`.
- **Access (ADR-0194, simpler permission sets, D4).** `Salesforce_Records_Sync` opens the Campaign
  sync, Opportunity mirror and Gift Transaction mirror pages; `Inbound_Gifts` is the integration
  user's set, with the Inbound Gift REST class and flow action. Both are Access Add-On rows. The
  five sets they replaced were removed at the namespaced cut-over (D-199).
- **Campaign sync (X-02).** The `Campaign_Sync` automation on Appeal (`CampaignSyncTriggerHandler`
  over `CampaignSyncService`) copies each appeal to a Campaign before it is saved, and stores
  the link in `Appeal__c.Campaign_Id__c`, a field Mirror adds to Giving's object.
  `CampaignSyncBatch` is Sync all appeals, started from the `campaignSync` page. Campaign is
  reached only through describe. Off until `Mirror_Settings__c.Campaign_Sync_Enabled__c` is
  switched on. `MirrorPostInstall` creates Mirror's automation switches. Permission set:
  `Salesforce_Records_Sync`. See `docs/admin-guide/campaign-sync.md` and canonical model Section 29B.
- **Opportunity mirror (X-01).** The `Opportunity_Mirror` automation on Gift
  (`OpportunityMirrorTriggerHandler` over `OpportunityMirrorService`) copies each gift to its
  Opportunity before it is saved, in Gifts to Opportunities, and stores the link in
  `Gift__c.Opportunity_Id__c`. `OpportunityMirrorBatch` is Run now and the nightly run
  (`OpportunityMirrorSchedulable`); in Opportunities to Gifts it makes gifts through
  `OpportunityGiftService`. `OpportunityMirrorReconciliation` compares a date range. All are
  started from the `opportunityMirror` page. Off until
  `Mirror_Settings__c.Opportunity_Mirror_Direction__c` is chosen. Shared pieces with Campaign
  sync are in `MirrorSync`. Permission set: `Salesforce_Records_Sync`. See
  `docs/admin-guide/opportunity-mirror.md` and canonical model Section 29C.
- **Gift Transaction mirror (X-07).** Copies each received gift to a Nonprofit Cloud Gift
  Transaction, with designations for funds that carry a `Gift_Designation_Id__c`, in runs only:
  `GiftTransactionMirrorBatch` is Run Now and the nightly run (`GiftTransactionMirrorSchedulable`,
  01:35), over `GiftTransactionMirrorService`. The link is `Gift__c.Gift_Transaction_Id__c`; the
  `Gift_Transaction_Mirror` automation (`GiftTransactionMirrorTriggerHandler`) only checks a
  typed link and reports deleted linked gifts. Every Nonprofit Cloud object is named only in
  `GiftTransactionMirrorSchema` and resolved through describe, so Mirror installs without
  Nonprofit Cloud and the mirror reports itself unavailable there; tests use its stand-ins.
  `GiftTransactionMirrorReconciliation` compares a date range on the `giftTransactionMirror`
  page. Off until `Mirror_Settings__c.Gift_Transaction_Mirror_Direction__c` is chosen and a
  start date is set. Permission set: `Salesforce_Records_Sync`. See
  `docs/admin-guide/gift-transaction-mirror.md` and canonical model Section 29C1.

## How to test it alone

Deploy Core, Giving and then Mirror (`scripts/org/deploy-packages.sh` does all three), then
run the `InboundGift*Test`, `AccountingExport*Test`, `CampaignSync*Test`, `MirrorSyncTest`,
`OpportunityMirror*Test` and `MirrorPostInstallTest` classes. The Campaign sync and Opportunity
mirror tests check that nothing happens on an org without Campaign or Opportunity, and exercise
the copy where they exist.
