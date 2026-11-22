# Module settings

How a module declares, reads and saves its settings and keeps its run state, in the settings
store (ADR-0238 settings as custom metadata, decision 11; canonical model Section 13, R-STV4).
Core names no module: everything below ships in the module's own package.

## 1. Declare

1. **One `Setting_Module__mdt` record**, DeveloperName the module's name (as on its BarnCRM
   Module record), file `customMetadata/Setting_Module.<Module>.md-meta.xml`:
   - `Settings_Object__c`: the group the module's Setting Definition rows name, which is its
     legacy hierarchy custom setting's API name without a prefix (`Giving_Settings__c`). Keep
     it after the object is removed: it is the group name from then on.
   - `Key_Prefix__c`: the prefix of its state rows (`Giving`). Letters, digits, underscores;
     unique across modules.
   - `State_Fields__c`: the legacy fields that are run state (last runs, watermarks, setup
     markers, summaries), comma separated. Carry-over copies each to its state row and never
     carries it as a setting.
2. **One `Setting_Definition__mdt` row per setting**, as today, with `Default_Value__c` a JSON
   literal: `true`, `30`, `"Contact"`. Checkbox, Number and Picklist rows must ship one; a row
   whose legacy field declares a default ships the same value. A value the module writes for
   itself, never shown on the console, is a `Hidden` row with its `Setting_Key__c`.
3. **Keys are unique across packages.** The store names a value by the row's DeveloperName and
   every package shares one namespace, so two packages cannot ship the same DeveloperName, and
   group plus key cannot repeat. Prefer the module's name at the front of a new DeveloperName.

`check-setting-defaults.py` enforces 2 and 3 and the registry's shape; `check-custom-metadata.py`
stops requiring a registered group's keys to be fields of an object.

Nothing else changes for a row to appear on BarnCRM Settings: the console's module sections
read and save a registered group through the store as soon as the registry record ships.

## 2. Read

`ModuleSettings` (Core, `@NamespaceAccessible`), by DeveloperName. Each answers the org's
Setting Value, else (before carry-over) the legacy field's value, else the default, and never
throws:

| Getter | Returns |
|---|---|
| `flag(name)` | Boolean, false when nothing is set |
| `number(name)` | Decimal; the default when the saved one is not a number or is outside the row's Min and Max |
| `integerValue(name)` | Integer from `number` |
| `text(name)` | trimmed String, null when blank |
| `dateValue(name)` | Date from `yyyy-MM-dd` text |
| `datetimeValue(name)` | Datetime from ISO 8601 text |
| `value(name)` | the raw parsed value (Boolean, Integer, Decimal, String) |

`SettingsService.flag/number/text/getValue(group, key)` keep working for a registered group,
so a module can move its readers in any order. Replace every `X_Settings__c.getOrgDefaults()`
and `SettingsRecordSelector` read of the module's object; a formula, validation rule or flow
that reads `$Setup.X_Settings__c` cannot read custom metadata records an org creates, so that
logic moves to Apex.

## 3. Save

- From the console: nothing to do. A save that touches Core and modules is one deployment.
- From the module's own page: `ModuleSettings.save(Map<String, Object> valuesByName)` (console
  rows) or `ModuleSettings.saveSystem(...)` (Hidden rows too). Both validate as the console
  does, need Manage BarnCRM Settings, deploy once, write the Setting Change rows when the
  deployment succeeds, and return the deployment Id (null in a test). Return that Id to the
  page and follow it with `waitForSave(deploymentId)` from `c/settingSaveOutcome`: it resolves to
  Succeeded, Failed (with Salesforce's reason) or Pending.
- Values saved are read back in the same transaction; other transactions see them once the
  deployment ends. Never save from a trigger or a scheduled job: that is run state.
- Tests: `ModuleSettings.setForTest(name, value)` puts a value in the store as if deployed; a
  save in a test applies at once and runs the callback (no metadata is deployed).

## 4. Run state

`SettingsState` (Core), synchronous, system mode, rows of `Nightly_Job__c` (Kind State):

- Key: `SettingsState.moduleKey(prefix, name)`, for example `Rollups.Last_Run_Started__c`.
- `put(Map<String, Object>)`, `get`, `text`, `flag`, `number`, `moment`.
- A run lock: `SettingsState.lockOrCreate(key)` takes `FOR UPDATE` on the row until the
  transaction ends and returns its value, creating it when missing. Create the row at install
  (`put` in the post-install class) so two first runs cannot each make one. A wait that times
  out throws `QueryException`: treat it as busy.
- Until carry-over, a key with no row reads the legacy field of that name.

## 5. Carry-over and removal

The console's Carry Over Settings covers every registered module whose legacy object the org
still has: values with a definition join the one deployment, `State_Fields__c` become state
rows. After the module moves, the integrator removes its legacy object (and any field or
object that only held settings) in the destructive deploy; carry-over then skips the group.
