# Imports

Scripts for the Import wizard: mappings, preview, commit, rejected rows, row rules, value changes, Load one object and undo. Setup detail: [Importing](../admin-guide/importing.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. The **Data Manager** feature must be on (BarnCRM Settings, **General**, see [Data Manager](../admin-guide/data-manager.md)). These scripts assume people are stored as contacts.

The Import tab opens from the **Data Manager** tab: on the **Import a file** card, select **Open**. Save the test files below as UTF-8 CSV files with exactly these headings (the shipped **Generic contact list** mapping recognizes them). For a migration-style file, the samples in [`docs/admin-guide/samples`](../admin-guide/samples) load through the Giving module's mappings and are tested with Giving.

`import-test-1.csv` (5 rows: 3 new people, 1 existing sample person, 1 row with no last name):

```
First Name,Last Name,Email,Phone,Street,City,State,Postal Code
Testa,Rivera,testa.rivera@example.org,555-0101,1 Test St,Springfield,IL,62701
Ben,Okoro,ben.okoro@example.org,555-0102,2 Test St,Springfield,IL,62701
Cara,Lind,cara.lind@example.org,555-0103,3 Test St,Springfield,IL,62701
Harper,Garcia,harper.garcia1@example.org,,,,,
Dee,,dee.nolast@example.org,555-0105,5 Test St,Springfield,IL,62701
```

`import-test-2.csv` (for row rules and value changes):

```
First Name,Last Name,Email,Status
Ana,RAMIREZ-TEST,ANA.RT@EXAMPLE.ORG,Active
Bo,Tester,bo.tester@example.org,Cancelled
Cy,Dupe,cy.dupe@example.org,Active
Cy,Dupe,cy.dupe@example.org,Active
```

## T-IMP-01: Preview and import a contact list

**Purpose:** confirm the main path: choose a mapping, upload, check columns, preview, import and read the results.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)); `import-test-1.csv`.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Data Manager** tab. On the **Import a file** card, select **Open**. | The **Import** tab opens on the card **Import a spreadsheet**, step heading **Choose what kind of file this is**. A **Recent imports** list shows below the wizard. |
| 2 | In **Choose what kind of file this is**, choose **Generic contact list**. | Its description appears under the picker ("A list of people with their contact details..."). **Next** is enabled. |
| 3 | Select **Next**. | Heading **Upload the file**, with an **Upload file** control. |
| 4 | Upload `import-test-1.csv`. | Heading **Check the columns**. **Columns are separated by** shows **Commas**. The table lists all 8 columns with **Column in your file**, **What it means** and **First values**; First Name, Last Name and Email are mapped to person fields (for example "Person: first name"). |
| 5 | Select **Next**. | Heading **Choose how rows are matched**. **Match a row to someone you already have by** shows **Email exact**, with its help text ("Matches only when the email in your file is exactly the email on the record..."). **When more than one record matches a row** shows **Reject the row**. |
| 6 | Select **Preview**. | Heading **Preview**. Counts: **Would create** 3, **Would update** 0, **Would match and change nothing** 1, **Would be rejected** 1. **Rows that were rejected** lists row 5 (Dee) with a reason naming the missing last name ("Required value missing: last name..."). |
| 7 | Search the org for "Testa Rivera". | No record found: the preview wrote nothing. |
| 8 | Back on the Import tab, select **Import these rows**. | "Working through the file. This page updates as it goes." shows, then heading **Results** with **Created** 3, **Updated** 0, **Matched, nothing changed** 1, **Rejected** 1, and the run log under **What happened**. |
| 9 | Open the new contact Testa Rivera from global search, then open their household. | The household exists and its **Created By Import Batch** field links to this import. |
| 10 | Open Harper Garcia. | Unchanged: the matched row created nothing and cleared nothing (empty cells never clear a person's fields). |
| 11 | Back on the Import tab, select **Download results**. | A CSV downloads with one line per file row and the columns **Row**, **Outcome**, **Reason**, **Person ID** (and the other ID columns) beside the file's own columns. Rows 1 to 3 read Created, row 4 Matched, row 5 Rejected with its reason. |

**Cleanup:** keep the import for T-IMP-02 and T-IMP-03; T-IMP-03 undoes it.

## T-IMP-02: Download rejected rows and retry the fixed rows

**Purpose:** confirm a rejected row can be fixed and loaded into the same import.
**Prerequisites:** admin; the finished import from T-IMP-01, still on its **Results** step (or reopen it from the same browser session).

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Results** step, select **Download rejected rows**. | A CSV downloads with one data row (Dee), with the file's columns plus Row and Reason. |
| 2 | In the downloaded file, delete the **Email** column, save it as `retry-bad.csv`. Under **Retry fixed rows**, upload it as **File of fixed rows**. | Refused with "The fixed rows file is missing these columns of the original file: Email". Nothing is previewed. |
| 3 | Open the downloaded file again, type `Nolast` into Dee's Last Name cell, save it as `retry-good.csv`, and upload it under **Retry fixed rows**. | A preview of that one row: **Would create** 1, **Would be rejected** 0. |
| 4 | Select **Import these rows**. | Results for the retry: **Created** 1. The import's rejected count is now 0. |
| 5 | Search the org for "Dee Nolast". | The contact exists, in a household of its own. |

**Cleanup:** none; T-IMP-03 undoes both runs together.

## T-IMP-03: Undo an import

**Purpose:** confirm undo removes what an import created, keeps what it only matched, and asks before acting.
**Prerequisites:** admin; the import from T-IMP-01 and T-IMP-02, not yet undone.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab (Data Manager, **Import a file**, **Open**). | **Recent imports** lists the import first, with **Started** and **Can be undone until** (30 days after it ran, unless the setting was changed) and an **Undo** button. |
| 2 | Select **Undo** beside it. | A box headed "Undo" plus the import's name shows counts: **People to remove** 4, **Households to remove** 4, **Organizations to remove** 0, **Changed values to put back** 0, with **Cancel** and **Undo this import**. Nothing has changed yet. |
| 3 | Select **Cancel**. | The box closes. The import is unchanged and **Undo** is still offered. |
| 4 | Select **Undo** again, then **Undo this import**. | "The undo has started. The import shows Undone when it has finished; refresh the page to check." |
| 5 | Wait a minute and select **Refresh**. | The import row reads **Undone**. **Undo** is no longer offered. |
| 6 | Search the org for Testa Rivera, Ben Okoro, Cara Lind and Dee Nolast. | None is found. Their households are gone too (they are in the Recycle Bin). |
| 7 | Open Harper Garcia. | Still there, in **The Garcia Family**: undo never deletes a record the import only matched. |
| 8 | Open the import's **Data Job** record (from the **Data Jobs** list view or report) and read **Run Log**. | A line "Undone by (your name) on (date): 8 records deleted, 0 kept, 0 values put back." |

**Cleanup:** none.

## T-IMP-04: Undo keeps a record somebody edited

**Purpose:** confirm undo does not delete a created record that was edited after the import.
**Prerequisites:** admin; `import-test-1.csv`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Import `import-test-1.csv` with **Generic contact list** as in T-IMP-01, steps 1 to 8. | **Created** 3, **Rejected** 1. |
| 2 | Open the contact Ben Okoro, edit **Title** to `Edited after import`, and save. | Saved. |
| 3 | Open the Import tab. Select **Undo** beside the import, then **Undo this import**. | The undo starts. |
| 4 | Select **Refresh** until the import reads **Undone**. | **Undone**. |
| 5 | Search for Testa Rivera, Cara Lind and Ben Okoro. | Testa Rivera and Cara Lind are gone. Ben Okoro is still there, with his household. |
| 6 | Read the Data Job's **Run Log**. | The undo line counts records kept (more than 0), and the import journal lists Ben Okoro as kept with "Kept: somebody changed this record, or logged an activity on it, after the import." |

**Cleanup:** delete Ben Okoro and his household by hand.

## T-IMP-05: Control totals and a file BarnCRM cannot read

**Purpose:** confirm a control total that does not match blocks the import, and an unreadable file is refused.
**Prerequisites:** admin; `import-test-1.csv`; a plain text file renamed to `broken.xlsx`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab, choose **Generic contact list**, select **Next**, and upload `broken.xlsx`. | "BarnCRM cannot read this Excel file. It may be an older .xls file or protected by a password. Save it as .xlsx or CSV and upload that." No columns step. |
| 2 | Upload `import-test-1.csv` instead and select **Next** on the columns step. | The matching step, with **Control totals (optional)** and **Rows in the file**. |
| 3 | Type `6` in **Rows in the file** and select **Preview**. | The run log says "Control total: the file has 5 rows, but 6 were expected. The import is refused until they agree." **Import these rows** is disabled. |
| 4 | Select **Back** to the matching step, change **Rows in the file** to `5`, and select **Preview**. | The run log says "Control total: the file has 5 rows, as expected." **Import these rows** is enabled. |

**Cleanup:** none (nothing was imported). Select **Import another file** or leave the page.

## T-IMP-06: Try the first rows, then the rest

**Purpose:** confirm a trial import saves only the first rows and the rest join the same import with one undo.
**Prerequisites:** admin; `import-test-1.csv`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Run `import-test-1.csv` through **Generic contact list** to the **Preview** step. | The four preview counts as in T-IMP-01, and a **Try the first rows** section with **Rows to try** (25 by default). |
| 2 | Set **Rows to try** to `2` and select **Import the first rows**. | "The first 2 rows were imported. Check them above, then import the remaining 3 rows into the same import. If they are wrong, undo the import from Recent imports instead." |
| 3 | Search for Testa Rivera and Cara Lind. | Testa Rivera exists (row 1); Cara Lind (row 3) does not yet. |
| 4 | Select **Import the remaining rows**. | Results for the whole file: **Created** 3, **Matched, nothing changed** 1, **Rejected** 1. |
| 5 | Open **Recent imports**. | One import for the file, not two. |
| 6 | Select **Undo**, then **Undo this import**, and **Refresh** until **Undone**. | **People to remove** was 3. Testa Rivera, Ben Okoro and Cara Lind are all gone. |

**Cleanup:** none.

## T-IMP-07: Row rules and value changes

**Purpose:** confirm Skip rows, One row per and Change values work and are shown in the preview.
**Prerequisites:** admin; `import-test-2.csv`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab, choose **Generic contact list**, select **Next**, and upload `import-test-2.csv`. | The columns step. **Status** is set to **Do not load**. |
| 2 | Beside **Email**, select **Change values**. Select **Add a change** and choose **All lower case**. | A panel headed "Change values: Email" shows **The first values, before and after**: `ANA.RT@EXAMPLE.ORG` becomes `ana.rt@example.org`. |
| 3 | Select **Done**. Beside **Last Name**, add **Capitalize each word** the same way and select **Done**. | The buttons now read **Change values (1)**. |
| 4 | Under **Rows to load**, **Skip rows where**, select **Add a rule**: **Column** Status, **Test** **equals**, **Text** `cancelled`. | The rule is listed. |
| 5 | Under **One row per**, choose **Email**. | Email is chosen. |
| 6 | Select **Next**, then **Preview**. | **Would create** 2, **Would be rejected** 0. The run log says "2 rows were skipped by Skip rows or One row per. They are listed with the file's rows, not as rejected." |
| 7 | Read **Changed values (first rows)**. | Row 1 shows `ANA.RT@EXAMPLE.ORG` before and `ana.rt@example.org` after, and `RAMIREZ-TEST` before and `Ramirez-Test` after. |
| 8 | Select **Import these rows**, then undo the import from **Recent imports**. | **Created** 2. After the undo, Ana Ramirez-Test and Cy Dupe are gone. |

**Cleanup:** the changes and rules are saved with the **Generic contact list** mapping. Upload `import-test-2.csv` with it again, remove both changes and the skip and one-row-per rules, and select **Preview**; then leave the page without importing.

## T-IMP-08: Matching choices

**Purpose:** confirm Match only refuses new people, and the duplicate-rule option explains itself.
**Prerequisites:** admin; `import-test-1.csv`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Run `import-test-1.csv` through **Generic contact list** to the matching step. | **Email exact** is chosen. |
| 2 | Choose **Name plus postal code** in **Match a row to someone you already have by**. | The help text reads "Matches on last name and postal code together. This will treat two different people who share a name at one address as the same person." |
| 3 | Choose **Email exact** again. Tick **Match only: update records you already have, add none**. | Ticked. |
| 4 | Select **Preview**. | **Would create** 0. **Would match and change nothing** 1 (Harper Garcia). The three new people and Dee are counted under **Would be rejected** and listed with a reason. |
| 5 | Select **Back**, untick **Match only**, and look for **Also match with my duplicate rules**. | Shown with its help text. If no duplicate rule is active for contacts, a line reads "No duplicate rule is switched on for these records, so this changes nothing for them...". |

**Cleanup:** none (nothing was imported).

## T-IMP-09: Matching through match sources

**Purpose:** confirm a person known only by a related address record is matched when first and last names agree, and not matched when either differs (a relative at the same address is never loaded into the person).
**Prerequisites:** admin; the shipped match source **Address (person)** active (BarnCRM Settings, **Custom metadata**, see [Custom metadata](../admin-guide/custom-metadata.md#match-sources)). Setup data: create a contact **Mara Stone** with no email and no mailing address, then on the **Addresses** tab create an address with **Person** Mara Stone, **Street** `77 Match Lane`, **City** Springfield, **Postal Code** `62702`.

Save `import-match.csv`:

```
First Name,Last Name,Email,Street,City,State,Postal Code
Mara,Stone,mara.stone.new@example.org,77 Match Lane,Springfield,IL,62702
Lee,Brook,lee.brook@example.org,77 Match Lane,Springfield,IL,62702
Jana,Stone,jana.stone@example.org,77 Match Lane,Springfield,IL,62702
```

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab, choose **Generic contact list**, select **Next**, upload `import-match.csv`, and select **Next**. | The matching step, with **Email exact** chosen. |
| 2 | Leave **Also match with my duplicate rules** unticked and select **Preview**. | **Would create** 3: by email alone, nobody matches any row. |
| 3 | Select **Back**, tick **Also match with my duplicate rules**, and select **Preview**. | **Would create** 2, **Would update** 1. Row 1 (Mara Stone) matches the existing Mara Stone through her address record, because the first and last names agree. Row 2 (Lee Brook, same address, different last name) and row 3 (Jana Stone, same address and last name, different first name) are not matched and would be created. |
| 4 | Select **Import these rows**. | **Created** 2, **Updated** 1. |
| 5 | Open the existing Mara Stone. | **Email** is now `mara.stone.new@example.org`; **First Name** is still Mara. There is still only one Mara Stone. |
| 6 | Open the import's Data Job record and its **Import Row** for row 1. | **Matched By Duplicate Rule** is ticked. On the rows for Lee Brook and Jana Stone it is not. |
| 7 | Search for Lee Brook and Jana Stone. | Each is a new contact, not loaded into Mara Stone. |
| 8 | Undo the import from **Recent imports** (**Undo**, **Undo this import**, **Refresh** until **Undone**). | **Changed values to put back** was 1. Lee Brook and Jana Stone are gone; Mara Stone remains, with no email. |

**Cleanup:** delete Mara Stone, her household and her address record.

## T-IMP-10: Load one object, update by record ID, and undo

**Purpose:** confirm a one-object mapping can be created, updates a record, appears in the mapping list, and its undo puts the value back.
**Prerequisites:** admin; the sample organization **Bayview Hardware**. Note its **Phone** value and copy its record ID from the address bar.

| Step | Action | Expected result |
|---|---|---|
| 1 | Save a CSV `org-phone.csv` with the heading `Id,Phone` and one row: the record ID, then `555-0199`. | Saved. |
| 2 | Open the Import tab. Under **Load one object**, select **Load one object**. | An **Object** picker, a **Mapping name** box and a **Create** button. **Create** is disabled until both are filled. |
| 3 | Choose **Account** as **Object**, type `Test org phone update` as **Mapping name**, and select **Create**. | The new mapping is chosen in **Choose what kind of file this is**. |
| 4 | Select **Next** and upload `org-phone.csv`. | The columns step. If **Id** is not already **Salesforce record ID**, choose it; **Phone** maps to the Phone field. Each column has an **Empty cells clear the field (update and upsert)** box. |
| 5 | Select **Next**. | **What each row does** offers update choices only, for example **Update by record ID** and **Update by a field you choose**; **Create new records** is not offered for accounts. |
| 6 | Choose **Update by record ID** and select **Preview**. | **Would update** 1, **Would be rejected** 0. |
| 7 | Select **Import these rows**. Open Bayview Hardware. | **Phone** reads `555-0199`. |
| 8 | Open the **Data Manager** tab. | **Import mappings** lists **Test org phone update**. **Data jobs** lists the import first. |
| 9 | In **Data jobs**, select **Undo** beside the import. | The box shows **Changed values to put back** 1 and 0 people, households and organizations to remove. |
| 10 | Select **Undo this import**, then **Refresh** until the job reads **Undone**. Open Bayview Hardware. | **Phone** is back to the value you noted. |

**Cleanup:** none (the test mapping may stay; it changes nothing on its own).

## T-IMP-11: Access to Import

**Purpose:** confirm only BarnCRM Admin holders can import.
**Prerequisites:** staff and read-only users with no extra permissions.

| Step | Action | Expected result |
|---|---|---|
| 1 | Log in as staff. Open the App Launcher and search for "Import" and "Data Manager". | Neither BarnCRM tab is found. |
| 2 | Log in as read-only and repeat. | Neither tab is found. |
| 3 | As admin, on **BarnCRM Settings**, **Access**, give staff the **BarnCRM Find and Export** extra permission. Log in as staff and open **Data Manager**. | The tab opens. There is no **Import a file** card and no **Import mappings** list. |
| 4 | Still as staff, search the App Launcher for "Import". | No Import tab. |

**Cleanup:** as admin, remove **BarnCRM Find and Export** from staff on the **Access** page.
