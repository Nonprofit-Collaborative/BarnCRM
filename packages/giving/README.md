# BarnCRM Giving

## Purpose

Gifts, funds and allocations, commitments (pledges and recurring gifts) and installments, soft
credits, tributes, matching gifts, appeals, acknowledgments and receipts, giving rollups and
dashboards, and gift batches.

## First ships in

Iteration **0.2**.

## Depends on

- BarnCRM Core

## What is here now

Features G-01 (gifts, allocations, funds), G-04 (refunds and write-offs) and G-05 (appeals):

- **Objects:** `Gift__c`, `Gift_Allocation__c`, `Fund__c`, `Appeal__c`, plus the giving rollup
  target fields on Account and Contact and the Giving module's settings object
  `Giving_Settings__c` (canonical model Sections 18 to 21A and 26).
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

## Post-install script

`GivingPostInstall` implements `InstallHandler`. It runs after the Giving package is
installed and after every upgrade, and it does one thing: call
`RollupService.ensureDefaultsDuringInstall`, which creates the giving rollup definitions
this package ships (44 `Rollup_Definition_Default__mdt` rows) and leaves every definition
already in the org exactly as the administrator left it (R-R6, ADR-0029).

Core cannot do this on Giving's behalf. Core installs first, and its own post-install call
correctly skips every giving row because the objects those rows name are not in the org
yet. Giving's script is the first moment both are present. It never throws: a failure goes
to the Error Log, and the Restore shipped rollups button on the Rollups page creates the
same records on demand.

Once package versions exist, `sfdx-project.json` names it for the Giving package
directory, as Core's README describes for `CorePostInstall`:

```json
"postInstallScript": "GivingPostInstall"
```

That line is not in `sfdx-project.json` yet, because no package version has been created
(the namespace is deferred, plan Section 4.3). Whoever creates the first Giving package
version adds it.

## Testing it alone

```bash
npm run check:apex
sf code-analyzer run --workspace packages --rule-selector Recommended --severity-threshold 2
```
