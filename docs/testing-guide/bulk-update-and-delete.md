# Bulk Update and Delete

Scripts for changing and deleting the records a Find query returns, editing in Find's table, deleting by file, undo, and the permissions behind them. Setup detail: [Bulk update](../admin-guide/bulk-update.md) and [Bulk delete](../admin-guide/bulk-delete.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest, so every query names only fixture contacts. Check the preview count before you confirm any bulk step: 3 for Zztest, 3 for Bulkdeltest. If it is higher, cancel. The **Data Manager** feature must be on (BarnCRM Settings, **General**). These scripts assume people are stored as contacts.

**Bulk Delete Records is in no role, not even BarnCRM Admin.** For the delete scripts, give admin the **BarnCRM Bulk Delete** extra permission first: BarnCRM Settings, **Access**, **Extra Permissions** (see [Access](../admin-guide/access.md)).

Test contacts for the delete scripts: create three contacts with first names `Del1`, `Del2`, `Del3` and last name `Bulkdeltest` (each gets a household of its own).

## T-BULK-01: Set a Field on Every Record a Query Returns

**Purpose:** confirm the main bulk update path: preview with before and after, typed count, run and summary.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)); the Garcia contacts have an empty **Title**.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Find**. Choose **Contact**, add **First Name**, **Last Name** and **Title**, add the condition **Last Name** **equals** `Garcia`, and select **Run**. | The Garcia contacts are listed. Note the count N from "N rows found." |
| 2 | Open **Change Records** and choose **Bulk Update**. | A panel **Bulk Update** opens under the buttons, with the path **Choose Changes**, **Confirm**, **Run**: "Change up to five fields on every record this query returns, with your own access. Nothing changes until you confirm." |
| 3 | Under **Changes**, choose **Title** in **Field**, **Set to a value** in **What to do**, and type `test title` in **New Value**. | The change is complete. **Add a Change** is enabled. |
| 4 | Select **Preview**. | "N records match. The first ones, before and after:" and a table with **Record**, **Before** (empty) and **After** (`test title`) for up to five records. The four columns are equal width, and a long value wraps onto more lines inside its cell instead of stretching the table past the panel. |
| 5 | Type a number other than N in **Type the number of records to confirm**. | The **Update N records** button stays disabled. |
| 6 | Type N. | **Update N records** is enabled. |
| 7 | Select **Update N records**. | "The bulk update started. It keeps running if you leave this page." then "Updating: X of Y chunks done." |
| 8 | Wait for it to finish. | "N matched: N updated, 0 already held the new values, 0 failed." and "To undo it, open Data Jobs on the Data Manager tab." |
| 9 | Select **Run** in Find again. | Every Garcia contact's **Title** reads `test title`. |

**Cleanup:** keep the job for T-BULK-02, which undoes it.

## T-BULK-02: Undo a Bulk Update

**Purpose:** confirm undo puts back every value nobody changed since, and keeps a value somebody did change.
**Prerequisites:** admin; the bulk update from T-BULK-01, not yet undone.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Harper Garcia and change **Title** to `Changed by hand`. Save. | Saved. |
| 2 | Open the **Data Manager** tab. In **Data Jobs**, choose **Bulk updates** in **Show**. | The bulk update is listed first with "N matched: N updated, 0 already held the new values, 0 failed.", **Started**, **Can be undone until**, and **Undo**. |
| 3 | Select **Undo**. | "Undo puts back the values on N records, except any somebody changed since. Type N to confirm." with **Cancel** and **Undo Bulk Update** (disabled). |
| 4 | Type N and select **Undo Bulk Update**. | "The undo started. Press Refresh to see when it has finished." |
| 5 | Select **Refresh** until the job's status reads **Undone**. | **Undone**; **Undo** is no longer offered. |
| 6 | Run the Find query from T-BULK-01 again. | Every Garcia **Title** is empty again, except Harper Garcia's, which still reads `Changed by hand`. |

**Cleanup:** clear Harper Garcia's **Title**.

## T-BULK-03: Bulk Update Refusals

