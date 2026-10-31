# ADR-0111: Load one object loads related records from the same file, keyed by the record key

**Status:** Superseded by `NEXT-several-objects-in-one-upload.md` (owner decision D-154,
2026-10-30): the load engine runs in steps, and a template with a Related Object is two of them
under the rules below; the wizard offers Several Objects in One File for new templates.
Previously: Proposed (builder decision)
**Date:** 2026-10-13
**Source:** data tools parity item 17 ("Generic parent and child in one file", owner approved
2026-10-13). Extends ADR-0080 (`0080-import-load-one-object.md`) and canonical model R-IT12 to
R-IT14; adds R-IT17.

## Context

A file from another system often holds two objects in one: programs and their sessions,
events and their attendees. Load one object loads one object per row, and a row naming a
record an earlier row named is rejected as a repeat. Other data tools load both in one job: a
parent key column groups the rows, parents are loaded first, the children of a failed parent
are marked as failed, and one rollback removes both. Core may not add a framework for this,
and must keep the existing batch, chunking, matcher, journal and undo.

The hard parts are across the chunk boundary: a parent and its children may fall in
different chunks, a dry run saves nothing, so a later chunk cannot read a parent's ID, and a
parent can fail after its rows were split.

## Decision

1. **Configuration.** A one-object template gains Related Object and Related Parent Field (the
   related object's lookup or master-detail to the target object). Related columns map to
   `Related.<field>` and go through the same plan, value reading, lookups and access checks as
   `Record` columns. Related records are always inserted.
2. **The parent key is the record key.** Under Upsert by external ID or Update by a matching
   field, the Load Match Field; under Update by record Id, the ID. Insert is refused with
   related records: a key no field holds cannot find its parent again in a later chunk, on a
   retry or a second run, nor an existing parent.
3. **Dedupe.** The first row of a pass with a key is the parent row; later rows with the key
   add a related record and their `Record` columns are not loaded. The parent row writes a
   digest of the key to its Processor Key: one prefix when the parent was saved (or would be,
   in a dry run), another when it failed. A later chunk reads both forms with the existing
   digest query, so its rows know without a parent ID whether the parent row succeeded.
4. **Order.** In each chunk, parents are matched and saved first, then related records with the
   parent ID set. A parent row is always the earliest row of its key. A later chunk's row finds
   its parent in user mode by the key (`findBy`, under Several Matches), in the commit only;
   a dry run needs no ID.
5. **Partial failure.** A related row of a failed parent is rejected "parent failed". A failed
   related record rejects its own row and the parent stays: the row is retried by loading it
   again, which finds the parent by its key. A chunk that dies rolls back both and leaves no
   digest, so a later row of that key becomes the parent row and finds or creates it by key.
6. **Results.** Status is the parent's outcome; a new Related Status says what the related
   record did; the related record's ID goes in the existing Second Resulting Record. The run
   log counts related records created and rejected, read from the rows at finish.
7. **Undo.** Related records are journaled on Created pages written after the chunk's parent
   pages; the Created pass reads newest first, so related records are deleted before their
   parents. The gained-since check already ignores children the committer made during the
   commit, so a parent is not kept for its own imported children.

## Alternatives considered

- **Two passes over the file (all parents, then all children).** Cleanest ordering, but it
  changes the batch runner, run status and pass numbering that the trial run and retry work
  also change, and doubles the run time. The earliest-row rule gives the same order per key.
- **Carrying a key to ID map in the batch's state.** Grows with the file, is lost by a chunk
  that dies, and changes `ImportProcessorBatch`. The row digests already survive chunks.
- **Insert with a file-only key.** Matches the other tools, but a retry or second run creates
  every parent again, and nothing can find an earlier chunk's parent in the commit.

## Consequences

- Rows of one parent are counted once as the parent's outcome and then as Matched; the run log
  carries the related counts. Mitigation: the admin guide says so.
- Related records are never matched, so a second run of the same file adds them again.
  Mitigation: the guide says to load only fixed rows; an upsert of related records can be added
  later with its own key.
- One extra aggregate query when an import finishes.
