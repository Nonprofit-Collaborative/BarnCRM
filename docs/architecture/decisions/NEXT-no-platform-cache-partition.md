# ADR-NEXT: Configuration reads use the platform's own caches; Core ships no Platform Cache partition

**Status:** Accepted (builder decision)
**Date:** 2026-10-13
**Source:** Core quality pass item Q-11 (plan decision D-39); amends decision 1 of
`0006-settings-storage-strategy.md` ("cached in Platform Cache") and canonical model R-N3;
review findings ADMIN-9, ADMIN-15, PLATFORM-8

## Context

Q-11 asked whether Platform Cache should hold the configuration Core reads on every save, and
to cache only reads that repeat across transactions (a static variable already covers repeats
within one). A Platform Cache entry pays off only when the read it replaces costs something the
platform does not already cache. The reads that run on a save, before this change:

| Read | Cost per save transaction | Already cached across transactions by |
|---|---|---|
| `BarnCRM_Settings__c` (`getOrgDefaults()`) | 0 SOQL | the platform's custom settings cache |
| `Automation_Registry__mdt` (trigger dispatcher) | 1 counted SOQL, 2 when a module is off | nothing: the query selected a long text field |
| `Setting_Definition__mdt` (a module reading its own setting, as Giving does on a gift save) | 1 counted SOQL | nothing: the query selected long text fields |
| `Relationship_Type__mdt` | 0 SOQL (no long text selected) | the platform's metadata cache |
| `Automation_Setting__c` (automation switches) | 1 SOQL | nothing |
| A module's settings record (dynamic query on its custom setting) | 1 SOQL | nothing |

A custom metadata query costs a counted SOQL only when it selects a long text area field;
`getAll()` never does. Describe results are per user and cannot be serialized, so they can only
be cached in a static. Import templates, rollup defaults and release notes are read when a page
opens or a package installs, not on a save. Repeated reads of rollup definitions inside one gift
save (ROLLUPS-5) and the org shape probe on an Account save (PEOPLE-36) repeat within a
transaction or are better removed than cached; they belong to that work, not to a cache.

`SettingsService` also carried an optional org cache layer over `getOrgDefaults()`, used only
when an administrator created a `BarnCRMSettings` partition by hand. It saved nothing, and a
read that loaded the old record just before a save cleared the cache could put that old record
back afterwards, where it stayed for the cache's lifetime.

Platform Cache capacity (Salesforce Apex Developer Guide and packaging guide): a partition with
no allocation silently skips every `get` and `put`; partitions are checked at run time, not at
compile time; the default partition cannot be packaged. Free capacity for a package (3 MB,
"Provider Free") is given only to a managed package that has passed AppExchange security
review. BarnCRM is not packaged yet (the namespace is deferred), so a shipped partition would
have zero capacity in every org unless an administrator allocated some.

## Decision

1. **Core ships no Platform Cache partition and no Platform Cache code.** The optional settings
   cache layer is removed; `SettingsService` keeps its per-transaction static and relies on the
   platform's custom settings cache, which a committed save refreshes at once.
2. **Custom metadata the framework reads on a save is read with `getAll()`**, which costs no
   query: the dispatcher and the module switch (`AutomationRegistrySelector.selectForFramework`)
   and the check of a module's settings object (`SettingDefinitionSelector.getAllShortFields`).
   The counted queries remain only where the full long text is needed (seeding automation
   switches, the settings console).
3. **A read is cached across transactions only by a platform cache that is updated by the save
   itself.** Any future Platform Cache use must key its entries by a version that is written in
   the same transaction as the change it covers, so a reader that loaded old data can never
   publish it under the current version.

## Alternatives considered

- **Ship a zero-capacity partition and cache the switches and module settings with
  `Cache.CacheBuilder`.** Rejected for now: it saves 1 or 2 SOQL per save in an org that
  allocates capacity and nothing anywhere else, and doing it safely needs a version field on a
  settings object and a version write on every config write path. Removing a packaged partition
  later is harder than adding one.
- **Keep the optional settings layer.** Rejected: no gain over the custom settings cache, and
  the read-then-put race above.
- **Org cache with a short lifetime instead of versioned keys.** Rejected: the shortest org
  cache lifetime is 300 seconds, above the ten-second staleness limit in R-N3.

## Consequences

- A save that fires BarnCRM triggers costs one SOQL less (two when a module is off), and a
  module's setting read one less, in every org, with no capacity to allocate.
- No cache can serve stale configuration to a save: every cross-transaction copy is the
  platform's, and it is refreshed by the commit.
- `getAll()` returns long text cut to 255 characters; the framework reads no long text, and a
  test compares the free read with the counted query.
- Revisit after the package passes security review, if Scale Center or ApexGuru shows the
  switch query or a module settings query near the SOQL limit: then cache those two with the
  versioned keys of decision 3.
