# Archive Rules

## 1. What It Does

An **archive rule** is a saved [Find](find.md) query that moves the records it finds out of
their object, now or on a schedule. For example: "every closed lost opportunity whose Close
Date is more than 1825 days ago goes to the big object, every Sunday night".

Each rule sends its records to one **destination**:

- **Files (CSV):** the records are saved as a CSV file in your **Files**, then deleted, as
  [Archive by Query](archive-by-query.md) does. The Recycle Bin is left as it is. The file holds
  only the records the query finds: the related records Salesforce deletes with them are not in
  it, so they are kept only in the Recycle Bin, for 15 days.
- **Big Object:** each record, with every field you can read and the related records Salesforce
  would delete with it, is copied into BarnCRM's **Archived Record** big object, then deleted.
  Big object rows do not use your data storage.
- **Off Platform:** your own storage outside Salesforce. The records are saved to a file in your
  Files as with **Files (CSV)**, the file is sent to your backup destination, and records are
  deleted only once every part of the file was accepted. It needs BarnCRM Connector with a
  connection set as the **Backup Destination** ([BarnCRM Connector, Backup Destination](connector.md#backup-destination)); until then it
  shows as not set up and a rule cannot use it. As with **Files (CSV)**, the file holds only the
  records the query finds, so their related records are kept only in the Recycle Bin, for 15
  days.

Only **Big Object** keeps the related records with each record. Choose it when you may need them
back.

A record is only deleted after its copy is saved and read back. A record changed after the run
started is left alone and named in the run's log. So is a Big Object record that gained a
related record after it was copied: deleting it would delete that related record with no copy,
so it stays live, its copy is removed, and the next run archives it with all its related records.

### A Backup Before Every Run

Every run, whether you press **Run Now** or the schedule starts it, first **backs up** the
records it will archive to your Files, with the related records the archive takes with them (one
file per kind of related record). The archive starts only once that backup is saved in full:

- The backup is a data job with Operation **Backup**, listed under **Recent Runs** in
  [Backup Sets](backup-sets.md) by the rule's name. Its files stay in your Files until you delete
  them; **Backup Runs Kept** never removes them.
- While the backup is being saved, the rule counts as running: **Run Now** stays off for it.
- The run then moves at most the records the backup holds. A Big Object run keeps any record
  changed since the backup started, so every record moved is as its backup holds it.
- **If the backup is not saved in full** (the query cannot run, a file cannot be saved, or the
  records have more than 10,000 related records in one step), the run does not start: nothing is
  archived or deleted, **Recent Runs** in Archive Rules lists it as **Failed** with the reason,
  and the Error Log says so. If the rule was changed, paused or removed while its backup was being
  saved, the run is skipped the same way.

[Archive by Query](archive-by-query.md) is not backed up again: it already saves every record to a
file in Files before deleting anything.

**Skip Backup Before Archive** (BarnCRM Settings, Import, in the Find, Bulk Update and Bulk Delete
box; off by default) starts runs without the backup. It is riskier: if a run goes wrong, there is
no backup to restore from. Turning it on asks you to confirm. BarnCRM records who turned it on and
when: the setting shows "Turned on by" that person and the date and time while it is on, the
**Recent Changes** list on BarnCRM Settings keeps every change to it, and each run started
without a backup says so, and who turned the setting on, in its log.

## 2. How to Turn It On

There is nothing to install. You need:

- **BarnCRM Admin**, or the **BarnCRM Archive Admin** permission set for someone who is not a
  BarnCRM Admin;
- **BarnCRM Bulk Delete** (Find and Export Records, to save the query, and Bulk Delete Records,
  because a rule deletes records).

The **Big Object** destination also needs the Archived Record object, which only **BarnCRM
Admin** and **BarnCRM Archive Admin** grant. People with neither cannot see archived records
anywhere. See [Who Can See Archived Records](#who-can-see-archived-records).

Scheduled rules run in the nightly run's **Archive Rules** step (BarnCRM Settings, General,
Nightly Jobs), at 3:00 in the time zone of the person who scheduled the nightly jobs, and as that
person. The step ships on and does nothing while no rule has a schedule. Turn the step off there
to pause every rule at once.

Each night, before a scheduled rule runs, BarnCRM checks the rule's owner (the owner of its saved
query). If the owner is inactive, or no longer holds the three permissions above (and, for
**Big Object**, BarnCRM Admin), the rule is **skipped**, not run: nothing is archived. The skip
is listed under **Recent Runs** of the person who scheduled the nightly jobs as a **Failed** run
whose log says why, and as a Warning on the Error Log naming the rule. To start it again, change
the saved query's owner to an active person who holds those permissions (or give the owner the
permissions back); the rule runs on its next due day.

