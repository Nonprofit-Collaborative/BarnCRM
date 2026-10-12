# Rollup engine: vendor or build (feature C-13, iteration v0.2)

Evaluation for plan Sections 4.10 and 12 (D-11), under ADR-0011. Date 2026-09-07. Findings verified by reading
cloned source, not marketing text.

**What was read.** `git clone` through the proxy worked for all three repositories, so nothing was blocked:
apex-rollup at HEAD `6dc353c67` (v1.7.44, 2026-07-30), DLRS at `8e43f0122` (2026-07-27), NPSP as a blobless
sparse clone of `force-app/main/default/classes` at 2026-09-02. Not read: the apex-rollup wiki (grandparent
behaviour below comes from the README and `RollupRelationshipFieldFinder.cls`), and NPSP's Aura and custom
metadata, listed by filename only.

## Candidate 1: apex-rollup (James Simone), MIT

**License.** MIT, `Copyright (c) 2019 James Simone`. Redistribution in source and binary form inside a managed
package is permitted with the copyright and permission notice retained, and MIT is one-way compatible into
Apache-2.0 for the combined work. No upstream patent grant, a real but small delta against ADR-0008.

**Architecture.** Trigger entry is one line, `Rollup.runFromTrigger()`. `RollupAsyncProcessor` implements
`Database.Batchable<SObject>` and `Database.RaisesPlatformEvents`, with an inner `QueueableProcessor implements
System.Queueable`; `RollupFinalizer` implements `System.Finalizer` for retry after an uncaught limit exception;
`RollupSchedulable` covers scheduled runs. It escalates synchronous to queueable to batch on
`RollupControl__mdt` thresholds (`MaxLookupRowsBeforeBatching__c` 3000, `BatchChunkSize__c` 500,
`MaxParentRowsUpdatedAtOnce__c` 5000, plus query and retry caps). Chained-job state is persisted in
`RollupState__c`, serialised by a DataWeave script resource (`rollup/core/dw/jsonToRollupState.dwl`) with a JSON
fallback behind `RollupControl__mdt.ShouldUseJSONSerializationStrategy__c`.

**Metadata model.** `Rollup__mdt` (39 fields), `RollupControl__mdt` (20), `RollupOrderBy__mdt`,
`RollupGrouping__mdt`, `RollupPlugin__mdt`, `RollupPluginParameter__mdt`, plus `RollupSettings__c` custom
setting and `RollupState__c` custom object. Key `Rollup__mdt` fields: `CalcItem__c`, `LookupObject__c`,
`LookupFieldOnCalcItem__c`, `LookupFieldOnLookupObject__c`, `RollupFieldOnCalcItem__c`,
`RollupFieldOnLookupObject__c`, `RollupOperation__c`, `CalcItemWhereClause__c`,
`GrandparentRelationshipFieldPath__c`, `RollupToUltimateParent__c`, `UltimateParentLookup__c`,
`IsRollupStartedFromParent__c`, `SharingMode__c`, `IsDisabled__c`, `RollupControl__c`. Every picklist-driven
field has a `...Text__c` twin, which is what makes a namespaced package workable. Operations: SUM, COUNT,
COUNT_DISTINCT, AVERAGE, MIN, MAX, FIRST, LAST, CONCAT, CONCAT_DISTINCT, MOST, ALL, SOME, NONE.

**Multi-hop.** Yes, the differentiating feature. `GrandparentRelationshipFieldPath__c` takes a dotted path and
`RollupRelationshipFieldFinder.cls` (928 lines) walks it, honouring SOQL's five-level child-to-parent cap;
`RollupToUltimateParent__c` handles self-hierarchies. Gift to Contact to Household Account is exactly the
documented shape. README caveat: intermediate objects in the chain must also fire `Rollup.runFromTrigger()` so a
reparent of the middle record re-triggers the aggregate. For us that means Contact carries the rollup trigger
call, which it will anyway.

**Filters and date windows.** `CalcItemWhereClause__c` is a SOQL-shaped where clause evaluated in Apex by
`RollupEvaluator.cls` (897 lines), so filtering needs no query when records are already in memory.
`RollupDateLiteral.cls` (1186 lines) implements 43 literals including `THIS_YEAR`, `LAST_YEAR`, `N_YEARS_AGO:n`
and the full fiscal set (`THIS_FISCAL_YEAR`, `LAST_FISCAL_YEAR`, `N_FISCAL_YEARS_AGO:n`,
`LAST_N_FISCAL_YEARS:n`) resolved against org fiscal settings. This year, last year and two years ago need no
new code.

