# ADR-NEXT: Import matching by Salesforce record ID, files that only match, and custom fields

**Status:** Accepted (owner decision, 2026-10-12)
**Date:** 2026-10-12
**Source:** owner decision of 2026-10-12 on the import gaps found by comparing C-32 with the
NPSP Data Importer; resolves plan Section 11 open question 15 (custom fields in the import
wizard) as yes. Builds on `NEXT-import-matching-per-entity-and-per-file-values.md`. Adds
canonical model R-IT10, R-IT11 and R-IB15 (Sections 15 and 16).

## Context

C-32 matched a row's people and organization by a rule (email, name plus postal code, a
chosen External ID field, or an organization's name). Two common files fell outside that. A
file exported from Salesforce carries each record's own ID, which is the one key that cannot
match the wrong record, and BarnCRM could not use it. A file meant to update records the org
already holds (new phone numbers, a corrected address list) could only be loaded by risking
that an unmatched row creates a duplicate person. The wizard also offered a fixed list of
columns, so an org's own fields could be imported only by editing a template by hand.

## Decision

1. **A record ID column.** A column can be mapped to `Contact1.Id`, `Contact2.Id` or
   `Organization.Id`. A row giving one is matched to that record and its matching rule is not
   asked. The ID must be a valid 15 or 18 character record ID whose key prefix is the
   object the entity is stored on (Contact, or Account in Person Accounts mode, for a person;
   Account for an organization). The record must exist and be readable by the importing user
   (one user-mode query per chunk and object), and an account must have the right record type:
   a person record type for a person account, the Organization record type for an
   organization. Any failure rejects the row with the reason. **An ID that is given but not
   found never creates a record**, because an ID means "this record", and creating another
   one would be a duplicate made on purpose. The ID is removed from the row's values before
   anything is written, so it is never written to a field. A blank ID cell is no ID. A value
   for every row of a file may not give a person's ID (R-IB14).
2. **Match only.** A file can be marked Match only (Import Batch `Match_Only__c`). A row
   whose organization or either person matches no record, by rule or by ID, is rejected with
   a message saying the file creates nobody. It is a choice for the file, not the template:
   the same mapping loads new people one month and corrections the next, and a choice kept on
   the template would silently carry over. The dry run rejects the same rows the commit will.
3. **Custom fields.** The wizard's column picker offers, besides the fixed columns, every field
   of the person's object (Contact, in contact terms, which Person Accounts mode translates as
   it does every person attribute) and of the organization's (Account, excluding person
   account fields) that describe says the user may read and create or edit, and that is not
   a formula, roll-up, auto number, lookup, compound address or location, system field, or
   one of the package's own bookkeeping fields. The import already writes any attribute the
   object has, through describe, with the field-level checks and run log notes of R-IB12, so
   no new write path is added.

## Alternatives considered

- **Record ID as a fourth person rule.** A rule applies to every row; an ID column applies to
  the rows that give one, so a file mixing exported and new rows still works, with the rule
  for the rest.
- **An ID that is not found falls back to the rule.** Would match a row meant for one record
  to another by email, which is exactly the mistake an ID exists to prevent.
- **Match only on the template.** Carries over to the next file without being seen; see 2.
- **A separate custom field picker.** One list of columns is simpler than two, and the
  combobox already filters as one types.
- **Offer lookup fields, taking an ID.** A lookup needs its target validated as well; left
  for when a file actually needs it.

## Consequences

- One field is added: `Import_Batch__c.Match_Only__c` (Checkbox, default false).
- A row with an ID is never a several-matches case (R-IT9), and is never shared with another
  row as a new person (R-IB12), since nothing is created for it.
- An ID the user cannot see reads as not found; the message says so, so a sharing gap is not
  mistaken for a wrong ID.
- The column list is longer in an org with many fields; fields are named "Person: <label>",
  "Second person: <label>" and "Organization: <label>".
- An org run must confirm the person account record type check and a custom field's write in
  Person Accounts mode, which the unit tests cannot reach in a Platform-only org.
