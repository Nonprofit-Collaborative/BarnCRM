# ADR-NEXT: Several objects in one upload replaces the parent and child load

**Status:** Accepted (owner decision)
**Date:** 2026-10-30
**Source:** owner requirements for C-49c (Super Importer: several objects in one upload) and plan
decision D-154, 2026-10-30. Supersedes the load path of ADR-0111 (`0111-load-related-records.md`,
D-50 "parent and child loads"); extends ADR-0080 (`0080-import-load-one-object.md`) and canonical
model R-IT12 to R-IT19; adds R-IT20.

## Context

ADR-0111 let a one-object template also create one related object from the same rows: parents by
a key, then the related records, with the key's digest carrying the parent's outcome across
chunks. Files from other systems hold more than two objects, split them across sheets ("Programs",
"Sessions", "Attendees"), or put several on one row ("Account.Name", "Contact.LastName"). The
owner asked for single-object and multi-object uploads, each sheet loading its own object, one row
loading several, records on a row linked where a lookup exists, records on different sheets
linked by a column the user picks, and parents before children. D-154 says this replaces the
parent and child load rather than becoming a third load path.

## Decision

1. **One engine in steps.** `ImportObjectLoader` runs a chunk as a list of steps from
   `ImportObjectSchema.steps`: one for a one-object template; two for a legacy template with a
   Related Object (the record, then the related record, always inserted); one per object for an
   upload of several objects. Each step is the one-object load (operation, key, lookups, value
   reading, access, duplicate rules, Match only, journal) run over a step template (the object,
   its operation and key) and the mapping's columns of that object read as `Record` columns. The
   separate related-records code is gone; ADR-0111's rules (key grouping, the parent's digest,
   "parent failed", Related Status, Second Resulting Record, the run log line) are now how the
   engine treats a legacy template's two steps, so those templates load as before.
2. **Configuration.** A several-object template keeps `"objects"` in its mapping document
   (canonical model R-IT20): each object's API name, operation (never Delete) and key field. Its
   columns target `<object API name>.<field>`. The first object is the Target Object, so every
   one-object route (refusals at run start, the processor, the wizard) applies. No field is added.
3. **Order.** Steps load parents first: an object waits for every listed object it points at
   through a lookup or master-detail to that object alone that the user may fill in and the
   package does not keep. Where objects point at each other, the one waiting for the fewest goes
   first, the mapping's order breaking ties.
4. **Linking on a row.** A record links to the row's record of each earlier step its object
   points at, through the field named after the parent (`AccountId`, `Account__c`) or the first
   by API name. A new record takes the link; an existing record takes it only when its field is
   empty, so a load never moves a record to another parent. A column mapped to the link field is
   not read for a row that has the parent on it, and the run log says so.
5. **Linking across sheets.** A row of another sheet names its parent by a lookup column (by ID
   or a field the user chooses, R-IT13). The wizard stages the sheets parents first, so a parent
   is saved in the same chunk or an earlier one. In a dry run a lookup to an object the upload
   may create that finds nothing is left for the commit, and the run log says so.
6. **Repeats.** A step that later steps link to, and that finds records by a key, groups its
   repeated keys: the first row of a key loads the parent and later rows link to it. A row holds
   one digest, so only the first keyed object's repeats and failures are seen across chunks; the
   others are grouped within the chunk.
7. **Which rows load an object.** A row loads an object when it has a value of its own for it,
   not only a value for every row, so a sheet of one object creates none of another.
8. **Results, failures and undo.** A row is Rejected when any of its objects is, the reason
   naming the object; otherwise Created when it created any record, Updated when it changed any,
   else Matched. A record whose parent on the row failed is rejected and nothing is saved for it;
   a failed child leaves its parent saved. Resulting Record holds the row's first record. Each
   step's created records go on Created pages written in load order, so the undo, newest page
   first, deletes children before their parents; updates are journaled and put back as for one
   object. Staging, dry run, rejection, journal and undo are unchanged.

## Alternatives considered

- **A third load path beside one object and related records.** Refused by D-154: two engines for
  the same rules drift apart.
- **One batch run per object.** Cleanest ordering, but a row's records could not be linked, the
  run would have several statuses, and undo would span runs.
- **A key to ID map in the batch's state.** Grows with the file and dies with a chunk; the row
  digests and lookups by key already survive chunks.
- **Re-pointing an existing record at the row's parent.** Moves contacts out of households and
  records out of their real parent; filling only an empty link is reversible and safe.

## Consequences

- Existing related-records templates keep loading through the same rules; the wizard no longer
  offers the related records choice for a new template and offers Several Objects in One File.
- Account and Contact stay update-only (R-IT14) in an upload of several objects.
- Retrying a rejected row of several objects loads all its objects again: under Insert, one that
  was saved the first time is created again. Upsert and the updates find it instead.
- A second keyed parent's repeats across chunks are not seen through digests: under Upsert the
  later row finds the record by its key in the commit; a dry run may count it as created again.
- The results file shows one Resulting Record a row.
