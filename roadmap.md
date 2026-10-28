# Roadmap

Purpose: planned work with status. Mirrors Section 6 of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Feature status detail lives in `docs/barncrm-features.md`.

Status as of 2026-10-28 (main at #648, squash 52909176; last full gate `oi-test` and `barn-sales` 3,934 of 3,934, coverage 93%, at batch 14 (#647, 9a10ef84); `mwdbdevsb` deployed at 9a10ef84). Landing batches 10 to 14 (#615, #619, #632, #638, #647) are in `main`: owner QA follow-ups, four apps, Duplicate Matching, address updates and history, Finish Setup, Rollup Builder DLRS parity (RB-A, RB-B), DLRS coexistence (RB-C) and ease of use (RB-D). Landed since 2026-10-13: #377 (Core quality pass, Q-01 to Q-14, rollup S9, data tools parity, Erase a person, console app); #401 to #408 (D-47 inventory); #411 to #426 (editions, neutral role names, feature switches, first-run setup); #438 (BarnCRM Rollup Builder module); #441 (Connect renamed Mirror); Volunteers V-01 to V-08 (#463 to #500); the 2026-10-20 and 2026-10-21 QA audit fixes (#506 to #526); 2026-10-25 and 2026-10-26: C-43 Preferred Phone, C-44 related-record matching (parts 1 to 3), the four guides (Overview, Admin, User, Testing) with the website /documentation/ page, the GitHub feedback path, the Testing Guide fixes (Core, Giving, Volunteers, read-only gaps, staff merges) and the final QA round (install and setup fixes, test independence from the deploying user, matching and UI guards, #547 to #565); landing batch 8 (#587, #570, #575) and batch 9 (#605) with the owner QA fixes (Settings sections, org fiscal year, Integrations page, list views, six-part organization address). The Testing Guide fixes and the final QA round are done. Core quality pass: complete. Open: the `barn-npc` release deploy (item 5 below), device mobile run, security review, namespace and first package version (after a v1.0 pilot, D-87). Planned after v1.0 and not scheduled: C-45, C-46, Corporate Hub, Portal Builder, Territory Management (C-40), LWC Builder, multi-brand (C-47), C-41 (items 9 to 13 below). Approved 2026-10-26 and landed in batches 10 to 13: Rollup Builder DLRS parity, Integrations page (C-48), Settings, address, app and gate decisions (D-124 to D-133; item 14 below). New modules approved 2026-10-26, release target TBD: Funders grant management, Scholarships and Outbound Grants, Event Management (item 15 below). "Landed" means in `main`.

## Near-term queue (plan 6.0, owner decisions 2026-10-13)

1. Core quality pass (D-38, D-39): test, optimize, improve and simplify existing Core without removing functionality, before the non-core modules. Built in parallel:
   - Seven Core reviews; findings become fix batches. Landed (#377); open review items listed in plan 11.3.
   - Q-01 to Q-14 platform features (D-39; table below). Landed (#377).
   - SLDS 2 linter gate (PR #223). Landed.
   - Console app with an app icon. Landed (#377).
   - Field utilization on demand (D-37, D-63). Landed (#377).
   - Test self-containment. Landed (#377).
   - Rollup S9 (vendored apex-rollup removed). Landed (#377). S14 only if the scale test needs it; S15 spike built; S16 and S17 deferred to after v1 (D-64), then started 2026-10-26 (D-124).
   - Inventory of unfinished Core work (D-47). Done 2026-10-14 (#401 to #408, including duplicate rule matching for any object, #405). Related-records import stays insert-only (post-1.0); org check of a parent and child file import passed 2026-10-15 on `oi-test` (Upsert by external ID, `Stewardship_Plan_Template__c` with `Stewardship_Plan_Step__c`, 3 parents and 7 children, dry run then commit, all linked, no errors).
   - Find, bulk update and duplicates fix batch. Landed (#377).
   - Approved review recommendations (D-48). Fix batches landed (#377); remainder per the feature catalog.
   - Affiliations in Core people imports, restored (D-49; C-32). Landed (#377).
   - Data tools parity (D-50): Data Manager hub, Org Optimizer, full results file, trial import, delete from a file of IDs, more transform steps, lookups and update matching on any Text, Email or Phone field, row rules, delimiter and worksheet choice, download before delete, retry rejects, server-side export (C-36 remainder), parent and child loads. Landed (#377). Not approved: seeding templates, files import. C-38 stays on hold.
   - Import tab label "Import", reached from Data Manager; Import and Bulk Update leave the navigation; Find stays (D-51). Landed (#377).
   - Erase a person in Core, with a Giving extension (D-52, D-86). Landed (#377).
   - Shipped import templates added at install and on upgrade (D-55). Landed (#377).
   - Deleting people never deletes their household (D-88, R-H12). Landed (#377).
   - Preferred Phone on a person, keeping the standard Phone in step (C-43, D-110; Brandon, 2026-10-25). Landed (#530; NPSP import mapping #535).
   - Related-record duplicate matching, steps 1 to 3: match sources, shipped Contact Point and `Address__c` sources, duplicate scan and import matching; no save-time warning (C-44, D-113; Brandon, 2026-10-25). Landed (#532 to #534, ADR-0133; first and last name agreement for every source #559).
   - Documentation upkeep as a standing rule (D-116): Overview, Admin Guide, User Guide and Testing Guide (219 scripts) landed 2026-10-25 (#537 to #548); the Testing Guide fixes (C1 to C12, U1 to U9) and the final QA round landed 2026-10-25 and 2026-10-26 (#545 to #565). Done.
   - Staff merges run in system mode, no Delete grants (D-117). Landed (#551, ADR-0134).
2. On hold: C-38 scheduled imports and connections, until Brandon is ready to start the next version (D-39).
3. After the Core quality pass: the non-core modules, in plan Section 6 order.
4. Telemetry (C-26): deferred indefinitely (D-24, no AppExchange for now).
5. `mwdbdevsb`: deployed 2026-10-14 at the owner's request (Core at e3f2db58, then plus #411 to #413); ask before every further deploy. Deployed again 2026-10-17 (owner approved) at cf861610: Core plus Rollup Builder; 2026-10-20 at ec8cf042; 2026-10-25 at 71e97ead; 2026-10-28 at 9a10ef84 (Core and Rollups, sample data loaded, Brandon Mead and Michelle Hansen have the BarnCRM permission sets). Ask before every further deploy; never change org settings (plan 9.6).
6. Release prerequisites (namespace, Dev Hub, steward entity): after a v1.0 pilot (D-87).
7. Rename Connect to Mirror (D-103, ADR-0126): Landed (#441, 98583f12, ADR-0126).
8. Test org cleanup of old Connect metadata (destructive deploy; owner approved): `oi-test` done (176 components); `oi-pa` done (module record, then 175 components); `barn-core` had no Connect module (nothing to remove); `barn-npc` done 2026-10-15 (Mirror deployed from main 702616e6 first, then 176 components). Done on all four test orgs.
9. New optional modules approved 2026-10-25 (Brandon), not yet scheduled (plan 6.0 item 4): BarnCRM Contact Point Sync (C-45, D-111) and BarnCRM Address Verification (C-46, D-112). Each needs a new ADR before build.
10. New optional modules for both editions, depending on Core only, approved 2026-10-25 (D-118) and amended 2026-10-26 (D-120), planned after the Core quality pass and after C-45 and C-46, not scheduled to an iteration; each needs a new ADR before build:
    - Corporate Hub (plan 5.8, CH-01 to CH-14): document and policy library, policy acknowledgments, compliance calendar, shipped compliance templates, board governance.
    - Portal Builder (plan 5.9, PB-01 to PB-05): Board, Volunteer, Service and Partner portal templates; option B (on-platform Salesforce Site with BarnCRM's own login layer, no added license cost) is required (D-120); confirming it as the build path waits on a terms check (plan 11.2 item 30, open).
11. BarnCRM Territory Management (C-40): the former Advanced Territory Management Super Tool, now an optional module for both editions depending on Core only (D-120, amends D-98); planned after v1.0, not scheduled.
12. BarnCRM LWC Builder (plan 5.10, LB-01 to LB-06): drag-and-drop grid canvas, one packaged runtime renderer reading saved definitions in user mode; optional module for both editions depending on Core only (D-120); planned after v1.0, not scheduled.
13. Multi-brand management (C-47, D-119, D-120): a Core feature for both editions, planned after v1.0, not scheduled: brands under Legal Entity records, many-to-many brand assignment, brand-aware receipts and letters, optional brand-restricted visibility (off by default; plan 11.2 item 31 resolved); the canonical model is updated before any object is added; the sharing code needs an ADR.
14. Approved 2026-10-26 (Brandon), plan 6.0 item 6. Done (landed in batches 10 to 13, #615, #619, #632, #638): Rollup Builder DLRS parity or better (RB-A to RB-D: parity, Instant Totals, DLRS coexistence and import, ease of use), S16 and S17 included, Integrations page, four apps, Duplicate Matching tool, Finish Setup safety net, address updates and history, list views, Field Utilization Snapshot History and Data Manager clarity. Decisions: (D-124; standard objects describe only, ADR-0136; admin-deployed one-line generated triggers, D-132, ADR-0138, one-click deploy deferred); Integrations page, roadmap only (C-48, D-125); Settings rules and pages (D-126); fiscal year and Organization Name read from Setup, six-part organization address (D-127, ADR-0135); households and addresses (D-128); rollup mode defaults (D-129); four apps, Duplicate Matching tool, Finish Setup safety net, list views and default configuration records (D-130); landing batches, light gate, `barn-sales` gate org (D-131); Field Utilization Snapshot History and Data Manager clarity (D-133).
15. New and expanded modules approved 2026-10-26 (Brandon), after Core QA and the current module round, release target TBD, not v1.0 (plan 6.0 item 7); each needs a new ADR: Funders Grant Finder and grant management (F-09 to F-13, D-121, Nonprofit Edition); Scholarships and Outbound Grants (plan 5.11, SG-01 to SG-08, PB-06, D-122, Nonprofit Edition proposed; reverses the grantmaking non-goal); Event Management (plan 5.12, EV-01 to EV-11, PB-07, D-123, both editions proposed; replaces the post-1.0 Events package, Summit compatibility kept).
16. Integrations and migrations (plan 6.0 item 8, 6.1.4, D-125): wait until Core QA and development are done, preferably after v1.0; top 10 are post-1.0 items; decisions O-1 to O-12 open (plan 11.2 item 32).

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
| v0.8 | Volunteers | V-01 to V-08; C-24 and C-30 | Started 2026-10-17 (D-104): built and tested unmanaged; install-link testing waits for the first package versions. C-24, C-30 landed (#219). Design landed (#456, #457); V-00 (#459), V-01 data model (#463, #465), V-06 Core import templates (#462) and V-02 domain (#469, #470) landed; V-01 to V-08 built, reviewed and landed on main: plumbing PR7 (#466 to #468), V-06 hours import (#473), V-03 totals (#481), rollup engine fix (#487), landing batch (#493: V-02 UI, V-03 totals and dashboard, V-04, V-05, V-07, V-08), hardening and QA fixes (#500) and lifecycle (#498: erasure and household dependents, five Health Check findings, sample data); V-08 uses Volunteers' own letter generator. Status: built and tested unmanaged on oi-test and oi-pa (3,443 of 3,443 on oi-pa, 93% coverage); QA and UX pass done; install-link testing waits for the first package versions. Volunteers is nonprofit-only (D-99) |
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
| Own rollup engine and Rollup Builder | D-16, D-18, D-30 to D-32 | S1 to S9, operations slice, Builder S10 to S13 landed (ADR-0082, ADR-0083); S15 spike built; S14 planned; DLRS parity (RB-A to RB-D, D-124, amends D-64, ADR-0136, ADR-0138) Done: landed in batches 11 to 13 (#619, #632, #638); S16, S17 included |
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
| Territory Management (C-40, optional module since D-120) and Grid tool (C-41) | D-98, D-120 | Planned, after v1.0 |
| Multi-brand management (C-47), LWC Builder module (LB-01 to LB-06), Corporate Hub (CH-01 to CH-14), Portal Builder (PB-01 to PB-05) | D-118, D-119, D-120 | Planned, after v1.0 (Core quality pass, C-45 and C-46 first for the two modules), not scheduled |
| Follow-up: household catch-up for person accounts (turning Household Upkeep on catches up contacts only) | #426 review | Done (#447) |
| Follow-up: scale test duplicate-rule losses (the load lost 309 households and 1,328 contacts to the standard duplicate rules; failed-*.csv not kept; root cause confirmed 2026-10-15: Bulk API 2.0 refuses duplicates with `DUPLICATES_DETECTED`; fix landed in #443; closes when a live scale run shows 0 refused) | Scale test | Done (2026-10-17 live run on `oi-test`, 0 refused) |
| Follow-up: namespace readiness for the module split (module pages use Core components cross-package: `settingsConsole`, `c/workspaceTabs`; module tests use Core `@TestVisible` privates; module `appUrl` namespace). Review result, blocking before the first package version: B1 19 module trigger handlers `@NamespaceAccessible` (done, #447); B2 production module code calling unannotated Core members (`OrgShapeDetector`, `ErrorLogger.SEVERITY_*`, `RollupFilterParser` members; done, #447); B3 module tests using Core `@TestVisible` privates (done, #450, public test hooks); B4 module tests using unannotated Core test factories (done, #450); B5 cross-package inner-class field access to verify (done, #450); B6 CI checks for cross-package visibility and dynamic lookups (done, #447). Should fix: S1 `rollupBuilder` imports unexposed `c/workspaceTabs` (done, #450, local `rollupTabLabel`); S2 `settingsConsole` reads only `c__section` (done, #447); S3 explicit constructors on 8 extension classes (done, #447); S4 a Mirror test uses Giving's protected label (done, #450); S5 check the `/lightning/app/Fundraising` link (open; the Hub Modules link opens the app without a namespace, waits on a click in `oi-test`); S6 more CI checks (done, #451, #452). B3 to B5 are confirmed at the first real package version (owner decided 2026-10-17 not to run a throwaway-namespace build) | Plan 4.10, D-101 | B1 to B6 and S1 to S4, S6 done (#447, #450, #451, #452); S5 open |
| Follow-up: Core-only coverage: HouseholdSelector 75%, CustomPermissionSelector 77%, HouseholdWriter 78%, DataManagerController 79%, PersonErasureController 79% from Core and Rollups tests alone on `oi-test`; check on a Platform-only org before the next client deploy (four other classes fixed in #508) | Plan 11.3 item 10 | Done 2026-10-20 (#508 and #511): all nine classes above 75% from Core and Rollups tests alone; the Platform-only org check is still to do before the next client deploy |
| PR #443: scale loader allow-save REST insert for Accounts and Contacts, plus a refused-row summary (the duplicate-rule losses row above stays Open until a live scale run shows 0 refused) | Scale test | Landed (#443, 34a6705b) |
| PR #444: `settingsConsole` namespaced section key | Namespace readiness S2 | Landed in #447 |
| Namespace registration, first package version | D-01, ADR-0001, D-87 | After a v1.0 pilot |

## Post-1.0 (plan 6.1, parked)

Memberships (G-22), Event Management module (replaces the Events package, D-123), Funders Grant Finder and grant management (F-09 to F-13, D-121), Scholarships and Outbound Grants module (D-122), public volunteer sign-up (V-09), processor webhooks (X-08), donor scoring maturity and portfolios, multi-currency, AI-readiness pack, localization, CMDT Manager (landed), Analytics module (field utilization landed), data management 2 (C-36 and C-37 moved to v0.7 and landed), scheduled imports and connections (C-38; on hold until Brandon starts the next version, D-39), Territory Management module (C-40, D-120) and Grid tool (C-41) (D-98), multi-brand management (C-47, D-119, D-120), LWC Builder module (D-120), Corporate Hub and Portal Builder modules (D-118), Forms module (C-42; owner request 2026-10-17, not scheduled; needs a decision log entry and a guest-user security design), BarnCRM for WordPress (future edition on Brandon's WordPress platform plugin, not scheduled; owner request 2026-10-17).

Plan 6.1.4 (integration and migration review, 2026-10-26, D-125; post-1.0, after Core QA and development): Migration Assistant framework; NPC Party Relationship Groups to households; V4S to Volunteers plus public sign-up; NPC gifts to Giving; NPSP migration kit; Stripe receiver and Zapier; DonorPerfect, Bloomerang and Little Green Light templates; DLRS and NPSP rollup import; PMM to Programs; Integrations page (C-48, roadmap only, being built now). Mass Action Scheduler is never added; overlapping tools (V4S, PMM, Outbound Funds) shown only when installed; complementary apps (Summit Events, Community Commons Membership, DLRS) may be listed always.

Plan 6.1.1 (proposed, recorded 2026-10-14, nothing approved except C-40, C-41, C-47, the LWC Builder module, and on 2026-10-26 item 1 DLRS parity (D-124) and item 3 Event Management (D-123)): 19 ranked ideas for Brandon to decide, in order: DLRS compatibility; Grid tool; Summit Events compatibility; advanced duplicate management; Memberships Essentials compatibility; document builder; access explorer; Territory Management (module); map and radius search; field history and restore; data cleanup and standardization; website and portal tool (superseded by Portal Builder, D-118); data dictionary and org documentation; engagement score; archiving and storage relief; forms and surveys; scheduled backup export; multi-brand management (C-47); LWC Builder (D-120). Plan 6.1.2 holds the comparable-tools research (18 categories). Plan 6.1.3 lists ideas considered and not recommended: CPQ, e-signature, marketing automation and mass email, phone systems (CTI), payment processing in Core, AI features that call a paid service.
