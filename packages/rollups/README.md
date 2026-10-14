# BarnCRM Rollup Builder

## Purpose

The rollup engine and the Rollup Builder: totals on households, people, organizations and
module records, calculated from definitions an administrator creates and edits in the app,
with Instantly, Every night or Both modes, a queue with retry, and a full nightly run
(ADR-0082). Moved out of Core into its own module by ADR-NEXT
(`docs/architecture/decisions/NEXT-rollup-builder-module.md`).

## Depends on

- BarnCRM Core

Giving depends on this module. Offered in both editions.

## What is here

- **Objects:** `Rollup_Definition__c`, `Rollup_Queue__c`, the `Rollup_Run_Lock__c` custom
  setting, the `Rollup_Queue_Ready__e` platform event, the `Rollup_Definition_Default__mdt`
  shipped defaults type, and `Rollup_Settings__c`, the module's own settings object, shown in
  the Rollups section of BarnCRM Settings (canonical model Sections 13, 14, 14A and 14B).
- **Engine:** `RollupService`, `RollupEngine` and the classes it plans and writes with, the
  queue and its processors, `RollupFullRecalcBatch` and `RollupScheduler`.
- **App:** `BarnCRM_Rollup_Builder` (label BarnCRM Rollup Builder) with two tabs: Rollup
  Builder, and Rollup Settings, an app page hosting Core's `settingsConsole` with its `module`
  property set to `Rollups`, so it shows only this module's settings rows.
- **Screens:** the Rollup Builder tab and app page (`rollupBuilder`, `rollupDefinitions`,
  `rollupWizard`, `rollupFilterBuilder`, `rollupNeedsAttention`) and the Recalculate rollups
  Flow action and template.
- **Seams into Core:** `RollupsEngineExtension` (Core's `RollupEngineExtension`, which Core's
  saves and merges call), `RollupsHealthCheckExtension` (the rollup Health Check findings and
  the Restore shipped rollups fix) and `RollupsNightlyJobProvider` (the nightly job). Core
  finds each by name and does nothing when the module is not installed. Core names no class
  of this module; `scripts/ci/check-core-names-no-module.py` enforces it.
- **Permission sets:** `Rollup_Builder_Admin` and `Rollup_Builder_User`. The integration
  note is [integration/c-13.permissions.md](integration/c-13.permissions.md).

Admin guide: [rollups](../../docs/admin-guide/rollups.md).

## Post-install script

`RollupsPostInstall` implements `InstallHandler`. At install and every upgrade it creates
the shipped Rollup Definitions the org does not have yet, leaving every existing definition
as the administrator left it (R-R6, ADR-0029), creates the Automation page switch rows for
the module's automations, and queues a job that gives the installer `Rollup_Builder_Admin`.
It never throws; failures go to the Error Log. Giving makes the same defaults call from
`GivingPostInstall` for its own rows.

Once package versions exist, `sfdx-project.json` names it for this package directory:

```json
"postInstallScript": "RollupsPostInstall"
```

That line is not there yet, because no package version has been created (the namespace is
deferred, plan Section 4.3).

## Testing it alone

Deploy Core, then this module (`scripts/org/deploy-packages.sh` does both in order). Apex
tests run as `TestUsers.adminWith('Rollup_Builder_Admin')`.
