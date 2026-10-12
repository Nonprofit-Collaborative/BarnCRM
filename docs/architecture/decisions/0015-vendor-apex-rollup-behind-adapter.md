# ADR-0015: Vendor apex-rollup as the aggregation core, behind a BarnCRM adapter

**Status:** Superseded by `NEXT-barncrm-owns-its-rollup-engine.md` (owner decision, 2026-10-12):
BarnCRM replaces apex-rollup with its own aggregation core and removes the vendored tree after a
clean comparison run. Until then this decision describes the engine that runs. Previously:
Accepted (builder decision under ADR-0011; vendored as source, not a package dependency)
**Date:** 2026-09-07
**Source:** ADR-0011, plan Section 4.10 and Section 12 decision D-11

## Context

ADR-0011 requires that before any rollup engine code is written we evaluate vendoring a well-maintained open
source Apex rollup library and record the outcome as an ADR. That evaluation is now done, against plan Section
4.10 and the constraints in ADR-0003, ADR-0008, ADR-0009 and ADR-0013. Three candidates were read at source
level.

DLRS (BSD-3-Clause) generates Apex triggers and custom metadata records and deploys them into the subscriber org
through the Metadata API at runtime, needs a Named Credential to do it, pins the `dlrs` namespace, carries fflib
and a 13,583-line MetadataService, and supports only a single child-to-parent lookup field. NPSP Customizable
Rollups (BSD-3-Clause) is 50 classes depending on 50 more NPSP classes, on the TDTM framework, on a runtime
custom metadata deployer, and on Opportunity, OpportunityContactRole and the npe01/npe03 objects ADR-0009
forbids in Core. No fourth open source engine of substance exists.

apex-rollup (MIT, jamessimone/apex-rollup, v1.7.44, 2026-07-30) meets the criteria. It deploys nothing at
runtime and makes no callouts, and it ships a second package built from identical source under a namespace, so
namespace safety is demonstrated rather than hoped for. `GrandparentRelationshipFieldPath__c` supports the
two-hop Gift to Contact to Household Account path directly; `RollupDateLiteral` implements the calendar and
fiscal literals that this year, last year and two years ago require; it escalates synchronous to queueable to
batch under `RollupControl__mdt` thresholds, retries through a `System.Finalizer`, and carries 20 test classes
and 551 test methods with scratch org CI.

Its costs are bounded and nameable: 12 references in non-test source to objects
`scripts/ci/check-standard-objects.sh` forbids in Core (a merge-eligibility check on Account, Case, Contact and
Lead, Task and Event polymorphic handling, and two string literals naming Opportunity in a multi-currency map);
153 `global` declarations, which are permanent API commitments in a managed package; a `without sharing` posture
with `AccessLevel.SYSTEM_MODE` DML that sits against plan Section 4.13; and one primary maintainer, which argues
for vendoring rather than depending.

## Decision

We **vendor apex-rollup's `rollup/core` directory as source into Core**, under
`packages/core/vendor/apex-rollup/`, retaining the MIT licence text and copyright notice, and we **drive it
through an adapter we own**. Concretely:

1. We vendor `rollup/core` (32 classes, 13,253 lines) and `rollup/tests`. We do not vendor `rollup/app`: no
   Rollup app, tab, quick action, LWC or permission set of theirs ships, and the administrator never sees
   `Rollup__mdt` or any upstream UI.
2. `Rollup_Definition__c` remains the system of record and the only thing our console reads or writes.
   `RollupAdapter` translates each active row into an **in-memory** `Rollup__mdt` and calls
   `Rollup.runFromApex(List<Rollup__mdt>, Evaluator, List<SObject>, Map<Id, SObject>)` for real-time mode and
   `Rollup.performBulkFullRecalc(List<Rollup__mdt>, String)` for scheduled mode. No `Rollup__mdt` record is ever
   created in a subscriber org, so there is no metadata deployment, no remote site setting and no admin-visible
   custom metadata.
