# ADR-0091: Bulk delete runs from a Find query, as the user, and is undone by undelete

**Status:** Accepted (owner decision D-64, 2026-10-13)
**Date:** 2026-10-12
**Source:** plan Section 4.9 (Bulk update; bulk delete is [later, C-37] by owner decision
2026-09-23) and D-13; builds on ADR-0047 (data jobs), ADR-0077 (bulk update), ADR-0080 (the
protected list) and ADR-0021 (system mode only for the package's own bookkeeping)

## Context

The owner decided on 2026-09-23 that bulk delete comes after bulk update, and only with the
journal recording each deleted Id so an undo can undelete from the Recycle Bin, a hard cap per
job, and its own permission. Bulk update (ADR-0077) already has the parts a delete needs: a
query document compiled as the person, a count the person confirms, a Batch Apex job in user
mode, a journal and an undo with a once-only latch. What is left to decide is how much of that
a delete reuses, what it may never delete, how large it may be, how long it can be undone, who
may run it, and what the person is told about records Salesforce deletes with the ones chosen.

## Decision

1. **A data job, like bulk update.** A bulk delete is an `Import_Batch__c` with a new
   `Operation__c` value, Delete. Its definition (`Operation_JSON__c`) holds the query document
   and the confirmed count. A new field, `Rows_Deleted__c`, counts what it deleted, so no
   import counter is read with a second meaning. The import history and the bulk update list
   leave Delete jobs out; they are listed on their own, on the Bulk Update tab.
2. **Counted twice, and its own ceiling.** The preview and the start count as the person, as
   bulk update does. `Bulk_Delete_Run_Limit__c` defaults to 10,000 and is held between 1 and
   48,000, the most one request can count exactly. The default is lower than bulk update's
   because a delete is harder to notice and the Recycle Bin is finite: a delete larger than
   the org's Recycle Bin pushes older records out of it.
3. **Batch Apex as the person.** The job reads at most the confirmed number of records in Id
   order in user mode, re-reads each chunk with the filter, and deletes with
   `Database.delete(records, false, AccessLevel.USER_MODE)`. Each chunk journals a Deleted entry
   (object, Id, name) for each record deleted and a Failed entry for each refusal.
4. **The protected list, and only undeletable objects.** The object must pass
   `DataProtectedFields.objectRefusal` (bookkeeping, a module's protected objects, household
   membership rows, custom settings, setup objects, objects that are never loaded) and describe
   must say the person may delete it and that the platform can undelete it. An object that
   cannot come back from the Recycle Bin is refused, because its delete could not be undone.
5. **Cascade deletes are shown, not counted.** The preview names the kinds of child record the
   platform deletes with each record, from describe (child relationships marked cascade
   delete that the person may read). Counting them would take one query per relationship and
   could not include what automation deletes. The undo brings them back with their parent, so
   they need no journal entry of their own.
6. **Undo is undelete, within 15 days.** The undo uses the import undo's guards and latch and
   its own small job, `BulkDeleteUndoBatch`, one journal page a chunk. A record still in the
   Recycle Bin (read with `ALL ROWS` in system mode, by the Id the journal holds) is undeleted
   in user mode; a record no longer there is counted as purged and journaled as NotRestored; a
   record somebody already restored is left alone. The Undo Deadline is the earlier of the
   import undo window and 15 days, the Recycle Bin's retention, so the tool never offers an
   undo that cannot work.
7. **Its own permission, in no role.** `Bulk_Delete_Records` gates every action, with
   `Find_And_Export_Records` because the records come from Find. It is granted only by a new
   permission set, BarnCRM Bulk Delete, and not by BarnCRM Admin: an administrator assigns it
   on purpose to the few people who should have it.
8. **Typed confirmation of the count.** As bulk update: the person types the number of records
   the preview counted; the start refuses if more match by then.

## Alternatives considered

- **Extend `ImportUndoBatch` with a Delete pass.** Rejected: the import undo is already five
  passes over tagged records and journals, and an undelete shares none of its checks. A
  separate job of about a hundred lines, sharing the latch and status rules, is easier to
  review and cannot change how an import is undone.
- **Reuse `Rows_Updated__c` for the deleted count.** Rejected: the field's label says updated,
  and reports would read it wrongly.
- **Include `Bulk_Delete_Records` in BarnCRM Admin.** Rejected for now (an owner question): the
  owner asked for its own permission, and leaving it out of every role makes deleting in bulk
  a deliberate grant.
- **Hard delete (empty the Recycle Bin).** Rejected: it could not be undone.
- **Count child records in the preview.** Rejected: one query per cascade relationship, still
  incomplete because automation can delete more.

## Consequences

- One new picklist value, one new field, one settings key, one custom permission and one
  permission set; no new object.
- The import undo's job-running check also recognizes `BulkDeleteUndoBatch`, so a delete undo
  that is running is not shown as failed.
- A delete larger than the Recycle Bin can hold may make older deleted records unrecoverable,
  this job's included; the admin guide says so beside the run limit.
