# ADR-0133: Duplicates are also matched through values on related records

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
   must exist, the value field (and an address source's postal code field) must be filterable
   text (text, email, phone, text area or URL), and the parent field must be a lookup that can
   point at a Contact, an Account or an Individual, the only parents a source resolves.
3. **A shipped source can be archived and restored, and nothing else about it changed.** This
   amends ADR-0085 decision 2 for a type registered with `shippedArchivable`; Relationship
   Type stays fully read only. An administrator who does not want phone matching archives the
   shipped phone source rather than going to Setup. Shipped rows are not protected, and
   `Active__c` is subscriber controlled, so the choice survives an upgrade once the package is
   managed (to be confirmed in the first managed install, as the rest of ADR-0085 is).
4. **Core ships six sources:** `ContactPointEmail` (EmailAddress, ParentId),
   `ContactPointPhone` (TelephoneNumber, ParentId), `ContactPointAddress` (Street and
   PostalCode, ParentId), and `Address__c` three times (Street and Postal Code: by
   `Contact__c` for people, by `Account__c` for households, by `Person_Account__c` for person
   accounts). A source whose object or fields are not in the org, or that the running user
   cannot read, is skipped at run time, so the contact point rows do nothing on a
   Platform-only org.
5. **Every read is dynamic.** Sources are read with dynamic SOQL built from describe, in user
   mode, so Core names no contact point object. The shipped rows are text, like Import
   Template Default's column headings, and `check-standard-objects.sh` exempts the
   `Match_Source` record files on the same reasoning: nothing resolves those words at deploy
   time. That exemption holds only while the type has no metadata relationship field.
6. **A parent resolves to a person, a person account or a household, or is skipped.** A parent
   that is a Contact is that contact, and an Account is that account. An `Individual` resolves
   to the contacts whose `IndividualId` is it and, when the records asked about are accounts,
   to the person accounts whose `PersonIndividualId` is it; each field is read by name and
   only when the org has it. Any other parent is skipped. Contact point rows in a Nonprofit
   Cloud org usually hang off an Individual or a person account, which is why the Individual
   step is there.
7. **Values are compared after normalization, in Apex.** Email: trimmed and lower case.
   Phone: digits only, and an 11 digit number starting 1 loses the 1 (North American
   numbering). Address: the street in lower case with punctuation removed, whitespace
   collapsed and common words abbreviated (street to st, avenue to ave), joined to the postal
   code without spaces in upper case, with a US ZIP+4 cut to five digits. A value that
   normalizes to nothing, or a phone with fewer than seven digits, is not compared.
8. **Lookups are bounded.** For a group of records the sources are read for those parents,
   then candidates are found per source: emails by equality in one query; phones by a pattern
   that allows any separator between the digits; addresses by the postal code together with
   the street's first word that normalization leaves as written (usually the house number).
   Phone and address patterns go at most 100 to a query. Each candidate is normalized and
   compared exactly. Every lookup reads at most 5,000 rows; one that reaches the cap is
   counted and logged as a warning in the Error Log, once per source per transaction, because
   matches past the cap are missed. A value shared by more than ten people or households (an
   office switchboard, a shared mailbox) is not used, because it says nothing about whether
   two of them are the same.
9. **The duplicate scan.** It adds the pairs the sources find to the same review list and
   drops a pair a duplicate rule already found (the rule's pair is written, once). Two people
   in the same household are not paired by a phone or an address source, since sharing a
   home phone or an address is what a household is; an email source still pairs them. The
   scan proposes only what BarnCRM can merge (R-DP2): pairs of households and pairs of
   contacts; a person account pair found by a source is dropped there, as a rule's is. No
   save-time warning is added.
10. **Why a pair is proposed is kept in `Duplicate_Reason__c`.** A duplicate record set has no
    field for it, so Core writes one row per set a source found: Set Id (the set's id as
    text) and Reason ("Same email on Contact Point Email"). The review list reads it in system
    mode, since it holds only the source's label, and shows it in place of the rule's name. It
    is deleted when its set is dismissed or closed by a merge, best effort; a row whose set
    is gone some other way is never read again and is harmless.
11. **Source pairs are recorded under a stand-in rule.** The platform requires every
    duplicate record set to name a duplicate rule, so a source pair is recorded under any
    active rule for its object, and with no active rule for that object it is not recorded
    at all. Salesforce's own Duplicate Record Sets tab and reports therefore show a source
    pair under that stand-in rule; the reason is only on the review list.
12. **Import.** Only a people template with "Also match with my duplicate rules" ticked asks
    the sources, and only for incoming people the rules found nobody for. A source candidate
    is used only when its last name agrees with the incoming person's (trimmed, capitals
    ignored; a person account's person last name), so a shared address or phone never loads
    one person into another's record. A row with no agreeing candidate falls to the
    template's normal no-match handling. Values are the person's Email, Phone, MobilePhone,
    HomePhone and OtherPhone, and mailing and other street with postal code.

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
- Salesforce's Duplicate Record Sets tab shows a source pair under the stand-in active rule
  (decision 11), which an administrator may read as that rule's finding; the review list is
  where the true reason is shown.
- An import may load a row into an existing person a source found only when the last names
  agree; a person whose last name changed is created new and found by the next scan instead.
- To confirm in the first managed install: archiving a shipped source (`setShippedArchived`)
  deploys the row's developer-controlled values unchanged alongside `Active__c`. If a
  subscriber org refuses a deployment that carries developer-controlled values of a packaged
  row, deploy `Active__c` alone.