**Purpose:** confirm bad changes and a stale count are refused before anything changes.
**Prerequisites:** admin; Find open on the Garcia query from T-BULK-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **Bulk Update**. Choose **Last Name**, **Clear**, and select **Preview**. | Refused: "Last Name is required, so it cannot be cleared." Nothing changes. |
| 2 | Change the action to **Set to a value**, `Garcia-Test`, and select **Preview**. Note N. | The preview shows N records. |
| 3 | In another browser tab, create a contact `Extra Garcia` (last name `Garcia`). | Saved. |
| 4 | Back in the panel, type N and select **Update N records**. | "More records match now than the N you confirmed. Nothing was changed. Preview again and confirm the new number." |
| 5 | Close the panel with **Close** without running it. Check the Garcia contacts. | Every last name is still `Garcia`. |

**Cleanup:** delete the contact Extra Garcia and its household.

## T-BULK-04: Change with Steps, and Household Names

**Purpose:** confirm Change with steps previews each record's own result, and a household's name is left to household naming.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set **Title** to `assistant coach` on Harper Garcia and Luis Garcia. In Find, query Contact where **Title** **equals** `assistant coach` and **Run**. | Two rows. |
| 2 | Select **Bulk Update**. Choose **Title**, **Change with steps**, select **Add a Change** and choose **Capitalize each word**. Select **Preview**. | "2 records match..." with **Before** `assistant coach` and **After** `Assistant Coach`. |
| 3 | Type `2` and select **Update 2 records**. | "2 matched: 2 updated, 0 already held the new values, 0 failed." Both titles read `Assistant Coach`. |
| 4 | In Find, query **Account** where **Account Name** **equals** `The Garcia Family` and **Run**. Select **Bulk Update**, choose **Account Name**, **Set to a value**, `Renamed Household`, **Preview**, type `1`, and select **Update 1 records**. | The summary counts 1 failed, listed under **Records that failed, and why** with "This is a household, and household naming keeps its name, so it was left as it was. To name it yourself, check Custom name on the household." |
| 5 | Open The Garcia Family. | The name is unchanged. |

**Cleanup:** undo the title bulk update from **Data Jobs** (or clear both titles by hand).

## T-BULK-05: Edit in Find's Table, and Undo

**Purpose:** confirm inline edits are saved as a data job that can be undone.
**Prerequisites:** admin (BarnCRM Admin holds Bulk Update Records).

| Step | Action | Expected result |
|---|---|---|
| 1 | In Find, run the Garcia Contact query with the **Title** column. | Editable cells show a pencil. |
| 2 | Double-click Luis Garcia's **Title**, type `Inline edit`, and select **Save** at the foot of the table. | "Saved 1 records. 0 already held the values. Undo from Data Jobs on the Data Manager tab." |
| 3 | Open the **Data Manager** tab, **Data Jobs**. | A bulk update job is listed first; its run log on the Data Job record starts "Edited in Find". |
| 4 | Select **Undo**, type `1`, and select **Undo Bulk Update**. **Refresh** until **Undone**. | Luis Garcia's **Title** is empty again. |

**Cleanup:** none.

## T-BULK-06: Bulk Delete with a Download First, and Undo

**Purpose:** confirm the bulk delete path, the download before delete, and undelete from the Recycle Bin.
**Prerequisites:** admin with **BarnCRM Bulk Delete**; the three `Bulkdeltest` contacts.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | In Find, query **Contact** where **Last Name** **equals** `Bulkdeltest` with column **First Name**, and **Run**. | Three rows: Del1, Del2, Del3. |
| 2 | Open **Change Records** and choose **Bulk Delete**. | A panel **Bulk Delete** with the path **Preview**, **Confirm**, **Run**: "Delete every record this query returns, with your own access. They go to the Recycle Bin, and Data Jobs in the Data Manager can undo it." |
| 3 | Select **Preview**. | A line saying 3 records match, "The first ones:" with the three names, and any related records Salesforce deletes with them, as badges, under "Salesforce also deletes these related records with them, and brings them back with an undo:". |
| 4 | Select **Download a Backup First**. | "Reading records for the download..." then "Downloaded 3 records. Nothing has been deleted yet." A CSV with the three contacts and every field you can see downloads. |
| 5 | Type `2` in **Type the number of records to confirm**. | **Delete 3 records** stays disabled. |
| 6 | Type `3` and select **Delete 3 records**. | "The bulk delete started..." then "Deleting: X of Y chunks done." and finally "3 matched: 3 deleted, 0 refused." with "To bring these records back, use Undo next to the job under Data Jobs on the Data Manager tab." |
| 7 | Run the Find query again. | "No records match these conditions." Their three households still exist (emptied households are kept). |
| 8 | Open **Data Manager**, **Data Jobs**, choose **Bulk deletes** in **Show**, and select **Undo** beside the job. | "Undo brings back 3 records from the Recycle Bin, except any no longer there. Type 3 to confirm." |
| 9 | Type `3`, select **Undo Bulk Delete**, and **Refresh** until **Undone**. | **Undone**. |
| 10 | Run the Find query again. | Del1, Del2 and Del3 are back, each in their household. |

