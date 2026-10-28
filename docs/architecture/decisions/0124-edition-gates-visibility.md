# ADR-0124: The edition, features, modules and first-run setup decide what BarnCRM shows

**Status:** Accepted (owner decisions, Brandon, 2026-10-14)
**Date:** 2026-10-14
**Source:** owner decisions of 2026-10-14 (A to H, then the terms, the BarnCRM module names,
off-by-default one-way features and the Modules section); builds on ADR-0122 (edition names);
amends ADR-0072 (suite choice is the first setup step), ADR-0062 (Giving installed offers every
module) and ADR-0073 (Module Manager)
**Amended by:** ADR-NEXT (D-134): a feature can carry an access set; Household Upkeep carries
  `BarnCRM_Households` (the Household record type and the Households tab), so both stay hidden
  while it is off.

## Context

ADR-0072 made the edition (stored in `BarnCRM_Settings__c.Suite__c` as `Community` or `Impact`)
the Setup Assistant's first step, and said it "installs, removes and hides nothing" and "can
be changed later". In practice the Standard Edition still listed Volunteers in the module
step, the Module Manager and the home Modules card, an installed Giving made every nonprofit
module appear in a Standard Edition org (ADR-0062), and Health Check suggested the Connect
module to any Nonprofit Cloud org. The step also kept offering the choice on every visit, so
a casual click could change what every admin and user sees.

The owner decided that nonprofit modules are not visible unless the Nonprofit Edition is
chosen, that the edition is chosen once, that Core's features are off on a new install until
an administrator turns them on (and stay on once on), with their tabs and settings hidden
while off, that modules are installed only from their own Settings section, and that a
first-run setup window asks the edition and which features to turn on before anything else.
The repo rule that every admin setting lives in the in-app Settings console still holds.

Terms (owner, 2026-10-14): a **feature** is installed with Core and is turned on when wanted
(including the tools the website calls Super Tools; that name is not used in the product). A
**module** is a separate package, not installed with Core, installed from BarnCRM Settings,
Modules, and named "BarnCRM" plus its name: BarnCRM Rollup Builder (both editions), BarnCRM
Giving, BarnCRM Volunteers, BarnCRM Programs, BarnCRM Funders and BarnCRM Connect. Rollup
Builder becomes a module (its own decision record, ADR-0125); its package split is
separate work, and BarnCRM Giving will depend on it.

## Decision

- **Visibility.** Core shows and offers the nonprofit modules (Giving, Volunteers, Programs,
  Funders, Connect) only when the Nonprofit Edition is chosen. With the Standard Edition, or no
  edition chosen, Core lists Core, the modules both editions offer, and any module that is
  already installed. One rule in `ModuleDetectionService.getModules()` feeds the Setup
  Assistant's module step, the Modules section and the home Modules card. The Health Check
  Connect hint (`connect_module_absent`) appears only in the Nonprofit Edition.
- **Installed modules keep working.** The edition never installs, removes or turns off
  anything; an installed module stays listed in either edition.
- **The module catalog is data.** `BarnCRM_Module__mdt` ships one record per module: the
  editions that offer it, its label, its README folder, its installer version, an optional
  probe object (so BarnCRM Rollup Builder, record `Rollups`, counts as installed while its
  objects still ship in Core) and its app name. A module both editions offer needs only a
  record. A `Requires__c` field (proposed by ADR-0125, so Giving can say
  "install Rollup Builder first") fits the same type and is left to that work.
- **Modules section.** Modules get their own BarnCRM Settings section, **Modules** (the Module
  Manager, ADR-0073), not General. It lists the modules the edition offers: Not installed with
  an Install link to Salesforce's installer, or Installed with a link to the module's own app.
  Nothing installs a module except the administrator from there; first-run setup does not.
  Each module has its own Lightning app with its own Settings tab; Core does not host module
  settings. The module sections that still render in the Core console stay for now and move
  to each module's app as follow-up work. A module's own on/off is the Module Manager's
  (`Modules_Turned_Off__c`); for Rollup Builder it replaces any rollups switch in Core.
- **Chosen once.** Once `Suite__c` has a value, the Setup Assistant's first step shows the
  edition read-only, also after Start again. The console's General section shows Edition
  read-only (`editionSetting`) with a collapsed "Change edition" disclosure for holders of
  Manage BarnCRM Settings, behind a confirmation; `SetupAssistantController.changeEdition`
  validates and audits it. Setup, Custom Settings (`Community` or `Impact`) also works; a value
  that is neither counts as no edition.
- **Features (General), off by default and one-way.** General lists eight features: three
  tools (Data Manager with Import, Find and Bulk Update; Duplicate Review; Org Optimizer and
  Health Check) and five Core feature groups (household upkeep, addresses, relationships,
  affiliations, preferred email). One new field, `Features_Turned_On__c`, lists the features
  that are on. A new install stores `None` there, so every feature starts off. An org upgraded
  from a release before this one has it empty, which means every feature is on, so nothing an
  existing org uses disappears. Turning a feature on adds it to the list, switches on its
  Automation Registry switches (for a group) and queues its tabs; there is no way back, and the
  page says so above the switches and asks for confirmation. While a group is off,
  `AutomationControl.isEnabled` reports its automations off whatever their own switches say,
  as it already does for a module turned off. Rule-enforcing validations belong to no feature
  and always run; the rollup automations belong to BarnCRM Rollup Builder. One Apex service
  (`FeatureSwitchService`) turns a feature on, used by General and by first-run setup. The
  feature list and the default selection are owner-overridable.
