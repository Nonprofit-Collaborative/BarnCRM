# ADR-0125: The rollup engine and Rollup Builder move out of Core into the BarnCRM Rollup Builder module

**Status:** Accepted (owner decision, Brandon, 2026-10-14: the move, this design, and decisions
D1 to D7 below as recommended)
**Date:** 2026-10-14
**Source:** owner decision 2026-10-14; amends ADR-0003 (Core no longer contains the rollup
engine), ADR-0029 (Core no longer materializes shipped rollups) and ADR-0082 decision 7 (the
Rollup Builder tab leaves Core's app); builds on ADR-0017, ADR-0018, ADR-0020, ADR-0057,
ADR-0073 and ADR-0075

## Context

ADR-0003 put the rollup engine in Core. Many orgs that would install BarnCRM already run DLRS
or Rollup Helper, and they want BarnCRM without a second engine: its objects, its triggers on
Contact and Household Member, its nightly job, its queue, its Health Check findings and its tab.
ADR-0003's own rule decides this: a capability that adds objects an org may never need is a
package. The engine adds four objects (`Rollup_Definition__c`, `Rollup_Queue__c`,
`Rollup_Run_Lock__c`, `Rollup_Queue_Ready__e`, 44 fields), one custom metadata type
(`Rollup_Definition_Default__mdt`), 3 triggers, 22 Apex classes (8.3k lines) with 27 test
classes (8.6k), 5 LWCs, 1 tab, 1 app page, 1 flow template and 163 labels.

Core reaches into the engine today from: `AccountTriggerHandler` (merge survivors,
`RollupService.runAfterMerge` and `runForSurvivors`), `AutomationControl` (resume starts
`RollupQueue.processPending`), `HubController` (freshness tile), `SampleDataModules`
(`startQueuedRecalculation`), `DataProtectedFields` (`RollupSelector.selectAll` for target
fields), `ImportUndoBatch` (`RollupService.FRESHNESS_FIELD`), `FiscalYearSelector`
(`RollupDateWindow.fiscalYearStartMonth`), `CorePostInstall` (`ensureDefaultsDuringInstall`),
`NightlyJobs` (`RollupJob`), `OrgOptimizerObjectChecks` (`Rollup_Definition__c` in its object
list), Health Check (`HealthCheckService`, `HealthCheckSettingsChecks` with three rollup checks,
`HealthCheckController` with the Restore shipped rollups fix) and `settingsConsole` (literal
import of `rollupDefinitions`). Find's `QueryCompiler`, `FindRelatedRecords`,
`DataHygieneService` and `FilterValueBinder` use `RollupFilterParser`, which depends only on
`FilterValueBinder`. Core already resolves dependent-package classes by name for Health Check
(`HealthCheckExtensions`), nightly jobs (`NightlyJobs.PROVIDER_CLASSES`), data protection,
person erasure, household dependents and the Setup Assistant.

Giving's donor, fund, appeal, commitment and installment totals are rollups: it ships 50
`Rollup_Definition_Default__mdt` rows, four Automation Registry rows naming
`RollupTriggerHandler`, and calls `RollupService` from `GivingPostInstall` and
`HouseholdSoftCreditRecompute`.

No managed or unlocked version has been released, so this is a source reorganization with no
subscriber migration.

## Decision

1. **A new package, BarnCRM Rollup Builder.** Folder `packages/rollups`, package name
   `BarnCRM Rollup Builder`, module key `Rollups` (the value of `Module__c` on its custom
   metadata rows and in `Modules_Turned_Off__c`), depending on BarnCRM Core only. It is offered
   in both editions. Core never references it; it reaches Core the way Giving does
   (`@NamespaceAccessible` classes, ADR-0017).
2. **What moves**, unchanged except where named: every `Rollup*` class and test except
   `RollupFilterParser` and its test and Core's engine seam (`RollupEngineExtension`,
   `RollupEngineExtensions` and `RollupEngineExtensionsTest`); the triggers `RollupDefinitionTrigger`,
   `RollupQueueReadyTrigger` and `RollupRecalcErrorTrigger`; the LWCs `rollupBuilder`,
   `rollupDefinitions`, `rollupFilterBuilder`, `rollupNeedsAttention` and `rollupWizard` with
   their Jest mocks; the four objects and `Rollup_Definition_Default__mdt`; the `Rollup_Builder`
   tab and app page; the `Recalculate_Rollups_Template` flow; the label files `CoreRollups` and
   `RollupBuilder` plus the Health Check and nightly job labels the moved checks use; the
   Automation Registry rows `Core_Rollups_Contact`, `Core_Rollups_Household_Member` and
   `Rollup_Definition_Validation` (developer names kept, `Module__c` set to `Rollups`); the
   Setting Definition rows `Rollup_Definitions`, `Rollup_Mode_Default` and `Rollup_Processing`.
   Label and row names keep their `Core_` prefixes: a rename is churn with no reader, and a
   renamed registry row runs twice in an org that still holds the old one.
