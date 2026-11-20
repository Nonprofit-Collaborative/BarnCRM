# ADR-NEXT: Org Optimizer With Health Check, and the Sample Data Loader, Are Optional Modules

**Status:** Proposed
**Date:** 2026-11-20
**Source:** D-215 (Brandon, 2026-11-20): "A-Moving Org Optimizer to a module with Health Check in
that module would be great B-Approved", where B is the sample data loader as a small optional
package. Core non-test Apex measured 2,201,145 characters against its 2,000,000 target. Amends
D-101's feature list (Org Optimizer and Health Check were a Core feature) and, with dated notes,
ADR-0124 (features), ADR-0086 (field utilization in Core), ADR-0103 (the Org Optimizer page)
and ADR-0106 (Health Check on Home). Builds on ADR-0017 (one namespace,
`@NamespaceAccessible`), ADR-0020 (Core never imports a module's component), ADR-0057 (seams
found by class name), ADR-0131 (module access by role) and ADR-NEXT `NEXT-migration-package.md`,
which this follows.

## Context

Org Optimizer (Data Quality, Field Utilization, Picklist Usage, Data Dictionary, AI Readiness
export, Storage, Unused Setup, Setup Changes, Report Subscriptions, Access Explorer, Field
Access Manager) and Health Check are about a tenth of Core's Apex, and the sample data loader
is a tool for scratch orgs, sandboxes and demos that no production org needs. Nothing is
released, so no upgrade path is owed. Three things decide whether they can leave Core: every
module's Health Check checks and fixes, and every module's sample set, compile against Core
today; Core's Settings, Home, Data Manager, Setup Assistant and install check reach them; and
the Org Optimizer page is also where Find and Export holders see Data Quality and where Staff
and Read Only holders read Health Check.

## Decision

1. **A new optional package, `packages/orgoptimizer` (BarnCRM Org Optimizer), in both
   editions, depending on Core only.** It holds the Org Optimizer page and every section's
   controllers and services, Access Explorer and Field Access Manager (both are Org Optimizer
   sections), and Health Check: the runner (`HealthCheckRunner`), the Core checks, the
   controller, the last run and the panel. Its tab keeps the API name `Data_Hygiene` (label
   Org Optimizer). `Org_Optimizer_Admin` goes to BarnCRM Admin holders and `Org_Optimizer` (the
   tab, Health Check to read, Data Quality) to Staff, Read Only, Find and Export, Bulk Update and
   Bulk Delete holders, through the catalog row. Health Check reads for everyone who opens the
   page; only Manage BarnCRM Settings runs a fix.
2. **The Health Check vocabulary and seams stay in Core.** `HealthCheckService` (findings,
   reports, fix scope, budgets), `HealthCheckExtension(s)`, `HealthCheckFixExtension` and
   `HealthCheckSkew` stay, so a module's checks and fixes compile against Core alone. Two new
   Core types: `HealthCheckRun` (the seam the runner implements, named in the catalog row) and
   `HealthCheckFixes` (the fix pipeline: permission, scope check, savepoint, history).
   `HealthCheckService.runInstalled()` returns null without the package, and
   `BarnInstallCheck.runHealthCheck` then reports `available` false. `extensionFindings()` runs
   only the module checks, which module tests use.
3. **The Org Optimizer feature switch goes.** Installing the package turns Org Optimizer and
   Health Check on; `FeatureSwitchService.ORG_OPTIMIZER`, its tab permission set and its row on
   the features list are removed. The nightly Setup Changes copy and the record cleanup stay in
   Core (the admin digest reads Setup Changes) and run while the package is installed
   (`ModuleDetectionService.isInstalled`). Data Manager's Org Optimizer card, Access Manager's
   Access Explorer link and the Settings links to Health Check and the Error Log show only while
   it is installed. Home's Health Check panel is the package's component, so Core's Home page
   no longer places it.
4. **A new optional package, `packages/sampledata` (BarnCRM Sample Data), in both editions,
   depending on Core only.** It holds `SampleDataLoader`, its stages, selector and controller,
   the `SampleData` and `CoreSampleData` sets, the `sampleDataManager` component on a new
   Sample Data tab, and the `Sample_Data` permission set (Admin, Staff and Read Only holders;
   loading and removing also need Manage BarnCRM Settings).
5. **The sample data framework stays in Core.** `SampleDataModules`, `SampleDataStageBatch`,
   `SampleDataRemoveBatch`, `SampleDataStages`, `SampleDataModule`, `SampleDataFile` and
   `SampleDataException` stay, because every module's sample set runs on them. A new Core seam,
   `SampleDataHost` (load, Core's removal stages, the finished notice), is implemented by the
   package's `SampleDataPackageHost` and found by its catalog row. `BarnInstallCheck.loadSampleData`
   says to install the package when it is missing. The Setup Assistant's Load Sample Data opens
   the Sample Data tab, or says how to get it; the Settings row opens the tab.
6. **What crosses the boundary is `@NamespaceAccessible`.** About 270 Core members the two
   packages and their tests read are marked, including a few test hooks made public so a
   module test can set them (`check-cross-package-visibility.py`). An `@AuraEnabled` field or
   method cannot also be `@NamespaceAccessible`, so the report, finding, link and org shape
   types the panel reads gain `@NamespaceAccessible` getters, `Report.put` and `OrgShape.put`
   set a field by name, and `FindController.rowsFor`, `FindController.saveFor` and
   `SettingsController.consoleModel` wrap the Aura methods the package calls.

## Alternatives considered

- **Keep Org Optimizer and Health Check as a Core feature (D-101).** Rejected by D-215: about
  215,000 characters of Apex every org carries, with Core over its target.
- **Leave Health Check in Core and move only Org Optimizer.** Rejected by D-215: Health Check
  runs from the Org Optimizer page and is most of its value.
- **Move Field History too.** Rejected: it is a record card and a Settings switch, not an Org
  Optimizer section, and record pages need it without the package.
- **Move the sample data framework into the Sample Data package.** Rejected: every module's
  sample set would then depend on that package.

## Consequences

- Core non-test Apex falls from 2,201,145 to 1,966,593 measured, under the 2,000,000 target;
  Org Optimizer measures 214,909 and Sample Data 29,516.
- An org without Org Optimizer has no Health Check: Settings shows no Health link, the Setup
  Checklist and install check report it unavailable, and Home has no Health Check panel. Its
  module checks still run once the package is installed.
- Labels and Help catalog entries the packages read stay in Core's files for now, because Core
  and other modules share many of them; moving the rest is a follow-up.
- Each package is a tab, a catalog row and a post-install like the Migration package.