## 3. A Five-Minute Walkthrough (as Maria)

Maria wants closed lost opportunities older than five years out of the way every week.

1. Open **Find**, choose **Opportunity**, and add two conditions: **Stage** equals **Closed
   Lost**, and **Close Date** **is more than N days ago** with `1825`. Press **Save** and name
   it `Old closed lost`.
2. Open **Data Manager** and select **Archive Rules**.
3. Under **Add a Rule**, choose `Old closed lost` and press **Add**.
4. Set **Where Records Go** to **Big Object**, **How Often** to **Weekly**, and **Day** to
   **Sunday**. Leave **Active** ticked.
5. Turning a schedule on shows how many records the rule matches now and asks you to type that
   number, as a bulk delete does. Type it and press **Save**.
6. To run it now instead of waiting, press **Preview and Run**. The preview names five of the
   records and any related records Salesforce deletes with them. Type the count and press **Run
   Now**. The run appears under **Recent Runs** and updates until it ends. While it runs, **Run
  Now** stays off for that rule and says why, and the nightly run skips it (the Error Log says
  so): a rule runs once at a time.

## 4. Limits

- **Run limit.** Each run moves at most the **Bulk delete run limit** (BarnCRM Settings, Import;
  default 10,000). A scheduled rule with more matching records moves that many each time it runs.
- **One million archived records.** Salesforce includes one million big object rows in every org.
  The panel shows how many are used. From 900,000 it warns; a run that would pass 1,000,000 stops
  and says so. To make room, move records back or delete them from the archive. BarnCRM never
  goes past the included amount.
- **Record size.** A record whose fields and related records add up to more than 131,072
  characters, or that has more than 2,000 related records, is not archived; the run log names it
  and it stays where it is. Records with many related records are moved fewer at a time.
- **Related records.** The records Salesforce deletes with a record (the kinds the preview lists)
  are saved inside it, one level deep. Their own related records are deleted by Salesforce and go
  to the Recycle Bin. Records that only look up to an archived record keep their record but lose
  that lookup. Just before deleting, each run checks for related records added since the copy
  was made; a record that has one is kept for that run (see section 1).
- **A missed night is not caught up.** A weekly rule whose night was missed runs on its next day.

## 5. Managing Rules

- **Edit** changes where records go, how often, and **Active**. Untick **Active** to pause a rule
  and keep its schedule.
- **Remove** takes the rule off the saved query. The query, files of past runs and archived
  records are kept.
- A rule is a saved query: rename, share or delete it in Find. Only its owner can edit or remove
  the rule; someone it is shared with can preview and run it.
- Each big object run is a data job with Operation **Archive**. **Recent Runs** shows how many
  records each run moved and left out, and its log names each one left out and says why. A Files run
  is an Archive by Query delete job, listed in Data Jobs.
- If a run stops unexpectedly, its log says so and the run is **Failed**: records already moved
  stay archived, the rest stay where they were, and running the rule again continues. In the rare
  case an archived copy of a record that was kept cannot be removed, the log counts it: that
  record is then both live and archived, so do not restore that copy.
- **The Archived records count stays true when a run stops.** Salesforce cannot count big object
  rows, so BarnCRM keeps a running count. Before each step that writes or removes archived rows,
  the run notes those rows on its data job; the next step, or the clean-up that runs when a step
  stops unexpectedly, reads them back and counts only what is really there. If a run stops with
  no clean-up at all (for example, someone aborts it in Setup), the nightly run's **Archive
  Rules** step finds it a day later, brings the count up to date and marks the run **Failed**
  with a line saying so. The same applies to restores and to erasures.

## 6. Archived Records: Looking Records Up

