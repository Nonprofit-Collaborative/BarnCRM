# Bulk delete

## 1. What it does

**Bulk delete** deletes every record a [Find](find.md) query returns, in one go. It is for
clearing out what should not be there: a test load, a list of contacts a partner sent twice,
last year's event sign-ups.

To delete the records a file lists by their record IDs instead, use **Load one object** with
**Delete by record ID** on the Import tab ([Importing](importing.md), section 9). It needs
**Bulk Delete Records** but not Find, and runs, journals and undoes exactly as below.

Before anything is deleted, BarnCRM counts the records that match and shows the first five by
name, with the kinds of related records Salesforce deletes with them. You type that number to
confirm. The delete then runs in the background, in chunks of up to 200 records (the **Bulk
chunk size** setting in BarnCRM Settings, Import), and the page
shows its progress.

Every deleted record is listed in the import journal, so an undo can bring them back from the
Recycle Bin. The undo works for as long as an import can be undone (30 days unless your
administrator changed it) or 15 days, whichever is shorter, because Salesforce empties a deleted
record from the Recycle Bin after 15 days. A record that is no longer in the Recycle Bin cannot
be brought back, and the undo says how many.

Neither a bulk delete nor a delete by file deletes anything for good: both delete the way a
person does in Salesforce, so every record goes to the Recycle Bin. One Salesforce limit
applies all the same: the Recycle Bin holds as many records as 25 times your org's storage in
MB (an org with 1,000 MB holds 25,000), and when it is full Salesforce empties the oldest records
that have been in it for at least two hours, even before 15 days. A very large delete in a small
org can push older deleted records out; download the records first (step 4 below) when you may
need them later.

A bulk delete acts with your own access. It deletes only records you may delete, and your
organization's automation runs on every record, as it does on any delete. A record that is
refused is listed with the reason; the rest are still deleted.

## 2. How to turn it on

1. Bulk delete needs two permissions: **Bulk Delete Records**, and **Find and Export Records**,
   because every bulk delete starts from a Find query. **Bulk Delete Records is in no role, not
   even BarnCRM Admin**: assign the **BarnCRM Bulk Delete** permission set to the few people
   who should have it (BarnCRM Settings, Access, Extra Permissions), with
   **BarnCRM Find and Export** if they do not have it already. Neither grants access to any
   record. Seeing the list of recent bulk deletes, and undoing one, needs only **Bulk Delete
   Records**, as does deleting by file from the Import tab.
2. Optional: open **BarnCRM Settings**, choose **Import**, and set **Bulk delete run limit**
   (default 10,000). A bulk delete that matches more records than this is refused before it
   starts. It cannot be set higher than 48,000, because one Salesforce request can count just
   under 50,000 records, and the count before you confirm has to be exact.
3. **Days an import can be undone**, on the same page, is also how long a bulk delete can be
   undone, up to 15 days.

## 3. A five-minute walkthrough (as Maria)

A volunteer loaded the spring gala sign-up sheet twice, and Maria wants the second copy gone.
Every record of the second copy has the description `Gala sign-up, copy 2`.

1. Open **Find**. Choose **Contact**, add the column **Name**, and add the condition
   **Description**, **equals**, `Gala sign-up, copy 2`. Press **Run**, and check the results.
2. Press **Bulk delete**. The bulk delete panel opens below the results. It uses the query as
   it is now; changing the query closes the panel.
3. Press **Preview**. BarnCRM says how many records match, for example 112, shows the first five
   by name, and lists what is deleted with each one (for a contact, for example, its
   household memberships if your org deletes them with the contact).
