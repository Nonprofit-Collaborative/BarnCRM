# Funders

Scripts for the funder pipeline (F-01), reporting requirements with reminders (F-02) government award fields (F-04) and the answer library (F-14). Setup detail: [Funders](../admin-guide/funders.md).

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

## T-FUN-06: Grant Requirements and the Submitted Date

**Purpose:** confirm requirements belong to their grant and the submitted date fills itself in.
**Prerequisites:** staff; an Awarded grant `Youth Grant`.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open `Youth Grant`. In **Requirements**, click **New**. Name `Year 1 report`, leave **Due Date** empty, **Save**. | Refused: **Due Date** is required. **Type** shows Narrative Report and **Status** Not Started. |
| 2 | Due Date 5 days from today, **Assigned To** the staff user, **Save**. | The requirement is in the grant's **Requirements** list. |
| 3 | **Edit**, Status **In Progress**, **Save**. | **Submitted Date** stays empty. |
| 4 | **Edit**, Status **Submitted**, **Save**. | **Submitted Date** is today. |
| 5 | Add `Site visit`, Type **Site Visit**, Status **Accepted**, Submitted Date last week, **Save**. | **Submitted Date** stays last week. |
| 6 | As staff, delete `Site visit`. | Deleted (staff may delete requirements, not grants). |

**Cleanup:** Set `Year 1 report` back to **Not Started** and clear its Submitted Date (T-FUN-07 uses it).

## T-FUN-07: Reminders and Their Settings

**Purpose:** confirm one task and one email per due date, to the right person, as the settings say.
**Prerequisites:** admin and staff; `Year 1 report` from T-FUN-06; the nightly jobs scheduled (Health Check, **Schedule all nightly jobs**).

| Step | Action | Expected result |
|---|---|---|
| 1 | **BarnCRM Settings**, **Funders** (under Fundraising). | **Create Reminder Tasks** on, **Email Reminders** on, **Days Before a Deadline to Remind** 14. |
| 2 | Health Check, nightly jobs list. | **Grant Requirement Reminders, 6:00 AM** is scheduled. |
| 3 | In the Developer Console run `GrantReminderBatch.startMorning();`, or wait until the next morning. | The staff user has a task `Year 1 report due for Youth Grant` on the grant, due on the due date, and an email with a link to the grant. **Reminder Sent For** on the requirement shows the due date. |
| 4 | Run it again. | No second task or email. |
| 5 | Change the requirement's **Due Date** to 7 days from today and run it again. | A new task and email for the new date. |
| 6 | Clear **Assigned To** and change the due date again; run it. | The task goes to the grant's owner. |
| 7 | Set **Days Before a Deadline to Remind** to `120`. | Refused: from 1 to 90. |
| 8 | Turn both reminder settings off and run it after changing the due date. | Nothing is made. Turn them back on. |

**Cleanup:** Delete the test tasks.

## T-FUN-08: Requirement Deadlines on the Pipeline and in Health Check

**Purpose:** confirm requirement rows, Mark Submitted and the overdue finding.
**Prerequisites:** admin, staff and read-only; `Year 1 report` open and due in 7 days; a second open requirement `Q1 financial` due 3 days ago.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Grant Pipeline**, **Upcoming Deadlines**. | `Q1 financial` first with `3 days overdue` in red, then `Year 1 report` with `7 days left`; under each, its type and `Youth Grant`. Each has **Mark Submitted**. |
| 2 | Click **Mark Submitted** on `Year 1 report`. | `Marked submitted.`; the row leaves the list; its **Submitted Date** is today. |
| 3 | As read-only, open **Grant Pipeline**. | `Q1 financial` is listed with no **Mark Submitted**. |
| 4 | As the admin, open **Health Check**. | `1 grant requirement is overdue`, linked to `Q1 financial`. |
| 5 | Set `Q1 financial` to **Waived** and run Health Check again. | The finding is gone. |
| 6 | Load sample data. | The **Youth Programs Award** has three requirements: Site visit (Accepted), Quarter 1 financial report (In Progress, due in 10 days), Interim narrative report (Not Started). |

**Cleanup:** Remove sample data; delete the test grants as the admin.

## T-FUN-12: Government Award Fields

**Purpose:** confirm the government award fields and their checks (F-04, R-GN8).
**Prerequisites:** staff and read-only; a grant `Youth Grant` to `Lakeside Foundation`.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open `Youth Grant` and click **Edit**. | A **Government Award** section with Assistance Listing Number, Award Number, Federal Agency, Indirect Cost Rate and Match Required; **Funding Source** in the first section. |
| 2 | Set **Funding Source** to `Federal Pass-Through`, **Assistance Listing Number** `84.287`, **Award Number** `S287C250001`, **Federal Agency** `Department of Education`, **Indirect Cost Rate** `15`, **Match Required** `5000`; **Save**. | Saved; the values show as typed, the rate as `15.00%`. |
| 3 | Change **Assistance Listing Number** to `84287` and **Save**. | Refused: `Assistance Listing Number must be two digits, a point and three digits or capital letters, for example 84.287.` |
| 4 | Set it back to `84.287`, set **Indirect Cost Rate** to `120` and **Save**. | Refused: `Indirect Cost Rate must be from 0 to 100.` |
| 5 | Set the rate to `15` and **Match Required** to `-1`; **Save**. | Refused: `Match Required can't be negative.` |
| 6 | As read-only, open `Youth Grant`. | The Government Award section shows the values; nothing can be edited. |

**Cleanup:** none.

## T-FUN-13: Answer Library

**Purpose:** confirm the answer library: topics, search, copying and the last used date (F-14, R-GA1 to R-GA3).
**Prerequisites:** staff and read-only; a grant `Youth Grant`; no grant answers yet.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open `Youth Grant`. | An **Answer Library** card: `No answers yet. Keep the application answers you reuse on the Grant Answers tab.` and a **New Answer** button. |
| 2 | Click **New Answer**: **Answer Title** `Mission (50 words)`, **Topics** `Mission, Organization`, **Answer** `We teach children to read.`; **Save**. Add `Need statement`, **Topics** `need`, with a paragraph of over 60 words. | Both saved; **Last Used Date** is blank. |
| 3 | Back on `Youth Grant`, open the **Topic** list. | `All topics`, `Mission`, `need`, `Organization`. |
| 4 | Choose `Mission`. | Only `Mission (50 words)`, with badges `Mission` and `Organization` and `6 words | Never used`. |
| 5 | Choose `All topics` and search `CHILDREN teach`. | Only `Mission (50 words)`: every word must appear, in any case. Search `zebra`: `No answer matches. Try other words or another topic.` |
| 6 | Clear the search. On `Need statement` click **Show All**, then **Show Less**. | The whole text, then the start with `...`. |
| 7 | Click **Copy** on `Mission (50 words)` and paste into a text editor. | `Copied. Paste it into the application.`; the text pastes exactly; the card shows `Last used` with today's date; the record's **Last Used Date** is today. |
| 8 | As read-only, open `Youth Grant`, click **Copy** on `Need statement`. | The text is copied; no **New Answer** button; its **Last Used Date** stays blank. |
| 9 | As read-only, open the **Grant Answers** tab. | The answers are listed; **New** is not offered. |

**Cleanup:** delete the two answers as staff.
