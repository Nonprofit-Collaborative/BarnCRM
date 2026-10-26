# ADR-0082: BarnCRM owns its rollup engine

**Status:** Accepted (owner decision, Brandon, 2026-10-12: decisions D1 to D9 of the rollup
proposal, with amendments A1 and A2). Supersedes ADR-0015. Amends ADR-0011: its reuse-first
rule does not apply to the rollup aggregation core.
**Amended by:** ADR-0125 (`0125-rollup-builder-module.md`): the engine this ADR describes, with
the Rollup Builder, is the BarnCRM Rollup Builder module (`packages/rollups`), not Core; Core
reaches it only through `RollupEngineExtension` and the Health Check and nightly job seams.
**Amended by:** ADR-0137 (`0137-instant-totals-generated-trigger-deployed-by-the-admin.md`):
for decision 8, the Builder generates the trigger and its test for any object that can carry
one, and the admin deploys them; the one-click Metadata API deploy is deferred.
**Date:** 2026-10-12
**Source:** owner decision 2026-10-12; plan Section 4.10; builds on ADR-0011, ADR-0015,
ADR-0021, ADR-0022 and ADR-0040

## Context

The owner wants BarnCRM to own its rollup engine outright, to let administrators build their
own totals without code, and to keep mass recalculation efficient and reliable at the v0.11
scale (100k contacts, 40k households, 1M gifts).

