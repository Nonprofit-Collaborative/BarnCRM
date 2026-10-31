# Imports

Scripts for the Import wizard: templates, preview, commit, rejected rows, row rules, value changes, the first-step cards, Load one object, several sheets and two-part headings, and undo. Setup detail: [Importing](../admin-guide/importing.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and, in `import-test-1.csv` row 4, use `Harper`, `Zztest`, `harper.zztest1@example.org` so the row matches Harper Zztest (without that match T-IMP-01 would show 4 created, 0 matched). Import only the test files here, never a real list. The **Data Manager** feature must be on (BarnCRM Settings, **General**, see [Data Manager](../admin-guide/data-manager.md)). These scripts assume people are stored as contacts.

The Import tab opens from the **Data Manager** tab: select the **Import a File** tile. Save the test files below as UTF-8 CSV files with exactly these headings (the shipped **Generic contact list** template recognizes them; a new install calls it **People and Organizations List**, and an org installed before 2026-10-28 keeps **Generic contact list**, so read either name below as the one your org shows). For a migration-style file, the samples in [`docs/admin-guide/samples`](../admin-guide/samples) load through the Giving module's templates and are tested with Giving.

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

## T-IMP-01: Preview and Import a Contact List

**Purpose:** confirm the main path: choose a template, upload, check columns, preview, import and read the results.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)); `import-test-1.csv`.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Data Manager** tab and select the **Import a File** tile. | The **Import** tab opens on the card **Import a Spreadsheet**. A path across the top shows **Choose File Type**, **Upload File**, **Check Columns**, **Match Rows**, **Preview** and **Results**, with **Choose File Type** current. Below it, **What Are You Importing?** with the choice cards, each with an icon. **Next** and **Back** are not shown yet. A **Recent Imports** list shows below the wizard. |
| 2 | Under **What Are You Importing?**, choose **People and Organizations**, then in **Template** choose **Generic contact list**. | The cards stay, with **People and Organizations** marked as chosen and its name as a heading below them. The template's description appears under the picker ("A list of people with their contact details...") and the line "This file can create: people, households, organizations, links between people and organizations." **Next** is enabled, at the bottom right. |
| 3 | Select **Next**. | **Upload File** is current on the path, with an **Upload file** control. **Back** shows at the bottom left. |
| 4 | Upload `import-test-1.csv`. | **Check Columns** is current on the path. **Columns are separated by** shows **Commas**. The table lists all 8 columns with **Column in Your File**, **What It Means** and **First Values**; First Name, Last Name and Email are mapped to person fields (for example "Person: first name"). |
| 5 | Select **Next**. | **Match Rows** is current on the path. A collapsed **More Options** section sits below the matching choices. **Match a row to someone you already have by** shows **Email exact**, with its help text ("Matches only when the email in your file is exactly the email on the record..."). **When more than one record matches a row** shows **Reject the row**. |
| 6 | Select **Preview**. | **Preview** is current on the path. Counts as big numbers: **Would create** 3, **Would update** 0, **Would match and change nothing** 1, **Would be rejected** 1. **Rows That Were Rejected** lists row 6 (Dee; the file's header line is row 1, so the fifth person is row 6) with a reason naming the missing last name ("Required value missing: last name..."). |
| 7 | Search the org for "Testa Rivera". | No record found: the preview wrote nothing. |
| 8 | Back on the Import tab, select **Import These Rows**. | "Working through the file. This page updates as it goes." shows, then **Results** is current on the path, with **Created** 3, **Updated** 0, **Matched, nothing changed** 1, **Rejected** 1, and the run log under **What Happened**. |
| 9 | Open the new contact Testa Rivera from global search, then open their household. | The household exists and its **Created By Import Batch** field links to this import. |
| 10 | Open Harper Garcia. | Unchanged: the matched row created nothing and cleared nothing (empty cells never clear a person's fields). |
| 11 | Back on the Import tab, open the **Download** menu (beside **Import Another File**, the main button) and select **Download Results**. | A CSV downloads with one line per file row and the columns **Row**, **Outcome**, **Reason**, **Person ID** (and the other ID columns) beside the file's own columns. Rows 2 to 4 read Created, row 5 Matched, row 6 Rejected with its reason (the header line is row 1). |

**Cleanup:** keep the import for T-IMP-02 and T-IMP-03; T-IMP-03 undoes it.

## T-IMP-02: Download Rejected Rows and Retry the Fixed Rows

**Purpose:** confirm a rejected row can be fixed and loaded into the same import.
**Prerequisites:** admin; the finished import from T-IMP-01, still on its **Results** step (or reopen it from the same browser session).

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Results** step, open the **Download** menu and select **Download Rejected Rows**. | A CSV downloads with one data row (Dee), with the file's columns plus Row and Reason. |
| 2 | In the downloaded file, delete the **Email** column, save it as `retry-bad.csv`. Under **Retry Fixed Rows**, upload it as **File of fixed rows**. | Refused with "The fixed rows file is missing these columns of the original file: Email". Nothing is previewed. |
| 3 | Open the downloaded file again, type `Nolast` into Dee's Last Name cell, save it as `retry-good.csv`, and upload it under **Retry Fixed Rows**. | A preview of that one row: **Would create** 1, **Would be rejected** 0. |
| 4 | Select **Import These Rows**. | Results for the retry: **Created** 1. The import's rejected count is now 0. |
| 5 | Search the org for "Dee Nolast". | The contact exists, in a household of its own. |

**Cleanup:** none; T-IMP-03 undoes both runs together.

## T-IMP-03: Undo an Import

**Purpose:** confirm undo removes what an import created, keeps what it only matched, and asks before acting.
**Prerequisites:** admin; the import from T-IMP-01 and T-IMP-02, not yet undone. The counts below assume both ran (T-IMP-02 adds Dee Nolast). If you ran only T-IMP-01, read **People to remove** 3, **Households to remove** 3, and "6 records deleted" in step 8, and skip Dee Nolast in step 6.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab (Data Manager, **Import a File**, **Open**). | **Recent Imports** lists the import first, with **Started** and **Can be undone until** (30 days after it ran, unless the setting was changed) and an **Undo** button. |
| 2 | Select **Undo** beside it. | A box headed "Undo" plus the import's name shows counts: **People to remove** 4, **Households to remove** 4, **Organizations to remove** 0, **Changed values to put back** 0, with **Cancel** and **Undo This Import**. Nothing has changed yet. The counts are the records the import created from your file; undo also removes the households and gift allocations BarnCRM created automatically for those rows, so on a large import the total removed can be higher. |
| 3 | Select **Cancel**. | The box closes. The import is unchanged and **Undo** is still offered. |
| 4 | Select **Undo** again, then **Undo This Import**. | "The undo has started. The import shows Undone when it has finished; refresh the page to check." |
| 5 | Wait a minute and select **Refresh**. | The import row reads **Undone**. **Undo** is no longer offered. |
| 6 | Search the org for Testa Rivera, Ben Okoro, Cara Lind and Dee Nolast. | None is found. Their households are gone too (they are in the Recycle Bin). |
| 7 | Open Harper Garcia. | Still there, in **The Garcia Family**: undo never deletes a record the import only matched. |
| 8 | Open the import's **Data Job** record (from the **Data Jobs** list view or report) and read **Run Log**. | A line "Undone by (your name) on (date): 8 records deleted, 0 kept, 0 values put back." |

**Cleanup:** none.

## T-IMP-04: Undo Keeps a Record Somebody Edited

**Purpose:** confirm undo does not delete a created record that was edited after the import.
**Prerequisites:** admin; `import-test-1.csv`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Import `import-test-1.csv` with **Generic contact list** as in T-IMP-01, steps 1 to 8. | **Created** 3, **Rejected** 1. |
| 2 | Open the contact Ben Okoro, edit **Title** to `Edited after import`, and save. | Saved. |
| 3 | Open the Import tab. Select **Undo** beside the import, then **Undo This Import**. | The undo starts. |
| 4 | Select **Refresh** until the import reads **Undone**. | **Undone**. |
| 5 | Search for Testa Rivera, Cara Lind and Ben Okoro. | Testa Rivera and Cara Lind are gone. Ben Okoro is still there, with his household. |
| 6 | Read the Data Job's **Run Log**. | The undo line counts records kept (more than 0), and the import journal lists Ben Okoro as kept with "Kept: somebody changed this record, or logged an activity on it, after the import." |

**Cleanup:** delete Ben Okoro and his household by hand.

## T-IMP-05: Control Totals and a File BarnCRM Cannot Read

**Purpose:** confirm a control total that does not match blocks the import, and an unreadable file is refused.
**Prerequisites:** admin; `import-test-1.csv`; a plain text file renamed to `broken.xlsx`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab, choose **People and Organizations** and **Generic contact list**, select **Next**, and upload `broken.xlsx`. | "BarnCRM cannot read this Excel file. It may be an older .xls file or protected by a password. Save it as .xlsx or CSV and upload that." No columns step. |
| 2 | Upload `import-test-1.csv` instead and select **Next** on the columns step. | The matching step, with a collapsed **More Options** section. |
| 3 | Open **More Options**, type `6` in **Rows in the file** under **Control Totals (Optional)**, and select **Preview**. | The run log says "Control total: the file has 5 rows, but 6 were expected. The import is refused until they agree." **Import These Rows** is disabled. |
| 4 | Select **Back** to the matching step (**More Options** is already open, since a control total is set), change **Rows in the file** to `5`, and select **Preview**. | The run log says "Control total: the file has 5 rows, as expected." **Import These Rows** is enabled. |

**Cleanup:** none (nothing was imported). Select **Import Another File** or leave the page.

## T-IMP-06: Try the First Rows, Then the Rest

**Purpose:** confirm a trial import saves only the first rows and the rest join the same import with one undo.
**Prerequisites:** admin; `import-test-1.csv`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Run `import-test-1.csv` through **Generic contact list** to the **Preview** step. | The four preview counts as in T-IMP-01, and a **Try the First Rows** section with **Rows to try** (25 by default). |
| 2 | Set **Rows to try** to `2` and select **Import the First Rows**. | "The first 2 rows were imported. Check them above, then import the remaining 3 rows into the same import. If they are wrong, undo the import from Recent imports instead." |
| 3 | Search for Testa Rivera and Cara Lind. | Testa Rivera exists (first person in the file); Cara Lind (third) does not yet. |
| 4 | Select **Import the Remaining Rows**. | Results for the whole file: **Created** 3, **Matched, nothing changed** 1, **Rejected** 1. |
| 5 | Open **Recent Imports**. | One import for the file, not two. |
| 6 | Select **Undo**, then **Undo This Import**, and **Refresh** until **Undone**. | **People to remove** was 3. Testa Rivera, Ben Okoro and Cara Lind are all gone. |

**Cleanup:** none.

## T-IMP-07: Row Rules and Value Changes

**Purpose:** confirm Skip Rows Where, One Row Per and Change values work and are shown in the preview.
**Prerequisites:** admin; `import-test-2.csv`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab, choose **People and Organizations** and **Generic contact list**, select **Next**, and upload `import-test-2.csv`. | The columns step. **Status** is set to **Do not load**. |
| 2 | Beside **Email**, select **Change Values**. Select **Add a Change** and choose **All lower case**. | A panel headed "Change values: Email" shows **The First Values, Before and After**: `ANA.RT@EXAMPLE.ORG` becomes `ana.rt@example.org`. |
| 3 | Select **Done**. Beside **Last Name**, add **Capitalize each word** the same way and select **Done**. | The buttons now read **Change values (1)**. |
| 4 | Under **Rows to Load**, **Skip Rows Where**, select **Add a Rule**: **Column** Status, **Test** **equals**, **Text** `cancelled`. | The rule is listed, with a **Remove Rule** button. |
| 5 | Under **One Row Per**, choose **Email**. | Email is chosen. |
| 6 | Select **Next**, then **Preview**. | **Would create** 2, **Would be rejected** 0. The run log says "2 rows were skipped by Skip Rows Where or One Row Per. They are listed with the file's rows, not as rejected." |
| 7 | Read **Changed Values (First Rows)**. | Row 1 shows `ANA.RT@EXAMPLE.ORG` before and `ana.rt@example.org` after, and `RAMIREZ-TEST` before and `Ramirez-Test` after. |
| 8 | Select **Import These Rows**, then undo the import from **Recent Imports**. | **Created** 2. After the undo, Ana Ramirez-Test and Cy Dupe are gone. |

**Cleanup:** the changes and rules are saved with the **Generic contact list** template. Upload `import-test-2.csv` with it again, remove both changes and the skip and one-row-per rules, and select **Preview**; then leave the page without importing.

## T-IMP-08: Matching Choices

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

## T-IMP-09: Matching Through Match Sources

**Purpose:** confirm a person known only by a related address record is matched when first and last names agree, and not matched when either differs (a relative at the same address is never loaded into the person).
**Prerequisites:** admin; the shipped match source **Address (person)** active (**Duplicate Matching** tab, **Matching Logic**, see [Matching Logic](../admin-guide/duplicates.md#matching-logic)). Setup data: create a contact **Mara Stone** with no email and no mailing address, then on the **Addresses** tab create an address with **Person** Mara Stone, **Street** `77 Match Lane`, **City** Springfield, **Postal Code** `62702`.

Save `import-match.csv`:

```
First Name,Last Name,Email,Street,City,State,Postal Code
Mara,Stone,mara.stone.new@example.org,77 Match Lane,Springfield,IL,62702
Lee,Brook,lee.brook@example.org,77 Match Lane,Springfield,IL,62702
Jana,Stone,jana.stone@example.org,77 Match Lane,Springfield,IL,62702
```

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab, choose **People and Organizations** and **Generic contact list**, select **Next**, upload `import-match.csv`, and select **Next**. | The matching step, with **Email exact** chosen. |
| 2 | Leave **Also match with my duplicate rules** unticked and select **Preview**. | **Would create** 3: by email alone, nobody matches any row. |
| 3 | Select **Back**, tick **Also match with my duplicate rules**, and select **Preview**. | **Would create** 2, **Would update** 1. Row 1 (Mara Stone) matches the existing Mara Stone through her address record, because the first and last names agree. Row 2 (Lee Brook, same address, different last name) and row 3 (Jana Stone, same address and last name, different first name) are not matched and would be created. |
| 4 | Select **Import These Rows**. | **Created** 2, **Updated** 1. |
| 5 | Open the existing Mara Stone. | **Email** is now `mara.stone.new@example.org`; **First Name** is still Mara. There is still only one Mara Stone. |
| 6 | Open the import's Data Job record and its **Import Row** for row 1. | **Matched By Duplicate Rule** is ticked. On the rows for Lee Brook and Jana Stone it is not. |
| 7 | Search for Lee Brook and Jana Stone. | Each is a new contact, not loaded into Mara Stone. |
| 8 | Undo the import from **Recent Imports** (**Undo**, **Undo This Import**, **Refresh** until **Undone**). | **Changed values to put back** was 1. Lee Brook and Jana Stone are gone; Mara Stone remains, with no email. |

**Cleanup:** delete Mara Stone, her household and her address record.

## T-IMP-10: Load One Object, Update by Record ID, and Undo

**Purpose:** confirm a one-object template can be created, updates a record, appears in the template list, and its undo puts the value back.
**Prerequisites:** admin; the sample organization **Bayview Hardware**. Note its **Phone** value and copy its record ID from the address bar.

| Step | Action | Expected result |
|---|---|---|
| 1 | Save a CSV `org-phone.csv` with the heading `Id,Phone` and one row: the record ID, then `555-0199`. | Saved. |
| 2 | Open the Import tab. Under **What Are You Importing?**, choose **One Kind of Record**. | An **Object** picker, a **Template name** box and a **Create** button. **Create** is disabled until both are filled. |
| 3 | Choose **Account** as **Object**, type `Test org phone update` as **Template name**, and select **Create**. | The new template is chosen in **Template**, and the line under it reads "Loads: Account". |
| 4 | Select **Next** and upload `org-phone.csv`. | The columns step. If **Id** is not already **Salesforce record ID**, choose it; **Phone** maps to the Phone field. Each column has an **Empty cells clear the field (update and upsert)** box. |
| 5 | Select **Next**. | **What each row does** offers update choices only, for example **Update by record ID** and **Update by a field you choose**; **Create new records** is not offered for accounts. |
| 6 | Choose **Update by record ID** and select **Preview**. | **Would update** 1, **Would be rejected** 0. |
| 7 | Select **Import These Rows**. Open Bayview Hardware. | **Phone** reads `555-0199`. |
| 8 | Open the **Data Manager** tab. | **Import Templates** lists **Test org phone update**. **Data Jobs** lists the import first. |
| 9 | In **Data Jobs**, select **Undo** beside the import. | The box shows **Changed values to put back** 1 and 0 people, households and organizations to remove. |
| 10 | Select **Undo This Import**, then **Refresh** until the job reads **Undone**. Open Bayview Hardware. | **Phone** is back to the value you noted. |

**Cleanup:** none (the test template may stay; it changes nothing on its own).

## T-IMP-11: Access to Import

**Purpose:** confirm only BarnCRM Admin holders can import.
**Prerequisites:** staff and read-only users with no extra permissions.

| Step | Action | Expected result |
|---|---|---|
| 1 | Log in as staff. Open the App Launcher and search for "Import" and "Data Manager". | Neither BarnCRM tab is found. |
| 2 | Log in as read-only and repeat. | Neither tab is found. |
| 3 | As admin, on **BarnCRM Settings**, **Access**, give staff the **BarnCRM Find and Export** extra permission. Log in as staff and open **Data Manager**. | The tab opens. There is no **Import a File** card and no **Import Templates** list. |
| 4 | Still as staff, search the App Launcher for "Import". | No Import tab. |

**Cleanup:** as admin, remove **BarnCRM Find and Export** from staff on the **Access** page.

## T-IMP-12: What Are You Importing?

**Purpose:** confirm each card on the first step opens what it should, the Gifts and Delete cards show only where they apply, and the line under a template says what it creates.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)); a Core-only org for step 2 and an org with Giving installed for step 3; for step 5, a second admin without **Bulk Delete Records** and one with it (see [Bulk Update and Delete](bulk-update-and-delete.md)).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab. | **What Are You Importing?** with an icon card for **People and Organizations**, **One Kind of Record**, **Several Objects in One File** and **Your Templates** (and **Gifts** and **Delete the Records a File Lists** where steps 3 and 5 say). Each card says what it creates. None is chosen and **Next** is not shown. |
| 2 | In a Core-only org, look at the cards. | There is no **Gifts** card. |
| 3 | In an org with Giving installed, look at the cards, then choose **Gifts**. | A **Gifts** card shows. It is marked as chosen and the cards stay on screen. Its **Template** picker lists only gift templates (for example **Generic gift list**), the first is chosen, and **Next** is enabled. |
| 3a | Tab to the cards and press the arrow keys. | The choice moves from card to card like radio buttons, and what shows below follows the chosen card. |
| 4 | Choose **People and Organizations**. | The **Template** picker lists only people templates and the first is chosen for you. The line under it says what it creates. **Next** is enabled. |
| 5 | Log in as an admin without **Bulk Delete Records** and open the Import tab. Then log in as one with it. | The first sees no **Delete the Records a File Lists** card. The second sees it, with a warning icon. |
| 6 | Choose **One Kind of Record**. | **Object**, **Template name** and **Create** show. **Next** is not shown until a template is created. Choose **Account**, name it `Test cards account`, select **Create**: the template is chosen and the line reads "Loads: Account". |
| 7 | Choose **Several Objects in One File**. | **Objects to load** (a list to move objects across), **Template name** and **Create** show, with no **Object** picker. **Create** is disabled until an object is chosen and the template is named. T-IMP-17 covers the rest. |
| 8 | Select **Back** to the first step, then choose **Delete the Records a File Lists** (as the holder of **Bulk Delete Records**), choose **Contact**, name it `Test cards delete`, select **Create**. | The template is chosen and the line reads "Deletes: Contact". On the matching step **Delete by record ID** is chosen. |
| 9 | Choose **One Kind of Record**, then **Delete the Records a File Lists** again, and choose an object whose records you may create or edit but not delete (for example a custom object your permission sets give Read, Create and Edit but not Delete). | "This object's records cannot be deleted by file, so the template creates or updates them instead. To pick another object, choose another card, then this one again." |
| 10 | Choose **Your Templates**. | Every active template shows with its description, what it creates, and **Last loaded** with a date or **Not loaded yet**. Each has a **Use This Template** button. |
| 11 | Select **Use This Template** on **Generic contact list**. | It is chosen, **Next** is enabled and the line reads "This file can create: people, households, organizations, links between people and organizations." |
| 12 | Choose **One Kind of Record**. | **Your Templates** is no longer chosen, the template list is gone, and **Next** is not shown until a template is created. |

**Cleanup:** none (the test templates may stay; they change nothing on their own).

## T-IMP-13: Start a New Template From This One

**Purpose:** confirm a people template can be copied from the first step, the copy is chosen for you, and the source and one-object templates are unaffected.
**Prerequisites:** admin; the one-object template `Test cards account` from T-IMP-12 (or any one-object template in **Your Templates**).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab and choose **People and Organizations**. | The first template is chosen and **Start a New Template From This One** shows under it. |
| 2 | Select **Start a New Template From This One**. | **New template name** shows prefilled "Copy of" plus the chosen template's name, with **Create**. |
| 3 | Clear the name. | **Create** is disabled. |
| 4 | Enter `Test event sign-ups` and select **Create**. | The new template is chosen under **Template**, **Next** is enabled and the line under it matches the source's ("This file can create: ..."). |
| 5 | Choose **Your Templates**. | **Test event sign-ups** is listed with **Not loaded yet**. |
| 6 | Choose **People and Organizations** and pick the source template again. | The source is unchanged: same name, description and creates line, and it is not marked recurring. |
| 7 | Choose **Your Templates** and select **Use This Template** on `Test cards account`. | It is chosen and **Start a New Template From This One** does not show. |

**Cleanup:** from the **Import Template** record list, deactivate or delete `Test event sign-ups`.

## T-IMP-14: Shipped People Templates

**Purpose:** confirm the three shipped people templates exist, import what they say, and keep their names on an upgraded org.
**Prerequisites:** admin; a new install or fresh scratch org for steps 1 to 4 (an org installed before 2026-10-28 for step 5); no real data. Save the two files below as UTF-8 CSV.

`import-test-orgs.csv` (3 organizations):

```
Organization Name,Street,City,State,Postal Code,Country,Phone,Website
Riverbend Food Pantry,10 Mill Rd,Springfield,IL,62701,United States,555-0201,https://riverbend.example.org
Oak Street Library Friends,22 Oak St,Springfield,IL,62702,United States,555-0202,https://oakfriends.example.org
Harbor Youth Club,5 Pier Ave,Springfield,IL,62703,United States,555-0203,https://harboryouth.example.org
```

`import-test-couples.csv` (2 rows):

```
Contact 1 First Name,Contact 1 Last Name,Contact 1 Email,Contact 1 Phone,Contact 2 First Name,Contact 2 Last Name,Contact 2 Email,Contact 2 Phone,Household Name,Street,City,State,Postal Code,Country
Mira,Tolliver,mira.tolliver@example.org,555-0301,Dean,Tolliver,dean.tolliver@example.org,555-0302,Tolliver Household,7 Elm Ct,Springfield,IL,62704,United States
Nell,Ashby,nell.ashby@example.org,555-0303,Omar,Ashby,omar.ashby@example.org,555-0304,Ashby Household,9 Elm Ct,Springfield,IL,62704,United States
```

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab and choose **People and Organizations**. | **People and Organizations List** is chosen first, with its creates line ("This file can create: people, households, organizations, links between people and organizations."). |
| 2 | Open the **Template** picker. | It also lists **Organization List** and **Couples and Households**. Choosing **Organization List** shows "This file can create: organizations."; choosing **Couples and Households** shows "This file can create: people, a second person per row, households." |
| 3 | Choose **Organization List**, select **Next**, upload `import-test-orgs.csv`, select **Next** through the column check, then **Preview**. Import. | The preview shows **would create** 3 and **would be rejected** 0. After the import, the three organizations exist with the street, city, state, postal code and country in the billing address, plus phone and website, and no new people or households. |
| 4 | Select **Import Another File**, choose **People and Organizations**, then **Couples and Households**, upload `import-test-couples.csv`, preview and import. | The preview shows **would create** 2 (one per row) and **would be rejected** 0. After the import, **Tolliver Household** holds Mira and Dean Tolliver and **Ashby Household** holds Nell and Omar Ashby: one household with two members per row. |
| 5 | In an org installed before 2026-10-28 that has **Generic contact list**, open the Import tab after the upgrade and choose **People and Organizations**. | The first template is still named **Generic contact list** (never renamed), and **Organization List** and **Couples and Households** are listed as well. |

**Cleanup:** undo both imports from **Recent Imports** (see T-IMP-03).

## T-IMP-15: Several Sheets and Example Values

**Purpose:** confirm a workbook's sheets are listed with their rows, the chosen ones load as one file with columns joined by field, and each column shows example values (C-49a).
**Prerequisites:** admin; a spreadsheet program that saves .xlsx; no real data. Make `import-test-sheets.xlsx` with three sheets:

- **Read me**: one cell, `About this file`.
- **2025**: headings `First Name`, `Last Name`, `Email`, then one row `Sheeta`, `Zztest`, `sheeta.zztest@example.org`.
- **2026**: headings `Contact.First Name`, `Last Name`, `Phone`, then two rows: `Sheetb`, `Zztest`, `555-0601` and `Sheetc`, `Zztest`, with Phone empty.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab, choose **One Kind of Record**, choose **Contact**, name the template `Test sheets contact`, select **Create**, then **Next**, and upload `import-test-sheets.xlsx`. | **Sheets to load** lists **Read me (0 rows)**, **2025 (1 rows)** and **2026 (2 rows)**, with **2025** and **2026** chosen and **Read me** not chosen. |
| 2 | Look at the columns. | One row each for **First Name**, **Last Name**, **Email** and **Phone**: `Contact.First Name` on the 2026 sheet joined **First Name** (both map to First Name). |
| 3 | Look at the **Examples** column. | **First Name** shows `Sheeta`, `Sheetb`, `Sheetc`, one per line; **Phone** shows `555-0601` and `(blank)`; **Email** shows `sheeta.zztest@example.org` only. |
| 4 | Clear **2025**. | The columns are read again: **Email** is gone, and the **First Name** examples are `Sheetb` and `Sheetc`. |
| 5 | Choose **2025** again, select **Next**, choose **Create new records**, then **Preview**. | **would create** 3, **would be rejected** 0. |
| 6 | Select **Back** to the columns and clear **2025** and **2026**. | "This file has no heading row that BarnCRM can read. Check that the first row of the file holds the column names." No columns show and **Next** is disabled. |

**Cleanup:** none; nothing was imported. Deactivate `Test sheets contact` if you do not keep it.

## T-IMP-16: Headings That Name the Object, and the Suggested Object

**Purpose:** confirm a heading that names the object and the field maps to that field, nothing inexact is mapped, the object is suggested from a file before one is chosen, and sheets for different objects hold the step (C-49a).
**Prerequisites:** admin; no real data. Save `import-test-two-part.csv` as UTF-8:

```
Contact.First Name,Last Name (Contact),Contact: Phone,Contact_Email,Account.Name,Contact.Shoe Size
Twopa,Zztest,555-0701,twopa.zztest@example.org,Nowhere Inc,10
```

Make `contacts_2026.xlsx` with two sheets: **Contacts** (headings `First Name` and `Last Name`, one row `Sheetd`, `Zztest`) and **Accounts** (heading `Account Name`, one row `Zztest Org`).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab, choose **One Kind of Record**, and under **Suggest the object from a file** choose `import-test-two-part.csv`. | **Object** is set to **Contact**, with "Suggested from your file: Contact. Change it if it is not right." |
| 2 | Change **Object** to **Account**, then back to **Contact**. Name the template `Test two-part contact`, select **Create**, then **Next**. | The file is read without a second upload. **Contact.First Name** maps to First Name, **Last Name (Contact)** to Last Name, **Contact: Phone** to the Phone field (labelled Business Phone in most orgs), **Contact_Email** to Email. **Account.Name** and **Contact.Shoe Size** are **Do not load**. |
| 3 | Change **Account.Name** to any Contact field, then back to **Do not load**. | Each mapping can be changed as before. |
| 4 | Select **Back** to the first step, choose **One Kind of Record** again, and under **Suggest the object from a file** choose `contacts_2026.xlsx`. | **Object** is set to **Contact**. "The file's sheets point at different objects." with **Contacts: Contact** and **Accounts: Account** listed. |
| 5 | Name the template `Test sheets suggest`, select **Create**, then **Next**. | Both sheets are chosen. The step says the sheets you chose point at different objects, lists **Contacts: Contact** and **Accounts: Account**, and **Next** is disabled. |
| 6 | Clear **Accounts**. | The message is gone and **Next** is enabled. |
| 7 | Choose **One Kind of Record**, and under **Suggest the object from a file** choose a file named `budget.csv` with the heading `Amount`. | "Nothing in the file names an object you can load. Choose one from the list." No object is chosen. |

**Cleanup:** none; nothing was imported. Deactivate the `Test two-part contact` and `Test sheets suggest` templates if you do not keep them.

## T-IMP-17: Several Objects in One File

**Purpose:** confirm one upload loads several objects: each sheet into its own object, several objects from one row through two-part headings, records on a row linked, records on another sheet linked by a lookup column, parents before children, a failed parent rejecting its row, and one undo for all (C-49c, D-154).
**Prerequisites:** admin; no real data; a test contact whose record ID you have. Accounts are update-only in an import, so first create two accounts by hand: `Zzsev Org A` and `Zzsev Org B`. Make `import-test-several.xlsx` with two sheets, in this order:

- **Affiliations**: headings `Organization`, `Role`; rows `Zzsev Org A`, `Member` and `Zzsev Org B`, `Board`.
- **Accounts**: headings `Account Name`, `Phone`; rows `Zzsev Org A`, `555-0801` and `Zzsev Org B`, `555-0802`.

Save `import-test-one-row.csv` as UTF-8, with the test contact's record ID in both rows:

```
Account.Name,Affiliation.Role,Contact.Id,Contact.Title
Zzsev Org A,Volunteer,<contact record ID>,Zzsev Title
Zzsev Nowhere,Volunteer,<contact record ID>,Zzsev Title
```

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab, choose **Several Objects in One File**, and under **Suggest the object from a file (optional)** choose `import-test-several.xlsx`. | **Objects to load** already holds **Affiliation** and **Account** (from the sheet names). |
| 2 | Name the template `Test several sheets` and select **Create**. | The template is chosen and the line reads "Loads: Account, Affiliation". |
| 3 | Select **Next**. | The file is read without a second upload. **Object for Affiliations** is **Affiliation** and **Object for Accounts** is **Account**. The columns list **Account Name** and **Phone** first (the parents' sheet loads first, whatever the file's order), then **Organization** and **Role**. |
| 4 | Map **Organization** to the affiliation's organization field and set **Find it by** to **Account Name**. Select **Next**. | One box per object, Account first, each with **What each row does**; Account offers only the updates. Below the boxes, one **When a lookup finds no record** choice. |
| 5 | For **Account** choose **Update by a field you choose**, with **Match rows on** set to **Account Name**; leave **Affiliation** on **Create new records**. Select **Dry Run**. | 4 rows: the 2 Accounts rows would update their accounts, the 2 Affiliations rows would each create an affiliation. Nothing is written. |
| 6 | Select **Commit**, then open each new affiliation. | Each points at its organization. |
| 7 | Run the template again and, on the column step, change **Object for Accounts** to **Affiliation**, then back to **Account**. | The sheet's columns are mapped again for the chosen object each time. Leave without loading. |
| 8 | Create `Test several one row` from **Several Objects in One File** with **Account**, **Affiliation** and **Contact**, upload `import-test-one-row.csv`, and go to the matching step. | Under **Affiliation**, lines say each affiliation is linked to the Account record and to the Contact record on its row. |
| 9 | Set **Account** to update by **Account Name** and **Contact** to **Update by record ID**, then dry run and commit. | Row 1 updates the account and the contact's Title and creates an affiliation linked to both, with no column for either link. Row 2 is rejected with a reason starting "Account:"; its contact is not updated again and its affiliation is not created, since both point at the account. A contact with an account keeps it; one with none gets `Zzsev Org A`. |
| 9a | Make `Test several retry` with **Relationship** (on **Create new records**) and **Affiliation**, and load a one-row file whose relationship is valid (two test contacts, a Type and a Status) and whose affiliation role is over 255 characters. Note the relationship count, then download the exceptions file, shorten the role, keep the **Row** column, and retry it. | The first commit creates the relationship and rejects the row with a reason starting "Affiliation:". The retry creates the affiliation only: the relationship count is unchanged. |
| 10 | Undo all three imports from **Recent Imports**. | The affiliations and the relationship are deleted once each, and the phones and the contact's Title go back to what they were. |
| 11 | Open a one-object template saved with **Related records** before this change, if the org has one, and dry run a file. | It still shows **Related records** under a parent key and loads both as before. |

**Cleanup:** deactivate the test templates and delete the test accounts.
