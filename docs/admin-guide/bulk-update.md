# Bulk Update

## 1. What It Does

**Bulk Update** changes up to five fields on every record a [Find](find.md) query returns, in
one go. Most bulk changes start in [Super Transform](super-transform.md): the **Update Many
Records** tile on the Data Manager tab opens it, and it runs this same bulk update without a
Find query. This page covers starting from Find instead, which suits a saved query: run it,
then choose **Change Records**, **Bulk Update**. The **Open Find** button under **Data Jobs**
on the Super Transform page (formerly **Bulk Update**) opens Find with a note. For each field
you choose one of:

- **Set to a value**: every record gets the same value, for example Mailing City "Portland".
- **Clear**: the field is emptied.
- **Copy from another field**: each record gets the value of another field on the same record,
  for example Work Email copied into Preferred Email.
- **Change with steps**: each record's own value is changed by a short list of steps, the same
  steps an import uses to tidy a column: find and replace, remove extra spaces, capitals, a
  value when empty, adding other fields of the same record, and reading a date (section 6).

Before anything changes, BarnCRM counts the records that match and shows the first five, each
with the value before and the value after. You type that number to confirm. The update then
runs in the background, in chunks of up to 200 records (the **Bulk chunk size** setting), and
the page shows its progress.

Every change is recorded in the import journal, so for as long as an import can be undone (30
days unless your administrator changed it) you can undo a bulk update: each value goes back to
what it was, except where somebody has changed it since.

A bulk update acts with your own access. It changes only records you may edit, and only fields
you may edit. Your organization's validation rules, duplicate rules and automation run on every
record, as they do on any save. A record that is refused is listed with the reason; the rest
still save.

Values you change by editing Find's results table ([Find](find.md), section 7.6) are saved
the same way, and each save is listed with the bulk updates under **Data Jobs** on the **Data Manager** tab, its
run log starting "Edited in Find", with the same undo.

## 2. How to Turn It On

1. Bulk update needs two permissions: **Bulk Update Records**, and **Find and Export Records**,
   because every bulk update selects its records with a Find query, whether built in Find or
   in Super Transform. The **BarnCRM Admin** role has both. To
   let a staff member bulk update without making them an admin, assign them the **BarnCRM Bulk
   Update** and **BarnCRM Find and Export** permission sets (BarnCRM Settings, Access,
   Extra Permissions). Neither grants access to any record or field.
   A person without both sees no bulk updates under **Data Jobs** on the **Data Manager** tab,
   and no error.
2. Optional: open **BarnCRM Settings**, choose **Import**, and set **Bulk update run limit**
   (default 48,000). A bulk update that matches more records than this is refused before it
   starts. It cannot be set higher than 48,000, because one Salesforce request can count just
   under 50,000 records, and the count before you confirm has to be exact.
3. **Days an import can be undone**, on the same page, is also how long a bulk update can be
   undone. Each bulk update keeps the deadline it started with.

## 3. A Five-Minute Walkthrough (as Maria)

Maria's office moved its Springfield mailings to a new volunteer, and every household in
Springfield should now say "Springfield" with a capital S; some were typed in lower case.

1. Open **Find**. Choose **Account**, add the column **Billing City**, and add the condition
   **Billing City**, **equals**, `springfield`. Press **Run**.
2. Open the **Change Records** menu and choose **Bulk Update**. The bulk update panel opens
   right under the buttons, with its steps along the top: **Choose Changes**, **Confirm**,
   **Run**. It uses the query as it is now; changing the query closes the panel.
3. Under **Changes**, choose the field **Billing City**, **Set to a value**, and type
   `Springfield`. To change a second field, press **Add a Change** (up to five).
4. Press **Preview**. BarnCRM says how many records match, for example 37, and shows the first
   five with the value before and after.
5. Type `37` into **Type the number of records to confirm**, then press **Update 37 records**.
6. The progress bar shows the chunks done. It checks every 3 seconds for the first minute and
   every 10 seconds after that, and tries once more if a check fails before it shows an
   error. When it finishes, the panel says how many records
   were updated, how many already held the new value and how many failed, with the reason for
   each failure. The job's run log, on the Data Job record, also says how many no longer matched
   the query.
