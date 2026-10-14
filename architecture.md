# Architecture: durable reference facts

Purpose: environments, access, layout and gotchas for BarnCRM. Reference facts only, not a task log (work done goes in `changelog.md`). Check here before re-querying a live system.

Last verified 2026-10-14.

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
| `oi-pa` | Person Account scratch org (D-15) | Expires 2026-10-24; recreation pre-approved. Cleaned 2026-10-12 (owner approved): old `Nonprofit_Admin` assignment, the 4 `Nonprofit_*` permission sets and their group deleted |
| `barn-core` | Third scratch test org, Sales Cloud shape, for Core-only runs | Approved 2026-10-12 (alias was `bc-core`). Expires 2026-10-15; recreation pre-approved (owner, 2026-10-13) |
| `barn-npc` | Nonprofit Cloud trial, production-type, Person Accounts on, API 68.0; for rollup S16 coverage and Nonprofit Cloud coexistence tests | Never the default. Enabled 2026-10-12 (owner approved): Fundraising_Admin and Program_Management_Administrator permission set groups on the admin; Contacts to Multiple Accounts on; Industries settings Fundraising, Gift Entry Grid, Group Membership, Program and Benefit Management on (irreversible). BarnCRM deploy approved once landing batches, Builder S10 to S14 and test self-containment merge |
| `mwdbdevsb` | Sandbox of a real, built-out org, for Standard Edition (Core without Giving) tests; alias was `mwdsb` until 2026-10-12; Midwest Dreamin' sandbox `brandondev`, connected 2026-10-12, instance API 68.0 | Never the default; check-only first; ask the owner before every deploy; no data changes, destructive deploys or scheduled jobs without approval; Core only. Real deploy on hold (owner, 2026-10-12). Lacks the Data Protection and Privacy objects, so vendored apex-rollup tests do not compile there |

Any other org (including other mwd sandboxes) needs owner approval. Agents share each scratch org one deploy or test run at a time, through a lock in the session scratchpad. Scratch org definitions: `config/scratch-defs/` (`person-accounts.json`, `sales-cloud.json`, `platform-only.json`, `npsp.json`, `nonprofit-cloud.json`).

## Credentials (names and locations only, never values)

- GitHub Actions secrets: `SF_DEVHUB_AUTH_URL` (Dev Hub) and `SF_TEST_ORG_AUTH_URL` (the `oi-test` org). Setup and rotation steps in `docs/contributor-guide/ci.md`.
- Local org access: the sf CLI's own auth store, by alias. Org auth URLs are credentials: never read, print or write them.

## Package layout