**Cleanup:** keep the contacts for T-BULK-07 and T-BULK-08, then delete them and their households.

## T-BULK-07: Bulk Delete Run Limit

**Purpose:** confirm a delete over the run limit is refused before it starts.
**Prerequisites:** admin with **BarnCRM Bulk Delete**; the three `Bulkdeltest` contacts.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Import**, set **Bulk delete run limit** to `2`, and save. | Saved. |
| 2 | In Find, run the `Bulkdeltest` query, select **Bulk Delete**, then **Preview**. | Refused: "More than 2 records match, the run limit for one bulk delete. Narrow the query, or run it in parts." Nothing is deleted. |

**Cleanup:** set **Bulk delete run limit** back to `10000`.

## T-BULK-08: Delete by File

**Purpose:** confirm Load one object's Delete by record ID dry runs a file, then deletes and can be undone like a bulk delete.
**Prerequisites:** admin with **BarnCRM Bulk Delete**; the record ID of Del1 (from its address bar) saved as a CSV `delete-ids.csv` with heading `Id` and that one ID.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab (Data Manager, **Import a File**, **Open**). Under **What Are You Importing?**, choose **Delete the Records a File Lists**, choose **Contact**, name the template `Test delete by file`, and select **Create**. | The new template is chosen, already on **Delete by record ID**, and the line under it reads "Deletes: Contact". |
| 2 | Select **Next**, upload `delete-ids.csv`, map **Id** to **Salesforce record ID** if needed, and select **Next**. | **What each row does** includes **Delete by record ID**, with its risk text ending "undo from Data Jobs on the Data Manager tab within 15 days." |
| 3 | Choose **Delete by record ID** and select **Preview**. | The dry run finds 1 record. A delete panel opens: "Delete every record this dry run found, with your own access..." with **Download these records first**, **Type the number of records to confirm** and the delete button. |
| 4 | Type `1` and select **Delete 1 records**. | "1 matched: 1 deleted, 0 refused." Del1 is gone; Del2 and Del3 remain. |
| 5 | Undo the job from **Data Jobs** on the **Data Manager** tab (type `1`, **Undo Bulk Delete**, **Refresh**). | **Undone**. Del1 is back. |
| 6 | On the Import tab, check **Recent Imports**. | The import's own Undo never undoes a delete: the job is either not offered there, or its Undo is refused with "This is a bulk delete. Undo it from Data Jobs on the Data Manager tab, which brings the records back from the Recycle Bin." |

**Cleanup:** delete the three `Bulkdeltest` contacts and their households; remove **BarnCRM Bulk Delete** from admin.

## T-BULK-09: Permissions and Tabs

