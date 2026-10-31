# BarnCRM: Claude Code instructions

Read the product plan before any work. Its canonical copy is the BMemory document `specification/open-impact-product-plan.md`; `docs/product-plan.md` is a mirror refreshed from it. When a document exists in BMemory, read and update the BMemory version first, then refresh the repo copy; never edit the repo copy alone. The plan is the single source of truth (Section 1.3 principles, Section 4 settled architecture, Section 9 working agreements, Section 12 decision log). Settled decisions are not re-opened without an ADR in `docs/architecture/decisions/`.

## Non-negotiables
- Namespace is deferred: keep `sfdx-project.json` namespace empty, never hard-code a prefix, never create 2GP package versions. CI runs `scripts/ci/check-namespace.sh`.
- No dependency on Person Accounts, Industries objects, OmniStudio, Data Cloud, Experience Cloud, or any standard object outside `packages/mirror` (Opportunity, Campaign, Case, Lead). CI runs `scripts/ci/check-standard-objects.sh`. Core must run on a Platform-only org (ADR-0013).
- Every admin setting lives in the in-app Nonprofit Settings console, never only in Setup.
- Salesforce Code Analyzer: zero high or critical findings before merge.
- No em dashes in documentation, labels, or commit messages. Use colons, commas, parentheses.
- Commits carry a DCO sign-off (`git commit -s`).

## Working rules
- Feature branches per feature ID (for example `feature/c-04-trigger-framework`), landed on `main` through a squash-merged landing batch, PRs under about 800 changed lines.
- Testing is batched (plan D-141, D-142): a feature PR runs Static checks, DCO, local Jest and the `scripts/ci` checks only, never an org gate. The integrator merges every ready branch into one `landing/batch-N` branch, runs the incremental gate (`scripts/org/run-org-tests.sh barn-sales`: relevant tests, no coverage floor) on its head, fixes failures there, squash-merges it only after it passes, and closes the included PRs as landed. Once a significant version's development is done and integrated, the release gate (`--release`: every test and the coverage floor) runs on `barn-sales` and `oi-test` in parallel, then the version is re-validated and deployed to `barn-npc` and `mwdbdevsb` (each `mwdbdevsb` deploy needs Brandon's approval), then QA and UX tested. Increments are tested as fast as possible; the version run is the end-to-end check.
- Canonical model (`docs/architecture/canonical-model.md`) is updated before any object or field is added.
- A new ADR written on a branch uses `ADR-NEXT`, never a chosen number: file `NEXT-title.md`, heading `# ADR-NEXT`, and every citation the same. The integrator assigns the number at merge. Picking a number on a branch collides when branches run in parallel, and renumbering afterwards is what rewrites correct citations in files that mention several ADRs.
- Admin-guide page (`docs/admin-guide/`) is written before the LWC.
- Overview (`docs/overview.md`), Admin Guide (`docs/admin-guide/`), User Guide (`docs/user-guide/`) and Testing Guide (`docs/testing-guide/`) are updated in the same PR as any feature added, changed, or removed; each index carries an "Applies to" line naming the main commit it was checked against.
- Feature catalog (`docs/barncrm-features.md`) is updated in the same PR as any feature added, changed, or removed.
- Release plan (plan 6.0a, 9.7, D-155) is kept up to date automatically: every newly approved item goes into a release (about 3 major, 3 to 6 minor enhancements); a move up or back that Brandon asks for is re-slotted and the affected releases rebalanced; statuses update as batches land; each landing batch covers 2 or 3 releases, and the release gate, `barn-npc` and `mwdbdevsb` (approval each time) deploys and QA and UX run once per batch.
- Before each batch is tested (plan 9.8), review the whole solution, all packages, for QA, UX and simplification (unused or deprecated elements, duplicate logic, mergeable components, performance); never remove functionality or usefulness; anything that would remove a capability or reverse a decision goes to Brandon.
- Prefer portable designs toward BarnCRM for WordPress on Pegwork (plan 9.9) where they cost little: browser-safe logic in framework-free JS modules, configuration as JSON, thin Apex controllers returning plain JSON; never at the cost of security, limits or the Section 4 architecture.
- Definition of done: plan Section 7.4. Review checklist: Section 9.4.

## Project docs
The four project docs live at the repo root:
- `architecture.md`: durable reference facts (repo rules, orgs by alias, credentials by name, package layout, gotchas). Updated in the same session a durable fact changes; points to `docs/architecture/` and `docs/contributor-guide/` for detail.
- `roadmap.md`: planned work with status. Mirrors BMemory plan Section 6.
- `changelog.md`: dated, newest-first log of every change, including each Claude change (merge, deploy, org change, BMemory edit, branch built), logged in the same session. Iteration reports stay in `docs/release-notes/`.
- `memory.md`: decisions, open questions and owner working agreements. Mirrors BMemory plan Sections 11 and 12; architecture decisions stay in ADRs.

`roadmap.md` and `memory.md` are refreshed from the BMemory plan whenever it changes (BMemory first, then these and `docs/product-plan.md`). Feature branches do not edit the root docs (they conflict); agents list entries in their reports and the integrator writes them.

Onboarding complete 2026-09-06. Root project docs added 2026-10-12.
