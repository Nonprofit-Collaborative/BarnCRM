# Backup Sets

## 1. What It Does

A **Backup Set** is a saved [Find](find.md) query whose records BarnCRM saves to files, when you
press **Run Now** or automatically on a schedule (daily, weekly or monthly): before a big cleanup,
before a bulk update, or every night. Each run saves every record the query returns, with every
field the person running it can see, as CSV files in **Files**. The files are the same kind
[Archive by Query](archive-by-query.md) writes, so you can put values back later with **Load one
object** on the **Super Importer** tab.

No record is changed or deleted. A scheduled set keeps the files of its newest runs (7 by
default) and deletes older ones, so storage does not keep growing.

Backup Sets are not a full backup of your org. For that, use Salesforce's own **Weekly Export**
(Data Manager, Salesforce tiles) or a backup service of your choice. Backup Sets keep a copy of
the records you choose, in your own org.

## 2. How to Turn It On

There is nothing to turn on. You need two permissions, both in **BarnCRM Admin Console**:

- **Manage BarnCRM Settings**, because the files hold every field of many records and restoring
  them is an import;
- **Find and Export Records**, to save and run Find queries.

Each run saves at most the **Export row limit** (BarnCRM Settings, Import; default 50,000).
A larger set is saved up to the limit, and the run says so.

