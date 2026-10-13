# ADR-NEXT: Merge survivors' real-time totals are recalculated just after the merge

**Status:** Accepted (builder decision)
**Date:** 2026-10-13
**Source:** canonical model R-R4 (real-time totals in the same save), R-R11, R-H13 and the
people merges of Section 29A; builds on `0082-barncrm-owns-its-rollup-engine.md` (BarnCRM's
own engine and the Rollup Queue)

## Context

R-R4 says a normal save updates the real-time totals in the same save. A merge, of people or
of households, deletes the losing records and leaves a survivor whose totals have changed, so
the `after delete` trigger recalculated the survivors there. In an org the platform refused
those writes: a record that is part of a merge cannot be updated by a trigger running inside
that merge. The recalculation failed, was queued for a retry, and the survivor's totals were
wrong for minutes after a merge, which is the moment a person looks at them.

## Decision

1. **Recalculated just after the merge, not in it.** `RollupService.runForSurvivors` reads the
   real-time definitions that target the merged entity and queues one small job,
   `SurvivorRecalculation`, with the survivors and those definitions. The job runs once the
   merge is saved and recalculates only those definitions (the Rollup Queue would also run the
   nightly ones).
2. **The Rollup Queue is the fallback.** When there are more than 50 survivors (the same limit
   as a real-time save) or the save cannot queue another job, the survivors go to the Rollup
   Queue instead. A survivor the platform still refuses in the job is queued to be tried again,
   and anything that stops the job logs the error and queues every survivor, as in a save.
3. **The same for every merge.** People merges (contacts, and a person stored as an account
   with its person contact) and household merges use the same path.

## Alternatives considered

- **Keep recalculating in the trigger and rely on the retry.** Rejected: the first write
  always fails, so every merge left wrong totals for minutes and an error behind it.
- **Always send survivors to the Rollup Queue.** Rejected: the queue runs on its own schedule
  and also runs nightly definitions, so a merge of one pair would wait longer than it needs to.
- **Platform event or a future method.** Rejected: a queueable carries the definitions already
  read, can be tested with `Test.stopTest`, and is what the Rollup Queue already uses.

## Consequences

- A merge's survivors show correct totals a moment after the merge, not in the same save; a
  page opened during that moment can show the old totals until it is refreshed.
- One queueable job per merge save, within the platform's limit per transaction; a save that
  has used them all falls back to the queue.
- R-R4 records the exception; no object or field is added.
