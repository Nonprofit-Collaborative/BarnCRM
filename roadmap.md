# Roadmap

Purpose: planned work with status. Mirrors Section 6 of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Feature status detail lives in `docs/barncrm-features.md`.

Status as of 2026-10-12 (main at PR #181, squash 87a00cb9). "Built" means built on a branch or open PR, not merged. "Landing" means in landing PR #217 (batch 5, which contains batches 2 to 4, PRs #214 to #216) or #218 (batch 6), being gated.

## Near-term queue

1. Gate and squash-merge #217, then #218; close #214 to #216 and the constituent PRs as landed.
2. Rollup S9: comparison run (`RollupEngineComparison`, sample data, `oi-test`, from main after the Builder lands), then land `feature/rollup-s9-remove-vendored`.
3. Deploy to `barn-npc` (approved once the batches, Builder and test self-containment merge), assign BarnCRM permission sets, run tests.
4. C-35 adopts the C-37 transforms, then C-37 bulk delete. Then C-38 scheduled imports, rollup S14 (only if the scale test needs it), S15 to S17 (S16 coverage confirmed on `barn-npc`), v0.11 hardening.
5. Telemetry (C-26): deferred indefinitely (D-24, no AppExchange for now).
6. Real deploy to `mwdbdevsb`: on hold (owner, 2026-10-12).

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
| Field utilization (plan 6.1 item 10) | D-26 | Landing (ADR-0086); register `FieldUtilizationJob` in `NightlyJobs` next |
| Tests run as permission-set users | D-33 | Landing; proof run without BarnCRM permission sets, then drop the assignment from `run-org-tests.sh` |
| "Data jobs" relabel | ADR-0047 | Not done |
| Namespace registration, first package version | D-01, ADR-0001 | Deferred |

## Post-1.0 (plan 6.1, parked)

Memberships (G-22), Events, public volunteer sign-up (V-09), processor webhooks (X-08), donor scoring maturity and portfolios, multi-currency, AI-readiness pack, localization, CMDT Manager (landing), Analytics module (field utilization landing), data management 2 (C-36 and C-37 part 1 moved to v0.7 and landing; bulk delete next), scheduled imports and connections (C-38).
