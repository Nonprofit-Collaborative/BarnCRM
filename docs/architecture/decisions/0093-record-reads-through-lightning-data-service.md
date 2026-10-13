# ADR-0093: Simple record reads in LWCs go through Lightning Data Service, not Apex

**Status:** Proposed (builder decision)
**Date:** 2026-10-13
**Source:** Core quality pass item Q-06 (Brandon, 2026-10-13: implement the recommended
platform features); plan Section 12 D-23 ("GraphQL in new screens"); plan Section 4.13
(user mode, FLS and sharing); review findings UI-8, UI-13, IMPORT-16, PEOPLE-38, ADMIN-14,
FINDB-14

## Context

D-23 adopted the GraphQL wire adapter for new screens only. The Core review then found the
cost of the older pattern in existing ones. The Addresses, Affiliations and Relationships
cards each read a flat list of one object through a cacheable Apex method: about 400 lines of
controller and test per card that only restate a query the platform can run as the user. The
Apex cache does not see edits made through the record page, so a card can show old rows, and
after a change the card calls a mutating method that returns the list and then refreshes the
same list, two reads per click, while the record's own fields (the default address, the
primary affiliation) stay stale until a reload. Elsewhere, cacheable Apex is called
imperatively right after a save (the settings console, household naming), so the browser
cache can answer with the values from before the save, and the import wizard waits on four
serial calls when it opens.

## Decision

1. **A flat read of records, as the user, uses Lightning Data Service.** The GraphQL wire
   adapter (`lightning/graphql`) for a filtered list, `getRecord` or `getRelatedListRecords`
   for one record or one related list, `getObjectInfo` and `getPicklistValues` for describe.
   A simple write of one record from the same screen uses `updateRecord`, `deleteRecord` or a
   record form. After a write the screen refreshes its own wire and calls
   `notifyRecordUpdateAvailable` for records a trigger changed.
2. **Apex stays where it earns its place:** aggregation or counts, logic across objects or
   org shapes (household membership in either mode), describe work the UI API does not offer
   (the list of loadable objects, Find's field catalog), system-mode reads or writes
   (ADR-0021), long-running jobs and anything polled.
3. **Cacheable only where staleness is harmless.** A read that is wired, or that is pure
   describe or metadata, is `cacheable=true`. A read the screen calls again after its own
   save, or polls, is not cacheable.
4. **Both org shapes.** A query names only BarnCRM's own fields (both person lookups,
   `Contact__c` and `Person_Account__c`, exist in every org) and standard `Name`; never a
   Person Account field such as `IsPersonAccount` or a `__pc` field.

## Consequences

- The three cards lose their controllers and tests, and the permission sets lose the class
  access. Object and field permissions now decide everything, as they already did in user
  mode.
- A refused read or write on these cards shows the card's message but writes no Error Log
  entry from the card itself; a failure inside a trigger still logs as before (R-E1 covers
  exceptions in Apex, and the household members card already worked this way).
- GraphQL query text names fields without a namespace prefix, like the existing field name
  strings in LWCs. When the namespace is registered, the queries in `addressPanel`,
  `affiliationPanel` and `relationshipPanel` need the prefix with the rest of that pass.
- The GraphQL queries cannot be checked offline (the Jest stub ignores the query); a deploy
  and a look at each card in a Contact-household org and a Person Account org confirm them.