- `packages/core` (neutral Core; the vendored apex-rollup tree, `RollupAdapter` and `RollupEngineComparison` were deleted by rollup S9, #377), `packages/giving` (depends on Core), `packages/connect` (depends on Core and Giving; the only package that may touch Opportunity, Campaign, Case, Lead). `packages/volunteers`, `programs`, `funders` are placeholders.
- Core never references Giving or Connect; no dependency on Person Accounts, Industries, OmniStudio, Data Cloud or Experience Cloud (ADR-0013).
- Deploys to an org run in stages through `scripts/org/deploy-packages.sh`.
- Namespace deferred (ADR-0001): `sfdx-project.json` namespace stays empty, no hard-coded prefix, no package versions; prefixed names come from `NamespaceUtil`.

## CI checks

- Offline checks live in `scripts/ci/` (namespace, standard objects, ADRs, canonical model, custom metadata, labels, help links, permission sets, setting defaults, object allowlist, reachable components, record pages, symlinks, offline Apex compile, Apex access modes, Flow templates, Person Account fields, module objects). Full list and behavior: `docs/contributor-guide/ci.md`.
- `check-metadata-lengths.py`: description and label lengths, reserved type names, duplicate layout actions, FlexiPage visibility rules on lookups, related list columns (added 2026-10-12 after deploy errors).
- `check-tests-run-as.py`: every test method runs inside `System.runAs(TestUsers.admin())` or `TestUsers.adminWith('<permission set>')`, or is a recorded opt-out (12). `TestUsers` makes a user on the running user's profile holding the BarnCRM permission sets, so tests pass without the gate assigning permission sets to the deploying user.

## Runtime facts

- Rollups: since S8 BarnCRM's engine is the only path. Full runs are `RollupFullRecalcBatch` (one at a time, `runningJobId`); chunk size comes from stored COUNT totals, with fixed constants (row budget 30,000, follow-up chunks a quarter, at most 10,000 held back), not admin settings. Stopped chunks retry through `RollupRecalcErrorTrigger` on `BatchApexErrorEvent` (the second trigger outside the dispatcher; `BatchApexErrorEvent` is on the object allowlist) and the Rollup Queue. Registry row `Rollup_Definition_Validation` (rule R-R15) refuses a rollup whose target field cannot hold its result; text rollups write dates in UTC.
- Data jobs: `Import_Batch__c.Operation__c` (Import, Update, Delete) plus `Operation_JSON__c` make the import batch the general data job (object label Data Job); bulk updates and deletes reuse `Import_Journal__c` and undo, listed under Data jobs on the Data Manager tab. Bulk update run limit `Bulk_Update_Run_Limit__c`, at most 48,000 (query rows).
- CMDT Manager: `Relationship_Type__mdt.Is_Shipped__c`; subscriber rows are named `Org_*`; `Setting_Change__c.Deployment_Id__c` audits each save; `Manage_BarnCRM_Metadata` is granted only by `BarnCRM_Metadata_Admin`. Needs the org setting "Deploy Metadata from Non-Certified Package Versions via Apex" for an unlocked package (unverified in an org).
- Field utilization: `Field_Utilization_Snapshot__c`, counted on demand inside Org Optimizer; no scheduled job or automatic cleanup (D-37, D-63).
- Also: `npm run lint`, `npm run prettier:verify` (Markdown is excluded from Prettier), `npx sfdx-lwc-jest`, Salesforce Code Analyzer with zero high or critical findings.

## Gotchas

- Synced folder spawns `name 2.ext` duplicates, including inside `.git/`: never `git add -A` or `git add .`; stage by path or `git add -u`.
- `push.default` is `upstream`: a worktree branch created from a tracking base pushes to the base. Create with `--no-track`, push with an explicit refspec (`git push -u origin <b>:refs/heads/<b>`). A bare push moved PR #200's branch and the rollup S3 branch (2026-10-12).
- `Setting_Definition__mdt` field defaults are not re-applied on redeploy, so every row names `Settings_Object__c` explicitly; enforced by `check-setting-object-explicit.py` (commit c20336ef, 2026-10-12).
- Renaming a permission set leaves the old one in an org with the same label, which blocks deploys until the old ones are deleted (hit on `oi-test` and `barn-core`, 2026-10-12).
- `sf project deploy validate` rejects `NoTestRun`; use `sf project deploy start --dry-run` instead.
- API 67.0 defaults Apex to user mode and `with sharing`; state access modes explicitly (`check-apex-access-modes.py`, 2026-10-12).
- Before a staged org gate, dry-run all packages (`sf project deploy start --dry-run`): minutes, against an hour for a gate that fails at its last stage (lesson of 2026-10-12: a full dry-run found 7 deploy errors after two gates had failed one error at a time).
- A FlexiPage visibility rule cannot test a lookup field; test `<Lookup>__r.Name` instead.
- Metadata description limits (255) count inner line breaks and indentation.
- Apex names are case-insensitive: a constant `ACCOUNT` shadows the `Account` type.
- Apex sharing reason API names end in `__c` (`Saved_Query__Share.RowCause.Shared_With_Find_Users__c`).
- `Page` is a reserved type name: an inner class named `Page` fails to deploy.
- A check-only deploy runs tests as the deploying administrator without FLS on new fields, so tests that rely on that user's access fail; hence `TestUsers` (above).
- `oi-test`: the scratch admin profile hides `Account.Site`, `Account.AccountNumber` and `Task.Type`; tests must not depend on them.
- The gate user's time zone is America/Los_Angeles, while `TestUsers` and `TestDataFactory` users are GMT; date tests must hold in both.
- The platform refuses trigger writes to a record that is mid-merge (ADR-0092 recalculates survivors after the merge instead).
- A queued batch without `Test.stopTest` still runs when the test method ends.
- After `Database.emptyRecycleBin` a record can still be returned by `ALL ROWS`, and its undelete fails `UNDELETE_FAILED` "Entity is not in the recycle bin"; treat it as purged.
- A Nonprofit Cloud trial org (production edition, `barn-npc`) rejects unpackaged deploys of custom settings and custom metadata types with visibility Protected; only developer, sandbox and scratch orgs accept them.
- An inner `Schedulable` class of a test class never runs at `Test.stopTest`; use a top-level test class.
- At API 67, user-mode DML in tests fails on standard fields no permission set grants (for example `Account.Site`); use a field a BarnCRM permission set grants.
- Deleting a parent purges children deleted before it from the Recycle Bin (lookup cascade and `Contact.AccountId`), so they cannot be undeleted; hence deleting people never deletes their household (D-88, R-H12; confirmed on `oi-test`).
- The org refuses Create on a platform event in a permission set without Read.
- A long text area field cannot be filtered in SOQL.
- The BarnCRM app's `navType` (Standard to Console) is not updateable by deploy: on an org that has the app, delete it first (destructive deploy), then deploy (done on `oi-test` 2026-10-13; D-57 for the other orgs).
- Aggregate SOQL counts every aggregated row toward the 50,000 query-row limit, not just the rows returned.
- A Queueable finalizer can enqueue at most 5 jobs in a row after failures.
- Queueable chain depth is 5 in Developer Edition, trial and scratch orgs.
- Anonymous Apex logs echo the script source, so scripts that parse output read `USER_DEBUG` lines only.
- The `oi-test` running user lacks Bulk API Hard Delete: hard delete fails there, so scale cleanup falls back to soft delete.
- `sf data delete bulk --json` returns the job id at `.result.jobInfo.id`.
- The synced folder can create `name 2` duplicate git refs inside `.git` that break `git fetch`; check they are stale, then move them out of `.git`.
- `FOR UPDATE` works on a hierarchy custom setting's org-level row; Core uses `Rollup_Run_Lock__c` as a run lock (#398, 2026-10-14).
- A new ADR on a branch uses the placeholder file `NEXT-<title>.md` and never a chosen number; the integrator numbers it at merge (see the repo `CLAUDE.md`).
- The journal cursor is `(CreatedDate, Id)` (keyset paging, #401).
- Rollups can run as Automated Process, started by the `Rollup_Queue_Ready__e` platform event through `RollupQueueReadyTrigger`; code that judges who made a save must not assume a human user (ADR-0119).
- `Merge_Settlement_Ready__e` (Publish After Commit) is consumed by `MergeSettlementReadyTrigger`, configured at batch size 50 by `PlatformEventSubscriberConfig` in the Apex stage of `deploy-packages.sh`; it runs as Automated Process (ADR-0118).
- `barn-core` is the Platform-only org (expires 2026-10-17). `BarnCRM_Access_Manager` is an optional permission set holding the Salesforce-license permissions (Assign Permission Sets, View All Users); `Duplicate_Review` is the other optional Salesforce-license set (ADR-0121).
- In a class with a field named `label`, reference custom labels as `System.Label.X`.
- `ALL ROWS` returns deleted records until they are physically removed.
- Person-account orgs rename some child relationships; do not hard-code relationship names.
