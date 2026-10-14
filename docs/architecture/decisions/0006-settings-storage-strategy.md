# ADR-0006: Settings storage: custom settings, custom objects, and custom metadata

**Status:** Accepted; the Platform Cache clause of decision 1 is superseded by ADR-0094
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-06

## Context

Two requirements pull in opposite directions.

Principle 1 and plan Section 2.3 require that every setting is on a page in the app,
editable by a non-technical administrator, with changes taking effect immediately. That
argues for storage Apex can write synchronously.

Principle 6 requires that nothing an administrator configures is overwritten by a package
upgrade. That argues for storage the package can update on upgrade without touching admin
data, which is the opposite property.

The platform offers three stores with different trade-offs. Custom settings are written
synchronously but are not reportable and carry no version history. Custom metadata is
upgrade-safe and versioned in source but is written asynchronously, which makes it a poor
target for a settings page. Custom objects are reportable, exportable, and editable with
the standard record UI, but the package cannot update their records on upgrade without
overwriting what the admin changed.

No single store satisfies both requirements, so we decide the split once, up front.

## Decision

Settings are stored in three places according to what kind of setting they are.

1. **Simple org-wide toggles and values** (feature flags, mode selections, naming rules,
   default record types): **protected hierarchy custom settings**, written synchronously
   by Apex from the console, cached in Platform Cache with invalidation on write. In v0.1
   this is `Nonprofit_Settings__c`.
2. **Structured configuration the admin manages as lists** (rollup definitions, import
   templates and mappings, level definitions, acknowledgment rules, stewardship plan
   templates, and the automation list): **custom objects in the package**, so they are
   reportable, exportable, and editable with the standard record UI where that is useful.
   In v0.1 this is `Automation_Setting__c`.
3. **Package-shipped defaults** (naming patterns, the automation registry, later default
   rollups, import templates, and levels): **custom metadata types**, read-only to
   admins, **materialized into the corresponding custom object records** by the
   post-install script on first install and on "Restore defaults." Upgrades update the
   metadata without touching the admin's records: in v0.1, `Naming_Pattern__mdt` and
   `Automation_Registry__mdt`.

Every write through the settings service produces a `Setting_Change__c` audit record
recording setting, old value, new value, who, and when.

## Alternatives considered

- **All custom metadata**: asynchronous writes make a settings page feel broken, and the
  admin editing experience is a Setup page, which plan Section 9.3 forbids.
- **All custom settings**: not reportable, not versioned, and unable to hold list-shaped
  configuration such as rollup definitions.
- **All custom objects**: no upgrade-safe way to ship defaults, so every upgrade either
  overwrites admin edits or ships nothing.

## Consequences

- The materialization step is real machinery: a post-install script that creates records
  from metadata on first install, adds newly shipped entries on upgrade without touching
  admin choices, and supports "Restore defaults".
- A contributor must know which store a new setting belongs in; the rule above is the
  test, and the canonical model records where each setting lives.
- Platform Cache invalidation on write is required so that a changed setting takes effect
  on the next transaction with no staleness beyond ten seconds (plan Section 10.2, C-03).
- Custom settings are protected, so they never appear as editable configuration in
  subscriber Setup, keeping the console the only place settings change.
