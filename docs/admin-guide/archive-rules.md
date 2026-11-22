# Archive Rules

## 1. What It Does

An **archive rule** is a saved [Find](find.md) query that moves the records it finds out of
their object, now or on a schedule. For example: "every closed lost opportunity whose Close
Date is more than 1825 days ago goes to the big object, every Sunday night".

Each rule sends its records to one **destination**:

- **Files (CSV):** the records are saved as a CSV file in your **Files**, then deleted, as
  [Archive by Query](archive-by-query.md) does. The Recycle Bin is left as it is.
- **Big Object:** each record, with every field you can read and the related records Salesforce
  would delete with it, is copied into BarnCRM's **Archived Record** big object, then deleted.
  Big object rows do not use your data storage.
- **Off Platform:** a store outside Salesforce. It shows as not set up until your org has one;
  a rule cannot use it until then.

A record is only deleted after its copy is saved and read back. A record changed after the run
started is left alone and named in the run's log.

## 2. How to Turn It On

There is nothing to install. You need three permissions, all in **BarnCRM Admin**:

- **Manage BarnCRM Settings**;
- **Find and Export Records**, to save the query;
- **Bulk Delete Records**, because a rule deletes records.

The **Big Object** destination also needs the **BarnCRM Admin** permission set itself, which
grants the Archived Record object. People without it cannot see archived records anywhere.

Scheduled rules run in the nightly run's **Archive Rules** step (BarnCRM Settings, General,
Nightly Jobs), at 3:00 in the time zone of the person who scheduled the nightly jobs, and as that
person. The step ships on and does nothing while no rule has a schedule. Turn the step off there
to pause every rule at once.

## 3. A Five-Minute Walkthrough (as Maria)

Maria wants closed lost opportunities older than five years out of the way every week.

1. Open **Find**, choose **Opportunity**, and add two conditions: **Stage** equals **Closed
   Lost**, and **Close Date** **is more than N days ago** with `1825`. Press **Save** and name
   it `Old closed lost`.
2. Open **Data Manager** and select **Archive Rules**.
3. Under **Add a Rule**, choose `Old closed lost` and press **Add**.
4. Set **Where Records Go** to **Big Object**, **How Often** to **Weekly**, and **Day** to
   **Sunday**. Leave **Active** ticked.
5. Turning a schedule on shows how many records the rule matches now and asks you to type that
   number, as a bulk delete does. Type it and press **Save**.
6. To run it now instead of waiting, press **Preview and Run**. The preview names five of the
   records and any related records Salesforce deletes with them. Type the count and press **Run
   Now**. The run appears under **Recent Runs** and updates until it ends.

## 4. Limits

- **Run limit.** Each run moves at most the **Bulk delete run limit** (BarnCRM Settings, Import;
  default 10,000). A scheduled rule with more matching records moves that many each time it runs.
- **One million archived records.** Salesforce includes one million big object rows in every org.
  The panel shows how many are used. From 900,000 it warns; a run that would pass 1,000,000 stops
  and says so. To make room, move records back or delete them from the archive. BarnCRM never
  goes past the included amount.
- **Record size.** A record whose fields and related records add up to more than 131,072
  characters is not archived; the run log names it and it stays where it is.
- **Related records.** The records Salesforce deletes with a record (the kinds the preview lists)
  are saved inside it, one level deep. Their own related records are deleted by Salesforce and go
  to the Recycle Bin. Records that only look up to an archived record keep their record but lose
  that lookup.
- **A missed night is not caught up.** A weekly rule whose night was missed runs on its next day.

## 5. Managing Rules

- **Edit** changes where records go, how often, and **Active**. Untick **Active** to pause a rule
  and keep its schedule.
- **Remove** takes the rule off the saved query. The query, files of past runs and archived
  records are kept.
- A rule is a saved query: rename, share or delete it in Find. Only its owner can edit or remove
  the rule; someone it is shared with can preview and run it.
- Each big object run is a data job with Operation **Archive**. **Recent Runs** shows how many
  records each run moved and left out, and its log says why each one was left out. A Files run
  is an Archive by Query delete job, listed in Data Jobs.

## Field Reference

| Where | Field | What it holds |
|---|---|---|
| Saved query | Query (the `archive` key) | Where records go, how often, the day, and Active. |
| Data Job | Operation | Archive, for a big object run. |
| Data Job | Bulk Update Definition | The rule's saved query, name, object, and when the run started. |
| Data Job | Row Count | The most records the run may move. |
| Data Job | Rows Deleted | Records moved into the archive. |
| Data Job | Rows Rejected | Records left out; the Run Log names them. |
| BarnCRM Settings | Archived Record Count | How many rows the archive holds, kept by BarnCRM. |
| Archived Record | Object, Archived At, Original Id | The row's key. |
| Archived Record | Name, Owner Id, Rule Name | What the viewer lists. |
| Archived Record | Record | The record and its related records as JSON. |
