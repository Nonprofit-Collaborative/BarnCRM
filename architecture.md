# Architecture: durable reference facts

Purpose: environments, access, layout and gotchas for BarnCRM. Reference facts only, not a task log (work done goes in `changelog.md`). Check here before re-querying a live system.

Last verified 2026-10-28 (landing/batch-8; main at #660, 2fa85483e; `mwdbdevsb` deployed at 9a10ef84; ADR-0141 account record types, ADR-0142 Admin View All and Modify All on Account and Contact).

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
- Org gates run per landing batch (D-141), `barn-sales` and `oi-test` in parallel. Defaults: `POLL_SECONDS=5`, `TEST_POLL_SECONDS=15`, `DEPLOY_SHOW_COMPONENTS=0`. Gotcha: both gates post the same `Org tests (local)` status, so a success never replaces the other org's failure (Held).
- Worktrees live under `~/worktrees/BarnCRM/<branch>`; the main checkout (in a synced folder) is not used for work.
- Commits carry a DCO sign-off (`git commit -s`).

## Salesforce orgs (by alias)

| Alias | What it is | Rules |
|---|---|---|
| `devhub` | Dev Hub | Creates scratch orgs. At its limit of 3 on 2026-10-28; the RT1 spike used two 1-day scratch orgs on `sftapanel` instead (deleted) |
| `oi-test` | Default scratch test org, Person Accounts shape | Named by the `SF_TEST_ORG_AUTH_URL` secret. Recreated 2026-10-25 (the previous org expired 2026-10-23): person-accounts shape, Enterprise, expires 2026-11-24; seeded with 200 households, 440 contacts and 25 organizations (`seed-sample-data.sh`; the create script's seed step failed on file mode until #527). The owner replaced the secret value 2026-10-26 (`gh secret list` shows updated 2026-10-26) |
| `barn-personaccount` | Person Account scratch org, successor of `oi-pa` | Expires 2026-11-24. First full gate on main 71e97ead 2026-10-25: 3,542 of 3,542, coverage 93%, 0 classes under the floor. Gate org for Person Account runs |
| `barn-sales` | Scratch org, Sales Cloud shape, contacts mode; the "DLRS present" test org | Expires 2026-11-25. DLRS 2.25.0.2 installed 2026-10-28 for coexistence QA (6 QA_* DLRS rollups and 2 legacy rows left in place); Giving_Admin assigned to the admin user. Batch 13 gate: every test passed, OpportunityMirrorSelector at 71% (floor 75%), fix in batch 14. DeploymentSettings `doesSkipAsyncApexValidation` is true (deployed as metadata 2026-10-26) so Apex redeploys are not blocked by the scheduled "BarnCRM Tab Access Check" job. Scratch org limit is 3 active (`oi-test`, `barn-personaccount`, `barn-sales`), all in use |
| `oi-pa` | Person Account scratch org (D-15) | Expired 2026-10-24; replaced by `barn-personaccount`. Cleaned 2026-10-12 (owner approved): old `Nonprofit_Admin` assignment, the 4 `Nonprofit_*` permission sets and their group deleted. 2026-10-14 (owner approved): stale BarnCRM app and its 4 in-app guidance prompts deleted. Fallback gate org when `oi-test` has no `DailyAsyncApexTests` left |
| `barn-core` | Third scratch test org, Sales Cloud shape, for Core-only runs | Approved 2026-10-12 (alias was `bc-core`). Expired; no recreation recorded |
| `barn-npc` | Nonprofit Cloud trial, production-type, Person Accounts on, API 68.0; for rollup S16 coverage and Nonprofit Cloud coexistence tests | Never the default. Enabled 2026-10-12 (owner approved): Fundraising_Admin and Program_Management_Administrator permission set groups on the admin; Contacts to Multiple Accounts on; Industries settings Fundraising, Gift Entry Grid, Group Membership, Program and Benefit Management on (irreversible). BarnCRM deploy approved once landing batches, Builder S10 to S13 and test self-containment merge. Deployed 2026-10-13 (`main` at #221); real-org check 2026-10-15 at e1a71e43 passed (tab sync, one-way turn-on, NoneChosen, restore; permission set groups recalculated in 2 to 8 s); settings objects deployed Public (a trial rejects Protected); the BarnCRM app is Console navigation there since 2026-10-15 (owner approved: the 4 in-app guidance Prompts and the BarnCRM CustomApplication were deleted, then both redeployed from main 4ed86f12); an org-default `BarnCRM_Settings__c` row exists (null values). Release deploy of `main` (Volunteers): validation was blocked by 77 stale BarnCRM components deleted in #377 (69 ApexClass, 3 LWC, 5 custom metadata records including `RollupControl.Org_Defaults`; none referenced in code). Owner approved the removal 2026-10-25 if no regression or loss. Phase 1 (Volunteers data model) deployed 2026-10-25 (0Afhk000001v6JRCAY, 148 components, NoTestRun); validation 0Afhk000001v6L3CAI failed 3 of 3,224 tests because test queries ran as the deploying user, who held no Volunteers permission sets (fixed in #556 and #557). The org rejects Protected visibility, so every deploy uses a local patch that sets the 9 affected settings and custom metadata objects to Public (kept in the `npc-cleanup` deploy worktree, never committed to `main`). Deploy allow rules for `barn-npc` were added to `~/.claude/settings.json` 2026-10-25 (owner approved). Use `main` 342dfb0f or later |
| `mwdbdevsb` | Sandbox of a real, built-out org, for Standard Edition (Core without Giving) tests; alias was `mwdsb` until 2026-10-12; Midwest Dreamin' sandbox `brandondev`, connected 2026-10-12, instance API 68.0 | Never the default; check-only first. Core and Rollups are deployed; the last deploy was 2026-10-28 at 9a10ef84. Sample data is loaded. Brandon and Michelle have the BarnCRM permission sets. Never change org settings; deploys still need owner approval. History: deployed 2026-10-14 (owner request): Core at e3f2db58, then e3f2db58 plus #411, #412 and #413; BarnCRM Admin group assigned to Brandon Mead and Michelle Hansen; no data or settings changes, no scheduled jobs. Deployed again 2026-10-17 (owner approved): Core plus Rollup Builder at cf861610, no Giving; the `.forceignore` tweak is no longer needed. A Core plus Rollup Builder org is deployed as `deploy-packages.sh <alias> --core-only`, then a `packages/rollups` deploy, then anonymous Apex running `RollupsPostInstall.carryOverCoreSettings`, `RollupService.ensureDefaults` and `RollupAccessSync.requestSync` (the script has no Core-plus-Rollups mode). Deployed 2026-10-20 (owner approved): Core plus Rollup Builder at ec8cf042, one `RunLocalTests` check-only (2088 of 2088, includes the 14 client test classes) then quick deploy, then the post steps; no data changes. Deployed 2026-10-25 (owner approved): main 71e97ead (Core and Rollup Builder identical at e1869f85), check-only 0AfWF00000H0K1l0AF `RunLocalTests` 2,140 of 2,140 and 3,132 components, quick deploy 0AfWF00000H0Llp0AF, post steps run, jobs Completed with 0 errors. State 2026-10-26 (before sample data): metadata-only sandbox with 0 Contacts and 0 Accounts, no `BarnCRM_Settings__c` row (first-run setup not done), language en_US, State and Country Picklists off. Core and Rollup Builder deployed. Test it as-is: never change org settings (no Person Accounts enablement or similar). Testers are Brandon Mead and Michelle Hansen (System Administrator), who get the BarnCRM permission sets and groups needed to review everything. A deploy from another folder needs `--ignore-conflicts` (source tracking is per folder). Ask before every further deploy. Dev org admins need `Rollup_Builder_Admin` after the Rollup Builder module lands |

Any other org (including other mwd sandboxes) needs owner approval. Agents share each scratch org one deploy or test run at a time, through a lock in the session scratchpad. Scratch org definitions: `config/scratch-defs/` (`person-accounts.json`, `sales-cloud.json`, `platform-only.json`, `npsp.json`, `nonprofit-cloud.json`).

## Credentials (names and locations only, never values)

- GitHub Actions secrets: `SF_DEVHUB_AUTH_URL` (Dev Hub) and `SF_TEST_ORG_AUTH_URL` (the `oi-test` org). Setup and rotation steps in `docs/contributor-guide/ci.md`.
- Local org access: the sf CLI's own auth store, by alias. Org auth URLs are credentials: never read, print or write them.

## Package layout

- `packages/core` (neutral Core; the vendored apex-rollup tree, `RollupAdapter` and `RollupEngineComparison` were deleted by rollup S9, #377), `packages/giving` (depends on Core), `packages/mirror` (BarnCRM Mirror, renamed from Connect by ADR-0126, D-103; depends on Core and Giving; the only package that may touch Opportunity, Campaign, Case, Lead). `packages/programs` and `funders` are placeholders.
- Core never references Giving or Mirror; no dependency on Person Accounts, Industries, OmniStudio, Data Cloud or Experience Cloud (ADR-0013).
- Deploys to an org run in stages through `scripts/org/deploy-packages.sh`. The script queues `TabAccessService.requestSync()` after a deploy, because dev orgs otherwise lose the tool tabs (landed #435, 2026-10-15).
- `packages/rollups` ("BarnCRM Rollup Builder", a both-editions module, D-101; landed in #438, ADR-0125); `packages/volunteers` landed V-01 to V-08 (built unmanaged, D-104); install order Core, Rollup Builder, Giving; permission sets `Rollup_Builder_Admin` and `Rollup_Builder_User`; a Rollup Builder stage in `deploy-packages.sh`; CI check `check-core-names-no-module.py`.
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
- A test that runs many passes of a SOQL-capped job in one transaction can fail only in orgs with more child relationships on Contact (Nonprofit Cloud: 124 vs 76 on `oi-pa`; the undo checks cap at half of 100 SOQL). Run later passes as their own job between `Test.startTest` and `Test.stopTest` (#510).
- Apex coverage on a scratch org accumulates across runs until the class is redeployed; redeploy a class before measuring its coverage.
- `BarnCRM_Settings__c.Suite__c` accepts only `Community` or `Impact` (the API values of Standard and Nonprofit Edition); Setup edits are not audited. The edition is chosen once in first-run setup; first-run shows while `Suite__c` is blank (ADR-0124).
- `Features_Turned_On__c`: blank means every feature on (upgraded org), `None` means a new install before setup, `NoneChosen` means setup finished with nothing turned on. Turning a feature on is one-way.
- Turning Household Upkeep on queues `HouseholdCatchUpBatch` (contacts only; person accounts are not caught up, a roadmap follow-up). Tests that turn it on enqueue a batch (one `executeBatch` per test method).
- `CorePostInstall` schedules "BarnCRM Tab Access Check" (nightly tab sync); skipped in tests unless `scheduleTabCheckInTests`. Settings has 14 sections, Modules second; `firstRunSetup` (LWC in `settingsConsole`) is first on `BarnCRM_Home`.
- Core role labels differ from API names: Team Member is `Program_Staff`, Coordinator is `Volunteer_Coordinator`; never rename the API names (ADR-0123).
- Module Apex calls `HealthCheckController.applyFixFor` (never `applyFix`). `RollupEngineExtension` is frozen: new needs go in a v2 interface. `check-core-names-no-module.py` has an `ALLOWED_LITERALS` list.
- Anything that sizes a record from stored totals must read every COUNT total on the entity, not only the named definitions (#412). The queue sends a parent to `RollupLargeParentBatch` when the estimate passes 40% of the query-row limit, or when its next query would pass four fifths (stale stored count, #434).
- `oi-test` `DailyAsyncApexTests` limit is 7,260 test classes per rolling 24 hours (about 22 full runs of about 330 classes). When it is exhausted `sf apex run test` fails with `UNKNOWN_EXCEPTION` ("An unknown exception occurred") and the gate reports "sf CLI crashed". Check: `sf org list limits -o oi-test --json`, the `DailyAsyncApexTests` row. Fall back to `oi-pa`.
- `NavType` is not updateable on an existing app: delete the in-app guidance prompts that reference it first, then the app (done on `oi-pa` 2026-10-14).
- `gh pr merge --delete-branch` closes PRs stacked on that branch and does not retarget them (hit 2026-10-14 on #414 and #417); retarget dependents first. CI workflows do not run after a PR is retargeted to main: close and reopen it.
- `AsyncApexJob` has a `BatchApexWorker` row per batch chunk next to the `BatchApex` row, with the same class name; filter `JobType` when counting runs (`RollupModuleSwitchTest.jobsOf`, #438).
- AuraEnabled fields cannot be `@NamespaceAccessible` (the deploy fails the whole Core Apex stage); CI runs `scripts/ci/check-aura-namespace-accessible.py` (#438).
- Connect renamed Mirror (D-103, ADR-0126, landed #441, 98583f12): `packages/connect` to `packages/mirror`; package `BarnCRM Mirror`; `Connect_Settings__c` to `Mirror_Settings__c`; 9 `Connect*` Apex classes to `Mirror*`; 156 `Connect_*` labels to `Mirror_*`; `Core_HealthCheck_ConnectMissing*` to `Core_HealthCheck_MirrorMissing*`; `BarnCRM_Module.Connect` to `.Mirror`; 7 `Setting_Definition.Connect_*` to `Mirror_*`. Permission sets, tabs, LWCs and fields kept their names.
- A test org that had Connect needs a destructive deploy of the old names after Mirror deploys (owner approved the cleanup on `oi-test`, `oi-pa`, `barn-core`, `barn-npc`). Deleting `Connect_Settings__c` drops its org values; unschedule any Connect nightly job before deleting its class.
- `deploy-packages.sh` queues `RollupAccessSync.requestSync()` after a deploy (unless `--core-only`), so dev org admins get `Rollup_Builder_Admin` and Staff/Read Only get `Rollup_Builder_User` without waiting for the nightly run (#440).
- LWCs that read page state keys match by suffix (`__section`, `__savedQueryId`): the prefix is `c` now and the namespace later.
- A module catalog record left in an org from a renamed module makes edition-module count tests fail (8 instead of 7): delete old module CMDT records after a module rename.
- A Lightning app needs `formFactors` (the Rollup Builder app got them with a Console `navType`, #429).
- `sf ... --json 2>&1` mixes the CLI update warning into the JSON; scripts must tolerate it (#433).
- A sandbox deploy from a different folder needs `--ignore-conflicts` (source tracking is per folder).
- `barn-npc` settings custom settings and metadata deployed with visibility Public (a production-edition trial rejects Protected, see above).
- CI checks for cross-package visibility (#446), production classes only: `scripts/ci/check-cross-package-visibility.py` (allowlist `scripts/ci/cross-package-visibility-allowlist.txt`, one entry: `HealthCheckService.Finding.detail`, B5 deferred) and `scripts/ci/check-dynamic-class-visibility.py`.
- `OrgShape` fields are `@AuraEnabled`, so they cannot be `@NamespaceAccessible`; other packages use static accessors (`OrgShapeDetector.hasPersonAccounts()`).
- A class Core builds by name (`Type.forName`, trigger handlers, registered module extensions) needs an explicit `@NamespaceAccessible` public no-arg constructor; the implicit one is not accepted by the check.
- `Contact.Description` is a long text field and cannot be filtered in SOQL; match test records on another field such as `Email`.
- Pruning worktrees must skip any worktree with uncommitted changes (a prune on 2026-10-15 lost the `barn-npc` Public-visibility edits and an `mwdbdevsb` `.forceignore` tweak).
- Bulk API 2.0 refuses rows the standard duplicate rules flag (`DUPLICATES_DETECTED`, Duplicate Alert); the scale loader uses the REST sObject Collections API with `Sforce-Duplicate-Rule-Header: allowSave=true` (#443).
- A PR branch created before a rename landed redeploys the old names when gated (`oi-test` got old Connect and Mirror back after such a gate; restored to main 6506cb52). Rebase open branches onto main after a rename lands, before gating them.
- `@AuraEnabled` methods, like fields, cannot be `@NamespaceAccessible` (the deploy fails); give cross-package callers a plain annotated wrapper or getter.
- In a worktree whose `node_modules` symlinks into the Mead Drive path, `prettier-plugin-apex` fails on the path with spaces, so the prettier step of `run-offline-checks.sh` fails there; CI is the check.
- The org-test user lacks Bulk API Hard Delete, so scale cleanup soft-deletes to the Recycle Bin.
- `Date.today()` can differ between `System.runAs` users across UTC midnight (a Volunteers totals test failed once at the gate); capture the date once in a test and reuse it.
- Code Analyzer high rule `EagerlyLoadedDescribeSObjectResult`: use `getDescribe(SObjectDescribeOptions.DEFERRED)` (hit in a Volunteers test, #493).
- ESLint `@lwc/lwc/no-unexpected-wire-adapter-usages` fires in Jest tests that call `getObjectInfo.emit`: use a file-level disable with a reason.
- One full Health Check request costs about 41 SOQL cold (Core 23, Rollups 3, Giving 3, Volunteers 5): a test must not run several full Health Checks in one transaction.
- Gate worktrees live in `~/worktrees/BarnCRM/gate-pa` and `gate-test`, never under `/tmp` or the scratchpad: macOS deletes `/tmp` files unused for 3 days (it removed gate scripts and worktree `.git` files on 2026-10-20).
- A single-branch deploy to a shared test org leaves stray classes and registry rows that break later gates (hit on #486: a stray handler and a missing selector method failed every Account and Contact trigger); gate with full deploys only.
- `scripts/ci/check-aura-class-access.py` fails when an Apex class an LWC calls is granted in no permission set of its package (added in #500 after the Volunteers readiness controller shipped ungranted); deliberate exceptions go in `scripts/ci/aura-class-access-allowlist.txt`.
- A `RunSpecifiedTests` validation enforces 75% coverage per class. A Core-only org without modules exposes classes covered mainly by module tests (`mwdbdevsb` 2026-10-20: AffiliationController, ImportMatcher, DataProtectionExtensions, HouseholdDependentsExtensions; fixed in #508). `RunLocalTests` uses org-wide coverage.
- An org deployed from an older `main` keeps components `main` later deleted, and a later deploy can fail to compile against them. A release deploy to a long-lived org needs a destructive pre-step for the components deleted since its last deploy (`barn-npc`: 77 deleted in #377; validation 0Afhk000001pzlyCAA failed on them 2026-10-20).
- The auto-mode classifier blocked `sf project deploy` to `barn-npc` (production edition) even with owner approval in chat; the owner added allow rules to `~/.claude/settings.json` on 2026-10-25. Edits to settings files are blocked as self-modification until the owner approves them.
- A source deploy must run `CorePostInstall.runAsSourceDeploy()` (first-run state, tool tabs, the nightly tab check); `deploy-packages.sh` runs it after Core (#560; `SOURCE_POST_INSTALL=0` skips it). On an org deployed another way, run it as anonymous Apex. It is safe on orgs already set up. `FirstRunControllerTest` calls `markNewInstall` and fails on an org that finished first-run setup.
- Test verification queries use `WITH SYSTEM_MODE` (#556 module fields, #557 Core fields), so a first-time `RunLocalTests` deploy does not depend on the deploying user's BarnCRM permission sets (the `barn-npc` validation failed on this, 2026-10-25). Tests read BarnCRM Settings through the `TestSettings` helper, not the org's saved row (#565).
- Mead Drive sync creates `name 2` duplicates inside `.git` too (refs and logs, for example `logs/HEAD 2`), and a duplicate ref breaks `git fetch`. Check each is stale, then ask before moving it out. Resolved: the `logs/HEAD 2` duplicate in the main checkout's `.git` no longer exists (checked 2026-10-26).
- Post-install schedules the BarnCRM Tab Access Check cron job; on an org with that job pending, Apex deploys fail ("schedulable class has jobs pending") unless DeploymentSettings `doesSkipAsyncApexValidation` is true. `barn-sales` has it on (2026-10-26); `oi-test` has no BarnCRM cron jobs. Tests must never sweep the org's real job (fixed by #598 in #605 and #602 in landing batch 10).
- `mwdbdevsb` has no `doesSkipAsyncApexValidation` and its settings must not change: abort the "BarnCRM Tab Access Check" CronTrigger before an Apex deploy. `CorePostInstall.runAsSourceDeploy` schedules it again.
- `check-metadata-lengths.py` also checks validation rule `errorMessage` length (255, #558). The Testing Guide has a Core-only real-org sandbox path using a Zztest fixture (#558).
- Apex compile gotchas the offline checks miss (each broke a landing batch's org deploy): `Schema.SObjectField.getDescribe()` takes no arguments (only `SObjectType.getDescribe(options)` takes `SObjectDescribeOptions`); `new Map<String, Object>(Map<String, String>)` does not compile (copy key by key); LongTextArea fields cannot be `<required>true</required>`; never remove an LWC `@api` property a Lightning page may use (declare it and ignore it); deploy with `sf project deploy start --metadata-dir` without `--single-package`.
- Mead Drive sync makes `name 2` duplicates inside `.git/refs`; they make `git fetch` exit 1 and leave `origin` refs stale. Workaround: update the refs from `git ls-remote` (the session's `sync-origin.sh` does this).
- LWC GraphQL `@optional` on a field the user cannot read returns no error and no value (verified at API v67.0); the Address card relies on it (#637).
- Record type mechanics (RT1 spike on `sftapanel` scratch orgs, ADR-0141): a permission-set record type becomes the effective default when the user's profile has none (Master); a user without a record type can read and edit an existing account of it but cannot create one or change another account to it; a permission-set source deploy removes record type visibility it no longer names; a newly deployed record type is visible to no profile, System Administrator included; anonymous Apex refuses `SYSTEM_MODE`. BarnCRM never gives users the Household record type (D-134).
- Never insert a Household account in user mode: use `HouseholdWriter.createHouseholdsForUser` (a person's request; checks Account create and edit, field create access and edit on touched households) or `createHouseholds` (automation); tests use `HouseholdTestDataFactory.insertHouseholds` (#661).
- `AccountKinds` is the only reader of `Organization_Record_Type__c` (developer name, or Master); never name an organization record type in code (#660). `AccountKinds.organizationRecordTypeId()` is null for Master; tests call `AccountKinds.reset()`. `SampleDataSelector.countSampleOrganizations` still filters by `RecordType.DeveloperName` 'Organization' (account record types PR 4); PR 4 also covers `ImportRowProcessor`, `AddressService`, `MatchingGiftService`, the Import log message `Core_Import_LogOrganizationRecordTypeMissing` and about 36 test `.get('Organization')` calls.
- `BarnCRM_Settings__c.Suite__c` stores `Community` (Standard Edition) and `Impact` (Nonprofit Edition); show them through `Core_SuiteChoice_StandardName` and `Core_SuiteChoice_NonprofitName` (`SettingsController.choiceLabelsByStoredName`), never as codes (#656).
- `Merge_Settlement_Ready__e`: the subscriber settles only records its publisher (the event's CreatedById) may edit; otherwise the survivor is left unsettled with an Error Log warning (#654). `check-apex-access-modes.py` flags Core inner async jobs with no sharing keyword.
- `Integration_App__mdt.Install_Url__c` no longer exists (#655, D-138).
- Setup deep links live in the shared `c/setupLinks` module; six paths are unverified in a browser (ApexSettings, ForecastFiscalYear, OrgWideEmailAddresses, FlexiPageList, OrgEmailSettings, CompanyProfileInfo), checked in batch QA (T-SET-20) (#659, D-137).
- Import templates are listed by Name; the People card picks `generic_contact_list` by key (#658).
- GitHub workflows run only on pull requests into `main`, so a stacked PR (for example #662 on #658) gets no CI until it is retargeted.
- Lightning App Pages print the page name above the component, so the page shell passes title-hidden (#663); Lightning desktop at 390 px is not the mobile app (the console tab bar overflows).
