# Data Manager

**Package:** Core
**Decision:** ADR-0103 `0103-org-optimizer-and-data-manager-pages.md`

## 1. What It Does

**Data Manager** is the one place to start any data task and to answer "what changed last
week, and can I undo it?" It has a card for each data tool you may use, your import templates,
and one list of every data job: imports, bulk updates and bulk deletes, newest first, each with
its counts and its **Undo**.

The tools themselves are unchanged. Import, Find, Bulk update and Bulk delete work exactly as
their own pages in this guide describe; Data Manager is how you reach them.

## 2. How to Turn It On

On a new install the **Data Manager** feature is off until you turn it on: choose **Turn
on** in the **Data Manager** row in **BarnCRM Settings**, **General** (or leave it ticked in
first-run setup); see [BarnCRM Settings](barncrm-settings.md). While it is off its tabs are
hidden for everyone. Once it is on, the **Data Manager** tab is in the navigation of every
BarnCRM app (BarnCRM, BarnCRM Console, BarnCRM Admin and BarnCRM Admin Console) for anyone with
the **BarnCRM Admin** role or one of the **BarnCRM Find and Export**, **BarnCRM Bulk Update**
or **BarnCRM Bulk Delete** permission sets.

The cards under **Start a Task** are listed in this order, and each card and each kind of job
is shown only to people who may use it:

| Card | Needs a file? | Opens | Who sees it |
|---|---|---|---|
| **Import a File** | Yes | The **Import** tab: add new records and update existing ones from a spreadsheet (people and organizations, gifts with Giving, or one object), with a dry run first | Administrators |
| **Find and Export Records** | No | The **Find** tab: find records, save the query, export them to a file | Anyone with **Find and Export Records** |
| **Update Many Records** | No | The **Find** tab: run a query, then **Bulk Update** changes up to five fields on every record it returns | Anyone with **Bulk Update Records** |
| **Tidy and Check Your Data** | No | The **Org Optimizer** tab | Anyone with **Find and Export Records**, and administrators |
| **Delete Many Records** | No | The **Find** tab, after a confirmation: run a query, then **Bulk Delete** | Anyone with **Bulk Delete Records** |
| **Import Templates** | | The templates you import with, and when each recurring file was last loaded | Administrators |
| **Data Jobs** | | Imports (administrators), bulk updates (**Bulk Update Records**), bulk deletes (**Bulk Delete Records**) | As shown |
| **Salesforce's Own Tools** | | Weekly Data Export (your backup), the Recycle Bin, and the Data Import Wizard for records BarnCRM does not load | Administrators |

"Administrators" means anyone with the **Manage BarnCRM Settings** permission, which the
**BarnCRM Admin** role carries.

**Which tool changes many records?** To change the same fields on many records without a file,
use **Update Many Records** (a Find query, then **Bulk Update**). To change records from a
spreadsheet, each row with its own values, use **Import a File**. To delete records, use
**Delete Many Records** (a Find query, then **Bulk Delete**); to delete the records a
spreadsheet lists by record ID, an administrator uses **Import a File**, **Load One Object**,
then **Delete by record ID** in **What each row does** ([Bulk delete](bulk-delete.md)).

**Delete Many Records** is the last card and is marked as destructive: its **Open** button is
red. Choosing **Open** shows a **Delete Many Records** box that reads "Deleted records go to the
Recycle Bin. You can undo a bulk delete from Data Jobs, on this page, for up to 15 days."
**Continue** opens the Find tab to choose the records; **Cancel** (or Escape) closes the box and
nothing else happens. Nothing is deleted for good: a bulk delete, and a delete by file, go to
the Recycle Bin, and **Undo** brings them back (section 4).

**Import Templates.** A template remembers how a file's columns match BarnCRM fields, so every
file with the same layout (for example, a monthly donations export) opens already matched.
BarnCRM ships some (the **Generic contact list**, and with Giving the gift and migration
templates). To make your own, open **Import a File** and use **Load One Object** in the first
step (**Choose what kind of file this is**): choose the object, type a **Template name**, and
select **Create** ([Importing](importing.md), section 9). There is no separate save step: the
column matches, changes and row rules you settle on are saved to the template each time you
import with it.

The **Import**, **Find** and **Bulk Update** tabs are not in the apps' navigation: open them
from here (the **Bulk Update** tab lists recent bulk updates, which **Data Jobs** below shows
too). Bookmarks to them still work, and so do the links that open Find from elsewhere
(**Open in Find** on the Org Optimizer page, for example).

## 3. A Five-Minute Walkthrough (as Maria)

Start from the sample data (see [Sample data](sample-data.md)).

1. Open the **Data Manager** tab. The cards at the top are the tools you can use.
2. Choose **Import a File**. The Import tab opens. Import a five-row file as
   [Importing](importing.md) describes, then come back to **Data Manager**.
3. Under **Data Jobs** your import is first, with its file name, **Complete**, how many people
   it created, and the date it can be undone until.
4. Choose **Find and Export Records**, run a query for five people, and use **Bulk Update** to
   set a field on them (see [Bulk update](bulk-update.md)). Back on **Data Manager**, press
   **Refresh**: the bulk update is now first.
5. In **Show**, choose **Imports**. Only your import is listed. Choose **All** again.
6. Press **Undo** beside the bulk update. The box says how many values the undo puts back. Type
   that number and press **Undo Bulk Update**. The job reads **Undoing**, then **Undone**; the
   list updates by itself while a job is running, so you do not need to press **Refresh**.

## 4. Undo From the Job List

Every kind of job is undone the way its own page describes, and every undo asks you to confirm
first, so nothing is undone by a stray click:

| Job | What Undo does | How you confirm |
|---|---|---|
| Import | Removes the people, households, organizations (and gifts, with Giving) it created and puts back the values it changed, keeping anything that has since gained a life of its own ([Importing](importing.md), section 5) | The box counts what it would remove and put back, by kind; press **Undo This Import** |
| Bulk update | Puts back the values it changed ([Bulk update](bulk-update.md)) | Type the number of values it puts back |
| Bulk delete | Brings the records back from the Recycle Bin ([Bulk delete](bulk-delete.md)) | Type the number of records it brings back |

**Undo** is shown only while a job can still be undone: before its **Undo until** date, and
only once. A job that can no longer be undone is still listed, with its counts.

## 5. Common Mistakes

- **Looking for the Import or Find tab in the navigation.** They moved into Data Manager:
  choose **Import a File** or **Find and Export Records**.
- **A job is missing from the list.** Each person sees the kinds of jobs they may run: imports
  need the BarnCRM Admin role, bulk updates and bulk deletes their own permission sets. The list
  shows the ten most recent jobs of each kind; report on **Data Jobs** for older ones.
- **Undo is not offered.** The undo window has passed, the job was already undone, or it is
  still running. The job's status says which.
- **Expecting Data Manager to back up your data.** It does not copy your records anywhere. Use
  Salesforce's **Weekly Data Export**, linked under **Salesforce's Own Tools**.

## Field Reference

Data Manager adds no object and no field. Every data job is a **Data Job** record
(`Import_Batch__c`), with **Operation** Import, Update or Delete; see the field reference of
[Importing](importing.md), [Bulk update](bulk-update.md) and [Bulk delete](bulk-delete.md).
