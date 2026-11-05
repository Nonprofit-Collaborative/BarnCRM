# ADR-NEXT: Modules add a glance card to Core's record pages through an extension seam

**Status:** Proposed (owner approval of the card, Brandon, 2026-11-04)
**Date:** 2026-11-04
**Source:** v1.0 usability review finding people-giving-14 ("Giving at a Glance"), approved
into v1.0 through the module-extension pattern; amends the third alternative of ADR-0064.
Reuses the cross-package mechanism of ADR-0017, ADR-0057 and ADR-0159.

## Context

In the **BarnCRM** and **BarnCRM Console** apps a person, household or organization opens on
Core's record page, which shows no giving (ADR-0064): Core may not reference Giving
(ADR-0003, ADR-0059). Staff who log a call there cannot see that the donor gave last week, or
enter a gift, without switching to BarnCRM Fundraising. ADR-0064 rejected "a custom giving
summary component on Core's page" because Core cannot place a Giving component.

Existing seams were checked first. `WhereUsedExtension`, `HealthCheckExtension`,
`HouseholdDependentsExtension`, `PersonErasureExtension` and `DataProtectionExtension` each
answer one question for one Core tool; none returns content for a record page. Their
mechanism (a Core interface, a registry of class names resolved with
`NamespaceUtil.resolveType`, absent or broken modules skipped and logged) fits exactly, so it
is reused with a new interface rather than a new mechanism.

## Decision

- Core defines `RecordGlanceExtension` (`RecordGlance.Card glance(Id recordId)`) and
  `RecordGlance`, a plain card shape: title, icon, figures (currency, number, date or text,
  each with its label) and actions (label and a Lightning page reference as JSON). A module
  returns finished label text, so Core holds no module wording.
- `RecordGlanceExtensions` lists the class names (`GivingRecordGlanceExtension`) and resolves
  them as `WhereUsedExtensions` does. A module that is absent, cannot be built or throws is
  skipped and logged; the page still opens.
- Core ships `recordGlance`, a host component on its Contact and Account record pages (and
  Giving's copies, per ADR-0064's two-copies rule), at the top of the sidebar. It calls
  `RecordGlanceController.getCards` (not cacheable, so a failure can be logged and figures move
  after a save) and draws each card with `c-barn-stat-tile`. With no card it draws nothing, so
  a Core-only org sees no change.
- Giving's `GivingRecordGlanceExtension` returns **Giving at a Glance**: Total Giving, Last Gift
  Date and Donor Level, labelled from the fields, read with the viewer's access (no card for
  someone who cannot read gifts or those fields), and **Enter a Gift**, shown only to someone
  who can create a gift, opening Quick Gift Entry with the donor (`c__donorId`). The button
  reads its name from the `New_Gift` quick action, so the two never disagree.

## Alternatives considered

- **Assign Giving's record pages in the BarnCRM apps** (the review's first option). Cross-app
  assignment is the step ADR-0064 left to the administrator, and it would replace the page a
  non-fundraising team uses with the whole Giving page.
- **Core reads Giving fields by dynamic SOQL.** Possible without a compile-time dependency,
  but Core would hold Giving's field names and wording, the coupling ADR-0057 rejected.
- **Reuse an existing extension interface.** None returns record page content; widening one
  would mix two jobs in one module class.

## Consequences

- Any module can add a small card to Core's person and organization pages by implementing
  the interface and adding its class name to `RecordGlanceExtensions.EXTENSION_CLASSES`.
- Each card costs one Apex call per record page view and one query per module.
- Module copies of Core's pages (Programs, Volunteers) do not yet carry the host component;
  adding it is a page change for their owners.
