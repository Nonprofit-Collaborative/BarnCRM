# Roadmap

Purpose: planned work with status. Mirrors Section 6 of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Feature status detail lives in `docs/barncrm-features.md`.

Status as of 2026-10-12 (main at PR #183). "Built" means built on a branch or open PR, not merged.

## Near-term queue

1. Land the rename stack (PRs #181 to #200) at c20336ef once the org gate passes.
2. Land the 12 sibling PRs (#201 to #212) as one batch.
3. Open PRs for the branches built 2026-10-12: C-32 import matching, C-34 Find, hub rebuild, C-24 Module Manager, C-30 suite choice, C-27 what's new, C-31 migration kit, Flow templates, C-39 interaction notes, UX core, rollup S1 to S5, AI-ready actions, portability checks, explicit access modes, household fixes (keep households with gifts, import undo), pledge payment picker.
4. Rollup engine (D-16, D-18): S6 in progress, then S7 to S17 and the operations slice after S8.
5. Telemetry (C-26): deferred indefinitely (D-24, no AppExchange for now).
6. Rollup trigger coverage on admin objects (S16) needs a production-type org to confirm.

## Iterations

| Iteration | Theme | Feature IDs | Status |
|---|---|---|---|
| v0.1 | Foundation and households | C-01, C-02, C-03, C-04 to C-11 | Shipped. Engineering open: namespace, first package version (deferred) |
| v0.2 | Giving core | G-01, C-13, C-14, G-02 to G-06, C-12 | Shipped. C-13 engine being replaced (D-16, below) |
| v0.3 | Commitments, relationships, addresses | G-07, C-15, C-17, C-16, G-08 to G-11 | Shipped |
| v0.4 | Stewardship and receipting | G-12 to G-16, G-18, C-18 | Shipped. Receipt UX pass built (PRs #209 to #212) |
| v0.5 | Import 2.0, gift import, coexistence | C-19, G-17, C-22, G-23, C-20, C-21, G-24, import templates | Shipped. First-name guard built (PR #200 stack) |
| v0.6 | Connect | X-01, X-02, X-03, X-04, X-06, C-23, G-20, C-29 | Shipped (C-29 PR #163). X-07 Gift Transaction mirror planned next (moved here by plan 6.3) |
| v0.7 | Data management | C-32, C-34 built; C-33, C-35 planned | In progress |
| v0.8 | Volunteers | V-01 to V-08; C-24 and C-30 built | C-24, C-30 built; V-items planned |
| v0.9 | Programs and Logic Models | P-01, P-02, P-04 to P-08, L-01 to L-04; C-39 built; G-19 if capacity | C-39 built; rest planned |
| v0.10 | Funders and Nonprofit Cloud mirror | F-01 to F-08, X-07, L-06; X-05 | Planned |
| v0.11 | Hardening | Security review, scale test, C-31 (C-26 deferred indefinitely, D-24) | C-31 built |
| v0.12 | Beta | Beta cohort, C-27 | C-27 built |
| v0.13 | AppExchange | Listing, v1.0 on approval | Planned |

## Cross-iteration work

| Item | Source | Status |
|---|---|---|
| Rename Open Impact to BarnCRM (labels, folders, package names) | Plan 11.3 item 6 | Built: PRs #184 to #187, #195 |
| Rename `Nonprofit_*` API names to BarnCRM names | Plan 11.2 item 25 | Built: PRs #198 to #200 |
| Neutral Core follow-ups | C-29 | Built: PRs #194 to #197 |
| Engineering follow-ups 1, 3, 4, 5 (settings writers, dynamic Apex, CLI heap, review items) | Plan 11.3 | Built: PRs #188 to #193, #203 |
| Engineering follow-up 2 (log unrecognized checkbox values in imports) | Plan 11.3 | Planned, no branch |
| Own rollup engine and Rollup Builder | D-16, D-18 | S1 to S5 built; S15 spike built; S6 in progress; S7 to S17 planned |
| Flow templates | D-22 | Built |
| Explicit Apex access modes (API 67.0 audit) | D-23 | Built (`fix/explicit-access-modes`) |
| AI-ready invocable actions, portability checks (OpenAPI, model check) | D-23 | Built |
| Gift keeps its household | D-20 | Built (`fix/keep-households-with-gifts`, import undo fix) |
| Pledge payment picker in gift entry | D-17 | Built (`feature/gift-entry-pays-installment-1` to `-3`) |
| Namespace registration, first package version | D-01, ADR-0001 | Deferred |

## Post-1.0 (plan 6.1, parked)

Memberships (G-22), Events, public volunteer sign-up (V-09), processor webhooks (X-08), donor scoring maturity and portfolios, multi-currency, AI-readiness pack, localization, CMDT Manager (proposed), Analytics module (proposed), data management 2 (C-36, C-37), scheduled imports and connections (C-38).
