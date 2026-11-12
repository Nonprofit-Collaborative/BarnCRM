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
