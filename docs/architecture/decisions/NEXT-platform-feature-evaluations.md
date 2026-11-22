# ADR-NEXT: Big Objects for Field History, Platform Cache and React Multi-Framework, evaluated

**Status:** Proposed (build agent W8 R1.36, 2026-11-22; for the integrator and Brandon)
**Date:** 2026-11-22
**Source:** Plan item EVAL-01, decision D-219 (Brandon, 2026-11-21: "Adopting newer platform
features can be now rather than later, as long as they're generally available and wouldn't
hinder adoption. Please evaluate now."). Builds on ADR-0094 (no Platform Cache partition),
ADR-0195 (Field History Keeper), ADR-0238 (settings as custom metadata), ADR-0240 (archive rules
and the big object archive, which records the barn-platform big object prototype) and plan
Section 9.9 (portability toward BarnCRM for WordPress).

## Context

D-219 asks for three platform features to be judged now against one test: generally available,
and no harm to adoption. Adoption here means every org BarnCRM targets: Enterprise and Unlimited
production orgs (most nonprofits through Power of Us), their sandboxes (`mwdbdevsb`, a sandbox
of a real Standard Edition org, D-192), Developer Edition and scratch orgs (`barn-platform`,
`barn-sales`, `oi-test`), unmanaged and source installs today (the namespace is deferred), and a
managed 2GP package later. Professional Edition and Platform Starter are not targets (D-174).

Platform facts were checked on 2026-11-22 against Salesforce's own pages where they could be
read (Trailhead "Get Started with Platform Cache", the Salesforce Developers blog posts of July
and October 2026 on Multi-Framework) and third-party summaries where Salesforce's documentation
site refused automated reads (the Multi-Framework guide and packaging page, the Apex Platform
Cache limits page). Facts from a summary only are marked as such below.

### 1. Big Objects for Field History

**Today.** Field History Keeper (ADR-0195) captures changes in `TriggerDispatcher` after update
and writes one `Field_History__c` row per changed record per save (JSON of the changed fields,
`Record_Id__c`, `Object_Name__c`), in system mode with partial success, in the save's own
transaction. The card reads the newest 200 rows for a record; restore re-reads one row; Record
Cleanup deletes rows older than `Field_History_Retention_Days` (default 730) through
`RecordRetentionBatch`; erasure deletes a person's rows in its own transaction (GD-01, the ADR-0195
amendment). The feature ships off (`Field_History_Enabled` defaults to false).

**The platform feature.** Big objects are GA (long established). They hold rows outside data
storage, one million rows included per org with more as a paid add-on, read only by their index.
The barn-platform prototype (ADR-0240 context) proved: `Database.insertImmediate` after ordinary
DML in the same transaction throws an uncatchable error; writes are not rolled back with the
transaction; Batch Apex, Apex Cursors and `COUNT()` do not work; a filter that skips an index
field aborts the transaction; `deleteImmediate` needs exactly the index fields; the index can
never change once deployed. Big objects run in every edition BarnCRM targets and package in
2GP.

**Fit.** A save that keeps history has already done DML (the record itself), so the capture
could not write a big object in the save: it would need a queueable or platform event per
tracked save, which adds an async job to every save, loses the "history is in the same
transaction" guarantee that erasure relies on (ADR-0195 amendment: every row already exists when
erasure runs), and lets a rolled-back save keep a history row. Retention could no longer be a
`RecordRetentionBatch` pass (no Batch Apex, no date filter without the leading index field), and
erasure would need an index scan like the archive's. The one-million allocation is per org and
already counted by `Archived_Record__b`, so history and the archive would compete for it. The
gain is data storage: a `Field_History__c` row costs 2 KB, so an org keeping 100,000 changes a
year holds about 400 MB at the 730-day default, a small share of an Enterprise org's 10 GB base
allocation, and retention bounds it.

### 2. Platform Cache

**Today.** ADR-0094 removed Platform Cache: configuration reads use the platform's own caches.
Since SET-01 (ADR-0238) every setting is custom metadata read with `getAll()` (no SOQL, cached by
the platform and refreshed by the deploy that changes it) and cached per transaction in
`SettingStore`; Automation Control is a hierarchy custom setting (`getInstance()`, no SOQL);
`ModuleSettings.registry()` runs one counted query, only for the one-time carry-over;
`SettingsState` reads job state rows, which must be current and are often read `FOR UPDATE`, so
they cannot be cached. No read on the save path costs a query that a cache would save.

**The platform feature.** GA (long established). Default org capacity: Enterprise 10 MB,
Unlimited and Performance 30 MB, Developer Edition 0 MB (a 10 MB trial on request), Professional
none (Trailhead). A partition's minimum size is 5 MB. A partition with no capacity misses every
`get` and drops every `put`, silently. A package's own free capacity ("Provider Free", 3 MB)
comes only to a managed package that has passed security review (ADR-0094, from the packaging
guide). The default partition cannot be packaged. Scratch orgs start with none.

**Fit.** In an unmanaged install today, or a managed one before security review, a shipped
partition has zero capacity until an admin allocates some of the org's 10 MB in Setup, which is
a setup step outside the Settings console. In Developer and scratch orgs it is zero. So a cache
helps only some orgs, only after an admin step, and must always fall back. With every hot read
already free after SET-01, the only candidates left are describe-heavy reads (per user, not
serializable) and job state (must not be stale). There is no hot read to put in it.