Runs happen when you press **Run Now**, or on the set's schedule (see [Scheduling a Backup
Set](#scheduling-a-backup-set)).

## 3. A Five-Minute Walkthrough (as Maria)

Maria is about to tidy every household's mailing address and wants a copy first.

1. Open **Find**, choose **Household**, add the columns you care about (a Backup Set saves every
   field anyway), and press **Save** to save the query as `Households before cleanup`.
2. Open **Data Manager** and select **Backup Sets**. The panel lists your Backup Sets and your
   last runs.
3. Under **Add a Backup Set**, choose `Households before cleanup` and press **Add**.
4. Press **Run Now** beside it. The run shows **Running**; you get a notification when the file is
   saved, and the run shows **Complete** with the number of records.
5. Select the file name to open it. It is in **Files**, owned by you, named like
   `Account-2026-11-11-a1b2c3-part-1`. A very large set is saved in more than one part.

## Scheduling a Backup Set

A scheduled set runs by itself with BarnCRM's nightly jobs, so you always have a recent copy
without pressing anything.

1. Open **Data Manager**, **Backup Sets**.
2. Beside one of your own sets, press **Edit Schedule**.
3. Under **How Often**, choose **Daily**, **Weekly** (then the **Day of the Week**) or
   **Monthly** (then the **Day of the Month**, 1 to 28, so it runs every month).
4. Press **Save Schedule**. The set shows its schedule beside its name, such as "Weekly on
   Sunday". Choose **Not scheduled** to stop it; Run Now still works.

How scheduled runs work:

- They start at 2:00 AM (your time zone) as the **Backup Sets** step of the nightly jobs. If the
  nightly jobs are not scheduled, or their Backup Sets step is off, the panel says so: turn them
  on in **BarnCRM Settings**, **General**, **Nightly Jobs**.
- They run as the user who scheduled the nightly jobs, not as the set's owner. That user needs
  **Manage BarnCRM Settings** and **Find and Export Records**; without them nothing runs and the
  Error Log says why. The files are owned by that user, and hold what that user can see.
- **Backup Runs Kept** (BarnCRM Settings, Import; default 7, from 1 to 365) is how many runs of
  each scheduled set keep their files. When a run finishes, the files of that set's older runs
  are deleted from Files and each such run says "Files removed" in its log. A set you only run
  with Run Now keeps every file.
- Every run, scheduled or not, is listed under **Recent Runs** for the person who ran it, and in
  **Data Jobs**, with a log line saying which schedule started it.

## Sending Backups Off Platform

A copy inside Salesforce does not help if you lose access to the org. With the optional **BarnCRM
Connector** module installed, each run can also be sent to storage your organization owns outside
Salesforce, such as a storage container or a file server that accepts files over HTTPS. BarnCRM
sends the files; it never stores them anywhere else, and nothing here is a paid service.

Without the Connector, **Edit Schedule** has no **Save To** choice and shows a short note instead.

**Step by step:**

1. Install BarnCRM Connector, set up a connection to your storage, and make it the **Backup
   Destination** on the Connections tab of Super Connector (see
   [BarnCRM Connector, Backup Destination](connector.md#backup-destination)). The connection holds
   the key; BarnCRM never shows or stores it anywhere else.
2. Open **Data Manager**, **Backup Sets**, and press **Edit Schedule** beside one of your sets.
3. Under **Save To**, choose **Files and backup destination**, then **Save Schedule**.
4. Press **Run Now** to try it. **Recent Runs** shows "Sending to backup destination", then "Sent
   to backup destination". Check that the files arrived in your storage.
5. If you do not want a second copy in Files, turn on **Remove Files Copy After Sending**
   (BarnCRM Settings, Import). A run's files are then removed from Files once every part reached
   your storage. It is off by default.

How sending works:

- The run saves its files in Files first, then sends them one at a time. Nothing is lost if the
  storage cannot be reached: the files stay in Files.
- A file that could not be sent is written to the **Error Log** and to the run's log, and the run
  shows "Not all sent: the next scheduled run tries again". The next night's Backup Sets step
  sends it again.
- The person who runs the set (for scheduled runs, the user the nightly jobs run as) needs the
  **BarnCRM Connections** permission set, which holds access to the connection's key. Creating
  or checking the connection gives it to you; give it to the nightly jobs' user too.
- How long copies are kept in your storage is up to its own rules (such as a lifecycle or
  retention rule); BarnCRM never deletes anything there.

## 4. Putting Values Back

Open **Import**, choose **One Kind of Record**, and load the file:

- **To put back values that changed** (records that still exist): choose **Update by record ID**
  and map the **Id** column to **Salesforce record ID**. The file's other headings are field API
  names, so each maps to its field. Leave out the columns you do not want to put back.
- **To bring back records that were deleted:** first try **Undo** on the job that deleted them
  (Data Manager, Data Jobs) or the Recycle Bin. Otherwise choose **Create**: the records come back
  as new records with new Ids, as described in [Archive by Query](archive-by-query.md), section 4.

The import's preview shows what would change before anything is saved, and the import can be
undone like any other.

## 5. Managing Backup Sets

- **Remove from Backup Sets** takes the mark off the saved query. The query and the files of past
  runs are kept.
- A Backup Set is a saved query: rename, share or delete it in Find. Only its owner can add it to
  or remove it from Backup Sets; a query someone shared with you can be run but not removed.
- Files count against your org's file storage. For a set you run only with Run Now, delete old
  runs' files in **Files** when you no longer need them; BarnCRM keeps them. A scheduled set
  keeps the files of its newest **Backup Runs Kept** runs.

## 6. Common Mistakes

- **"The set may hold more records than were saved."** The query returns more records than the
  Export row limit. Split it (for example by year) or raise the limit.
- **The run failed.** Your file storage may be full, or the query no longer runs (a field was
  deleted). The run log, in Data Manager's Data Jobs, says why.
- **A scheduled set did not run.** Check the panel's note about the nightly jobs, then the
  Nightly Jobs panel's last result for **Backup Sets**, then the Error Log: the nightly jobs'
  user may lack Manage BarnCRM Settings or Find and Export Records.
- **The restore created duplicates.** The file was loaded with **Create** instead of **Update by
  record ID**. Undo that import and load it again.

## Field Reference

| Where | Field | What it holds |
|---|---|---|
| Data Job | Operation | Backup. |
| Saved query | Query document, `backup` key | Marks a Backup Set; its `schedule` holds how often and on which day. |
| Data Job | Bulk Update Definition | The saved query's Id, name and object, and every part's document. |
| Data Job | Row Count | The records saved. |
| Data Job | File Name, File Id | The first part's title and document; empty once the run's files are removed. |
| Data Job | Run Log | When it started, what started it, the parts written, and any warning. |
| BarnCRM Settings, Import | Export row limit | The most records one run saves. Default 50,000. |
| BarnCRM Settings, Import | Backup Runs Kept | How many runs of each scheduled set keep their files. Default 7. |
| BarnCRM Settings, Import | Remove Files Copy After Sending | Delete a run's files from Files once every part reached your backup destination. Off by default. |
| BarnCRM Settings, Import | Skip Backup Before Archive | Archive rule runs start without their backup first ([Archive Rules](archive-rules.md#a-backup-before-every-run)). Off by default. |
| Saved query | Query document, `backup` key | `destination`: Files and backup destination, when chosen. |
| BarnCRM Settings, General | Nightly Jobs, Backup Sets | The step that starts scheduled sets at 2:00 AM; on by default. |

The backup an [archive rule](archive-rules.md#a-backup-before-every-run) makes before each run is
listed among these runs by the rule's name. It is not a Backup Set: it is never sent off platform,
and Backup Runs Kept never removes its files.
