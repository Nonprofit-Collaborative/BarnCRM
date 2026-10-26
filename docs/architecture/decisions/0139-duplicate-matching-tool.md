# ADR-0139: Duplicate Matching is its own tool, with a tab and a settings section

**Status:** Accepted (owner decision, 2026-10-26)
**Date:** 2026-10-26
**Source:** owner request 2026-10-26 ("Duplicate matching should be its own tool with its own
settings page to handle the settings and a tab to manage matching logic"). Amends ADR-0103
`0103-org-optimizer-and-data-manager-pages.md` (duplicate review moved to Org Optimizer) and
ADR-0133 `0133-related-record-matching.md` decision 2 (match sources managed on the Custom
metadata page); builds on ADR-0124 `0124-edition-gates-visibility.md` (tool tabs follow their
feature) and ADR-0085 (custom metadata saves).

## Context

Duplicate review lived in Org Optimizer's Duplicates section, reached from a row under
Households in BarnCRM Settings. Its matching logic, the match sources (ADR-0133), was edited
only on the generic Custom metadata page, as rows of API names, next to Relationship Type.
Nothing put the review list, the matching logic and the org's own duplicate rules in one
place, and nothing explained a source in plain words (which object, which field, a person or
a household, how values are compared).

## Decision

1. **A Duplicate Matching tab** (`Duplicate_Matching`, app page `Duplicate_Matching`, shell
   `duplicateMatching`) with two areas, each loaded when first opened:
   - **Review**: the existing `duplicateReview` list, unchanged, including the read-only
     status of the org's Salesforce duplicate rules and the link to them in Setup. Shown to
     Manage BarnCRM Settings or Review Duplicate Suggestions holders, as before.
   - **Matching Logic**: the match sources in plain words, with add, edit, activate and
     deactivate, and a "Try a value" check that lists the people and households holding a
     value on a source. Shown to Manage BarnCRM Settings or Manage BarnCRM Metadata holders.
2. **Org Optimizer no longer lists duplicates.** Its Duplicates section is removed; the
   BarnCRM Duplicate Review permission set no longer gives the Org Optimizer tab.
3. **Tab visibility follows the feature** (ADR-0124): `BarnCRM_Tab_Duplicate_Matching` is
   given by `TabAccessService` while the Duplicate Review feature is on, to holders of
   BarnCRM Admin, BarnCRM Duplicate Review and BarnCRM Metadata Admin. The feature keeps its
   key, `DuplicateReview`, and is shown as **Duplicate Matching**.
4. **A Duplicate Matching section in BarnCRM Settings** (`SettingSections.DUPLICATE_MATCHING`,
   after Households) holds the tool's settings: the existing `Duplicate_Review` row, moved out
   of Households and pointed at the new tab (its Open button opens the tool), and the
   duplicates Setup note. No scan or matching setting existed to move; a new one is a
   separate decision.
5. **Match source writes keep the existing path and permission.** Matching Logic saves
   through `CustomMetadataManagerController` (`saveRow`, `setArchived`, `getOutcome`), so a
   save is validated by `MatchSourceService.validate`, deployed with `Metadata.Operations`,
   and needs Manage BarnCRM Metadata (BarnCRM Metadata Admin), as before. Reading the list
   and trying a value need Manage BarnCRM Settings or Manage BarnCRM Metadata
   (`MatchSourceController`). A shipped source can still only be deactivated and reactivated.
6. **Match Source leaves the Custom metadata page**, so it has one place to be managed;
   it stays registered with the custom metadata manager, which is what saves it.

## Alternatives considered

- **Keep duplicates in Org Optimizer and add a Matching Logic section there.** Rejected: the
  owner asked for a tool of its own, and Org Optimizer is about org health, not data entry.
- **A new save path for match sources.** Rejected: the custom metadata manager already
  validates, deploys and records a match source save; a second path would drift.
- **List match sources on both pages.** Rejected: two editors for one list confuse people.

## Consequences

- One more tool tab and tab permission set; the BarnCRM app's navigation is changed
  separately (app files are owned elsewhere).
- People who opened duplicates from Org Optimizer find them on the new tab; the Settings row
  and the guides point there.
- A Duplicate Review holder no longer sees Org Optimizer, which showed them only Duplicates.