- **Off hides navigation.** While a feature is off, its rows in BarnCRM Settings are hidden (a
  section left empty disappears) and its tabs are hidden. Salesforce shows a tab to anyone with
  a permission set granting it and offers no other way for an app to hide one. Checked
  options: (1) one packaged tab-only permission set per feature tab, assigned by Core;
  (2) a muting permission set in each role group; (3) a permission set created at runtime
  whose tab setting rows Apex creates and deletes. Chosen: (1). Packaged sets upgrade and
  uninstall cleanly and need only `PermissionSetAssignment` DML, which Core already does at
  install. (2) mutes only grants that come through a group, so it cannot hide the tabs the
  directly assigned extra permissions (Find and Export, Bulk Update, Bulk Delete) grant, and
  changing a packaged group triggers an asynchronous recalculation. (3) would leave
  unpackaged permission sets behind and depends on `PermissionSetTabSetting` DML from Apex,
  which the API lists but no BarnCRM code has proven. The five feature tabs (Data Manager,
  Import, Find, Bulk Update, Data Hygiene) are removed from every other packaged set (the
  Rollup Builder tab is left as it was until it moves to its module); `BarnCRM_Tab_<Tab>`
  grants each, and `TabAccessService` gives it to whoever holds a set that used to grant the
  tab once the feature is on, and takes it from everyone else (from everyone while the feature
  is off). It runs in system mode (the sets grant only a tab), in a queued job so a large org
  stays inside DML limits, and is triggered by turning a feature on, by the Access page after a
  role or extra permission is given or removed, by every install and upgrade, and by a nightly
  job (roles given in Setup or by user access policies). Since features are one-way, taking
  tab sets away only ever corrects a hand assignment or a lost role.
- **First-run setup.** While `Suite__c` is empty, the BarnCRM home page and BarnCRM Settings
  both show one component (`firstRunSetup`) in front of the page: the edition, then "Turn on
  all the default core features" (default) or "Let me choose" with every feature ticked to
  untick. Finish saves the edition and turns on every ticked feature through
  `FeatureSwitchService`; unticked ones stay off until turned on in General. No module is
  installed. It then lands on Settings, General. Without Manage BarnCRM Settings the window
  only says an administrator needs to finish setting up BarnCRM. Once the edition is saved it
  never shows again, and the Setup Assistant's first step shows the edition read-only, so
  there is one edition picker.

## Alternatives considered

- **Keep Edition a plain picklist row.** Rejected: too easy to change.
- **Remove Edition from the console.** Rejected: breaks the in-app console rule.
- **Hide installed modules in the Standard Edition.** Rejected: an installed, running module
  would become unmanageable.
- **Hide an off feature's page content instead of its tab.** Rejected by the owner: tabs must
  disappear.
- **Features that switch both ways.** Rejected by the owner: turning a feature off after its
  data exists invites half-maintained records; on is permanent.
- **Store the features that are off.** Rejected once features became off by default: an
  empty list would have to mean both "upgraded, all on" and "new, all off".

## Consequences

- Volunteers is no longer offered in the Standard Edition; ADR-0062 decision 4 is superseded.
- BarnCRM Rollup Builder is listed in both editions and shows as installed while it ships in
  Core; its on/off and tab follow the module once the package split lands.
- A module's own tabs are hidden only once that module ships tab-only sets on the same
  pattern; until then they follow the module's permission sets. Giving is the first follow-up.
- An upgraded org keeps every feature and every tab: `Features_Turned_On__c` is empty, which
  means all on, and the post-install run gives each tab set to everyone who had the tab before.
- A new install runs no Core automation until first-run setup turns its feature on. With
  household upkeep off that includes two guards that are not about creating households:
  `refuseHandSetPrimaryContacts` (junction mode refuses a hand edit of Primary Contact) and the
  junction-mode `beforeDelete` membership cleanup on Contact, so before setup a Primary Contact
  can be set by hand and deleting a contact leaves its membership rows naming nobody.
- Turning household upkeep on queues one batch (`HouseholdCatchUpBatch`) that gives a
  household to every contact added while it was off, in the mode in force, through the same
  `HouseholdService` methods the trigger uses. The other four feature groups are not caught
  up: their records settle on their next save, or not at all.
- An upgrade that finds no edition saved saves the recommended one (the Standard Edition when
  nothing points to the Nonprofit one), so an upgraded org never sees the first-run window.
  Every install and upgrade also schedules the nightly tab access check if it is not already.
- A BarnCRM Tab set assigned by hand is removed by the next run.
- An org that had saved an edition before this release never sees the first-run window.
- First-run setup shows while `Suite__c` is empty or `Features_Turned_On__c` is `None`, so an
  edition typed in Setup, Custom Settings before first-run setup still leads to the feature
  choice, with that edition pre-selected. Finishing always moves the list off `None`: to the
  keys turned on, or to `NoneChosen` when every feature was unticked, which counts as none on
  and setup done. The window therefore cannot loop, and an upgraded org (an empty list) never
  sees it once an edition is saved.
- The admin guide covers it in `editions.md`, `barncrm-settings.md`, `access.md`,
  `module-manager.md` and `setup-assistant.md`.
