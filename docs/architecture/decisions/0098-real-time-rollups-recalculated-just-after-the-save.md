# ADR-0098: Real-time rollups are recalculated just after the save, by default

**Status:** Proposed (builder decision, Core quality pass item Q-01)
**Date:** 2026-10-13
**Source:** canonical model R-R4 and Section 14A (Rollup Queue); modifies decision 4 of
`0082-barncrm-owns-its-rollup-engine.md` ("a normal save recalculates in the same save");
rollup review findings ROLLUPS-2, ROLLUPS-5, ROLLUPS-7 and ROLLUPS-11

## Context

A gift saved with the shipped rollups installed recalculates every Instantly and Both total it
touches inside the save: about 52 to 58 SOQL queries (the donor's 22 account totals, 10 contact
totals, appeal, pledge and fund totals, plus reading the definitions about six times). That is
more than half of the 100 queries a save may use. Two things follow:

- **A save can fail.** The check before the recalculation let it start with up to 49 queries
  used, but the recalculation alone needs more than 50, so a save that reaches the rollups at 45
  queries hits "Too many SOQL queries". A limit error cannot be caught, so the person's gift
  is not saved (ROLLUPS-2). An org with its own Flows or triggers on Gift reaches that point
  sooner.
- **Every save is slow.** Each gift save, including each line of a gift batch and each Quick
  Gift Entry, pays for the recalculation before the page comes back.

The Rollup Queue (ADR-0082 decision 4) already exists for bulk and background saves: an
append-only list of target records, a single Queueable processor that merges and recalculates
them, retries with backoff, a finalizer that halves a slice that hits a limit, Failed after
five attempts, and Needs attention with Retry.

## Decision

1. **Queued by default.** A save that marks target records (R-R11) writes them to the Rollup
   Queue and returns; the processor recalculates them just after the save, usually within a
   minute. The save pays for marking (the definitions, the households of the people it reaches),
   one insert per trigger and one check for a waiting processor: a budget of 8 queries and 4
   DML statements per gift save, pinned by `GiftSaveRollupCostTest`. Recalculation recomputes
   (ADR-0082 decision 2), so the totals end up exactly what recalculating in the save gives.
2. **The admin can choose the save.** A new setting on the Rollups section of the BarnCRM
   Settings console, **When instant totals are calculated** (`Rollup_Processing__c`): **Just
   after the save (recommended)**, the default, or **During the save**, which keeps the
   behaviour before this decision for an org that needs the total on the page the moment the
   save returns. A blank setting means just after the save.
3. **During the save is planned first (ROLLUPS-2).** With During the save chosen, the
   recalculation starts only when the queries it can spend (one per definition on each marked
   target entity, one more through a household token, four per entity) fit what the
   transaction has left, and the rows read so far are under half the limit. Otherwise the
   records are queued, as a bulk save's are.
4. **Coalescing.** Each trigger adds one entry per target entity; one processor waits at a
   time (a save that finds one queued starts none); the processor merges entries per target
   entity into slices of 200, so a record saved many times is recalculated once. A slice halved
   after a limit error grows back after a run that finishes (ROLLUPS-11).
5. **Nothing waits for a save that never comes (ROLLUPS-7).** The nightly run, the end of an
   automation pause, Retry and a new **Start now** button in Needs attention start a processor
   when Pending entries wait and none is queued.
6. **Errors are visible.** What stops a processor run is logged by its finalizer, records the
   platform refuses are summarised in one Error Log entry per run (both as before), and Health
   Check gains a Rollup Queue finding: records Failed after five attempts, or entries waiting
   more than an hour. Both point to Needs attention.
7. **Definitions are read once per transaction (ROLLUPS-5).** The engine's read of
   `Rollup_Definition__c` is cached for the transaction and cleared by the definition trigger on
   any insert, update or delete, so a save no longer reads them once per target entity.
8. **Unchanged.** Merges keep their own queued job (ADR-0092). The Recalculate rollups Flow
   action follows the same setting. The nightly run stays the safety net.

## Alternatives considered

- **Keep recalculating in the save and only tighten the check.** Fixes the failed saves but
  keeps every save slow, and the check would queue most gift saves in an org with its own
  automation anyway.
- **Change Data Capture or a platform event subscriber.** CDC entity selection is limited per
  edition (five entities without the add-on) and its subscriber runs as the Automated Process
  user; a platform event needs a separate failure store and publish allocations, and its backlog
  is invisible. ADR-0082 rejected the event queue for the same reasons; the Rollup Queue already
  is durable, visible and retried, and runs on every edition.
- **One Queueable per save carrying the Ids in memory.** Lost at the enqueue limit (one job in
  a batch or queueable context), nothing to retry or show, and parallel saves race on parents.
- **Make the queue the only path and drop During the save.** Simplest, but removes behaviour an
  org may rely on (totals visible when the page refreshes); kept behind the setting instead.

## Consequences

- Totals in Instantly and Both mode appear a few seconds after a save rather than in it. A
  record page open on the donor shows the new total after a refresh. The admin guide says so.
- A gift save spends about 8 rollup queries instead of about 55, and cannot fail on the
  rollups' query count.
- Tests that read a total right after a save set During the save (`RollupTestSupport`); the
  queued path has its own tests (`RollupBackgroundTest`, `GiftSaveRollupCostTest`).
- A parent too large for one transaction (more than 50,000 source rows read) still fails in the
  processor after five attempts and shows in Needs attention and Health Check; a streaming path
  stays deferred to the scale test (ADR-0082).
