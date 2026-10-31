# Data Manager and Job History

Scripts for the Data Manager tab, the data job list and its undo, the Data Quality checks, field utilization and job notifications. Setup detail: [Data Manager](../admin-guide/data-manager.md), [Data Quality](../admin-guide/data-hygiene.md), [Field utilization](../admin-guide/field-utilization.md), [Job notifications](../admin-guide/job-notifications.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In **BarnCRM Settings**, **General**, the **Data Manager** and **Org Optimizer and Health Check** features are **On**.

## T-DM-01: Data Manager Shows Every Card to an Admin

**Purpose:** Confirm the Data Manager tab lists each tool, the import templates, the job list and Salesforce's own tools for an administrator.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | In the BarnCRM app, open the **Data Manager** tab. | The page name **Data Manager** shows once, in the page header with the tab icon, and no other icon or title repeats it. The line **Start a data task, or see and undo what changed.** is under it, then **About This Tool** (open on your first visit) with two short lines on which tool to use and a **Learn More** link. |
| 2 | Look at the tiles. | Four groups in this order: **Bring Data In** (**Import a File**), **Find and Change** (**Find and Export Records**, **Update Many Records**), **Check and Tidy** (**Org Optimizer**), **Careful** (**Delete Many Records**, alone and last). Each tile has an icon, its name and one line of 12 words or fewer; there are no **Open** buttons. **Update Many Records** reads "Find records, then change up to five fields at once." |
| 3 | Look around the tiles. | There is no warning box anywhere on the page. |
| 4 | Look under **Import Templates**. | The line "A template remembers how a file's columns match fields." with a **Learn More** link, then a table with the columns **Template**, **Loads**, **Arrives Regularly As**, **Last Loaded**, listing the shipped import templates. **Loads** reads **People and organizations** for the people templates, **Gifts** for a gift template, and a plural object name (for example **Accounts**) for a one-object template; never an API name such as `Account`. With no template at all it shows an illustration, **No Import Templates Yet**, and a **Create a Template** button that opens **Import**. |
| 5 | Look at the job list card. | It is headed **Data Jobs**, with a **Refresh** button, a **Show** list and a **Show everyone's jobs** checkbox. With no jobs run yet it shows an illustration, the heading **No Data Jobs Yet** and the line "Each import, bulk update and bulk delete is listed here, with its undo." |
| 6 | Look under **Salesforce's Own Tools**. | Three tiles: **Weekly Data Export**, **Recycle Bin**, **Data Import Wizard**, each with a small new-window icon after its name. |
| 7 | Click the **Recycle Bin** tile. | A new browser tab opens Salesforce's Recycle Bin. Close it. |
| 8 | Close **About This Tool** and reload the page. | It stays closed. |
| 9 | Check the app's navigation bar, in **BarnCRM** and in **BarnCRM Admin**. | **Data Manager** is there in both. **Find**, **Import** and **Bulk Update** are in neither. |

**Cleanup:** None.

## T-DM-02: Each Tile Opens Its Tool

**Purpose:** Confirm every tool tile goes to the right tab, by mouse and by keyboard.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Data Manager**, click **Import a File**. | The **Import** tab opens. |
| 2 | Go back to **Data Manager**. Press Tab until **Find and Export Records** has the focus ring, and press Enter. | The **Find** tab opens. |
| 3 | Go back. Click **Update Many Records**. | The **Super Transform** tab opens, with its five steps above **Data Jobs**. |
| 4 | Go back. Click **Org Optimizer**. | The **Org Optimizer** tab opens on **Overview**. |
| 5 | Go back. Click **Delete Many Records**. | A box titled **Delete Many Records** opens, reading "Deleted records go to the Recycle Bin. You can undo a bulk delete from Data Jobs, on this page, for up to 15 days.", with **Cancel** and a red **Continue** button. Nothing else has opened yet. |
| 6 | Click **Cancel**. | The box closes and **Data Manager** stays open. No tab opens. |
| 7 | Click **Delete Many Records** again, and press Escape. | The box closes and nothing opens. |
| 8 | Click **Delete Many Records** again, and click **Continue**. | The **Find** tab opens. |

**Cleanup:** None.

## T-DM-12: Find, Import and Bulk Update Open From Data Manager Only

**Purpose:** Confirm Find, Import and Bulk Update are not in any app's navigation, and open from their Data Manager tiles and from links elsewhere.
**Prerequisites:** admin, and staff with the **BarnCRM Find and Export** permission set.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open **BarnCRM**, **BarnCRM Console**, **BarnCRM Admin** and **BarnCRM Admin Console** in turn, and check each navigation bar or menu. | **Data Manager** is in all four. **Find**, **Import** and **Bulk Update** are in none. |
| 2 | In **BarnCRM**, open **Data Manager** and click **Find and Export Records**. | The **Find** tab opens and works: choose **Contact** and run a query. |
| 3 | In **BarnCRM Admin**, open **Data Manager** and click **Import a File**. | The **Import** tab opens on its first step. |
| 4 | Open **Org Optimizer**, and press **Open in Find** next to any check. | The **Find** tab opens with that check's query. |
| 5 | As staff, open **BarnCRM**. | **Data Manager** is in the navigation; **Find** is not. On **Data Manager**, the **Find and Export Records** tile opens Find. |

**Cleanup:** None.

## T-DM-03: A Bulk Update Appears in Data Jobs, with a Notification

**Purpose:** Confirm a bulk update is listed newest first with its counts, the filter works, and the starter gets one bell notification.
**Prerequisites:** admin. In **BarnCRM Settings**, **General**, **Tell people when their long jobs finish** is ticked.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Find**. Query Contact where Last Name equals `Whitfield` and run it. | 6 rows: the members of the **Staff Household**. |
| 2 | Press **Bulk Update** and set **Title** to `Test title` on all 6, confirming with the count (steps in [Bulk update](../admin-guide/bulk-update.md)). | The bulk update starts. |
| 3 | When it finishes, check the bell at the top of the page. | One new notification titled **Bulk update finished**, reading **6 updated, 0 already right, 0 no longer matched, 0 could not be saved. Open the bulk update for the run log.** |
| 4 | Click the notification. | The bulk update's **Data Job** record opens, with its run log. |
| 5 | Open **Data Manager** and press **Refresh** on **Data Jobs**. | The bulk update is first. Its title names the job, **Bulk Update**, **Contact** and its status; the line under it reads **6 matched: 6 updated, 0 already held the new values, 0 failed.**, followed by **Started** and **Can be undone until** with dates, and an **Undo** button. |
| 6 | In **Show**, choose **Imports**. | The bulk update is no longer listed. |
| 7 | In **Show**, choose **Bulk updates**, then **All**. | The bulk update is listed again each time. |

**Cleanup:** Leave the job for T-DM-04.

## T-DM-04: Undo a Bulk Update From Data Jobs

**Purpose:** Confirm the typed-count confirmation guards the undo and the values go back.
**Prerequisites:** admin; T-DM-03 done.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Data Manager**, under **Data Jobs**, press **Undo** beside the bulk update. | A box opens: **Undo puts back the values on 6 records, except any somebody changed since. Type 6 to confirm.**, with **Type the number of records to confirm**, **Cancel** and **Undo Bulk Update**. |
| 2 | Type `5`. | **Undo Bulk Update** stays disabled. |
| 3 | Press **Cancel**. | The box closes. Nothing is undone; the job still shows **Undo**. |
| 4 | Press **Undo** again, type `6`, press **Undo Bulk Update**. | A success message: **The undo started. Press Refresh to see when it has finished.** |
| 5 | Wait without pressing **Refresh**. | The job's status changes to undoing and then to undone on its own (the list refreshes while a job runs). **Undo** is no longer shown; the counts stay. |
| 6 | Open any Whitfield person. | **Title** is empty again. |
| 7 | Check the bell. | One notification titled **Bulk update undo finished**. |

**Cleanup:** None.

## T-DM-05: Undo a Bulk Delete From Data Jobs

**Purpose:** Confirm a bulk delete is listed and its undo brings the record back from the Recycle Bin.
**Prerequisites:** admin (holds **BarnCRM Bulk Delete** from the create script). Create a contact `Dana Deletetest`.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Find**, query Contact where Last Name equals `Deletetest`, run it, press **Bulk Delete** and confirm with the count (steps in [Bulk delete](../admin-guide/bulk-delete.md)). | 1 row is deleted. |
| 2 | Open **Data Manager**, press **Refresh**. | The bulk delete is first, reading **1 matched: 1 deleted, 0 refused.**, with **Undo**. |
| 3 | Press **Undo**. | **Undo brings back 1 records from the Recycle Bin, except any no longer there. Type 1 to confirm.** |
| 4 | Type `1` and press **Undo Bulk Delete**. | The undo starts; the job reaches undone on its own. |
| 5 | Search for `Dana Deletetest`. | The contact is back. |

**Cleanup:** Delete `Dana Deletetest`.

## T-DM-06: Who Sees Data Manager and What

**Purpose:** Confirm the tab, tiles and job kinds follow each person's permissions.
**Prerequisites:** staff; admin to give and take permissions.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the BarnCRM app. | No **Data Manager** and no **Org Optimizer** tab. |
| 2 | As admin, open **BarnCRM Settings**, **Access**. Under **Extra Permissions**, give the staff user **BarnCRM Find and Export** with **Give Permission**, and confirm. | A message says the staff user now has the permission. |
| 3 | As staff, wait a minute and reload. Open **Data Manager**. | The tab is there. Only two tiles: **Find and Export Records** under **Find and Change** and **Org Optimizer** under **Check and Tidy**. There is no **Bring Data In** or **Careful** group. |
| 4 | Look for **Import Templates**, **Data Jobs** and **Salesforce's Own Tools**. | None of them is shown. |
| 5 | As admin, also give the staff user **BarnCRM Bulk Update**. As staff, reload **Data Manager**. | A third tile, **Update Many Records**, appears after **Find and Export Records**, and **Data Jobs** appears with the line **Start a bulk update from Find: run a query, then press Bulk update. Recent bulk updates are listed here, with their undo.** There is no **Show** list (one kind of job only) and no **Show everyone's jobs**. |
| 6 | As staff, check whether the admin's bulk update from T-DM-03 is listed. | It is not: staff see their own jobs only. |

**Cleanup:** As admin, remove both extra permissions from the staff user on the **Access** page.

## T-DM-07: Data Quality Checks and Open in Find

**Purpose:** Confirm the Data Quality section counts each check and opens a check's records in Find.
**Prerequisites:** admin.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Org Optimizer** and choose **Data Quality**. | The **Data Quality** section (a heading with a help icon and **Recount**, no card of its own) shows a spinner (**Counting records**), then ten checks, each with a number, **records found** and a **Needs Attention** or **All Clear** badge, starting with **People with No Household** and ending with **People Not Changed in 5 Years**. |
| 2 | Read **People with No Household**. | **0** on fresh sample data. |
| 3 | Read **Deceased People Who Can Still Be Emailed**. | A number above 0 (sample data has deceased people with an email, for example Sung Silva). |
| 4 | Click **Open in Find** on that check. | A message says to choose **Data Quality: Deceased People Who Can Still Be Emailed** from Saved queries, and the **Find** tab opens with that query already run. Sung Silva is in the list. |
| 5 | Go back to **Data Quality** and click **Recount**. | The spinner shows, the buttons are disabled while it counts, and the same numbers come back. |

**Cleanup:** Delete the saved query **Data Quality: Deceased People Who Can Still Be Emailed** in Find if you want a tidy org.

## T-DM-08: An Empty Household Is Counted, and the Years Setting Is Bounded

**Purpose:** Confirm a new problem shows after **Recount**, and an out-of-range setting is refused.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Home**, click **New Household**, rename it `Empty Test Household`, and add nobody. | The household saves. |
| 2 | On **Org Optimizer**, **Data Quality**, click **Recount**. | **Households with Nobody in Them** has gone up by 1. |
| 3 | Open it in Find. | `Empty Test Household` is in the list. |
| 4 | In **BarnCRM Settings**, **Org Optimizer**, set **Years before a person is not changed** to `25` and click **Save**. | Nothing is saved: the value is marked and the page says **A number is outside the range its setting takes, so nothing was saved. Correct the marked value and save again.** (or the server message **Years before a person is not changed takes a number from 1 to 20, so nothing was saved. Change it and save again.**). |
| 5 | Set it to `3`, save, then **Recount** on **Data Quality**. | **Your settings are saved.** The last check now reads **People Not Changed in 3 Years**. |

**Cleanup:** Set the years back to `5`. Keep `Empty Test Household` if you run T-HC-05 next; otherwise delete it.

## T-DM-09: Field Utilization Counts, Saves and Compares

**Purpose:** Confirm the on-demand count, the saved counts and the change column.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Org Optimizer** and choose **Field Utilization**. | **Field Utilization**, with **Kind of Record** set to **Choose a kind of record**. |
| 2 | In **Kind of Record**, choose **Account**. | A progress bar fills while it reads **Counted N of N fields.** The table has **Field**, **API Name**, **Record Type**, **Filled**, **With a Value** and **Records** columns; rows appear for **Household** and **Organization**. |
| 3 | Read the line above the table. | **No counts have been saved for this kind of record yet.** |
| 4 | Read the small text under the button group, then click **Save Utilization Snapshot**. | The small text reads "Keeps this count so your next count shows what changed." Then **Saved N counts.** |
| 5 | Open any sample organization and fill in **Website**. Return and click **Count Again**. | The Website row for **Organization** shows a higher **Filled**; **Saved** shows the earlier percentage and **Change (Points)** shows the rise. |
| 6 | Check the bell. | No notification for the count. |

**Cleanup:** Clear the Website you added. Delete the **Field Utilization Snapshot** records if you want a tidy org.

## T-DM-10: Job Notifications Can Be Turned Off

**Purpose:** Confirm the one setting stops notifications while jobs still run.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **General**, clear **Tell people when their long jobs finish** and click **Save**. | **Your settings are saved.** |
| 2 | Run a bulk update as in T-DM-03, steps 1 and 2, setting **Title** to `Quiet`. | The job completes and is listed in **Data Jobs**. |
| 3 | Check the bell. | No new notification. |
| 4 | Undo the job as in T-DM-04 (type `6`). | The job reaches undone; no notification. |

**Cleanup:** Tick **Tell people when their long jobs finish** again and save.

## T-DM-11: Snapshot History Compares, Shows and Deletes Saved Counts

**Purpose:** Confirm the Snapshot History list, the compare choice, the saved rows and the delete.
**Prerequisites:** admin; T-DM-09 done (one saved count for **Account**).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Org Optimizer**, choose **Field Utilization**, and choose **Account**. | After the count, **Snapshot History** appears below the table with one row: **Taken**, **Saved By** (you), **Fields** and **Average Fill Rate**, and the buttons **Compare with this one** (greyed out, it is the one in use), **View** and **Delete**. |
| 2 | Open any sample organization and fill in **Website**. Return, click **Count Again**, then save the count again. | The list now has two rows, newest first. |
| 3 | Fill in another field on an organization, such as **Phone**, then click **Count Again**. On the older row choose **Compare with this one**. | The line above the table names the older save's date, and **Saved** and **Change (Points)** now use the older save. The older row's button is greyed out. |
| 4 | Click **Count Again**. | The comparison is back on the latest save. |
| 5 | On the newer row choose **View**. | Under the list, a table with **Kind of Record**, **Record Type**, **Field** and **Fill Rate** shows that save's rows. |
| 6 | Click **Close**. | The table goes away. |
| 7 | On the newer row choose **Delete**, then **Cancel**. | Nothing is deleted. |
| 8 | Choose **Delete** again and confirm with **Delete Snapshot**. | **Snapshot deleted.** The list has one row, and **Saved** now compares with the older save. |
| 9 | Choose a kind of record with no saved counts, such as **Contact** if you have not saved it. | **No snapshots have been saved for this kind of record yet.** |

**Cleanup:** Delete the remaining snapshot with **Delete** if you want a tidy org.
