# ADR-0080: Import loads one object: insert, update by record ID, upsert, with an allow-list

**Status:** Accepted (builder decision)
**Date:** 2026-10-12
**Source:** plan Section 4.9 ("Load one object", "Fields that can never be bulk updated or
imported over", "Architecture decisions") and feature C-33. Builds on ADR-0047, ADR-0021 and
`0069-import-record-id-matching-and-match-only.md`. Adds canonical model R-IT12 to R-IT14 and
amends R-IT1, R-IB8, R-IB9, R-IJ3 and Section 17A (a journal phase for created records).

## Context

C-14 to C-32 load a row as a household, up to two people, an organization and an affiliation,
and hand the rest to an entity processor. Three kinds of file do not fit: an export fixed in
Excel and loaded back into the object it came from, a Community Suite org's own objects, and
the module templates the plan builds on this feature (V-06 volunteer hours, P-06 program
rosters). The plan asks for one object at a time, any object including custom ones, with the
same batch, dry run, journal and undo, every read and write in the running user's own access,
and nothing written to setup or to the package's own bookkeeping.

A one-object load cannot rely on the batch tag (R-IB3) for its undo: an arbitrary object has no
Created By Import Batch field, and Core cannot add one to it.

## Decision

1. **A template loads one object when it names one.** `Import_Template__c` gains Target Object
   (the object's API name as describe gives it), Load Operation, Load Match Field and Lookup Not
   Found. A row of such a template is one record: its mapping targets are `Record.<field API
   name>`, and `Record.Id` names an existing record. The object and every field are taken from
   the running user's describe, at save time and again in every chunk; an object or field the
   user cannot see is refused, never guessed.
2. **Three operations, decided by the loader, not by `Database.upsert`.** Insert creates a
   record per row. Update by record ID changes the record a row's `Record.Id` names; an ID that
   is invalid, of another object, or not visible rejects the row, and nothing is created for it.
   Upsert by external ID finds the record by a field the object marks External ID (text or
   email, readable by the user), updates it when found and creates one when not. The loader
   reads the existing records itself in user mode, so the dry run makes the same decision as the
   commit, a key several records hold follows Several Matches (R-IT9), and the journal holds
   each value before. A row repeating an earlier row's ID or key is rejected wherever the file's
   chunks fall (a digest in Processor Key, as R-IR6 uses it).
3. **Lookup columns name their parent three ways.** By record ID (the default), by the parent's
   name field, or by one of the parent's External ID or Unique fields, chosen per column and
   held as `lookupField` in the mapping document. A lookup that can point at several objects is
   read by record ID only. A value that finds no parent rejects the row, or leaves the lookup
   empty when the template says so (Lookup Not Found); one that finds several follows Several
   Matches.
4. **An allow-list, decided from describe (R-IT14).** An object may be loaded only when all of
   these hold:
   - it is a custom object (not a custom setting, custom metadata, platform event, big object or
     external object), or a standard object that describe calls a business record: searchable
     and queryable;
   - it is not a share, history, feed or change event object;
   - it is not a Salesforce setup or security object: users, groups and group members, queues,
     profiles, roles, permission sets and their groups, assignments and licenses, object and
     field permissions, setup entity access, record types, the organization, user and package
     licenses, and network members;
   - it is not the package's own bookkeeping (import templates, batches, rows and journal pages,
     error log, setting changes, automation settings, rollup definitions) or household
     membership rows, which only the household service writes (R-M5);
   - it is not an object a module protects through the new `DataProtectionExtension` seam
     (Giving: receipts, receipt runs, receipt number sequences, acknowledgments and their runs),
     so Core names no module object;
   - the running user can read it and can create records (Insert), edit them (Update) or both
     (Upsert).

   **Accounts and contacts load by Update only.** People, households and organizations are
   created by the people import, which builds households and memberships; a one-object insert
   of contacts or accounts would leave that undone.
5. **What is never written** (plan Section 4.9): system fields, formula and auto number fields,
   every Rollup Definition target, the import tag, the package's `Last_Calculated` fields, the
   household fields the household automation keeps on accounts and contacts, and a household's
   name. The list is built from describe and the Rollup Definitions at run time, in a class of
   its own (`DataProtectedFields`) that bulk update (C-35) also uses since landing. A field the user may not
   write is skipped and named in the run log.
6. **A value the field cannot take rejects the row.** The people import skips such a value and
   logs it, because the row still describes a person; a one-object row is one record, and
   loading part of it would be a silent partial change.
7. **Created records are journaled.** A commit of a one-object template journals each record it
   created as a Created entry on pages of a new journal phase, Created, and each record it
   updated as an Updated entry, as today. Undo deletes the journaled creations after putting
   values back, with every check R-IB9 makes (edited since, gained a record since, a module's
   reasons), and also keeps a journaled record that the committer did not create during the
   commit, so a journal entry can never delete somebody else's record. The count shown before
   an undo includes them under the object's plural label.
8. **Match only and values for every row.** Under Match only (R-IB15) a row that would create a
   record is rejected. A value for every row may not be the record ID or the upsert key, since
   every row would then be one record.

## Alternatives considered

- **`Database.upsert` with the external ID field.** The platform decides at save time, so the
  dry run could not say which rows create, several holders of a key raise an error instead of
  following the template's rule, and the value before is not read for the journal.
- **A deny-list alone.** Every new standard object Salesforce ships would be loadable by default,
  including setup objects added after this was written; describe's business-record properties
  keep the default closed.
- **Allow inserting accounts and contacts.** Would create people without households and
  organizations outside the people model's matching; the people import does that job.
- **Tag created records with a field.** Core cannot add a field to another package's object or to
  a subscriber's own; the journal can name any record.
- **Name Giving's receipts in Core's list as text.** Works, but Core would name a module's
  objects; the seam keeps the list with the module, as the Health Check and Setup Assistant
  seams do (ADR-0057, ADR-0059).

## Consequences

- `Import_Template__c` gains four fields; `Import_Journal__c.Phase__c` gains Created; the mapping
  document gains the `Record` entity and `lookupField`. No field is added to any loaded object.
- New Core classes: `DataProtectedFields`, `DataProtectionExtension`, `DataProtectionExtensions`,
  `ImportObjectSchema`, `ImportObjectLoader`; Giving gains `GivingDataProtectionExtension`.
- An undo of a one-object load reads its Created pages in a pass of its own.
- A load runs the target object's own automation in the running user's mode, as a save by hand
  would; a validation rule or trigger that refuses a record rejects that row with the platform's
  words.
- An org run must confirm the objects offered in an org with standard business objects (the
  scratch org shapes have few) and a load into a Giving object with Giving installed.