3. Four patches are named here and six were applied, all recorded in `VENDOR.md` (E ports the vendored
   tests off the Sales Cloud objects, F strips dangling metadata references and makes the upstream
   configuration protected): (a) the merge-eligibility check in `Rollup.cls` becomes
   a name-based check against a configurable set, removing the static `Schema.Case` and `Schema.Lead`
   references; (b) the `'Opportunity'` and `'OpportunitySplit'` dated-multicurrency literals in
   `RollupCurrencyInfo.cls` move into a custom metadata-driven map; (c) `global` is downgraded to `public`
   throughout, since we ship none of their invocable actions; (d) the sharing posture is documented rather than
   claimed away. **Correction, 2026-09-07:** an earlier version of this item said our adapter defaults
   `RollupControl__mdt.ShouldRunAs__c` and `Rollup__mdt.SharingMode__c` to `User`. That was wrong on both
   counts. `ShouldRunAs__c` selects the execution context only (Queueable, Batchable, Synchronous Rollup); it
   has no sharing meaning and no value named `User`. `SharingMode__c` affects queries only: it becomes the
   `AccessLevel` on the SOQL in `RollupRepository`. The writes in `RollupSObjectUpdater` and `RollupState` pass
   `System.AccessLevel.SYSTEM_MODE` unconditionally and no setting changes that. The engine writes rollup
   targets in system mode by design, because computed totals must be correct regardless of the running user's
   sharing, and no user input reaches these writes. That is the documented exception under plan Section 4.13,
   and `VENDOR.md` patch C states it once for all 29 `without sharing` engine classes. The adapter default that
   remains real, and is deferred to `RollupAdapter` in C-14, is `SharingMode__c`. `check-standard-objects.sh` gains no path exclusion: after (a) and (b) the vendored
   tree passes it as-is, which is the acceptance test for those patches.
4. Upstream is tracked deliberately, not continuously (ADR-0011). `VENDOR.md` records upstream URL, licence, the
   vendored commit hash and tag (`6dc353c670fc381a56ac29968be2d1fbf7f60527`, v1.7.44), the date, the four
   patches with rationale, and the procedure for taking a new upstream version.

## Alternatives considered

- **Build our own engine.** Rejected under ADR-0011 and Principle 8: it means reimplementing relationship-path
  walking, 43 date literals and an in-memory where clause evaluator, about 3,000 lines of the
  highest-correctness-risk code in the product, to reach parity with something that exists and is tested.
- **Take apex-rollup as a package dependency** instead of vendoring source. Rejected: ADR-0003 keeps Core's
  dependency graph empty, install becomes two steps, and the six patches recorded in `VENDOR.md` become impossible.
- **DLRS.** Rejected: runtime Metadata API trigger deployment, its own admin console, no multi-hop, a pinned
  namespace, and a 65,000-line footprint including fflib.
- **NPSP Customizable Rollups.** Rejected: not extractable. Fifty NPSP class dependencies, a runtime metadata
  deployer, and a data model built on objects Core may not reference.
- **Vendor apex-rollup wholesale, `rollup/app` included.** Rejected: it puts a second rollup configuration
  surface in front of the administrator, against plan Section 2.3 and ADR-0011.

## Consequences

- Core carries about 13,000 lines of third-party Apex plus its tests. Someone must read upstream release notes
  and decide, and a security finding in vendored code is our finding.
- The patches are a rebase cost on every upstream pull. They are kept minimal and mechanical for that
  reason, and `VENDOR.md` states each rationale so a future maintainer can tell whether upstream has made one
  unnecessary.
- Coverage (plan Section 7.2) is computed over the whole package. Vendored tests help, but our adapter tests
  must stand on their own and must not lean on upstream coverage.
- The `without sharing` posture is inherited, and there is no setting that undoes it: 29 of the 32 engine
  classes are `without sharing`, and every rollup write is system mode by design. `SharingMode__c` moves the
  reads only. v0.10 security review preparation treats the vendored tree as in scope and documents every
  remaining `AccessLevel.SYSTEM_MODE` write, starting from the patch C section of `VENDOR.md`.
- `RollupState.cls` serialises chained-job state with a DataWeave script resource. If packaging a `.dwl` in a
  2GP managed package proves problematic, the fallback
  `RollupControl__mdt.ShouldUseJSONSerializationStrategy__c` already exists. Verified in the first packaging
  build, not later.
- The 100k contact and 1M gift claim is structural, not measured. It is proven by the v0.10 scale test, and this
  decision is revisited if that test fails after tuning `RollupControl__mdt`.
