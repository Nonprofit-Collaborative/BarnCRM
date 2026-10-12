# ADR-0077: Bulk update runs as the user, from a Find query, and is undone by the import undo

**Status:** Accepted (builder decision)
**Date:** 2026-10-12
**Source:** plan Section 4.9 (Bulk update, C-35); builds on ADR-0047 (bulk update is a data
job) and ADR-0021 (system mode only for the package's own bookkeeping)

## Context

ADR-0047 settled that a bulk update is an `Import_Batch__c` with `Operation__c` Update,
treats the confirmed count as a ceiling, journals every change through the import journal and
is undone the way an import is. It left open how the job is checked and run, which fields it
may write, how large it may be, and how a person reaches it. The plan asks for set, clear and
copy on up to five fields, a count preview, user-mode writes and an undo, with every setting in
BarnCRM Settings and a permission of its own.

## Decision

1. **The record set is a Find query document, nothing else.** The browser sends the document
   and the changes; `QueryCompiler` compiles the document as the person (R-SQ2), and every
   field name in a change is found in describe before it is used. The document is stored on
   the job (`Operation_JSON__c`) with the changes and the confirmed count, and the job checks
   all of it again, as the person, when it starts and in every chunk.
2. **Counted twice, and a ceiling.** The preview counts in user mode and shows five records
   before and after. The start counts again and refuses when none match, more match than
   confirmed, or more than `Bulk_Update_Run_Limit__c`. A count consumes query rows, and one
   request may read just under 50,000, so the limit is held between 1 and 48,000 (default
   48,000) and a count reads at most the limit plus one. Larger changes run in parts.
3. **Always Batch Apex, as the person.** One path for every size: the job reads at most the
   confirmed number of records in Id order with `Database.getQueryLocatorWithBinds` in user
   mode, re-reads each chunk with the filter so records that no longer match are left alone,
   and saves with `Database.update(records, false, AccessLevel.USER_MODE)`. The job record and
   journal are written in system mode under ADR-0021. Progress is the batch job's own chunk
   count, read from `AsyncApexJob`.
4. **Fields from describe, and a protected list worked out at run time.** Targets are fields of
   the query's object the person may edit, of a writable type, and not on the protected list
   (canonical model R-BU4): every Rollup Definition target, household greetings and member
   count, last calculated times, the import tag and the sample data key, and objects that are
   the package's bookkeeping, custom settings or Salesforce setup objects. `BulkUpdateFields`
   holds the bulk update rules; at landing its protected list was merged into the one-object
   import's `DataProtectedFields` (C-33), so both tools refuse the same objects and fields. Core names no Giving
   object: a posted gift or issued receipt is refused by its own lock trigger and journaled as
   Failed.
5. **The import undo, widened.** `ImportUndoBatch` runs only its restore pass for an Update
   job and restores any object its journal names that describe still finds. The journal gains
   a Failed entry so each refused record and its reason is kept beside the changes.
6. **Two permissions.** `Bulk_Update_Records` gates every action, and the person must also hold
   `Find_And_Export_Records`, because the record set comes from Find. A new permission set,
   BarnCRM Bulk Update, grants the first and read access to data jobs; BarnCRM Admin has both.
7. **Reached from Find.** After a query runs, Find shows **Bulk update** to a person with both
   permissions and opens the bulk update panel with the query in hand, so no document travels
   through the URL or browser storage. The Bulk Update tab lists recent bulk updates with
   their progress and undo.

## Alternatives considered

- **Run small sets synchronously.** Faster for ten records, but two code paths and two sets of
  limits to test. Rejected: one batch path, with progress, serves every size.
- **Pass the query to a separate tab through session storage or the URL.** Rejected: storage
  is per browser and can be empty, and a long document does not fit a URL. The panel inside
  Find has the document already.
- **Bulk update only behind `Bulk_Update_Records`.** Rejected: the preview would become a way to
  query records without the Find permission.
- **A limit of 50,000.** Rejected: the count before confirmation could not tell 50,000 from
  more in one request.

## Consequences

- No new object; two fields and one settings key. The import history filters out Update jobs.
- Formulas, find and replace, and bulk delete stay later (C-37).
- The one-object import (C-33) and bulk update each carry a protected-field list until one of
  them is folded into the other.
