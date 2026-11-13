# ADR-0017: Cross-package mechanisms under one namespace

**Status:** Accepted
**Date:** 2026-09-07
**Source:** builder decision under plan Section 9.3 (platform mechanism chosen to serve plan Sections 4.1, 4.8, 7.1 and 7.2); refines ADR-0002 and ADR-0014

## Context

Core is one 2GP package and Giving, Volunteers, Programs, Funders and Connect are separate 2GP
packages that depend on it, all under one namespace (ADR-0002, ADR-0003). Three mechanisms
were left open by the plan once real code existed:

1. Plan Section 7.1 says cross-package Apex calls go through `global` service interfaces.
   `global` is a permanent API commitment in a managed package: nothing marked `global` can
   later be removed or have its signature changed.
2. Plan Section 4.8 puts org-wide toggles in one protected hierarchy custom setting
   (`Nonprofit_Settings__c`, in Core). A dependent package cannot add fields to an object that
   another package owns (the same constraint ADR-0014 records), so module settings need a
   home.
3. Plan Section 7.2 requires one trigger per object dispatched through the trigger framework,
   with every handler bypassable. Several features in one package (for example installment
   fulfilment and automatic soft credits on Gift) each need a handler on the same object
   without editing one shared trigger or one shared handler class.

## Decision

1. **Cross-package Apex uses `@NamespaceAccessible` on `public` types, not `global`.** Core
   classes that modules call (`TriggerDispatcher`, `TriggerHandler`, `AutomationControl`,
   `ErrorLogger`, `SettingsService`, `HouseholdService`, `OrgShapeDetector`, `TestDataFactory`)
   are `public` and annotated `@NamespaceAccessible`, which makes them callable from other
   packages in the same namespace while keeping them out of the subscriber-facing API. The
   annotation has no effect until the namespace is registered, and unmanaged scratch org
   deploys already see everything, so development is unaffected. `global` is reserved for the
   deliberately public surface (the Connect REST endpoint, Flow-invocable actions).
2. **Each package owns its settings object.** Core keeps `Nonprofit_Settings__c`. Giving ships
   `Giving_Settings__c` (protected hierarchy custom setting) and later modules follow the same
   pattern. `Setting_Definition__mdt` gains a `Settings_Object__c` field (default
   `Nonprofit_Settings__c`) so the Settings console and `SettingsService` read and write any
   registered settings object through dynamic describe, and modules ship their definition
   records without touching Core.
3. **Trigger dispatch is registry-driven.** `TriggerDispatcher.run(String objectApiName)` reads
   `Automation_Registry__mdt` rows for that object ordered by `Execution_Order__c`,
   instantiates each `Handler_Class__c` with `Type.forName`, and runs it through the existing
   bypass, pause, and error-logging path. One trigger per object calls only this method.
   Modules ship their handler classes plus registry records; nobody edits another feature's
   trigger or handler. The single-handler `run(TriggerHandler)` overload remains for tests.

## Alternatives considered

- **`global` service interfaces as the plan wrote.** Rejected: permanent API surface for
  internal plumbing; every refactor of Core would be blocked by module compatibility.
- **One settings object in Core with fields for every future module.** Rejected: Core would
  carry Giving, Volunteer and Program fields whether or not those packages are installed,
  breaking Principle 3.
- **Custom metadata for module settings.** Rejected by ADR-0006 (asynchronous writes, poor
  admin editing).
- **Hand-maintained handler lists in each trigger.** Rejected: merge conflicts and no
  per-handler bypass row unless someone remembers to add it.

## Consequences

- The `Automation_Registry__mdt` catalog is the single place an automation is declared; the
  admin's `Automation_Setting__c` rows are materialized from it, so every registered handler is
  automatically bypassable from the console.
- `Type.forName` on a class from another package requires the class to be
  `@NamespaceAccessible` and `public` with a public no-argument constructor; the registry
  record stores the class name without a namespace prefix and the dispatcher qualifies it at
  runtime from the running package's namespace.
- Plan Section 7.1 is amended by this ADR: "global service interfaces" reads as
  "`@NamespaceAccessible` public services".
- Canonical model Section 12 (Nonprofit Settings) is annotated: the v0.3 Giving keys move to
  `Giving_Settings__c`.

## Note, 2026-11-13: module wiring is catalog data too (D-200 S1)

Decision 3's registry pattern now covers the rest of a module's wiring into Core. Each module's
row of the module catalog (`BarnCRM_Module__mdt`, shipped by Core) carries three maps:

- `Extensions__c`: the module's class for each Core extension seam, one line per seam as
  `Seam: Class`, the seam being the Core interface's name. One Core class, `ModuleExtensions`,
  reads the lines and builds the classes by namespace and name, in catalog order (Sort Order,
  then name), once per transaction; a class that is not installed is skipped. It replaces each
  seam's hard-coded list of module class names, starting with the nightly step providers
  (`NightlyJobs`, which named every module: review defect SD6).
- `Access_By_Permission_Set__c` and `Access_By_Role__c`: the permission sets Core's access sync
  gives (ADR-0131). One generic sync in `ModuleAccessSyncs` replaces each module's
  `<Module>AccessSync` class, and its `setUp(moduleKey, installerId)` replaces each module's
  copy of the installer grant: the installer gets the sets the row gives `BarnCRM_Admin`
  holders. A module that needs its own step after a pass registers a `ModuleAccessStep`.

A module adds or changes wiring by editing its catalog row, never Core's code. Behavior is
unchanged: the same sets, roles, steps, times and switches. The slice one pass gives is now
derived from the number of sets (9,000 assignments a pass, at most 5,000 a set) instead of a
constant per module; it changes how many passes a large org takes, not what is given.
