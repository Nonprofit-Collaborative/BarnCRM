# ADR-NEXT: The Migration Assistant Runs In-Org Migration Kits on the Import Engine

**Status:** Proposed
**Date:** 2026-11-11
**Source:** release 1.4 items MIG-01 (Migration Assistant framework), MIG-10 (Integrations page:
detected apps, compatibility notes and migration links) and MIG-08 (rollup migration: DLRS and
NPSP customizable rollups into Rollup Builder); plan Section 6.1.4 items 1, 8 and 10, Section
11.2 item 32 (O-1, O-8, O-9), D-125, D-124. Builds on ADR-0013 (Core runs on a Platform-only
org), ADR-0057 (extension seams found by class name), ADR-0062 (Core names other products only
when it detects them), ADR-0136 (Rollup Builder DLRS parity), ADR-0149 (undo restores from the
Recycle Bin, D-153) and ADR-0155 (NPSP household adoption in place).

## Context

Most migration sources (NPSP, V4S, PMM, Outbound Funds, Nonprofit Cloud) live in the same org
as BarnCRM (plan 6.1.4, key finding). Today an administrator moves their data by exporting a
file from the old app and loading it back with Super Importer, one object at a time, in the
right order, with no record of which steps are done and nothing that tells them what of the
old app is still running. Section 6.1.4 ranks a Migration Assistant first: an in-org source for
Import, ordered multi-step runs, verification and a retire checklist. Seven later items plug
into it (MIG-02 NPC party relationship groups, MIG-04 NPC gifts, MIG-05 NPSP kit, MIG-09 PMM,
MIG-07 off-Salesforce templates, MIG-03 V4S, MIG-11 Outbound Funds), so the seam matters more
than the first kit.

Three of the review's open questions bear on this (Section 11.2 item 32): O-1 where migrations
live, O-8 whether the Integrations page lists detected apps with migration links, and O-9 how
an app is detected. They were deferred until after Core QA; release 1.4 schedules MIG-01, so a
reversible answer is needed now. Each decision below takes the review's recommended option.

## Decision

1. **Where it lives (O-1, recommended option).** The framework is Core data tooling, beside
   Super Importer. A *migration kit* ships in the module that owns the destination records (or
   in Mirror when the source is a standard object such as Opportunity or Gift Transaction, the
   standard-object rule), as a `Migration_Kit__mdt` row plus, when it needs one, an Apex class
   implementing Core's `MigrationKitExtension`. No separate migration package. A kit row exists
   only when its package is installed, so Core never offers a kit for a module the org lacks.
2. **Detection by describe only (O-9, recommended option).** A kit names the Integration App
   row of the product it migrates from (`Source_App__c`). It is offered only when that row's
   Detection Objects are in the org's describe, the check the Integrations page already makes.
   `PackageLicense` is not read: an app installed from source or unpacked still counts.
3. **A kit is ordered steps in JSON.** `Steps_JSON__c` holds the steps in run order. Two kinds:
   - `import`: an in-org source for the Import engine. The step names a source object and its
     fields (namespaced names written `namespace.Name__c`, as Integration App rows do, resolved
     through describe at run time), an optional filter of field equals value conditions, and a
     shipped Import Template by key. The fields are read with user-mode dynamic SOQL in Batch
     Apex, and each record becomes one staged row whose columns are the field names as the step
     writes them. The template maps those columns like any file's, so a kit adds a template and
     no loader. The kit's extension may reshape rows (one source record to several rows, or
     none). A filter may be `notEquals`. A step's `links` name columns holding the Id of a
     source record an earlier step moved; staging swaps in the BarnCRM record that step's load
     made, found through the Row Key of the earlier template's one row per `Id` (R-IT18), so a
     chain such as program, service, enrollment keeps its links with no new field on any
     BarnCRM object (added with MIG-05 and MIG-09, release 1.9).
   - `tool`: a step done in another BarnCRM tool (Rollup Builder's Import From DLRS, Adopt NPSP
     Households). The Assistant opens the tool's tab and the administrator marks the step done.
   JSON keeps a kit portable (plan 9.9) and lets a kit change without code.
