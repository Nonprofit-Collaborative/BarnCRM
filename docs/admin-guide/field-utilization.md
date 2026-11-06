# Field Use

Field Use was called Field Utilization until v1.0; its records keep that name (**Field
Utilization Snapshot**).

## What It Does

Field Use shows, for the kind of record you choose (people, households and
organizations, gifts, or any other kind of record you can see), how many records have each field
filled in. Where a kind of record has record types, such as households and organizations, each
record type is counted on its own, because a field that matters for organizations may be
meaningless for households.

The count runs when you ask for it, in the **Field Use** section of the **Org
Optimizer** tab. Choose **Save Snapshot** to keep a result; the next time you count, the page shows the saved result next to the
new one, so you can see the trend: a field that went from 40% to 70% filled since the last saved
count is being adopted; a field that sits at 0% count after count is a field nobody uses, and a
candidate to retire or hide. A field that is nearly always filled is a candidate to make
required.

It only counts. It never changes a record, a field or a page.

## How to Turn It On

You need the BarnCRM Admin role (the BarnCRM Admin permission set, which carries the Manage
BarnCRM Settings permission). It shows you the **Field Use** section of the **Org
Optimizer** tab in the BarnCRM app. Nobody else sees the section. There is nothing to schedule
and no setting to change.

## A Five-Minute Walkthrough

Start from the sample data (see [Sample data](sample-data.md)).

1. In the BarnCRM app, open the **Org Optimizer** tab and choose **Field Use**.
2. In **Kind of record**, choose **Account**. The page counts the records, then fills the table
   as it counts the fields, 40 at a time, with a progress bar. When it is done it reads, for
   example, "Counted 56 of 56 fields."
3. The table lists every field it counted, once per record type: Household and Organization.
   Each row shows the field's label, whether it is **Required**, its **Default Value**, how many
   records have it filled in, how many records there are, the percentage, and **At Default**:
   the share of records still holding the default. Sort by **Filled** to put the least used
   fields first. Turn on
   **Show technical names** above the table to add the **API Name** column (it starts off).
4. Choose **Save Snapshot**. Small text under the button says "Keeps this count so
   your next count shows what changed." The page reads, for example, "Saved 112 counts."
5. Open any sample organization and fill in its **Website**. Go back to the section and choose
   **Count Again**. The Website row for Organization now shows a higher percentage, **Saved**
   shows the percentage you saved in step 4, and **Change Since Saved Count** shows how many
   percentage points it moved since then.
6. For a field almost nobody fills in, open the action menu at the end of its row and choose
   **Where Used** to see which BarnCRM setup still uses it before you retire it
   ([Where Used and Retire a Field](where-used.md)).

## What Is Counted

- **Records.** The count sees the records you can see. An administrator who can see every
  record gets the whole organization.
- **Kinds of records.** The list offers every kind of record you can open in Find. Settings and
  system records are left out.
- **Fields.** Every field a person can fill in, including required fields and checkboxes. Left
  out: formula and roll-up fields, automatic numbers, fields only Salesforce sets (such as Last
  Viewed), and fields you cannot read or edit. An address is counted as its parts (street, city
  and so on). A checkbox always has a value, so it is always 100% filled; its **At Default**
  column is the one to read.
- **Required.** Checked when the field's setup makes it required on every new record: it cannot
  be empty and has no default. It comes from the field's setup only: a field that a page layout
  or a validation rule makes required is not marked. A checkbox is never marked required.
