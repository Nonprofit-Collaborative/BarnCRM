# Archive by Query

## 1. What It Does

**Archive Records** frees storage by moving old records out of Salesforce into a file you
keep. You pick the records with a [Find](find.md) query (for example, gifts closed before
2015), and BarnCRM:

1. counts the records that match and shows the first five by name, with the kinds of related
   records Salesforce deletes with them, exactly as [Bulk Delete](bulk-delete.md) does;
2. after you type that number to confirm, saves every matching record, with every field you
   can see, as a CSV file in your **Files**;
3. only once the file is saved, deletes the records the way [Bulk Delete](bulk-delete.md) does,
   in the background, with your own access and journaled for undo;
4. only if you chose it and confirmed it a second time, empties those records from the
   Recycle Bin, so they no longer count against your storage and cannot be undone.

If the file cannot be saved, nothing is deleted. A record that was added or changed after the
file was started is never deleted by the archive: it is counted as no longer matching and left
where it is, so every deleted record is in the file.

Archive Records uses Bulk Delete's checks, limits and permissions. Everything in
[Bulk Delete](bulk-delete.md) sections 4 and 5 applies: the objects it refuses, the run limit,
locked records, and refusals listed with the reason.

## 2. How to Turn It On

There is nothing to turn on. Archive Records needs the same permissions as Bulk Delete:
**Bulk Delete Records** and **Find and Export Records**, given by the **BarnCRM Bulk Delete**
permission set (BarnCRM Settings, Access, Extra Permissions). **Bulk Delete Records is in no
role, not even BarnCRM Admin**: give it only to the few people who should delete records in
bulk.

The **Bulk delete run limit** (BarnCRM Settings, Import; default 10,000, at most 48,000) is
also the most records one archive may hold. Run a larger archive in parts, for example one
year at a time.

## 3. A Five-Minute Walkthrough (as Maria)

Maria's org is close to its data storage limit. She wants to keep gifts from before 2015 in a
file and take them out of Salesforce.

1. Open **Org Optimizer**, **Storage and Limits**, and check **Data storage**. Select
   **Archive Records**: Find opens, ready for an archive. (You can also start in **Find**
   directly.)
2. In Find, choose **Gift**, add the condition **Close Date**, **less than**, `2015-01-01`, and
   press **Run**. Check the results.
3. Open the **Change Records** menu and choose **Archive Records**. The panel opens under the
   buttons with its steps along the top: **Preview**, **Confirm**, **Run**.
4. Press **Preview**. BarnCRM says how many records match, for example 3,410, names the first
   five, and lists what Salesforce deletes with each one.
5. Type `3410` into **Type the number of records to confirm**.
6. Optional: tick **Also empty them from the Recycle Bin**. A warning says this cannot be
   undone. Type `3410` again into **Type the number again to empty the Recycle Bin**. Leave this
   off unless you need the storage back now: records in the Recycle Bin are emptied by
   Salesforce after 15 days anyway, and until then an undo can bring them back.
7. Press **Archive and Delete 3410 Records**. The progress bar first shows the file being
   saved, then the delete. You get a notification when the file is saved (it opens the file)
   and another when the delete finishes.
8. The file is in **Files**, owned by you, named like `Gift-2026-11-11-a1b2c3-part-1`. A very
   large archive is saved in more than one part, each with the header row. Keep the files
   somewhere safe; download them if your org's file storage is also tight.

## 4. Bringing Records Back

- **Within the undo window, if you did not empty the Recycle Bin:** open **Data Manager**,
  **Data Jobs**, and select **Undo** beside the job, as for any bulk delete. The records come
  back with their Ids, relationships and related records.
- **Later, or after emptying the Recycle Bin:** load the file with **Load one object** on the
  **Super Importer** tab ([Importing](importing.md)). The file's headings are field API names, so each
  column maps to its field. The records come back as new records with new Ids: fields Salesforce
  sets itself (Id, Created Date, Last Modified By and the like) are not loaded, and lookups to
  records that no longer exist stay empty. Related records Salesforce deleted with them are not
  in the file; archive those first, with their own query, if you may need them.

## 5. Common Mistakes

- **"More records match now than the 3410 you confirmed."** Somebody added records between
  your preview and the delete. Nothing was deleted; the file that was saved is kept. Press
  **Preview** again and confirm the new number.
- **The delete deleted fewer records than the file holds.** Records changed after the file was
  started are left in Salesforce on purpose (section 1). Run the archive again to take them out.
- **The archive file could not be saved.** Your file storage may be full, or you may not be
  allowed to create files. Nothing was deleted; the job shows **Failed** with the reason in its
  run log.
- **Undo says the records cannot be brought back.** The archive emptied them from the Recycle
  Bin. Load the file instead (section 4).

## Field Reference

| Where | Field | What it holds |
|---|---|---|
| Data Job | Operation | Delete, as for a bulk delete. |
| Data Job | Bulk Update Definition | The query, the confirmed count, and for an archive the time the file was started and whether the Recycle Bin is emptied. |
| Data Job | Run Log | The file's name, then the bulk delete's lines. |
| BarnCRM Settings, Import | Bulk delete run limit | The most records one archive or bulk delete may hold. Default 10,000, at most 48,000. |
