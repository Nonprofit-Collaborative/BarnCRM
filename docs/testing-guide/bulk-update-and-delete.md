# Super Transformer and Bulk Delete

Scripts for changing and deleting the records a Find query returns, editing in Find's table, deleting by file, undo, and the permissions behind them. Setup detail: [Super Transformer runs and undo](../admin-guide/bulk-update.md) and [Bulk delete](../admin-guide/bulk-delete.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest, so every query names only fixture contacts. Check the preview count before you confirm any bulk step: 3 for Zztest, 3 for Bulkdeltest. If it is higher, cancel. The **Data Manager** feature must be on (BarnCRM Settings, **General**). These scripts assume people are stored as contacts.

**Bulk Delete Records is in no role, not even BarnCRM Admin.** For the delete scripts, give admin the **BarnCRM Bulk Delete** extra permission first: BarnCRM Settings, **Access**, **Extra Permissions** (see [Access](../admin-guide/access.md)).

Test contacts for the delete scripts: create three contacts with first names `Del1`, `Del2`, `Del3` and last name `Bulkdeltest` (each gets a household of its own).

## T-BULK-01: Set a Field on Every Record a Query Returns

**Purpose:** confirm the main Super Transformer path from Find: preview with before and after, typed count, run and summary.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)); the Garcia contacts have an empty **Title**.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Find**. Choose **Contact**, add **First Name**, **Last Name** and **Title**, add the condition **Last Name** **equals** `Garcia`, and select **Run**. | The Garcia contacts are listed. Note the count N from "N rows found." |
| 2 | Open **Change Records** and choose **Super Transformer**. | The **Super Transformer** tab opens already filled in: **1. Kind of Record** reads **Contact**, **2. Which Records** shows the condition **Last Name** **equals** `Garcia`, **Matching Records** shows N, and a notice reads "Find handed over its kind of record and conditions. Choose what to change, then preview. Nothing has changed yet." Nothing has run. |
| 3 | Under **3. What to Change**, choose **Title** in **Field**, keep **Set To** in **Action**, and type `test title` in **New Value**. | The change is complete. **Add a Field** is enabled. |
| 4 | Select **Preview**. | "N records match. The first N, before and after:" and a table with **Record** and **Title**: each **Title** cell shows "(blank)", an arrow, then `test title`. The table scrolls sideways on a phone instead of stacking. |
| 5 | Select **Run Super Transformer**, then **Cancel**. | A confirmation reads "Change Title on N Contacts." Nothing changed. |
| 6 | Select **Run Super Transformer** again, then **Run**. Over 200 records the box also asks you to type the number; type a different number first. | With a wrong number **Run** stays disabled. When it is accepted, "Super Transformer started. It keeps running if you leave this page." then a bar with "Updating: N% done." (a percent, never parts of a batch). |
| 7 | Wait for it to finish. | "N matched: N updated, 0 already held the new values, 0 failed." and "To undo this run, press Undo on it under Data Jobs below." |
| 8 | Go back to Find and select **Run** again. | Every Garcia contact's **Title** reads `test title`. |

**Cleanup:** keep the job for T-BULK-02, which undoes it.

## T-BULK-02: Undo a Super Transformer Run

**Purpose:** confirm undo puts back every value nobody changed since, and keeps a value somebody did change.
**Prerequisites:** admin; the Super Transformer run from T-BULK-01, not yet undone.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Harper Garcia and change **Title** to `Changed by hand`. Save. | Saved. |
| 2 | Open the **Data Manager** tab. In **Data Jobs**, choose **Super Transformer runs** in **Show**. | The Super Transformer run is listed first with "N matched: N updated, 0 already held the new values, 0 failed.", **Started**, **Can be undone until**, and **Undo**. |
| 3 | Select **Undo**. | "Undo puts back the values on N records, except any somebody changed since. Type N to confirm." with **Cancel** and **Undo Super Transformer Run** (disabled). |
| 4 | Type N and select **Undo Super Transformer Run**. | "The undo started. Press Refresh to see when it has finished." |
| 5 | Select **Refresh** until the job's status reads **Undone**. | **Undone**; **Undo** is no longer offered. |
| 6 | Run the Find query from T-BULK-01 again. | Every Garcia **Title** is empty again, except Harper Garcia's, which still reads `Changed by hand`. |

**Cleanup:** clear Harper Garcia's **Title**.

## T-BULK-03: Super Transformer Refusals

**Purpose:** confirm bad changes and a stale count are refused before anything changes.
**Prerequisites:** admin; Find open on the Garcia query from T-BULK-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **Super Transformer**. Choose **Last Name**, **Clear**, and select **Preview**. | Refused: "Last Name is required, so it cannot be cleared." Nothing changes. |
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
| 2 | Select **Super Transformer**. Choose **Title**, **Change with steps**, select **Add a Change** and choose **Capitalize each word**. Select **Preview**. | "2 records match..." with **Before** `assistant coach` and **After** `Assistant Coach`. |
| 3 | Type `2` and select **Update 2 records**. | "2 matched: 2 updated, 0 already held the new values, 0 failed." Both titles read `Assistant Coach`. |
| 4 | In Find, query **Account** where **Account Name** **equals** `The Garcia Family` and **Run**. Select **Super Transformer**, choose **Account Name**, **Set to a value**, `Renamed Household`, **Preview**, type `1`, and select **Update 1 records**. | The summary counts 1 failed, listed under **Records that failed, and why** with "This is a household, and household naming keeps its name, so it was left as it was. To name it yourself, check Custom name on the household." |
| 5 | Open The Garcia Family. | The name is unchanged. |

**Cleanup:** undo the title Super Transformer run from **Data Jobs** (or clear both titles by hand).

## T-BULK-05: Edit in Find's Table, and Undo