4. Optional, and recommended: press **Download these records first**. BarnCRM reads all 112
   records, with every field you can see, and saves them as a CSV file (the same format as
   Find's export). Nothing is deleted. Keep the file: it is your copy if a record is ever needed
   after the Recycle Bin has emptied. Related records deleted with them are not in it.
5. Type `112` into **Type the number of records to confirm**, then press **Delete 112
   records**.
6. The progress bar shows the chunks done. It checks every 3 seconds for the first minute and
   every 10 seconds after that, and tries once more if a check fails before it shows an
   error. When it finishes, the panel says how many records
   matched, how many were deleted and how many were refused, with the reason for each
   refusal. The count of records that no longer matched the query (changed or removed by
   someone else while the job ran) is in the job's run log and in its notification, not in
   the panel.
7. To undo it, find the job under **Data Jobs** on the **Data Manager** tab, press
   **Undo**, type the number, and confirm. The records come back from the Recycle Bin. The list
   shows your own bulk deletes. Someone who manages BarnCRM Settings can tick **Show everyone's
   jobs** to see and undo anyone's.

## 4. What can and cannot be deleted

- **Every matching record, not only the rows shown.** Find's **Rows to show** and sort order
  only shape the results table. A bulk delete covers every record the object and conditions
  match, and the preview count says how many that is.
- **Related records can go too.** Salesforce deletes some related records with their parent:
  the detail records of a master-detail relationship (for example, every line of a record that
  owns its lines), and a few standard ones (deleting an account deletes its contacts). The
  preview lists these kinds of record. The undo brings them back with their parent.
- **Emptied households are kept.** Deleting people never deletes their household, even with
  **Delete empty households** on, so the undo can bring them back into it.
- **Objects BarnCRM keeps itself** cannot be bulk deleted: imports and their journal, import
  templates, the error log, settings and setting changes, automation settings, rollup
  definitions, duplicate dismissals, saved queries, household membership rows (use the
  household page, so the household stays correct), and any object a BarnCRM module protects.
  Salesforce's own setup objects (users, profiles, permission sets, record types and the like)
  cannot either; use Setup.
- **Objects that cannot come back** cannot be bulk deleted either: an object Salesforce does not
  keep in the Recycle Bin could not be undone, so it is refused.
- **Locked records** (for example a posted gift or an issued receipt) are refused by their own
  rules, listed with the reason, and stay.

## 5. Common mistakes

- **"More records match now than the 112 you confirmed."** Somebody added or changed records
  between your preview and your confirmation. Nothing was deleted. Press **Preview** again and
  confirm the new number.
- **"More than 10,000 records match, the run limit for one bulk delete."** Narrow the query, or
  run it in parts. Ask your administrator before raising the limit: a large delete can also
  push older records out of the Recycle Bin, which holds a limited number of records for your
  org's storage.
- **Some records were refused.** A record is refused when your access, a validation rule, a
  locked record or other automation stops the delete. Each is listed with the reason.
- **The undo did not bring everything back.** A record that has been emptied from the Recycle
  Bin (after 15 days, by somebody emptying it, or because the bin was full) is gone for good;
  the undo counts these in the job's run log. A record somebody already restored is left as it
  is.
- **The job was stopped part way.** A job stopped in Setup, or by Salesforce, deleted the
  records of the chunks that ran before it stopped. It shows as **Failed**, and **Undo** still
  offers to bring back exactly those records. A job also stops when your access to the object
  is taken away while it runs; the run log says why, and the records it had not reached are
  left as they were. When Salesforce stopped part of the job, the run log also says how many
  of the confirmed records were not reached.
- **Undo is refused in Import.** A bulk delete is undone from the bulk delete history, which
  brings the records back from the Recycle Bin; the import's own Undo refuses it.

## Field reference

| Where | Field | What it holds |
|---|---|---|
| Data Job | Operation | Delete for a bulk delete. |
| Data Job | Bulk Update Definition | The query and the confirmed count a bulk delete ran with. |
| Data Job | Row Count | How many records matched when the bulk delete started. |
| Data Job | Rows Deleted | How many records the bulk delete deleted. |
| Data Job | Rows Rejected | How many records the platform refused, each with its reason in the journal. |
| BarnCRM Settings, Import | Bulk delete run limit | The most records one bulk delete may delete. Default 10,000, at most 48,000. |
| BarnCRM Settings, Import | Bulk chunk size | Records each chunk of a bulk update or bulk delete handles. Default and highest 200, lowest 10. |
