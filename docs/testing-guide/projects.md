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
