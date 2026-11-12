# ADR-0205: The BarnCRM Territory Management module: territories and rules as records, a batch that previews then assigns, owner routing by territory owner, round robin or capacity, and undo through Core's data jobs

**Status:** Accepted (builder decision, for Brandon to confirm)
**Date:** 2026-11-11
**Source:** plan Section 6 rows C-40 and C-40b, Section 6.0a release 1.16, D-98, D-120, D-156,
Section 1.5 (nothing paid, no services), Section 4 (Core runs on a Platform-only org), Section
9.9 (portability); builds on ADR-0013, ADR-0047 (in-org data tools), ADR-0076 (the Find query
document), ADR-0131 (module access sync), ADR-0164 (help text JSON), ADR-0166 (nightly
dispatcher) and ADR-0192 (module tabs in the BarnCRM apps).

## Context

D-98 planned an Advanced Territory Management tool; D-120 made it an optional module for both
editions, depending on Core only, with a new ADR before build. C-40 assigns people, households
and organizations to territories and owners by rules (geography, postal code, type, size), with
a preview before reassigning and undo. C-40b (D-156) adds round-robin and capacity routing of
owners inside a territory, with the same preview and undo.

Salesforce's Enterprise Territory Management (`Territory2`, `ObjectTerritory2Association`) is not
an option: it is a Sales Cloud feature, it is not on a Platform-only org, and Core and its
modules may not depend on objects outside the allowlist (ADR-0013).

## Decision

1. **Its own package, Core only, both editions.** `packages/territory`, package `BarnCRM
   Territory Management`, module key `Territory`. Core ships the catalog row
   `BarnCRM_Module.Territory` (editions `Standard;Nonprofit`, no probe object: its Setting
   Definition row names the module, #1053), so Core finds `TerritoryAccessSync`,
   `TerritoryPostInstall` and `TerritoryNightlyJobProvider` by name. No app of its own
   (ADR-0192): the Territory Management page tab joins the BarnCRM admin apps. Install leaves
   the module off, as every module, and nothing changes a record until an admin runs it.
2. **Territories are records (canonical model 29TM1 to 29TM4).** `Territory__c`: name, active,
   priority (lower first), routing (Keep Owner, Territory Owner, Round Robin, Capacity), the
   territory owner and the round-robin position. `Territory_Rule__c` (detail): what it applies to
   (People, Households or Organizations), a filter in the Find filter document (canonical model
   R-R2) edited with Core's filter builder, and a summary sentence. `Territory_Member__c`
   (detail, C-40b): a user, a capacity and whether they take new records. A record's territory
   is a lookup, `Territory__c`, which the module adds to Account (households and organizations)
   and Contact (people), so list views, reports and Find use it like any field.
3. **What a run decides.** For each kind, every record is checked against the active rules of
   active territories for that kind in priority order (then territory name); the first match
   wins. A record already in its territory is left alone, owner included. A record no rule
   matches keeps the territory it has. Kinds: people are Contacts; households are Accounts of
   Core's household record type; organizations are Accounts of the organization record type
   (`AccountKinds`), or of none. Rules compile through Core's `QueryCompiler` (ADR-0076) with
   the record Ids of the chunk added as one more condition, run in user mode, so the run
   assigns only records the person can see and edit, and no SOQL text is ever accepted.
4. **Owners (C-40b).** Keep Owner changes only the territory. Territory Owner also sets the
   owner to the territory's owner. Round Robin gives each record to the next active member in
   turn, skipping a member at capacity, and remembers its place for the next run. Capacity gives
   each record to the active member with the most room: capacity minus the territory's people,
   households and organizations they already own, counted once per run; a member with no
   capacity is never full. When every member is full the record still moves and keeps its
   owner, and the run counts it under No Room.
5. **Preview, then assign.** A run (`Territory_Run__c`) is a batch, one kind after another,
   in one of two modes. Preview changes nothing and stores counts by territory and owner and a
   sample of 50 changes. Assign writes the changes in user mode, partial success, with each
   record's before and after values in Core's import journal under one Core data job
   (`Import_Batch__c`, operation Update), so the job is listed in Data Manager's Data jobs and
   its Undo is the bulk update undo (R-BU5). The Territory Management page also undoes a run
   through `ImportUndoService`. One run at a time. At most 50 active rules per kind, so a
   chunk stays inside the query limits.
6. **Nightly assignment, shipped off.** One step of Core's dispatcher (ADR-0166),
   `TerritoryNightlyJobProvider`, 5:45 AM, switched on in Nightly Jobs: an Assign run of
   records with no territory yet, so new records join a territory overnight. Its switch ships
   off, because it changes owners.
7. **Access (ADR-0131, D-191).** `Territory_Admin` (everything, View All and Modify All on the
   module's objects, the page, edit the Territory field) to BarnCRM Admin holders;
   `Territory_Staff` (read territories, rules and members; edit the Territory field) to Team
   Member and Fundraising Staff; `Territory_Read_Only` (read, Territory field read only) to
   Read Only. Given by `TerritoryAccessSync`, never taken away.
8. **Pages are thin.** UI text comes from the module's help catalog `BarnHelp_Territory`
   (ADR-0164), no custom labels; Apex returns plain shapes in user mode; owner routing is a
   small pure function (`TerritoryRouting`) and the page's view logic a framework-free module
   (`territoryModel`, plan 9.9).

## Alternatives Considered

- **Salesforce Enterprise Territory Management.** Not on Platform-only orgs, a Sales Cloud
  license feature, and outside the standard object allowlist (ADR-0013).
- **A junction (`Territory_Assignment__c`) instead of a lookup on Account and Contact.** Allows
  a record in several territories, but every list view, report and Find query would need a join.
  One territory per record is the common need; a second assignment model can be added later.
- **Assign on save with a trigger.** Immediate, but it changes owners on every insert in an org
  that turned the module on; the nightly step covers new records with an off switch.
- **The module's own undo store.** Duplicates Core's journal and undo; the data job keeps one
  history and one Undo for every bulk change.
- **Geocoded areas (radius, polygons).** Needs an outside geocoding service; postal code,
  state, city and county rules cover most small teams. A radius rule can reuse Find's radius
  (C-69) later.

## Consequences

- Territory and owner changes made by a run are undoable for the data job undo window, from
  Data Manager or the Territory Management page.
- A run reads every person, household and organization once per kind, so a large org takes
  one batch job of a few minutes; preview and assign read the same records.
- Capacity counts records owned in the territory by its members when the run first needs the
  territory, plus what the run gives. The count reads those records, so capacity routing suits
  territories of up to about 40,000 records; a larger territory uses Round Robin.
- A person stored as a person account is checked as an account of its record type, not as a
  person; Territory Management never reads person account fields.
