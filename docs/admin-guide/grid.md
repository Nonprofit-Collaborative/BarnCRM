# Grid

## What It Does

The **Grid** (C-41, C-41b) shows the records of a saved Find query in one editable table, with
up to two kinds of related record in tables of their own on the same screen: for example
households with their members and their gifts. Change a value right in a table and press
**Save**; the change is saved the way an edit in Find's results is, as one data job you can
undo. Save the whole layout as a named **grid** to open it again, or share it.

It is part of Core. It opens from the **Grid** tile in Data Manager and shows in the **Find**
tab, so it needs no tab of its own.

## Turn It On

- **Looking** at a grid needs the **Find and Export Records** permission, as Find does. The
  **BarnCRM Admin** role has it; give anyone else the **BarnCRM Find and Export** permission
  set (BarnCRM Settings, Access, Extra Permissions).
- **Changing** values in a grid also needs **Bulk Update Records**, as editing Find's results
  does. Without it, the grid is read only and says so.
- The **Data Manager** feature must be on (BarnCRM Settings, **General**) for the tile to show.

Nothing else to set up: there is no setting, object or permission set of its own.

## Use It

1. Build and save a query in **Find** (the fields you want as columns, and the conditions).
2. Open **Data Manager** and choose **Grid**.
3. In **Saved Query or Grid**, choose the query.
4. Under **Related Records**, use **Add a Related Record Column** for up to two kinds of related
   record and their fields (the same panel as in Find).
5. Press **Run**. The first table lists the records; one table under it per kind of related
   record. Select records in the first table to show only their related records.
6. Double-click a cell to change it, then press **Save** under that table. Each save is one data
   job: undo it from Data Manager, **Data Jobs**.
7. Type a **Grid Name** and press **Save Grid**. Tick **Share** to let everyone who can use Find
   open it. A grid you own can be saved again or deleted; anyone else's is saved as a new grid.

**Open in Find** opens the query in Find, to change its columns or conditions.

## Saved Grids

A saved grid is a Find saved query whose document also carries a `grid` key, so it shows in
Find's saved query list too (named with "(grid)" in the Grid's picker). Opening it in Find runs
the same query and related records; deleting it from either place deletes it.

## Limits and Notes

- The limits are Find's: up to 2 kinds of related record, 5 fields each, and 10 related records
  under each record. Fields read through a parent record (a dotted path such as
  `Account.Name`) are read only.
- Records and fields follow each person's own access, in user mode. A field the person may not
  change is not editable; a field they cannot see is not shown.
- A value the platform refuses (a validation rule, a required field) stays in the table with its
  reason, and the other rows are saved.
- The Grid adds no Apex: it uses Find's own server methods.
