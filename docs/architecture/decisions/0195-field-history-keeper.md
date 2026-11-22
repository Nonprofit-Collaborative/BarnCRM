# ADR-0195: Field History Keeper captures changes in the trigger dispatcher

**Status:** Proposed (build agent, 2026-11-11; for the integrator and Brandon)
**Date:** 2026-11-11
**Source:** Plan C-68 (release 1.6, D-157: "Field History Keeper: history for chosen fields on
BarnCRM-owned objects beyond the 20-field limit, with restore"). Builds on ADR-0017
(registry-driven trigger dispatch), ADR-0024 (what Automation Control may stop), ADR-0085 (the
custom metadata manager) and ADR-0166 (the nightly run, Record Cleanup step).

## Context

Salesforce tracks at most 20 fields per object and shows 18 months; Field Audit Trail, which
goes further, is a paid Shield add-on. BarnCRM must keep history for chosen fields of its own
objects, view it on the record, restore an earlier value, keep it for a set time, ship off, and
cost nothing when off. Every BarnCRM object with automation already has one trigger that calls
`TriggerDispatcher.run(objectName)`.

## Decision

1. **Capture in the dispatcher.** `TriggerDispatcher.run(String)` hands each after update to
   `FieldHistoryService.capture` once the registered handlers have run. No new trigger, no
   registry row per object, and a module object gets history the day it has a trigger. When
   the setting is off the cost is one read of the cached settings.
2. **Offered objects are the dispatcher's.** The custom objects named in the Automation Registry
   (custom metadata, no query) less BarnCRM's logs. An object without a BarnCRM trigger cannot
   be captured, so it is not offered.
3. **Chosen fields are custom metadata** (`History_Field__mdt`, `Object.Field`), saved through
   the custom metadata manager like Merge Rules, and read with `getAll()`, so a save spends no
   query on them. Alternatives: a text setting (255 characters fits about 12 fields), or a
   configuration object (one query per save).
4. **One row per record per save** (`Field_History__c`, JSON of the changed fields), written in
   system mode with partial success; a failure is logged and never stops the save. Long text
   over 1,000 characters is cut and cannot be restored.
5. **Automation Control applies** (ADR-0024): nothing is kept while automation is paused for
   everyone or the person saving has Bypass for me. History is a convenience, not a rule.
6. **Reading follows the record**, restoring needs Manage BarnCRM Settings and runs in user mode.
7. **Retention** is a pass of the Record Cleanup step (`Field_History_Retention_Days__c`).

## Consequences

- Standard objects (Contact, Account) are not covered; Salesforce's own history serves them.
- A change made while automation is paused, or by a flow on an object without a BarnCRM
  trigger, is not kept.
- Each tracked save adds one insert (system mode) to the transaction.

## Amendment (W8 R1.34): erasure deletes the history rows

Erasing a person (ADR-0110, R-ER4) deletes every `Field_History__c` row whose `Record_Id__c` is
the person, their Individual, or any record the run deleted, updated or ended (the person's
addresses, relationships, household memberships, and the records a module's erasure extension
lists as changed, ADR-0193). A record the erasure keeps unchanged keeps its history. The rows hold
old values, so keeping them would keep what the erasure cleared. They are Core's own rows,
written in system mode, so they are read and deleted in system mode inside the erasure's
transaction (the capture is synchronous, so every row already exists), emptied from the Recycle
Bin like other deleted records, and listed as a Deleted line with a count in the preview, the
result and the Erasure record. No module dependency is added: modules appear only through the
record ids they already report.
