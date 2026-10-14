# ADR-0116: Rollup totals too large for a Queueable are recalculated by a batch over their source rows

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
   time; entries routed while one runs wait two minutes. A run starts only under a row lock on
   the org-level record of `Rollup_Run_Lock__c` (a protected custom setting with no fields,
   created the first time), taken before the check for a running batch: two or three
   processors at once (parallel saves start them) otherwise both found none running and both
   started one, as the scale rerun showed. The lock is held from that check to the processor's
   commit, a few statements; a run that cannot take it in time waits two minutes as when busy.
2. **What goes there, and only that.** Before a queue run recalculates its slice it estimates
   each record's source rows: its largest stored COUNT total times the planned queries, as the
   full run weighs a record. A filtered or fiscal year COUNT is a floor, and a record with no
   COUNT to go by (none defined, or never calculated) is unknown, ten rows per query, not one.
   A record estimated at 40 percent of the query row limit (20,000 rows) or more moves to a new
   entry for the batch. The others are taken in order up to a row budget for the whole run (60
   percent of the limit, as the full run's chunk budget); the rest go back to the queue as fresh
   entries for the next run, uncharged, and the first record a run takes always runs, so a
   record under the threshold is recalculated alone if it must be. The gap between the two
   leaves room for the queue's own queries, the target records' triggers and flows, and a
   filtered or stale COUNT that makes the estimate low, so a record just under the threshold
   does not stop a run and charge the records it shares it with. (The threshold was a fifth of
   the limit at first; on the scale rerun that sent a donor with about 2,000 soft credits to the
   batch on every change, one batch job per planned query, when a run could hold it.) A run that stops anyway while recalculating a single
   record, on the query row limit, hands that record to the batch. Every other failure stays
   with the queue (decision 3).
3. **A stopped run narrows down to the record that stops it.** The finalizer charges only the
   records the run was recalculating: they move to a new entry with one more attempt and the
   reason, the rest of each entry stays as it was. An entry charged this way merges only with others
   charged the same way, for the same entity and attempts, and a run takes a quarter as many
   records per attempt (50, 12, 3, then 1 of a 200 slice), so a record that stops every run (a
   flow failing on it, heap, CPU) ends Failed alone and the others it shared a run with are
   recalculated. Retries of a refused save are already one record each and run at the full
   slice. This replaces the halving of the next run's
   slice: the narrowing travels with the entries, so it survives a fresh chain.
4. **The finalizer never queues the next run.** It publishes `Rollup_Queue_Ready__e`, whose
   subscriber starts a fresh processor (ADR-0100's doorbell). A fresh chain is neither a
   finalizer re-queue nor a deeper link, so neither platform cap applies.
5. **Ownership.** The batch owns the entries it is given: it charges each one attempt as it takes
   them (Failed after the fifth, with Last Error), holds them with Next Attempt an hour ahead,
   renewed with every chunk so a long run never loses them, deletes them when the totals are
   written, and releases them with the reason when a chunk stops. A run that dies without
   finishing leaves them due an hour after its last chunk; the next routing charges them again,
   so even that ends Failed rather than looping. Records are saved with partial success, so one
   the platform refuses is queued again on its own and never stops the others.
6. **Bounded state.** COUNT_DISTINCT and TEXT_LIST_DISTINCT keep one entry per distinct value
   while rows are folded, so the batch's state grows with distinct values, not rows.

7. **Quiet hand-offs.** A processor at the chain depth limit hands off to the Ready event without
   an Error Log entry: on a busy org that happens every few runs (31 Info entries in ten minutes
   on the scale rerun) and needs nothing doing. Health Check still reports entries waiting over
   an hour.

## Alternatives considered

- **Keep halving, fix the chain.** Halving to one record still fails for the fund itself.
  Rejected as the whole answer: the totals would still never be right.
- **Send every stopped run's records to the batch.** A slice that dies of CPU, heap or a failing
  flow would die the same way in the batch's write, and all of its records would end Failed
  together. Rejected: only the row limit is what the batch fixes.
- **Carry the slice size on the Ready event.** Needs a field and is lost whenever a processor
  is already waiting. The attempts on the entries already say how far to narrow.
- **Count child rows before each run.** `COUNT()` counts every row towards the same limit, so a
  pre-count over 28,739 rows costs what it is trying to avoid. The stored COUNT totals are free.
- **Route every large record through the full recalculation batch.** It recalculates whole
  records per chunk, so one record is still one transaction; its "calculated alone" step fails
  the same way.
- **A field on the queue entry marking the route.** Not needed: the batch holds the entries by
  Id and the Next Attempt lease keeps the queue off them.
- **Lock Core's settings record instead of a dedicated one.** An org that never saved its
  settings has no record, and creating one from a rollup run would store first-save defaults
  nobody chose; admin saves would also wait on rollup runs.
- **The same lock around every processor run.** A processor holds its transaction for seconds of
  recalculation, so a second one would wait on the lock and fail on the platform's ten second
  lock timeout, which the finalizer then charges as a stopped run. Concurrent processors stay
  harmless (recalculation recomputes); only the batch start, which is expensive and should be
  single, is locked.

## Consequences

- A total of any size is calculated, a few minutes after the change instead of seconds.
- The full run's "calculated alone" step still stops on such a record; its records reach the
  queue through `RollupRecalcErrorHandler` (R-R14) and from there this batch.
- A plain TEXT_LIST over a huge parent still holds every value in the batch's state, since every
  row is listed; the shipped definitions use none on funds or organizations.
- A large record whose stored counts are stale or missing costs up to five failed runs, while
  the queue narrows down to it, before it reaches the batch; it may show as Failed while the
  batch that then recalculates it runs, and the entry goes when the totals are written. The
  stored counts that run writes route it straight to the batch from then on.
