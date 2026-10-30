# Super Transform

## 1. What It Does

**Super Transform** changes many records at once without a file and without building a Find
query first. It is the top of the **Super Transform** tab (the tab that used to be called
**Bulk Update**), and it walks you down one page in five numbered cards:

1. **Object**: search for and choose the kind of record to change, for example Contact. Only
   objects you may edit are offered.
2. **Which Records**: add conditions in plain words, the same condition rows Find uses (for
   example **Mailing City** **equals** `springfield`). The number of matching records
   updates by itself as you type. With no condition, a warning says the change would reach
   every record of that object, and how many that is. Another warning says when more records
   match than one run may change (the **Bulk update run limit**).
3. **What to Change**: one row per field, up to five. For each field choose **Set To** (a
   value typed to the field: a dropdown for a picklist, a date picker for a date, a yes or no
   choice for a checkbox, a search for a lookup), **Clear**, **Copy From Another Field**, or
   **Change With Steps** (the transform steps of [Bulk update](bulk-update.md), section 6).
4. **Preview**: the first 25 matching records, each changed field shown as its old value and
   its new value, with the cells that change highlighted. A line under the table says how many
   of the records shown already hold the new values, and so will not be saved.
5. **Run**: press **Run Super Transform**. A confirmation names the object, the number of
   records and the fields. Over 200 records, you also type the number to confirm. The page
   then shows the progress and the result.

Super Transform is a new front for the same bulk update engine
([Bulk update](bulk-update.md)): the preview is worked out by the code the run uses, the run
is a bulk update job in the background with your own access, every change is journaled, and
each run is listed under **Data Jobs** right below the cards with its **Undo**, for as
long as an import can be undone.

## 2. How to Turn It On

1. Super Transform needs the same two permissions as a bulk update: **Bulk Update Records** and
   **Find and Export Records**. The **BarnCRM Admin** role has both. For anyone else, assign
   the **BarnCRM Bulk Update** and **BarnCRM Find and Export** extra permissions (BarnCRM
   Settings, **Access**, **Extra Permissions**). A person without both sees a short message
   in place of the cards, and no error.
2. The **Data Manager** feature must be on (BarnCRM Settings, **General**), because the tab is
   one of its tools.
3. Optional: **Bulk update run limit** and **Bulk chunk size** (BarnCRM Settings, **Import**)
   apply to Super Transform exactly as to a bulk update. There is no setting of its own.

## 3. A Five-Minute Walkthrough (as Maria)

Maria wants every volunteer in Springfield whose **Title** is empty to read `Volunteer`.

1. Open the **Super Transform** tab (from **Data Manager**, or the App Launcher).
2. Under **1. Object**, type `con` in the search box and choose **Contact**.
3. Under **2. Which Records**, add the condition **Mailing City** **equals** `Springfield`,
   then **Add Condition**, **Title** **is blank**. The count reads, for example, "37 contacts
   match."
4. Under **3. What to Change**, choose **Title**, keep **Set To**, and type `Volunteer`.
5. Under **4. Preview**, press **Preview**. The table lists up to 25 contacts with **Title**
   going from empty to `Volunteer`, highlighted.
6. Under **5. Run**, press **Run Super Transform**. The confirmation says "Change Title on 37
   contacts." Press **Run**.
7. The progress bar fills. When it finishes, the card says how many were updated, how many
   already held the value and how many failed, with each reason. To put it back, press
   **Undo** on the run under **Data Jobs**.

## 4. How It Compares to a Bulk Update from Find

Both make the same job. Start from **Find** when you already have the query open, want to see
more columns, or want to save the query. Start from **Super Transform** when you only want to
change something: there is no column or row limit to set, and the count, warnings and preview
come as you go.

## 5. Common Mistakes

- **"This changes every contact."** No condition is set. Add one, unless you mean every
  record.
- **"More records match than one run may change."** Narrow the conditions, or run it in parts.
  The **Run** card stays disabled until the count is within the limit.
- **The preview shows a reason in place of a new value.** That record cannot take the value
  (for example a step result too long for the field, or a household name, which household
  naming keeps). The run leaves that record as it is and lists it with the reason.
- **Nothing is highlighted.** Every record shown already holds the new values. Check the field
  and value; the run would change only records outside the sample, if any.
- **The count changed between Preview and Run.** The run counts again. If more records match
  than you confirmed, nothing changes and the page says so: preview and run again.
- **Something went wrong and the message says to check the Error Log.** An unexpected error
  was recorded in the **Error Log** tab with the details your administrator needs.

## Field Reference

Super Transform adds no object, field or setting. Its runs are Data Job records with
**Operation** Update, described in [Bulk update](bulk-update.md#field-reference).
