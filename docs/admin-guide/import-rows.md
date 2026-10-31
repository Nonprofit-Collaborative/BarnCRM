# Super Importer Rows

## 1. What It Does

Every row of every file you import is kept as an **Import Row** for a while
([How long the rows are kept](importing.md#how-long-the-rows-are-kept)), so you can see what
happened to it. Super Importer rows let you:

- **Browse rows** of one import, of every import, or only rejected rows, from the **Import
  Rows** tab and its list views, or from an import's **Data Job** record, which lists its rows.
- **Open a row** to see each column the file gave it, any correction beside it, and why the
  row was rejected.
- **Correct a rejected row on screen**: type the right value next to the file's value. The
  file's own values are never changed, so the row still shows what was uploaded.
- **Retry This Row**, or **Retry All Fixed Rows** of the import, without a spreadsheet. The
  rows are loaded through the same import (same template, matching and values for every row),
  and the import's one **Undo** still removes everything it created, the retried rows included.

Retrying with a fixed file ([Importing](importing.md), section 3, "Fixing the rejected
rows") still works too; use it when many rows need the same fix.

## 2. How to Turn It On

Nothing to switch on: it comes with **Import**, which needs the **Data Manager** feature
(BarnCRM Settings, **General**) and the Manage BarnCRM Settings permission (the BarnCRM Admin
permission set). The **Import Rows** tab shows for the people who see the **Import** tab.

**Delete Import Rows** in **BarnCRM Settings**, **Import**, says how long rows are kept after
an import is complete: **Once Complete**, **After 30 Days** (the default), **After 90 Days** or
**Never**. A rejected row can be corrected and retried only while its row is kept.

## 3. A Five-Minute Walkthrough (as Maria)

Maria imported 200 contacts; 3 were rejected.

1. Open the **Import Rows** tab and choose the **Rejected Import Rows** list view. Each row
   shows its import, row number and status, and the status of its import. To see only one
   import's rows, open the import's **Data Job** record instead (or add a filter on
   **Import Batch** to your own list view).
2. Open row 14. The **Super Importer Row** card shows **Why It Was Rejected** ("A person needs
   a last name.") and a table: **Column**, **File Value** and **Corrected Value**.
3. Type `Nolast` in **Corrected Value** beside **Last Name** and select **Save Corrections**.
   The file's value (empty) stays beside the correction.
4. Select **Retry This Row**. The card says the retry has started. Select **Refresh** after a
   moment: the row now reads **Created**, and the import's counts and run log include it.
5. Correct the other two rows the same way, saving each. Then, on any of them, select **Retry
   All Fixed Rows** to retry every corrected rejected row of the import at once.
6. Changed your mind? **Undo** on the import (Import tab or Data Manager) removes what the
   import and its retries created.

## 4. Common Mistakes

- **The fields are greyed out.** Only a rejected row can be corrected, only by someone with
  the Manage BarnCRM Settings permission who can edit the import's rows (sharing on the Data
  Job decides), only while the import can still be undone, and not while it is running or
  while a retry by file is open. The card says which applies. Anyone who runs imports may
  correct and retry a row, not only the person who committed the import, and the one undo
  covers what each of them loaded.
- **A retried row is rejected again.** It keeps your corrections and shows the new reason; fix
  that and retry again.
- **The row is gone.** With **Once Complete**, rows are deleted the night after the import;
  correct them the same day, or upload a fixed file as a new import.
- **Retry All Fixed Rows retried nothing.** Only rows with a saved correction are retried;
  select **Save Corrections** first.
