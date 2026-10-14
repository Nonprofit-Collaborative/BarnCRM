# ADR-NEXT: Find's export to Files is a Batch Apex job that writes CSV parts the person owns

**Status:** Proposed (builder decision)
**Date:** 2026-10-13
**Source:** plan C-36 (server-side export, the remainder after the browser export shipped);
review finding FINDA-6 (the export row limit was enforced only in the browser); builds on
R-SQ3 (export format), Q-04 (job notifications) and ADR-0021 (system mode only for the
package's own bookkeeping)

## Context

Find's export reads pages in the browser and builds the file there. Past a few tens of
thousands of wide rows the tab runs out of memory, and the export row limit is only where the
browser stops reading: anyone with Find can keep calling the page method. Mail-house exports
of a few hundred thousand donors need a path that does not depend on the browser, and the
limit needs one path where the server holds it.

## Decision

1. **A Batch Apex job, as the person.** The job's query locator is the document's filter in Id
   order, in user mode, with `LIMIT` the Export Row Limit, so the server never reads past it.
   The document's own columns are exported; its `related` entries (child lists) are not.
2. **CSV parts in Files.** Heap cannot hold a 500,000-row file, and a `ContentVersion` cannot be
   appended to. The job keeps a text buffer between chunks and writes a new `ContentVersion`,
   owned by the person, every 50,000 rows or about 4 million characters, each with the header
   row. The format is R-SQ3's, cell for cell.
3. **No new object.** The files carry the job in their title (`<Object>-<date>-<job>-part-<n>`);
   the page polls the `AsyncApexJob` and lists the person's own files with that title. Storing
   a job record would need a new Operation value and history filters for a job that has
   nothing to undo.
4. **Told when it is over.** The finish sends the Q-04 notification, opening the first file.
5. **The limit is enforced here only.** The browser export keeps its client-side stop, and the
   guide says plainly that it is a convenience, not a control (FINDA-6, the documented option);
   counting served pages on the server would need Platform Cache or a token store.

## Alternatives considered

- **One file, assembled at the end.** Rejected: the whole file would have to fit in the heap of
  one transaction (12 MB).
- **A job record (`Import_Batch__c`, Operation Export).** Rejected for now: no undo, no rows,
  and a new picklist value every history list must filter out.
- **Enforce the browser limit with a page counter in Platform Cache.** Rejected for now: needs a
  cache partition the package does not have, and the data read is the person's own anyway.

## Consequences

- Exports use the org's file storage until the person deletes the files; the guide says so.
- A person may need to join several parts for a very large export.
- Scheduled exports and destinations stay with C-38.