Most of the engine is already BarnCRM code: the definition model (`Rollup_Definition__c`,
R-R1 to R-R10), paths (`RollupPath`), filters (`RollupFilterParser`), fiscal windows
(`RollupDateWindow`), the Rollups page and the 50 shipped defaults. apex-rollup is reached at
three call sites in `RollupService`. ADR-0015's build-cost case (43 date literals and an
in-memory filter evaluator) no longer applies: windows are plain date ranges and filters
compile to SOQL. Vendoring costs about 25,000 lines, eight local patches re-applied on every
upstream pull, a test-support object shipped to subscribers, and delta math that races under
parallel loads (apex-rollup #579).

Five defects were found on 2026-10-12 and pinned by the regression suite (slices S1 to S3):
real time never ran for gifts; target filters are ignored, so two definitions writing one
Account field overwrite each other by run order; household soft credit totals are not
calculated, and real time on Soft Credit and Gift Allocation throws (both are unregistered
until S6, so real time runs only on Gift and Commitment today); the record stamp is never
written by a recalculation; and a definition's Last Calculated is stamped when its job is
queued, not when it finishes. The suite also fixes three engine requirements: fund totals
follow a gift's status change and the gift's delete (neither touches the allocation row the
fund total counts), and a person who changes household moves totals out of the old household
and into the new one.

## Decision

1. **Own the aggregation core.** New classes behind `RollupService` replace apex-rollup;
   `vendor/apex-rollup`, `RollupAdapter`, `Rollup__mdt` and `RollupCalcItem__c` are deleted
   only after a comparison run in a test org explains every difference from apex-rollup's
   results.
2. **Recompute, never add and subtract.** Every affected target record is re-aggregated from
   all its source records, so processing a record twice is harmless (R-R9). All active
   definitions on one target object are planned together: aggregate SOQL with bind variables,
   one write per target record, and only changed values written.
3. **Affected parents.** A change marks a target dirty when it touches a field a definition
   reads: the source, order-by, fiscal date and path fields, any filter field, and fields read
   through a relationship (a gift's status for allocation-sourced fund totals). Reparents mark
   old and new targets; deletes mark the old one, including a parent delete that cascades its
   children without firing their triggers; a household move marks both households.
4. **Instant, then queued (R-R4 reworded).** A normal save recalculates in the same save. A
   bulk or asynchronous save writes the dirty parents to `Rollup_Queue__c` (append-only, parent
   Ids held as text so a queue row never locks a parent) and one processor drains it within
   minutes. The nightly full recalculation stays as the safety net. Thresholds are internal.
5. **Full recalculation and skew.** A batch by target object runs the same planner, zeroes
   parents with no remaining children, stamps `Rollups_Last_Calculated__c` in the same write,
   and stamps each definition's Last Calculated when the job chain finishes. A parent with very
   many children is processed alone; a streaming batch is built only if the scale test needs it.
6. **Locks and failures.** No `FOR UPDATE`, writes sorted by Id, partial-success DML, per-parent
   retry with backoff, Failed after five attempts, a `System.Finalizer` that halves and retries
   a slice, and one Error Log summary per run. The Automation Registry switch pauses the engine.
7. **Rollup Builder (amendment A1).** A dedicated "Rollup Builder" tab and app page, built from
   standard Lightning base components plus one shared filter builder. Every rollup, shipped or
   admin-made, is created and edited there, with a preview on a real record and a "Needs
   attention" list with Retry. Definitions stay `Rollup_Definition__c` records and shipped
   defaults stay `Rollup_Definition_Default__mdt`, so saving a rollup is never a deploy.
8. **Admin objects get a generated trigger (amendment A2).** A package can ship triggers only
   for its own objects. For an administrator's own object, the Builder generates a one-line
   trigger and its test class and deploys them for the admin through the Metadata API, in one
   click. The trigger only hands the changed records to a packaged entry point, which runs the
   same change detection and queue as packaged objects; the rollup's settings stay in the
   definition, so editing a rollup never regenerates code. Removing the last rollup on an
   object offers to remove the trigger. The record-triggered Flow action and template remain the
   fallback for anyone who cannot deploy.
9. **Mode names.** Administrators see "Instantly", "Every night" and "Both (recommended)";
   the stored values (Real-time, Scheduled, Both) do not change.
10. **Operations at least as broad as free DLRS.** After the engine swap (S8), one slice adds
    count distinct, "Any" and "None" for checkbox targets, First and Last into text fields, and
    text lists (distinct, delimiter, cut at the field length). Until it lands, the Builder does
    not offer checkbox targets.
11. **Multi-currency.** The calculator slice (S5) tests aggregate behavior in a multi-currency
    org, the Builder warns on currency targets in such an org, and the Health Check wording is
    made to match. Conversion itself stays deferred.
12. **Recalculate all is estimated.** Before a full run the Builder shows the record-count
    estimate and how long it is likely to take, warns during business hours, and offers to run
    it tonight instead (S12).
13. **Who changed a rollup.** Field history tracking on the key `Rollup_Definition__c` fields
    (a platform feature, no code).

### Why the DLRS runtime-deploy pattern, and how its failure modes are handled

ADR-0015 rejected DLRS partly because it deploys triggers at runtime. A2 adopts that pattern
on purpose: without a trigger, a total on an administrator's object can only be nightly or
depend on the admin copying a Flow, and one click is the "easier than DLRS" goal. What made it
painful in DLRS is mitigated as follows:

- **Unrelated org tests block the deploy.** Deploy with `RunSpecifiedTests` naming only the
  generated test, so production needs coverage of the deployed trigger, not a clean org-wide
  run. A failure is shown in plain words with what to do, never a stack trace.
- **The generated test fails on the admin's validation rules or required fields.** The trigger
  body is one line calling a packaged entry point, so the test only has to fire it once; the
  test tolerates a rejected insert. To be confirmed in S15 before the generator is built; the
  admin is pointed to a sandbox first.
- **Connecting to the Metadata API (Named Credential setup).** No Visualforce session Id. The
  preferred path is a packaged connection the admin authorizes once in the browser. Slice S15
  is a spike that proves the package can ship it without per-org secrets, so the admin only
  clicks Authorize; if it cannot, the owner is told before S16 starts and the Flow template is
  the path.
- **Generated code outlives its rollups or the package.** Trigger and test names are derived
  deterministically from the object name, so a sandbox change set and a production deploy
  produce identical code and the Builder never deploys a second copy. The Builder offers removal
  with the last rollup, Health Check reports a generated trigger with no active rollup, and the
  admin guide says to remove generated triggers before uninstalling.
- **Permissions and editions.** Deploying needs Customize Application and Modify All Data,
  checked before the step is offered; others, and editions without Apex, are sent to the Flow
  template with "Ask a Salesforce admin, or use the Flow template". A separate custom
  permission separates building rollups from deploying triggers.
- **Namespace.** The entry point the generated trigger calls is the only `global` method the
  engine adds, takes no arguments and reads the trigger context itself. The generator resolves
  the namespace prefix at run time and never hard-codes one (`check-namespace.sh`).

## Alternatives considered

- **Keep apex-rollup and fix the wrapper.** Cheapest; fails the ownership goal and keeps the
  patch upkeep and delta races.
- **apex-rollup as a package dependency.** Rejected by ADR-0003.
- **A platform event queue.** Invisible backlog, a separate failure store, publish allocations.
- **One Queueable per transaction with no queue.** Lock storms on parallel loads, lost work at
  the enqueue limit, nothing to retry or show.
- **Admin-made definitions as custom metadata.** Every save becomes a Metadata API deploy.
- **Flow template only for admin objects (the proposal's original D5).** No code deployed, but
  instant totals then need an admin to copy and maintain a Flow; kept as the fallback.
- **Native roll-up summaries or Flow aggregation.** Master-detail only, no household paths or
  fiscal windows, no bulk-safe full recalculation.

## Consequences

- BarnCRM maintains about 2,000 lines of engine Apex; the regression suite (S2, S3) and the v0.11
  scale test are the guard. The scale gate adds a skew case, a parallel-load case and a
  queue-drain target (for example, 50,000 gifts loaded in parallel are reflected in every total
  within 15 minutes, with the oldest queue entry's age recorded). If the single processor misses
  it, several processors partitioned by target Id range are allowed, which recompute keeps safe.
  No upstream fixes arrive.
- Bulk saves no longer finish their totals in the same transaction; the admin guide says so.
- Deferred, each brought back by a named need: moving definitions from sandbox to production
  (the deploy step is idempotent so "import then deploy" works later), "last N days" windows,
  failure emails (the Hub tile and Error Log summary cover v1), top N, grandchild, hierarchy and
  Task or Event paths, and currency conversion.
- `NOTICE`, `VENDOR.md`, the `VENDOR_ONLY` allowlist section and the `.prettierignore` entry go
  with the vendored tree. Security review scope shrinks to about six system-mode classes of our
  own plus the generator, the deploy call and the one `global` entry point.
- Canonical model: R-R4 reworded, new rules for change detection and generated triggers, and
  `Rollup_Queue__c` (Section 14A). Plan Section 4.10, C-13, v0.11 and risk 11.1 need the
  matching edits in BMemory.
- Slices added to the original S1 to S14 plan: S15, the Metadata API connection spike; S16,
  generate and deploy the trigger and test with `RunSpecifiedTests`, plain failure messages and
  the separate deploy permission; S17, remove the trigger with the last rollup, uninstall
  guidance and the Health Check finding; and the operations slice after S8 (decision 10).
- The swap (S8) makes BarnCRM's engine the only path for real time, the queue, Recalculate,
  Recalculate all and the nightly run, and deletes `RollupBatch`. The vendored tree,
  `RollupAdapter`, `Rollup__mdt` and `RollupCalcItem__c` stay in the repository, reached by no
  run, until the comparison of decision 1 is made: `RollupEngineComparison`, an Apex utility a
  developer or administrator runs on a test org, calculates a sample of target records with both
  engines inside a savepoint it rolls back and lists every value that differs
  (`docs/contributor-guide/rollup-engine-comparison.md`). S9 deletes them once every difference
  is explained.
- S9 deletes the vendored tree, `RollupAdapter`, `Rollup__mdt`, `RollupCalcItem__c`, the
  `VENDOR_ONLY` allowlist section, the `.prettierignore` and `NOTICE` entries, the vendored
  deploy stage, and `RollupEngineComparison` with its guide and labels: the utility compares
  the two engines, so it cannot outlive one of them, and its last run is the record of
  decision 1. The deletion lands only after that run on a test org has explained every
  difference.
- That run (`oi-test`, 2026-10-13, main at `cbf2f3c4`, sample data, the 50 shipped
  definitions, one definition per transaction, each target field blanked first so neither
  engine could pass by leaving the stored value): 49 definitions and 6,226 values compared,
  3,284 differences, all explained. 3,016 are zero against blank: a sum or count with nothing
  to count is zero in BarnCRM's engine and left blank by the vendored one. 260 are the
  household soft credit totals, whose `{Household}` path the vendored engine cannot walk
  (BarnCRM's matched a direct query). 8 are the one Written off gift and its refund: the
  vendored engine splits its filter on spaces, so the value `Written off` never matched
  (ADR-0022 counts it; BarnCRM's matched a direct query). `Fund_Last_Gift_Date` was not
  compared: the vendored engine refuses a source attribute read through a relationship.
  Several definitions in one transaction made the vendored engine leave minimums and maximums
  blank, which is why each ran alone.
- The deletion also fixes deployability. A check-only deploy to a sandbox showed the vendored
  apex-rollup test classes fail to compile on an org without the Data Protection and Privacy
  objects (`ContactPointAddress`, `Individual`, `ContactPointConsent`), which upstream's tests
  use as fixtures. Those classes ship inside Core's package, so while the tree stays, Core
  cannot install on such an org, against ADR-0013; with it gone, Core names none of them.
- Decision 6's finalizer cannot apply to a batch (a `System.Finalizer` attaches only to a
  Queueable). The full recalculation batch instead raises `BatchApexErrorEvent`
  (`Database.RaisesPlatformEvents`), and a handler writes a stopped chunk's records to the
  Rollup Queue, which retries them with the queue's own finalizer and backoff. Only one full
  run goes at a time: a second start (Recalculate all during the nightly run) is refused with
  the running job named (canonical model R-R14).