- Every vendored custom metadata type ships `Protected` and every vendored custom metadata record ships
  `protected`, so item 1's promise that the administrator never sees `Rollup__mdt` holds in a subscriber org
  rather than only in our own UI. This is decided before the first package version because it cannot be
  relaxed afterwards: a protected type cannot be made public once subscribers hold a version.
- If apex-rollup stops being maintained we keep a working MIT copy and become its maintainer for our purposes.
  That is the outcome vendoring was chosen to make survivable.

## Integration plan for the recommended option

**Definitions and the console.** `Rollup_Definition__c` keeps the fields plan Section 4.10 names and stays the
only thing the console reads or writes. `RollupAdapter.toMetadata(List<Rollup_Definition__c>)` produces
in-memory `Rollup__mdt`: source to `CalcItemText__c`; target to `LookupObjectText__c`; relationship path to
`LookupFieldOnCalcItem__c` for one hop or `GrandparentRelationshipFieldPath__c` for two or more; aggregate to
`RollupOperation__c`; target field to `RollupFieldOnLookupObjectText__c`; filter builder output plus date window
to `CalcItemWhereClause__c` (for example `Gift_Date__c = N_FISCAL_YEARS_AGO:2`). Using the `...Text__c` variants
throughout makes the adapter the single place that prefixes our namespace onto object and field API names, which
is exactly what the upstream namespaced-package rule requires. Packaged default definitions still ship as our
own custom metadata and are materialised on install (plan Section 4.8).

**Household membership abstraction.** In Contact mode the path is a real relationship (`Contact.AccountId`), so
Gift to Household Account is one `GrandparentRelationshipFieldPath__c` such as
`Contact__r.Account.Household_Total__c`, handled natively. In Junction mode `Household_Member__c` is
many-to-many and no single path exists, so the adapter does not attempt one:
`HouseholdService.getHouseholdIdsFor(Set<Id> contactIds)` resolves the target Ids, the adapter sets
`IsRollupStartedFromParent__c` and hands apex-rollup the resolved parent Ids with a query over the junction, so
the aggregate runs through the same code path either way. `HouseholdService` stays the only class that knows
which mode is in use (plan Section 4.6). In Contact mode the Contact trigger must also call the rollup entry
point, because upstream requires intermediate objects in a grandparent chain to re-trigger on reparent; that is
what makes moving a contact between households correct.

**Last Calculated.** Ours, not theirs. `RollupAdapter` writes `Rollup_Definition__c.Last_Calculated__c` and the
per-target `..._Last_Calculated__c` sibling after each successful run, from the finalizer path so it lands once
per job chain rather than once per chunk. The Hub reads the maximum across active definitions for "Rollups last
completed" and raises the 36-hour warning tile. Upstream has no such concept and needs none.

**Upgrade management.** `packages/core/vendor/apex-rollup/VENDOR.md` records upstream URL and licence file,
vendored commit `6dc353c670fc381a56ac29968be2d1fbf7f60527` (tag v1.7.44, 2026-07-30), the vendored subtree
(`rollup/core`, `rollup/tests`), the patches with rationale and the file and line each touches, and the
pull procedure: fetch upstream, diff the new tag against the vendored hash, reapply the patches, run the full
Core suite plus `check-standard-objects.sh` and `check-namespace.sh`, then update the hash and date in
`VENDOR.md` in the same pull request. Upstream is reviewed on a schedule and on security advisories, never
auto-tracked.

**First three tests.**
1. `RollupAdapterTest.mapsTwoHopHouseholdPathInBothMembershipModes`: one `Rollup_Definition__c` for Gift SUM to
   Household Account, asserted twice. Contact mode must produce the expected
   `GrandparentRelationshipFieldPath__c` and the right household total over 200 gifts across 50 contacts in 25
   households; Junction mode must produce identical totals via `HouseholdService`-resolved parent Ids.
2. `RollupEngineTest.recalculationIsIdempotentAcrossEveryPath`: insert, update, delete, undelete, reparent and
   merge over 200 gifts in one DML context, then a full recalculation, asserting the same values both times.
   Plan Section 9.4's requirement, and the direct test of patch (a).
3. `RollupDateWindowTest.fiscalYearWindowsResolveAgainstOrgFiscalSettings`: this year, last year and two years
   ago against a non-January fiscal year start, asserting each gift lands in exactly one window and a
   boundary-dated gift lands in the later one.
