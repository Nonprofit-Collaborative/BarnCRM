# Field utilization

## What it does

Field utilization shows, for each kind of record you choose (people, households and
organizations, or any custom kind of record), how many records have each field filled in.
Where a kind of record has record types, such as households and organizations, each record type
is counted on its own, because a field that matters for organizations may be meaningless for
households.

Each count is saved, so you can see the trend: a field that went from 40% to 70% filled since
the last count is being adopted; a field that sits at 0% month after month is a field nobody
uses, and a candidate to retire or hide. A field that is nearly always filled is a candidate to
make required.

It only counts. It never changes a record, a field or a page.

## How to turn it on

You need the BarnCRM Admin role (the Manage BarnCRM Settings permission). Nobody else sees
this page.

1. Open **BarnCRM Settings** and choose **Health**. **Field utilization** is below Health
   Check.
2. Under **What to count**, move the kinds of records you want counted into **Counted**, for
   example Account and Contact, and choose **Save**. Nothing is counted until you have chosen at
   least one.
3. Choose **Schedule the weekly count**. The page now reads "The count runs every Sunday at 4:00
   AM." and shows the date of the next count.
4. To see results today rather than on Sunday, choose **Count now**, wait a few minutes, and
   refresh the page.

To stop counting, choose **Stop the weekly count**. The counts already saved stay until they age
out (see below).

Once you have chosen at least one kind of record, Health Check lists the weekly count among the
nightly jobs it expects to be scheduled, and its **Schedule all nightly jobs** fix schedules it.

## A five-minute walkthrough

Start from the sample data (see [Sample data](sample-data.md)).

1. Open **BarnCRM Settings** and choose **Health**. Under **Field utilization** the page reads
   "Field use has not been counted yet."
2. Under **What to count**, move **Account** and **Contact** into **Counted** and choose **Save**.
3. Choose **Count now**. The page reads "The count has started. Refresh this page in a few
   minutes to see the results."
4. Refresh after a minute or two. **Last counted** shows the time, and a sentence such as
   "Counted 112 fields on 2 kinds of records. 0 could not be counted."
5. In **Show results for**, choose **Account**. The table lists every field the count looked at,
   once per record type: Household and Organization. Sort by **Filled** to put the least used
   fields first.
6. Open any sample organization and fill in its **Website**. Choose **Count now** again and
   refresh after a minute. The Website row for Organization now shows a higher percentage, and
   **Change (points)** shows how many percentage points it moved since the previous count.

## What is counted

- **Records.** The count sees the records the person who scheduled it, or who chose **Count
  now**, can see. An administrator who can see every record gets the whole organization.
- **Fields.** Every field a person can fill in. Left out: formula and roll-up fields, automatic
  numbers, checkboxes (a checkbox always has a value), fields Salesforce requires on every record,
  fields only Salesforce sets (such as Last Viewed), and fields the person running the count
  cannot read or edit. An address is counted as its parts (street, city and so on).
- **Long text fields** (such as Description) cannot be counted across a whole kind of record, so
  they are counted on the 200 most recently changed records instead. Their rows are marked
  **Sampled**, and the percentage is for those 200 records, not for all of them.
- **Very large kinds of records.** A kind of record with more than 1,000,000 records is skipped,
  so one count never runs for hours. The summary names what was skipped.
- **How long counts are kept.** Each count saves one row per field and record type. Rows older
  than 13 months are deleted each time a count finishes, which keeps a year of trend and bounds
  the storage they use. For example, Account and Contact with three record types between them
  come to about 300 rows a week, roughly 600 KB of data storage a week and about 35 MB at the
  most.

## Reports and dashboards

Every count is saved as **Field Utilization Snapshot** records, so you can build reports and
dashboards on them in the report builder like any other records. A useful first report: Field
Utilization Snapshots grouped by **Field Label**, with **Taken At** as columns, showing **Fill
Rate**.

## Common mistakes

**Choosing too many kinds of records.** The choices are saved as one short list. If they do not
fit you will see "Those choices do not fit. Choose fewer kinds of records." Count the ones you
are deciding about now; you can change the list at any time, and the older counts stay.

**Reading a sampled row as the whole picture.** A long text field marked **Sampled** shows the
200 most recently changed records. Records nobody has touched in years are not in it, so a
sampled field can look more used than it is.

**Counting as someone who cannot see everything.** The count sees only what the person who
scheduled it can see. If percentages look low or a record type is missing, have an administrator
who can see all records stop the weekly count and schedule it again.

**Expecting a field to be counted that is not in the table.** A field is left out when it is a
formula, a checkbox, required on every record, or hidden from the person running the count (see
**What is counted**). Give that person read and edit access to the field and count again.

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
| Taken At | `Taken_At__c` | When the count started. Every row from one count has the same time. |
