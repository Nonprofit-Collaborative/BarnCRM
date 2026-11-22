# ADR-0243: Apex Cursors in Large-Volume Jobs

**Status:** Proposed
**Date:** 2026-11-22
**Source:** plan item PF-02, decision D-219 (adopt newer GA platform features now as long as
they do not hinder adoption). Builds on ADR-0240 (archive rules and big object archive) and
ADR-0202 (brand management and visibility). The Import screens already page rows through a
pagination cursor (`ImportRowSelector.openCursor`, `ImportController.getRowPage`).

## Context

Apex Cursors are GA. `Database.getCursorWithBinds(soql, binds, accessLevel)` runs a query once
and holds up to 50 million rows; `cursor.fetch(position, count)` reads any slice of it, and the
cursor can be kept in a queueable's state and used by the next link of a chain. Fetched rows
count toward the query row limit, a transaction allows only a few fetch calls, the org has a
daily allowance of cursors and cursor rows, and the platform does not hold a cursor forever.

Several BarnCRM jobs walk a large set across queueable links by re-running their query on each
link with `Id > :lastId ORDER BY Id LIMIT n`. That is correct, but the full filter runs again
for every link, and a filter that is not selective (an archive rule's filter on any field, over
up to a million records) scans the object every time.

## Decision

1. **A queueable chain that walks one fixed set uses an Apex cursor.** The first link opens it
   with the job's access mode (user mode or system mode, unchanged), ordered by `Id`; each link
   fetches the next slice and carries the cursor, the next position and the last Id fetched.
2. **Converted now:**
   - `BigObjectArchiveJob` (Core, Copy links): the archive rule's filter, which can match up to
     the 1,000,000 row cap and need not be selective, runs once per run instead of once per
     200 records. Opened in user mode, limited to the confirmed count. Ids a Copy fetched but
     did not take (its children did not fit, or the JSON budget ran out) are kept for the next
     Copy.
   - `BrandShareJob` (Core, full shares walk): every Brand Assignment with an Account or
     Contact, unbounded, in pages of 500, system mode. The cursor replaces the key-prefix floor
     Id the first page needed and ends the chain at the last page instead of one empty link
     later.
3. **Resilience:** a fetch that fails reopens the cursor once with `Id > :lastId` (what is left
   of the run, in the same order) and goes on; a second failure ends the run as any other
   failure does (the archive's run log reason, the brand job's Error Log entry).
4. **Positions, not rows returned:** rows deleted since the cursor opened come back as gaps, so
   a link advances by the count it asked for and the chain goes on while
   `position < getNumRecords()`.
5. **Not converted, and why:**
   - Batch classes (`FindExportBatch`, `DuplicateScanBatch`, `OffPlatformSendBatch`,
     `RollupFullRecalcBatch`, `BulkDeleteBatch`, `BulkDeleteUndoBatch`): a QueryLocator already
     runs the query once and holds up to 50 million rows.
   - `ArchiveErasureJob` and the other big object scans: cursors do not work on big objects
     (ADR-0240); they page by the big object's index.
   - Queue drains (`PaymentEventProcessor`, `FormPublicProcessor`, `RollupQueue`,
     `ContactPointSyncService`, `EventCheckoutJob`, `CaseProviderRequests`): they process
     pending rows and mark them done; a snapshot would miss rows that arrive mid-chain.
   - `ProjectRevenue`: its condition ("no revenue row for the month yet") must be current when
     each chunk is written, it stops at 2,000 projects (20 links), and a cursor would need the
     filter run again per chunk anyway.
   - Screen paging (`ReportingQueryService.page`, `BulkDeleteService.backupPage`,
     `PicklistUsageService`, `AccessExplorerController`, `VolunteerHoursSelector`,
     `ImportJournalService`): not jobs; each call is a separate request driven by the browser.
     A later change can move them to pagination cursors as Import did.
   - `ImportBatchSelector` trial OFFSET: one row at a time, at most 2,000 rows.
   - `ConnectorTriggers`: a sync watermark, not a walk.

## Consequences

- The archive and full brand walks run their query once; each later link costs one fetch.
- The set is fixed when the cursor opens. For the archive, a record that starts to match after
  that is not taken by this run (it is changed since the start, so it would have been left out
  and named anyway); it no longer uses up the confirmed count, so every confirmed record can be
  reached. For brand shares, an assignment added during a full walk is shared by its own
  Brand Assignment job, as before.
- Each run uses one cursor of the org's daily allowance (two if reopened).
- Contributors: `docs/contributor-guide/dynamic-apex.md`, "Walking a large record set in a job".

## Alternatives considered

- **Keep `Id > :lastId` everywhere:** correct, but re-runs a possibly non-selective filter on
  every link of a run up to a million rows.
- **A batch class for the archive:** the Copy and Settle links must alternate (no immediate big
  object call may follow ordinary DML in a transaction), which a batch cannot do.
- **No reopen on failure:** simpler, but a long archive chain would fail outright if the
  platform let the cursor go.
