# ADR-NEXT: Settings as Custom Metadata: Defaults on Setting Definition, Changed Values in Setting Value, Run State on Nightly Job

**Status:** Accepted (owner decision D-219, 2026-11-21); phase 1 (Core) built, phase 2 Core
prerequisite built (decision 11), phase 2 module moves planned
**Date:** 2026-11-21
**Source:** Brandon, D-219: every BarnCRM setting lives in custom metadata (deployable), managed on
the BarnCRM Settings tab, module menus shown only when the module is installed, done before the
first package version. Design review option (i), release 1.34 item SET-01. Supersedes ADR-0006
decision 1 and the Platform Cache clause already replaced by ADR-0094; amends ADR-0017 decision
2, ADR-0035, ADR-0085, ADR-0087, ADR-0141, ADR-0166 and ADR-0227.

## Context

Settings were held in 21 protected hierarchy custom settings, one per package (ADR-0006
decision 1, ADR-0017 decision 2). Custom setting rows are data: they cannot be retrieved,
deployed or sent in a change set, so an admin cannot move a configured org's settings to a
sandbox or a new org as metadata, and each package's settings object counts toward the 200
custom object limit (ADR-0227). ADR-0006 rejected custom metadata in 2026-09 because saves
are asynchronous; the owner has now accepted that cost in exchange for deployable settings.

## Decision

1. **Defaults ship on `Setting_Definition__mdt`.** New field `Default_Value__c` (Text 255, a
   JSON literal: `true`, `90`, `"Both"`; blank means no default). Each package ships its own
   definitions, so a module's settings appear only where the module is installed (ADR-0059).
2. **Changed values live in `Setting_Value__mdt`** (Core, Public): one record per setting the
   org changed, DeveloperName equal to the definition's, `Value__c` (Text 255, JSON literal).
   No package ships a record. The effective value is the Setting Value when it exists and is
   not blank, else the definition's default. Public, not protected, so admins can retrieve,
   deploy and change-set the records; an edit in Setup is read too, and a value that does not
   parse falls back to the default.
3. **One read path.** `SettingStore` reads both types with `getAll()` (no SOQL), resolves value
   then default, and caches per transaction (ADR-0094: no Platform Cache). `SettingsService` is
   the only caller; `SettingsService.getSettings()` keeps returning a `BarnCRM_Settings__c`
   built in memory from the store, so every existing Core reader reads the new store unchanged
   until phase 2 moves readers to keys.
4. **One write path, asynchronous.** A save validates as before, then sends one
   `Metadata.Operations.enqueueDeployment` with every changed key. `SettingValueDeployCallback`
   writes one Setting Change per key with the deployment Id on success, then applies the save's
   side effects (app and tab sync, brand sharing, the seasonal job, the rollup engine); on
   failure it writes an Error Log entry referencing the deployment. The console shows
   "Saving..." and polls the outcome. Values saved in a transaction are read back in that
   transaction. Tests cannot deploy metadata, so the deployer is a seam: in a test it applies
   the values in memory and runs the callback at once (same pattern as ADR-0085).
5. **Install step.** A packaged, non-certified version saves only after the admin turns on
   "Deploy Metadata from Non-Certified Package Versions via Apex" in Setup, Apex Settings. It is
   documented as an install step until BarnCRM passes security review. Defaults work without it.
6. **Run state is not a setting.** Last runs, summaries, watermarks and setup markers move to
   rows of `Nightly_Job__c` (ADR-0166) with the new `Kind__c` = State, Name = the key, and the
   value in the new `Value__c` (Long Text, JSON). Written in system mode, synchronously; not
   deployable on purpose (it describes what ran in this org). `Shipped_Defaults_Applied__c`
   moves there too (module upgrades still use it until phase 2).
7. **Per-user values.** `BarnCRM_Automation_Control__c` stays a hierarchy custom setting (per-user
   bypass, `$Setup` in flows and formulas) and gains `Paused_Until__c`, the org pause end, read
   on every save beside `Pause_All__c` at no query cost. What's New dismissals move from
   `Whats_New_Seen__c` to `Nightly_Job__c` rows with `Kind__c` = Seen and Name
   `WhatsNew:<UserId>`. Chosen as the lightest structure: no new object, the object already has
   a system-mode writer and admin-only access, and the job registry skips non-job rows. A User
   field was rejected (a standard object outside the mirror package) and so was a new object.
