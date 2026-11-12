# Project Management

Scripts for the optional BarnCRM Project Management module. Setup detail:
[Project Management](../admin-guide/projects.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Project
Management deployed and the module turned on in BarnCRM Settings, **Modules**. You need an admin
(BarnCRM Admin), a user with the Team Member role (staff A) and a user with the Read Only role.

## T-PM-01: Install and Access

**Purpose:** confirm the tabs, sets and settings.
**Prerequisites:** admin.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the BarnCRM app. | Projects Home, Projects and Time Entries tabs, before Error Log. |
| 2 | Open Setup, staff A's permission set assignments. | Projects Staff is assigned (within the hour, or after Finish Setup). |
| 3 | Open BarnCRM Settings, Projects. | Track time and budgets on, Days late before at risk 7, Budget warning percent 90, Weekly capacity hours 40. |
| 4 | As the Read Only user, open the Projects tab and a project. | The records show; New and Edit are not offered. |

**Cleanup:** None.

## T-PM-02: New Project From the Salesforce Implementation Template

**Purpose:** confirm a shipped template builds a dated project.
**Prerequisites:** staff A.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Projects Home, New Project From Template. Choose Salesforce Implementation, name it "Test Rollout", start next Monday, pick a client organization. Create. | The project opens: Type Salesforce Implementation, Status Planned, Template Used salesforce_implementation. |
| 2 | Look at the phases on the project page. | Discovery, Design, Build, Data Migration, Testing, Training and Go-Live, in order, each with dates from the start date and a bar on the timeline. |
| 3 | Open the Go-Live phase. | A Go-Live milestone task. |
| 4 | Look at the progress line. | 0 tasks done, 0%. |

**Cleanup:** keep the project for T-PM-03 to T-PM-06.

## T-PM-03: Tasks, Progress and a Template of Your Own

**Purpose:** confirm task status, Completed Date, percent complete and a template project.
**Prerequisites:** T-PM-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set the project's Status to Active. On the first Discovery task choose Done. | Its Completed Date is today; the progress line counts 1 done and the percent rises. |
| 2 | Choose In Progress on the same task. | Completed Date is cleared. |
| 3 | Add Task "Extra review" in Design. | It appears in Design as Not Started. |
| 4 | Edit a task and pick a phase of another project as its Phase. | Refused by the lookup filter. |
| 5 | Check Is Template on a second small project with two phases and an assignment with a role. Create a new project from it with a start date 30 days later. | Phases and tasks copied, dates moved 30 days, tasks Not Started, the assignment has the role and no person. |

**Cleanup:** None.

## T-PM-04: Health and the Projects at Risk Card

**Purpose:** confirm R-PM2 and the card.
**Prerequisites:** the active project from T-PM-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | Give an open task a Due Date 10 days ago. Refresh Health. | At Risk, with the late task in Health Reasons. |
| 2 | Set the project's Target Date to yesterday. Refresh Health. | Off Track, with the target date reason. |
| 3 | Open Projects Home. | The project is in Projects at Risk with its reasons; Only Mine keeps it when you own it. |
| 4 | Check Is Template on the project. Refresh Health. | Health is blank; the project leaves the card. Uncheck it. |
| 5 | Run the nightly run's Projects health step (BarnCRM Settings, Automation, Nightly Jobs, Run Now). | Active projects have a health. |

**Cleanup:** restore the dates.

## T-PM-05: Time, Budget and Utilization

**Purpose:** confirm time entries, actuals and utilization.
**Prerequisites:** T-PM-02; Budget Hours 10, Budget Amount 1000, Hourly Rate 100 on the project.

| Step | Action | Expected result |
|---|---|---|
| 1 | Log Time: today, 4 hours on a task, billable. | Actual Hours 4, Billable Hours 4, Actual Cost 400, Remaining Budget 600. |
| 2 | Log Time: 0 hours. | Refused: hours must be more than 0 and at most 24. |
| 3 | Log Time: 5.5 hours, not billable. Refresh Health. | Actual Hours 9.5; At Risk with the budget reason (95% of 10). |
| 4 | Projects Home, Utilization for this week. | Your row: 9.5 logged, 4 billable, capacity 40, about 24%. |
| 5 | Turn Track time and budgets off. Reload the project and Projects Home. | No Log Time, no budget line, no Utilization or export. Turn it back on. |

**Cleanup:** None.

## T-PM-06: Export Billable Time

**Purpose:** confirm the CSV and Exported Date.
**Prerequisites:** T-PM-05; admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Projects Home, Export Billable Time for this month. | A CSV with the 4-hour entry only (not the non-billable one), with rate 100 and amount 400. |
| 2 | Open the entry. | Exported Date is today. |
| 3 | Export again. | Nothing new: an empty file with only the heading line. With Include Exported checked, the entry is there again. |
| 4 | As staff A, open Projects Home. | No Export Billable Time. |

**Cleanup:** None.

## T-PM-07: Draft Status Update

**Purpose:** confirm R-PM8.
**Prerequisites:** T-PM-03 and T-PM-05.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the project, Draft Status Update. | A Project Status Update dated today with the project's health, percent complete and hours. |
| 2 | Open it. | Accomplishments lists the task done today; Next Steps lists tasks due in the next 14 days; Risks lists the health reasons and any Blocked task. |
| 3 | Edit Summary and save. | Saved. |

**Cleanup:** None.

## T-PM-08: Reports

**Purpose:** confirm the shipped reports run.
**Prerequisites:** T-PM-04 to T-PM-06.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Reports, BarnCRM Projects. | Projects at Risk, Overdue Project Tasks, Time by Person This Month, Billable Time Last Month. |
| 2 | Run Time by Person This Month. | Hours grouped by person, with totals. |

**Cleanup:** None.

## T-PM-15: Resource Management and Staffing (PM-09, D-197)

**Purpose:** confirm R-PM14 and R-PM15: nothing changes while Manage resources is off, people are
kept one row each, Fill ranks by skills, role and free capacity, and the allocation view works.
**Prerequisites:** admin, staff A and a second user (staff B); a project with a Data Migration
resource request of 20 hours for next Monday to Friday, skills Data Migration and Training.

| Step | Action | Expected result |
|---|---|---|
| 1 | With Manage resources off, open the Staffing tab. | Only the message that resource management is off. |
| 2 | In BarnCRM Settings, Projects, turn Manage resources on. Open Staffing. | The open request, People Who Can Be Staffed (empty) and Weekly Allocation. |
| 3 | Add staff A: skills Data Migration and Training, Weekly Capacity Hours 40, Default Role Data Migration. Add staff B: skills Training, capacity 10. Save each. | Both are listed. Saving staff A again edits the same row. |
| 4 | Plan 30 hours for staff A on another active project in the request week (a Project Assignment with those dates). | The assignment shows in Weekly Allocation for that week as 30 / 40. |
| 5 | Choose Fill on the request. | Staff A first (every skill and the role) with 10 free hours; staff B second with 1 of 2 skills. The help line explains the order. |
| 6 | Assign staff A. | A message says staff A is assigned. The request is Filled and linked to a new Project Assignment with the request's role, hours and dates. |
| 7 | Open Weekly Allocation for that week. | Staff A shows 50 / 40 in red (over capacity); Unfilled Requests shows 0. |
| 8 | Set staff B to inactive. | Staff B leaves Weekly Allocation and the Fill list. |
| 9 | On Projects Home, show utilization for the week. | Staff A's capacity is 40; staff B's own capacity applies if staff B logged time. |
| 10 | Turn Manage resources off again. | The Staffing tab shows the off message; records are kept. |

**Cleanup:** Delete the test assignment and request, and the Project Resource rows.


## T-PM-09: Rate Cards (PM-06)

**Purpose:** confirm R-PM9: rates by person and role, kept on the entry.
**Prerequisites:** T-PM-05; admin; staff A with a Project Assignment on the project, Role
Developer; the project's Hourly Rate 100.

| Step | Action | Expected result |
|---|---|---|
| 1 | Log 2 hours as staff A. Turn on **Use rate cards** in BarnCRM Settings, Projects, after step 1 only. | The entry from step 1 has no Bill Rate. |
| 2 | Project Rates tab: add a Role rate Developer, Bill Rate 150, Cost Rate 80, Effective From 60 days ago. Add a Person rate for staff A, Bill Rate 175, no Cost Rate, Effective From 30 days ago. | Both saved. A rate with both a Person and a Role is refused. |
| 3 | Projects Home, **Apply Rates**. | "Rates applied to 1 time entries." The step 1 entry now has Bill Rate 175 and Amount 350; Cost Rate is visible to admin only (80). |
| 4 | As staff A, log 1 hour today. As the admin, log 1 hour. | Staff A: Bill Rate 175, Cost Rate 80. Admin: Bill Rate 100 (the project rate), no Cost Rate. |
| 5 | Change staff A's Person rate to 999. Open the step 4 entry. | Still 175: a rate change never reprices logged time. |
| 6 | Change the step 4 entry's Date to 45 days ago. | Bill Rate 150 (the Role rate): a new date prices it again. |
| 7 | As staff A, open a Project Rate and an entry. | Bill rates visible; no Cost Rate or Cost Amount fields. |
| 8 | Turn **Use rate cards** off and log 1 hour. | No rates written; Actual Cost is Actual Hours times the Hourly Rate again. No Apply Rates button. |

**Cleanup:** keep the project for T-PM-10.

## T-PM-10: Timesheets and Approvals (PM-07)

**Purpose:** confirm R-PM10 and R-PM11.
**Prerequisites:** T-PM-09; admin owns the project; staff A and staff B (no owner, no admin).
Turn on **Approve time and expenses**.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff A, open the **Timesheet** tab. Add a row for the project, enter 4 on Monday and 3 on Tuesday, Save. | Two entries, each Open. The project's Actual Hours has not changed (Open time does not count). Older entries with no status still count. |
| 2 | Log Time on the project page. | "Time logged as Open." and the entry is in this week's grid. |
| 3 | Empty a saved cell and Save. | Refused with the message that a cell cannot be emptied. |
| 4 | **Submit Week**. Try to change Monday to 5. | Entries are Submitted; the cell is locked. **Recall Week** unlocks them; submit again. |
| 5 | As staff B, open **Approvals**. Try to approve through the Time Entries list edit. | The queue is empty (not owner); the edit is refused: only the owner or a Projects admin approves. |
| 6 | As the admin, open **Approvals**. | One group, staff A, this week. |
| 7 | Reject the week with no reason. | Refused: a reason is needed. |
| 8 | Reject with the reason "Wrong task". | Entries are Rejected with the reason. As staff A the Timesheet shows the reason; change Monday and submit again. |
| 9 | As the admin, Approve the week. | Entries are Approved with Approved By. Actual Hours and Billable Hours now include them. |
| 10 | As staff A, try to change an approved entry. As the admin, change its hours. | Staff A is refused (locked); the admin can. |
| 11 | Projects Home, Export Billable Time. | Only approved billable entries, at the rate each was logged at. |
| 12 | Turn **Approve time and expenses** off and reload. | The Timesheet and Approvals pages say the setting is off; Log Time and totals behave as before 1.20 (approved and unstatused time counts). |

**Cleanup:** keep the project for T-PM-11.

## T-PM-11: Expenses (PM-08)

**Purpose:** confirm R-PM13.
**Prerequisites:** T-PM-10; turn on **Track expenses** and **Approve time and expenses**.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff A, project page, **Add Expense**: Travel, 42.50, billable. | "Expense added." The expense is Open. |
| 2 | On the Timesheet, add another expense and attach a receipt file when prompted. | The file is in the expense's Files list. |
| 3 | An expense of 0. | Refused: Amount must be more than 0. |
| 4 | **Submit Week**, then as the admin open **Approvals**. | The expenses are in staff A's week with the amount; approve. They are Approved and count in the project's Expense Amount. |
| 5 | Run Expenses This Month, and Time Awaiting Approval (with some time Submitted). | Each lists the right rows grouped as described. |
| 6 | Turn **Track expenses** off. | No Add Expense button and no expenses section on the Timesheet; existing expenses remain. |

**Cleanup:** None.