**Purpose:** confirm inline edits are saved as a data job that can be undone.
**Prerequisites:** admin (BarnCRM Admin holds Bulk Update Records).

| Step | Action | Expected result |
|---|---|---|
| 1 | In Find, run the Garcia Contact query with the **Title** column. | Editable cells show a pencil. |
| 2 | Double-click Luis Garcia's **Title**, type `Inline edit`, and select **Save** at the foot of the table. | "Saved 1 records. 0 already held the values. Undo from Data Jobs on the Data Manager tab." |
| 3 | Open the **Data Manager** tab, **Data Jobs**. | A Super Transformer run is listed first; its run log on the Data Job record starts "Edited in Find". |
| 4 | Select **Undo**, type `1`, and select **Undo Super Transformer Run**. **Refresh** until **Undone**. | Luis Garcia's **Title** is empty again. |

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
| 6 | Type `3` and select **Delete 3 records**. | "The bulk delete started..." then "Deleting: N% done." and finally "3 matched: 3 deleted, 0 refused." with "To bring these records back, use Undo next to the job under Data Jobs on the Data Manager tab." |
| 7 | Run the Find query again. | "No records match these conditions." Their three households still exist (emptied households are kept). |
| 8 | Open **Data Manager**, **Data Jobs**, choose **Bulk deletes** in **Show**, and select **Undo** beside the job. | "Undo brings back 3 records from the Recycle Bin, except any no longer there. Type 3 to confirm." |
| 9 | Type `3`, select **Undo Bulk Delete**, and **Refresh** until **Undone**. | **Undone**. |
| 10 | Run the Find query again. | Del1, Del2 and Del3 are back, each in their household. |
| 11 | Change the query to match one contact (**First Name** equals `Del1`), **Run**, and select **Preview** in a new Bulk Delete panel. | The line reads "1 Contact matches. It is:". The related-records badges list BarnCRM's kinds first and no Share, History or Feed kinds; a long list ends with "and N more kinds". |
| 12 | Change the query to match nobody (**First Name** equals `Nobodyhere`) and **Preview**. | **No Records Match** (or "No records match this query, so there is nothing to delete."), with no list, download, confirm box or **Delete** button. |

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

**Purpose:** confirm Load one object's Delete by record ID previews a file, then deletes and can be undone like a bulk delete.
**Prerequisites:** admin with **BarnCRM Bulk Delete**; the record ID of Del1 (from its address bar) saved as a CSV `delete-ids.csv` with heading `Id` and that one ID.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Super Importer** tab (Data Manager, **Import a File**, **Open**). Under **What Are You Importing?**, choose **Delete the Records a File Lists**, choose **Contact**, name the template `Test delete by file`, and select **Create**. | The new template is chosen, already on **Delete by record ID**, and the line under it reads "Deletes: Contact". |
| 2 | Select **Next**, upload `delete-ids.csv`, map **Id** to **Salesforce record ID** if needed, and select **Next**. | **What each row does** includes **Delete by record ID**, with its risk text ending "undo from Data Jobs on the Data Manager tab within 15 days." |
| 3 | Choose **Delete by record ID** and select **Preview**. | The preview finds 1 record. A delete panel opens: "Delete every record the preview found, with your own access..." with **Download these records first**, **Type the number of records to confirm** and the delete button. |
| 4 | Type `1` and select **Delete 1 records**. | "1 matched: 1 deleted, 0 refused." Del1 is gone; Del2 and Del3 remain. |
| 5 | Undo the job from **Data Jobs** on the **Data Manager** tab (type `1`, **Undo Bulk Delete**, **Refresh**). | **Undone**. Del1 is back. |
| 6 | On the **Super Importer** tab, check **Recent Imports**. | The import's own Undo never undoes a delete: the job is either not offered there, or its Undo is refused with "This is a bulk delete. Undo it from Data Jobs on the Data Manager tab, which brings the records back from the Recycle Bin." |

**Cleanup:** delete the three `Bulkdeltest` contacts and their households; remove **BarnCRM Bulk Delete** from admin.

## T-BULK-09: Permissions and Tabs

**Purpose:** confirm the **BarnCRM Bulk Update** and **BarnCRM Bulk Delete** permission sets, and that the BarnCRM Tab sets follow them.
**Prerequisites:** admin; staff and read-only with no extra permissions.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin (without **BarnCRM Bulk Delete**), run any Find query. | **Super Transformer** is offered; **Bulk Delete** is not. |
| 2 | Log in as read-only. Search the App Launcher for "Find", "Super Transformer" and "Data Manager". | None of these BarnCRM tabs is found. |
| 3 | As admin, on **Access**, give staff **BarnCRM Find and Export** only. Log in as staff and run a Find query. | Neither **Super Transformer** nor **Bulk Delete** is offered. No **Super Transformer** tab in the App Launcher. |
| 4 | As admin, give staff **BarnCRM Bulk Update** as well. Log in as staff and run a Find query. | **Super Transformer** is offered in the **Change Records** menu, and the **Super Transformer** tab is available. |
| 5 | As staff, open the **Super Transformer** tab. | The five Super Transformer steps, then **Data Jobs** with "Start a change with Super Transformer above, or from a saved query in Find (Change Records, Super Transformer). Recent Super Transformer runs and their undo are listed here." and **Open Find**. Only staff's own jobs are listed; **Show everyone's jobs** is not offered. |
| 6 | As admin, open the **Super Transformer** tab. | **Show everyone's jobs** is offered; ticking it lists other people's jobs too. |
| 7 | As admin, give staff **BarnCRM Bulk Delete**. Log in as staff and run a Find query. | **Bulk Delete** is offered. On **Access**, the Bulk Delete give step showed the warning "This permission lets the person remove data. Give it only to someone you trust to do that." |
| 8 | As admin, in Setup, open staff's user and check **Permission Set Assignments**. | **BarnCRM Auto: Bulk Update Tab**, **BarnCRM Auto: Find Tab** and **BarnCRM Auto: Data Manager Tab** are assigned (given by BarnCRM, not by hand). |
| 9 | As admin, remove **BarnCRM Bulk Update**, **BarnCRM Bulk Delete** and **BarnCRM Find and Export** from staff on **Access**. Log in as staff. | The **Find**, **Super Transformer** and **Data Manager** tabs are gone. |
| 10 | As admin, give staff **BarnCRM Bulk Update** only (no Find and Export). Wait a minute. Log in as staff, open **Find** and run a query. | The **Find** tab is there, the query runs and **Super Transformer** is offered in **Change Records**: Bulk Update includes Find and Export. |
| 11 | As admin, remove **BarnCRM Bulk Update** from staff. | Staff is back to no extra permissions. |