3. **What stays in Core:** `RollupFilterParser` and `FilterValueBinder` (Find owns the filter
   document; the module calls the parser), `filterBuilder` and `filterDocument`, `hubRollups`
   (Core's home page cannot place a module component), `Fiscal_Year_Start_Month__c`, the section
   names `SettingSections.ROLLUPS` and `JobNotifier.SECTION_ROLLUPS` (strings, not schema), and
   the `settingsSetupNotes` rollups note. `FiscalYearSelector` takes over the body of
   `fiscalYearStartMonth`, and `RollupDateWindow` delegates to it, so the dependency points from
   the module to Core.
4. **Core-owned extension points the module registers into.** Each follows the existing
   pattern: an `@NamespaceAccessible` interface in Core, a resolver holding a list of class
   names, resolved once per transaction with `NamespaceUtil.resolveType`, absent when missing,
   unbuildable or the wrong shape, and `@TestVisible` overrides for Core's tests.

   | Core extension point | Module class | Replaces | When the module is absent |
   |---|---|---|---|
   | `RollupEngineExtension` (new) with `afterMerge`, `forSurvivors`, `startQueuedRecalculation`, `processPending`, `lastCalculated`, `isStale`, `targetFieldsByObject`; resolver `RollupEngineExtensions.find()` | `RollupsEngineExtension`, delegating to `RollupService`, `RollupQueue`, `RollupSelector` | the calls in `AccountTriggerHandler`, `AutomationControl`, `SampleDataModules`, `HubController`, `DataProtectedFields` | merges complete with nothing to recalculate; resume and sample data skip the queue; the home rollups tile is hidden (`rollupsInstalled` false); no field is protected as a rollup target |
   | `RollupEngineExtensionV2` (new, decision 9) with `afterModuleTurnedOn`; resolver `RollupEngineExtensions.findV2()` | `RollupsEngineExtension`, delegating to `RollupService.catchUpAfterTurnedOn` for `Rollups` only | `ModuleManagerService.turnOn` | Turn on only turns the module on |
   | `HealthCheckExtensions.EXTENSION_CLASSES` (existing) gains `RollupsHealthCheckExtension` | `RollupsHealthCheckExtension`, holding the shipped rollups, nightly rollups and rollup queue checks | the three `HealthCheckSettingsChecks` rollup checks | no rollup findings |
   | `HealthCheckFixExtension` (new, optional second interface on a Health Check extension) with `fixKeys`, `fixScope`, `fixLabel`, `runFix` | `RollupsHealthCheckExtension` | the `restoreShippedRollups` branches in `HealthCheckService.fixScope` and `HealthCheckController` | the key is unknown and the fix is refused, as for any unknown key |
   | `NightlyJobs.PROVIDER_CLASSES` (existing) gains `RollupsNightlyJobProvider` | `RollupsNightlyJobProvider`, returning the former `NightlyJobs.RollupJob` | `RollupJob` in Core's list | the nightly jobs finding and fix do not name the rollup run |
   | `Setting_Definition__mdt.Navigation_Target__c` (existing, ADR-0020) | the `Rollup_Definitions` row: `Component__c` blank, `Navigation_Target__c` `Rollup_Builder` | the literal `rollupDefinitions` import in `settingsConsole` | no row, no Rollups section |
   | `ModuleManagerService.ownedObjects` and admin set map (existing) gain `Rollups` | n/a (names only) | nothing | the module lists as not installed |

   `ImportUndoBatch` keeps its own string constant for `Rollups_Last_Calculated__c` (a field
   Giving ships); `OrgOptimizerObjectChecks` drops `Rollup_Definition__c` from Core's list.
   `CorePostInstall` stops calling the engine. Import and Duplicates need no seam: their saves
   reach the engine only through the registry rows, which are absent with the module.

   `RollupEngineExtension` never gains a method once a module implements it: a class compiled
   against the old interface would no longer satisfy it, and the resolver would treat the
   installed module as absent. A new need gets a new interface (for example
   `RollupEngineExtensionV2`) that the module implements beside the first, and Core's resolver
   checks for it separately.
5. **The module's own post-install script.** `RollupsPostInstall` carries over the two rollup
   settings an org saved on `BarnCRM_Settings__c` (decision 6), calls
   `RollupService.ensureDefaultsDuringInstall` and assigns `Rollup_Builder_Admin` to the
   installer. ADR-0029's guarantees stand; Giving's script still runs its own call, now into the
   module.
6. **Its own settings object.** `Rollup_Mode_Default__c` and `Rollup_Processing__c` move from
   `BarnCRM_Settings__c` to `Rollup_Settings__c`, a protected hierarchy custom setting in the
   module (ADR-0017 decision 2); their Setting Definition rows name it in `Settings_Object__c`
   and their shipped defaults follow ADR-0035.
7. **Its own console app and Settings tab.** The module ships a console app, label
   `BarnCRM Rollup Builder`, with two navigation items: Rollup Builder (the existing tab) and
   Rollup Settings (new tab and app page). The Rollup Settings page hosts Core's
   `settingsConsole` with a new `module` property set to `Rollups`, which shows only that module's
   rows; the same rows stay in BarnCRM Settings (plan Section 4.8, one console). Core's
   BarnCRM app loses the Rollup Builder tab; the Hub's Modules card links the app (ADR-0018).
   **Amended 2026-10-26 (owner request RS1):** the Rollup Settings tab and app page are removed.
   The module's settings are only the Rollups section of BarnCRM Settings (Default rollup mode,
   When instant totals are calculated, and a Rollups row that opens the Rollup Builder tab).
   The console's `module` property stopped filtering with the Volunteer Settings tab, its last
   user. It stays declared and is ignored, because the platform refuses to remove a page
   property from a component that any Lightning page in the org places.
   A source deploy does not delete the old tabs from an org that has them; remove
   `Rollup_Settings` and `Volunteer_Settings` (tab and flexipage each) with a destructive deploy.
