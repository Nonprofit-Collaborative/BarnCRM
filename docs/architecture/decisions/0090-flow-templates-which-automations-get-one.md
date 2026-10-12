# ADR-0090: Flow templates: which automations get one, how they are named, and what they leave out

**Status:** Accepted (builder decision, owner to confirm)
**Date:** 2026-10-12
**Source:** ADR-0040 deliverable for Core; admin guide `docs/admin-guide/flow-templates.md`

## Context

ADR-0040 says each switchable automation has a Flow template a customer can Save As and own
("switch ours off, run yours"), and that a template is part of the Definition of Done for a
switchable automation. Core ships twelve registry rows. Building the templates showed that
some of them cannot be copied into a flow faithfully:

- The household upkeep rows (`ContactTriggerHandler`, `AccountTriggerHandler`,
  `HouseholdMemberTriggerHandler`) are one piece of engine logic spread over three objects and
  two membership modes. ADR-0040 already names household naming and the membership mode
  guards as engine logic.
- `Address_Default_Propagation` writes the mailing fields of people held as Person Accounts.
  Core may not name those fields at deploy time (ADR-0013, `check-person-account-fields.py`),
  and a flow can only name fields statically. It also follows both membership modes and the
  seasonal address swap.
- `Contact_Address_Capture` resolves a person's household through the membership mode and
  the Addresses setting.
- The two `Core_Rollups_*` rows are the rollup engine. The approved rollup rework adds an
  invocable action and a template for admin objects (slice S10).

A packaged flow checks its own switch first (ADR-0040). A template is not a packaged
automation once copied: the copy belongs to the customer, and the switch it would read is the
one the customer has just turned off.

## Decision

- **A template ships for a registry row only when a flow can do the same work faithfully with
  standard flow elements.** In Core that is `Account_Address_Capture`,
  `Affiliation_Validation`, `Affiliation_Primary`, `Relationship_Validation` and
  `Relationship_Reciprocal`. Every other row is listed in the admin guide page with the reason
  it has none. ADR-0040's "each switchable automation has a template" is read as "each has a
  template or a documented reason".
- **No invocable Apex is added to make a template possible.** A template that only calls our
  Apex gives the customer nothing to change. Invocable actions are added when a customer flow
  needs engine logic (the rollup recalculation in S10 is the first), not to fill this table.
- **Naming.** API name `Template_<registry DeveloperName>`, with `_Delete` for the before
  delete half where Flow needs a second flow. Label `BarnCRM template: <registry label>`, so a
  template matches its row on the Automation page. The S10 rollup template follows the same
  pattern: `Template_Recalculate_Rollups`, calling an action labelled "Recalculate rollups for
  these records".
- **Shape.** Every template is `isTemplate` true and `Draft` (never active in the package),
  record triggered, and does not read the Automation Registry switch or the org-wide pause.
  User-visible errors use the same custom labels as the Apex they mirror.
- **Gaps a flow cannot close are documented, not engineered around**: no undelete trigger,
  no view of the other records in the same save, and no way to stand itself down while it
  writes the other side of a relationship. The admin guide lists each one.
- **A CI check keeps the table honest.** `scripts/ci/check-flow-templates.py` fails when a
  Core registry row has neither a template flow nor a row in the admin guide's "no template"
  table, and when a template flow is active or not marked as a template.

## Consequences

- A new Core automation either ships its template or adds its reason to the admin guide in
  the same change; CI enforces it.
- Giving's registry rows are not covered yet. The check is scoped to Core until Giving's
  templates (or reasons) are written.
- Template behaviour cannot be tested by Apex, because an inactive record-triggered flow does
  not run. Each template needs a manual check in an org: Save As, activate, switch ours off,
  and walk the admin guide page.
