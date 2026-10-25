# ADR-NEXT: Duplicates are also matched through values on related records

**Status:** Accepted (owner approved the feature, steps 1 to 3, 2026-10-25)
**Date:** 2026-10-25
**Source:** owner request 2026-10-25 (related-record duplicate matching in Core); amends
ADR-0050 (R-DP1) and ADR-0085 (decision 2); builds on ADR-0013 and ADR-0110

## Context

Core's duplicate scan (C-20) and import matching (R-IT16) ask the org's own duplicate rules
(ADR-0050). A matching rule compares fields on the record it is about and nothing else, so it
cannot see an email kept on a related record. Two contacts that share an email held only on
`ContactPointEmail`, or a street and postal code held only on Core's `Address__c`, are never
paired. In a Nonprofit Cloud org the contact point objects are where email, phone and address
live, so the gap there is most of the problem.

The org's rules cannot be extended to fix it: a matching rule has no cross-object criteria,
and BarnCRM ships no rule anyway (ADR-0050). The objects themselves may not exist: Core runs
on a Platform-only org (ADR-0013) and may not name a Nonprofit Cloud object at compile time
(ADR-0110, `check-standard-objects.sh`).

## Decision

1. **Match sources are custom metadata, `Match_Source__mdt`,** one row per related object and
   parent link: Object Name, Value Field, Postal Code Field (address only), Parent Field,
   Normalization (Email, Phone or Address), Active, and Is Shipped. It is a list of rows of the
   same shape, which is what Core's other list settings are (Relationship Type, ADR-0085), and
   it travels with the package, so a shipped source is in every org from install with no data
   load. A custom object was rejected: it would need its own page and a first-run seeding job
   for what is configuration, not organization data.
2. **They are managed in BarnCRM Settings, on the Custom metadata page** (ADR-0085), never only
   in Setup. Match Source is registered there. An administrator adds, edits and archives their
   own sources there, and each save is checked against the org: the object and both fields
   must exist, the parent field must be a lookup, and an address source must name a postal
   code field.
3. **A shipped source can be archived and restored, and nothing else about it changed.** This
   amends ADR-0085 decision 2 for a type registered with `shippedArchivable`; Relationship
   Type stays fully read only. An administrator who does not want phone matching archives the
   shipped phone source rather than going to Setup. Shipped rows are not protected, and
   `Active__c` is subscriber controlled, so the choice survives an upgrade once the package is
   managed (to be confirmed in the first managed install, as the rest of ADR-0085 is).
4. **Core ships five sources:** `ContactPointEmail` (EmailAddress, ParentId),
   `ContactPointPhone` (TelephoneNumber, ParentId), `ContactPointAddress` (Street and
   PostalCode, ParentId), and `Address__c` twice (Street and Postal Code, once by Contact for
   people and once by Account for households). A source whose object or fields are not in the
   org is skipped at run time, so the contact point rows do nothing on a Platform-only org.
5. **Every read is dynamic.** Sources are read with dynamic SOQL built from describe, in user
   mode, so Core names no contact point object. The shipped rows are text, like Import
   Template Default's column headings, and `check-standard-objects.sh` exempts the
   `Match_Source` record files on the same reasoning: nothing resolves those words at deploy
   time. That exemption holds only while the type has no metadata relationship field.
6. **A parent resolves to a person or a household, or is skipped.** A parent that is a
   Contact is that person, and an Account is that account (the scan keeps households only,
   R-DP2). An `Individual` resolves to the contacts whose `IndividualId` is it, read by name
   only when Contact has that field. Any other parent is skipped. Contact point rows in a
   Nonprofit Cloud org usually hang off an Individual or a person account, which is why the
   Individual step is there; a person account is not a household and is never proposed.
7. **Values are compared after normalization, in Apex.** Email: trimmed and lower case.
   Phone: digits only, and an 11 digit number starting 1 loses the 1 (North American
   numbering). Address: the street in lower case with punctuation removed, whitespace
   collapsed and common words abbreviated (street to st, avenue to ave), joined to the postal
   code without spaces in upper case, with a US ZIP+4 cut to five digits. A value that
   normalizes to nothing, or a phone with fewer than seven digits, is not compared.
8. **Lookups are bounded.** For a group of records the sources are read for those parents,
   then candidates are found with one query per source: emails by equality, phones by a
   pattern that allows any separator between the digits, addresses by the postal code. Each
   candidate is normalized and compared exactly. A value shared by more than ten people or
   households (an office switchboard, a shared mailbox) is not used, because it says nothing
   about whether two of them are the same.
9. **What uses them.** The duplicate scan adds the pairs the sources find to the same review
   list, with a reason naming the source ("Same email on Contact Point Email"), and drops a
   pair a duplicate rule already found. Import matching asks the sources for incoming people
   that the template's rule found nobody for. No save-time warning is added.

## Alternatives considered

- **A matching rule on a formula or copied field.** Copying the related email onto Contact
  needs automation on the related object, which Core cannot name, and a second copy of data
  that drifts.
- **Hard-coded sources in Apex.** No way for an administrator to add their own object or
  switch one off, and the contact point names would sit in Core's code.
- **A full pass over each source object building one map of values.** One query per object
  instead of per chunk, but the map grows with the org and does not fit in a batch's heap for
  a large one.

## Consequences

- R-DP1 changes: Core now compares values on the configured related records, and only there.
  Field-by-field comparison of the records themselves is still the org's duplicate rules.
- A phone lookup with a leading wildcard reads the whole source object; it runs only in the
  scan's batch chunks and an import's chunks, never on save.
- Formats the normalization does not know (a non-North-American phone written with its trunk
  prefix, a street written two different ways) are not matched. The rules still are.
