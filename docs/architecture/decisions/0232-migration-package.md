# ADR-0232: An Optional Migration Package Holds the Migration Assistant and Household Adoption

**Status:** Proposed
**Date:** 2026-11-20
**Source:** D-213 (2026-11-20), release 1.30 item S11: an optional Migration package that can be
uninstalled after migrating, to shrink Core Apex toward its 2.0M target without losing any
capability. Amends ADR-0197 (decision 1, "No separate migration package") and ADR-0155
(decision 1, adoption in Core). Builds on ADR-0017 (one namespace, `@NamespaceAccessible`),
ADR-0020 (Core never imports a module's component), ADR-0057 (seams found by class name),
ADR-0141 (the Household record type is given to nobody) and ADR-0013.

## Context

Core measured 2,255,311 characters of non-test Apex against a 2,000,000 target. The Migration
Assistant (ADR-0197) and NPSP and Nonprofit Cloud household adoption (ADR-0155, R-HA7) are
one-time tools: an org runs them while it moves into BarnCRM and never again, yet every org
carries them. Nobody uses them in production yet, so no upgrade path is owed. Three seams
decide whether they can leave Core: what a running org still needs after migrating, how a kit
whose records land in an optional module works without the new package depending on that
module, and how Core's Settings and Integrations pages find the Assistant only when it is
installed.

## Decision

1. **A new optional package, `packages/migration` (BarnCRM Migration), depending on Core only.**
   It holds `MigrationKitService`, `MigrationStageBatch`, `MigrationController`,
   `NpspHouseholdAdoptionService`, `NpspHouseholdAdoptionBatch`,
   `NpspHouseholdAdoptionController`, the `migrationHome`, `migrationAssistant` and
   `npspHouseholdAdoption` components, a Migration Assistant tab, the `Migration_Admin`
   permission set (given to BarnCRM Admin holders through the module catalog), the fields only
   a run uses (`Merge_Journal__c.Kit__c`, `Import_Batch__c.Migration_Journal__c` and
   `Migration_Step__c`), and kit `NPSP_People` with its three templates, whose destination
   records are Core's. It is beta in both editions and can be uninstalled once every migration
   is done; the records it moved stay, and the undo of runs and adoptions goes with it.
2. **What a running org needs stays in Core.** `NpspHouseholdSource` (NPSP detection, which the
   Household Upkeep guard R-HA6, Health Check and Mirror's Nonprofit Cloud source use),
   `HouseholdWriter.saveAdoptionChanges` (the one writer that may set the Household record
   type, ADR-0141), `Migration_Kit__mdt`, `MigrationKitExtension` and `MigrationCheck` (the seam
   a kit implements), Integration App's Migration Path, and the Admin Journal kinds Migration
   and Household Adoption. `HouseholdWriter`, `saveAdoptionChanges` and a few readers
   (`OrgShapeDetector.hasNpsp`, `CoexistenceService.getCurrentMode`,
   `ImportRowFilter.digestOfValues`) become `@NamespaceAccessible`; nothing outside BarnCRM's
   namespace can reach them.
3. **Kits stay in the module that owns their records.** A kit is a `Migration_Kit__mdt` row plus
   an optional extension class, found by name (ADR-0057), so the Migration package never names
   a module and works with any mix of them. `MigrationKitExtension.rows(stepKey, rows)` now
   receives the rows the Assistant read and returns them reshaped, or null for unchanged, so a
   module's kit compiles against Core alone. Module kit tests read their step definitions
   through Core's test helper `MigrationKitSteps`.
4. **Discovery through the module catalog.** `BarnCRM_Module.Migration` and a Setting
   Definition row (`Migration_Assistant_Page`, Settings, Integrations) announce the package.
   The Integrations page lists a detected product's kits, with Start Migration, only while the
   package is installed (`ModuleDetectionService`), and Start Migration navigates to the
   Migration Assistant tab with the kit in the page state (`c__kit`), since Core cannot import
   the package's component (ADR-0020). Adopt NPSP Households and Convert Nonprofit Cloud
   Households appear under Households on that tab, where their product applies, instead of on
   the General settings page.

## Alternatives considered

- **Keep everything in Core (ADR-0197 decision 1).** Rejected by D-213: about 54,500
  characters of one-time Apex in every org.
- **Move the kits into the Migration package too.** Rejected: a gift, volunteer or rollup kit's
  extension names its module's objects, so the package would depend on every module, and the
  standard-object rule (ADR-0013) keeps the Nonprofit Cloud kits in Mirror.
- **Move `NpspHouseholdSource` too.** Rejected: Household Upkeep's guard and Health Check read
  it after migration, and Mirror's Nonprofit Cloud source extends it.
- **Give the Migration package its own record type writer.** Rejected: ADR-0141 allows one
  writer of the Household record type; exposing that one method keeps it single.

## Consequences

- Core Apex falls to 2,200,764 measured; the Migration package is 56,490. Module kits shrink
  slightly, since they no longer read the source themselves.
- ADR-0155's reason for rejecting a cross-package seam into `HouseholdWriter` no longer holds
  for this one method: it is exposed inside the namespace only, and it saves only Accounts the
  caller has checked the running user can edit, as before.
- Uninstalling the package removes undo for every migration run and adoption, which the tab's
  closing note says.
- A module that ships a kit no longer needs the Migration package to compile or test; it needs
  it only to run the kit.
