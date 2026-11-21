# ADR-0234: A Reusable Mapper in Core: One Map Document and One Mapping Screen, Saved as a Kind of Saved Transform

**Status:** Proposed
**Date:** 2026-11-20
**Source:** Brandon, 2026-11-20 ("a UI feature to map objects and fields that can be reused for
functions like data import, transformations, automations, and integrations ... as easy or
easier/more intuitive to use as Salesforce's Flow/Data 360 transform screen"); design in
`docs/architecture/integration-hub-design.md` Section 2 and Appendix A. Amends ADR-0081 (the
transform document) and canonical model R-IT1 and 29X; builds on ADR-0227 (fewer objects),
ADR-0231 (definitions as JSON), D-150 (fuzzy match badge) and plan 9.9. Companion: ADR-0235
`0235-integration-module.md`.

## Context

Mapping exists in three places that cannot share: Super Importer's Check Columns step (file
columns to entities, R-IT1, with transforms R-IT15), Super Transformer's changes (R-BU1), and,
for anyone using Flow, assignments and the Transform element inside each flow. The owner wants one
mapping feature reused by import, transformation, automation and integration, easier than Flow's
screens. Integration needs what the R-IT1 document cannot express: a JSON payload as a source, a
JSON body as a target, and matching for a single record outside a template. Core Apex is over its
size target (O-01), the suite is at 197 of 200 custom objects (ADR-0227), and ADR-0081 refuses any
formula language.

## Decision

1. **One map document: R-IT1, version 4.** It adds optional `from` (columns, record or json, with a
   sample), `to` (record or json), `match` (by id, field, external ID or duplicate rules, with
   several and none policies) and, per column, `value`, `required` and `lookup` (the R-IT13 lookup
   generalized). Sources and JSON targets may be paths (R-MAP2): keys and list indexes only,
   nothing evaluated. The transform steps stay the closed list of R-IT15; ADR-0081 decisions 1 to 3
   hold unchanged. Every existing template document is already a valid map document.
2. **One screen in Core, logic in JavaScript.** A framework-free `mapDocument` module (validation,
   paths from a sample, auto-match by exact normalized name then the C-49e likeness with the D-150
   badge, type checks) and a `barnMapper` component with three panes: source with sample values,
   targets as sentences, and a live preview of the record or body the sample produces, with
   problems badged. Drag and drop through `c/barnDrag` is always an addition to Pick. Check Before
   Running runs a dry run of the map over up to 200 samples on the server.
3. **Saved maps are Saved Transform rows of Kind Map.** `Saved_Transform__c` gains `Kind__c`
   (Step List, the default, or Map); no new object. Maps are org-wide and managed by people with
   Manage BarnCRM Settings, and checked as the person on load, preview and use (R-ST3 pattern).
4. **Linked or copied.** Connector recipes and the Flow action link a map by key, with Where Used
   listing every user of a map before it is changed. Super Importer templates and Super
   Transformer copy a map in (Use a Saved Map) and out (Save as Map), so a template's behavior never
   changes underneath a running import.
5. **No runtime in Core.** Core adds only the save checks and the preview call (estimated 10,000 to
   15,000 Apex characters). Super Importer and Super Transformer keep their tested runtimes and read
   the parts of a map they support; the general runtime (paths, lookups, JSON bodies) lives in the
   Connector module.
6. **Adoption order, nothing removed:** Connector recipes; Super Importer Save as Map and Use a
   Saved Map; the Flow action; Super Importer's Check Columns step drawn by the Mapper only after a
   parity checklist passes; Super Transformer Apply a Map; extra gift mirror field copies.

## Alternatives considered

- **Keep mappings per tool:** fails the owner's reuse requirement.
- **A new Saved Map object:** works, but costs one of the three remaining object slots for what a
  kind on an existing definition object holds (ADR-0227).
- **Maps as Salesforce Files (ADR-0231):** possible; rejected because Where Used and the tools
  already read `Saved_Transform__c`, and a File adds sharing rules nobody asked for.
- **A formula mode like Flow's:** refused by ADR-0081; the step list plus conditions in recipes
  covers the documented cases.
- **The map runtime in Core:** needed only if Core itself ran maps; it would add an estimated 40,000
  characters to a package already over its target.
- **Replacing Super Importer's mapping step at once:** risks losing capabilities the step has
  (new-field creation, multi-object entities, row rules); done only after parity.

## Consequences

- One map can feed an import, a recipe and a flow; Where Used shows the blast radius of a change.
- R-IT1 readers must ignore unknown keys (they already skip broken parts); MAP-01 adds a test that
  a version 4 document loads in Super Importer unchanged.
- Two places still apply maps (Super Importer's engine and the Connector's runtime); they share
  `DataTransform` and a JSON fixture for paths so they cannot drift.
- Maps used by the Flow action need the Connector module installed.
- Make the Check Columns swap (decision 6) only when the parity checklist passes in an org test.