### 3. React through Salesforce Multi-Framework

**Today.** The front end is 415 Lightning Web Components across the packages, built on the UX kit
(`c-barn-*`), Lightning Data Service and thin Apex controllers. Logic that should port to
BarnCRM for WordPress lives in framework-free JavaScript modules with Jest tests (plan 9.9,
ADR-0175 Forms, `askPipelineModel`, help text as JSON, ADR-0164); the off-platform portal client
(ADR-0185) is plain JavaScript with a WordPress plugin. D-219 also asked whether React could
lower the Apex budget: it cannot, since JavaScript (LWC or React) never counts toward the Apex
character limit, and moving logic into LWC JavaScript already earns that (AP-01).

**The platform feature.** Salesforce Multi-Framework went GA on 2026-07-16 for React, with Angular
GA in October 2026 (Salesforce Developers blog). From the GA notes and summaries of the guide:
available only in Hyperforce orgs on Summer '26 or later (production, sandboxes, Developer
Edition and scratch); an app is a `UIBundle` (built output deployed, so every deploy needs an
`npm ci` and build per bundle) exposed through a Custom Application and a permission set;
employee apps run as standalone full-screen apps on the separate `salesforce.app` domain, not
inside Lightning containers, so not on record pages, App Builder pages, utility bars, quick
actions or Flow screens (`lightning-ui-embedding` can frame one in a Lightning page through an
LWC wrapper); data comes through a Data SDK (GraphQL over the UI API) and Apex REST. Managed
package support is contradictory across sources: Salesforce's packaging page describes 2GP
distribution with a namespace, and a GA-era review lists managed packages and Translation
Workbench as roadmap. No source states a license cost.

**Fit.** Nearly every BarnCRM screen lives inside Lightning: record page panels, Module Home tabs
in console apps, the Settings console, Flow-facing components. Those cannot be React apps. A
React app would add a second component system beside the UX kit, an npm supply chain to keep
secure for security review, a build step in every deploy script and CI job, and a Hyperforce
requirement an org on first-generation infrastructure cannot meet. Translation is not available
in GA while BarnCRM's labels are translatable. Framework-free modules already serve the
WordPress goal better than React would, since they run under any framework.

## Decision

1. **Big Objects for Field History: rejected for capture; adopt later only as an archive tier.**
   `Field_History__c` stays the store. If a pilot org's history rows reach a share of data
   storage that matters (Org Optimizer's Storage and Limits shows `Field_History__c` among the
   largest objects, or an admin asks to keep history past the retention window), the later step
   is a Record Cleanup option that moves expiring rows into the existing `Archived_Record__b`
   through the archive's Copy and Settle links (ADR-0240) instead of deleting them, so no new
   big object, index or capture change is needed.
2. **Platform Cache: rejected now; adopt later on evidence.** ADR-0094 stands, now with SET-01
   behind it: Core and the modules ship no partition and no cache code. Revisit when both hold:
   the package has passed security review (so the 3 MB Provider Free capacity reaches every
   subscriber without an admin step), and Scale Center or ApexGuru shows a cross-transaction read
   near a limit. Any later use follows ADR-0094 decision 3 (keys versioned by the writing
   transaction) and treats a miss as the normal path.
3. **React Multi-Framework: no pilot now; adopt later for one full-screen tool.** LWC stays the
   framework for every BarnCRM screen, and portable logic stays in framework-free modules. A
   pilot is reconsidered when all of these hold: Salesforce documents managed 2GP packaging of a
   `UIBundle` as GA and translation support, a BarnCRM screen is a standalone full-screen tool
   that would gain from an npm library (candidates: the Grid, Advanced Reporting's builder, the
   Projects staffing planner), and the pilot org set is on Hyperforce. The pilot would then ship
   in its own module so Core never requires it.

## Alternatives considered

- **Field history straight to a big object through a queueable.** Rejected: an async job per
  tracked save, history kept for rolled-back saves, retention and erasure rebuilt around index
  scans, and a second claim on the one-million allocation, all to save data storage that
  retention already bounds.
- **A dedicated `Field_History__b`.** Rejected for the same reasons, plus a second index that can
  never change.
- **Ship a Platform Cache partition now with a safe fallback, caching a read such as the module
  registry.** Rejected: zero capacity in every org until an admin allocates it (zero in Developer
  and scratch orgs), a setup step outside the Settings console, and no remaining read on the
  save path that costs a query. Removing a packaged partition later is harder than adding one.
- **A React pilot now (for example a standalone Grid app).** Rejected for now: Hyperforce-only,
  managed packaging and translation not settled, a build step and npm review burden in every
  deploy, and a second UI system beside the UX kit for a screen LWC already serves.
- **Lightning Out 2.0 or `lightning-ui-embedding` to put BarnCRM components on other sites.**
  Out of scope for EVAL-01; the portal client (ADR-0185) already serves off-platform pages.

## Consequences

- No code changes from this record; no edition, sandbox or unmanaged install loses anything.
- Three adopt-later triggers to watch, each named above: history storage share in a pilot org,
  security review plus Scale Center evidence, and Multi-Framework managed packaging and
  translation GA.
- Field history keeps its same-transaction guarantee, which erasure depends on.
- Revisit this record at the first package version (namespace decision) and after security
  review, when the Provider Free cache and managed packaging facts become testable in a real
  subscriber org.
