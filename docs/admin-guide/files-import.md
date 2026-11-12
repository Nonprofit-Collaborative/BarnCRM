# Import Files

## 1. What It Does

**Import Files** loads documents from another system (signed forms, grant letters, photos, old
attachments) into Salesforce **Files**, each linked to the record it belongs to. You give it one
zip file holding the documents and a list, `manifest.csv`, that says which record each document
belongs to. A dry run checks everything first and loads nothing; the load can be undone.

## 2. How to Turn It On

There is nothing to turn on. You need **Manage BarnCRM Settings** (in **BarnCRM Admin**), as for
every import. The files are saved with your own access: you own them, and you can only link a
file to a record you can see.

Limits:

- at most 2,000 files in one zip;
- each file at most 2 MB (a larger file can be added to its record by hand);
- each group of files sent together at most 2 MB in all: a file that would overflow a group is
  refused with "This group is full. Load again." (it is not too large; load it again);
- a browser that can unzip files (any current Chrome, Edge, Firefox or Safari).

## 3. Making the Zip

1. Put the documents in a folder. Subfolders are fine.
2. Make `manifest.csv` in the same folder (Excel's **Save As**, CSV UTF-8), with a heading row and
   one row per document:

   | File | Record Id | Title | Description |
   |---|---|---|---|
   | letters/smith-2019.pdf | 0035g00000AbCdEAAV | Smith pledge letter 2019 | Signed copy |
   | photos/gala.jpg | 001Hp00002XyZaBIAV | | |

   - **File** (required): the document's path inside the zip, with forward slashes.
   - **Record Id** (required): the Salesforce record Id of the person, organization, gift or any
     other record. Get Ids from a [Find](find.md) export or an import's results file.
   - **Title** (optional): the name shown in Files. Blank uses the file name.
   - **Description** (optional): shown in the file's details.
   - Other columns are ignored.
3. Zip the folder's contents so `manifest.csv` is at the top of the zip, not inside a folder.

## 4. A Five-Minute Walkthrough (as Maria)

Maria's old database kept a scanned pledge letter for each major donor.

1. Open **Data Manager** and select **Import Files**.
2. Choose the zip. The panel reads it in your browser and shows how many rows the manifest has.
3. Press **Dry Run**. Each row is checked: the file is in the zip and not too large, the record
   Id is real and you can see the record, and the row is not repeated. The panel shows how many
   rows are ready and lists every row that is not, with the reason. **Download Rows** saves the
   list as a CSV.
4. Fix the zip if you need to and run the dry run again, or go on with the rows that are ready.
5. Press **Load Files**. The progress bar counts the files as they are saved. Keep the page open
   until it finishes.
6. Open one of the records: the document is in its **Files** related list.

## 5. Undo

Within the import undo window (BarnCRM Settings, Import, **Days an import can be undone**), open
**Data Manager**, **Data Jobs**, or the Import Files panel's **Recent Loads**, and select
**Undo** beside the job. Every file the job saved is deleted, except a file someone has uploaded a
new version of since: that file is kept, and the job's run log counts it.

## 6. Common Mistakes

- **"The zip has no manifest.csv at its top."** The zip holds a folder that holds the manifest.
  Zip the folder's contents, not the folder.
- **"No file with this name is in the zip."** The File column must match the path inside the zip
  exactly, including subfolders and capital letters.
- **"No record with this Id that you can see."** The Id is from another org, the record was
  deleted, or sharing hides it from you.
- **You closed the page during the load.** The files sent so far are saved and the job shows
  **Failed** in Data Jobs. Undo it, or load the zip again with only the rows that were not saved.

## Field Reference

| Where | Field | What it holds |
|---|---|---|
| Data Job | Operation | Files. |
| Data Job | File Name | The zip's name. |
| Data Job | Row Count | The files the load set out to save. |
| Data Job | Rows Created, Rows Rejected | Files saved, and files the platform refused. |
| Data Job | Undo Deadline | The end of the undo window. |
| Data Job | Run Log | When it started and finished, and what an undo deleted and kept. |