**Purpose:** confirm the Bulk Update and Bulk Delete permission sets, and that the BarnCRM Tab sets follow them.
**Prerequisites:** admin; staff and read-only with no extra permissions.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin (without **BarnCRM Bulk Delete**), run any Find query. | **Bulk Update** is offered; **Bulk Delete** is not. |
| 2 | Log in as read-only. Search the App Launcher for "Find", "Bulk Update" and "Data Manager". | None of these BarnCRM tabs is found. |
| 3 | As admin, on **Access**, give staff **BarnCRM Find and Export** only. Log in as staff and run a Find query. | Neither **Bulk Update** nor **Bulk Delete** is offered. No **Super Transform** tab in the App Launcher. |
| 4 | As admin, give staff **BarnCRM Bulk Update** as well. Log in as staff and run a Find query. | **Bulk Update** is offered, and the **Super Transform** tab is available. |
| 5 | As staff, open the **Super Transform** tab. | The five Super Transform steps, then **Data Jobs** with "Start a bulk update with Super Transform above, or from a saved query in Find (Change Records, Bulk Update). Recent bulk updates and their undo are listed here." and **Open Find**. Only staff's own jobs are listed; **Show everyone's jobs** is not offered. |
| 6 | As admin, open the **Super Transform** tab. | **Show everyone's jobs** is offered; ticking it lists other people's jobs too. |
| 7 | As admin, give staff **BarnCRM Bulk Delete**. Log in as staff and run a Find query. | **Bulk Delete** is offered. On **Access**, the Bulk Delete give step showed the warning "This permission lets the person remove data. Give it only to someone you trust to do that." |
| 8 | As admin, in Setup, open staff's user and check **Permission Set Assignments**. | **BarnCRM Tab: Bulk Update**, **BarnCRM Tab: Find** and **BarnCRM Tab: Data Manager** are assigned (given by BarnCRM, not by hand). |
| 9 | As admin, remove **BarnCRM Bulk Update**, **BarnCRM Bulk Delete** and **BarnCRM Find and Export** from staff on **Access**. Log in as staff. | The **Find**, **Super Transform** and **Data Manager** tabs are gone. |

**Cleanup:** none (step 9 resets staff).

## T-BULK-10: The Bulk Path from Data Manager

**Purpose:** confirm the way into Bulk Update and Bulk Delete is obvious, and each panel shows its steps.
**Prerequisites:** admin with **BarnCRM Bulk Delete**; sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Data Manager** and choose the **Update Many Records** tile. | The **Super Transform** tab opens on **1. Object**, with no Find note. On a first visit a tip "Bulk Changes Start Here" says to start from Find only for a saved query. Go back. |
| 2 | Open **Find**. Choose **Contact**, add **Title**, add the condition **Last Name** **equals** `Garcia`, select **Run**, then **Change Records**, **Bulk Update**. | The **Bulk Update** panel shows a path **Choose Changes**, **Confirm**, **Run**, on **Choose Changes**, and **Add a Change**. |
| 3 | Choose **Title**, **Set to a value**, type `x`, and select **Preview**. | The path moves to **Confirm**. Select **Close**; nothing changed. |
| 4 | Choose **Change Records**, **Bulk Delete**, then **Preview**. | The **Bulk Delete** panel's path **Preview**, **Confirm**, **Run** is on **Confirm**. Any related records deleted with them show as badges. **Download a Backup First** has an info icon whose popover says what the file holds. Select **Close** without typing the count. |
| 5 | Open **Data Manager**, choose the **Delete Many Records** tile, then **Continue**. | **Find** opens with "Bulk Delete starts here: find the records, press Run, then choose Change Records, Bulk Delete." |
| 6 | On **Data Manager**, under **Data Jobs**, select **Open Find**. | **Find** opens with a note: "Bulk Update starts here: find the records, press Run, then choose Change Records, Bulk Update." (the way to start from a saved query) |

**Cleanup:** none (nothing was changed or deleted).

## T-BULK-11: Super Transform from Start to Undo

