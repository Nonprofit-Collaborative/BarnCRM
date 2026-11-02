# ADR-NEXT: Where Used reads BarnCRM's own setup records, and modules add theirs through an extension seam

**Status:** Proposed (builder decision)
**Date:** 2026-11-02
**Source:** plan Section 6.0a release 0.16 item C-59 (decision D-156); competitive research
6.1.5 idea 10; admin guide `where-used.md`. Reuses the cross-package mechanism of ADR-0017 and
ADR-0057.

## Context

Before an administrator deletes a field, they need to know what uses it. Salesforce answers part
of that on the field's Setup page ("Where is this used?"), but it does not read BarnCRM's own
setup, which names fields as text inside records and JSON documents: saved Find queries (also
Giving's donor segments, R-DS1), Super Transform step lists (R-ST1), import mappings (R-IT1),
merge rules, matching sources, settings whose value names a field, and the Rollup Builder's
definitions (R-R1, R-R2). A field deleted under any of these breaks it quietly.

Two constraints shape the answer. Core may not depend on a module (plan Section 4.1, ADR-0014,
ADR-0125), yet rollup definitions live in the Rollup Builder module and gift import entities in
Giving. And the full Salesforce dependency graph (flows, Apex, page layouts, reports,
validation rules) needs the Tooling API, which the plan keeps out of the package (Section 1.3
non-goals; competitive research 6.1.5 out-of-scope list).

## Decision

- Core's `WhereUsedService` reads Core's setup records and returns, for one field or one whole
  object, a list of references: kind, name, record Id, where in the record the field is named,
  what breaks, and the tab and page state that edit it. Field paths are resolved through describe
  (`Household__r.Name` names the household lookup and Account Name; a merge rule on
  `MailingAddress` names `MailingStreet`).
- A module adds its own records by implementing `WhereUsedExtension`, a `@NamespaceAccessible`
  interface Core defines. `WhereUsedExtensions` finds implementations by class name
  (`RollupsWhereUsedExtension`, `GivingWhereUsedExtension`) with `NamespaceUtil.resolveType`,
  exactly as `HealthCheckExtensions` does (ADR-0057). A module that is absent, cannot be built or
  throws is skipped, logged, and the answer is marked incomplete.
- Modules read paths with the target's own `matchesPath`, `matchesFilter` and `matchesField`, so
  every package reads a name the same way. Giving reuses Core's import column reader and passes
  the objects its row entities load.
- Records are read in system mode and without sharing (`WhereUsedSelector`), behind Manage
  BarnCRM Settings, because a safe retirement needs every saved query. A private query someone
  else owns is listed by its owner only, never its name.
- BarnCRM never deletes a field. The page ends in a Retire a Field checklist that links each
  reference and the field's Setup page, and says plainly that flows, Apex, layouts and reports
  are not scanned.

## Alternatives considered

- **Tooling API `MetadataComponentDependency`.** Complete, but needs an outbound callout to the
  org, a Named Credential and API access in every edition; a plan non-goal.
- **Core reads module objects by dynamic SOQL.** Possible without a compile-time dependency, but
  Core would then hold the Rollup Builder's path notation and Giving's entity names, the coupling
  ADR-0057 rejected for Health Check.
- **Custom metadata registry naming objects and fields to scan.** Simple for flat fields, but
  JSON documents (filters, mappings, paths) need code to read, so an interface is still needed.

## Consequences

- A new kind of BarnCRM setup that names fields must add itself to `WhereUsedService` or its
  module's extension, or Where Used silently misses it. The admin guide page lists what is read.
- Reading every saved query, step list, mapping and rollup is bounded at 2,000 records of each
  kind per request; a larger org sees the first 2,000 by name.
- A new module extension adds its class name to `WhereUsedExtensions.EXTENSION_CLASSES`.
