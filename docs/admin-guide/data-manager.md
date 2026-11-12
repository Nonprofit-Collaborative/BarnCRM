# Data Manager

**Package:** Core
**Decision:** ADR-0103 `0103-org-optimizer-and-data-manager-pages.md`

## 1. What It Does

**Data Manager** is the one place to start any data task and to answer "what changed last
week, and can I undo it?" It has a tile for each data tool you may use, your import templates,
and one list of every data job: imports, Super Transformer runs and bulk deletes, newest first, each with
its counts and its **Undo**.

The tools themselves are unchanged. Super Importer, Find, Super Transformer, Bulk delete,
Org Optimizer and Duplicate Matching work exactly as their own pages in this guide describe;
Data Manager is how you reach them. Each tool has one name, used on its tab, its tile and in
Data Jobs: **Super Importer** brings records in from a spreadsheet, **Find** finds and exports
records, **Super Transformer** changes many records without a file.

## 2. How to Turn It On

On a new install the **Data Manager** feature is off until you turn it on: choose **Turn
on** in the **Data Manager** row in **BarnCRM Settings**, **General** (or leave it ticked in
first-run setup); see [BarnCRM Settings](barncrm-settings.md). While it is off its tabs are
hidden for everyone. Once it is on, the **Data Manager** tab is in the navigation of every
BarnCRM app (BarnCRM, BarnCRM Console, BarnCRM Admin and BarnCRM Admin Console) for anyone with
the **BarnCRM Admin** role or one of the **BarnCRM Find and Export**, **BarnCRM Bulk Update**
or **BarnCRM Bulk Delete** permission sets.

The page opens with one tile per tool, in short groups. Each tile has an icon, the tool's name
and one line; the whole tile is the control, so select anywhere on it. **About This Tool**,
under the page name, holds the longer help: it is open on your first visit and stays closed
after that unless you open it again (your browser remembers this, for you only). Each tile,
section and kind of job is shown only to people who may use it:

| Group | Tile or section | Needs a file? | Opens | Who sees it |
|---|---|---|---|---|
| **Bring Data In** | **Super Importer** ("Add or update records from a spreadsheet.") | Yes | The **Super Importer** tab (API name `Import`): people and organizations, gifts with Giving, any one kind of record, records with their related records, or deleting the records a file lists, with a preview first | Administrators |
| **Find and Change** | **Find** ("Find records, then save or export them.") | No | The **Find** tab: find records, save the query, export them to a file | Anyone with **Find and Export Records** |
| **Find and Change** | **Grid** ("Edit a saved query's records, and their related records, in one table.") | No | The **Find** tab on the Grid view: a saved query's records and up to two kinds of related record in editable tables, saved as named grids ([Grid](grid.md)) | Anyone with **Find and Export Records**; editing also needs **Bulk Update Records** |
| **Find and Change** | **Super Transformer** | No | The **Super Transformer** tab ("Change fields on many records at once, no file needed."): choose the object and the records, then change up to five fields on every record that matches ([Super Transformer](super-transform.md)). To start from a saved query, use Find's **Change Records**, **Super Transformer** instead | Anyone with **Bulk Update Records** |
| **Check and Tidy** | **Org Optimizer** | No | The **Org Optimizer** tab | Anyone with **Find and Export Records**, and administrators |
| **Check and Tidy** | **Duplicate Matching** ("Review possible duplicates and merge them.") | No | The **Duplicate Matching** tab ([Duplicates](duplicates.md)) | Administrators, and anyone with **BarnCRM Duplicate Review** or **BarnCRM Metadata Admin** |
| **Careful** | **Delete Many Records** | No | The **Find** tab, after a confirmation: run a query, then **Bulk Delete** | Anyone with **Bulk Delete Records** |
| | **Import Templates** section | | The templates you import with, and when each recurring file was last loaded | Administrators |
| | **Data Jobs** section | | Imports (administrators), Super Transformer runs (**Bulk Update Records**), bulk deletes (**Bulk Delete Records**) | As shown |
| **Salesforce's Own Tools** | **Weekly Data Export** (your backup), **Recycle Bin**, **Data Import Wizard** (records BarnCRM does not load) | | Salesforce's own page, in a new browser tab | Administrators |

A group with no tile you may use is left out. Each tile's icon is its tab's icon, the same as
in the navigation and the page header.

**What do you want to do?** Above the tiles, a search box finds the tool for a task. Type what
you want to do in your own words, for example "fix capital letters in names", "delete test
records", "merge two households", "import donors" or "find people without email". The tasks
that match are listed, each with the tool that does it; choose one to open that tool (a delete
still asks first, as below). Only tools you may use are listed. When nothing matches, the box
says so; choose a tile instead. The task list is a plain table of phrases in the page's code
(`dataManagerTasks.js`), not a setting.

"Administrators" means anyone with the **Manage BarnCRM Settings** permission, which the
**BarnCRM Admin** role carries.

**Which tool changes many records?** To change the same fields on many records without a file,
use **Super Transformer** (or a saved Find query, then **Change Records**, **Super Transformer**). To change records from a
spreadsheet, each row with its own values, use **Super Importer**. To delete records, use
**Delete Many Records** (a Find query, then **Bulk Delete**); to delete the records a
spreadsheet lists by record ID, an administrator who also has **Bulk Delete Records** uses
**Super Importer**, then the **Delete the Records a File Lists** card ([Bulk delete](bulk-delete.md)).