7. To undo it, open the **Data Manager** tab. Find the job under **Data Jobs** (choose **Bulk
   updates** in **Show** to list only those), press **Undo**, type the number, and confirm.
   The list shows your own bulk updates. Someone who manages BarnCRM Settings can tick **Show
   everyone's jobs** to see and undo anyone's.

## 4. What Can and Cannot Be Changed

- **Every matching record, not only the rows shown.** Find's **Rows to show** and sort order
  only shape the results table. A bulk update covers every record the object and conditions
  match, and the preview count says how many that is.
- **Lookup values** are chosen by searching for the record when the lookup points at one kind
  of record. When it can point at several (Owner, for example), paste the record Id.
- **Fields you can choose** are the fields of the query's object that you may edit. Fields on a
  related record are not offered: a bulk update changes the records the query returns and
  nothing else.
- **Fields BarnCRM keeps itself** are not offered: every rollup total (any field a Rollup
  Definition writes), household greetings, custom names, roles and member counts, primary
  contacts and primary affiliations, last calculated times, the import tag and the sample data
  marks. These are the same fields an import never writes. Formula, auto-number and system fields cannot be edited by
  anyone, so they are not offered either. Change what they are calculated from instead.
- **Objects BarnCRM keeps itself** cannot be bulk updated: imports and their journal, import
  templates, the error log, settings and setting changes, automation settings, rollup
  definitions, duplicate dismissals and saved queries. Salesforce's own setup objects (users,
  profiles, permission sets, record types and the like) cannot either; use Setup.
- **Copy from another field** offers only fields whose values fit: a field of the same type;
  any text, email, phone, URL or picklist into a text field; any number into a number field;
  and a lookup into a lookup that can point at the same kind of record.
- **Household names.** A household's name is kept by household naming, so a bulk update of
  **Account Name** leaves every household as it is and lists each one with the reason; the
  organizations in the same query are changed. To give one household a name of its own, open
  the household, check **Custom name** and type the name (see
  [Household naming](household-naming.md)).

## 5. Common Mistakes

- **"More records match now than the 37 you confirmed."** Somebody added or changed records
  between your preview and your confirmation. Nothing was changed. Press **Preview** again and
  confirm the new number.
- **"More than 48,000 records match, the run limit for one bulk update."** Narrow the query, or
  run it in parts (one filter per postal code range, for example).
- **Some records failed.** A record fails when a validation rule, a duplicate rule, a locked
  record (for example a posted gift) or your access refuses the save. Each is listed with the
  reason on the job. Fix those records by hand, or fix the cause and run a new bulk update over
  them.
- **Fewer records were updated than you confirmed.** A record that changed after you confirmed,
  so that it no longer matches the query, is left alone and counted as "no longer matched". A
  record that already held the new value is not saved, so it has nothing to undo.
- **The undo did not put everything back.** A value somebody changed after the bulk update is
  kept, on purpose, because putting back the old value would silently overwrite their
  correction.
- **The job was stopped part way.** A job stopped in Setup, or by Salesforce, saved the records
  of the chunks that ran before it stopped. It shows as **Failed**, and **Undo** asks you to
  confirm the number of values those chunks saved, then puts them back. A job also stops when
  your access to the object or a field is taken away while it runs; the run log says why, and
  the records it had not reached are left as they were. When Salesforce stopped part of the
  job, the run log also says how many of the confirmed records were not reached; run a new
  bulk update over them, in smaller parts if automation on them is heavy, or lower **Bulk
  chunk size** in BarnCRM Settings (Import) so each chunk saves fewer records.
- **"The old and new values of this record are too long to keep for an undo."** A very long
  text value (tens of thousands of characters) cannot be kept for an undo, so that record is
  left as it was rather than changed without one. Change it on the record itself.

## 6. Changing Values with Steps

**Change with steps** changes each record's own value rather than giving every record the same
one. Choose the field, choose **Change with steps**, then **Add a Change** (up to ten). Steps run
in the order listed:

