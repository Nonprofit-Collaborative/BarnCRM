# ADR-0131: A module gives its sets to holders of a BarnCRM role, and Core asks it at Turn on and nightly

**Status:** Accepted (owner direction 2026-10-18 to proceed on the integrator's recommendation; settles the open point in ADR-0127, decision 3 and its Consequences)
**Date:** 2026-10-17
**Source:** v0.8 Volunteers build plan, PR7; builds on ADR-0059, ADR-0124, ADR-0125 and ADR-0127.

## Context

ADR-0127 decision 3 gives each Volunteers permission set to one BarnCRM role: Coordinator to the
Coordinator role (`Volunteer_Coordinator`), Staff to the Team Member role (`Program_Staff`) and
Read Only to the Read Only role (`Read_Only`). `TabAccessService.giveToHolders` gives a module's
set to everyone holding a named permission set, directly or through a group. The Coordinator
and Team Member roles both hold `BarnCRM_Staff` and nothing else, so no permission set tells
them apart: only the role, a permission set group, does.

The Rollup Builder module runs its sync at install, at each Turn on and nightly through seams
only it has: its engine extension (`RollupEngineExtensionV2.afterModuleTurnedOn`) and its own
nightly job. Volunteers has neither, and a nightly job of its own only to keep sets in step
would be one more scheduled job for Health Check to count.

## Decision

1. **`TabAccessService.giveToGroupHolders(setName, groupNames, budget, context)`.** Gives a
   module's set to every active person assigned one of the named permission set groups (the
   BarnCRM roles), with the same rules as `giveToHolders`: never takes a set away, skips anyone
   holding the set already, refuses Core's own sets, writes in system mode and works a slice at
   a time. The module passes Core's role names; Core names no module set (ADR-0059).
2. **A module access sync seam.** Core's interface `ModuleAccessSync` (`requestSync()`, queues
   the module's sync and never throws) and resolver `ModuleAccessSyncs`. A module's sync is
   found by convention, so Core names no module class: the class named after the module's key
   in the module catalog (`BarnCRM_Module__mdt`) followed by `AccessSync`, such as
   `VolunteersAccessSync`. A future module needs no Core change. Core asks the module's sync
   when the Module Manager turns that module on (`ModuleManagerService.turnOn`), and asks every
   catalog module's sync when a role or add-on is given on the Access page (`AccessController`)
   and from Core's nightly access check (`TabAccessScheduler`), so a module needs no scheduled
   job of its own to keep its sets with the roles. A module without such a class is skipped;
   one that cannot be built, or throws, is logged and skipped.
3. The Rollup Builder module keeps its own wiring: nothing changes for it. Its sync is named
   `RollupAccessSync`, not `RollupsAccessSync`, so the convention does not find it. Moving it
   onto the seam (renaming it and dropping its own Turn on and nightly calls) is a follow-up.

## Alternatives considered

- **Let `giveToHolders` accept group names in its audience.** Rejected: one list meaning two
  kinds of thing is a quiet trap, and a set and a group could share a name.
- **A Core role-to-set map Core keeps for every module.** Rejected: Core would name module sets.
- **A nightly job in Volunteers.** Rejected for the reason above; Turn on would still need a
  seam.

## Consequences

- A person given the Coordinator role on BarnCRM's Access page gets the Volunteers set within a
  minute; given it in Setup instead, at the next nightly check (one o'clock), or at once when the
  module is turned on again.
- The Access page and the nightly check queue one job per installed module sync beside their
  own, well inside the platform's limit on queued jobs.
- A class named `<ModuleKey>AccessSync` that is not an access sync is logged as an error each
  time it is looked for: the name is reserved for this seam.