8. **Is Organization is kept, not computed.** `Account.Is_Organization__c` is a formula over
   `$Setup.BarnCRM_Settings__c.Organization_Record_Type__c`; a packaged formula cannot read an
   org-created custom metadata record. The platform refuses to turn a formula field into
   another type, so a new checkbox `Account.Is_Organization_Account__c` takes its place: the
   Account handler sets it on every insert and update from `AccountKinds.isOrganization`, and
   `OrganizationFlagBatch` puts right every account that disagrees when the setting changes and
   on each install. List views, record page rules, the address flow and donor segments read the
   checkbox. The formula field stays, unused, until phase 2 removes it with
   `BarnCRM_Settings__c` (amends ADR-0141).
9. **Carry-over.** Values an org saved in the old custom settings are read while the hidden
   marker `Settings_Carried_Over` is not true, so an upgraded org runs on its own values from
   the moment it upgrades. The console's Carry Over Settings action (shown to settings admins
   while the org has legacy values) deploys every saved value that differs from its default
   as Setting Value records plus the marker in one deployment, copies run state and What's New
   dismissals to their rows, and moves a running pause to Automation Control.
10. **Phases.** Phase 1 moves Core (`BarnCRM_Settings__c`, `Whats_New_Seen__c`, the pause).
    Phase 2 moves every module settings object, then the integrator removes the old objects in a
    destructive deploy. `Automation_Setting__c` (the automation switch list) is not a setting
    store in this sense and stays an object.
11. **Modules register; Core names none** (amendment, SET-02). A module moves by shipping, in
    its own package, one `Setting_Module__mdt` record (`Settings_Object__c` its settings group,
    the legacy object's name; `Key_Prefix__c` its state prefix; `State_Fields__c` its legacy
    state fields) and a `Default_Value__c` on each of its Setting Definition rows. From then on
    `SettingsService` reads and saves every row of that group through the store from the
    definitions alone (no describe, so the group outlives its object), the console's existing
    module sections included; `ModuleSettings` gives module code typed reads by DeveloperName
    and the same save. A console save touching Core and modules is one deployment
    (`SettingsService.collectSaves`), and a module's own page follows its save with the shared
    `c/settingSaveOutcome`. Module run state is `SettingsState` rows named `Prefix.Name`; a run
    lock is one such row read `FOR UPDATE` (`SettingsState.lockOrCreate`), replacing
    `Rollup_Run_Lock__c`. Carry-over reads each registered group's legacy record through
    describe and skips a group whose object is gone. Until carry-over, a module key with no
    Setting Value reads its legacy field, but only in an org that saved Core's legacy settings,
    so a fresh org spends no query on it. One marker covers Core and every module: a module
    upgraded after the org carried over starts on its defaults (acceptable while no package
    version exists). Rejected: a registry on `BarnCRM_Module__mdt` (Core ships those records,
    so a module could not add its own), a registry encoded as a special Setting Definition row
    (mixes console rows with package wiring), and a unique key field on `Nightly_Job__c` for the
    lock (the module creates its lock row at install instead; no schema change). How a module
    declares and reads settings: `docs/contributor-guide/module-settings.md`.

## Alternatives considered

- **A Core key/value custom object** (option iii): synchronous, not deployable as metadata;
  rejected by the owner. The store is one class, so it could still be swapped in.
- **One Core hierarchy custom setting for all modules**: Core would name module fields
  (ADR-0059) and settings would still be data.
- **Subscriber-editable fields on shipped definition records**: deploying edits to managed
  records is unverified and mixes the package's rows with the org's choices (ADR-0170).

## Consequences

- Saves take seconds, longer when another deployment is queued; reads elsewhere see the old
  value until the deployment completes. ADR-0006's "takes effect immediately" no longer holds.
- `SettingsService.SHIPPED_DEFAULTS`, the first-save blank handling and ADR-0035's trap no
  longer apply to Core: a setting added in an upgrade has no Setting Value, so its default
  applies. `check-setting-defaults.py` checks Core defaults on the definitions instead.
- Apex cannot delete a custom metadata record, so every value is stored explicitly: keeping a
  shown default saves it as a Setting Value, and a record left blank in Setup reads the default.
- Module menus need no switch of their own: a module's definitions ship in its package, so its
  sections and settings appear on the BarnCRM Settings tab only where it is installed.
- A module's Setting Value records outlive its uninstall and are ignored.
- The deployment callback runs as the platform's automated process user, not the saver; the
  audit row carries the saver from the save request.
- After phase 2 the suite counts 181 objects (180 custom objects plus Automation Control).
