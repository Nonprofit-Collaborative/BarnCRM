# Projects

Your admin turns on BarnCRM Project Management. You then see Projects Home, Projects and Time
Entries in the BarnCRM app. Setup detail: [Project Management](../admin-guide/projects.md).

## Projects Home

- **Projects at Risk**: active projects that are At Risk or Off Track, with the reasons. Check
  **Only Mine** to see only projects you own.
- **My Open Tasks**: tasks assigned to you that are not Done or Cancelled, soonest due first.
  **Done** marks one finished.
- **New Project From Template**: choose a template, a name and a start date, and optionally the
  client organization and contact. The new project opens with its phases and tasks dated from
  your start date.
- **Utilization** (when your admin tracks time): each person's hours in a date range against
  their capacity.
- **Export Billable Time** (admins): a CSV of billable time for your accounting system.

## A Project's Page

- The badge says On Track, At Risk or Off Track, with the reasons under it. **Refresh Health**
  checks again now; the morning run checks every active project.
- The progress line shows tasks done and the percent complete; with time tracking, the hours
  and the budget.
- Each phase shows its dates on the timeline, its progress and its tasks. Change a task's status
  from its menu; **Done** records today as its completed date. **Add Task** adds one to the
  phase.
- **Log Time** records your hours for a day, on a task or the project, billable or not.
- **Draft Status Update** writes a status update from the project (done since the last update,
  due in the next 14 days, risks). Open it from Status Updates, edit the words, then share it.

A milestone (such as Go-Live) is a task marked Milestone. A project is set to Active by its
owner when work starts; only active projects get a health.

## Time Entries

The Time Entries tab lists every entry; the This Week view shows the current week. Edit an entry
to fix its hours or task. Hours are more than 0 and at most 24 in a day.

## Staffing and Allocation (When Your Admin Manages Resources)

- A **Resource Request** on a project says what it needs: a role, skills, hours and dates.
- The **Staffing** tab lists open requests. **Fill** shows who could do the work, best first:
  people with every requested skill, then those whose Default Role is the requested role, then
  those with the most free capacity in the request's dates. People with only some of the skills
  are listed too, with how many they have. **Assign** creates the Project Assignment for that
  person and marks the request Filled.
- **People Who Can Be Staffed** holds each person's skills, weekly capacity (blank uses the
  organization's standard week, so a part-time person can have less) and default role. Mark
  someone inactive to take them off the lists.
- **Weekly Allocation** shows, for 4 to 26 weeks, each person's planned hours against capacity.
  An assignment's hours are spread over its working days (Monday to Friday); over capacity shows
  in red, point at a cell to see the hours logged, and the last row is the hours of requests not
  yet filled. Only approved time counts as logged when your organization approves time.


## Timesheet and Approvals (When Your Admin Turns Them On)

**Timesheet** shows your week, Monday to Sunday. Add a row for a project (and a task), type hours
in the day cells, then **Save**. When the week is done, **Submit Week**: Open and Rejected time
and expenses become Submitted and are locked while the project's owner decides. **Recall Week**
puts them back to Open if you need to change something before they are decided. A rejected entry
shows the reason; fix it and submit again. A cell cannot be emptied (staff cannot delete time):
change the hours, or ask a Projects admin to remove the entry. A cell with two or more entries
shows their total and is changed where they were logged.

Time you log from the project's **Log Time** is saved as Open too, and goes with the week when
you submit it.

**Approvals** is for project owners (Projects admins see every project). Time and expenses
submitted on your projects are grouped by person and week: **Approve** or **Reject** a whole
week, or open **Details** and decide one line. A rejection needs a reason, typed in the week's
Rejection Reason box. Approved time is locked and is the only time that counts in a project's
hours, cost, billable export and invoices.

## Expenses (When Your Admin Turns Them On)

**Add Expense** on a project, or on the Timesheet, records the date, category, amount, whether it
is billable and a description. Attach the receipt as a file on the expense when prompted, or from
its Files list later. With approvals on, expenses are submitted, approved or rejected with the
week, like time.

## Rates (Admins)

With rate cards on, each time entry keeps the bill rate it was logged at, from the person's rate,
else their role's, else the project's Hourly Rate. Changing a rate card later does not change
time already logged. On Projects Home, **Apply Rates** gives rates to time logged before rate
cards were turned on.

## Invoices, Financials and Change Requests (When Your Admin Turns Them On)

Your admin turns each part on in BarnCRM Settings, Projects.

- **New Invoice** (admins, on the project page): choose a period and a Draft invoice is built from
  the project's approved billable time, expenses, Done milestones or retainer months. Check the
  lines on the invoice, then **Send**. **Print** saves a PDF to the invoice's Files. **Mark Paid**
  records a payment the client made directly; **Void** cancels an invoice and frees its work to
  bill again. With BarnCRM Payments, **Send Payment Link** emails the client a link to pay online,
  and the invoice turns Paid when the payment goes through.
- **Export Invoices** (admins, Projects Home): a CSV of sent and paid invoices with their lines for
  your accounting system.
- **Financials** (project page): budget with approved changes, revenue to date, invoiced and
  unbilled, and recognized revenue month by month. Admins also see cost and margin, and can
  **Recognize Revenue** for a closed month again after correcting it.
- **Change Requests** (project page, Change Requests list): a scope change with the hours and
  amount it adds (or removes, as a negative). The project owner approves or rejects it; approved
  changes add to the budget the project is measured against.
