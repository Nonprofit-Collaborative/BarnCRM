# ADR-NEXT: Relationship and affiliation upkeep run in system mode

**Status:** Accepted (product owner, decision D-85)
**Date:** 2026-10-13
**Source:** Core review item PEOPLE-26; extends ADR-0021 category 2; features C-15 and C-16

## Context

ADR-0021 lets package upkeep of package owned, computed values run in system mode once the
platform has authorized the user's own save. Two People features did their upkeep in user mode
anyway:

- **Affiliations (C-16).** After an affiliation save the package clears the primary flag from
  the person's other affiliations and writes the person's Primary Affiliation field (R-AF2).
  Both were user mode writes, fed by user mode reads.
- **Relationships (C-15).** After a relationship save, edit or delete the package creates,
  updates or deletes the other side, and writes the Reciprocal Relationship back pointer
  (R-RL1, R-RL4a). All of it was user mode, and so were the reads that find an existing other
  side.

The shipped sharing model for both objects is Public Read/Write, which hid the problem. Under a
private sharing model the other side of a relationship, the person, and the person's other
affiliations usually belong to another user. The upkeep then failed the user's own save with a
raw error, or read only the rows the user could see and so built a duplicate other side or left
two primary affiliations. A narrower permission set (no edit on Contact, or on the package's
bookkeeping fields) failed the same way.

## Decision

The upkeep reads and writes of both features go through dedicated `without sharing` classes in
`AccessLevel.SYSTEM_MODE`, each with a header naming ADR-0021 and the reason:
`AffiliationUpkeepSelector`, `AffiliationUpkeepWriter`, `RelationshipUpkeepSelector` and
`RelationshipUpkeepWriter`. The conditions of ADR-0021 apply unchanged: they are reached only
from the feature's service after the user's own save, no user typed text reaches a query, only
the values the package computes are written, and the user's own save and every screen read
(`AffiliationSelector`, `RelationshipSelector`) stay in user mode.

One extension beyond ADR-0021: deleting the other side of a relationship, and restoring it
from the recycle bin, are covered. `HouseholdWriter` keeps record deletes and restores in user
mode, because a household or a membership row is a record people own. The other side of a
relationship is not: the package built it, every value on it is copied from its partner, and it
exists only because its partner does. Its delete or restore follows a delete or restore of the
partner that the platform has just allowed, and refusing it would leave a one-sided pair the
user may not even be able to see.

## Alternatives considered

- **Keep user mode and document that orgs with private sharing must grant access.** Rejected:
  the grant needed is edit on every other person's relationships and contacts, which defeats
  the private sharing the org chose.
- **Run the whole service `without sharing`.** Rejected: the user's own save and the cards would
  be elevated with it, which ADR-0021 forbids.

## Consequences

- Upkeep completes for any user the platform lets save the relationship or affiliation.
- The Primary Affiliation field can name an organization the person viewing it cannot open.
  That is the same as any lookup under private sharing.
- An org run under a private sharing model on `Affiliation__c`, `Relationship__c` and Contact
  is the only way to confirm the sharing half; Apex tests cannot change the sharing model and
  prove the permission half only.
