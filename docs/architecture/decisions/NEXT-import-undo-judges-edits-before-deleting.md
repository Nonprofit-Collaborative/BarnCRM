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

1. **A rollup's save is not an edit, whoever made it.** Every rollup save writes
   `Rollups_Last_Calculated__c` (canonical model, freshness stamp) in the same save as its
   totals, stamped just before the save. A record whose `LastModifiedDate` falls within five
   seconds after its stamp was last saved by a rollup. Any later save of another kind leaves the
   stamp behind it. The stamp is read by its name through describe, so Core names no module.
2. **Edits are judged before anything is deleted.** A rollup's save, or the undo's own (a
   household renamed), replaces `LastModifiedDate`, which would hide an edit made before it.
   After the restore pass, one judging pass per delete pass, in the same order, notes which
   tagged records were already edited, and the job carries that set to the delete passes. A
   record saved during the undo by the undo itself or by a rollup is kept only when the judging
   found it edited. A record saved during the undo by anybody else is kept, as before.

## Consequences

- Undoing an import of people and gifts removes the people, whoever recalculated their totals.
- A person somebody edited after the import is still kept, even when the undo's gift deletes
  recalculate their totals afterwards.
- Each judging pass costs one query per 2,000 records. The carried set holds only the records
  found edited.
- An object without the stamp cannot tell a rollup's save from an edit, and such a save keeps
  the record. Core ships no rollup targets without it; an administrator's own rollup onto an
  object without the stamp keeps the safe answer.
- An edit made within five seconds after a rollup's save is read as that save. An edit hidden
  by a rollup that ran later, before the undo began, is not seen; the import's own rollups run
  within minutes of the commit.

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
