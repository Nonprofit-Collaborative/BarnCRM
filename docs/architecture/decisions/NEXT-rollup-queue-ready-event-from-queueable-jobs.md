# ADR-NEXT: A platform event starts the Rollup Queue after a save inside a Queueable

**Status:** Accepted (builder decision)
**Date:** 2026-10-13
**Source:** canonical model R-RQ3; rollup comparison run on `oi-test` (2026-10-13)

## Context

A save inside a Queueable job writes Rollup Queue entries but never starts the processor
(R-RQ3): the platform lets a Queueable queue one job, and that job belongs to the running job's
own next step. Taking it stopped the sample data load with "Too many queueable jobs added to the
queue: 2". BarnCRM's own jobs start the processor when their chain ends
(`RollupService.startQueuedRecalculation`), but a subscriber's integration or any other code's
Queueable does not, so its totals waited for the next processor a later save happened to start,
or for the nightly run. That breaks the promise of the Instantly and Both modes for every change
made in the background.

The Q-01 decision (`NEXT-real-time-rollups-recalculated-just-after-the-save.md` on
`feature/q-01-async-rollups-2`) rejected a platform event subscriber as the main mechanism for
real-time rollups: it needs its own failure store and publish allocations, and its backlog is
invisible. That reasoning stands. This decision is narrower.

## Decision

Inside a Queueable, `RollupQueue` publishes one `Rollup_Queue_Ready__e` per transaction, after
commit, the first time it writes entries. The event carries no data. Its subscriber,
`RollupQueueReadyTrigger`, calls `RollupService.startQueuedRecalculation`, which starts the
processor only when entries are pending and no processor is already waiting.

The Rollup Queue stays the durable, visible, retried store. The event is only a doorbell: it
holds no record Ids, so losing one loses nothing. If it cannot be published, the failure is
logged and the entries wait for a later processor or the nightly run, as before this decision.

## Alternatives considered

- **Leave it as it was.** Totals from other code's Queueables wait up to a day. Rejected: the
  mode is called Instantly.
- **A platform event carrying the record Ids.** What Q-01 rejected: a second store with its own
  failures and limits. Not needed, because the queue already holds the Ids.
- **A scheduled job polling the queue every few minutes.** Uses a scheduled job slot, runs when
  nothing is pending, and still lags by its interval.

## Consequences

- One event per Queueable transaction that queues totals, counted against the org's daily
  platform event publish allocation. A busy integration publishes at most one per job.
- The subscriber runs as the Automated Process user. The processor is `without sharing` and
  reads definitions in system mode, so its totals are the same as from any other start.
- The three packaged permission sets grant Read and Create on the event, as on
  `Error_Log_Event__e`.
- Revisit if the event allocation becomes a constraint in large orgs.
