# ADR-NEXT: Import undo judges edits before it deletes, and a rollup's save is not an edit

**Status:** Accepted (builder decision)
**Date:** 2026-10-14
**Source:** canonical model R-IB9; 25,000 row gift import scale test on `oi-test` (person
accounts, 8,333 new people)

## Context

Undo keeps a tagged record somebody edited since the import (R-IB9). It reads the record's
`LastModifiedDate` and `LastModifiedById` at the moment its delete pass reaches it, and counts
a save as the undo's own only when the person undoing made it.

The scale test undid a batch that created people and gifts. The gift pass runs first, and
deleting the gifts set off the donors' rollups. The Rollup Queue saved those totals, started by
its platform event as the Automated Process user. When the people pass reached the donors,
7,229 of 8,333 had last been saved by somebody other than the person undoing, and were kept as
"somebody changed this record after the import". The same happens to the import's own rollups
whenever the queue runs them as Automated Process rather than as the committer.

Field history is not available to tell which fields a save changed. Treating every Automated
Process save as safe would hide edits made by flows and integrations that run as that user.

## Decision

1. **A rollup the import set off is not an edit, whoever ran it.** Every rollup save writes
   `Rollups_Last_Calculated__c` (canonical model, freshness stamp) in the same save as its
   totals, stamped just before the save. A record whose `LastModifiedDate` falls within five
   seconds after its stamp was last saved by a rollup. Any later save of another kind leaves the
   stamp behind it. The stamp is read by its name through describe, so Core names no module.
   Such a save is the import's own when the stamp is no later than sixty minutes after the
   commit completed (the import's follow-on work; other saves keep the ten minute window). A
   later rollup save (a nightly run, a total that
   depends on the date) may hide a real edit, so it keeps the record. `RollupWriter` writes the
   stamp whenever the field exists and is not calculated, never by the running user's access:
   the queue runs as the Automated Process user.
2. **Edits are judged before anything is put back or deleted.** A rollup's save, or the undo's
   own (a household renamed), replaces `LastModifiedDate`, which would hide an edit made before
   it. The undo of an import starts with one judging pass per delete pass, in the same order,
   before the restore pass; the job carries the records found edited to the delete passes. While
   judging, the undo has changed nothing, so no save is excused as the undo's or as a rollup it
   set off. In the delete passes, a record saved during the undo by the undo itself or by a
   rollup is kept only when the judging found it edited; one saved during the undo by anybody
   else is kept, as before. A bulk update's undo has no judging.

## Consequences

- Undoing an import of people and gifts removes the people, whoever recalculated their totals.
- A person somebody edited after the import is still kept, even when the undo's gift deletes
  recalculate their totals afterwards.
- Each judging pass costs one query per 2,000 records. The carried set holds only the records
  found edited.
- An object without the stamp cannot tell a rollup's save from an edit, and such a save keeps
  the record. Core ships no rollup targets without it; an administrator's own rollup onto an
  object without the stamp keeps the safe answer.
- An edit made within five seconds after a rollup's save is read as that save.
- The sixty minutes are a fixed window, not the moment the import's rollups drained. The Rollup
  Queue deletes its entries once processed and keeps no per-record history, so knowing when a
  batch's own entries drained would need new state written on every queue run; and a busy org's
  queue is never empty, so "the queue had nothing pending" is no signal. The 25,000 row scale
  test drained in about seven minutes, so sixty leaves room for imports several times larger
  or a queue behind other work.
- The trade-off: an edit made within sixty minutes after the commit and then hidden by a rollup
  save in that hour is not seen. A rollup save stamped later keeps the record even when nobody
  edited it: the import's rollups stuck behind more than an hour of other work, a nightly run,
  or a total that depends on the date. Keeping is the safe answer; the journal says why.

## Alternatives considered

- **Ignore every save by Automated Process.** Rejected: flows and integrations run as that user,
  and their saves are edits.
- **Snapshot only, without the stamp.** Covers the undo's own deletes but not the import's own
  rollups run by Automated Process, which already count as edits before the undo starts.
- **Suppress the rollups a delete sets off for records the undo will judge.** Rejected: a
  person the undo keeps would be left with totals that still count the deleted gifts, and it
  reaches into the Rollup Queue for one caller.
- **A new "last edited" field kept by triggers.** Rejected: a new field on Contact and Account
  and a trigger on every save, for one check.
