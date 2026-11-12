# Grid

Scripts for the Grid (C-41, C-41b): a saved Find query in editable tables with related records, and saved grids. Setup detail: [Grid](../admin-guide/grid.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) read Garcia as Zztest. The **Data Manager** feature must be on (BarnCRM Settings, **General**). In Find, save a query named **Garcia contacts** on **Contact** with columns **First Name**, **Last Name** and **Email** and the condition **Last Name equals Garcia**.

## T-GRID-01: Run a Saved Query in the Grid

**Purpose:** confirm the Grid opens from Data Manager and runs a saved query into a table.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Data Manager**. Under **Find and Change**, read the **Grid** tile. | It reads "Edit a saved query's records, and their related records, in one table." |
| 2 | Choose **Grid**. | The **Find** tab opens on the Grid: **Saved Query or Grid**, and **Open in Find**. |
| 3 | In **Saved Query or Grid**, choose **Garcia contacts**, then **Run**. | Under **Records**, a table lists the Garcia contacts with First Name, Last Name and Email. |

**Cleanup:** none.

## T-GRID-02: Edit and Undo

**Purpose:** confirm an edit saves as one undoable data job.
**Prerequisites:** admin; T-GRID-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Double-click **Email** on Harper Garcia, type `harper.grid@example.org`, and press **Save**. | "Saved 1 records. To undo, open Data Manager, then Data Jobs." The table shows the new email. |
| 2 | Open **Data Manager**, **Data Jobs**, and undo the newest job. | Harper Garcia's email is back to what it was. |
| 3 | As a user with **BarnCRM Find and Export** but not **Bulk Update Records**, run the same query in the Grid. | The table is read only: "You can look but not change values here: changing records needs the Bulk Update Records permission." |

**Cleanup:** none.

## T-GRID-03: Related Records and Saved Grids

**Purpose:** confirm related record tables and saving, sharing and deleting a grid.
**Prerequisites:** admin; T-GRID-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Under **Related Records**, select **Add a Related Record Column** and choose **Cases** or any related list with records for the Garcias, with two fields, then **Run**. | A second table, headed with the related list's name, lists the related records with a **Record** column naming each parent. |
| 2 | Select one Garcia in the first table. | The related table shows only that person's records. |
| 3 | Type `Garcia grid` in **Grid Name**, tick **Share**, and press **Save Grid**. | "The grid is saved." **Saved Query or Grid** lists **Garcia grid (grid)**. |
| 4 | Open **Find** and its saved queries. | **Garcia grid** is listed. |
| 5 | Back in the Grid, choose **Garcia grid**, press **Delete Grid**, and confirm. | It is gone from both lists; **Garcia contacts** is unchanged. |

**Cleanup:** none.