8. **Permission sets.** The rollup grants leave `BarnCRM_Admin`, `BarnCRM_Staff` and
   `BarnCRM_Read_Only` for `Rollup_Builder_Admin` (build, recalculate, retry, the queue) and
   `Rollup_Builder_User` (read the Builder and definitions, as Staff and Read Only can today).
   The engine's save path must run in system mode for every package-owned read and write
   (ADR-0021), so a user holding neither set still saves records and totals still update.
   One exception: publishing `Rollup_Queue_Ready__e` needs Create on the event, which only the
   module's sets grant (Core's sets cannot name a module object). A save publishes it whenever
   it has to announce waiting totals after commit: a save inside a Queueable, and a
   synchronous save whose processor request was already made or could not be queued
   (`RollupQueue.askAgainAfterCommit`). A user holding neither module set (an integration
   user, say) cannot publish it then: the save goes through, its entries stay queued and wait
   for the next processor run or the nightly run, and a Warning is logged. BarnCRM role
   holders get `Rollup_Builder_User` from `RollupAccessSync` (D2) at install, at each Turn on
   and with each scheduled nightly run; until a role holder has it, the same lag applies.

   `RollupAccessSync` reads, per set, every active holder of the audience sets and of the set
   itself through `TabAccessService.giveToHolders`, unbounded, and gives up to 4,000 a run.
   Both sets share one transaction's 50,000 query rows, so an org past about 20,000 BarnCRM
   role holders would stop the sync with a limit error (logged; the nightly run tries again).
   No org is near that; slicing the holder queries is the fix if one gets there. A slice whose
   every assignment is refused does not queue itself again.
