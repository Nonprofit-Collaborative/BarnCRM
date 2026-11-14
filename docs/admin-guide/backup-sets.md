# Backup Sets

## 1. What It Does

A **Backup Set** is a saved [Find](find.md) query that you can save to a file whenever you want a
copy of its records: before a big cleanup, before a bulk update, or as a monthly habit. Each run
saves every record the query returns, with every field you can see, as a CSV file in your
**Files**. The files are the same kind [Archive by Query](archive-by-query.md) writes, so you can
put values back later with **Load one object** on the **Super Importer** tab.

Nothing is deleted. A Backup Set only reads records and writes files you own.

Backup Sets are not a full backup of your org. For that, use Salesforce's own **Weekly Export**
(Data Manager, Salesforce tiles) or a backup service of your choice. Backup Sets keep a copy of
the records you choose, in your own org.

## 2. How to Turn It On

There is nothing to turn on. You need two permissions, both in **BarnCRM Admin**:

- **Manage BarnCRM Settings**, because the files hold every field of many records and restoring
  them is an import;
- **Find and Export Records**, to save and run Find queries.

Each run saves at most the **Export row limit** (BarnCRM Settings, Import; default 50,000).
A larger set is saved up to the limit, and the run says so.

Runs happen when you press **Run Now**. Scheduled runs come later, with scheduled imports.

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
- Files count against your org's file storage. Delete old runs' files in **Files** when you no
  longer need them; BarnCRM never deletes them.

## 6. Common Mistakes

- **"The set may hold more records than were saved."** The query returns more records than the
  Export row limit. Split it (for example by year) or raise the limit.
- **The run failed.** Your file storage may be full, or the query no longer runs (a field was
  deleted). The run log, in Data Manager's Data Jobs, says why.
- **The restore created duplicates.** The file was loaded with **Create** instead of **Update by
  record ID**. Undo that import and load it again.

## Field Reference

| Where | Field | What it holds |
|---|---|---|
| Data Job | Operation | Backup. |
| Data Job | Bulk Update Definition | The saved query's Id, name and object. |
| Data Job | Row Count | The records saved. |
| Data Job | File Name, File Id | The first part's title and document. |
| Data Job | Run Log | When it started, the parts written, and any warning. |
| BarnCRM Settings, Import | Export row limit | The most records one run saves. Default 50,000. |
