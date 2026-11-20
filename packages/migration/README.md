# BarnCRM Migration

## Purpose

The one-time tools that move an org into BarnCRM from another product in the same org: the
Migration Assistant, which runs Migration Kits step by step on the Import engine, and Adopt NPSP
Households and Convert Nonprofit Cloud Households, which make existing household accounts
BarnCRM households in place (ADR-0232 `0232-migration-package.md`, ADR-0197, ADR-0155,
ADR-0217). Optional: install it to migrate, and uninstall it once every migration is done and no
undo is needed. The records it moved stay. In beta.

## Depends on

- BarnCRM Core

No other module. A kit for module records (gifts, volunteers, scholarships, rollups and so on)
ships in that module with its import templates and extension class; this package finds kits as
`Migration_Kit__mdt` rows and builds an extension by name, so any mix of modules works.

## Contents

- Objects: none. Fields on Core objects: `Import_Batch__c.Migration_Journal__c` and
  `Migration_Step__c` (the run and step a data job loads), `Merge_Journal__c.Kit__c` (a run's
  kit). Runs and adoptions are Admin Journal rows (canonical model 29ZS, 29ZQ).
- Apex: `MigrationKitService` (kits, a run's view, actions, the source reader),
  `MigrationStageBatch` (stages a source into an Import Batch), `MigrationController`,
  `NpspHouseholdAdoptionService`, `NpspHouseholdAdoptionBatch` (adopt and undo),
  `NpspHouseholdAdoptionController`, `MigrationPostInstall`.
- LWC: `migrationHome` (the Migration Assistant tab), `migrationAssistant` (one kit's steps,
  verification and retire checklist), `npspHouseholdAdoption` (the NPSP and Nonprofit Cloud
  household panels).
- Custom metadata: kit `NPSP_People` with templates `NPSP_Migration_Relationships`,
  `NPSP_Migration_Affiliations` and `NPSP_Migration_Addresses` (destination records are Core's);
  Setting Definition `Migration_Assistant_Page` (Settings, Integrations).
- Permission set: `Migration_Admin` (given to BarnCRM Admin holders).
- Tab: `Migration_Assistant`. Static resource: `BarnHelp_Migration`. Labels: `Migration`.
- Catalog row: `BarnCRM_Module.Migration` (Core), beta, both editions.

## Stays in Core

`MigrationKitExtension` and `MigrationCheck` (the seam a module's kit implements),
`Migration_Kit__mdt` (the kit rows modules ship), `NpspHouseholdSource` (NPSP detection and the
Household Upkeep guard, which a running org needs after migrating; Mirror's Nonprofit Cloud
source extends it), `HouseholdWriter.saveAdoptionChanges` (the one writer that may set the
Household record type, ADR-0141), and the Integrations page, which shows Start Migration only
while this package is installed.
