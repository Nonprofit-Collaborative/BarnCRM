# Find

Scripts for the Find tab: building and running queries, conditions, related records, typed queries, summaries, exports and saved queries. Setup detail: [Find and export](../admin-guide/find.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest. Run, save and export only queries whose conditions match the fixture (for example **Last Name equals Zztest**); an export of a broader query would copy real people. The **Data Manager** feature must be on (BarnCRM Settings, **General**). These scripts assume people are stored as contacts. Editing in the results table is tested in [Bulk update and delete](bulk-update-and-delete.md).

## T-FIND-01: Build and Run a Query

**Purpose:** confirm a query built from lists runs and shows the matching records.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Find** tab. | The card **Find** with the line "Choose an object, the columns and conditions, then run, save or export. Find shows only what your own access allows." **Saved queries** and **Object** pickers are shown. |
| 2 | In **Object**, choose **Contact**. | **Columns** (with **Available fields** and **Columns, in order**), **Add fields from**, **Conditions**, **Sort by** and **Rows to show** appear. **Conditions** reads "No conditions yet, so every record matches." |
| 3 | In **Columns**, move **First Name**, **Last Name** and **Email** to **Columns, in order**. | The three fields are listed in that order. |
| 4 | Under **Conditions**, select **Add condition**. Choose **Last Name**, **equals**, and type `Garcia`. | The condition is complete; no message under it. |
| 5 | Read **Query (read only)**, and point at its help icon. | It shows a SOQL query on Contact with a WHERE clause on LastName equal to Garcia. The help reads "The query Find runs, in SOQL, for anyone who wants to check it or copy it. To type or paste a query instead, use Type a query." |
| 6 | In **Sort by**, choose **First Name**; in **Direction**, **Ascending**. Select **Run**. | The table lists the Garcia contacts sorted by first name, including Harper Garcia and Luis Garcia. The line above it reads "N rows shown." with N the number of rows. |
| 7 | Change the condition value to `Nobodyzz` and select **Run**. | "No records match these conditions." |

**Cleanup:** none. Keep the page open for T-FIND-02 if you like.

## T-FIND-02: Conditions That Are Refused

**Purpose:** confirm incomplete conditions, bad values and bad condition logic are marked and the query does not run.
**Prerequisites:** admin; Find open on **Contact** with at least one column chosen.

| Step | Action | Expected result |
|---|---|---|
| 1 | Remove every column and select **Run**. | "Choose at least one column." Nothing runs. |
| 2 | Add **First Name** back. Select **Add condition** and leave the field empty. Select **Run**. | The condition shows "Choose a field." and the page says "Fix the conditions marked below, then try again." |
| 3 | Choose **Last Name**, **equals**, and leave the value empty. Select **Run**. | The condition shows "Enter a value." |
| 4 | Change the condition to **Birthdate**, **is in the last N days**, value `0`. | "Enter a whole number of days from 1 to 3650." |
| 5 | Change the condition to **Last Name**, **equals**, `Garcia`. Add a second condition **First Name**, **equals**, `Harper`. Tick **Use custom condition logic** and type `1` in **Condition logic**. | "The condition logic must use every condition. Add condition 2 to it, or remove the condition." |
| 6 | Change the logic to `1 AND 3`. | "The condition logic names condition 3, which does not exist." |
| 7 | Change the logic to `1 AND 2` and select **Run**. | One row: Harper Garcia. |

**Cleanup:** none.

## T-FIND-03: Related Fields and Related Records

**Purpose:** confirm columns from a related record, related-records conditions and related record columns.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Find**, choose **Account**, and add **Account Name** to the columns. | Shown in **Columns, in order**. |
| 2 | Under **Related records**, select **Add related records**. Choose **Has related records** in **Which records**, and the Contacts option in **Kind of related record**. | **Conditions on the related records (none means any related record)** appears. |
| 3 | Add a related condition **First Name**, **equals**, `Harper`, and select **Run**. | The results include **The Garcia Family** and no household without a Harper. |
| 4 | Under **Related Record Columns**, select **Add a Related Record Column**. Choose the Contacts option and add **First Name** to **Fields to show (up to 5)**. Select **Run**. | A new column lists each household's contacts' first names in one cell, for example Harper and Luis on The Garcia Family. |
| 5 | Change **Which records** to **Has no related records**, remove the related condition, and select **Run**. | Only accounts with no contacts are listed (for example sample organizations with no people); The Garcia Family is not listed. |

**Cleanup:** none.

## T-FIND-04: Export to CSV and Excel

**Purpose:** confirm exports hold every matching record, not only the rows shown.
**Prerequisites:** admin.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Find**, choose **Contact**, add **First Name**, **Last Name** and **Email**, no conditions. Set **Rows to show** to `10` and select **Run**. | Ten rows. The line above reads "Showing the first 10 rows. Export to get every matching record." |
| 2 | Select **Export to CSV**. | "Exporting: N rows so far." while it reads, then "Exported N rows." with N the total number of contacts (about 440 with sample data), not 10. A CSV downloads, named for the object and today's date. |
| 3 | Open the CSV in a spreadsheet. | A header row of the three column labels and N data rows. Accented names (if any) read correctly. |
| 4 | Edit one sample contact's **Title** to `=1+1` and save. Export again and open the file. | That cell reads `'=1+1` (a leading single quote), so the spreadsheet does not calculate it. |
| 5 | Select **Export to Excel**. | An .xlsx file downloads with the same rows and a header row. |

**Cleanup:** clear the Title you set in step 4.

## T-FIND-05: Export to Files

**Purpose:** confirm the server-side export writes CSV files to the user's Files.
**Prerequisites:** admin; job notifications on (the default).

| Step | Action | Expected result |
|---|---|---|
| 1 | Run a Contact query with no conditions and three columns, as in T-FIND-04. | Rows are shown. |
| 2 | Select **Export to Files**. | "Export to Files started. You can leave this page: BarnCRM tells you when the files are ready." Then "Exporting: X of Y chunks done." |
| 3 | Wait until it finishes. | "Ready: 1 CSV files in your Files (Owned by Me). Delete them there once downloaded." and **Files:** with a link to the file. A bell notification arrives. |
| 4 | Open **Files**, **Owned by Me**. | The CSV is there, named for the object, the date and the part. It holds every contact. |

**Cleanup:** delete the exported file from Files.

## T-FIND-06: Save, Share and Delete a Query

**Purpose:** confirm saved queries, Save as, sharing, and the delete confirmation.
**Prerequisites:** admin and staff; staff given **BarnCRM Find and Export** on BarnCRM Settings, **Access**, **Extra Permissions** (see [Access](../admin-guide/access.md)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, build the T-FIND-01 query. Type `Test Garcias` in **Query name** and select **Save**. | "Saved Test Garcias." |
| 2 | Select **New query**, then open **Test Garcias** from **Saved queries**. | The object, columns, condition and sort come back as saved. |
| 3 | Select **Save as**, name it `Test Garcias copy`. | "Saved Test Garcias copy." Both are listed in **Saved queries**. |
| 4 | Open **Test Garcias**, tick **Show to everyone who uses Find**, and select **Save**. | Saved. |
| 5 | Log in as staff, open **Find**, and open **Saved queries**. | **Test Garcias** is listed as "Test Garcias (shared by" plus the admin's name. **Test Garcias copy** is not listed. |
| 6 | As staff, open the shared query and select **Run**. | The same Garcia rows. **Save** and **Delete** are disabled for it; **Save as** is enabled. |
| 7 | As admin, open **Test Garcias** and select **Delete**. | A dialog "Delete this saved query?" says "Test Garcias will be deleted. This cannot be undone." and "This query is shared with everyone who uses Find. Deleting it removes it for all of them." |
| 8 | Select **Keep it**. | The dialog closes; the query is still listed. |
| 9 | Select **Delete** again, then **Delete** in the dialog. | "Deleted Test Garcias." It is gone from **Saved queries** for admin and staff. |

**Cleanup:** delete **Test Garcias copy**; remove **BarnCRM Find and Export** from staff.

## T-FIND-07: Type a Query

**Purpose:** confirm a typed query is read into the builder and unsupported text is refused.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Find**, choose **Contact**, and select **Type a query**. | A **Query (SOQL)** box starting with the query shown below the conditions, and **Use this query**. |
| 2 | Type `SELECT FirstName, LastName FROM Contact WHERE LastName = 'Garcia' ORDER BY FirstName LIMIT 50` and select **Use this query**. | The builder shows object Contact, the two columns, the condition Last Name equals Garcia, sort by First Name, and 50 rows to show. **Run** lists the Garcias. |
| 3 | Type `SELECT LastName FROM Contact WHERE LastName = 'A' AND FirstName = 'B' OR Email = null` and select **Use this query**. | "Add brackets where AND and OR are mixed, for example A AND (B OR C)." The builder is unchanged. |
| 4 | Type `SELECT LastName, COUNT(Id) FROM Contact GROUP BY LastName` and select **Use this query**. | Refused with a message starting "Find queries do not support this:" and ending "Use Summarize for totals and groups." |
| 5 | Clear the box and select **Use this query**. | "Type a query first." |

**Cleanup:** none.

## T-FIND-08: Summarize

**Purpose:** confirm counts and grouped summaries use the query's conditions.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Build the T-FIND-01 query (Contact, Last Name equals Garcia) and **Run** it. Note the row count. | "N rows shown." |
| 2 | Under **Summarize**, choose **Count of records** in **Summary**, **No grouping (one line)** in **Group by**, and select **Summarize**. | A table with **Group** and **Result**: one line whose result is N. |
| 3 | Choose **Group by** **First Name** and select **Summarize**. | One line per first name; the results add up to N. |
| 4 | Change the condition to Last Name equals `Nobodyzz` and select **Summarize**. | "No records match, so there is nothing to summarize." |

**Cleanup:** none.

## T-FIND-09: Access to Find

**Purpose:** confirm Find is only for holders of Find and Export, and the bulk buttons follow their own permissions.
**Prerequisites:** staff and read-only with no extra permissions; admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Log in as read-only. Search the App Launcher for "Find". | No BarnCRM **Find** tab. |
| 2 | Log in as staff and repeat. | No **Find** tab. |
| 3 | As admin, on BarnCRM Settings, **Access**, give staff **BarnCRM Find and Export** under **Extra Permissions**. Log in as staff again. | The **Find** and **Data Manager** tabs are available. |
| 4 | As staff, run a Contact query. | Results show. **Run**, **Export to CSV**, **Export to Excel**, **Export to Files** and **Summarize** are offered; **Bulk Update** and **Bulk Delete** are not. Cells show no edit pencil. |
| 5 | As staff, open an object staff cannot read (if your org has one), or ask admin to note a field staff cannot see. | That object is not offered, and that field is not offered as a column or a condition. |
| 6 | As admin, remove **BarnCRM Find and Export** from staff. Log in as staff. | **Find** is gone again. |

**Cleanup:** none (step 6 resets staff).
