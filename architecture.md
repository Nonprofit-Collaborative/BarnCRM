# Architecture: durable reference facts

Purpose: environments, access, layout and gotchas for BarnCRM. Reference facts only, not a task log (work done goes in `changelog.md`). Check here before re-querying a live system.

Last verified 2026-10-12.

## Pointers

- Canonical data model: `docs/architecture/canonical-model.md` (updated before any object or field change).
- Architecture decision records: `docs/architecture/decisions/` (index in its `README.md`).
- Toolchain and namespace rules: `docs/contributor-guide/environment.md`.
- CI checks, org test gate, test orgs, secrets: `docs/contributor-guide/ci.md`. Scratch org shapes: `docs/contributor-guide/scratch-orgs.md`.
- Product plan: BMemory `specification/open-impact-product-plan.md` (canonical), mirrored at `docs/product-plan.md`.
- Feature catalog: `docs/barncrm-features.md`.

## Repository and branches

- GitHub: `Nonprofit-Collaborative/BarnCRM`, default branch `main`.
- Feature branch per feature ID (for example `feature/c-04-trigger-framework`), squash-merged to `main`; PRs under about 800 changed lines, stacked as `-1`, `-2` when larger.
- Ruleset on `main` requires the status `Org tests (local)`, posted by `scripts/org/run-org-tests.sh`. Run it from a clean detached worktree at the pushed head, with `NODE_OPTIONS=--max-old-space-size=8192` (the sf CLI runs out of heap reading about 2,200 results).
- Worktrees live under `~/worktrees/BarnCRM/<branch>`; the main checkout (in a synced folder) is not used for work.
- Commits carry a DCO sign-off (`git commit -s`).

## Salesforce orgs (by alias)

| Alias | What it is | Rules |
|---|---|---|
| `devhub` | Dev Hub | Creates scratch orgs |
| `oi-test` | Default scratch test org, Person Accounts shape | Named by the `SF_TEST_ORG_AUTH_URL` secret |
| `oi-pa` | Person Account scratch org (D-15) | Expires 2026-10-24; recreation pre-approved |
| `barn-core` | Third scratch test org, Sales Cloud shape, for Core-only runs | Approved 2026-10-12 (alias was `bc-core`) |
| `mwdbdevsb` | Sandbox of a real, built-out org, for Community Suite (Core without Giving) tests; alias was `mwdsb` until 2026-10-12 | Never the default; check-only first; ask the owner before every deploy; no data changes, destructive deploys or scheduled jobs without approval; Core only |

Any other org (including other mwd sandboxes) needs owner approval. Agents share each scratch org one deploy or test run at a time, through a lock in the session scratchpad. Scratch org definitions: `config/scratch-defs/` (`person-accounts.json`, `sales-cloud.json`, `platform-only.json`, `npsp.json`, `nonprofit-cloud.json`).

## Credentials (names and locations only, never values)

- GitHub Actions secrets: `SF_DEVHUB_AUTH_URL` (Dev Hub) and `SF_TEST_ORG_AUTH_URL` (the `oi-test` org). Setup and rotation steps in `docs/contributor-guide/ci.md`.
- Local org access: the sf CLI's own auth store, by alias. Org auth URLs are credentials: never read, print or write them.

## Package layout

- `packages/core` (neutral Core; includes `packages/core/vendor/apex-rollup`, MIT, vendored as source), `packages/giving` (depends on Core), `packages/connect` (depends on Core and Giving; the only package that may touch Opportunity, Campaign, Case, Lead). `packages/volunteers`, `programs`, `funders` are placeholders.
- Core never references Giving or Connect; no dependency on Person Accounts, Industries, OmniStudio, Data Cloud or Experience Cloud (ADR-0013).
- Deploys to an org run in stages through `scripts/org/deploy-packages.sh`.
- Namespace deferred (ADR-0001): `sfdx-project.json` namespace stays empty, no hard-coded prefix, no package versions; prefixed names come from `NamespaceUtil`.

## CI checks

- Offline checks live in `scripts/ci/` (namespace, standard objects, ADRs, canonical model, custom metadata, labels, help links, permission sets, setting defaults, object allowlist, reachable components, record pages, symlinks, offline Apex compile). Full list and behavior: `docs/contributor-guide/ci.md`.
- Also: `npm run lint`, `npm run prettier:verify` (Markdown is excluded from Prettier), `npx sfdx-lwc-jest`, Salesforce Code Analyzer with zero high or critical findings.

## Gotchas

- Synced folder spawns `name 2.ext` duplicates, including inside `.git/`: never `git add -A` or `git add .`; stage by path or `git add -u`.
- `push.default` is `upstream`: a worktree branch created from a tracking base pushes to the base. Create with `--no-track`, push with an explicit refspec (`git push -u origin <b>:refs/heads/<b>`). A bare push moved PR #200's branch and the rollup S3 branch (2026-10-12).
- `Setting_Definition__mdt` field defaults are not re-applied on redeploy, so every row names `Settings_Object__c` explicitly; enforced by `check-setting-object-explicit.py` (commit c20336ef, 2026-10-12).
- Renaming a permission set leaves the old one in an org with the same label, which blocks deploys until the old ones are deleted (hit on `oi-test` and `barn-core`, 2026-10-12).
- `sf project deploy validate` rejects `NoTestRun`; use `sf project deploy start --dry-run` instead.
- API 67.0 defaults Apex to user mode and `with sharing`; state access modes explicitly (`check-apex-access-modes.py` on `fix/explicit-access-modes`, 2026-10-12).
- A new ADR on a branch uses the placeholder file `NEXT-<title>.md` and never a chosen number; the integrator numbers it at merge (see the repo `CLAUDE.md`).
