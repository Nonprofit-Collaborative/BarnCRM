# ADR-NEXT: Delete by file is a one-object import operation that hands its dry run to the bulk delete job

**Status:** Proposed (builder decision)
**Date:** 2026-10-13
**Source:** data tools parity review, item "delete by file"; builds on ADR-0080 (load one
object), ADR-0091 (bulk delete from a Find query with undelete) and ADR-0021 (system mode only
for the package's own bookkeeping)

## Context

Bulk delete (ADR-0091) deletes what a Find query returns. Administrators coming from other
data tools also delete from a file: an export of the records a bad load created, or a list a
partner sent of records to remove. The record IDs are in the file, not in any field a query
could filter on. Load one object (ADR-0080) already stages a file, reads a record ID column,
checks each ID in user mode in a dry run, and shows the results. The bulk delete already has
the confirm, the job, the journal and the undelete. What is left to decide is where the IDs
live while the job runs, which permission applies, and which history the job belongs to.

## Decision

1. **A fourth Load Operation, Delete by record Id.** It is offered only to a person holding
   `Bulk_Delete_Records`, and only for an object the bulk delete may delete (ADR-0091 point 4).
   Only the record ID column is read. Find access is not needed: the records come from the file.
2. **The dry run is the import's.** Each row's ID is checked as Update by record Id checks it
   (a valid ID of the object, a record the person can see, not repeated), and a row that passes
   is Matched with the record in its Resulting Record. Nothing is deleted.
3. **The commit is the bulk delete's start.** In place of Commit, the person sees the Matched
   count, the cascade kinds and the run limit, and types the count. The start turns the same
   `Import_Batch__c` into a bulk delete job (Operation Delete), with a definition that names
   the object and the confirmed count and has `"source": "file"` instead of a query.
4. **The IDs stay in the staged rows.** `BulkDeleteBatch` reads the batch's Matched rows in
   system mode (bookkeeping, ADR-0021) and reads each chunk's records again in user mode, so a
   record deleted or hidden since the dry run is counted as no longer matching. The rest of the
   job, the journal and the undo are the bulk delete's, unchanged.
5. **It is a bulk delete from the start on.** With Operation Delete it leaves the import
   history and is listed with the bulk deletes; the import undo refuses it as it refuses any
   bulk delete, and the bulk delete undo undeletes it.

## Alternatives considered

- **A file upload on the bulk delete panel.** Rejected: it would need its own parsing, staging
  and ID checks, all of which the import already has, and its own page for rejected rows.
- **The IDs in the job definition.** Rejected: 10,000 IDs do not fit the definition field, and
  the rows already hold them.
- **Commit through the import loader with a delete branch.** Rejected: the loader's save,
  journal and undo are for inserts and updates; the bulk delete job already deletes in user
  mode, chunk by chunk, with a journal its undo reads.
- **Require Find access too.** Rejected: Find guards the query, and there is none.

## Consequences

- One new picklist value on `Load_Operation__c`; no new field or object.
- `BulkDeleteBatch` has two sources of records, chosen by the definition.
- A delete by file is undone from the bulk delete history, not from the import history; the
  admin guide says so.