**Cleanup:** none (step 11 resets staff).

## T-BULK-10: The Bulk Path from Data Manager

**Purpose:** confirm the way into Super Transformer and Bulk Delete is obvious, and each panel shows its steps.
**Prerequisites:** admin with **BarnCRM Bulk Delete**; sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Data Manager** and choose the **Super Transformer** tile. | The **Super Transformer** tab opens on **1. Kind of Record**, with no Find note. On a first visit a tip "Bulk Changes Start Here" says to start from Find only for a saved query. Go back. |
| 2 | Open **Find**. Choose **Contact**, add **Title**, add the condition **Last Name** **equals** `Garcia`, select **Run**, then **Change Records**, **Super Transformer**. | The **Super Transformer** tab opens with **Contact** and the Garcia condition already filled in, and nothing run. There is no second bulk update panel in Find. |
| 3 | Choose **Title**, keep **Set To**, type `x`, and select **Preview**. | A before and after table shows. Go back to Find without running; nothing changed. |
| 4 | Choose **Change Records**, **Bulk Delete**, then **Preview**. | The **Bulk Delete** panel's path **Preview**, **Confirm**, **Run** is on **Confirm**. Any related records deleted with them show as badges. **Download a Backup First** has an info icon whose popover says what the file holds. Select **Close** without typing the count. |
| 5 | Open **Data Manager**, choose the **Delete Many Records** tile, then **Continue**. | **Find** opens with "Bulk Delete starts here: find the records, press Run, then choose Change Records, Bulk Delete." |
| 6 | On **Data Manager**, under **Data Jobs**, select **Open Find**. | **Find** opens with a note: "Super Transformer can start here: find the records, press Run, then choose Change Records, Super Transformer." (the way to start from a saved query) |

**Cleanup:** none (nothing was changed or deleted).

## T-BULK-11: Super Transformer from Start to Undo

**Purpose:** confirm the five Super Transformer steps: live count, typed value inputs, preview with highlighted changes, confirmation, run and undo. Setup detail: [Super Transformer](../admin-guide/super-transform.md).
**Prerequisites:** admin; the Garcia contacts have an empty **Title**.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Super Transformer** tab. | The tab reads **Super Transformer**. Five numbered steps show above **Data Jobs**: **1. Kind of Record**, **2. Which Records**, **3. What to Change**, **4. Preview**, **5. Run**. Steps 2 and 3 say "Choose a kind of record first." **Preview** and **Run Super Transformer** are disabled. |
| 2 | Type `cont` in **Search Kinds of Record**, then open **Kind of record**. | Only kinds of record whose name contains "cont" are listed. No BarnCRM bookkeeping object (Data Job, Error Log) is offered anywhere in the list. Choose **Contact**. |
| 3 | Wait a moment without adding a condition. | **Matching Records** shows the number of contacts with an **Every Record** badge, and a warning: "No condition is set. This changes every Contact: N records." |
| 4 | Add the condition **Last Name** **equals** `Garcia`. | After about half a second the count changes to the number of Garcia contacts (note it as N) and the warning goes away. |
| 5 | Under **3. What to Change**, choose **Title**, keep **Set To**, and type `st test`. Then press **Add a Field**, choose a picklist field (for example **Salutation**). | The second row's **New Value** is a dropdown of the picklist's values. Remove the second row with its delete icon. |
| 6 | Press **Preview**. | "N records match. The first N, before and after:" and a table with **Record** and **Title**. Every **Title** cell is shaded and reads "(blank)", an arrow, then `st test` in bold. "0 of the N records shown already have these values and will not be saved." |
| 7 | Change **New Value** to `st test2`. | The preview table disappears and **Run Super Transformer** is disabled until you press **Preview** again. Press **Preview**. |
| 8 | Press **Run Super Transformer**, then **Cancel**. | The confirmation read "Change Title on N Contacts." Nothing changed. |
| 9 | Press **Run Super Transformer**, then **Run**. | "Super Transformer started. It keeps running if you leave this page." then a progress bar, then "N matched: N updated, 0 already held the new values, 0 failed." and "To undo this run, press Undo on it under Data Jobs below." |
| 10 | Reload the page. Under **Data Jobs**, press **Undo** on the newest Super Transformer run, type the number and confirm. | When the undo finishes, every Garcia contact's **Title** is empty again. |

**Cleanup:** none (the undo put the titles back).

## T-BULK-12: Super Transformer Warnings and Typed Confirmation

**Purpose:** confirm the run limit warning, the typed confirmation over 200 records, and that values already held are shown as unchanged.
**Prerequisites:** admin; sample data loaded (more than 200 contacts).

