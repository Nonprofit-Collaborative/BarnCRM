# ADR-NEXT: Archive rules move records to Files, a big object or an off-platform store, on a schedule

**Status:** Proposed (build agent W8 R1.36, 2026-11-21; for the integrator and Brandon)
**Date:** 2026-11-21
**Source:** Plan D-221 (Brandon: "the big object and off platform destination options with
automations available (example: any closed lost opportunity over 5 years old goes to big object
scheduled to run weekly) ... an option to view big object records and selectively move records
back to the regular object. Scheduled runs can be built now."). Builds on R-BD9 Archive by Query
(C-67), ADR-0213 (Backup Sets), ADR-0166 (nightly job dispatcher), ADR-0110 and ADR-0193
(person erasure seams). Platform facts from the EVAL-01 big object prototype in barn-platform.
The off-platform destination and scheduled Backup Sets are BK-10, built separately against the
seam this record defines.

## Context

Archive by Query saves a query's records to CSV files in the person's Files and then deletes
them. It runs by hand only, and a file is a poor place to look a record up again. Salesforce big
objects hold records outside data storage (one million rows included per org, more is a paid
add-on) and are read by an index, never by a report or list view.

Proven in barn-platform (EVAL-01): `Database.insertImmediate` after ordinary DML in the same
transaction throws an uncatchable error; the same index key overwrites the row (upsert); Batch
Apex, Apex Cursors and `COUNT()` do not work on big objects; a filter that skips an index field
aborts the transaction (uncatchable); `deleteImmediate` works only with exactly the index fields
set; `CreatedById` and `CreatedBy.Name` are readable; writes are not rolled back with the
transaction; an optional field needs field permission for any user-mode read.

## Decision

1. **One big object for every archived record.** Core ships `Archived_Record__b`, index
   `Object_Name__c` ASC, `Archived_At__c` DESC, `Original_Id__c` ASC. Fields: the record's name,
   owner Id, the record as JSON (long text), the people it names (long text, for erasure), the
   archive rule's Id and name. Who archived it is the row's `CreatedById`. One object serves
   every archived object, so the index is never changed per object (an index can never be
   changed once deployed). The index reads as the viewer browses: an object, then newest first
   within a date range.
2. **An archive rule is a saved Find query.** The query document gains an optional `archive`
   key (R-SQ18): `{ "version": 1, "destination": "Files" | "BigObject" | "OffPlatform",
   "frequency": "off" | "daily" | "weekly" | "monthly", "weekday": 1-7, "monthDay": 1-28,
   "active": true | false }`. As with Backup Sets (ADR-0213), no object is added: the rule is
   shared, renamed and deleted through the saved query's own rules, and its filter is the
   query's filter. Alternatives: a rule object (one more object, tab and permission grants for
   no new behavior); custom metadata per D-219 (a rule names a saved query, which is data, and
   a metadata record cannot point at data that differs between sandbox and production).
   Relative dates come from the filter document, which gains `more than n days ago` (R-R2
   extension, rendered `field < LAST_N_DAYS:n`): "closed lost and Close Date more than 1825
   days ago".
3. **Destinations are one seam.** `ArchiveDestination` (Core, `@NamespaceAccessible`) has a key,
   a reason it cannot be used here (null when it can), and `start(ArchiveRun)`, which returns the
   data job. `ArchiveDestinations.forKey` resolves Files (`ArchiveToFiles`, R-BD9 unchanged) and
   BigObject (`ArchiveToBigObject`) in Core, and OffPlatform (`OffPlatformArchiveDestination`,
   also Core), which runs R-BD9 with the file sent through BK-10's `OffPlatformDestination` seam
   before the delete. Until a module installs a ready backup destination, OffPlatform is offered
   but refused with a plain reason.
