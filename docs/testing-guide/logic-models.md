# Logic Models

Scripts for the Logic Model Builder (L-01), indicators (L-02), indicator sources (L-03) and the
Logic Model Report (L-04). Setup
detail:
[Logic Models](../admin-guide/logic-models.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Logic Models
deployed. Programs is optional; T-LM-04 needs it. Logic Models works on the platform-only shape.
Give the testers their roles on the **Access** page: admin (Admin role), staff (Program Staff
role) and read-only (Read Only role). Each gets its Logic Models permission set from the role.

## T-LM-01: Build a Model Part by Part

**Purpose:** confirm parts go in the right column, move and save.
**Prerequisites:** staff.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM Logic Models** app, **Logic Models** tab, **New**. Name `Reading Program Model`, save. | The record page shows the **Logic Model Builder** panel. **For** shows `The whole organization`. Seven columns run left to right with a chevron between each; each heading has a `0` count and says `Nothing here yet.` |
| 2 | Click **Add to Inputs**, type `Two tutors`, **Save**. | `Two tutors` is under **Inputs**. |
| 3 | Add `Weekly sessions` to **Activities**, `Sessions held` to **Outputs**, `Reads at home` to **Short Term Outcomes**, `Reads at grade level` to **Impact**. Add `Books` to **Inputs**. | Each part is in its column; `Books` is under `Two tutors`. |
| 4 | Click `Books`, then **Move Up**. | `Books` is above `Two tutors`. **Move Up** is disabled. |
| 5 | Click **Edit**, change **Column** to **Activities**, **Save**. | `Books` is under **Activities**. |
| 6 | Reload the page. | Everything is as you left it. |
| 7 | Click `Books`. | The page scrolls to its details and focus is on the `Selected Part` heading. |
| 8 | Click **Back to the Model** at the top of the details. | Focus returns to the `Books` tile in its column. |

**Cleanup:** None (T-LM-02 and T-LM-03 use this model).

## T-LM-02: Arrows, Assumptions and Things to Look At

**Purpose:** confirm arrows go forward only, once per pair, and the findings update.
**Prerequisites:** staff, the model from T-LM-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | Read **Things to Look At**. | No column is listed as empty (the empty Intermediate and Long Term Outcomes columns are fine, since Short Term has a part). Every part except `Two tutors` has `has no arrow coming in.`, every part except `Reads at grade level` has `has no arrow going out.`, and `Reads at home has no indicator.` is listed. |
| 2 | Click `Two tutors`. Under **Leads To** click **Add Arrow**. Open **Part It Leads To**. | Only parts in later columns are offered; `Books` (an activity) is, `Two tutors` is not. |
| 3 | Choose `Weekly sessions`, type the assumption `Tutors run the sessions.`, **Save**. | The arrow shows under **Leads To** with its assumption. `Weekly sessions` shows it under **Comes From**. |
| 4 | Click **Add Arrow** again on `Two tutors`. | `Weekly sessions` is no longer offered. |
| 5 | Click **Edit** beside the arrow, change the assumption, **Save**. | The new assumption shows. |
| 6 | Link `Weekly sessions` to `Sessions held`, `Sessions held` to `Reads at home`, `Reads at home` to `Reads at grade level`. | Those parts drop out of the no-arrow findings. |
| 6b | Click `Sessions held`. | `Weekly sessions` and `Reads at home` have a blue border; the other parts are dimmed. |
| 6a | Click `Weekly sessions`, **Edit**, change **Column** to **Inputs**, **Save**. | Refused before saving: the message names the arrow `Two tutors to Weekly sessions` and says to delete those arrows first or pick a column that keeps every arrow forward. The part stays in **Activities**. |
| 7 | Click `Books`, **Delete**. Press **Cancel** in the dialog, then **Delete** again and confirm with the red **Delete**. | Cancel keeps `Books`. After confirming, `Books` is gone; the status says `Deleted.` |

**Cleanup:** None.

## T-LM-03: Indicators, Periods and Progress

**Purpose:** confirm indicators only on outputs and outcomes, progress both ways, and one row per period.
**Prerequisites:** staff, the model from T-LM-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click `Weekly sessions` (an activity). | No **Indicators** section shows. |
| 2 | Click `Reads at home`. Click **Add Indicator**: name `Students reading daily`, unit `students`, baseline `10`, **Save**. | The indicator shows `Unit: students. Better when Higher. Baseline: 10.` `Reads at home has no indicator.` leaves **Things to Look At**. |
| 3 | Under it click **Add Period**: `2026 Q1`, 1 January 2026 to 31 March 2026, target `30`, result `20`. **Save**. | **Progress** shows a half bar with `50%`. Target and result are right-aligned. |
| 4 | Click **Edit** on the row, change the result to `30`, **Save**. | **Progress** shows a full bar with `Met`. |
| 5 | Add another period with the same dates. | Refused: `This indicator already has a period with these dates. Change that row instead.` |
| 6 | Add a period with an end date before its start date. | The save is refused with the end date message. |
| 7 | Click **Edit** on `Reads at home` and open **Column**. | Only output and outcome columns are offered. |

**Cleanup:** None.

## T-LM-04: Whose Model It Is

**Purpose:** confirm one model per scope and the program choice.
**Prerequisites:** admin; Programs deployed with at least one program for steps 3 to 5.

| Step | Action | Expected result |
|---|---|---|
| 1 | **Logic Models**, **New**, name `Second Model`, save. | Refused: `The organization already has a logic model. Open that one instead of adding another.` |
| 2 | Without Programs deployed: open `Reading Program Model`. | No **Change** link beside **For**. Skip to the cleanup. |
| 3 | With Programs: click **Change**, choose a program, **Save**. | **For** shows the program's name. |
| 4 | Create `Second Model` again. | It saves: it is the organization's model now. |
| 5 | On `Second Model`, click **Change** and choose the same program. | Refused: `This program already has a logic model. Open that one instead of adding another.` |

**Cleanup:** As admin, delete `Second Model`.

## T-LM-05: Staff and Read-Only Access

**Purpose:** confirm staff cannot delete a model and read-only changes nothing.
**Prerequisites:** staff and read-only; the model from T-LM-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open `Reading Program Model`. | The record page shows no **Delete** action for the model. Parts still show **Delete**. |
| 2 | As read-only, open the **BarnCRM Logic Models** app and the model. | The builder shows every column, arrow and indicator, with no **Add to**, **Edit**, **Delete**, **Change** or **Add Arrow** buttons. |
| 3 | As read-only, open the **Logic Models** tab. | No **New** button. |

**Cleanup:** None.

## T-LM-06: Keyboard and Phone

**Purpose:** confirm the builder works with a keyboard and on a narrow screen.
**Prerequisites:** staff, the model from T-LM-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | Tab through the builder. | Every part and button is reached in reading order, with a visible focus ring. A selected part is announced as pressed. |
| 2 | Press Enter on a part, then save a change. | Focus moves to the status message, which a screen reader reads as `Saved.` |
| 3 | Open the model in the Salesforce mobile app, or narrow the browser to phone width. | The columns stack, one above another, with a downward chevron between them and no sideways scrolling. Select an output with periods: each period row is stacked, one labelled value per line. |

**Cleanup:** None.

## T-LM-07: Imported Results

**Purpose:** confirm the results sheet round trip through Import updates periods and creates nothing.
**Prerequisites:** admin, the model and `2026 Q1` period from T-LM-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | On `Students reading daily` click **Source**, choose **Imported**, **Save**. | The line under it reads `Results: Imported.` |
| 2 | Click **Download Results Sheet**. Open the file. | One row per period of every indicator not computed, headed `Period Id`, `Logic Model`, `Part`, `Indicator`, `Unit`, `Period`, `Start Date`, `End Date`, `Target`, `Result`, `Notes`. |
| 3 | Set the `2026 Q1` row's **Result** to `25`, add a row with **Period Id** `a0Z000000000000AAA`, save as CSV. In **Import** choose the **Indicator Results** template and load it. | The dry run shows one update and one rejected row (no period found); nothing is created. Commit. |
| 4 | Reload the model. | `2026 Q1` shows result `25` and its progress. |
| 5 | In **Import**, undo the batch. | The result goes back to the value before. |

**Cleanup:** None.

## T-LM-08: Computed Results

**Purpose:** confirm a computed indicator counts records per started period, is read only, and reports problems.
**Prerequisites:** admin and staff, the model from T-LM-01. At least three contacts created this month.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, in **Find**, query **Contacts** with no filter and save it as `All people`. | Saved. |
| 2 | On `Sessions held` add the indicator `People in our records`. Add a period `This year` from 1 January to 31 December of this year, and `Next year` for next year. | Two rows; no results. |
| 3 | Click **Source**, choose **Computed**, **Saved Query** `All people`, **Date Field** `Created Date`, **Work Out** `Count`, **Save**. | The indicator shows `Working out results. This takes a few minutes; this panel updates when it is done.` The line reads `Results: computed from All people, count of records by Created Date.` |
| 4 | Wait, without reloading. | Within a few minutes the notice goes and `This year` shows the number of contacts created this year; `Next year` stays blank. The line under the indicator says when it was last worked out. (If it takes over three minutes, the notice offers **Check Again**.) |
| 5 | Click **Edit** on `This year`. | **Result** is disabled, with help saying it is worked out from the source. Change the target and save: the result does not change. |
| 6 | Click **Source**, change **Work Out** to **Count Unique** with **Field** `Account ID`, save and wait. | `This year` shows how many different accounts the new contacts belong to. |
| 7 | Choose **Sum** with **Date Field** `Created Date`: open **Field**. | Only number fields are offered. Cancel. |
| 8 | As staff (Program Staff role, no Find access), open the model. | The indicator line reads `computed from a saved query`; there is no **Source** button; **Refresh Results** is there and works. |
| 9 | As admin, delete `All people` in **Find**, then click **Refresh Results** and wait. | The indicator shows a red notice that the saved query can't be found; the results are unchanged. |
| 10 | In **Health Check**, look at nightly jobs. | `Indicator Results, 3:30 AM` is listed; **Schedule all nightly jobs** schedules it. |

**Cleanup:** Delete `People in our records`.

## T-LM-09: The Logic Model Report

**Purpose:** confirm the report compares chosen periods and downloads as CSV and a printable page.
**Prerequisites:** staff and read-only, the model from T-LM-03. On `Students reading daily` add
periods `2026 Q2` (1 April to 30 June 2026, target 30, result 25), `2026 Q3`, `2026 Q4` and
`2027 Q1` (three months each, target 30, no result).

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the model and scroll to **Logic Model Report**. | **Periods to Compare** lists five periods oldest first; the latest four are ticked. One row per indicator shows its column, part and baseline `10`. |
| 2 | Tick `2026 Q1` and untick `2027 Q1`. | `2026 Q1` columns show target `30`, result and progress as in the builder; `2027 Q1` columns are gone. |
| 3 | Add a period with `2026 Q2`'s dates to another indicator, named `Spring`. | The report still lists one period for those dates; the other indicator's row fills its cells. An indicator without a period shows empty cells. |
| 4 | Change a result in the builder and save. | The report shows the new result without reloading; the ticked periods stay ticked. |
| 5 | Click **Download CSV**. Open the file. | Columns `Column`, `Part`, `Indicator`, `Unit`, `Better When`, `Baseline`, `Baseline Date`, then `Target`, `Result`, `Progress` for each ticked period, headed with its name. |
| 6 | Click **Download Printable Report**, open the file in a browser and print preview. | The model's name, whose model it is, today's date and the table; the header repeats on each printed page. |
| 7 | Untick every period. | `Choose at least one period to compare.` shows; both download buttons are disabled. |
| 8 | As read-only, open the model. | The report shows and both downloads work. |

**Cleanup:** None.
