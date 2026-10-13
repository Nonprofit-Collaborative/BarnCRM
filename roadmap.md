# Roadmap

Purpose: planned work with status. Mirrors Section 6 of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Feature status detail lives in `docs/barncrm-features.md`.

Status as of 2026-10-13 (main at PR #222, squash 55e6b3d9). #219 landed batches 2 to 6, the Rollup Builder, test self-containment, v0.11 hardening, security follow-ups, C-37 part 2 and ADR-0092; PRs #201 to #218 are closed as landed. `main` deployed to `barn-npc` 2026-10-13 and passes. "Built" means built on a branch or open PR, not merged.

## Near-term queue (plan 6.0, owner decisions 2026-10-13)

1. Core quality pass (D-38, D-39): test, optimize, improve and simplify existing Core without removing functionality, before the non-core modules. Built in parallel:
   - Seven Core reviews; findings become fix batches.
   - Q-01 to Q-14 platform features (D-39; table below), branches `feature/q-NN-<slug>`.
   - SLDS 2 linter gate (PR #223; every component passes).
   - Console app with an app icon (`feature/console-app-icon`).
   - Field utilization on demand from its own tab (D-37, `feature/field-utilization-on-demand`).
   - Test self-containment (`fix/tests-self-contained`).
   - Rollup S9 after a clean engine comparison run (`feature/rollup-s9-remove-vendored`, not landed); S14 only if the scale test needs it; S15 to S17 spike.
2. On hold: C-38 scheduled imports and connections, until Brandon is ready to start the next version (D-39).
3. After the Core quality pass: the non-core modules, in plan Section 6 order.
4. Telemetry (C-26): deferred indefinitely (D-24, no AppExchange for now).
5. Real deploy to `mwdbdevsb`: on hold (owner, 2026-10-12).

| ID | Platform feature (Core quality pass, D-39) | Status |
|---|---|---|
| Q-01 | Real-time rollups off the save transaction | Started 2026-10-13 |
| Q-02 | RunRelevantTests and `isCritical`/`testFor` for fast gates | Started 2026-10-13 |
| Q-03 | Apex Cursors for large-volume jobs (also removes the 200-row import exceptions cap) | Started 2026-10-13 |
| Q-04 | Custom Notifications when long jobs finish | Started 2026-10-13 |
| Q-05 | `lightning/modal`, toast, alert and confirm | Started 2026-10-13 |
| Q-06 | GraphQL and Lightning Data Service reads | Started 2026-10-13 |
| Q-07 | Workspace API in the console app | Started 2026-10-13 |
| Q-08 | Dynamic Forms, Related Lists and Actions on every record page | Started 2026-10-13 |
| Q-09 | User Access Policies | Started 2026-10-13 |
| Q-10 | In-App Guidance | Started 2026-10-13 |
| Q-11 | Platform Cache | Started 2026-10-13 |
| Q-12 | Scratch org snapshots | Started 2026-10-13 |
| Q-13 | ApexGuru and Scale Center | Started 2026-10-13 |
| Q-14 | Agentforce-ready invocable actions (optional; approved) | Started 2026-10-13 |

## Iterations

| Iteration | Theme | Feature IDs | Status |
|---|---|---|---|
| v0.1 | Foundation and households | C-01, C-02, C-03, C-04 to C-11 | Shipped. Engineering open: namespace, first package version (deferred) |
| v0.2 | Giving core | G-01, C-13, C-14, G-02 to G-06, C-12 | Shipped. C-13 own engine S1 to S8, operations slice, Builder S10 to S13 landing (D-16, below) |
| v0.3 | Commitments, relationships, addresses | G-07, C-15, C-17, C-16, G-08 to G-11 | Shipped |
| v0.4 | Stewardship and receipting | G-12 to G-16, G-18, C-18 | Shipped. Receipt UX pass built (PRs #209 to #212) |
| v0.5 | Import 2.0, gift import, coexistence | C-19, G-17, C-22, G-23, C-20, C-21, G-24, import templates | Shipped. First-name guard built (PR #200 stack) |
| v0.6 | Connect | X-01, X-02, X-03, X-04, X-06, C-23, G-20, C-29 | Shipped (C-29 PR #163). X-07 Gift Transaction mirror planned next (moved here by plan 6.3) |
| v0.7 | Data management | C-32, C-33, C-34, C-35, C-36, C-37 (C-36 and C-37 moved from 1.x 2026-10-12), C-28, G-25 | All landing (C-37 part 1 only; bulk delete next) |
| v0.8 | Volunteers | V-01 to V-08; C-24 and C-30 | C-24, C-30 landing; V-items planned |
| v0.9 | Programs and Logic Models | P-01, P-02, P-04 to P-08, L-01 to L-04; C-39; G-19 if capacity | C-39 landing; rest planned |
| v0.10 | Funders and Nonprofit Cloud mirror | F-01 to F-08, X-07, L-06; X-05 | Planned |
| v0.11 | Hardening | Security review, scale test, C-31 (C-26 deferred indefinitely, D-24); tests run as permission-set users; vendored rollup tests removed by S9 | C-31 landing (ADR-0088 still Proposed); test self-containment landing |
| v0.12 | Beta | Beta cohort, C-27 | C-27 landing |
| v0.13 | AppExchange | Listing, v1.0 on approval | Planned |

## Cross-iteration work

| Item | Source | Status |
|---|---|---|
| Rename Open Impact to BarnCRM (labels, folders, package names) | Plan 11.3 item 6 | Merged (#181) |
| Rename `Nonprofit_*` API names to BarnCRM names | Plan 11.2 item 25 | Merged (#181) |
| Neutral Core follow-ups | C-29 | Merged (#181) |
| Engineering follow-ups 1, 3, 4, 5 (settings writers, dynamic Apex, CLI heap, review items) | Plan 11.3 | 1, 3, 4 merged (#181); 5 landing (#203 in #217) |
| Engineering follow-up 2 (log unrecognized checkbox values in imports) | Plan 11.3 | Planned, no branch |
| Own rollup engine and Rollup Builder | D-16, D-18, D-30 to D-32 | S1 to S8, operations slice, Builder S10 to S13 landing (ADR-0082, ADR-0083); S9 built, waits for the comparison run; S15 spike built; S14, S16, S17 planned |
| Flow templates | D-22 | Landing (ADR-0090) |
| Explicit Apex access modes (API 67.0 audit) | D-23 | Landing (`check-apex-access-modes.py`) |
| AI-ready invocable actions, portability checks (OpenAPI, model check) | D-23 | Landing |
| Gift keeps its household | D-20 | Landing (ADR-0070, ADR-0071) |
| Pledge payment picker in gift entry (G-25) | D-17 | Landing (ADR-0084) |
| CMDT Manager (plan 6.1 item 9) | D-25 | Landing (ADR-0085) |
| Field utilization (plan 6.1 item 10) | D-26, D-37 | In main (ADR-0086); on-demand rework from its own tab on `feature/field-utilization-on-demand` (D-37); `NightlyJobs` registration dropped |
| Tests run as permission-set users | D-33 | Landing; proof run without BarnCRM permission sets, then drop the assignment from `run-org-tests.sh` |
| "Data jobs" relabel | ADR-0047 | Not done |
| Namespace registration, first package version | D-01, ADR-0001 | Deferred |

## Post-1.0 (plan 6.1, parked)

Memberships (G-22), Events, public volunteer sign-up (V-09), processor webhooks (X-08), donor scoring maturity and portfolios, multi-currency, AI-readiness pack, localization, CMDT Manager (landing), Analytics module (field utilization landing), data management 2 (C-36 and C-37 part 1 moved to v0.7 and landing; bulk delete next), scheduled imports and connections (C-38; on hold until Brandon starts the next version, D-39).
