# ADR-0117: A save that queues no processor asks again after it commits

**Status:** Accepted (builder decision)
**Date:** 2026-10-14
**Source:** canonical model R-RQ3; tier 1 scale rerun on `oi-test` (2026-10-14); extends ADR-0100

## Context

A save that writes Rollup Queue entries starts a processor unless one is already waiting
(`RollupQueue.startProcessor`). The reasoning was that a waiting processor reads every entry
committed by the time it starts. The save's own entries are not committed yet: the waiting
processor can start, find nothing new, and finish before the save commits. Nothing then comes
for them.

The scale rerun hit it during a Bulk API Contact load in parallel batches of 200. Forty-seven
Account entries were created from 07:27:41Z, Pending with no attempts, two seconds after the
last processor was queued (07:27:39Z). That processor completed, and no processor or large
parent batch ran in the 25 minutes after. They would have waited for the nightly run.

The same gap had two smaller cases: a transaction that asked for a processor before it wrote
any entries (a background job's chain end), and one with no queueable job left to give.

## Decision

The decision to start a processor is made again after commit whenever the transaction's own
decision could not cover its entries. A transaction that inserted entries and queued no
processor (one was waiting, it had asked earlier with nothing pending, or its job allowance was
used) publishes one `Rollup_Queue_Ready__e`. The event is delivered after commit (ADR-0100), so
its subscriber's check runs when the entries are visible: a processor still waiting is sure to
read them, and if none is waiting it starts one.

Only a transaction that inserted entries publishes. The subscriber inserts none, so it never
publishes again while a processor waits (which could loop for the ten minutes a delayed run
waits).

What each piece prevents:

- The event when a processor was waiting: the stranded entries the scale load left.
- The event after an earlier ask: entries a background job writes after asking at its chain end.
- The event when the job allowance is used: entries waiting a day for the nightly run.
- The inserted-entries guard: the subscriber ringing itself while a processor waits.

## Alternatives considered

- **The processor's finalizer re-checks for Pending entries.** It runs after the processor's own
  transaction, but the saving transaction can commit later still, so the same race remains.
- **A scheduled job every few minutes starting a processor for Pending entries.** A backstop,
  not a fix: it still strands entries for its interval, and it takes a scheduled job slot and a
  setting in Nonprofit Settings. Not needed while the race is closed by construction.
- **Always publish the event instead of starting a processor.** It adds a platform event to
  every save that queues totals, and delivery delay to the common case that has no race.

## Consequences

- At most one more event per transaction, only in a save that finds a processor waiting.
  During a parallel bulk load that is about one per batch, within the allocation ADR-0100
  accepted.
- If the event cannot be published, the failure is logged and the nightly run, which starts a
  processor for Pending entries (ROLLUPS-7), stays the backstop.
