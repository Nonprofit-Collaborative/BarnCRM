# BarnCRM Core

Core is the foundation package. Every other BarnCRM module depends on it, and it depends on
nothing else. It contains no Opportunity, Campaign, Case, Lead, Person Account, or Industries
object references: those live only in the Mirror module, behind dynamic Apex.

## What Core contains

- **Constituent model**: Contacts, Accounts (Household and Organization record types),
  Household membership (contact mode and junction mode via `HouseholdService`),
  Relationships, Affiliations, and Addresses (`Address__c`).
- **BarnCRM app**: the Lightning app and its tabs (Home, Households, Contacts,
  Organizations, Import, Reports, BarnCRM Settings). Each module adds its own tabs (Volunteers, for
  example) when it is installed.
- **Settings framework**: the BarnCRM Settings console (LWC-based), protected hierarchy
  Custom Settings for simple toggles, custom objects for structured configuration, and Custom
  Metadata Types for package-shipped defaults. The console's rows come from
  `Setting_Definition__mdt`, so a feature adds its settings to the console by shipping rows
  rather than by editing the console.

  **No Platform Cache.** Settings and the shipped custom metadata are read through the
  platform's own caches (`getOrgDefaults()` and custom metadata `getAll()`), which cost no
  query and are refreshed when a save commits, plus a per-transaction static cache that every
  write clears. Core ships no cache partition and needs no cache allocation (ADR-0094). A
  `BarnCRMSettings` partition created for an earlier version is no longer used and can be
  deleted.
- **Trigger framework**: one trigger per object, bypassable handlers, a pause-all switch.
- **Error Log** (`Error_Log__c`): every caught exception with context, user, record, and a
  plain-language message, published as a platform event so the entry survives the rollback it
  documents.
- **Rollup seam**: `RollupEngineExtension`, the interface Core's saves and merges call to
  recalculate totals, and `RollupFilterParser`, the filter grammar Core's saved queries share.
  The engine itself, `Rollup_Definition__c` and the Rollup Builder are the BarnCRM Rollup
  Builder module (`packages/rollups`, ADR-0125); without it Core's calls do nothing.
- **Import framework**: `Import_Template__c`, `Import_Batch__c`, `Import_Row__c`, and the
  wizard that lets an admin load a spreadsheet without a consultant.
- **Health Check**: org shape and license detection, missing permission assignments, orphaned
  records, coexistence conflicts, and the checks modules add through `HealthCheckExtension`
  (rollup schedule staleness comes from the Rollup Builder module).

## Trigger framework

One trigger per object, one line in it, and every automation switchable from the app.

```apex
trigger ContactTrigger on Contact(
    before insert,
    after insert,
    before update,
    after update,
    before delete,
    after delete,
    after undelete
) {
    TriggerDispatcher.run('Contact');
}
```

