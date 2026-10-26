# ADR-0138: Instant Totals on Any Object: the Builder Generates the Trigger, the Admin Deploys It

**Status:** Proposed (builder decision, under the owner's instruction to close gap 2: "Please
resume work to close gap 2 now instead of waiting", Brandon, 2026-10-26)
**Date:** 2026-10-26
**Source:** rollup parity gap report section 3c (gap 2); amends ADR-0082 amendment A2
(decision 8 and its failure-mode mitigations); brings rollup slices S16 and S17 forward from
after version 1 (D-64); canonical model R-R12

## Context

A rollup is instant only when a trigger on its source object hands each save to the engine.
BarnCRM ships that trigger for its own objects (Automation Registry rows naming
`RollupTriggerHandler`). Every other object, a standard object, another package's object or
the organization's own, recalculates only in the nightly run and on Recalculate, unless the
admin copies the Flow template. That is gap 2. Once the Builder offers standard objects
(ADR-0136), it is also the gap between a DLRS rollup and its BarnCRM import.

ADR-0082 decision 8 (amendment A2) chose DLRS's answer: the Builder generates a one-line
trigger and its test and deploys them for the admin through the Metadata API, in one click.
Slice S15 (`feature/rollup-s15-spike`) built a candidate connection: a Named Credential
created at run time with ConnectApi, and the session id of a queued job passed to the
Metadata API SOAP `deploy` call. D-64 then deferred S16 and S17 to after version 1.

What the one click needs, and why it is not taken now:

- Apex's own `Metadata` namespace cannot deploy a trigger or a class, and a production org
  refuses Apex written in Setup or the Developer Console. Only a Metadata API deploy reaches
  production.
- A callout to the org's own Metadata API needs an API-enabled session. A Lightning session is
  not one. The S15 path (a queued job's session id) was never run on an org, and a session id
  sent in a callout is a standard security review finding. The supported alternative, an OAuth
  Named Credential, needs an External Client App and an Auth Provider set up in each org: more
  setup than the copy and change set it would save.
- About 400 lines of callout, polling and failure handling, a packaged External Credential,
  and a deploy permission would ship to every org, for a step most admins do once per object.

## Decision

1. **Any object that can have a trigger.** The Builder offers instant totals for any object a
   rollup counts that has no packaged BarnCRM real time (no registry row running
   `RollupTriggerHandler`) and that the platform lets carry an Apex trigger
   (`EntityDefinition.IsApexTriggerable`). Names come from describe and the definitions at run
   time: no BarnCRM
   source names a standard object (`check-standard-objects.sh`), and generated code is a
   string the Builder builds, not a repository file.
2. **The generated code.** The trigger is named `BarnRollup_` plus the object's API name with
   every run of characters other than letters and digits made one underscore (`Shift__c`
   gives `BarnRollup_Shift_c`); a name that would leave the test class over 40 characters is
   cut and ends in six characters of the name's MD5 hash. The test class is the trigger's name
   plus `_Test`. The same object gives the same names and code in every org. The trigger runs
   on before insert, after insert, after update, before delete, after delete and after
   undelete, and its body is one line, `RollupInstantTrigger.run();`, with the namespace
   prefix added at run time once there is one (never hard-coded). The test inserts one empty
   record with `allOrNone` false and asserts `RollupInstantTrigger.hasRun()`: the before
   insert trigger runs before required fields and validation rules are checked, so the org's
   own rules may refuse the record and the test still covers the trigger's only line (the
   DLRS `testHandler` pattern, without a test-code field to edit).
3. **The admin deploys it; the Builder does not.** "Turn on instant totals" shows the code
   with Copy buttons, a **Download deploy package** (a Metadata API zip: `package.xml`, the
   trigger, the test, their `-meta.xml` files) and the steps:
   - in a sandbox (or a Developer Edition org), create the test class and the trigger in the
     Developer Console from the copied code, then send both in an outbound change set and
     deploy it to production with **Run specified tests** naming only the test class; or
   - with the Salesforce CLI, deploy the downloaded zip with `--test-level
     RunSpecifiedTests` naming the test class, to a sandbox or to production.

   Only the generated test runs, so failing tests elsewhere in the org do not block it
   (ADR-0082's mitigation, kept). Everything happens in Salesforce; the CLI is optional.
   No callout, Named Credential, session id or External Credential ships. The platform's own
   permissions govern the deploy (Author Apex in the sandbox; deploying change sets in
   production), so the separate BarnCRM deploy permission of ADR-0082 is not added: the
   Builder only shows text.
4. **Turn off without a deploy.** Each generated trigger has its own automation switch, an
   `Automation_Setting__c` row whose name is the trigger's name, created with Is Package
   Default false the first time the admin turns instant totals off for that object
   (`AutomationControl.ensureSwitch`). With the switch off the trigger returns at once, so
   "Turn off instant totals" takes effect immediately, in production too, and "Turn on" flips
   it back. Pause all automation, a transaction bypass and the Rollup Builder module's off
   switch stop it as they stop every packaged trigger, because the trigger reaches the engine
   through `TriggerDispatcher` and `RollupTriggerHandler`.
5. **Removal is a deploy, and is rarely needed.** "Remove the trigger" offers a **Download
   removal package** (`destructiveChanges.xml` for the trigger and its test) and the steps: in
   a sandbox, delete both in Setup; in production, deploy the removal package with the CLI
   (production runs local tests for any Apex change). A switched-off trigger costs almost
   nothing, so removal is for tidying up and is required before uninstalling BarnCRM, because
   the trigger refers to a BarnCRM class (the admin guide says so).
6. **The Builder shows the real state.** For each object an active Instantly or Both rollup
   counts, and each object with a generated trigger, it reads the org: the registry (Built in),
   `ApexTrigger` by the generated name and its Status (On, or Inactive in Setup), the switch
   (Turned off), else Not set up, or Not available for an object that cannot carry a trigger.
7. **Two global methods.** `RollupInstantTrigger.run()` and `RollupInstantTrigger.hasRun()`
   are the engine's global entry point (ADR-0082 named one). `run` takes no arguments, reads
   the trigger context, checks the object's switch, and dispatches `RollupTriggerHandler`
   through `TriggerDispatcher`, so it never fails a save (errors go to the Error Log and the
   nightly run puts the total right). `hasRun` exists for the generated test. Both are
   permanent once a managed version is released.

## Alternatives considered

- **One click through the Metadata API (ADR-0082 A2 as written, S15).** The best experience,
  deferred rather than rejected: it returns when a spike proves, on a production-type org, a
  connection that needs no session id in a callout and no per-org app setup. The generated
  names and code stay the same, so a later one-click deploy finds and keeps what admins
  deployed by hand.
- **Deploy directly only in sandboxes, through a Named Credential the admin sets up.** Saves
  one paste in a sandbox, but still needs the callout code, the OAuth setup per org and the
  security review scope, and production still needs the change set.
- **Download only, with no copy and no in-org steps.** Requires the CLI or a third-party tool
  for every org; the change set route keeps everything inside Salesforce.
- **Turn off by deploying an inactive trigger.** A change set per change and a test that must
  tolerate an inactive trigger; the switch is immediate and needs no deploy.
- **Flow template only.** Kept as the no-code fallback (R-R12); it misses undelete and needs a
  second flow for deletes.

## Consequences

- Gap 2 closes for every object that can carry a trigger: an admin turns a total instant with
  one sandbox step and one change set, and off again with one click.
- New: `RollupInstantTrigger` (global), `RollupInstantTotals` (generator, state, switch and
  the Builder's calls), `AutomationControl.ensureSwitch`, and `TriggerHandler.noteTriggerProgress`
  made namespace accessible so a module's entry point marks trigger progress as the dispatcher
  does. No new object or field.
- Deferred: the one-click deploy (above); the Health Check findings of ADR-0082 S17 (a
  generated trigger no active rollup uses, and an Instantly rollup on an object with no
  trigger), whose states the Builder's Instant totals list already shows; offering to remove
  the trigger when the last rollup on its object is removed (the list shows "no rollup counts
  this object" with Turn off and Remove).
- Canonical model R-R12 is reworded to match. Plan Section 4.10, C-13 and the feature catalog
  entry "Instant totals on your own objects" change in BMemory and in the repository.
