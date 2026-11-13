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
| 3 | Projects Home, **Apply Rates**. | "Time entries given rates: 1." The step 1 entry now has Bill Rate 175 and Amount 350; Cost Rate is visible to admin only (80). |
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

## T-PM-20: Invoices Off at Install

**Purpose:** confirm nothing changes while Create invoices, Show financials and recognize revenue,
and Track change requests are off (PM-10 to PM-12).
**Prerequisites:** T-PM-05; admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open BarnCRM Settings, Projects. | Create invoices, Take invoice payments online, Show financials and recognize revenue and Track change requests are off; Invoice due days 30; Invoice payment return page shows your My Domain address (https://...my.salesforce.com), not blank. |
| 2 | Open the project from T-PM-05. | No New Invoice card and no Financials card. |
| 3 | Open Projects Home. | No Export Invoices card. |

**Cleanup:** None.

## T-PM-21: Build, Send, Print and Void an Invoice

**Purpose:** confirm R-PM16 and R-PM17.
**Prerequisites:** T-PM-20; turn on Create invoices.

| Step | Action | Expected result |
|---|---|---|
| 1 | On a Time and Materials project, log 3 billable hours today for you and 2 for staff A. Add a billable 50 Travel expense (with Track expenses on). | Saved. |
| 2 | On the project, New Invoice with the period this month. | A Draft invoice opens (INV-000001 or the next number) with one Time line per person and rate and an Expense line; Total is the sum. |
| 3 | New Invoice again for the same period. | Refused: nothing to invoice. Nothing is billed twice. |
| 4 | On the invoice, Send. | Sent; Invoice Date today, Due Date 30 days later. Lines can no longer be edited. |
| 5 | Print. | A PDF named after the invoice is in the invoice's Files, with your organization's name, the lines and Balance Due. |
| 6 | Void, then confirm. | Void; the lines stay; the time entries' Invoice Line is blank again; New Invoice for the period builds a new Draft. |
| 7 | As staff A, open the new invoice and the project. | No invoice actions and no New Invoice. |

**Cleanup:** Delete the Draft from step 6.

## T-PM-22: Fixed Fee and Retainer Invoices, Mark Paid and Export

**Purpose:** confirm the other billing types and the CSV.
**Prerequisites:** T-PM-21.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set a project's Billing Type to Fixed Fee; give a milestone a Billing Amount of 1000 and mark it Done. | Saved. |
| 2 | New Invoice for this month. | One Milestone line of 1000. |
| 3 | Set another project to Retainer with Retainer Amount 500 and a Start Date last month; New Invoice from the first of last month to today. | Two Retainer lines of 500. Running it again for the same months adds none. |
| 4 | Send both; on one, Mark Paid with yesterday's date. | Paid, with that Paid Date and an Amount Paid equal to the Total. Deleting either Sent or Paid invoice is refused with a message to Void it instead. |
| 5 | Projects Home, Export Invoices for this month. | A CSV with one row per line and the invoice columns; the invoices' Exported Date is today. Exporting again gives only the heading line unless Include invoices already exported is checked. |
| 6 | Set a project to Not Billed and open it. | No New Invoice. |

**Cleanup:** None.

## T-PM-23: Pay Online Through BarnCRM Payments

**Purpose:** confirm R-PM22 (needs the Payments module set up with test keys).
**Prerequisites:** T-PM-22; Payments installed and set up; turn on Take invoice payments online.

| Step | Action | Expected result |
|---|---|---|
| 1 | Give a Sent invoice a Bill To Contact with your email; Send Payment Link. | A message that the link was emailed; Payment Link and Payment Key are filled. |
| 2 | Open the email and pay with a Stripe or PayPal test card. | After Payments processes the event: Amount Paid equals Total, Status Paid, Paid Date the payment's date. |
| 3 | Refund part of the payment in the processor. | After processing: Amount Paid drops by the refund and the invoice is Sent again. |
| 4 | Turn Take invoice payments online off (or test without Payments installed). | Send Payment Link does not show. |

**Cleanup:** None.

## T-PM-24: Financials and Recognized Revenue

**Purpose:** confirm R-PM19 and R-PM21.
**Prerequisites:** T-PM-21; turn on Show financials and recognize revenue.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the project. | A Financials card: budget, revenue to date, cost and margin (admin), invoiced and unbilled, and a month table ending with this month (open). |
| 2 | As staff A, open the project. | The card without cost and margin. |
| 3 | As admin, Recognize Revenue for last month. | A Project Revenue row for last month (Revenue related list) with Method and Recognized Amount; Recognized Revenue on the project matches. |
| 4 | Log 1 billable hour dated last month, then Recognize Revenue for this month's first day. | Refused: the open month is never stored. |
| 5 | Recognize Revenue for last month again. | The step 3 row is updated, not duplicated: its Recognized Amount now includes the hour logged in step 4. |
| 6 | In BarnCRM Settings, Automation, Nightly Jobs. | Project revenue at 6:42 AM, switched on. |
| 7 | Open Reports, BarnCRM Projects; run Unbilled Approved Time, Invoices Outstanding and Recognized Revenue by Month. | Each runs: approved billable time not yet invoiced, Sent invoices with their due dates and lines, and the recognized amount by month. |

**Cleanup:** None.

## T-PM-25: Change Requests

**Purpose:** confirm R-PM20.
**Prerequisites:** T-PM-05; turn on Track change requests.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff A, add a Change Request on a project with Budget Hours 10: 10 hours, 1000. Try to set it Approved. | Refused: only the project owner or Projects Admin decides. |
| 2 | As the project owner, approve it. | Change Hours 10 and Change Amount 1000 on the project; Remaining Budget rises by 1000; Budget Hours stays 10. |
| 3 | Log 12 hours and Refresh Health. | Not over budget (12 of 20). The board's hours line shows the budget with the change. |
| 4 | As staff A, edit the approved request's hours. | Refused: only Projects Admin. |
| 5 | Turn off Track change requests. Add another change request. Open the project. | The new request is refused ("Change requests are turned off..."); the approved one still counts (Change Hours 10). |

**Cleanup:** None.

## T-PM-30: Requests Off at Install, Then Staff Requests

**Purpose:** confirm the switch, R-PM23 and the Requests tab (D-201).
**Prerequisites:** T-PM-01. A Contact with an email address you can read (the requester).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Requests tab. Try to save a new Request from the Request object. | The tab says requests are off; the save is refused ("Requests are turned off..."). |
| 2 | Turn on Track requests and issues. As staff A, **New Request**: subject, priority High, the requester. Save. | Saved with Channel Staff, a due date two weekdays from today, Requesting Organization the requester's account. |
| 3 | On the Requests tab, **My Open**. | The request is listed with its number, status New and due date. |
| 4 | Open it. Set Status Resolved with no resolution. Save. | Refused: "Enter a resolution before marking the request Resolved." |
| 5 | Add an internal comment, then a comment with Share with requester checked. | Both in the thread, marked Internal and Shared; the requester gets one email, for the shared comment. |
| 6 | Enter a Resolution, set Resolved, Save. | Resolved Date set; the requester is emailed the resolution; the request moves to Recently Closed. |

**Cleanup:** Delete the request.

## T-PM-31: Assigning, Queues, Overdue and Linked Work

**Purpose:** confirm assignment notices, the Requests queue, Overdue, Create Task and Create
Change Request.
**Prerequisites:** T-PM-30; Track change requests on; a project.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the admin, open a request and set its Owner to staff A. Save. | Staff A gets a bell notice "Request REQ-... assigned to you". |
| 2 | On the request record page, change Owner to the Requests queue. | It appears in **Unassigned**. |
| 3 | Set a request's Due Date to yesterday, Status In Progress. Then set Status Waiting on Requester. | Listed under **Overdue** with the due date in red; once Waiting on Requester it is no longer Overdue. |
| 4 | Create Task with no project. | Refused: "Choose the request's project and save first." |
| 5 | Choose the project, Save, then **Create Task** and **Create Change Request**. | A task named from the subject on the project and a Draft change request, both shown on the panel; a New request moves to In Progress. |
| 6 | Log time on the project with Request set to this request. | The time entry shows in the request's Time Entries list. |
| 7 | Run the reports Open Requests, Overdue Requests and Requests Resolved This Month. | Each lists the matching requests. |

**Cleanup:** Delete the requests, task and change request.

## T-PM-32: Requests From the Portal

**Purpose:** confirm the Requests portal template, R-PM24 and the reply inbox (D-201).
**Prerequisites:** T-PM-30; BarnCRM Portal Builder set up with a test portal page; the requester
Contact from T-PM-30.

| Step | Action | Expected result |
|---|---|---|
| 1 | With Take requests from outside off, paste `requests.json` into a portal and sign in as the requester. Send a new request. | Refused; nothing is saved. |
| 2 | Turn on Take requests from outside. Send a request: subject, type, priority Medium, details. | Listed under My Requests with its number and status New; in Salesforce it has Channel Portal, Owner the Requests queue, and the queue members get a bell notice. |
| 3 | In the portal, change the priority to Urgent and save. | The priority stays Medium. |
| 4 | As staff, add a shared comment and an internal comment, and set Status Waiting on Requester. | The requester is emailed the shared comment; **Updates** in the portal shows only the shared one. |
| 5 | In the portal, enter Add a Reply and save. | The reply appears in the request's thread as Shared from the requester; Add a Reply is blank again; the status is In Progress. |
| 6 | Resolve the request with a resolution. In the portal, set Satisfied? to Satisfied. | The portal shows the resolution; Satisfaction is Satisfied on the request. |
| 7 | Sign in as another person. | Neither the request nor its updates are listed. |

**Cleanup:** Delete the request and the test portal.

## T-PM-33: Requests From Another Organization

**Purpose:** confirm the request API and R-PM26 (D-201).
**Prerequisites:** T-PM-30; Take requests from outside on; an integration user with Projects
Request Intake and an External Client App with client credentials run as that user; a REST
client (Postman, or Workbench REST Explorer signed in as that user).

| Step | Action | Expected result |
|---|---|---|
| 1 | Without a Request Connection, `POST /services/apexrest/barncrm/requests/v1/requests` with `orgId` your org id, `reference` T-1, `subject`. | `403 not_allowed`; nothing saved. |
| 2 | On the Request Connections tab, add one: a name, an Account, your org id, the integration user, Hourly Limit 2. Send the same call. | `201` with a number and status New. The request has Channel Partner Organization, the connection's Account, Owner the Requests queue. |
| 3 | Send it again. | `200` with the same number; still one request. |
| 4 | Send references T-2 and T-3. | T-2 is `201`; T-3 is `429 too_many`. |
| 5 | Resolve T-1 with a resolution. `GET ...requests?orgId=<org id>&refs=T-1,T-2`. | Both listed; T-1 Resolved with the resolution. |
| 6 | Untick Active on the connection and send T-4. Send a body that is not JSON. | `403 not_allowed`; then `400 bad_request`. |

**Cleanup:** Delete the requests and the connection.
