# Changing Many Records at Once

**Super Transform** changes the same fields on many records in one go, for example every
contact in one city, without a spreadsheet. You need the bulk update permissions; if the tab
says Super Transform is not turned on for you, ask your BarnCRM administrator (setup detail:
[Super Transform](../admin-guide/super-transform.md)).

## Making a Change

Open the **Super Transform** tab and work down the five steps.

1. **Object**: type part of the name in **Search Objects**, then choose it in **Object**.
2. **Which Records**: add conditions, for example **Mailing City** **equals** `Springfield`.
   **Matching Records** shows how many records match and updates as you type. A yellow
   warning means there is no condition, so every record would change; a red **Over the
   Limit** badge means too many records match for one run, so narrow the conditions.
3. **What to Change**: choose a **Field** and an **Action**:
   - **Set To**: type or pick the new value. Picklists show a list, dates a calendar,
     checkboxes True or False, and lookups a search.
   - **Clear**: empty the field.
   - **Copy From Another Field**: take the value of another field on the same record.
   - **Change With Steps**: tidy each record's own value, for example find and replace.
   - **Fix Name Capitals**: a ready-made set of steps that removes extra spaces and capitalizes
     each word, so `ana  GARCIA` becomes `Ana Garcia`.
   - **Format Phone Number** (on phone and short text fields): writes each number as
     `(555) 123-4567`, dropping a leading `1` and keeping an extension as ` x12`. A value that
     does not fit, such as a seven-digit number, is left as it is.

   Press **Add a Field** to change more than one field (up to five).
4. **Preview**: press **Preview**. The table shows up to 25 matching records with each field's
   old value, an arrow and the new value. Shaded cells will change; the rest already hold
   the new value. A red message in a cell means that record cannot take the value and will be
   left as it is.
5. **Run**: press **Run Super Transform**, check the object, number and fields in the
   confirmation, type the number if asked, and press **Run**. The bar shows the progress, and
   the result says how many records were updated, already held the values, or failed.

## Saving a Change to Use Again

The **Saved Step Lists** card at the top keeps what you have set up. Type a **List Name** and
press **Save as New List**. Later, choose it in **Saved List** and press **Load List**: the
object, conditions and changes fill in again and nothing runs until you press **Preview** and
**Run Super Transform**. **Rename List** and **Delete List** work on the list you chose. Lists
are shared with everyone who uses Super Transform, and a saved list changes no records.

## Undoing a Change

Every run is listed under **Data Jobs**, below the steps. Press **Undo** on it and confirm
the number. A value someone changed since your run is kept.