4. **A big object run never mixes DML and immediate writes in one transaction.** It is a
   queueable chain whose links alternate:
   - **Copy** (no DML): delete any archived copies the last link could not finish (below), read
     the next chunk of matching records in user mode in Id order with every readable field
     (R-BD8's fields) and their cascade-delete children, and `insertImmediate` them.
   - **Settle** (DML only): read back the rows just written by their full index key, read the
     originals again, delete in user mode the records whose copy exists and that were not changed
     since the run started (R-BD9's rule), add the count to the archive counter, write the job's
     counts and log, then queue the next Copy. A copy whose original could not be deleted is
     carried to the next Copy and deleted there, so a record is never both live and archived.
   The archive time and Original Id make the key unique, so a Copy retried writes the same rows.
5. **Children.** A record's cascade-delete children of kinds the person may read (the kinds the
   bulk delete preview lists, less the platform's sharing, history and feed rows) are saved in
   its JSON and restored with it. Their own cascade-delete children (a third level) are not
   saved: the preview names the kinds, and the platform deletes them with the record, to the
   Recycle Bin, as a bulk delete does today. Records that only look up to an archived record
   keep their record and lose the lookup, as with any delete.
6. **Who runs what.** Setting up, running and restoring need Manage BarnCRM Settings, Find and
   Export Records and Bulk Delete Records; a manual run has the bulk delete preview and the
   typed count. Turning a schedule on asks for the same typed count once; each scheduled run is
   capped by the bulk delete run limit and logs what it did. Records are read and deleted in
   the running person's user mode. Scheduled rules run as the Archive Rules step of the nightly
   run (ADR-0166), each due rule starting its own job, as the user who scheduled the nightly run; the step's
   switch and each rule's Active switch are the automation's switches (ADR-0166 item 4). The
   Automation Registry is not used: it lists record-triggered automations.
7. **The one-million cap.** `COUNT()` does not work, so Core keeps a running count on
   `BarnCRM_Settings__c.Archived_Record_Count__c`, changed only in Settle and restore links
   from the rows actually written or removed. The viewer and the rule list warn from 900,000
   rows; a Copy that would pass 1,000,000 stops the run, saying so. BarnCRM never suggests
   buying more: the remedy offered is restoring or deleting archived rows.
8. **Viewer and restore.** An Archived Records panel in Data Manager (and from Org Optimizer's
   Storage and Limits) lists archived objects, then rows of one object newest first within a
   date range, and shows a row's fields from its JSON. Restore inserts the selected records
   again in user mode: only fields the person may create, lookups only when their target still
   exists, children re-parented; what was left out is reported per record. A restored record gets
   a new Id: the run log keeps the old to new mapping, and the UI and guides say so. The next
   link `deleteImmediate`s the restored rows; the one after writes the count and log.
9. **Access.** `BarnCRM_Admin` grants read and create on the big object and read on its fields;
   viewer reads run in user mode, so a person without the grant sees nothing. Writes and
   deletes run in system mode after the person's permissions are checked (big objects have no
   sharing). The JSON holds every field the archiving person could read; anyone with the grant
   reads all of it, which the admin guide says.
10. **Erasure.** Core registers `ArchiveErasureExtension` in `PersonErasureExtensions`. Its
    `erase` queues a scan and reports the archived rows as counted, not listed. The scan runs
    after commit only when the person's Erasure record exists (so a preview, rolled back, does
    nothing), pages every archived object by index, and `deleteImmediate`s rows whose Original
    Id is the person or whose people list names them. `PersonErasure` itself is not changed.

## Alternatives considered

- **A big object per archived object.** Rejected: each needs its own index forever and its own
  permission grants; one generic object costs one slot.
- **Platform event hand-off instead of a queueable chain.** Rejected: one more object-like slot
  and a subscriber, for the same two-transaction shape.
- **Counting by scanning the big object.** Rejected as the only count: up to fifty transactions
  near the cap. The counter can drift only if a link fails between writing and counting; a
  Recount is a later addition if a pilot needs it.

## Consequences

- One new Core object (the big object, from the 100 big object allocation), one settings
  field, one operation value (`Archive` on `Import_Batch__c`), no new custom object for rules.
- The index can never change after the first install that ships it.
- Restored records have new Ids; integrations keyed on the old Id do not find them.
- Developer Edition's short queueable chain can stop a long run: the job says how far it got,
  and running the rule again continues, since archived records no longer match.
- Big object rows are not in reports or the weekly export; the viewer is the way in.

## Amendment: viewer, restore and erasure as built (AR-10 part 4, 2026-11-21)

Items 8 to 10 are built as decided, with these details settled:

1. **Opening the viewer.** Archived Records is a Data Manager panel (`archivedRecords`). Data
   Manager opens a panel named in its page state under `NamespaceUtil.stateKey('panel')`
   (`c__panel` unpackaged, the namespace's prefix packaged), served by
   `DataManagerController.panelStateKey` as `findToolStateKey` is. Org Optimizer's Storage and
   Limits button navigates to Core's `Data_Manager` tab with that state, so Core never depends
   on the module.
2. **Who sees it.** Viewing needs only the grant on `Archived_Record__b` (BarnCRM Admin), checked
   as object read access (`ArchiveController.canViewArchive` gates the tile and the button).
   Restoring also needs item 6's permissions. The panel and the admin guide say a viewer sees
   every field the archiving person could read.
3. **Paging.** Rows are read 50 to a page in index order with a cursor (the last row's time and
   Original Id), never an offset, which a big object does not support.
4. **Restore chain.** Up to 50 rows of one object per restore. Links alternate: Write (DML only)
   first settles the last Remove (reads the removed rows back by key and subtracts those gone
   from the count), then inserts the next 25 rows' records in user mode; Remove (no DML)
   `deleteImmediate`s the rows whose record was created. The last Write subtracts and finishes
   the job, so a two-chunk restore fits Developer Edition's five-link chain. A record whose saved
   child cannot be created is deleted again, so its row stays archived whole; a Write that
   throws rolls back to before its inserts. Restores are Archive data jobs with
   `"action": "restore"`; Rows Created counts records created, Rows Deleted rows removed.
5. **Erasure scan.** `ArchiveErasureExtension` is queued only when the archive count is above
   zero. `ArchiveErasureJob` reads the Erasure record for the person and matches rows against its
   erased record Id, Contact and Person Account; scan links read ten pages of 200 per object in
   index order and `deleteImmediate` matches; the final link (DML only) subtracts the count and
   writes any failure to the Error Log, since an Error Log insert may not share a scan link's
   transaction.
