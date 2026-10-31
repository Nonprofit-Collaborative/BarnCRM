# ADR-NEXT: Import rows are corrected on screen, deleted by a retention choice, and never needed by undo

**Status:** Accepted (owner decision, Brandon, 2026-10-30)
**Date:** 2026-10-30
**Source:** C-49b Super Importer: import rows; canonical model R-IR4, R-IR5, R-IR8, R-IB17a

## Context

Three earlier rules shaped the staged rows of an import:

- **R-IR4** said raw values are never rewritten and a correction is made only by fixing the
  file and running it again (R-IB17, retry by file). Fixing one rejected row meant a spreadsheet
  round trip.
- **R-IR5** (D-40) kept rows for a number of days, 90 by default, 0 for ever, counted from the
  last pass, previews included. Plan Section 4.9 had earlier said rows are purged on commit
  and rejected rows kept for the undo window.
- **Undo** (R-IB9) already read only the tag on the records and the journal, but nothing
  stated that as a rule a later change must keep.

## Decision

1. **Row correction on screen (supersedes R-IR4's "fix the file only").** A rejected row can
   be edited on screen. Raw Values is still never rewritten: the corrections go to a new
   field, `Import_Row__c.Corrected_Values_JSON__c`, holding only the columns that differ, so
   the file's value and the correction are shown side by side. Retry This Row or Retry All
   Fixed Rows runs a commit pass over only those rows, through the same processing path as
   the original run (template the commit ran under, the batch's file values, matching,
   chunks, tags and journal), so the one undo covers them (R-IB17a). The row processor reads
   the corrected value in place of the raw one at its single reading point. Retry by file
   stays as it is.
2. **Retention is a choice of four (supersedes D-40's number of days and plan 4.9's purge on
   commit).** The Import setting Delete Import Rows offers Once Complete, After 30 Days
   (default), After 90 Days and Never. The nightly Import row cleanup deletes the rows of
   complete batches (Complete, Failed, Undone, Undo failed) by it. Rejected rows awaiting
   correction follow the same setting. An uncommitted preview keeps its rows at least 30 days,
   so Once Complete never removes a file between preview and commit; batches in any other
   status keep their rows.
3. **Undo never depends on staging rows and never re-inserts a copy (R-IR8).** Undo reads
   the tag, the journal and the batch only. An import's undo deletes what it created and puts
   values back on records that still exist; a bulk delete's undo undeletes from the recycle
   bin. A record no longer in the recycle bin is journaled as not restorable, never recreated.
   Tests prove an undo after the cleanup removed the rows.

## Consequences

- One more long text field on Import Row; it is empty for every row nobody corrected.
- `BarnCRM_Settings__c.Import_Row_Retention_Days__c` and its setting definition are removed
  from source. No package version exists (the namespace is deferred), so an org that had it
  keeps an unused field until it is deleted in Setup; nothing reads it.
- With Once Complete, a rejected row can be corrected only until the next nightly run.
- A corrected retry has no separate preview: the commit's own validation rejects a row it
  cannot load, with its reason, and the corrections stay for another try.
