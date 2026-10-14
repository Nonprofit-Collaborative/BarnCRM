# ADR-NEXT: Rollup totals too large for a Queueable are recalculated by a batch over their source rows

**Status:** Accepted (builder decision)
**Date:** 2026-10-14
**Source:** canonical model R-RQ3, R-RQ6; tier 1 scale test on `oi-test` (2026-10-14)
**Amends:** ADR-0082 decision 6 (`0082-barncrm-owns-its-rollup-engine.md`, "a `System.Finalizer`
that halves and retries"), ADR-0100 (`0100-rollup-queue-ready-event-from-queueable-jobs.md`)

## Context

The tier 1 scale test loaded 28,739 gift allocations onto the default fund. Every Rollup Queue
run that held that fund stopped with "Too many query rows: 50001". An aggregate query counts
every row it aggregates towards the 50,000 rows a transaction may read, so the fund's four totals
(three planned queries, two of them over all 28,739 rows) cannot be calculated in one transaction at any slice
size, and no `catch` stops that limit. Any org's General Fund, or an organization with tens of
thousands of gifts, reaches the same point.

The failure then stranded the queue: 826 entries (347 Contact, 347 Account, 132 Fund) stayed
Pending with no processor. Evidence on `oi-test`: two chains of six failed `RollupQueue` jobs
(05:49:29 to 05:49:46 UTC), one Error Log entry per finalizer, entries charged once each with
Next Attempt two minutes later, and no job after the sixth failure in either chain. The finalizer
halved the slice and queued the next run itself; every halved run held the fund again (every Fund
entry names it) and failed again; and the platform queues at most five jobs in a row from
finalizers of failed jobs (and refuses a link past the chain depth limit), so the sixth link was
never created. Each run charged different entries (the ones it charged were not due for the next
run), so none reached five attempts and Failed: nothing was left to process them and nothing
showed them as failed.

## Decision

1. **A batch route for large parents.** `RollupLargeParentBatch` reads the source rows of each
   planned query with a `Database.QueryLocator` (Ids only), runs that query over each chunk's
   rows (`RollupAggregator.calculateRows`, the same query with `AND Id IN :rows`) and folds the
   partial answers into one, which merges exactly as path alternatives already do (R-R1). When
   an entity's queries are all read it writes once through `RollupEngine.writeCalculated`: the
   same target filters, currency handling and write as every other recalculation. One run at a
   time; entries routed while one runs wait two minutes.
2. **What goes there.** Before a queue run recalculates its slice, records whose stored COUNT
   totals times the planned queries reach a fifth of the query row limit (10,000 rows) are
   moved to new entries and handed to the batch, as the full run already estimates a record's
   weight. A run that stops anyway (a record with no COUNT total, or stale counts) is caught by
   its finalizer, which charges the entries it held one attempt and hands those still Pending to
   the batch.
3. **The finalizer never queues the next run.** It publishes `Rollup_Queue_Ready__e`, whose
   subscriber starts a fresh processor (ADR-0100's doorbell). A fresh chain is neither a
   finalizer re-queue nor a deeper link, so neither platform cap applies. The halving of the
   slice is removed: the batch is what now works a heavy slice through.
4. **Ownership.** The batch owns the entries it is given: they wait with a Next Attempt an hour
   away while it runs, are deleted when the totals are written, and are charged one attempt
   (Failed after the fifth, with Last Error and an Error Log entry) when a chunk stops. A run
   that never ends leaves them due again an hour later, never lost.

## Alternatives considered

- **Keep halving, fix the chain.** Halving to one record still fails for the fund itself.
  Rejected: the totals would still never be right.
- **Count child rows before each run.** `COUNT()` counts every row towards the same limit, so a
  pre-count over 28,739 rows costs what it is trying to avoid. The stored COUNT totals are free.
- **Route every large record through the full recalculation batch.** It recalculates whole
  records per chunk, so one record is still one transaction; its "calculated alone" step fails
  the same way.
- **A field on the queue entry marking the route.** Not needed: the batch holds the entries by
  Id and the Next Attempt lease keeps the queue off them.

## Consequences

- A total of any size is calculated, a few minutes after the change instead of seconds.
- The full run's "calculated alone" step still stops on such a record; its records reach the
  queue through `RollupRecalcErrorHandler` (R-R14) and from there this batch.
- A text list or distinct count over a huge parent holds every value in the batch's state;
  practical for the shipped definitions, which use none on funds or organizations.