**Delete Many Records** is the last tile, alone in the **Careful** group. Choosing it shows a
**Delete Many Records** box that reads "Deleted records go to the
Recycle Bin. You can undo a bulk delete from Data Jobs, on this page, for up to 15 days."
**Continue** opens the Find tab to choose the records; **Cancel** (or Escape) closes the box and
nothing else happens. Nothing is deleted for good: a bulk delete, and a delete by file, go to
the Recycle Bin, and **Undo** brings them back (section 4).

**Import Templates.** A template remembers how a file's columns match BarnCRM fields, so every
file with the same layout (for example, a monthly donations export) opens already matched.
BarnCRM ships some (**People and Organizations List**, called **Generic contact list** in an
older org, **Organization List**, **Couples and Households**, **Relationships** and **Affiliations**, and with Giving the gift and
migration templates). To make your own, open **Super Importer** and choose **One Kind of
Record** in the first step (**What Are You Importing?**): choose the object, type a
**Template name**, and select **Create** ([Importing](importing.md), section 9); for a people
or gift file, choose a template and select **Start a New Template From This One**
([Importing](importing.md), section 6). There is no separate save step: the
column matches, changes and row rules you settle on are saved to the template each time you
import with it. The table's **Loads** column says in words what each template loads:
**People and organizations** for a people file, **Gifts** for a gift file, and for a
one-object template the object's plural name, for example **Addresses** (or its API name when
the object is no longer in the org).
On the page the section shows one line and a **Learn More** link to this guide;
with no template yet it shows **No Import Templates Yet** and a **Create a Template** button,
which opens **Super Importer**.

The **Super Importer**, **Find** and **Super Transformer** tabs are not in
the apps' navigation: open them from here or the App Launcher (the **Super Transformer** tab
changes many records without a file, see [Super Transformer](super-transform.md), and lists
recent Super Transformer runs, which **Data Jobs** below shows too). Bookmarks to them still work, and so do the links that open Find from elsewhere
(**Open in Find** on the Org Optimizer page, for example).

## 3. A Five-Minute Walkthrough (as Maria)

Start from the sample data (see [Sample data](sample-data.md)).

1. Open the **Data Manager** tab. The tiles at the top are the tools you can use.
2. Choose **Super Importer**. The Super Importer tab opens. Import a five-row file as
   [Importing](importing.md) describes, then come back to **Data Manager**.
3. Under **Data Jobs** your import is first, named **Super Importer** with its file name, a
   green **Complete** badge, how many people it created, and the date it can be undone until.
   The **Show** list filters by **Imports**, **Super Transformer runs** or **Bulk deletes**.
4. Choose **Find**, run a query for five people, and use **Change Records**, **Super Transformer** to
   set a field on them (see [Super Transformer runs and undo](bulk-update.md)). Back on **Data Manager**, press
   **Refresh**: the Super Transformer run is now first.
5. In **Show**, choose **Imports**. Only your import is listed. Choose **All** again.
6. Press **Undo** beside the Super Transformer run. The box says how many values the undo puts back. Type
   that number and press **Undo Super Transformer Run**. The job reads **Undoing**, then **Undone**; the
   list updates by itself while a job is running, so you do not need to press **Refresh**.

## 4. Undo From the Job List

Every kind of job is undone the way its own page describes, and every undo asks you to confirm
first, so nothing is undone by a stray click:

| Job | What Undo does | How you confirm |
|---|---|---|
| Import | Removes the people, households, organizations (and gifts, with Giving) it created and puts back the values it changed, keeping anything that has since gained a life of its own ([Importing](importing.md), section 5) | The box counts what it would remove and put back, by kind; press **Undo This Import** |
| Super Transformer run | Puts back the values it changed ([Super Transformer runs and undo](bulk-update.md)) | Type the number of values it puts back |
| Bulk delete | Brings the records back from the Recycle Bin ([Bulk delete](bulk-delete.md)) | Type the number of records it brings back |

**Undo** is shown only while a job can still be undone: before its **Undo until** date, and
only once. A job that can no longer be undone is still listed, with its counts.

## 5. Common Mistakes

- **Looking for the Super Importer or Find tab in the navigation.** They moved into Data
  Manager: choose the **Super Importer** or **Find** tile, or type the task in **What do you
  want to do?**.
- **Looking for the Import Rows tab.** It left the admin apps' navigation: open an import's
  results in Super Importer, or type **Import Rows** in the App Launcher. The tab and its list
  views are unchanged.
- **A job is missing from the list.** Each person sees the kinds of jobs they may run: imports
  need the BarnCRM Admin role, Super Transformer runs and bulk deletes their own permission sets. The list
  shows the ten most recent jobs of each kind; report on **Data Jobs** for older ones.
- **Undo is not offered.** The undo window has passed, the job was already undone, or it is
  still running. The job's status says which.
- **Expecting Data Manager to back up your data.** It does not copy your records anywhere. Use
  Salesforce's **Weekly Data Export**, linked under **Salesforce's Own Tools**.

## Field Reference

Data Manager adds no object and no field. Every data job is a **Data Job** record
(`Import_Batch__c`), with **Operation** Import, Update or Delete; see the field reference of
[Importing](importing.md), [Super Transformer runs and undo](bulk-update.md) and [Bulk delete](bulk-delete.md).
