# ADR-NEXT: The edition, feature switches and first-run setup decide what BarnCRM shows

**Status:** Accepted (owner decisions, Brandon, 2026-10-14)
**Date:** 2026-10-14
**Source:** owner decisions of 2026-10-14 (A to H); builds on ADR-0122 (edition names); amends
ADR-0072 (suite choice is the first setup step), ADR-0062 (Giving installed offers every
module) and ADR-0073 (Module Manager)

## Context

ADR-0072 made the edition (stored in `BarnCRM_Settings__c.Suite__c` as `Community` or `Impact`)
the Setup Assistant's first step, and said it "installs, removes and hides nothing" and "can
be changed later". In practice the Standard Edition still listed Volunteers in the module
step, the Module Manager and the home Modules card, an installed Giving made every nonprofit
module appear in a Standard Edition org (ADR-0062), and Health Check suggested the Connect
module to any Nonprofit Cloud org. The step also kept offering the choice on every visit, so
a casual click could change what every admin and user sees.

The owner decided that nonprofit modules are not visible unless the Nonprofit Edition is
chosen, that the edition is chosen once, that features and modules can be switched on and off
from the General page with their tabs and settings hidden while off, and that a first-run
setup window asks the edition and what to turn on before anything else. The repo rule that
every admin setting lives in the in-app Settings console still holds.

Terms (owner, 2026-10-14): a **feature** is installed with Core and can be switched on or off
(including the tools the website calls Super Tools; that name is not used in the product). A
**module** is a separate package, not installed with Core, installed from Settings, General,
and named "BarnCRM" plus its name: BarnCRM Rollup Builder (both editions), BarnCRM Giving,
BarnCRM Volunteers, BarnCRM Programs, BarnCRM Funders and BarnCRM Connect. Rollup Builder
becomes a module; its package split is separate work, and BarnCRM Giving will depend on it.

## Decision

- **Visibility.** Core shows and offers the nonprofit modules (Giving, Volunteers, Programs,
  Funders, Connect) only when the Nonprofit Edition is chosen. With the Standard Edition, or no
  edition chosen, Core lists Core and any module that is already installed, and nothing else.
  One rule in `ModuleDetectionService.getModules()` feeds the Setup Assistant's module step,
  the Module Manager and the home Modules card. The Health Check Connect hint
  (`connect_module_absent`) appears only in the Nonprofit Edition.
- **Installed modules keep working.** The edition never installs, removes or turns off
  anything; an installed module stays listed in either edition.
- **The module catalog is data.** `BarnCRM_Module__mdt` ships one record per module: the
  editions that offer it, its label, its README folder, its installer version, an optional
  probe object (so BarnCRM Rollup Builder counts as installed while its objects still ship in
  Core) and its app name. A module both editions offer needs only a record.
- **Modules have their own apps.** Each module has its own Lightning app with its own Settings
  tab. The Core General page lists modules with their install state, an Install link when not
  installed, and a link to the module's app when it is; it does not host module settings. The
  module sections that still render in the Core console stay for now and move to each
  module's app as follow-up work.
- **Chosen once.** Once `Suite__c` has a value, the Setup Assistant's first step shows the
  edition read-only, also after Start again. The console's General section shows Edition
  read-only (`editionSetting`) with a collapsed "Change edition" disclosure for holders of
  Manage BarnCRM Settings, behind a confirmation; `SetupAssistantController.changeEdition`
  validates and audits it. Setup, Custom Settings (`Community` or `Impact`) also works; a value
  that is neither counts as no edition.
- **Switches (General, Modules and features).** One panel lists every switchable item: three
  tool features (Data Manager with Import, Find and Bulk Update; Duplicate Review; Org
  Optimizer and Health Check), five Core feature groups (household upkeep, addresses,
  relationships, affiliations, preferred email) and the modules offered in the edition.
  Existing switches are reused: modules use `Modules_Turned_Off__c` (ADR-0073), Core feature
  groups set their Automation Registry switches (on while any is on; rule-enforcing
  validations belong to no group), and only the tool features, which had no switch, get one
  new field, `Features_Turned_Off__c`. The rollup automations are not a Core group: they go
  with BarnCRM Rollup Builder. One Apex service
  (`FeatureSwitchService`) turns an item on or off, used by the panel and by first-run setup.
  The item list and the default selection are owner-overridable.
- **Off hides navigation.** While an item is off, its rows in BarnCRM Settings are hidden (a
  section left empty disappears) and its tabs are hidden. Salesforce shows a tab to anyone with
  a permission set granting it and offers no other way for an app to hide one. Checked
  options: (1) one packaged tab-only permission set per switchable tab, assigned by Core;
  (2) a muting permission set in each role group; (3) a permission set created at runtime
  whose tab setting rows Apex creates and deletes. Chosen: (1). Packaged sets upgrade and
  uninstall cleanly and need only `PermissionSetAssignment` DML, which Core already does at
  install. (2) mutes only grants that come through a group, so it cannot hide the tabs the
  directly assigned extra permissions (Find and Export, Bulk Update, Bulk Delete) grant, and
  changing a packaged group triggers an asynchronous recalculation. (3) would leave
  unpackaged permission sets behind and depends on `PermissionSetTabSetting` DML from Apex,
  which the API lists but no BarnCRM code has proven. The five switchable tabs (Data Manager,
  Import, Find, Bulk Update, Data Hygiene) are removed from every other packaged set (the
  Rollup Builder tab is left as it was until it moves to its module); `BarnCRM_Tab_<Tab>` grants each, and `TabAccessService` gives it to whoever
  holds a set that used to grant the tab, and takes it from everyone else or from everyone
  while the feature is off. It runs in system mode (the sets grant only a tab), in a queued job
  so a large org stays inside DML limits, and is triggered by a switch, by the Access page
  after a role or extra permission is given or removed, by every install and upgrade, and by a
  nightly job (roles given in Setup or by user access policies).
- **First-run setup.** While `Suite__c` is empty, the BarnCRM home page and BarnCRM Settings
  both show one component (`firstRunSetup`) in front of the page: the edition, then "Turn on
  all the default core features" (default) or "Let me choose" with every item ticked. Finish
  saves the edition and calls `FeatureSwitchService` for every item, then lands on Settings,
  General. Without Manage BarnCRM Settings the window only says an administrator needs to
  finish setting up BarnCRM. Once the edition is saved it never shows again, and the Setup
  Assistant's first step shows the edition read-only, so there is one edition picker.

## Alternatives considered

- **Keep Edition a plain picklist row.** Rejected: too easy to change.
- **Remove Edition from the console.** Rejected: breaks the in-app console rule.
- **Hide installed modules in the Standard Edition.** Rejected: an installed, running module
  would become unmanageable.
- **Hide a turned-off feature's page content instead of its tab.** Rejected by the owner: tabs
  must disappear.

## Consequences

- Volunteers is no longer offered in the Standard Edition; ADR-0062 decision 4 is superseded.
- BarnCRM Rollup Builder is listed in both editions and shows as installed while it ships in
  Core; its switch and tab follow the module once the package split lands.
- A module's own tabs are hidden only once that module ships tab-only sets on the same
  pattern; until then they follow the module's permission sets. Giving is the first follow-up.
- An upgraded org keeps every tab: nothing is listed as off, and the post-install run gives
  each tab set to everyone who had the tab before.
- A BarnCRM Tab set assigned by hand is removed by the next run.
- An org that had saved an edition before this release never sees the first-run window.
- The admin guide covers it in `editions.md`, `barncrm-settings.md`, `access.md` and
  `setup-assistant.md`.