9. **Turning the module off** (ADR-0073) stops its three registry rows through `Module__c`,
   `Rollup_Definition_Validation` included: it keeps its own switch (owner decision: no
   functionality is dropped), so a definition saved while the module is off is not checked.
   That is safe: `RollupPlanner` refuses a definition it cannot plan and logs it on every run,
   so the full recalculation Turn on starts skips it rather than writing a wrong total. The
   engine's entry points (`RollupTriggerHandler`, the
   queue processor, the nightly batch, the Flow action) also return early while `Rollups` is
   turned off, so Giving's four rollup rows stop too. One check, `RollupService.isTurnedOff`,
   reads `ModuleManagerService.turnedOff`; the real-time, delete, merge and Flow paths (Core's
   merge seam included), the queue processor and its start, the full runs (nightly,
   Recalculate all, Recalculate) and the scheduler all return on it, and a full run, a
   large-parent run or a merge's survivor job chains no next pass or job once it is off (an
   Info entry says so). Recalculate, Recalculate all and Run tonight refuse with a message;
   the Builder still saves and says the rollup is calculated once the module is on. Nothing is
   processed while it is off and queued entries wait. Turn on (`ModuleManagerService.turnOn`)
   calls the engine through `RollupEngineExtensionV2.afterModuleTurnedOn`, which starts the
   processor for the waiting entries and a full recalculation of every active definition,
   since saves made while it was off were not recorded (owner decision: totals are right after
   Turn on). Until this was built the Module Manager offered `Rollups` no switch.
10. **Giving depends on the module.** `sfdx-project.json`: Giving depends on Core and BarnCRM
    Rollup Builder; Funders and Connect list Core, BarnCRM Rollup Builder and Giving (2GP needs
    the transitive list, in install order). Giving's code, its 50 shipped defaults, its registry
    rows and its `Rollups_Last_Calculated__c` fields do not change; they now resolve against the
    module. Install order is Core, Rollup Builder, Giving.
11. **Edition catalog row.** One `BarnCRM_Module__mdt` record on the edition-gates branch: name
    `Rollups`, display name `BarnCRM Rollup Builder`, `Editions__c` `Community;Impact`,
    `Package_Folder__c` `rollups`, `Install_Version_Id__c` blank until published,
    `Sort_Order__c` 5 (before Giving at 10). The edition-gates switch list then drops its
    "Rollup Builder" Super Tool and its "rollups" Core feature group: the module switch replaces
    both. This ADR does not build the modules panel.
12. **CI and scripts.** `deploy-packages.sh` deploys Rollup Builder after Core and before Giving,
    skips it with `--core-only`, and runs `RollupService.ensureDefaults()` only when it was
    deployed; `check-standard-objects.sh` adds `packages/rollups` to `DIRS`, so the module must
    also run on a Platform-only org; `check-namespace.sh` already scans all of `packages/`;
    `check-tests-run-as.py`, `check-flow-templates.py`, `check-deploy-readiness.py` and
    `check-labels.py` (`PLACEHOLDER_PACKAGES`) learn the new folder; `run-org-tests.sh` finds it
    through its `packages/*.cls` glob, and a Core-only run must exclude it;
    `check-module-objects.py` matches `Rollups` to `packages/rollups` with no change.