- **Default Value.** The value a new record gets when nobody fills the field in: a plain value
  (such as `Open` or `25`), the picklist's default value, or **True** or **False** for a
  checkbox. A default worked out by a formula (such as today's date plus 7 days) shows as
  **Formula**. Blank when the field has no default.
- **At Default.** The share of the counted records whose field still holds its default value.
  A high share can mean people never change it, or that the default is right; a picklist at
  100% default may not need to be on the page at all. It is counted with one extra count per
  field, so it follows the same record types, the same records you can see and the same size
  limit as **Filled**. It is blank when the default is a formula, when there is no default, for
  a percent field, for a field that cannot be filtered (such as long text), and for a
  **Sampled** row. For a checkbox whose default is False, At Default is the share left
  unchecked. At Default is not kept in saved snapshots.
- **Long text fields** (such as Description) cannot be counted across a whole kind of record, so
  they are counted on the 200 most recently changed records instead. Their rows are marked
  **Sampled**, and the percentage is for those 200 records, not for all of them.
- **Fields that could not be counted.** If a field cannot be counted at all, the page names it
  under the table. The other fields are still counted.
- **Very large kinds of records.** A kind of record with more than 1,000,000 records is not
  counted, so the page never runs for minutes. The page says so.
- **How long it takes.** A few seconds for 40 fields on a small kind of record. Above 100,000
  records the page counts 10 fields at a time so each step stays short. Stay on the page until
  the progress bar finishes; leaving it stops the count.

## Saved Counts, Reports and Dashboards

Every saved count is stored as **Field Utilization Snapshot** records, one per field and record
type, so you can build reports and dashboards on them in the report builder like any other
records. A useful first report: Field Utilization Snapshots grouped by **Field Label**, with
**Taken At** as columns, showing **Fill Rate**.

Saved counts are kept until you delete them; nothing deletes them on a schedule. Account and
Contact with three record types between them come to about 300 rows per save, roughly 600 KB of
data storage. To clear old saves one at a time, use **Delete** in Snapshot History (below). To
clear many at once, use [Bulk delete](bulk-delete.md): in Find, choose Field Utilization
Snapshots, filter **Taken At** before the date you want to keep from, and delete the results.
Any other way you delete records works too.

## Snapshot History

At the bottom of the section, below the table, **Snapshot History** lists the saved counts for
the kind of record you chose, newest first. Each row is one save, and shows:

- **Taken**: the date and time the count was saved.
- **Saved By**: who saved it.
- **Fields**: how many different fields it holds.
- **Average Fill Rate**: the filled values as a percentage of the records counted, across every
  field and record type in that save.

The list shows the newest 50 saves, and says so when older ones exist. Older saves are still in
the Field Utilization Snapshot records, so reports see them.

Each row has three actions:

- **Compare with this one.** Until you choose, the page compares with the latest save. Choose
  this on an older save and the **Saved** and **Change Since Saved Count** columns, and the line above the
  table, follow that save instead. It is a choice for what you are looking at: counting again,
  saving, deleting a save or choosing another kind of record puts the comparison back on the
  latest save.
- **View.** Opens that save's rows under the list, with **Kind of Record**, **Record Type**,
  **Field** and **Fill Rate**. Choose **Close** to hide them.
- **Delete.** Deletes every row of that save, after you confirm. It cannot be undone from the
  page. **Delete** appears only for people who can delete Field Utilization Snapshot records (the
  BarnCRM Admin permission set does). The list refreshes, and if you deleted the latest save, the
  next older one becomes the one the page compares with.

If the kind of record has no saved counts, the list reads "No snapshots have been saved for this
kind of record yet."

## Picklist Value Usage

Under the Field Use table, **Picklist Value Usage** answers a different question: which
values of a picklist are still used? Choose a kind of record, then click **Show Picklist Value
Usage**. Nothing is read until you click.

For every single-select picklist field of the kind of record that you can read, the table lists
each value with:

- **Status.** **Active** (a value on the picklist that records hold), **Inactive, Still in Data**
  (a value that is no longer on the picklist, or was retired, but records still hold it),
  **Never Used** (an active value that no record holds), or **No Value** (one row for the records
  where the field is empty).
- **Records.** How many records hold the value.
- **Last Used.** The newest **Last Modified Date** among the records that hold the value. It is
  the latest time a record holding the value was changed, not the time the value was chosen:
  any later edit to such a record moves it. On a kind of record with no Last Modified Date,
  Created Date is used. A value with no records has no date.

Click a column heading to sort. Sort by **Status** to bring the retired values still in your
data together, or by **Records** to see the least used values first. To replace a retired value
in bulk, use [Super Transformer](super-transform.md) or
[Super Transformer runs and undo](bulk-update.md).

How it counts: one query per picklist field, run as you (so you see the counts for the records
you can see), 20 fields at a time with a progress bar. Only the 500 most used values found in
the data are shown for a field; if a field has more, the page names it under the table. A kind
of record with more than 1,000,000 records is not read, as for the field counts above.

On a large kind of record (tens of thousands of records or more), the records per value come
first and **Last Used** follows: the page reads the records in chunks of up to 20,000, one call
at a time, and shows **Finding Last Used dates: read N of N records.** with a **Cancel** button.
Last Used stays blank until a field's dates are complete. If you click **Cancel**, or a chunk
fails (the Error Log has the detail), the page keeps what it read, names the fields still
without dates, and offers **Continue**, which carries on from the last chunk that finished. A field
with more than 1,000 different values in one chunk gets no Last Used dates.

Not covered: multi-select picklists, and picklist values you cannot read because the field is
hidden from you. Nothing is saved; the table is gone when you leave the page.

## Common Mistakes

**Reading a sampled row as the whole picture.** A long text field marked **Sampled** shows the
200 most recently changed records. Records nobody has touched in years are not in it, so a
sampled field can look more used than it is.

**Counting as someone who cannot see everything.** The count sees only what you can see. If
percentages look low or a record type is missing, have an administrator who can see all records
count and save instead.

**Expecting a trend without saving.** A count you do not save is gone when you leave the page.
Choose **Save Snapshot** after any count you want to compare against later.

**Expecting a field to be counted that is not in the table.** A field is left out when it is a
formula, an automatic number, set only by Salesforce, or hidden from you (see **What Is Counted**). Give
yourself read and edit access to the field and count again.

## Fields Behind This Page, for Report Builders

| Field | API name | What it holds |
|---|---|---|
| Object Name | `Object_Name__c` | The kind of record that was counted. |
| Field Name | `Field_Name__c` | The field that was counted. |
| Field Label | `Field_Label__c` | The field's label when it was counted. |
| Record Type | `Record_Type__c` | The record type the row is for; blank when the kind of record has none, or for records that have none. |
| Filled Count | `Filled_Count__c` | How many records have the field filled in. |
| Record Count | `Record_Count__c` | How many records were looked at. |
| Fill Rate | `Fill_Rate__c` | Filled Count as a percentage of Record Count. |
| Sampled | `Sampled__c` | Checked when the row counts a sample of recent records rather than all of them. |
| Taken At | `Taken_At__c` | When the counts were saved. Every row from one save has the same time. |
