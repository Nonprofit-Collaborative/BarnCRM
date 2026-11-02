# Funders

Scripts for the funder pipeline (F-01). Setup detail: [Funders](../admin-guide/funders.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, Rollup Builder,
Giving and Funders deployed. Programs is optional; T-FUN-04 needs it for its second half. Funders
works on the platform-only shape. Give the testers their roles on the **Access** page: admin
(Admin role), staff (Fundraising Staff role) and read-only (Read Only role). Each gets its Funders
permission set from the role. Have one organization, `Lakeside Foundation`, with a contact,
`Pat Rivera`.

## T-FUN-01: Add a Grant and Watch the Stage Dates

**Purpose:** confirm a grant needs an organization funder and the stage dates fill themselves in.
**Prerequisites:** staff.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM Funders** app. | Tabs: **Grant Pipeline**, **Grants**, **Reports**, **Error Log** (last). |
| 2 | **Grants**, **New**. Name `2027 Literacy Grant`, leave **Funder** empty, **Save**. | Refused: **Funder** is required. |
| 3 | Funder `Lakeside Foundation`, Funder Contact `Pat Rivera`, Amount Requested `25,000`, Application Deadline 10 days from today, **Save**. | The grant's page shows the **Program** card. **Stage** is **Prospect**; **Submitted Date** and **Decision Date** are empty. |
| 4 | **Edit**, Stage **Applied**, **Save**. | **Submitted Date** is today. |
| 5 | **Edit**, Submitted Date one week ago, Stage **Invited to Apply**, **Save**; then Stage **Applied** again. | **Submitted Date** stays one week ago. |
| 6 | **Edit**, Amount Requested `-5`, **Save**. | Refused: `Amount Requested and Amount Awarded can't be negative.` |
| 7 | **Edit**, Award Start Date today, Award End Date yesterday, **Save**. | Refused: `Award End Date can't be before Award Start Date.` |
| 8 | Try to delete `Lakeside Foundation`. | Refused; Salesforce names the grant. |

**Cleanup:** None (T-FUN-02 uses this grant).

## T-FUN-02: The Grant Pipeline Board

**Purpose:** confirm columns, totals, Mine and the deadlines list.
**Prerequisites:** staff; the grant from T-FUN-01 moved back to **Prospect**; a second grant `Arts Grant` owned by the admin at **Letter of Inquiry**, Amount Requested `10,000`, Application Deadline 3 days ago.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Grant Pipeline**. | Columns **Prospect**, **Letter of Inquiry**, **Invited to Apply**, **Applied**, each with a count and an amount. **Open Requests** counts both grants; **Amount Requested** is 35,000. |
| 2 | Read **Upcoming Deadlines**. | `Arts Grant` first, `3 days overdue` in red; then `2027 Literacy Grant` with `10 days left`. |
| 3 | Choose **Mine**. | Only `2027 Literacy Grant` (the staff user owns it). |
| 4 | Choose **Everyone**, then a card's menu, **Open**. | The grant's page opens. |

**Cleanup:** None.

## T-FUN-03: Move and Award a Grant

**Purpose:** confirm moving from the menu and recording the award.
**Prerequisites:** staff, the grants from T-FUN-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | On `2027 Literacy Grant`, menu, **Move to Applied**. | `Moved to Applied.`; the card is in **Applied**, and the grant leaves **Upcoming Deadlines**. |
| 2 | Menu, **Move to Awarded**. | **Record the Award** asks for **Amount Awarded**, showing 25,000. |
| 3 | Change it to `24,000`, **Save**. | The card leaves the board. **Awarded This Fiscal Year** shows 24,000 and `1 grants awarded`. The grant's **Decision Date** is today and **Amount Awarded** 24,000. |
| 4 | On `Arts Grant`, menu, **Move to Withdrawn**. | It leaves the board and the deadlines list. |
| 5 | Open `2027 Literacy Grant`'s **Grant History** related list. | Each move is listed. |

**Cleanup:** None.

## T-FUN-04: The Program a Grant Pays For

**Purpose:** confirm the Program card with and without Programs.
**Prerequisites:** staff; a grant.

| Step | Action | Expected result |
|---|---|---|
| 1 | In an org without Programs, open a grant. | The **Program** card says to install the Programs module. Nothing to choose. |
| 2 | In an org with Programs and a program `After School`, open a grant. | The card offers **No program** and `After School`; **Save** is disabled. |
| 3 | Choose `After School`, **Save**. | `Program saved.` Reload: `After School` is chosen. |
| 4 | As the admin, delete `After School`, then open the grant. | The card says the program has been deleted or you cannot see it. |
| 5 | Choose **No program**, **Save**. | Saved; the message is gone. |

**Cleanup:** None.

## T-FUN-05: Access, Health Check and Sample Data

**Purpose:** confirm the role sets, the read-only view, the Health Check finding and sample data.
**Prerequisites:** admin, staff and read-only; `Arts Grant` moved back to **Prospect** with its deadline in the past.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Setup, look at each tester's **Permission Set Assignments**. | Staff holds **Funders Staff**, read-only **Funders Read Only**, the admin **Funders Admin**. |
| 2 | As staff, try to delete a grant. | No **Delete** is offered. |
| 3 | As read-only, open **Grant Pipeline**. | `You can look at the pipeline but not change it.`; card menus offer only **Open**; no **New Grant**. |
| 4 | As the admin, open **Health Check**. | `1 grant application is past its deadline`, linked to `Arts Grant`. |
| 5 | Move `Arts Grant` to **Applied** and run Health Check again. | The finding is gone. |
| 6 | **BarnCRM Settings**, **Load Sample Data**. | Three sample grants on the sample organizations: one Prospect, one Applied, one Awarded. |
| 7 | **Remove Sample Data**. | The sample grants are gone; your own grants stay. |

**Cleanup:** Delete the test grants as the admin.