**Scale.** No published benchmark at 1M records. The evidence is structural: elastic escalation to batch, chunked
parent updates, in-memory evaluation instead of per-record SOQL, stateful chaining, finalizer retry. Prove it in
our own v0.10 scale test rather than assuming it.

**Tests, CI and maintenance.** 20 test classes, 11,964 lines, 551 `@IsTest` annotations, bundled into the base
package as of v1.7.44; `.github/workflows/deploy.yml` runs LWC Jest plus scratch org Apex tests with Codecov
upload, and `code-analyzer.yml` is present. 300 commits, a steady 1 to 4 merged pull requests every month from
2025-08 through 2026-07, latest release 2026-07-30. Single primary maintainer: the main bus-factor risk, and the
main argument for vendoring rather than depending.

**Managed-package specifics.**
- *Namespace: solved upstream.* The repo ships `rollup-namespaced/`, a second package built from identical
  source under the `please__` namespace, so the library provably compiles and runs inside a namespace. The
  documented rule is that every text-valued field reference (where clauses, grandparent paths, ultimate parent,
  order by) must be namespace-qualified. Our adapter generates those strings, so we qualify them in one place.
- *No Metadata API from Apex.* Zero references to `Metadata.Operations`, `MetadataService`, `HttpRequest`, or
  any remote site setting. Nothing is deployed at runtime. This is the single biggest contrast with DLRS and
  NPSP CRLP.
- *Standard object references.* `Rollup.cls:2908-2912` statically references `Schema.Account`, `Schema.Case`,
  `Schema.Contact` and `Schema.Lead` to decide which objects can be merged. `RollupQueryBuilder.cls`,
  `RollupCalculator.cls` and `RollupRelationshipFieldFinder.cls` reference `Task.SObjectType` and
  `Event.SObjectType` for polymorphic What/Who handling. `RollupCurrencyInfo.cls` has `'Opportunity'` and
  `'OpportunitySplit'` as **string literals** in a dated-multicurrency map. Twelve matches in non-test source
  would fail `scripts/ci/check-standard-objects.sh` today.
- *`global` surface.* 153 `global` declarations, each a permanent, unremovable API commitment in a 2GP **managed**
  package. Downgrade to `public` when vendoring: we ship none of their invocables, so nothing must stay `global`.
- *Sharing.* Nearly every class is `without sharing`, and `RollupSObjectUpdater` and `RollupState` do DML with
  `System.AccessLevel.SYSTEM_MODE`, though `RollupRepository` honours `RollupControl__mdt.ShouldRunAs__c` and
  `Rollup__mdt.SharingMode__c` offers a per-rollup User mode. Collides with plan Section 4.13; largest
  security-review item.
- *Size.* Vendorable slice `rollup/core`: 190 files, 32 classes, 13,253 lines, plus `rollup/tests`: 41 files, 20
  classes, 11,964 lines. `rollup/app` (37 files: LWC, tabs, app, permission sets) is the admin surface we do
  **not** vendor.

## Candidate 2: DLRS, BSD-3-Clause

License is fine (BSD-3-Clause, Andrew Fawcett 2013; redistribution permitted with notice and a no-endorsement
clause). Everything else disqualifies it.

- **Realtime mode generates and deploys Apex triggers into the subscriber org via the Metadata API.**
  `RollupController.getParentTriggerCode()` string-builds a trigger body and `deployZip()` posts it through
  `MetadataService.MetadataPort`; definitions themselves are `LookupRollupSummary2__mdt` records deployed at
  runtime by `CustomMetadataService`. This needs a Named Credential (`NamedCredentialForAPI__c`), puts a
  deployment console in front of the administrator, and cannot live inside a managed package we ship. Direct
  conflict with plan Sections 2.3 and 4.10.
- **No multi-hop.** `RelationshipField__c` is a single child-to-parent lookup field. Gift to Contact to
  Household Account requires two chained definitions and an intermediate field.
- **Size and dependencies.** 134 classes, roughly 65,000 lines, 524 files, including `MetadataService.cls` at
  13,583 lines, fflib-common (8,464 lines) and fflib-apexmocks (14,685 lines). Vendoring that into Core is not
  proportionate.