| Step | What it does | Example |
|---|---|---|
| **Remove extra spaces** | Removes spaces at the start and end, and turns several in a row into one. | `  Ana   Ramirez ` becomes `Ana Ramirez` |
| **All capitals** | Writes every letter as a capital. | `ca` becomes `CA` |
| **All lower case** | Writes every letter small. | `ANA@EXAMPLE.ORG` becomes `ana@example.org` |
| **Capitalize each word** | A capital at the start of each word, the rest small. | `springfield` becomes `Springfield` |
| **Find and replace** | Replaces text you type with other text. Tick **Whole value only** to replace only a value that is exactly that text, and **Match capitals** to tell `st.` from `St.`. | `St.` becomes `Street` |
| **Value when empty** | Gives an empty field a value. | empty becomes `Unknown` |
| **Add other fields** | Adds the values of other fields of the same record after this one, with a separator you choose (a space unless you type another). An empty one is left out. | First Name with Last Name becomes `Ana Ramirez` |
| **Read as a date** | Reads a date written month first, day first or year first and writes it the way Salesforce reads it. | day first: `31/12/2025` becomes `2025-12-31` |
| **Map values** | Changes each value listed in a table (up to 100 rows) to the value beside it. A value not in the table is kept, or becomes the value in **Anything else** if you give one. | `M` becomes `Monthly` |
| **If, then** | When the value equals some text, contains it, or is empty, writes the value you give (empty clears the field); **Otherwise** is written when the test fails, or the value is kept. | contains `test`: becomes `Do not mail` |
| **Keep part** | Splits the value at a separator and keeps one part, from the start or the end. | separator `@`, part 2: `ana@example.org` becomes `example.org` |
| **First characters**, **Last characters** | Keeps the first or last number of characters you give. | first 5: `97201-1234` becomes `97201` |
| **Shift a date** | Adds or takes away days or months. Use it on date fields: a date and time field refuses the result, record by record. | minus 30 days: `2025-12-31` becomes `2025-12-01` |
| **Today's date** | Writes today's date, or only into empty fields if you tick **Only when empty**. | empty becomes today |

The steps work on the value as text, and the result is then saved as the field's type: a
number field takes `1,250.00` as 1250 (a whole-number field refuses `12.5` rather than drop the
point), a checkbox takes `true`, `yes` or `1` as ticked and `false`, `no`, `0` or nothing as
unticked (any other word is refused for that record), and a date field takes `2025-12-31`. A
step reads a date as `2025-12-31` and a date and time as `2025-12-31 09:30:00` in your own time
zone, so a step that changes nothing leaves the value as it was. A step never runs code and
never reads another record.

- **The preview shows each record's own result.** The five records in the preview show the
  value before and after the steps, so you can see the change before you confirm.
- **A result the field cannot take is refused for that record only.** A result longer than a
  text field allows, a number field result that is not a number, or a value a restricted
  picklist does not list is not saved; the record is listed with the reason, and the rest still
  save. The preview says so for the records it shows.
- **An empty result clears the field**, as **Clear** would, unless the field is required, in
  which case that record is refused.
- **Text is compared exactly.** A step that only changes capitals (`springfield` to
  `Springfield`) still changes the record, and the undo puts the old capitals back.
- **Change with steps** is offered for text, email, phone, URL, picklist, number, date, date and
  time, and checkbox fields. Lookups are set or copied, not changed with steps.

Deleting the records a query returns is a separate tool with its own permission: see
[Bulk delete](bulk-delete.md).

## Field Reference

| Where | Field | What it holds |
|---|---|---|
| Data Job | Operation | Import for a file import, Update for a bulk update, Delete for a bulk delete. |
| Data Job | Bulk Update Definition | The query, the changes (with any steps) and the confirmed count a bulk update ran with; for a bulk delete, the query and the confirmed count. Written only by bulk update and bulk delete. |
| Data Job | Row Count | How many records matched when the bulk update started. |
| Data Job | Rows Updated | How many records the bulk update saved. |
| Data Job | Rows Matched | How many records already held the new values and were not saved. |
| Data Job | Rows Rejected | How many records the platform refused, each with its reason in the journal. |
| BarnCRM Settings, Import | Bulk update run limit | The most records one bulk update may change. Default 48,000, at most 48,000. |
| BarnCRM Settings, Import | Bulk chunk size | Records each chunk of a bulk update or bulk delete handles. Default and highest 200, lowest 10; a job keeps the size it started with. |
