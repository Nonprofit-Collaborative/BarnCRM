# Data Manager

**Package:** Core
**Decision:** ADR-0103 `0103-org-optimizer-and-data-manager-pages.md`

## 1. What it does

**Data Manager** is the one place to start any data task and to answer "what changed last
week, and can I undo it?" It has a card for each data tool you may use, your import mappings,
and one list of every data job: imports, bulk updates and bulk deletes, newest first, each with
its counts and its **Undo**.

The tools themselves are unchanged. Import, Find, Bulk update and Bulk delete work exactly as
their own pages in this guide describe; Data Manager is how you reach them.

## 2. How to turn it on

There is nothing to turn on. The **Data Manager** tab is in the BarnCRM app for anyone with
the **BarnCRM Admin** role or one of the **BarnCRM Find and Export**, **BarnCRM Bulk Update**
or **BarnCRM Bulk Delete** permission sets.

Each card and each kind of job is shown only to people who may use it:

| Card | Opens | Who sees it |
|---|---|---|
| **Import a file** | The **Import** tab: people, organizations, gifts (with Giving), or one object | Administrators |
| **Find and export records** | The **Find** tab | Anyone with **Find and Export Records** |
| **Change many records** | The **Find** tab: run a query, then **Bulk update** | Anyone with **Bulk Update Records** |
| **Delete many records** | The **Find** tab: run a query, then **Bulk delete** | Anyone with **Bulk Delete Records** |
| **Tidy and check your data** | The **Org Optimizer** tab | Anyone with **Find and Export Records**, and administrators |
| **Import mappings** | The mappings you import with, and when each recurring file was last loaded | Administrators |
| **Data jobs** | Imports (administrators), bulk updates (**Bulk Update Records**), bulk deletes (**Bulk Delete Records**) | As shown |
| **Salesforce's own tools** | Weekly Data Export (your backup), the Recycle Bin, and the Data Import Wizard for records BarnCRM does not load | Administrators |

"Administrators" means anyone with the **Manage BarnCRM Settings** permission, which the
**BarnCRM Admin** role carries.

The **Import** and **Bulk Update** tabs are no longer in the app's navigation: open them from
here. Bookmarks to them still work. **Find** stays in the navigation, because staff use it
every day.

## 3. A five-minute walkthrough (as Maria)

Start from the sample data (see [Sample data](sample-data.md)).

1. Open the **Data Manager** tab. The cards at the top are the tools you can use.
2. Choose **Import a file**. The Import tab opens. Import a five-row file as
   [Importing](importing.md) describes, then come back to **Data Manager**.
3. Under **Data jobs** your import is first, with its file name, **Complete**, how many people
   it created, and the date it can be undone until.
4. Choose **Find and export records**, run a query for five people, and use **Bulk update** to
   set a field on them (see [Bulk update](bulk-update.md)). Back on **Data Manager**, press
   **Refresh**: the bulk update is now first.
5. In **Show**, choose **Imports**. Only your import is listed. Choose **All** again.
6. Press **Undo** beside the bulk update. The box says how many values the undo puts back. Type
   that number and press **Undo bulk update**. The job reads **Undoing**, then **Undone**.

## 4. Undo from the job list

Every kind of job is undone the way its own page describes, and every undo asks you to confirm
first, so nothing is undone by a stray click:

| Job | What Undo does | How you confirm |
|---|---|---|
| Import | Removes the people, households, organizations (and gifts, with Giving) it created and puts back the values it changed, keeping anything that has since gained a life of its own ([Importing](importing.md), section 5) | The box counts what it would remove and put back, by kind; press **Undo this import** |
| Bulk update | Puts back the values it changed ([Bulk update](bulk-update.md)) | Type the number of values it puts back |
| Bulk delete | Brings the records back from the Recycle Bin ([Bulk delete](bulk-delete.md)) | Type the number of records it brings back |

**Undo** is shown only while a job can still be undone: before its **Undo until** date, and
only once. A job that can no longer be undone is still listed, with its counts.

## 5. Common mistakes

- **Looking for the Import tab in the navigation.** It moved into Data Manager: choose **Import
  a file**.
- **A job is missing from the list.** Each person sees the kinds of jobs they may run: imports
  need the BarnCRM Admin role, bulk updates and bulk deletes their own permission sets. The list
  shows the ten most recent jobs of each kind; report on **Data Jobs** for older ones.
- **Undo is not offered.** The undo window has passed, the job was already undone, or it is
  still running. The job's status says which.
- **Expecting Data Manager to back up your data.** It does not copy your records anywhere. Use
  Salesforce's **Weekly Data Export**, linked under **Salesforce's own tools**.

## Field reference

Data Manager adds no object and no field. Every data job is a **Data Job** record
(`Import_Batch__c`), with **Operation** Import, Update or Delete; see the field reference of
[Importing](importing.md), [Bulk update](bulk-update.md) and [Bulk delete](bulk-delete.md).
