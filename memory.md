# Memory

Purpose: project context, decisions and rationale not derivable from code or git. Mirrors Sections 11 (open questions, parking lot) and 12 (decision log) of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Architecture decisions are recorded as ADRs in `docs/architecture/decisions/`; this file points to them rather than copying them.

Last refreshed from BMemory 2026-10-12.

## Decision log (plan Section 12)

| ID | Date | Decision |
|---|---|---|
| D-01 | 2026-09-06, 2026-09-23, 2026-10-12 | Product name: "Open Impact" working title, then BarnCRM (cleared 2026-10-12); namespace deferred (ADR-0046) |
| D-02 | 2026-09-06, amended 2026-09-23 | Second-generation managed packages with one namespace for the listing; unlocked packages until then (ADR-0046) |
| D-03 | 2026-09-06 | Core plus separate module packages; feature flags for minor behavior |
| D-04 | 2026-09-06 | Custom `Gift__c` is the gift record; Opportunity and Gift Transaction are optional mirrors in Connect |
| D-05 | 2026-09-06 | Household is an Account record type with two membership modes behind one service |
| D-06 | 2026-09-06 | Settings: hierarchy custom settings for toggles, custom objects for lists, custom metadata for shipped defaults |
| D-07 | 2026-09-06 | `sf` CLI plus GitHub Actions; CumulusCI optional later |
| D-08 | 2026-09-22 | License Apache-2.0 |
| D-09 | 2026-09-06 | No Person Account, Industries, OmniStudio, Data Cloud or Experience Cloud dependency |
| D-10 | 2026-09-06 | Receipts immutable (void and reissue); refunds are negative linked gifts |
| D-11 | 2026-09-06, superseded 2026-10-12 | Vendor a rollup library before building; superseded by D-16 |
| D-12 | 2026-09-06 | Trunk-based development, squash merges, `main` always releasable |
| D-13 | 2026-09-23 | Data management scope and phasing: in-org import, Find and bulk update; new v0.7 iteration (ADR-0047) |
| D-14 | 2026-09-24 | Cancelled status for unpaid Pending gifts (amends G-04) |
| D-15 | 2026-09-24 | Second long-lived test org `oi-pa` (Person Accounts), gated locally |
| D-16 | 2026-10-12 | BarnCRM owns its rollup engine; apex-rollup removed after a clean comparison run (new ADR, supersedes ADR-0015) |
| D-17 | 2026-10-12 | Import matches by record ID, "match only" option, custom fields in the wizard (C-32); pledge payment picker in gift entry |
| D-18 | 2026-10-12 | Rollup comparison recommendations: slices S15 to S17, operations slice after S8, deferred items listed |
| D-19 | 2026-10-12 | Confidential interaction notes not built; notes stay completed Tasks |
| D-20 | 2026-10-12 | A gift stays credited to the household it was given to (amends R-G2; new ADR) |
| D-21 | 2026-10-12 | "What's new" notes (C-27) are labelled by release; first is "0.6" |
| D-22 | 2026-10-12 | New ADRs accepted: migration kit, Flow templates, suite choice first, Module Manager, interaction notes as Tasks, settings record pickers, Health Check schedules nightly jobs |
| D-23 | 2026-10-12 | Platform capabilities: keep LWC, audit API 67.0 access modes, Apex Cursors, GraphQL in new screens, AI-ready action descriptions, cheap portability steps; avoid Data 360, Heroku AppLink, Functions and similar |

## Open questions still open (plan Section 11.2)

- 1: Namespace registration (deferred; blocks package versions only).
- 3: Dev Hub type (Partner Business Org or Developer Edition with a planned migration).
- 4: Steward entity.
- 7: Telemetry (C-26): include opt-in anonymous usage, default off. Awaiting owner input.
- 12: Remove the three permission set groups that contain only the staff set before the first package version.
- 14: Shipped import templates copied at install or at first use.
- 16: Per-automation switches: optional end date or stay off until turned on.
- 19 to 22: Opportunity mirror defaults (NPSP mode direction, deleted gift, double thanks, record-type filter).
- 23: A separate nonprofit app in Giving.
- 24: Neutral labels for nonprofits (names become "BarnCRM ..." in the rename).
- 27: Plan corrections awaiting approval.
- Provisional (confirm when the owner tests): 8 primary person through the person contact, 9 guards only, 10 membership-mode switch guard only.

## Parking lot (plan Section 11.3)

Donor portal and online giving; email marketing beyond export; grantmaking as a funder; peer-to-peer; wealth screening; text-to-give; multi-org roll-up reporting; an in-app AI assistant; confidential interaction notes (D-19); Nonprofit Cloud household migration (X-09, until an org asks). Engineering follow-ups (plan 11.3, recorded 2026-09-27): 1 settings writers, 3 dynamic Apex, 4 CLI heap, 5 small review items and 6 BarnCRM rename are built on open PRs (see `roadmap.md`); 2 (log unrecognized checkbox values in imports) has no branch yet.

## Working agreements (owner instructions)

- Merge authority (2026-09-23): squash-merge without asking when every required check (Static checks, DCO sign-off, Org tests (local)) is green on the head, threads are resolved and nothing is open; hold and ask on an owner question, a failing or skipped check, or a design doubt. Report merges afterwards.
- Test orgs (2026-09-23, 2026-09-24, 2026-10-12): only `oi-test`, `oi-pa` and `barn-core`; any other org needs approval; recreating `oi-pa` on expiry is pre-approved; agents share each org through a lock, one deploy or test run at a time.
- Sandbox `mwdbdevsb` (2026-10-12): real built-out org; never the default; check-only first; ask before every deploy; no data changes, destructive deploys or scheduled jobs without approval; Core only.
- Gate from a clean worktree (2026-09-24): run `scripts/org/run-org-tests.sh` only from a dedicated detached worktree at the pushed head.
- Naming (2026-10-12): short prefix is "barn-" (for example `barn-core`), never "bc-".
- Synced folder: never `git add -A`; stage by path; check for ` 2.` files before pushing.
- BMemory writes go through the BMemory MCP gateway, not git (2026-10-12); `_meta/` paths need asking.
- Root project docs (2026-10-12): `changelog.md` logs every Claude change in the same session; `roadmap.md` and this file mirror the BMemory plan.
