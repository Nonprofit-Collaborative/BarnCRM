# Bulk update

## 1. What it does

**Bulk update** changes up to five fields on every record a [Find](find.md) query returns, in
one go. For each field you choose one of:

- **Set to a value**: every record gets the same value, for example Mailing City "Portland".
- **Clear**: the field is emptied.
- **Copy from another field**: each record gets the value of another field on the same record,
  for example Work Email copied into Preferred Email.

Before anything changes, BarnCRM counts the records that match and shows the first five, each
with the value before and the value after. You type that number to confirm. The update then
runs in the background, in chunks of up to 200 records, and the page shows its progress.

Every change is recorded in the import journal, so for as long as an import can be undone (30
days unless your administrator changed it) you can undo a bulk update: each value goes back to
what it was, except where somebody has changed it since.

A bulk update acts with your own access. It changes only records you may edit, and only fields
you may edit. Your organization's validation rules, duplicate rules and automation run on every
record, as they do on any save. A record that is refused is listed with the reason; the rest
still save.

Values you change by editing Find's results table ([Find](find.md), section 7.6) are saved
the same way, and each save is listed with the bulk updates on the **Bulk Update** tab, its
run log starting "Edited in Find", with the same undo.

## 2. How to turn it on

1. Bulk update needs two permissions: **Bulk Update Records**, and **Find and Export Records**,
   because every bulk update starts from a Find query. The **BarnCRM Admin** role has both. To
   let a staff member bulk update without making them an admin, assign them the **BarnCRM Bulk
   Update** and **BarnCRM Find and Export** permission sets (Setup, Users, choose the person,
   Permission Set Assignments). Neither grants access to any record or field.
2. Optional: open **BarnCRM Settings**, choose **Import**, and set **Bulk update run limit**
   (default 48,000). A bulk update that matches more records than this is refused before it
   starts. It cannot be set higher than 48,000, because one Salesforce request can count just
   under 50,000 records, and the count before you confirm has to be exact.
3. **Days an import can be undone**, on the same page, is also how long a bulk update can be
   undone. Each bulk update keeps the deadline it started with.

## 3. A five-minute walkthrough (as Maria)

Maria's office moved its Springfield mailings to a new volunteer, and every household in
Springfield should now say "Springfield" with a capital S; some were typed in lower case.

1. Open **Find**. Choose **Account**, add the column **Billing City**, and add the condition
   **Billing City**, **equals**, `springfield`. Press **Run**.
2. Press **Bulk update**. The bulk update panel opens below the results. It uses the query as
   it is now; changing the query closes the panel.
3. Under **Changes**, choose the field **Billing City**, **Set to a value**, and type
   `Springfield`. To change a second field, press **Add a change** (up to five).
4. Press **Preview**. BarnCRM says how many records match, for example 37, and shows the first
   five with the value before and after.
5. Type `37` into **Type the number of records to confirm**, then press **Update 37 records**.
6. The progress bar shows the chunks done. When it finishes, the panel says how many records
   were updated, how many already held the new value and how many failed, with the reason for
   each failure. The job's run log, on the Import record, also says how many no longer matched
   the query.
7. To undo it, open the **Bulk Update** tab. Find the job under **Recent bulk updates**, press
   **Undo**, check the number, and confirm.

## 4. What can and cannot be changed

- **Every matching record, not only the rows shown.** Find's **Rows to show** and sort order
  only shape the results table. A bulk update covers every record the object and conditions
  match, and the preview count says how many that is.
- **Lookup values** are chosen by searching for the record when the lookup points at one kind
  of record. When it can point at several (Owner, for example), paste the record Id.
- **Fields you can choose** are the fields of the query's object that you may edit. Fields on a
  related record are not offered: a bulk update changes the records the query returns and
  nothing else.
- **Fields BarnCRM keeps itself** are not offered: every rollup total (any field a Rollup
  Definition writes), household greetings, member counts, last calculated times, the import
  tag and the sample data key. Formula, auto-number and system fields cannot be edited by
  anyone, so they are not offered either. Change what they are calculated from instead.
- **Objects BarnCRM keeps itself** cannot be bulk updated: imports and their journal, import
  templates, the error log, settings and setting changes, automation settings, rollup
  definitions, duplicate dismissals and saved queries. Salesforce's own setup objects (users,
  profiles, permission sets, record types and the like) cannot either; use Setup.
- **Copy from another field** offers only fields whose values fit: a field of the same type;
  any text, email, phone, URL or picklist into a text field; any number into a number field;
  and a lookup into a lookup that can point at the same kind of record.
- **Household names.** A household's name is kept by household naming. To give a household a
  name of its own, bulk update **Custom Name** rather than **Account Name**.

## 5. Common mistakes

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

## 6. What bulk update does not do (yet)

Formulas ("set Preferred Name to First Name plus Last Name") and find and replace within a
value are planned for a later release (C-37), and so is bulk delete, with its own permission.

## Field reference

| Where | Field | What it holds |
|---|---|---|
| Import (data job) | Operation | Import for a file import, Update for a bulk update. |
| Import (data job) | Bulk Update Definition | The query, the changes and the confirmed count a bulk update ran with. Written only by bulk update. |
| Import (data job) | Row Count | How many records matched when the bulk update started. |
| Import (data job) | Rows Updated | How many records the bulk update saved. |
| Import (data job) | Rows Matched | How many records already held the new values and were not saved. |
| Import (data job) | Rows Rejected | How many records the platform refused, each with its reason in the journal. |
| BarnCRM Settings, Import | Bulk update run limit | The most records one bulk update may change. Default 48,000, at most 48,000. |
