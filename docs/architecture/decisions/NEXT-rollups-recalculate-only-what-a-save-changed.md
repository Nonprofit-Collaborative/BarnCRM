# ADR-NEXT: A save recalculates only the rollups its change can affect

**Status:** Accepted (owner decision D-48, Brandon, 2026-10-13: "rollups run only what changed")
**Date:** 2026-10-13
**Source:** rollup review finding ROLLUPS-4; narrows decision 2 of
`0082-barncrm-owns-its-rollup-engine.md` ("all active definitions on one target object are
planned together") for real-time saves; canonical model R-R11 and Section 14A

## Context

A save marks the target records its change reaches (R-R11, ADR-0082 decision 3), but each
definition marks separately: a gift save marks the donor account for the gift totals, never for
the soft credit or pledge totals, which read other source entities. The recalculation then threw
that away. In the save and in the Rollup Queue, `RollupEngine.recalculate(ids, targetType)`
reloaded every active definition on the target entity, of every mode, and ran them all.

With the shipped definitions a gift save therefore also re-ran the commitment and soft credit
totals on the donor's account and contact (about 11 of the 36 aggregate queries), and a soft
credit save re-ran every gift and commitment total (about 24 of 32). Every night definitions
(Scheduled) also ran in each save, though their mode says they wait for the nightly run.
Since the async rollups ADR (`NEXT-real-time-rollups-recalculated-just-after-the-save.md`) the
Rollup Queue does this work by default, so the waste moved from the save to the processor: the
same queries, in a job whose slice of 200 records fails sooner the more it runs.

## Decision

1. **The definitions that marked a target run, and only those.** `RollupChanges.Marked` records,
   for each target entity, the definitions that marked its records: in the save itself, from the
   rows under a changed parent (`RollupDependents`), from a delete, and from a household move.
   A recalculation in the save runs those definitions and no others over the marked records, as the merge survivor job already did (ADR-0092).
2. **Queue entries carry them.** A new Rollup Queue attribute, Definition Ids
   (`Definition_Ids__c`), holds the definitions that queued the entry. The processor merges the
   entries of one target entity as before and runs the union of their definitions, reading them
   from the transaction's definition cache. A record the platform refused is queued again with
   the same definitions.
3. **Blank means every definition.** An entry with no Definition Ids runs every active
   definition on its target entity, whatever its mode, as before this decision: entries written
   before the upgrade, chunks of a full run handed to the queue (R-R14), the error handler's
   hand-off, and any marked definition that has no record id. A definition list too long for
   the attribute is also written blank. Recalculation recomputes, so running more is never
   wrong, only slower.
4. **A definition switched off or deleted while its entry waits is skipped.** The processor
   reads only active definitions; the rest of the entry still runs.
5. **ADR-0082 decision 2 is narrowed, not reversed.** The definitions a recalculation runs are
   still planned together per target entity, with one write per target record and only changed
   values written. Full runs (nightly, Recalculate, Recalculate all) are unchanged.

## Alternatives considered

- **Keep running every definition and fold queries instead (ROLLUPS-6).** Folding cuts the
  cost of each definition; it does not stop definitions that cannot have moved from running.
  The two are complementary.
- **One queue entry per definition.** Exact, but multiplies the entries a save writes (22
  account totals) and loses the merging that makes the queue cheap.
- **Carry definition keys rather than ids.** Keys survive a definition being re-created, but
  an entry lives minutes, and keys are not unique for an administrator's own definitions.

## Consequences

- With the shipped defaults, a gift save's recalculation drops from about 36 aggregate queries
  to about 25, and a soft credit save's from about 32 to about 8, in the save or in the queue.
- Every night definitions run only in the nightly run and on demand, as their mode says.
- A target record's Rollups Last Calculated stamp means "a total on this record was
  recalculated", which is already what it means when only changed values are written.
- One attribute is added to `Rollup_Queue__c`; the BarnCRM Admin permission set reads it.
