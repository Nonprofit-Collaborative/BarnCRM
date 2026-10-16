# Roadmap

Purpose: planned work with status. Mirrors Section 6 of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Feature status detail lives in `docs/barncrm-features.md`.

Status as of 2026-10-13 (main at PR #377, squash 272d1e3b, gated 2,952 of 2,952 on `oi-test`). #219 landed batches 2 to 7; #377 landed batches 8a to 8e: the Core quality pass fix batches, Q-01 to Q-14, rollup S9, data tools parity, Erase a person, the console app and the gate fixes. `main` (at #221) deployed to `barn-npc` 2026-10-13 and passes. 2026-10-14: #401 to #408 landed (Core cleanups, Access add-on permission sets, merge settlement, coverage floor, import undo, Platform-license permission split, duplicate rule matching for Load one object, empty household tidy); the D-47 inventory is done. 2026-10-14 and 2026-10-15 (main at #426, squash b570b8ae, `oi-pa` gate 3,125 of 3,125): #411 edition names, #412 and #434 rollup queue row-limit fixes, #433 scale cleanup fix, #413 neutral role names, and #426 editions, feature switches, Modules section and first-run setup (D-96, D-97, D-99 to D-102). The Rollup Builder module stack (#417 to #432) and #435 are in review (below). "Landed" means in `main`.

## Near-term queue (plan 6.0, owner decisions 2026-10-13)

1. Core quality pass (D-38, D-39): test, optimize, improve and simplify existing Core without removing functionality, before the non-core modules. Built in parallel:
   - Seven Core reviews; findings become fix batches. Landed (#377); open review items listed in plan 11.3.
   - Q-01 to Q-14 platform features (D-39; table below). Landed (#377).
   - SLDS 2 linter gate (PR #223). Landed.
   - Console app with an app icon. Landed (#377).
   - Field utilization on demand (D-37, D-63). Landed (#377).
   - Test self-containment. Landed (#377).
   - Rollup S9 (vendored apex-rollup removed). Landed (#377). S14 only if the scale test needs it; S15 spike built; S16 and S17 deferred to after v1 (D-64).
   - Inventory of unfinished Core work (D-47). Done 2026-10-14 (#401 to #408, including duplicate rule matching for any object, #405). Related-records import stays insert-only (post-1.0); org check of a parent and child file import passed 2026-10-15 on `oi-test` (Upsert by external ID, `Stewardship_Plan_Template__c` with `Stewardship_Plan_Step__c`, 3 parents and 7 children, dry run then commit, all linked, no errors).
   - Find, bulk update and duplicates fix batch. Landed (#377).
   - Approved review recommendations (D-48). Fix batches landed (#377); remainder per the feature catalog.
   - Affiliations in Core people imports, restored (D-49; C-32). Landed (#377).
   - Data tools parity (D-50): Data Manager hub, Org Optimizer, full results file, trial import, delete from a file of IDs, more transform steps, lookups and update matching on any Text, Email or Phone field, row rules, delimiter and worksheet choice, download before delete, retry rejects, server-side export (C-36 remainder), parent and child loads. Landed (#377). Not approved: seeding templates, files import. C-38 stays on hold.
   - Import tab label "Import", reached from Data Manager; Import and Bulk Update leave the navigation; Find stays (D-51). Landed (#377).
   - Erase a person in Core, with a Giving extension (D-52, D-86). Landed (#377).
   - Shipped import templates added at install and on upgrade (D-55). Landed (#377).
   - Deleting people never deletes their household (D-88, R-H12). Landed (#377).
2. On hold: C-38 scheduled imports and connections, until Brandon is ready to start the next version (D-39).
3. After the Core quality pass: the non-core modules, in plan Section 6 order.
4. Telemetry (C-26): deferred indefinitely (D-24, no AppExchange for now).
5. `mwdbdevsb`: deployed 2026-10-14 at the owner's request (Core at e3f2db58, then plus #411 to #413); ask before every further deploy.
6. Release prerequisites (namespace, Dev Hub, steward entity): after a v1.0 pilot (D-87).
7. Rename Connect to Mirror (D-103, ADR-0126): Landed (#441, 98583f12, ADR-0126).
8. Test org cleanup of old Connect metadata (destructive deploy; owner approved): `oi-test` done (176 components); `oi-pa` done (module record, then 175 components); `barn-core` had no Connect module (nothing to remove); `barn-npc` done 2026-10-15 (Mirror deployed from main 702616e6 first, then 176 components). Done on all four test orgs.

| ID | Platform feature (Core quality pass, D-39) | Status |
|---|---|---|
| Q-01 | Real-time rollups off the save transaction | Landed (#377; D-71) |
| Q-02 | RunRelevantTests and `isCritical`/`testFor` for fast gates | Landed (#377) |
| Q-03 | Apex Cursors for large-volume jobs (also removes the 200-row import exceptions cap) | Landed (#377) |
| Q-04 | Custom Notifications when long jobs finish | Landed (#377; on by default, D-67) |
| Q-05 | `lightning/modal`, toast, alert and confirm | Landed (#377; D-66) |
| Q-06 | GraphQL and Lightning Data Service reads | Landed (#377) |
| Q-07 | Workspace API in the console app | Landed (#377) |
| Q-08 | Dynamic Forms, Related Lists and Actions on every record page | Landed (#377) |
| Q-09 | User Access Policies | Landed (#377; documented with samples, not packaged, D-61) |
| Q-10 | In-App Guidance | Landed (#377; tips off in Setup, D-62) |
| Q-11 | Platform Cache | Landed (#377; no Platform Cache for now, D-60) |
| Q-12 | Scratch org snapshots (Dev Hub snapshot `BarnPA` from `oi-pa` approved, D-46) | Landed (#377) |
| Q-13 | ApexGuru and Scale Center | Landed (#377) |
| Q-14 | Agentforce-ready invocable actions (optional; approved) | Landed (#377; D-68, D-69) |

## Iterations

| Iteration | Theme | Feature IDs | Status |
|---|---|---|---|
| v0.1 | Foundation and households | C-01, C-02, C-03, C-04 to C-11 | Shipped. Engineering open: namespace, first package version (after a v1.0 pilot, D-87) |
| v0.2 | Giving core | G-01, C-13, C-14, G-02 to G-06, C-12 | Shipped. C-13 own engine S1 to S9, operations slice, Builder S10 to S13 landed (D-16) |
| v0.3 | Commitments, relationships, addresses | G-07, C-15, C-17, C-16, G-08 to G-11 | Shipped |
| v0.4 | Stewardship and receipting | G-12 to G-16, G-18, C-18 | Shipped |
| v0.5 | Import 2.0, gift import, coexistence | C-19, G-17, C-22, G-23, C-20, C-21, G-24, import templates | Shipped |
| v0.6 | Mirror (was Connect, D-103) | X-01, X-02, X-03, X-04, X-06, C-23, G-20, C-29 | Shipped (C-29 PR #163). X-07 Gift Transaction mirror planned next (moved here by plan 6.3) |
| v0.7 | Data management | C-32, C-33, C-34, C-35, C-36, C-37 (C-36 and C-37 moved from 1.x 2026-10-12), C-28, G-25 | Landed (#219, #377), including C-36 server-side export and the C-37 follow-ons |
| v0.8 | Volunteers | V-01 to V-08; C-24 and C-30 | C-24, C-30 landed (#219); V-items planned |
| v0.9 | Programs and Logic Models | P-01, P-02, P-04 to P-08, L-01 to L-04; C-39; G-19 if capacity | C-39 landed (#219); rest planned |
| v0.10 | Funders and Nonprofit Cloud mirror | F-01 to F-08, X-07, L-06; X-05 | Planned |
| v0.11 | Hardening | Security review, scale test, C-31 (C-26 deferred indefinitely, D-24); tests run as permission-set users; vendored rollup tests removed by S9 | C-31 landed (ADR-0088 accepted, D-64); tests as permission-set users and S9 landed; accessibility static pass and translation sweep landed (#377); device mobile run and security review open; scale test done except the 25,000-row import run, which the owner wants finished before marking it done (2026-10-14) |
| v0.12 | Beta | Beta cohort, C-27 | C-27 landed (#219) |
| v0.13 | AppExchange | Listing, v1.0 on approval | Planned |

## Cross-iteration work

| Item | Source | Status |
|---|---|---|
| Rename Open Impact to BarnCRM (labels, folders, package names) | Plan 11.3 item 6 | Merged (#181) |
| Rename `Nonprofit_*` API names to BarnCRM names | Plan 11.2 item 25 | Merged (#181) |
| Neutral Core follow-ups | C-29 | Merged (#181) |
| Engineering follow-ups 1, 3, 4, 5 (settings writers, dynamic Apex, CLI heap, review items) | Plan 11.3 | 1, 3, 4 merged (#181); 5 landed (#219) |
| Engineering follow-up 2 (log unrecognized checkbox values in imports) | Plan 11.3 | Merged (#224) |
| Own rollup engine and Rollup Builder | D-16, D-18, D-30 to D-32 | S1 to S9, operations slice, Builder S10 to S13 landed (ADR-0082, ADR-0083); S15 spike built; S14 planned; S16, S17 after v1 (D-64) |
| Flow templates | D-22 | Landed (ADR-0090) |
| Explicit Apex access modes (API 67.0 audit) | D-23 | Landed (`check-apex-access-modes.py`) |
| AI-ready invocable actions, portability checks (OpenAPI, model check) | D-23 | Landed; Q-14 actions landed (#377) |
| Gift keeps its household | D-20 | Landed (ADR-0070, ADR-0071) |
| Pledge payment picker in gift entry (G-25) | D-17 | Landed (ADR-0084) |
| CMDT Manager (plan 6.1 item 9) | D-25 | Landed (ADR-0085) |
| Field utilization (plan 6.1 item 10) | D-26, D-37, D-63 | Landed: on demand, inside Org Optimizer only (#377) |
| Tests run as permission-set users | D-33 | Landed (#219, self-containment #377) |
| "Data Job" relabel | ADR-0047, D-45, D-51 | Landed (#377): object label Data Job, tab "Import" |
| Deleting people keeps their household | D-88 | Landed (#377); the tidy-later option was decided by D-89 (2026-10-14), landed (#408): a nightly Core job moves empty households to the Recycle Bin once their former members can no longer be restored |
| Edition names: Nonprofit Edition and Standard Edition | D-96 | Landed (#411, ADR-0122) |
| Neutral Core role names (Team Member, Coordinator) | D-97 | Landed (#413, ADR-0123) |
| Editions, features, modules: edition gates what Core shows; Core features off on a new install, turn-on one-way; Settings Modules section; first-run setup that holds Core automation until done | D-99, D-100, D-101, D-102 | Landed (#426, ADR-0124; #414 to #425 closed as landed in it) |
| Rollup queue row-limit fixes (query-row budget, stale-count large-parent route) | Scale test, D-90 | Landed (#412, #434); scale cleanup script fix landed (#433) |
| BarnCRM Rollup Builder module (engine and Builder move out of Core into `packages/rollups`; Giving depends on it; both editions) | D-101 | Landed (#438, 4ed86f12, ADR-0125; #417, #419, #423, #424, #427 to #432 and #437 closed as landed in it) |
| #435 | Follow-up after #426: `deploy-packages.sh` calls `TabAccessService.requestSync()` after deploy; the `turnOn` unknown-key message says "setting", not "feature" | Landed (#435) |
| Advanced Territory Management (C-40) and Grid tool (C-41) Super Tools | D-98 | Planned, after v1.0 |
| Follow-up: household catch-up for person accounts (turning Household Upkeep on catches up contacts only) | #426 review | Done (#447) |
| Follow-up: scale test duplicate-rule losses (the load lost 309 households and 1,328 contacts to the standard duplicate rules; failed-*.csv not kept; root cause confirmed 2026-10-15: Bulk API 2.0 refuses duplicates with `DUPLICATES_DETECTED`; fix landed in #443; closes when a live scale run shows 0 refused) | Scale test | Open |
| Follow-up: namespace readiness for the module split (module pages use Core components cross-package: `settingsConsole`, `c/workspaceTabs`; module tests use Core `@TestVisible` privates; module `appUrl` namespace). Review result, blocking before the first package version: B1 19 module trigger handlers `@NamespaceAccessible` (done, #447); B2 production module code calling unannotated Core members (`OrgShapeDetector`, `ErrorLogger.SEVERITY_*`, `RollupFilterParser` members; done, #447); B3 module tests using Core `@TestVisible` privates (needs public test hooks; open); B4 module tests using unannotated Core test factories (open); B5 cross-package inner-class field access to verify (open); B6 CI checks for cross-package visibility and dynamic lookups (done, #447). Should fix: S1 `rollupBuilder` imports unexposed `c/workspaceTabs` (copy `labelTab` instead; open); S2 `settingsConsole` reads only `c__section` (done, #447); S3 explicit constructors on 8 extension classes (done, #447); S4 a Mirror test uses Giving's protected label (open); S5 check the `/lightning/app/Fundraising` link (open); S6 more CI checks (open). Only a throwaway-namespace 2GP build can settle B3 to B5 (owner decision pending) | Plan 4.10, D-101 | B1, B2, B6, S2, S3 done (#447); B3, B4, B5, S1, S4, S5, S6 open |
| PR #443: scale loader allow-save REST insert for Accounts and Contacts, plus a refused-row summary (the duplicate-rule losses row above stays Open until a live scale run shows 0 refused) | Scale test | Landed (#443, 34a6705b) |
| PR #444: `settingsConsole` namespaced section key | Namespace readiness S2 | Landed in #447 |
| Namespace registration, first package version | D-01, ADR-0001, D-87 | After a v1.0 pilot |

## Post-1.0 (plan 6.1, parked)

Memberships (G-22), Events, public volunteer sign-up (V-09), processor webhooks (X-08), donor scoring maturity and portfolios, multi-currency, AI-readiness pack, localization, CMDT Manager (landed), Analytics module (field utilization landed), data management 2 (C-36 and C-37 moved to v0.7 and landed), scheduled imports and connections (C-38; on hold until Brandon starts the next version, D-39), Advanced Territory Management (C-40) and Grid tool (C-41) (D-98).

Plan 6.1.1 (proposed, recorded 2026-10-14, nothing approved except C-40 and C-41): 17 ranked ideas for Brandon to decide, in order: DLRS compatibility; Grid tool; Summit Events compatibility; advanced duplicate management; Memberships Essentials compatibility; document builder; access explorer; Advanced Territory Management; map and radius search; field history and restore; data cleanup and standardization; website and portal tool; data dictionary and org documentation; engagement score; archiving and storage relief; forms and surveys; scheduled backup export. Plan 6.1.2 holds the comparable-tools research (18 categories). Plan 6.1.3 lists ideas considered and not recommended: CPQ, e-signature, marketing automation and mass email, phone systems (CTI), payment processing in Core, AI features that call a paid service.