4. **The Import engine does the loading.** An import step creates one Import Batch, linked to
   the run and step, with Expected Count set to the source count (the control total, R-IB10)
   unless the kit's extension may reshape rows, so a commit is refused if staging fell short.
   A step whose source has no records is done at once, with no batch. The dry run starts by itself once staging
   ends. Commit, Try the First Rows, results, row correction and retry, and undo are the Import
   engine's own, unchanged (R-IB1 to R-IB17, D-152, D-153). Nothing else writes records.
5. **Order both ways.** A step can start only when every earlier step is done: an import step's
   batch Complete, a tool step marked done. Undo goes backwards: only the latest done import
   step offers Undo, through the Import engine's undo, because later steps may point at the
   records it made. An undone step can be run again.
6. **Verification.** For each import step the Assistant shows the source count now, the rows
   staged, the rows committed (created, updated or matched) and the rows rejected, and says
   Verified only when all of the first three agree and none was rejected. A kit's extension may
   add its own check (for a tool step, the only one), returning a source count and a done count.
7. **Retire checklist.** A kit ships the old app's automations to switch off, as text items
   (`Retire_Checklist_JSON__c`); the administrator ticks them. BarnCRM never switches off,
   changes or uninstalls the other app (the rule R-R16 already sets for DLRS). A run is
   Complete when every step is done and every item ticked; Complete can be reopened.
8. **One run record per kit.** `Migration_Run__c` holds the kit key, status and a JSON state
   (tool steps done, checklist ticks). Import steps are found through the Import Batches that
   point at the run (`Import_Batch__c.Migration_Run__c`, `Migration_Step__c`). Private, granted
   only to BarnCRM Admin, written in user mode.
9. **Integrations page (MIG-10, O-8).** Detected apps, compatibility notes and migration links:
   the page keeps its catalog and detection, adds the products the brief and the review name
   that it lacked (NPSP and Nonprofit Cloud Fundraising, both shown only when installed), and,
   for a detected product with a kit, shows Start Migration to people who may manage settings.
   Start Migration opens the Assistant in place on the same page. A listing's status stays In
   Progress: a migration path is not an integration. A product whose records land in several
   modules (NPSP) has one kit per receiving module, and its listing shows one button per kit.
10. **No new setting.** The Assistant changes no existing behavior, appears only when a kit's
    source is detected, and does nothing until an administrator starts a step. Every step needs
    Manage BarnCRM Settings and the Import permission the Import engine already checks.
11. **Rollup migration (MIG-08).** Rollup Builder ships two kits, DLRS and NPSP Customizable
    Rollups, each one tool step on the Rollup Builder tab. NPSP's customizable rollups are read
    by describe from NPSP's own custom metadata types Rollup and Filter Rule (namespace `npsp`,
    names built at run time) in system mode, read only, and mapped into the same
    definition shape the DLRS import uses, so the existing wizard copies them switched off,
    compares them on sample records and turns each on with the administrator's word that she
    will deactivate the NPSP one. What Rollup Builder cannot express stays in NPSP with the
    reason: soft credit, contact role and payment paths, fiscal years, Years Donated, Donor
    Streak, Best Year, more than one year back, and filter rules on another object. The
    same-field guard (R-R16) covers active NPSP customizable rollups as it covers DLRS.

## Consequences

- A later kit is a `Migration_Kit__mdt` row, one shipped Import Template per import step and,
  only when rows need reshaping or a step needs its own check, one small extension class. The
  admin guide page Migration Assistant documents the seam for contributors.
- Core never names another product's object or field in code; kit rows hold names as data.
- An org without any detected source sees nothing new except the two new Integration App rows
  when NPSP or Nonprofit Cloud is present.
- Staging reads the whole source in the running administrator's access: records she cannot
  see are not migrated, and the verification count says so.

## Alternatives Considered

- **A separate migration package (O-1 option 2).** Rejected: it would duplicate the Import
  engine's loader and undo, or depend on every module.
- **`PackageLicense` detection (O-9 option 2).** Rejected: misses source installs; describe
  already answers the only question asked.
- **Kits as Apex only.** Rejected: JSON steps keep kits portable and readable; Apex stays the
  exception through the extension.
- **A Migration Assistant tab.** Rejected for now: a tab needs its own tab permission set and
  app entries; the Integrations page is where a detected app is already shown. Easy to add.