- **Namespace.** `sfdx-project.json` pins `"namespace": "dlrs"`, and nine source lines hard-code
  `dlrs__LookupRollupSummary__c` for legacy detection.
- Maintenance real but slowing: 122 commits in 2024, 55 in 2025, 15 in 2026, last 2026-07-27.
## Candidate 3: NPSP Customizable Rollups (CRLP), BSD-3-Clause

License fine, extraction is not. 50 non-test `CRLP_*` classes, about 13,100 lines, plus 12 Aura components,
referencing 50 distinct non-CRLP NPSP classes: the TDTM trigger framework (`TDTM_Runnable`,
`TDTM_TriggerHandler`, `TDTM_Config_API`), `UTIL_Describe`, `UTIL_CustomSettingsFacade`, `UTIL_DMLService`,
`UTIL_CurrencyCache`, `UTIL_AbstractRollup_BATCH`, the legacy `RLLP_*` engine, and `CMT_MetadataAPI`, which
deploys custom metadata at runtime exactly as DLRS does. The domain model is welded to Opportunity (430
references), OpportunityContactRole, `npe01__OppPayment__c`, `npe03__Recurring_Donation__c`, `Allocation__c` and
`Partial_Soft_Credit__c`, all forbidden in Core by ADR-0009 and by `check-standard-objects.sh`. Extraction would
be a rewrite wearing a donor's class names. Rejected.

**Candidate 4: anything else.** Nothing else qualifies. `vmedatwilio/ApexRollup` is a personal fork with no
releases; Rollup Helper and Rollup Magic are commercial and excluded by the brief; fflib has no rollup extension
of substance. The field is genuinely two projects wide.

## Decision matrix

Scores: 2 = meets it, 1 = partial or needs work, 0 = fails. Weight 3 = hard requirement.

| Criterion | W | apex-rollup | DLRS | CRLP |
| --- | --- | --- | --- | --- |
| License permits redistribution in our managed package | 3 | 2 | 2 | 2 |
| 2GP-packageable as source, namespace-safe | 3 | 2 (namespaced build exists upstream) | 0 (pinned namespace, runtime deploys) | 1 |
| No Metadata API deploy from Apex, no remote site | 3 | 2 | 0 | 0 |
| Parent-child and lookup rollups | 3 | 2 | 2 | 2 |
| Two-hop path (Gift to Contact to Household) | 3 | 2 | 0 | 1 (Opportunity-shaped only) |
| Declarative metadata model our UI can drive | 2 | 2 | 1 (own console) | 1 (own Aura app) |
| Filters without admin-typed SOQL | 2 | 2 | 1 | 2 |
| Fiscal year and date-window aggregates | 2 | 2 | 0 | 1 |
| Real-time and scheduled modes | 2 | 2 | 2 | 2 |
| Governor safety at 100k contacts / 1M gifts | 3 | 1 (structural, unproven for us) | 1 | 1 |
| Tests and CI | 2 | 2 | 2 | 2 |
| Maintained | 2 | 2 | 1 | 1 |
| No dependency on other packages | 3 | 2 | 0 (fflib, MetadataService) | 0 (NPSP) |
| No forbidden standard objects | 3 | 1 (12 fixable refs) | 1 | 0 |
| Sharing and FLS posture matches Section 4.13 | 2 | 1 (`without sharing`, has User mode flags) | 1 | 1 |
| **Weighted total (max 76)** | | **65** | **28** | **32** |

## Recommendation
**Vendor apex-rollup as source into Core, behind a thin BarnCRM adapter.** It is the only candidate that is
namespace-proven, deploy-free at runtime, dependency-free, multi-hop capable and fiscal-year aware. The 12
standard-object references and the sharing posture are bounded, nameable patches, not architecture problems.
Building our own would mean reimplementing `RollupRelationshipFieldFinder`, `RollupDateLiteral` and
`RollupEvaluator`, roughly 3,000 lines of the hardest correctness code in the product, against ADR-0011's
explicit instruction not to. This is a hybrid in the sense ADR-0011 anticipated: the aggregation core is theirs;
the administrator surface, the definition model, the household abstraction, the freshness surfacing and the
packaged defaults are ours, and the administrator never sees `Rollup__mdt`.

