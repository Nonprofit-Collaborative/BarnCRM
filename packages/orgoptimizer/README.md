# BarnCRM Org Optimizer

## Purpose

Org Optimizer and Health Check (ADR-0233 `0233-org-optimizer-and-sample-data-modules.md`,
D-215): the Org Optimizer page with Health Check and its fixes, Data Quality, Field
Utilization, Picklist Usage, the Data Dictionary, the AI Readiness export, Storage, Unused
Setup, Setup Changes, Report Subscriptions, Access Explorer and Field Access Manager. Optional,
in both editions: install it from Module Manager. Without it, Core runs as before and its
pages that link here hide the link.

## Depends on

- BarnCRM Core

No other module. A module's own Health Check checks and fixes stay in that module, behind
Core's `HealthCheckExtension` and `HealthCheckFixExtension` seams, and this package runs them
with its own.

## Contents

- Objects: none. Its records and settings are Core's: Setup Changes (`Setup_Change__c`), the
  saved field use counts (`Field_Utilization_Snapshot__c`), the last Health Check result, and
  the threshold and retention fields of BarnCRM Settings.
- Apex: `HealthCheckRunner` (every check, in order; Core's `HealthCheckRun` seam),
  `HealthCheckController` and `HealthCheckLastRun`, the checks (`HealthCheckAccessChecks`,
  `HealthCheckHouseholdChecks`, `HealthCheckOrgShapeChecks`, `HealthCheckSettingsChecks`,
  `OrgOptimizerObjectChecks`), the page controllers (`DataHygieneController`,
  `FieldUtilizationController`, `DataDictionaryController`, `OrgOptimizerSetupController`,
  `OrgOptimizerStorageController`, `SetupChangeController`, `ReportSubscriptions`,
  `AccessExplorerController`, `FieldAccessController`) and their services (among them
  `PicklistUsageService` and `AutomationInventoryService`), the Health Check reads
  `UserAccessSelector` and `PersonLinkOrphanSelector`, and `OrgOptimizerPostInstall`.
- LWC: `orgOptimizer` (the page), `healthCheckPanel` and the section components.
- Custom metadata: the Org Optimizer section's Setting Definitions (thresholds, retention, the
  Health and Error Log links).
- Permission sets: `Org_Optimizer_Admin` (BarnCRM Admin holders: every section) and
  `Org_Optimizer` (Staff, Read Only, Find and Export, Bulk Update and Bulk Delete holders:
  Health Check to read, and Data Quality for Find and Export Records holders).
- Tab: `Data_Hygiene` (label Org Optimizer). Labels: the files only this package reads.
- Catalog row: `BarnCRM_Module.OrgOptimizer` (Core), both editions.

## Stays in Core

The Health Check vocabulary and seams (`HealthCheckService`, `HealthCheckExtension(s)`,
`HealthCheckFixExtension`, `HealthCheckRun`, `HealthCheckFixes`, `HealthCheckSkew`), so module
checks compile against Core alone; `BarnInstallCheck.runHealthCheck`, which reports
`available` false without this package; the nightly Setup Changes copy (`SetupChangeCopyJob`,
which runs only while this package is installed) and the record cleanup of saved counts;
`OrgLimitReader` (the admin digest reads limits too); Field History (a record card and a
Settings switch, not an Org Optimizer section); the Error Log tile; the Home page's Health
Check tile (`hubHealthCheck`, shown while this package is installed) and the badge it shares
with this package's page (`healthCheckBadge`); and the Help catalog entries and labels that
Core and other modules also use.