That is the whole trigger. The dispatcher reads `Automation_Registry__mdt` for that object, in
`Execution_Order__c` order, builds each `Handler_Class__c` with `Type.forName` (qualified with the
running package's namespace, falling back to the bare name when there is none), and runs each one
(ADR-0017). A module ships its handler class and its registry record and never edits another
feature's trigger or handler. A handler that cannot be built is skipped with a warning in the
Error Log: one broken automation does not stop a person saving a record.

`TriggerDispatcher.run(new ContactTriggerHandler())` remains, for tests and for an object with
exactly one handler.

A handler extends `TriggerHandler` and overrides only the contexts it needs. **Every context
method takes no arguments, and the handler reads its own records from the trigger context.** That
is the contract every feature module is written against:

```apex
public class ContactTriggerHandler extends TriggerHandler {
    public override void beforeInsert() {
        for (Contact person : (List<Contact>) Trigger.new) {
            person.LastName = person.LastName.trim();
        }
    }

    public override void afterUpdate() {
        HouseholdNamingService.rename(Trigger.newMap.keySet());
    }
}
```

The seven overridable methods are `beforeInsert()`, `afterInsert()`, `beforeUpdate()`,
`afterUpdate()`, `beforeDelete()`, `afterDelete()`, and `afterUndelete()`, plus `getName()`, which
returns the automation's stable name and defaults to the class name with any namespace stripped.
The bodies read `Trigger.new`, `Trigger.old`, `Trigger.newMap`, and `Trigger.oldMap`.

Outside a trigger those collections are null, so a unit test that wants to drive a handler without
inserting records sets the `TriggerHandler` test overrides and the handler reads them through the
matching accessor:

```apex
TriggerHandler.testNew = (List<SObject>) records;
TriggerHandler.testNewMap = new Map<Id, SObject>(records);
TriggerDispatcher.run(new ContactTriggerHandler(), context);
```

`newRecords()`, `newRecordsById()`, `oldRecords()`, and `oldRecordsById()` return the override when
a test has set one and the trigger collection otherwise, so a handler written against them behaves
the same in both places.

The dispatcher works out which context it is in, then checks three things before it invokes
anything: a per transaction
bypass (`AutomationControl.bypass(name)`), the org wide pause
(`BarnCRM_Settings__c.Automation_Paused_Until__c`), and the automation's own switch (a row on
`Automation_Setting__c`, keyed by the registry's developer name). Anything a handler throws is
written to the Error Log first, then reported to the person saving the record: `addError` with a
plain language message in a before context, a rethrow in an after context.

A handler guards itself against recursion with `claimRunFor(phase, recordIds)`, which hands back
the records this handler has not already processed in this transaction. The guard is per record on
purpose: one DML of 400 records fires the trigger twice with statics preserved, so a guard that
claimed the whole phase would process 200 records and silently skip the rest.

Whatever a handler throws reaches the Error Log through an `Error_Log_Event__e` platform event
published immediately, not through an insert. Almost every failure worth recording ends in a
rollback, and an insert in that transaction would be rolled back with it: the entry that says what
went wrong would disappear exactly when it is needed. `ErrorLogWriter` publishes,
`ErrorLogEventTrigger` and `ErrorLogEventHandler` write the row, and a direct system mode insert
remains only as the fallback for when publishing itself fails.

A handler another package ships must be `public`, annotated `@NamespaceAccessible`, and have a
no-argument constructor, so that `Type.forName` can build it. Core's own shared classes
(`TriggerDispatcher`, `TriggerHandler`, `AutomationControl`, `ErrorLogger`, `SettingsService`,
`TestDataFactory`) are `public` and `@NamespaceAccessible` for the same reason, and never `global`
(ADR-0017): `global` is a permanent API commitment, and this is internal plumbing.

An automation with no `Automation_Setting__c` row still runs, so a newly shipped automation works
the moment it is installed. `AutomationControl.ensureDefaults()` materializes the missing rows
from `Automation_Registry__mdt` and never touches a row the administrator already has.

**v0.1 ships the framework with no triggers and an empty registry.** Feature C-01 adds the first
two handlers, their triggers, and their `Automation_Registry__mdt` records in one change.

## Post-install script

`CorePostInstall` implements `InstallHandler`. It runs after the package is installed and
after every upgrade. Its first job is to make sure the installing user can open BarnCRM
Settings; it also sets the recommended coexistence mode, the Automation page's switch rows
and the shipped import templates (the class comment has each).

Without the access step, a fresh install leaves the console read only for everybody, including
the System Administrator who installed it, because a custom permission is not implied by
Modify All Data.

That takes two steps, because the platform makes the obvious one unreliable:

1. **Assign the `BarnCRM_Admin` permission set.** A permission set has no calculation
   status, so this works the moment the install finishes. This is the step that matters:
   after it, the installer can use the app.
2. **Assign the `BarnCRM_Admin_Group` permission set group**, which is the role the
   Access page shows. Salesforce recalculates packaged groups in the background after an
   install and refuses to assign one while that is running, which is the usual state in the
   first minutes, so this is attempted and, if the group is not ready,
   `CorePostInstallRetryQueueable` waits and looks again up to five times, one chained job
   at a time. If it runs out of attempts it writes a warning to the Error Log naming the
   one manual step left, and stops.

Both steps are safe to run twice: a person who already holds a permission set or a role is
left alone, so an upgrade is a no-op for an org that is already set up. Nothing throws: an
install must never fail because of a bootstrap step, so every failure goes to the Error Log
instead.

Core creates no Rollup Definitions: the engine is the BarnCRM Rollup Builder module, and
its `RollupsPostInstall` creates the shipped ones (ADR-0029, ADR-0125). Giving makes the
same call from `GivingPostInstall` for its own.

Once package versions exist, `sfdx-project.json` names it for the Core package directory:

```json
"postInstallScript": "CorePostInstall"
```

That line is not in `sfdx-project.json` yet, because no package version has been created
(the namespace is deferred, plan Section 4.3). Whoever creates the first Core package
version adds it then. Until then the same effect is achieved by the org scripts, which
assign the permission sets after deploying:
a source deployment runs no post-install script.

## Third party code

Core carries none. The vendored [apex-rollup](https://github.com/jamessimone/apex-rollup) engine
(MIT, James Simone) was replaced by BarnCRM's own rollup engine and deleted in rollup slice S9
([decision](../../docs/architecture/decisions/0082-barncrm-owns-its-rollup-engine.md)).
That engine is now the BarnCRM Rollup Builder module (ADR-0125).

## Iteration

Core first ships in **v0.1** and is required by every later iteration; it is the only package
present in v0.1.

## Testing Core alone

Core has no dependencies, so it can be deployed and tested by itself in an empty scratch org:

```bash
sf org create scratch --definition-file config/scratch-defs/platform-only.json \
  --alias core-dev --set-default --wait 15
sf project deploy start --source-dir packages/core --wait 30
```

Run Apex tests scoped to Core only:

```bash
sf apex run test --test-level RunLocalTests --code-coverage --result-format human
```

Run LWC Jest tests for Core's components only:

```bash
npx sfdx-lwc-jest --config-path packages/core/main/default/lwc
```

Because Core has no hard reference to Sales Cloud objects, it must deploy and pass its tests on
the **Platform-only** scratch org shape (`config/scratch-defs/platform-only.json`), which is the
strictest of the four shapes and the one CI treats as the floor.
