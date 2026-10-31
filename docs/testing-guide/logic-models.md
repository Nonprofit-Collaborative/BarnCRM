# Logic Models

Scripts for the Logic Model Builder (L-01) and indicators (L-02). Setup detail:
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
| 1 | Open the **BarnCRM Logic Models** app, **Logic Models** tab, **New**. Name `Reading Program Model`, save. | The record page shows the **Logic Model Builder** panel. **For** shows `The whole organization`. Seven columns each say `Nothing here yet.` |
| 2 | Click **Add to Inputs**, type `Two tutors`, **Save**. | `Two tutors` is under **Inputs**. |
| 3 | Add `Weekly sessions` to **Activities**, `Sessions held` to **Outputs**, `Reads at home` to **Short Term Outcomes**, `Reads at grade level` to **Impact**. Add `Books` to **Inputs**. | Each part is in its column; `Books` is under `Two tutors`. |
| 4 | Click `Books`, then **Move Up**. | `Books` is above `Two tutors`. **Move Up** is disabled. |
| 5 | Click **Edit**, change **Column** to **Activities**, **Save**. | `Books` is under **Activities**. |
| 6 | Reload the page. | Everything is as you left it. |

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
| 6a | Click `Weekly sessions`, **Edit**, change **Column** to **Inputs**, **Save**. | Refused before saving: the message names the arrow `Two tutors to Weekly sessions` and says to delete those arrows first or pick a column that keeps every arrow forward. The part stays in **Activities**. |
| 7 | Click `Books`, **Delete**, then confirm. | `Books` is gone; the status says `Deleted.` |

**Cleanup:** None.

## T-LM-03: Indicators, Periods and Progress

**Purpose:** confirm indicators only on outputs and outcomes, progress both ways, and one row per period.
**Prerequisites:** staff, the model from T-LM-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click `Weekly sessions` (an activity). | No **Indicators** section shows. |
| 2 | Click `Reads at home`. Click **Add Indicator**: name `Students reading daily`, unit `students`, baseline `10`, **Save**. | The indicator shows `Unit: students. Better when Higher. Baseline: 10.` `Reads at home has no indicator.` leaves **Things to Look At**. |
| 3 | Under it click **Add Period**: `2026 Q1`, 1 January 2026 to 31 March 2026, target `30`, result `20`. **Save**. | **Progress** shows `50%`. |
| 4 | Click **Edit** on the row, change the result to `30`, **Save**. | **Progress** shows `Met`. |
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
| 3 | Open the model in the Salesforce mobile app, or narrow the browser to phone width. | The columns stack, one above another, with no sideways scrolling. |

**Cleanup:** None.
