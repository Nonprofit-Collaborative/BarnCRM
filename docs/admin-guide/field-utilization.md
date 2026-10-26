# Field utilization

## What it does

Field utilization shows, for the kind of record you choose (people, households and
organizations, gifts, or any other kind of record you can see), how many records have each field
filled in. Where a kind of record has record types, such as households and organizations, each
record type is counted on its own, because a field that matters for organizations may be
meaningless for households.

The count runs when you ask for it, in the **Field utilization** section of the **Org
Optimizer** tab. Choose **Save these
counts** to keep a result; the next time you count, the page shows the saved result next to the
new one, so you can see the trend: a field that went from 40% to 70% filled since the last saved
count is being adopted; a field that sits at 0% count after count is a field nobody uses, and a
candidate to retire or hide. A field that is nearly always filled is a candidate to make
required.

It only counts. It never changes a record, a field or a page.

## How to turn it on

You need the BarnCRM Admin role (the BarnCRM Admin permission set, which carries the Manage
BarnCRM Settings permission). It shows you the **Field utilization** section of the **Org
Optimizer** tab in the BarnCRM app. Nobody else sees the section. There is nothing to schedule
and no setting to change.

## A five-minute walkthrough

Start from the sample data (see [Sample data](sample-data.md)).

1. In the BarnCRM app, open the **Org Optimizer** tab and choose **Field utilization**.
2. In **Kind of record**, choose **Account**. The page counts the records, then fills the table
   as it counts the fields, 40 at a time, with a progress bar. When it is done it reads, for
   example, "Counted 56 of 56 fields."
3. The table lists every field it counted, once per record type: Household and Organization.
   Each row shows the field's label and API name, how many records have it filled in, how many
   records there are, and the percentage. Sort by **Filled** to put the least used fields first.
4. Choose **Save these counts**. The page reads, for example, "Saved 112 counts."
5. Open any sample organization and fill in its **Website**. Go back to the section and choose
   **Count again**. The Website row for Organization now shows a higher percentage, **Saved**
   shows the percentage you saved in step 4, and **Change (points)** shows how many percentage
   points it moved since then.

## What is counted

- **Records.** The count sees the records you can see. An administrator who can see every
  record gets the whole organization.
- **Kinds of records.** The list offers every kind of record you can open in Find. Settings and
  system records are left out.
- **Fields.** Every field a person can fill in. Left out: formula and roll-up fields, automatic
  numbers, checkboxes (a checkbox always has a value), fields Salesforce requires on every record,
  fields only Salesforce sets (such as Last Viewed), and fields you cannot read or edit. An
  address is counted as its parts (street, city and so on).
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

## Saved counts, reports and dashboards

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
- **Saved by**: who saved it.
- **Fields**: how many different fields it holds.
- **Average fill rate**: the filled values as a percentage of the records counted, across every
  field and record type in that save.

The list shows the newest 50 saves, and says so when older ones exist. Older saves are still in
the Field Utilization Snapshot records, so reports see them.

Each row has three actions:

- **Compare with this one.** Until you choose, the page compares with the latest save. Choose
  this on an older save and the **Saved** and **Change (points)** columns, and the line above the
  table, follow that save instead. It is a choice for what you are looking at: counting again,
  saving, deleting a save or choosing another kind of record puts the comparison back on the
  latest save.
- **View.** Opens that save's rows under the list, with **Kind of record**, **Record type**,
  **Field** and **Fill rate**. Choose **Close** to hide them.
- **Delete.** Deletes every row of that save, after you confirm. It cannot be undone from the
  page. **Delete** appears only for people who can delete Field Utilization Snapshot records (the
  BarnCRM Admin permission set does). The list refreshes, and if you deleted the latest save, the
  next older one becomes the one the page compares with.

If the kind of record has no saved counts, the list reads "No snapshots have been saved for this
kind of record yet."

## Common mistakes

**Reading a sampled row as the whole picture.** A long text field marked **Sampled** shows the
200 most recently changed records. Records nobody has touched in years are not in it, so a
sampled field can look more used than it is.

**Counting as someone who cannot see everything.** The count sees only what you can see. If
percentages look low or a record type is missing, have an administrator who can see all records
count and save instead.

**Expecting a trend without saving.** A count you do not save is gone when you leave the page.
Choose **Save these counts** after any count you want to compare against later.

**Expecting a field to be counted that is not in the table.** A field is left out when it is a
formula, a checkbox, required on every record, or hidden from you (see **What is counted**). Give
yourself read and edit access to the field and count again.

## Fields behind this page, for report builders

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
