# ADR-NEXT: Erase a person anonymizes the record in place, as the user, with a module seam

**Status:** Proposed (builder decision; owner approved the feature, Brandon, 2026-10-13)
**Date:** 2026-10-13
**Source:** data tools parity report rank 18 ("Erase a person"), owner decision 4 of 2026-10-13;
builds on ADR-0021 (system mode only for the package's own bookkeeping), ADR-0036 and ADR-0070
(empty household tidy-up and its dependents seam), ADR-0059 (Core is neutral), ADR-0080 (the
protected fields), ADR-0091 (a dangerous data tool gets its own permission in no role)

## Context

A person can ask an organization to erase what it holds about them (GDPR Article 17, and
several state privacy laws). Today an administrator would have to find and blank every field,
address, relationship and affiliation by hand, and would still miss a household named after
the person, a linked Individual record and the field history. Deleting the record is not an
answer: a gift's donor lookup would empty and break the rule that every gift has a donor,
totals for the household and the person would change, and the record sits in the Recycle Bin
for 15 days with every value intact.

The law has edges. Records kept to meet a legal duty (gift records, tax receipts, accounting)
may be kept (GDPR Article 17(3)(b)), and what must be kept differs by country. Core cannot know
what Giving keeps (ADR-0059).

### What Salesforce provides, and what this uses

- **Individual** (Setup, Data Protection and Privacy, "Make data protection details available
  in records"): a record linked from Contact (`IndividualId`) and from a person account that
  holds privacy preferences, including **Forget this Individual** (`ShouldForget`). Salesforce
  does nothing automatic when it is set; it is the platform's marker that other systems (for
  example Marketing Cloud connectors) read. Available in every edition once the setting is on,
  absent otherwise. **Used**, found by describe, never named at compile time.
- **Field history** (`ContactHistory`, `AccountHistory`): keeps old values of tracked fields,
  including the ones an erasure clears. Salesforce lets a user with the **Delete From Field
  History** permission delete these rows through the API. **Used** where the user holds it.
- **Recycle Bin**: a deleted record keeps its values for 15 days. **Emptied** for what the erasure
  deletes.
- **Contact point objects** (`ContactPointEmail`, `ContactPointPhone`, `ContactPointAddress`):
  Nonprofit Cloud's and the consent model's home for contact details. **Not used**: Core may not
  depend on them (CI `check-standard-objects.sh`), BarnCRM keeps contact details on the person
  and in `Address__c`, and an org that also uses them is told so in the admin guide.
- **Privacy Center** (paid add-on, retention and erasure policies), **Shield** (Platform
  Encryption, Field Audit Trail) and **Data Mask** (sandboxes only): not in every edition, so not
  assumed. An org with Privacy Center can still use it; nothing here conflicts.

## Decision

1. **Anonymize in place, never delete the person.** The Contact, or the person account, stays,
   so every gift, soft credit and total that points at it keeps pointing at something and the
   anonymous totals stay right. Its name becomes the label "Erased person".
2. **What is cleared is worked out from describe, not listed.** Every field on the person's record
   that can be empty is emptied, so a field the org added (birth date, pronouns, a free text
   note) is not missed. Kept: the fields `DataProtectedFields` protects (the platform's own,
   formula and auto number fields, every Rollup Definition target, the fields the package
   writes), owner, record type, currency, the Individual link, and the fields an installed module
   asks to keep through the seam below. Checkboxes go back to their default, except opt-out flags
   (`HasOptedOut...`, `DoNotCall`, `ShouldForget`), which are set, so no mailing reaches the
   record. A field the platform requires and that is not the surname is kept and listed.
3. **The person leaves every household.** Contact mode empties the contact's account, junction
   mode ends each current membership (End Date today, not primary) through
   `HouseholdService.endMembershipsFor`. Household upkeep then recounts and renames as on any
   move, and a household left empty follows **Delete empty households** and the dependents seam
   (ADR-0036, ADR-0070). A household left empty that is kept (the setting is off, or gifts are
   credited to it) would still carry the person's name, greetings and address, so it is
   anonymized the same way: name "Erased household", Custom Name on, greetings and address
   fields emptied, its addresses deleted.
4. **Contact points and connections.** Addresses the person owns are deleted. Relationships on
   either side and affiliations are ended (End Date today, or the Start Date when that is
   later), lose their description, and an affiliation loses its role and primary flag. Ending
   rather than deleting keeps the other person's history ("was a spouse of an erased person").
5. **Salesforce's own privacy records.** The linked Individual is cleared the same way and gets
   Forget this Individual and every opt-out set. Field history of the person and the Individual
   is deleted after the erasure commits (the erasure itself writes history rows holding the old
   values), by a queueable that runs as the user; a user without Delete From Field History is
   told in the preview that history is kept. What the erasure deletes is emptied from the
   Recycle Bin.
6. **A seam for modules: `PersonErasureExtension`.** The same registry shape as
   `HouseholdDependentsExtension` (ADR-0070): `PersonErasureExtensions.EXTENSION_CLASSES` names
   `GivingPersonErasureExtension`, found with `Type.forName`. Two methods: `fieldsToKeep(type)`
   (fields of the person record the module maintains, for example a donor level) and
   `erase(personId)`, which changes the module's own records in the same transaction and says
   what it did and what it kept. Unlike the other seams, **an extension that is installed but
   cannot be built, or throws, refuses the whole erasure**: an erasure that skipped Giving would
   report done while personal data stayed.
7. **The preview is the erasure, rolled back.** `PersonErasure.preview` runs exactly the code the
   erasure runs inside a savepoint, collects what changed, and rolls back. So the preview cannot
   disagree with the erasure, and module changes appear in it with no second code path. A
   background job a trigger queues during the preview is not taken back by the rollback; the
   only ones that can be queued (rollup queue, household soft credit recompute) recompute from
   data the rollback restored, so they change nothing.
8. **As the user, all or nothing.** Every read that decides what to change runs in system mode
   (so a hidden field is not missed); every change runs in user mode. Before changing anything
   the erasure checks the user can edit the person and every record it will change, and can edit
   every field that holds a value; if not, it refuses and names what is in the way. Any refusal
   during the run rolls everything back. Two writes are bookkeeping under ADR-0021, in system
   mode: the audit record, and (Giving) the acknowledgment ledger's recipient email.
9. **An audit record that holds no erased value.** `Erasure__c` records who erased (Created By),
   when, which record (`Contact__c` or `Person_Account__c`, and `Erased_Record_Id__c` as text so
   it survives a later delete), an optional request reference the user types, and `Details__c`:
   each record changed, by object and Id, with the action and the field labels, never a value.
   No packaged permission set grants edit or delete on it.
10. **Its own permission, in no role, and a typed confirmation.** Custom permission
    `Erase_People`, granted only by the permission set **BarnCRM Erase People**, which is in no
    permission set group, as Bulk Delete (ADR-0091). The user types the person's current name
    to confirm, and the server checks it. A person already erased is refused.

### Giving's defaults (built in `GivingPersonErasureExtension`)

Gifts, soft credits, commitments, installments, allocations and receipts are kept unchanged:
amounts, dates and funds stay, and they keep pointing at the anonymized record, so household and
person totals do not move (posted and receipted gifts are locked anyway, ADR-0024, ADR-0053).
Receipt documents (the PDFs, which print the donor's name and address) are kept, as the record a
tax authority may ask for, and the preview counts them so an organization whose rules allow it
can delete them by hand (owner question). Tribute names typed for the person (as honoree or as
the person to notify) are emptied, and so is the message on a tribute of the person's own gift.
The acknowledgment ledger's recipient email and failure reason are emptied on rows sent to the
person. Active stewardship plans for the person are ended. Donor level fields are kept: they are
anonymous aggregates like the totals.

## Alternatives considered

- **Delete the person (and empty the Recycle Bin).** Rejected: breaks the donor rule on gifts,
  changes totals, and loses the anonymous aggregate the owner asked to keep.
- **A configurable list of personal fields.** Rejected: the field the admin forgets to list is
  the one that leaks. Clearing everything that can be cleared, minus a short protected list, needs
  no configuration and fails safe.
- **Reuse the data job (`Import_Batch__c`) as the audit.** Rejected: it is public read and write,
  an import user could edit or delete it, and the import history and undo would need new
  exclusions. A small object with no edit grant is the audit an erasure needs.
- **A separate preview code path.** Rejected: two paths drift; the rolled-back run is exact.
- **Use the contact point objects or Privacy Center.** Rejected for Core: not in every org (see
  Context).

## Consequences

- New: object `Erasure__c` (five fields), custom permission `Erase_People`, permission set
  `BarnCRM_Erase_People`, classes `PersonErasure`, `PersonErasureExtension`,
  `PersonErasureExtensions`, `PersonErasureHistoryCleanup`, one method on `HouseholdService`.
- An erased person has no household on purpose, so Health Check's "people with no household"
  and the matching data hygiene count leave out every person an Erasure record names (owner
  decision 2026-10-13, R-ER9).
- Tasks, events (by Name, Related To and shared activity relations) and files (by
  ContentDocumentLink) about the person are counted in the preview and listed as kept, for the
  admin to delete by hand; nothing in them is changed (owner decision 2026-10-13, R-ER10). Their
  free text can hold anything, so no rule could say which to keep.
- What this does not reach is listed in the admin guide: notes and emails about the person,
  Chatter feed tracking, reports already exported, backups, other systems, and
  custom objects of the org's own that hold personal data in their own fields.
