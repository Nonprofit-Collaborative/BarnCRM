# ADR-0029: Shipped rollups are created by each package's post-install script

**Status:** Accepted
**Date:** 2026-09-09
**Amended by:** ADR-0056 (Campaign sync keeps its link on the appeal), under which Connect also has a
post-install script, `ConnectPostInstall`; the statement below that Core is the only package with one
describes the state before this ADR (Giving gained `GivingPostInstall` here). Amended by ADR-NEXT
(`NEXT-rollup-builder-module.md`): Core's post-install script no longer creates rollups; the
BarnCRM Rollup Builder module's `RollupsPostInstall` makes the call Core made, and Giving's script
still makes its own, now into the module.
**Source:** defect in C-13 and G-02; canonical model Section 13 and rule R-R6; ADR-0006, ADR-0003,
ADR-0021

## Context

`RollupService.ensureDefaults()` materializes `Rollup_Definition_Default__mdt` into
`Rollup_Definition__c` records. It had exactly one non-test caller: the **Restore shipped
rollups** button on the Rollups page. `CorePostInstall.onInstall` assigned the installer's
permission set and role and nothing else.

So a fresh install had no rollup definitions at all. Every giving total on every donor, fund,
appeal, commitment and installment was blank, the nightly batch had nothing to run, and the only
way out was a button labelled Restore, for something that had never been there. Nothing in the app
pointed at it: the Setup Assistant has no rollup step, and the Hub tile reports staleness rather
than absence. Canonical model Section 13 and R-R6 both say these records are created "on install",
so the code was wrong rather than the documentation, and the documentation had already been
corrected to describe the two clicks an administrator actually had to make.

Four things make the fix more than adding one call.

**Core installs first.** Core is the only package with a post-install script, and at the moment it
runs, no module is installed. Its call sees Core's own shipped rows and none of Giving's, because
`isShippableHere` skips a row whose source or target entity is not in the org, which is exactly
what keeps a Core-only org clean (Principle 3, ADR-0013). Giving has no `InstallHandler` at all
today.

**A post-install script is a constrained context.** It runs asynchronously, as a platform user who
holds no permission set, with no user to report to and no way to retry. An unhandled exception
fails the install, which is a far worse outcome than an org with blank totals: blank totals are two
clicks from being right, and a rolled back install is a support case. The transaction cost is one
query for the shipped rows, one for the existing definitions, one describe per distinct entity name
and one insert of at most a few dozen records, which is small against the limits, but only if the
describe per row is not repeated.

**An upgrade must not duplicate.** `ensureDefaults` matches on Definition Key and skips what
exists, so it should be idempotent across upgrades, and that has to be asserted rather than
believed.

**A deliberately deleted definition leaves no trace.** R-R6 says packaged code never deletes an
administrator's records, and it says an administrator who does not want a packaged definition sets
Active to false. It does not say what happens to one that was deleted anyway, and now that the
materialization runs on every upgrade, that case has an answer whether or not one is chosen.

## Decision

1. **Every package that ships rollup defaults materializes them from its own post-install
   script.** Core calls it from `CorePostInstall`, and Giving gets `GivingPostInstall`, a new
   `InstallHandler` whose only job this is. A module's script is the first moment the org holds
   both that module's shipped rows and the objects they name. Core's call is not redundant: it
   creates Core's own rows, and on a Core upgrade it also picks up anything a module shipped and
   failed to create.
2. **The call is `RollupService.ensureDefaultsDuringInstall(context)`, which never throws.** It
   wraps `ensureDefaults`, writes any failure to the Error Log under the calling script's name, and
   returns zero. The guarantee lives in one place rather than in each script's own `catch`, so a
   module added later cannot get it wrong. This follows what `CorePostInstall` already does for
   permission set and role assignment.
3. **Restore shipped rollups stays, and is documented as the recovery path**, for an install whose
   step failed and for a rollup that is missing for any other reason. It calls the same method, so
   there is one materialization mechanism and not two.
4. **A definition the administrator deleted comes back on the next upgrade, and the admin guide
   says so plainly.** The package cannot tell a deleted record from one that was never created:
   deletion leaves nothing behind, and matching is by Definition Key on records that exist. The
   alternative is to keep a tombstone of every key an administrator has deleted, which is a new
   object, a new place for the two to disagree, and a new thing to explain. Clearing **Active** is
   the supported way to refuse a total, it is what R-R6 already prescribes, it survives every
   upgrade, and it keeps the values already calculated. The guide says both halves: what deletion
   does, and what to do instead.
5. **Nothing existing is ever updated.** An upgrade adds newly shipped definitions and touches no
   field of a definition that is already there, whether the administrator edited it or not
   (R-R6, ADR-0006).

## Alternatives considered

- **Call it only from `CorePostInstall`.** Rejected: it is the shape of the bug, not a fix. At Core
  install time Giving is not present, so its rows are skipped, and Giving's own install would
  create nothing. The totals would appear only if Core were later upgraded, which may not happen
  for months.
- **Have Giving materialize its own rows in Giving code.** Rejected: `Rollup_Definition__c`, the
  shipped defaults and the matching rule are Core's, so a module doing it itself is a second
  implementation to keep in step with the Restore button, over a Core object, for no gain.
- **Record deleted Definition Keys, so a deliberate deletion is permanent.** Rejected: it adds an
  object and a rule ("this key is refused") that an administrator can neither see nor undo from the
  Rollups page, to serve a case the Active box already serves better. Revisit if organizations are
  found deleting definitions rather than deactivating them.
- **Leave it to the Setup Assistant.** Rejected: an assistant step is still a step somebody has to
  find and perform, and the Setup Assistant is not where a module installed six months later would
  be noticed.
- **Materialize lazily, the first time the Rollups page or the nightly batch runs.** Rejected: it
  writes records as a side effect of reading a page, it does not help the org where nobody opens
  that page, and it would run in the user's context rather than in the one place where system mode
  writes to package-owned data are already justified (ADR-0021).

## Consequences

- **A new module that ships rollup defaults needs a post-install script of its own**, or its totals
  will not appear until Core is next upgraded. That is one class and one line in the module README,
  and it is written down in both package READMEs.
- **The `postInstallScript` entry is still not in `sfdx-project.json`**, for Core or for Giving,
  because no package version has been created (namespace deferred, plan Section 4.3). Whoever
  creates the first version of each package adds it. Until then the scripts run in no environment
  at all, which is the same state Core's has been in.
- **An install whose materialization fails is silent to the installer.** The Error Log holds the
  reason, and the Rollups page shows an empty list with the button that fixes it. The admin guide
  names both.
- **A deleted definition returns on upgrade.** This is a real limitation, chosen over a mechanism
  nobody can see, and the guide states it rather than implying that deletion is honoured.
- **`ensureDefaults` now describes each entity name once per call** rather than once per shipped
  row, because the shipped rows name a handful of entities between them and each miss walks the
  org's whole describe. The behaviour is unchanged; the cost in a post-install transaction is not.
- **Only a real install can confirm three things.** No Apex in this repository has been executed
  against an org: that the shipped custom metadata rows are readable from the post-install context
  at the moment the script runs, that a protected custom metadata record packaged by one module is
  visible to Core's selector once namespaces exist, and that the whole step fits inside the limits
  of a post-install transaction in a large org. The first two also govern the existing Restore
  button, so they are not risks this decision introduces, but they are unproven either way.
