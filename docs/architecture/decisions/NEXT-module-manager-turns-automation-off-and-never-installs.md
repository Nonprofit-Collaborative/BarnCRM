# ADR-NEXT: The Module Manager switches a module's automation, links to installs, and counts before an uninstall

**Status:** Accepted (builder decision, under ADR-0046 and the owner decisions of 2026-10-12)
**Date:** 2026-10-12
**Source:** C-24; plan Section 4.8 "Module Manager"; ADR-0046; ADR-0021; ADR-0024; builds on
`NEXT-suite-choice-is-the-first-setup-step.md`

## Context

Plan Section 4.8 asks for a Module Manager that lists every module with status (Not installed,
Installed and off, On), version and an action: Install opens the package install URL; Turn on
runs the module's post-install configuration and assigns permission sets; Turn off disables its
automation and hides its tabs; Uninstall links to the platform uninstall with a pre-flight report
of data that would be lost. Three platform facts limit what Core can do:

1. Apex cannot read which version of another package is installed: that is the Tooling API
   (`InstalledSubscriberPackage`), and the unlocked packages have no namespace to probe.
2. An app cannot change tab visibility at run time without the Metadata API.
3. Core may not reference a module's schema statically, and a module's registry rows do not say
   which module they belong to.

## Decision

1. **Status comes from detection and one Core setting.** A module is Not installed until
   `ModuleDetectionService` finds it, then On, unless it is listed in `Modules_Turned_Off__c`
   (text, comma separated module names), which makes it Installed and off. Core is always On and
   cannot be turned off. The list offered follows the suite gate of the suite ADR.
2. **Turn off switches off the module's automation, through the switch every automation already
   has.** `Automation_Registry__mdt` gains `Module__c`; Giving and Connect set it on their rows,
   and a blank value means Core. While a module is off, `AutomationControl.isEnabled` answers false
   for its automations, except an `Always_Runs__c` one (ADR-0024), whatever its own switch says.
   Each switch keeps its own value, so turning the module on restores exactly what was there.
3. **Turn off does not hide tabs.** The platform gives an app no supported way to change tab
   visibility at run time. The page says so and points to the Access page, where taking away the
   module's role removes its tabs for that person.
4. **Turn on clears the module from the list and runs Core's part of its post-install work**:
   `AutomationControl.ensureDefaults()` creates any missing switch rows. It then, in a second
   call (a permission set assignment cannot share a transaction with the settings write), gives
   the person who turned it on the module's admin permission set (`Giving_Admin`); a module with
   no admin set gets none.
5. **No installed version.** The Module Manager shows no version column (fact 1). Install links
   are the published version Ids of the suite ADR; Salesforce's Installed Packages page, linked
   from the Module Manager, shows installed versions.
6. **Uninstall is Salesforce's.** The Module Manager links to Installed Packages in Setup. Before
   that link it shows a pre-flight report: for each object the module owns, how many records the
   uninstall would delete, counted in system mode (an administrator who cannot see a record still
   loses it) and capped at 50,000 a object so a count can never fail on a limit. Only someone
   holding Manage BarnCRM Settings can run it. The objects each module owns are listed in
   `ModuleManagerService`, and `scripts/ci/check-module-objects.py` fails when that list and the
   module's `objects/` folder disagree.
7. **The Module Manager lives in BarnCRM Settings**, as a component row in the General section,
   and the Setup Assistant's modules step links to it.

## Alternatives considered

- **Turn off by removing the module's permission set assignments.** Rejected: it destroys the
  administrator's access decisions, and turning back on cannot know who had them.
- **Switch every module automation's own row off.** Rejected: turning back on would switch on
  automations the administrator had chosen to keep off.
- **A module registry custom metadata type.** Rejected for the reason in the suite ADR: release
  data only a new Core version can change.
- **Count records in user mode.** Rejected: the report would under-state what an uninstall
  deletes for an administrator without read access to a module object.

## Consequences

- Giving's scheduled jobs and flows stop only where they already ask `AutomationControl` for a
  switch; a job that does not is a follow-up for that module.
- Plan Section 4.8's "hides its tabs" and "version" are not delivered; the plan lines need the
  owner's update.