## Alternatives considered

- **Keep the engine in Core behind a feature switch.** The edition-gates design already offers a
  switch. Rejected: a switch hides behavior, not schema (ADR-0003), and the case for the move is
  orgs that want no second engine installed.
- **Fold the engine into Giving.** Rejected: Standard Edition orgs want the Builder without
  Giving, and Volunteers or Programs may want totals without Giving.
- **One extension point per caller** (merge, resume, hub, data protection). Rejected: one module
  answers all of them, and one interface with seven methods is one resolver and one class to
  test instead of five.
- **Health Check findings that link to the Rollup Builder instead of a fix seam.** Smaller, but
  it turns a one-click fix into two steps; functionality is not dropped (owner rule).
- **A separate settings LWC in the module.** Rejected: it would copy the console's validation,
  audit and default logic; a `module` filter on the existing console reuses all of it.

## Consequences

- Core loses about 17k lines and 4 objects; Core-only and Platform-only orgs carry no rollup
  schema. An org running DLRS or Rollup Helper installs Core (and any module except Giving)
  without the engine.
- Giving cannot install without Rollup Builder; the installer refuses it. The Setup Assistant
  and the modules panel must offer Rollup Builder first (open decision D3).
- Two new Core interfaces and four reused registries become surface between packages; each is
  covered by Core tests through overrides (present, absent, throwing) and by module tests
  against the real classes.
- Development orgs (`oi-test`, `oi-pa`, `mwdbdevsb`) already hold every component under the same
  API names, so a redeploy with the new stage order is enough. Two orphans remain until removed
  with a one-time destructive deploy or a fresh org: the two fields left on `BarnCRM_Settings__c`.
  Their values are carried over: `RollupsPostInstall.carryOverCoreSettings`, run at install and
  by `deploy-packages.sh`, copies each non-blank value to `Rollup_Settings__c` while the module
  has saved no settings of its own, reading the old fields by name since Core no longer defines
  them. Once `Rollup_Settings__c` has a saved row it wins and nothing is copied again.
- The PR breakdown is in the pull request that adds this ADR. Docs move with each PR:
  canonical model Sections 12, 14, 14A and 32 before the settings object is added, the admin
  guide's rollups, module manager, Health Check, settings and editions pages, the feature
  catalog, and a `packages/rollups/README.md`.

## Owner decisions (decided 2026-10-14, each as recommended)

- **D1.** (Superseded 2026-10-26, see decision 7.) The Rollup Settings tab hosts Core's console filtered by module (decision 7), not a
  module-owned settings component.
- **D2.** Staff and Read Only keep a read-only Builder through `Rollup_Builder_User`, assigned
  to holders of `BarnCRM_Staff` or `BarnCRM_Read_Only` when the module is turned on, as Giving
  does for `Giving_Staff`. Built as `RollupAccessSync`: at install (after the installer's own
  grant, in the same job), at each Turn on and with each nightly run it
  gives `Rollup_Builder_User` to holders of those sets and `Rollup_Builder_Admin` to holders of
  `BarnCRM_Admin`, directly or through a permission set group, through Core's
  `TabAccessService.giveToHolders` (the module names the sets; Core names none of its). It
  never takes a set away (one given by hand, to the installer or an integration user, stays)
  and gives nothing while the module is turned off.
- **D3.** `BarnCRM_Module__mdt` gains `Requires__c` (module keys), so Giving's Install says to
  install Rollup Builder first and the Nonprofit Edition setup offers both. Built on the
  edition-gates stack.
- **D4.** The module switch replaces the edition-gates "Rollup Builder" Super Tool and "rollups"
  Core feature group (decision 11).
- **D5.** Moved labels and rows keep their `Core_` names (decision 2).
- **D6.** Health Check keeps the one-click Restore shipped rollups fix through
  `HealthCheckFixExtension` (decision 4).
- **D7.** Module key `Rollups`, folder `packages/rollups`, display name `BarnCRM Rollup Builder`.
