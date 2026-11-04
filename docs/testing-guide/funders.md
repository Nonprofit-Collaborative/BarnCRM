# Funders

Scripts for the funder pipeline (F-01), reporting requirements with reminders (F-02), award schedules (F-05), restricted funds (F-03), the Grant Calendar (F-08), government award fields (F-04), the answer library (F-14), links to Logic Models outcomes (L-06), funder report templates (F-06) and the board dashboard (F-07). Setup detail: [Funders](../admin-guide/funders.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, Rollup Builder
and Funders deployed. Programs and Giving are optional; T-FUN-04 needs Programs and T-FUN-10
Giving for their second halves. Funders
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
| 1 | Open the **BarnCRM Funders** app. | It opens on **Board Dashboard** (first tab), then **Grant Pipeline**, **Grants**, **Reports**, **Error Log** (last). |
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
| 2 | Read **Upcoming Deadlines**. | `Arts Grant` first with a red `3 days overdue` badge; then `2027 Literacy Grant` with an amber `10 days left` badge. The `2027 Literacy Grant` card shows the same amber badge, its amount in larger type and the owner's initials. |
| 3 | Choose **Mine**. | Only `2027 Literacy Grant` (the staff user owns it). |
| 4 | Choose **Everyone**, then a card's menu, **Open**. | The grant's page opens. |
| 5 | Back on the board, click a card's grant name. | The grant's page opens. The totals are tiles; the intro reads `Click a grant to open it`. |

**Cleanup:** None.

## T-FUN-03: Move and Award a Grant

**Purpose:** confirm moving from the menu and recording the award.
**Prerequisites:** staff, the grants from T-FUN-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | On `2027 Literacy Grant`, menu, **Move to Applied**. | `Moved to Applied.`; the card is in **Applied**, and the grant leaves **Upcoming Deadlines**. |
| 2 | Menu, **Move to Awarded**. | A **Record the Award** dialog asks **Amount Awarded** (showing 25,000), **Award Start Date**, **Award End Date** and **Restricted**. Tab and Shift+Tab stay inside it; Escape closes it with nothing saved. |
| 3 | Set an end date before the start date, **Save**. | The dialog stays open with the reason. |
| 4 | Change the amount to `24,000`, dates January 1 to December 31 next year, tick **Restricted**, **Save**. | `Awarded. Open 2027 Literacy Grant to build its payment schedule.` with the name as a link. The card leaves the board. **Awarded This Fiscal Year** shows 24,000 and `1 grants awarded`. The grant has **Decision Date** today, **Amount Awarded** 24,000, the award dates and **Restricted** ticked. |
| 5 | On `Arts Grant`, menu, **Move to Withdrawn**. | It leaves the board and the deadlines list. |
| 6 | Open `2027 Literacy Grant`'s **Grant History** related list. | Each move is listed. |

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
| 1 | **BarnCRM Settings**, **Funders** (under Fundraising). | **Create reminder tasks** on, **Email reminders** off, **Days before a deadline to remind** 14. Turn **Email reminders** on and save. |
| 2 | Health Check, nightly jobs list. | **Grant Requirement Reminders, 6:00 AM** is scheduled. |
| 3 | In the Developer Console run `GrantReminderBatch.startMorning();`, or wait until the next morning. | The staff user has a task `Year 1 report due for Youth Grant` on the grant, due on the due date, and an email with a link to the grant. **Reminder Sent For** on the requirement shows the due date. |
| 4 | Run it again. | No second task or email. |
| 5 | Change the requirement's **Due Date** to 7 days from today and run it again. | A new task and email for the new date. |
| 6 | Clear **Assigned To** and change the due date again; run it. | The task goes to the grant's owner. |
| 7 | Set **Days before a deadline to remind** to `120`. | Refused: from 1 to 90. |
| 8 | Turn both reminder settings off and run it after changing the due date. | Nothing is made. Turn **Create reminder tasks** back on and leave **Email reminders** off (the shipped values). |

**Cleanup:** Delete the test tasks.

## T-FUN-08: Requirement Deadlines on the Pipeline and in Health Check

**Purpose:** confirm requirement rows, Mark Submitted and the overdue finding.
**Prerequisites:** admin, staff and read-only; `Year 1 report` open and due in 7 days; a second open requirement `Q1 financial` due 3 days ago.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Grant Pipeline**, **Upcoming Deadlines**. | `Q1 financial` first with a red `3 days overdue` badge, then `Year 1 report` with `7 days left`; under each, its type and `Youth Grant`. Each has **Mark Submitted**. |
| 2 | Click **Mark Submitted** on `Year 1 report`. | `Marked submitted.` with an **Undo** link; the row leaves the list; its **Submitted Date** is today. |
| 2a | Click **Undo**. | `Undone.`; the row is back with **Mark Submitted**; the requirement's **Status** is what it was and **Submitted Date** is empty. Mark it submitted again. |
| 3 | As read-only, open **Grant Pipeline**. | `Q1 financial` is listed with no **Mark Submitted**. |
| 4 | As the admin, open **Health Check**. | `1 grant requirement is overdue`, linked to `Q1 financial`. |
| 5 | Set `Q1 financial` to **Waived** and run Health Check again. | The finding is gone. |
| 6 | Load sample data. | The **Youth Programs Award** has three requirements: Site visit (Accepted), Quarter 1 financial report (In Progress, due in 10 days), Interim narrative report (Not Started). |

**Cleanup:** Remove sample data; delete the test grants as the admin.

## T-FUN-09: Award Schedules

**Purpose:** confirm Build Schedule, its checks, Mark Received and the totals.
**Prerequisites:** admin, staff and read-only; a grant `Two Year Award` to `Lakeside Foundation`, **Awarded**, **Amount Awarded** 25,000, **Award Start Date** January 1 next year, **Award End Date** December 31 the year after.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open `Two Year Award`. | The **Award Schedule** card shows Amount Awarded 25,000, Amount Scheduled 0, Amount Received 0, **Payment Frequency** Annual and **Build Schedule**. |
| 2 | Choose **Quarterly**, then **Annual**. | Eight payments of 3,125, then two of 12,500 on January 1 of each year. |
| 3 | Click **Build Schedule**. | `Saved.`; two **Expected** payments; Amount Scheduled 25,000; **Build Schedule** is gone. The grant's **Payment Frequency** is Annual. |
| 4 | Click **Mark Received** on the first payment. | `Saved.`; it is **Received** with today's date; Amount Received 12,500, on the card and on the grant. |
| 5 | In the **Payments** list, set the second payment to **Cancelled**. | Scheduled 12,500. **Build Schedule** stays hidden (a payment is Received). |
| 6 | Create a grant `Not Yet` at **Applied** and open it. | The card says what a schedule needs; no **Build Schedule**. |
| 7 | As read-only, open `Two Year Award`. | The payments show; no **Mark Received** and no **Build Schedule**. |
| 8 | Load sample data and open **Youth Programs Award**. | Two payments of 17,500: the first Received on the award start date, the second Expected six months later. |
| 9 | As the admin, delete `Two Year Award`. | Its payments go with it. |

**Cleanup:** Remove sample data; delete `Not Yet` as the admin.

## T-FUN-10: Restricted Funds and the Giving Fund

**Purpose:** confirm the restricted ledger, its totals, the entries written for received payments, and the Giving Fund card with and without Giving.
**Prerequisites:** admin, staff and read-only; a grant `Restricted Award` to `Lakeside Foundation`, **Awarded**, **Amount Awarded** 10,000, award dates this year, with **Restricted** ticked and one **Expected** payment of 10,000.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open `Restricted Award` and click **Mark Received** on the payment. | A **Received** entry of 10,000 dated today appears in **Restricted Fund Entries**; **Restricted Received** and **Restricted Balance** are 10,000. Staff cannot edit the entry's **Payment**. |
| 2 | Add a **Spent** entry of 12,000, description `Tutor salaries`. | **Restricted Spent** 12,000; **Restricted Balance** -2,000 (shown, not refused). |
| 3 | Add a **Released** entry of 0. | Refused: the amount must be above zero. |
| 4 | Change the payment's **Amount** to 9,000, then its **Received Date** to the first of the month. | The Received entry follows: 9,000, dated the first. |
| 5 | Set the payment to **Expected**. | The Received entry is removed; the Spent entry stays. |
| 6 | Untick **Restricted**, add a second payment of 500 as **Received**. | No entry is added. |
| 7 | Without Giving: look at the **Giving Fund** card. | It says to install the Giving module. Typing text into **Giving Fund** on the grant is refused. |
| 8 | With Giving: choose an active fund on the card and click **Save**. | `Saved.` and the fund's name; the grant's **Giving Fund** holds an 18-character ID. Choose **No fund** and save to clear it. |
| 9 | As read-only, open the grant. | The entries and totals show; no **New** on the entries and the fund is shown by name. |
| 10 | Load sample data and open **Youth Programs Award**. | **Restricted** is ticked: Received 17,500, Spent 6,000 (`Tutor stipends`), balance 11,500. |
| 11 | As the admin, delete `Restricted Award`. | Its entries and payments go with it. |

**Cleanup:** Remove sample data.

## T-FUN-11: The Grant Calendar

**Purpose:** confirm the calendar shows the same deadlines as the pipeline, plus expected payments, by month and scope.
**Prerequisites:** admin, staff and read-only; load sample data. As staff, create a grant `Calendar Test` at **Prospect** with **Application Deadline** in 10 days, owned by staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the **Grant Calendar** tab in **BarnCRM Funders**. | This month, today in bold. `Application: Calendar Test` on its day; the sample requirements and the sample award's expected payment on theirs if they fall this month. The tab is next to **Grant Pipeline**. |
| 2 | Open **Grant Pipeline**. | Every application and requirement under **Upcoming Deadlines** that falls this month is on the calendar too; when overdue it has a red badge on the pipeline and is marked with the warning icon and **Overdue** on the calendar (see step 10). |
| 3 | Click **Next Month** until the sample award's second payment shows. | `Grant Payment: Youth Programs Award $17,500.00` (in your currency) on its due date. |
| 3a | Click **Print**. | The print preview shows the month without the app's header, navigation or buttons. |
| 4 | Click the payment, then go back and click `Calendar Test`. | Each opens its record. |
| 5 | Mark the payment **Received** and return to the calendar. | It is gone: only expected payments show. |
| 6 | Choose **Mine**. | Only `Calendar Test` and requirements assigned to staff or on staff's grants. |
| 7 | As read-only, open **Grant Calendar**. | The same entries for **Everyone**; nothing to change. |
| 8 | Narrow the window to phone width (or use the Salesforce mobile app). | Only days with entries are listed, one under another, with no sideways scrolling. |
| 9 | With a screen reader, step through the calendar. | The month is announced; each entry is a button that says what it is. |
| 10 | Set `Calendar Test`'s **Application Deadline** to 3 days ago and reload **Grant Calendar** on this month. | The entry shows a warning icon, the word **Overdue** (in its hover text and read out by a screen reader) and bold text, not red text alone. |
| 11 | Look under the month heading. | A legend names the border colours: **Application** (blue), **Grant Requirement** (orange), **Grant Payment** (green), plus the **Overdue** mark. Each entry's border matches its legend colour. |

**Cleanup:** Remove sample data; delete `Calendar Test` as the admin.

## T-FUN-12: Government Award Fields

**Purpose:** confirm the government award fields and their checks (F-04, R-GN10).
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

## T-FUN-14: Requirements Linked to Logic Model Outcomes

**Purpose:** confirm the optional link from a requirement to a Logic Models outcome (L-06, R-GQ6).
**Prerequisites:** Logic Models deployed (steps 1 to 6) and an org without it (step 7); admin and staff with Logic Models access; a logic model "Reading" with an outcome "Students read at home" carrying an indicator "Students reading daily" (unit students) with periods 2024 (target 30, result 20) and 2026 (target 30, result 25), and an activity "Tutoring"; an awarded grant `Youth Grant` with award period 1 January to 31 December 2026 and a requirement `Final report`.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open `Youth Grant`. | A **Logic Model Outcomes** card listing `Final report (Narrative Report)` with **No outcome**. |
| 2 | Open the list. | `No outcome` and `Reading: Students read at home`; the activity is not offered. |
| 3 | Choose the outcome and click **Save**. | `Outcome saved.`; under the requirement `Students reading daily (students)` and `2026: target 30, result 25`; the 2024 period is not shown. |
| 4 | Open `Final report`. | **Logic Model Outcome** holds an 18-character record ID. |
| 5 | Edit `Final report` and type `abc` into **Logic Model Outcome**; **Save**. | Refused: `Choose an outcome or output from a logic model in the Logic Model Outcomes card on the grant's page. This is not one.` |
| 6 | As the admin, delete the outcome in the Logic Model Builder, then reopen `Youth Grant`. | The card says `The outcome this requirement named cannot be found. Choose another.` |
| 7 | In an org without Logic Models, open a grant. | The card says `Install the Logic Models module to link each requirement to the outcome it reports on.` |

**Cleanup:** none.

## T-FUN-15: Funder Report from a Template

**Purpose:** confirm the funder report merge template (F-06, R-FT1 to R-FT3).
**Prerequisites:** admin, staff and read-only users; the awarded grant `Youth Grant` from T-FUN-14 with its requirement `Final report` linked to the outcome; Award Number `S287C250001`.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the admin, open the **Funder Report Templates** tab. | One active template, **Grant report**. |
| 2 | As staff, open `Youth Grant`. | A **Funder Report** card with **Grant report** chosen. |
| 3 | Click **Download Printable**, then open the downloaded file. | `Report downloaded.`; the file shows the grant name, funder, amount awarded in currency, the award period, `S287C250001`, a requirements table with `Final report`, and the outcome with `2026: target 30, result 25`. |
| 4 | As the admin, add a template `Short` with body `<p>{GrantName} for {FunderName} {Unknown}</p>`. As staff, reload the grant, choose `Short` and download. | The file shows `Youth Grant for` the funder's name, and `{Unknown}` as typed. |
| 5 | As the admin, rename the grant `Youth <Grant>` and download again as staff. | The name shows as typed, not as markup. |
| 6 | As the admin, clear **Active** on both templates; reload the grant as staff. | The card says no active template is available. |
| 7 | Make **Grant report** active again. As read-only, open the **BarnCRM Funders** app, then `Youth Grant`. | No **Funder Report Templates** tab; the **Funder Report** card still downloads the report. |

**Cleanup:** delete `Short`, rename the grant `Youth Grant`.

## T-FUN-16: Board Dashboard

**Purpose:** confirm the board dashboard's revenue mix, concentration flags and restricted balances (F-07, R-GN9).
**Prerequisites:** Giving installed; staff with Giving read access and staff without it; no other grants awarded this fiscal year. Two organizations, `Lakeside Foundation` and `State Agency`. Awarded with a decision date this fiscal year: `Federal award` (Lakeside, 30,000, Funding Source Federal) and `State award` (State Agency, 20,000, no funding source). Awarded two fiscal years ago: `Old award` (Lakeside, 99,000). In Giving, gifts this fiscal year of 12,000 to an active restricted fund `Scholarships` and 38,000 to an unrestricted fund, 5,000 of it from `Lakeside Foundation`.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff with Giving access, open the **BarnCRM Funders** app. | It opens on **Board Dashboard**. Tiles: **Revenue This Fiscal Year** 100,000, **Awarded This Fiscal Year** 50,000, **Gifts to funds** 50,000. A **Tools** group has a tile per Funders tab staff can open (no Funder Report Templates); each opens its tab. **Revenue Mix**: a bar per line, `Gifts to funds` 50,000 (50%), `Federal` 30,000 (30%), `Not set` 20,000 (20%). `Old award` is not counted. |
| 2 | Read **Concentration**. | `Lakeside Foundation` 35,000 (35%) first, then `State Agency`, each with a bar; one amber notice holding the two warnings: Lakeside gives 35% (above 25 percent), and the five largest give more than half. |
| 3 | Read **Restricted Balances**. | Under **Restricted Funds: Raised This Fiscal Year**, `Scholarships` 12,000; the unrestricted fund is not listed. |
| 4 | As staff without Giving access, open the tab. | Revenue Mix shows `Federal` and `Not set` only, total 50,000; Restricted Balances says `Nothing to show for this fiscal year yet.` |
| 5 | As the admin, give `State award` the Funding Source **State**; reload as staff. | `Not set` is replaced by `State`. |
| 6 | With restricted fund tracking (F-03) installed, mark `Federal award` restricted and record 10,000 received; reload. | Under **Restricted Grants: Balance**, `Federal award` 10,000, and a **Restricted Grants: Balance** tile of 10,000. |
| 7 | Click **Print**. | The print preview shows the dashboard without the app's header, navigation, Print button or tool tiles. |
| 8 | At phone width, open the tab. | Tiles two to a row; the restricted tables stack each row. |

**Cleanup:** none.