Records a Big Object rule moved are listed in **Data Manager**, **Archived Records** (or press
**View Archived Records** in Org Optimizer's **Storage and Limits**, which opens the same panel).

1. Choose a **Kind of Record**. Only kinds that have archived records are offered.
2. Optionally set **Archived From** and **Archived To** to the dates the records were archived
   (not their own dates), then press **Show**.
3. Records are listed newest first, 50 to a page, with **Next Page** and **Previous Page**. Each
   row shows the record's name, its original Id, when it was archived, the rule and who ran it.
4. Press **View** on a row to see its fields and how many related records were saved with it.

The panel always asks for a kind of record first, then dates: that is the only order Salesforce
can read the archive in. Archived records are not in reports, list views or the weekly export.

### Who Can See Archived Records

Only **BarnCRM Admins**, and people given the **BarnCRM Archive Admin** permission set. Each
archived record holds **every field the person who archived it could read**, and anyone who can
open the panel sees all of those fields, whatever their own field access is. The Archive Rules
and Archived Records panels say so. Give these only to people who may see every field.

To give someone who is not a BarnCRM Admin access, open the [Access](access.md) page, choose the
person, and add **BarnCRM Archive Admin** under **Extra Permissions**. With it alone they can look
archived records up. Add **BarnCRM Bulk Delete** as well for them to run archive rules and
restore records. BarnCRM Archive Admin grants nothing else of BarnCRM Admin: no settings, no
Error Log, no other tools.

## 7. Moving Records Back (Restore)

Restore needs the same permissions as running a rule (section 2): BarnCRM Admin or BarnCRM
Archive Admin, with BarnCRM Bulk Delete.

1. In **Archived Records**, show a page of records and tick the ones to move back (up to 50, all
   of one kind, on one page).
2. Press **Restore** and confirm. The restore runs in the background; its log is under **Recent
   Runs** in **Archive Rules**. The page is read again at once. A record already in a restore
   that is still running cannot be restored again until that restore ends: the panel says so.

What a restore does:

- **New Ids.** Each record is created again, so it gets a **new record Id**. Links, reports or
  integrations that used the old Id do not find it. The run log lists every old Id with its new
  Id ("Restored 003... as 003...").
- **Your access.** Records are created as you, with only the fields you may create. Fields you
  cannot create are left out.
- **Lookups.** A lookup is kept only when the record it points at still exists and you can see
  it (an owner must be an active user). Otherwise it is left out.
- **Related records** saved with the record are created again under the new record.
- **What was left out** is listed per record in the run log ("Left out of 003...: ReportsToId").
- **Failures.** A record that cannot be created, or whose related record cannot be created, is
  not restored and **stays archived**; the log says why. The others are restored.
- Once records are created, their archived rows are removed and the **Archived records** count
  goes down. If a row cannot be removed, the log names the record, which is then both live and
  archived.
- If a restore stops unexpectedly, it is **Failed** and its log says so: records already restored
  stay restored, and the rest are still in the archive, so restore them again.

## 8. Erasing a Person

When you [erase a person](erase-a-person.md), archived records that are that person, or that
name them in a lookup (for example a gift whose donor was the person), are deleted from the
archive in the background once the erasure is saved. The erasure summary lists **Archived
records** as deleted, counted rather than listed. A preview deletes nothing. The archived record
count goes down as the background work goes. When it finds archived records to delete, the work is
listed under **Recent Runs** of the person who erased, as "Erasure: removing archived records that
name an erased person", with how many it removed; it names no person. If that background work
stops unexpectedly, an Error in the Error Log says so, naming no record, and the run is
**Failed**: some archived records may still name the person.

## Field Reference

| Where | Field | What it holds |
|---|---|---|
| Saved query | Query (the `archive` key) | Where records go, how often, the day, and Active. |
| Data Job | Operation | Archive, for a big object run. |
| Data Job | Bulk Update Definition | The rule's saved query, name, object, and when the run started; while it runs, the archived rows its next step writes or removes, until they are counted. |
| Data Job | Row Count | The most records the run may move. |
| Data Job | Rows Deleted | Records moved into the archive; for a restore, rows removed from the archive. |
| Data Job | Rows Created | For a restore, records created again. |
| Data Job | Rows Rejected | Records left out (or, for a restore, left archived); the Run Log names them. |
| Data Job | Run Log | For a restore, each old Id with its new Id and the fields left out. |
| Data Job | Operation | Backup, for the backup before a run; its definition holds the run under `beforeArchive`. |
| BarnCRM Settings | Archived Record Count | How many rows the archive holds, kept by BarnCRM. |
| BarnCRM Settings, Import | Skip Backup Before Archive | Start runs without the backup first. Off by default; turning it on is confirmed and recorded. |
| Archived Record | Object, Archived At, Original Id | The row's key. |
| Archived Record | Name, Owner Id, Rule Name | What the viewer lists. |
| Archived Record | Record | The record and its related records as JSON. |