| Step | Action | Expected result |
|---|---|---|
| 1 | In BarnCRM Settings, **Import**, set **Super Transformer run limit** to `10`. Open **Super Transformer**, choose **Contact**, with no condition. | **Matching Records** shows 11 with an **Over the Limit** badge and a warning that more records match than the 10 one run may change. **Preview** is disabled. |
| 2 | Set **Super Transformer run limit** back to `48000` and reload **Super Transformer**. Choose **Contact**, choose **Title**, **Set To**, type `x`, and press **Preview**. | The table lists 25 contacts. |
| 3 | Press **Run Super Transformer**. | The confirmation has a field "Type N to confirm" (N is the count), and **Run** stays disabled until N is typed. Press **Cancel**. |
| 4 | Add the condition **Last Name** **equals** `Garcia`, choose **Title** **Clear**, and press **Preview**. | Every **Title** cell that is already empty is not shaded and shows only "(blank)"; the line under the table counts them. |

**Cleanup:** check **Super Transformer run limit** reads 48,000.

## T-BULK-13: Super Transformer Steps and Permissions

**Purpose:** confirm Change With Steps, Fix Name Capitals and the message for a person without the permissions.
**Prerequisites:** admin; a contact with **First Name** `  ana ` and **Last Name** `Sttest`; a user with **BarnCRM Find and Export** only (see [Test users](before-you-test.md#test-users)).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Super Transformer**, choose **Contact**, add **Last Name** **equals** `Sttest`, choose **First Name**, and open **Action**. | The actions are **Set To**, **Clear**, **Copy From Another Field**, **Change With Steps**, **Fix Name Capitals** and **Format Phone Number**. |
| 2 | Choose **Fix Name Capitals**. | **Action** shows **Change With Steps**, with two steps already filled in: remove extra spaces, and capitalize each word. |
| 3 | Press **Preview**, then **Run Super Transformer** and **Run**. | The preview showed `  ana ` changing to `Ana`. After the run the contact's **First Name** is `Ana`. Undo it under **Data Jobs**. |
| 4 | Log in as the user with **BarnCRM Find and Export** only and open **Super Transformer** (App Launcher). | If the tab is shown, it says Super Transformer is not turned on for them, with the permissions to ask for, and no error. |

**Cleanup:** delete the Sttest contact.

## T-BULK-14: Super Transformer Saved Step Lists

**Purpose:** confirm a Super Transformer can be saved by name, loaded, renamed and deleted, org-wide. Setup detail: [Super Transformer](../admin-guide/super-transform.md), section 5.
**Prerequisites:** admin; a second user holding **BarnCRM Find and Export** and **BarnCRM Bulk Update** (see [Test users](before-you-test.md#test-users)); no saved list named `Sttest list` yet.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Super Transformer**. | The **Saved Step Lists** card is at the top, saying "No lists are saved yet." (or listing existing lists). **Save as New List**, **Load List**, **Rename List** and **Delete List** are disabled. |
| 2 | Choose **Contact**, add **Last Name** **equals** `Sttest`, choose **First Name**, choose **Fix Name Capitals**. Type `Sttest list` in **List Name**. | **Save as New List** is enabled. |
| 3 | Press **Save as New List**. | "Saved the list Sttest list." **Saved List** now offers "Sttest list (Contact)" and has it chosen. |
| 4 | Type `Sttest list` again and press **Save as New List** a second time. | A red message says a saved list named Sttest list already exists. No second list appears. |
| 5 | Choose **Account** under **1. Kind of Record** (the changes clear). Choose **Sttest list** in **Saved List** and press **Load List**. | "Loaded the list Sttest list." The kind of record is **Contact**, the condition **Last Name** **equals** `Sttest` is back, and **First Name** shows **Change With Steps** with the two name steps. **Matching Records** counts again. Nothing has run. |
| 6 | Press **Preview** and check the table, but do not run. | The preview works as for any other change; no record has changed. |
| 6a | Create a text field `Sttest_Temp__c` on Contact (Setup, Object Manager). In **Super Transformer** add the conditions **Last Name** **equals** `Sttest` and **Sttest Temp** **equals** `x`, save the list as `Sttest stale`, then delete the field in Setup and reload **Super Transformer**. Choose **Contact** and press **Preview** on any change first, so the page is filled in, then load **Sttest stale**. | The list is not loaded: a red message says the list Sttest stale was not loaded because its conditions use fields that are gone or that you cannot read, naming `Sttest_Temp__c`, and to edit or delete the saved list. The page, its object, conditions and changes are exactly as you left them. Delete **Sttest stale** afterwards. |
| 7 | Log in as the second user, open **Super Transformer**. | **Sttest list (Contact)** is offered. Choose it, type `Sttest names` in **List Name** and press **Rename List**: "Renamed the list to Sttest names." |
| 8 | Back as admin, reload **Super Transformer**. | The list is now **Sttest names (Contact)**. |
| 9 | Choose it and press **Delete List**, then **Cancel**. | Nothing is deleted. |
| 10 | Press **Delete List** again and confirm. | "Deleted the list Sttest names." The card says no lists are saved. Contacts are unchanged. |

**Cleanup:** delete the Sttest contact.

## T-BULK-15: Format Phone Number and the Format Digits Step

**Purpose:** confirm the one-click phone format and the Format digits step on phone values with a country code and an extension.
**Prerequisites:** admin; five contacts with last name `Phtest` and **Phone** values `5551234567`, `1-555-123-4567`, `+1 (555) 123-4567 ext. 12`, `555-1234` and `call the office`. Setup detail: [Super Transformer](../admin-guide/super-transform.md), section 6.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Super Transformer**, choose **Contact**, add **Last Name** **equals** `Phtest`, choose **Phone**, and open **Action**. | The actions include **Format Phone Number**. |
| 2 | Choose **Format Phone Number**. | **Action** shows **Change With Steps** with one step, **Format digits**, **Pattern** `(###) ###-####` and **Country code to drop** `1`. |
| 3 | Press **Preview**. | After values: `(555) 123-4567`, `(555) 123-4567`, `(555) 123-4567 x12`, `555-1234` (unchanged, not highlighted) and `call the office` (unchanged, not highlighted). |
| 4 | Change **Pattern** to `###-###-####` and clear **Country code to drop**. Press **Preview**. | `5551234567` becomes `555-123-4567`. `1-555-123-4567` is now unchanged (eleven digits and no country code to drop). |
| 5 | Set **Country code to drop** back to `1`, press **Preview**, then **Run Super Transformer** and **Run**. | Three phones are updated to `(555) 123-4567` form (the third with ` x12`); two are unchanged. Undo the run under **Data Jobs**; the original phones return. |

**Cleanup:** delete the Phtest contacts.

## T-BULK-16: Archive by Query

**Purpose:** confirm an archive saves every matching record to Files before deleting, deletes only what is in the file, and empties the Recycle Bin only after the second typed count.
**Prerequisites:** admin with **BarnCRM Bulk Delete**; four contacts with Last Name `Arctest` (First Name Arc1 to Arc4). Not on mwdbdevsb.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Org Optimizer**, **Storage and Limits**, and select **Archive Records**. | Find opens with a note that the Change Records menu offers Archive Records. As a user without BarnCRM Bulk Delete the button is not shown. |
| 2 | Query **Contact** where **Last Name** **equals** `Arctest` and **First Name** **not equal to** `Arc4`, **Run**, open **Change Records** and choose **Archive Records**. | A panel **Archive Records** with **Preview**, **Confirm**, **Run**, and no **Download a Backup First** button. |
| 3 | **Preview**, type `3`, and select **Archive and Delete 3 Records**. | The progress shows the file being saved, then the delete; finally "3 matched: 3 deleted, 0 refused." Two notifications: the file is saved, and the delete finished. |
| 4 | Open **Files**. | A file `Contact-<today>-<tag>-part-1` owned by you: a heading row of field API names (`Id`, `FirstName`, `LastName` and the rest you can read) and three rows. |
| 5 | Open **Data Manager**, **Data Jobs**, and **Undo** the job. | The three contacts come back. |
| 6 | Run the query again, choose **Archive Records**, **Preview**, type `3`, tick **Also empty them from the Recycle Bin**. | A warning that this cannot be undone, and a second box **Type the number again to empty the Recycle Bin**; the start button stays disabled until it holds `3`. |
| 7 | Type `3` in the second box and start. When it finishes, open **Data Jobs**. | The job shows 3 deleted and no **Undo**. Its run log says the records were emptied from the Recycle Bin. The Recycle Bin does not list them. |
| 8 | On the **Super Importer** tab, **Load one object**, **Contact**, insert, with the step 7 file. | Every column with a field you can create maps by its heading; the three contacts come back as new records. |

**Cleanup:** delete the Arctest contacts, their households and the archive files.

## T-BULK-17: Backup Sets

**Purpose:** confirm a Backup Set saves every matching record to Files, deletes nothing, is listed as a run, and its file puts values back through Load one object.
**Prerequisites:** admin (BarnCRM Admin); three contacts with Last Name `Baktest` and Title `Before`; a saved Find query `Baktest people` (Contact, Last Name equals `Baktest`). A second user with only **BarnCRM Find and Export**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Data Manager**. As the second user, open it too. | The admin sees a **Backup Sets** tile under **Find and Change**; the second user does not. |
| 2 | As the admin, select **Backup Sets**. | The tiles are replaced by the Backup Sets panel with **Back to Data Manager** above it; "No Backup Sets yet", and **Add a Backup Set** offers `Baktest people`. |
| 3 | Choose `Baktest people` and press **Add**, then **Run Now**. | The set is listed; "Run started" shows and **Recent Runs** lists the run as Committing, then Complete with 3 records and a file name. A notification opens the file. |
| 4 | Select the file name. | A file `Contact-<today>-<tag>-part-1` owned by you: a heading row of field API names (`Id` first) and three rows with every field you can read. The three contacts are unchanged. |
| 5 | Open **Data Jobs** (Data Manager, Back). Filter by **Backup Set runs**. | The run is listed with "3 records saved to Files." and no **Undo**. It is not in the import history on the **Super Importer** tab. |
| 6 | In Find, open `Baktest people`, change a column, and **Save**. Reopen Backup Sets. | `Baktest people` is still a Backup Set. |
| 7 | Change the three contacts' Title to `After`. On the **Super Importer** tab choose **One Kind of Record**, **Contact**, **Update by record ID**, and load the step 4 file with only the **Id** and **Title** columns mapped. | The preview shows three updates to `Before`; after the load the three contacts' Title is `Before`. |
| 8 | In Backup Sets, press **Remove** beside `Baktest people`. | It moves back to **Add a Backup Set**; the saved query and the run's file remain. |

**Cleanup:** delete the Baktest contacts, their households, the saved query and the run's file.

## T-BULK-18: Apply a Map and Copy With Steps

**Purpose:** confirm **Apply a Map** fills the changes from a saved map from a kind of record to itself, and that **Copy From Another Field** takes steps (MAP-06).
**Prerequisites:** admin; two contacts with last name `Maptest` and an empty **Description**. In **Data Manager**, **Saved Maps**, a map `Contact tidy` **From** a record of kind **Contact** **To** a record of kind **Contact**: **Description** gets **Last Name** with **All capitals**, **Title** **Always Use** `Volunteer`, **Department** **When Blank, Use** `None`. Setup detail: [Super Transformer](../admin-guide/super-transform.md), section 1, and [The Mapper and Saved Maps](../admin-guide/mapper.md), section 6.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Super Transformer**, choose **Contact**, add **Last Name** **equals** `Maptest`. | **3. What to Change** shows **Apply a Map**, listing **Contact tidy**. |
| 2 | Choose **Contact tidy** and press **Apply Map**. | Three rows: **Description** **Copy From Another Field** **Last Name** with the step **All capitals**; **Title** **Set To** `Volunteer`; **Department** **Change With Steps** with a **Value when empty** step `None`. A notice says the changes came from the map. |
| 3 | Press **Preview**. | **Description** goes to `MAPTEST`, **Title** to `Volunteer` and an empty **Department** to `None`. |
| 4 | Choose **Account** in **1. Kind of Record**. | **Contact tidy** is not offered. |
| 5 | Choose **Contact** again, set up the condition, choose **Description**, **Copy From Another Field**, **First Name**. | No step list shows, only **Add Changes** under the row. |
| 6 | Press **Add Changes**, add **All lower case** and press **Preview**. | The description is each contact's first name in lower case. |
| 7 | Choose **Contact tidy** and press **Apply Map**. | A confirmation says the map replaces the changes already chosen. **Cancel** keeps the **Description** row as it was. |

**Cleanup:** delete the Maptest contacts and the **Contact tidy** map.

## T-BULK-19: Scheduled Backup Sets

**Purpose:** confirm a Backup Set's schedule is saved and kept, the nightly Backup Sets step starts only the sets due, and a scheduled set keeps only its newest runs' files.
**Prerequisites:** T-BULK-17's admin, contacts and saved query `Baktest people` added to Backup Sets; the nightly jobs scheduled (BarnCRM Settings, General, Nightly Jobs). A second saved query `Baktest other` added to Backup Sets. In BarnCRM Settings, Import, **Backup Runs Kept** set to 2.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Backup Sets. | Each set shows "Not scheduled". **Edit Schedule** shows beside your own sets only. |
| 2 | Press **Edit Schedule** beside `Baktest people`, choose **Weekly**, then today's day of the week, and **Save Schedule**. | "Schedule saved."; the set shows "Weekly on" today's day. A note says scheduled sets run at 2:00 AM and keep the files of their newest 2 runs. |
| 3 | Give `Baktest other` **Weekly** on tomorrow's day of the week. In Find, open `Baktest people`, change a column and **Save**. Reopen Backup Sets. | `Baktest people` still shows its weekly schedule. |
| 4 | In BarnCRM Settings, General, Nightly Jobs, press **Run Now** on **Backup Sets** if offered, or wait for the next night's run. | One new run of `Baktest people` only; its log says "Started by its weekly schedule." `Baktest other` did not run. |
| 5 | Press **Run Now** on `Baktest people` twice, waiting for each to complete. | After the second, **Recent Runs** shows the oldest of the three runs with no file, and its log (Data Jobs) ends "Files removed: a scheduled set keeps the files of its newest 2 runs." Its file is gone from Files; the two newest files remain. |
| 6 | Turn the nightly jobs' **Backup Sets** step off. Reopen Backup Sets. | A warning says the nightly jobs are not scheduled or their Backup Sets step is off. Turn the step back on. |
| 7 | **Edit Schedule** on `Baktest people`, choose **Not scheduled**, **Save Schedule**, then **Run Now** twice. | Every run keeps its file: a set run only on demand keeps every file. |

**Cleanup:** delete the runs' files and `Baktest other`; set **Backup Runs Kept** back to 7; then T-BULK-17's cleanup.

## T-BULK-20: Off-Platform Backups and Archives

**Purpose:** confirm the backup destination is offered only with a destination installed, a run's files are sent and kept or removed as set, a refused file waits and is sent again, and an archive deletes only after its file was accepted.
**Prerequisites:** T-BULK-17's admin and `Baktest people` Backup Set. For steps 2 to 7: BarnCRM Connector with a connection set as the **Backup Destination** to a test HTTPS endpoint you can watch (T-CN-35 in the Connector testing guide sets one up), and BarnCRM Connections given to the admin and the nightly jobs' user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Without BarnCRM Connector installed, open Backup Sets and press **Edit Schedule**. Open Find, archive any query (Data Manager, **Archive by Query**) up to **Preview**. | No **Save To** choice; a note says to install BarnCRM Connector and set up a backup destination. The archive panel shows the same note and no send option. |
| 2 | With the Connector set up, **Edit Schedule** on `Baktest people`, choose **Daily** and **Files and backup destination**, **Save Schedule**, then **Run Now**. | **Recent Runs** shows "Sending to backup destination", then "Sent to backup destination". The endpoint received one CSV file per part, named as in Files. The files are still in Files. |
| 3 | In BarnCRM Settings, Import, turn on **Remove Files Copy After Sending**. **Run Now** again. | Once sent, the run's file link is gone and its log says the files were removed from Files. |
| 4 | Make the endpoint refuse uploads (or point the connection's path at a place it refuses). **Run Now**. | The run shows "Not all sent: the next scheduled run tries again"; the Error Log has an Error naming the file and the endpoint's answer; the file stays in Files even with step 3's setting on. |
| 5 | Let the endpoint accept uploads again. In BarnCRM Settings, General, Nightly Jobs, **Run Now** on **Backup Sets**. | The waiting run becomes "Sent to backup destination". |
| 6 | Archive three test contacts with **Send the file to your backup destination before deleting** ticked while the endpoint refuses uploads. | The job ends **Failed**; its log says the file was not sent so nothing was deleted; the three contacts remain; the file is in Files. |
| 7 | Repeat step 6 with the endpoint accepting uploads. | The log says the files were sent, then the delete runs and the three contacts are deleted. |

**Cleanup:** turn **Remove Files Copy After Sending** off; set `Baktest people` back to **Not scheduled** and **Files**; delete the endpoint's test files and the runs' files; then T-BULK-17's cleanup.
## T-BULK-21: Archive Rules to the Big Object

**Purpose:** confirm an archive rule copies records into the Archived Record big object before deleting them, keeps records changed during the run, counts archived rows, runs on its schedule, and skips a scheduled rule whose owner lost access (AR-10, AR-11). A record given a related record between its copy and its delete is kept live (AR-12); the Apex tests cover that timing.
**Prerequisites:** run in barn-platform (Platform-only). Admin with the **BarnCRM Admin** permission set; four contacts with Last Name `Arcbig` (First Name Big1 to Big4); a saved Find query `Arcbig people` (Contact, Last Name equals `Arcbig`). A second user with only **BarnCRM Find and Export**. Setup detail: [Archive Rules](../admin-guide/archive-rules.md).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Data Manager** as the admin, then as the second user. | The admin sees an **Archive Rules** tile under **Find and Change**; the second user does not. |
| 2 | As the admin, select **Archive Rules**. | The panel shows "No rules yet", the **Archived records** meter against the 1,000,000 included, and **Add a Rule** offering `Arcbig people`. |
| 3 | Choose `Arcbig people` and press **Add**. Set **Where Records Go** to **Off Platform** and press **Save**. | A message says no off-platform store is set up, and the rule is not saved. |
| 4 | Set **Where Records Go** to **Big Object**, **How Often** to **Only when I run it**, and press **Save**. | The rule is listed with "Only when run". |
| 5 | Press **Preview and Run**. | "4 Contacts match now", up to five sample names, and any related records deleted with them. **Run Now** stays disabled until **Number of records** holds `4`. |
| 6 | Type `4` and press **Run Now**. While it shows Running, change Big4's Title. | **Recent Runs** shows the run, then "3 moved, 1 left out"; its run log names Big4 as changed since the run started. If the run ends before the edit, all four move; repeat with a fresh Big4. |
| 7 | While the run in step 6 still shows Running, press **Preview and Run** on the rule again and type the count. | **Run Now** stays off, with "This rule is still running. Wait until its run under Recent Runs finishes, then run it again." Once the run ends, **Run Now** turns on again. |
| 8 | Run `Arcbig people` in Find. | Only Big4 is returned. The Recycle Bin holds Big1 to Big3. The meter counts 3 more archived records. |
| 9 | In the Developer Console, query `SELECT Object_Name__c, Original_Id__c, Record_Name__c FROM Archived_Record__b WHERE Object_Name__c = 'Contact'`. | Three rows, for Big1 to Big3. |
| 10 | **Edit** the rule, set **How Often** to **Weekly** and **Day** to today, and press **Save**. | A box asks for the current count, 1; another number is refused with "Nothing was saved". With `1` the rule shows "Weekly on" today. |
| 11 | In **BarnCRM Settings**, **General**, **Nightly Jobs**, find **Archive Rules**, then let the nightly run happen. | The step is listed and on. After the run, **Recent Runs** lists a run that moved Big4. |
| 12 | Change the owner of the saved query `Arcbig people` to the second user, then let the nightly run happen again. | **Recent Runs** (of the person who scheduled the nightly jobs) lists a **Failed** run of `Arcbig people` whose log says the scheduled run was skipped because its owner no longer holds the permissions, naming them. The Error Log has a Warning naming the rule. Nothing was archived. |
| 13 | Change the owner back to the admin. | The next nightly run starts the rule again. |
| 14 | Untick **Active**, type the count if asked, and **Save**. | The rule shows "(paused)" and the next nightly run starts nothing for it. |
| 15 | **Remove** the rule. | It moves back to **Add a Rule**; the saved query and the archived rows remain. |

**Cleanup:** none before T-BULK-22, which views, restores and erases these archived rows. Afterwards delete the Arcbig households and the saved query.

## T-BULK-22: Archived Records, Restore and Erasure

**Purpose:** confirm the Archived Records panel lists and shows archived rows only to holders of the grant, a restore creates records again with new Ids, leaves out lookups to records gone, removes the rows and lowers the count, a failed row stays archived, and erasing a person deletes the archived rows that name them (AR-10).
**Prerequisites:** run in barn-platform (Platform-only) right after T-BULK-21, with Big1 to Big4 archived. Before archiving, set Big1's **Reports To** to a contact `Arcboss Staff`, then delete `Arcboss Staff` after the archive run. The second user from T-BULK-21, and a third user with **BarnCRM Admin** but not **BarnCRM Bulk Delete**. Setup detail: [Archive Rules](../admin-guide/archive-rules.md#6-archived-records-looking-records-up).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Data Manager** as the second user. | No **Archived Records** tile. |
| 2 | As the admin, open **Org Optimizer**, **Storage and Limits**, and press **View Archived Records**. | Data Manager opens on the **Archived Records** panel, which says each archived record holds every field the archiving person could read. |
| 3 | Choose **Contact** and press **Show**. | Big1 to Big4 are listed newest first, with Original Id, Archived, Rule `Arcbig people` and Archived By. Setting **Archived From** and **Archived To** to yesterday and pressing **Show** lists nothing. |
| 4 | Press **View** on Big1. | Its fields (First Name Big1, Last Name Arcbig, Reports To Id and the others) are listed. |
| 5 | As the third user, open the panel and show Contact. | Rows show, but no tick boxes and no **Restore**. |
| 6 | As the admin, tick Big1 and Big2 and press **Restore 2**. Confirm. | The box says each record gets a new Id and what may be left out. A message says the restore started, and the page is read again with no row ticked. |
| 7 | At once, while that restore is still running, tick Big2 again (if it is still listed) and press **Restore 1**. Confirm. | Refused: "Some of these records are already being restored. Wait until that restore under Recent Runs finishes, then press Show to read the list again." No second restore is listed. If the first restore already ended, Big2 is no longer listed: note it and go on. |
| 8 | Open **Archive Rules**, **Recent Runs**. | A run named "Restore Contact" ends Complete; its log reads "Restored 003... as 003..." twice, "Left out of" Big1's old Id "ReportsToId", and "Moved 2 records back out of the archive; 0 stay archived". The meter counts 2 fewer. |
| 9 | Run `Arcbig people` in Find; then show Contact in **Archived Records** again. | Big1 and Big2 are back with new Ids (Big1 without Reports To). Only Big3 and Big4 remain archived. |
| 10 | As the admin, remove your create access to Contact's **Title** field in a permission set you hold, restore Big3, and put the access back. | Big3 is restored without its Title; the log lists Title as left out. |
| 11 | Create contacts `Arcerase Two` and `Arcerase Child` (Reports To `Arcerase Two`). Archive `Arcerase Child` with a saved query and a Big Object rule run once. On `Arcerase Two`, open **Erase a Person** and press **Preview**. | The preview lists **Archived records** as deleted. After the preview, **Archived Records** still lists the Arcerase Child row. |
| 12 | Erase `Arcerase Two`, wait a minute, and show Contact in **Archived Records**. | The Arcerase Child row is gone, and the meter counts 1 fewer. **Archive Rules**, **Recent Runs** lists "Erasure: removing archived records that name an erased person", Complete, with "Removed 1 archived records that named the erased person." and no name. |
| 13 | Start a restore of Big4, and in **Setup**, **Apex Jobs**, abort the queued `ArchiveRestoreJob` as soon as it shows, before the restore finishes. After the first nightly run at least 24 hours later, open **Recent Runs**. | The restore is **Failed** with a line saying the nightly run marked it failed and brought the archived record count up to date; the meter matches the rows **Archived Records** lists. (If the restore finished before the abort, repeat with another row.) |

**Cleanup:** delete the Arcbig and Arcerase contacts and households, the saved queries, and restore or `Database.deleteImmediate` any archived rows left.

## T-BULK-23: BarnCRM Archive Admin

**Purpose:** confirm someone who is not a BarnCRM Admin sees archived records only with BarnCRM Archive Admin, and with BarnCRM Bulk Delete too may run archive rules and restore, while BarnCRM Admins keep full access (AR-14, D-223).
**Prerequisites:** run in barn-platform. A contact `Arckeep One` archived to the big object by a Big Object rule run as the admin. A user `Arckeep Staff` with the **BarnCRM Staff** role and **BarnCRM Bulk Delete**, and no other extra permission. Setup detail: [Archive Rules](../admin-guide/archive-rules.md#who-can-see-archived-records).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Data Manager** as `Arckeep Staff`. | No **Archive Rules** and no **Archived Records** tile. |
| 2 | As the admin, open **Archive Rules**. | Under the intro, a note says who can see archived records, that each shows every field the archiving person could read, and to add BarnCRM Archive Admin on the Access page. |
| 3 | As the admin, open **Access**, choose `Arckeep Staff`, and add **BarnCRM Archive Admin** under **Extra Permissions**. | It is listed with its sentence; the person now holds it. |
| 4 | As `Arckeep Staff`, reload **Data Manager**. | **Archive Rules** and **Archived Records** tiles show. **Backup Sets** and **Import** do not. |
| 5 | Open **Archived Records**, choose **Contact**, press **Show**, and restore `Arckeep One`. | The row is listed; the restore starts and ends Complete under **Recent Runs**. |
| 6 | As the admin, remove **BarnCRM Bulk Delete** from `Arckeep Staff` on **Access**; as them, reload **Data Manager**. | **Archived Records** shows with no tick boxes and no **Restore**; **Archive Rules** is gone. |
| 7 | As the admin, open **Archived Records**. | Unchanged: the admin keeps full access without BarnCRM Archive Admin. |

**Cleanup:** remove BarnCRM Archive Admin from `Arckeep Staff`; delete `Arckeep One` and its saved query.

## T-BULK-24: A Backup Before Every Archive Run

**Purpose:** confirm every archive rule run first backs up its records, with their related records, and starts only once that backup is saved; and that Skip Backup Before Archive is confirmed, records who turned it on and when, and keeps that history when turned off (AR-15, D-223).
**Prerequisites:** run in barn-platform as an admin with BarnCRM Bulk Delete. Two contacts `Arcbak One` and `Arcbak Two`, each with one task, and a saved Find query `Arcbak` on Contact whose Last Name is `Arcbak`, made an archive rule with **Where Records Go** set to **Big Object**. Skip Backup Before Archive is off. Setup detail: [Archive Rules](../admin-guide/archive-rules.md#a-backup-before-every-run).

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Archive Rules**, press **Preview and Run** on `Arcbak`, type `2` and press **Run Now**. | The message says the backup is saved first. Until it is saved, **Run Now** stays off for the rule. |
| 2 | Open **Backup Sets** and look under **Recent Runs**. | A **Backup** run named `Arcbak` is Complete with 2 records; its log says the archive has started. Files holds a Contact file and a Task file for it. |
| 3 | Back in **Archive Rules**, wait for the run to end. | The Archive run is Complete with 2 records moved; its log says they were backed up first. Both contacts are in **Archived Records**. |
| 4 | In **BarnCRM Settings**, **Import**, tick **Skip Backup Before Archive**, then press **Cancel** in the dialog. | The dialog **Archive Without a Backup?** says it is riskier. After Cancel the box is unticked and nothing is saved. |
| 5 | Tick it again, press **Turn On**, then save. | The box stays ticked; under it: "Turned on by" your name with today's date and time. **Recent Changes** lists the change with your name. |
| 6 | Create `Arcbak Three`, then run `Arcbak` again. | No Backup run is added. The Archive run starts at once; its log says it started without a backup and who turned the setting on. |
| 7 | Untick **Skip Backup Before Archive** and save. | No dialog. The "Turned on by" line is gone; **Recent Changes** keeps both changes. |
| 8 | Edit the saved query `Arcbak` to use a field you then delete, and run the rule. | The backup fails; the rule's run is **Failed** with the reason, nothing is archived or deleted, and the Error Log has an entry from ArchiveBackupGate. |

**Cleanup:** restore or delete the archived `Arcbak` contacts, delete their backup files from Files, and remove the rule, saved query and test field.