**Purpose:** confirm the five Super Transform steps: live count, typed value inputs, preview with highlighted changes, confirmation, run and undo. Setup detail: [Super Transform](../admin-guide/super-transform.md).
**Prerequisites:** admin; the Garcia contacts have an empty **Title**.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Super Transform** tab. | The tab reads **Super Transform**. Five numbered steps show above **Data Jobs**: **1. Object**, **2. Which Records**, **3. What to Change**, **4. Preview**, **5. Run**. Steps 2 and 3 say "Choose an object first." **Preview** and **Run Super Transform** are disabled. |
| 2 | Type `cont` in **Search Objects**, then open **Object**. | Only objects whose name contains "cont" are listed. No BarnCRM bookkeeping object (Data Job, Error Log) is offered anywhere in the list. Choose **Contact**. |
| 3 | Wait a moment without adding a condition. | **Matching Records** shows the number of contacts with an **Every Record** badge, and a warning: "No condition is set. This changes every Contact: N records." |
| 4 | Add the condition **Last Name** **equals** `Garcia`. | After about half a second the count changes to the number of Garcia contacts (note it as N) and the warning goes away. |
| 5 | Under **3. What to Change**, choose **Title**, keep **Set To**, and type `st test`. Then press **Add a Field**, choose a picklist field (for example **Salutation**). | The second row's **New Value** is a dropdown of the picklist's values. Remove the second row with its delete icon. |
| 6 | Press **Preview**. | "N records match. The first N, before and after:" and a table with **Record** and **Title**. Every **Title** cell is shaded and reads "(blank)", an arrow, then `st test` in bold. "0 of the N records shown already have these values and will not be saved." |
| 7 | Change **New Value** to `st test2`. | The preview table disappears and **Run Super Transform** is disabled until you press **Preview** again. Press **Preview**. |
| 8 | Press **Run Super Transform**, then **Cancel**. | The confirmation read "Change Title on N Contacts." Nothing changed. |
| 9 | Press **Run Super Transform**, then **Run**. | "The bulk update started." then a progress bar, then "N matched: N updated, 0 already held the new values, 0 failed." and "To undo this run, press Undo on it under Data Jobs below." |
| 10 | Reload the page. Under **Data Jobs**, press **Undo** on the newest bulk update, type the number and confirm. | When the undo finishes, every Garcia contact's **Title** is empty again. |

**Cleanup:** none (the undo put the titles back).

## T-BULK-12: Super Transform Warnings and Typed Confirmation

**Purpose:** confirm the run limit warning, the typed confirmation over 200 records, and that values already held are shown as unchanged.
**Prerequisites:** admin; sample data loaded (more than 200 contacts).

| Step | Action | Expected result |
|---|---|---|
| 1 | In BarnCRM Settings, **Import**, set **Bulk update run limit** to `10`. Open **Super Transform**, choose **Contact**, with no condition. | **Matching Records** shows 11 with an **Over the Limit** badge and a warning that more records match than the 10 one run may change. **Preview** is disabled. |
| 2 | Set **Bulk update run limit** back to `48000` and reload **Super Transform**. Choose **Contact**, choose **Title**, **Set To**, type `x`, and press **Preview**. | The table lists 25 contacts. |
| 3 | Press **Run Super Transform**. | The confirmation has a field "Type N to confirm" (N is the count), and **Run** stays disabled until N is typed. Press **Cancel**. |
| 4 | Add the condition **Last Name** **equals** `Garcia`, choose **Title** **Clear**, and press **Preview**. | Every **Title** cell that is already empty is not shaded and shows only "(blank)"; the line under the table counts them. |

**Cleanup:** check **Bulk update run limit** reads 48,000.

## T-BULK-13: Super Transform Steps and Permissions

**Purpose:** confirm Change With Steps, Fix Name Capitals and the message for a person without the permissions.
**Prerequisites:** admin; a contact with **First Name** `  ana ` and **Last Name** `Sttest`; a user with **BarnCRM Find and Export** only (see [Test users](before-you-test.md#test-users)).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Super Transform**, choose **Contact**, add **Last Name** **equals** `Sttest`, choose **First Name**, and open **Action**. | The actions are **Set To**, **Clear**, **Copy From Another Field**, **Change With Steps** and **Fix Name Capitals**. |
| 2 | Choose **Fix Name Capitals**. | **Action** shows **Change With Steps**, with two steps already filled in: remove extra spaces, and capitalize each word. |
| 3 | Press **Preview**, then **Run Super Transform** and **Run**. | The preview showed `  ana ` changing to `Ana`. After the run the contact's **First Name** is `Ana`. Undo it under **Data Jobs**. |
| 4 | Log in as the user with **BarnCRM Find and Export** only and open **Super Transform** (App Launcher). | If the tab is shown, it says Super Transform is not turned on for them, with the permissions to ask for, and no error. |

**Cleanup:** delete the Sttest contact.
