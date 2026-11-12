# Project Management: Rates, Approvals, Billing and Resources (PSA)

## What It Does

The PSA (professional services automation) parts of BarnCRM Project Management (release 1.20,
PM-06 to PM-12, D-197) are for organizations that staff, bill or account for project work, such
as a consultant running Salesforce implementations for clients, or a nonprofit that bills a
partner for program work. Each part has its own setting and ships off, so nothing changes until
you turn a part on. Turning Track time and budgets off hides every part.

| Part | Setting | What you get |
|---|---|---|
| Rate cards (PM-06) | Use rate cards | Bill and cost rates by person and role, kept on each time entry when it is logged |
| Timesheets and approvals (PM-07) | Approve time and expenses | A weekly timesheet; submit, approve or reject; approved time locked; only approved time counts |
| Expenses (PM-08) | Track expenses | Project expenses with a receipt, through the same approvals |
| Resource management (PM-09) | Manage resources | Skills and capacity per person, resource requests, a Staffing page and weekly allocation |
| Billing and invoices (PM-10) | Create invoices | Billing types, invoice records, a printable invoice, Export Invoices, and Pay Online through BarnCRM Payments when installed |
| Financials and revenue (PM-11) | Show financials and recognize revenue | Revenue, cost and margin against budget, and recognized revenue for each closed month |
| Change requests (PM-12) | Track change requests | Scope changes with hours and an amount; approved ones add to the budget |

Projects processes no payment of its own. Invoices are records for your own accounting; with the
BarnCRM Payments module installed, a client can pay an invoice online through your own Stripe or
PayPal account, and the payment marks the invoice Paid.

## Settings

BarnCRM Settings, **Projects** (org-wide):

| Setting | Default | What it does |
|---|---|---|
| Use rate cards | Off | Rates by person and role. Off: one Hourly Rate per project, as before. |
| Approve time and expenses | Off | Timesheets and approvals. Off: time and expenses count as soon as they are saved. |
| Track expenses | Off | The Project Expenses tab, Add Expense and expenses on the timesheet. |
| Manage resources | Off | The Staffing page, resource requests and the allocation view. |
| Create invoices | Off | Billing Type on projects, New Invoice, the invoice actions and Export Invoices. |
| Take invoice payments online | Off | Send Payment Link on a sent invoice. Needs Create invoices and the Payments module. |
| Invoice payment return page | Your My Domain address | The https page a client returns to after paying online, such as your website's thank you page. Filled in with your My Domain address at install. |
| Invoice due days | 30 | Days from the invoice date to its due date (1 to 365). |
| Show financials and recognize revenue | Off | The financials card on the project page and the monthly recognized revenue rows. |
| Track change requests | Off | Change requests on projects; approved ones add to the budget. |

## Who Approves

The project manager is the project's **owner**. The owner approves or rejects time, expenses and
change requests on the project; Projects Admin holders can approve anything. Anyone else is
refused, whatever page or tool they use. To hand a project to another manager, change its owner.

| Permission set | PSA access |
|---|---|
| Projects Admin | Everything: rates, invoices (build, send, mark paid, void, print, export, payment links), Apply Rates, Recognize Revenue, cost and margin |
| Projects Staff | Timesheets, expenses, resources, resource requests and change requests; read rates (bill rates only), invoices and revenue; no cost or margin |
| Projects Read Only | Read everything except cost and margin |

Cost rates are close to salaries, so Cost Rate, Cost Amount, Labor Cost and margin are seen only
with Projects Admin. A bookkeeper who is not a BarnCRM admin needs Projects Admin.

## Rate Cards (PM-06)

1. Turn on **Use rate cards**.
2. Open the **Project Rates** tab (BarnCRM Admin app) and add rates. Each rate is for one
   **Person** or one **Role** (the same words as the Role on Project Assignments, such as Project
   Manager or Data Migration), with a **Bill Rate**, an optional **Cost Rate** and the dates it
   applies.
3. When time is logged, its rates are worked out in this order and kept on the entry:
   - the person's rate for that date;
   - else the rate for their role on that project (their assignment), else their resource's
     Default Role;
   - else the project's **Hourly Rate** (bill rate only).
4. **Apply Rates** on Projects Home fills the rates of time logged before you turned rates on
   (entries not yet invoiced). Run it once after turning rates on.

A rate change never reprices time already logged. To reprice an entry, change it (its date or
person) before it is approved. With rate cards on, **Actual Cost** is the sum of each entry's
hours times the rate it was logged at.

## Timesheets and Approvals (PM-07)

With **Approve time and expenses** on:

- New time starts **Open**. People fill in the week on the **Timesheet** page (Monday to Sunday)
  and **Submit Week**; they can **Recall** it until it is decided.
- The project owner opens **Approvals** and approves or rejects each entry or a person's whole
  week. A rejection needs a reason, and the person fixes and resubmits.
- **Submitted** time can be changed only by the project owner or Projects Admin. **Approved**
  time is locked: only Projects Admin can change it. **Invoiced** time cannot change at all until
  its invoice is voided.
- Only approved time counts in Actual Hours, Billable Hours, utilization, Export Billable Time,
  invoices and revenue.

Time logged while approvals were off (and all time from before 1.20) has no Status and keeps
counting, so turning approvals on never removes hours from a project. Turning approvals off later
does not approve Open or Submitted time: approve it first.

## Expenses (PM-08)

With **Track expenses** on, add expenses from the project page (**Add Expense**), the timesheet,
or the **Project Expenses** tab: date, category, amount, billable, description, and the receipt
as a file on the expense (Files related list). With approvals on, expenses go through the same
submit, approve and lock steps as time. Expense categories can be added in Setup (Project
Expense, Category field).

## Resource Management (PM-09)

With **Manage resources** on:

- **Project Resources** tab: one record per person who can be staffed, with **Skills**, **Weekly
  Capacity Hours** (blank uses the Weekly capacity hours setting, so part-time people can have
  their own) and a **Default Role**. Edit the skills list in Setup, Picklist Value Sets,
  **Project Skills**.
- **Resource Requests** on a project: a role, skills, hours and dates the project needs.
- The **Staffing** tab lists open requests and the people who can be staffed (add or edit a
  person there; each person has one row). **Fill** shows people with all the requested skills
  first, then those whose Default Role is the requested role, then those with the most free
  capacity in the request's dates (their capacity for its working days less the hours already
  planned on their assignments), and creates the Project Assignment for the one you pick. People
  with only some of the skills are still listed, with the count.
- The **Weekly Allocation** view (below Staffing, 4 to 26 weeks) shows, week by week, each
  person's planned hours (assignments spread over their working days) against capacity, red when
  over, with logged hours on hover and unfilled requests as demand. Only active people with a
  Project Resource row appear; assignments of people without one are not shown.
- Utilization on Projects Home uses a person's own Weekly Capacity Hours when this is on, and
  counts only approved time as logged when approvals are on.

## Billing and Invoices (PM-10)

With **Create invoices** on, set each project's **Billing Type**:

| Billing Type | What New Invoice adds |
|---|---|
| Time and Materials (also blank) | Approved billable time in the period, one line per person and rate |
| Fixed Fee | Each milestone that is Done with a **Billing Amount** (set on the milestone task) |
| Retainer | One line per month at the project's **Retainer Amount** |
| Not Billed | No invoice |

Every billing type also adds approved billable expenses. Add other lines by hand while the
invoice is Draft.

1. **New Invoice** on the project page (Projects Admin) builds a **Draft** for a period. Work on
   it is marked invoiced so it is never billed twice; deleting a Draft frees it.
2. Check the lines, then **Send**: the Invoice Date and Due Date (plus Invoice due days) are filled
   in and the lines are locked.
3. **Print** saves a PDF of the invoice to its Files, to email from Salesforce or your mail.
4. When the client pays you directly, **Mark Paid** with the Paid Date. **Void** cancels an invoice
   and frees its work to be billed again; a void invoice stays void.
5. **Export Invoices** on Projects Home downloads sent and paid invoices with their lines as a
   CSV for your accounting system.

Invoice numbers are automatic (INV-000001 and up) and never reused.

### Pay Online (With BarnCRM Payments)

With the Payments module installed and set up (your own Stripe or PayPal keys), turn on **Take
invoice payments online**. On a Sent invoice, **Send Payment Link** emails the Bill To Contact a
secure checkout link for the amount still owed. When the processor reports the payment paid,
**Amount Paid** rises and, once it reaches the total, the invoice becomes **Paid** with the
payment's date. A refund made in Stripe or PayPal lowers Amount Paid and sets the invoice back to
Sent. Sending a new link replaces the old one. Without Payments the action does not show.
Projects never sees card details.

## Financials and Recognized Revenue (PM-11)

With **Show financials and recognize revenue** on, the project page shows a **Financials** card:
budget (Budget Amount plus approved changes), revenue to date, cost (Projects Admin), margin,
invoiced and unbilled, with a month by month table.

Revenue is earned by billing type: Time and Materials, approved billable time and expenses;
Fixed Fee, the fee (Budget Amount plus approved changes) times Percent Complete; Retainer, the
Retainer Amount for each month the project has run.

Each month, the nightly run (6:42 AM, **Project revenue**, which can be switched off in BarnCRM
Settings, Automation, Nightly Jobs) stores a **Project Revenue** row for the month just closed:
what was earned through that month less what earlier rows recognized. Stored months never move:
time approved late for a closed month, or a lower percent complete, lands in the next month. Edit
a row to adjust it, or delete it and use **Recognize Revenue** on the project to redo that month.

## Change Requests (PM-12)

With **Track change requests** on, add **Change Requests** on a project: a title, description, and
the hours and amount it adds (or removes, as a negative). Submit it; the project owner or Projects
Admin approves or rejects it. Approved changes are added to **Change Hours** and **Change Amount**
on the project, and the project is measured against Budget plus changes (Remaining Budget,
health, financials). Budget Hours and Budget Amount stay the original budget. Only Projects Admin
can change an approved request. The history of each request's status, hours and amount is kept.

## Reports

The BarnCRM Projects folder gains Time Awaiting Approval, Expenses This Month, Open Resource
Requests, Unbilled Approved Time, Invoices Outstanding and Recognized Revenue by Month.

## Common Mistakes

- A project's Actual Hours dropped after approvals were turned on: new time is Open until
  approved. Approve it, or look at the Awaiting Approval list view.
- Actual Cost shows 0 after turning on rate cards: run **Apply Rates** on Projects Home.
- New Invoice adds no time: the time is not approved, not billable, outside the period, already
  invoiced, or the project is Not Billed.
- Someone cannot approve: only the project's owner or Projects Admin can. Change the owner.
- Send Payment Link is missing: the Payments module is not installed, Take invoice payments online
  is off, or the invoice is not Sent.

## Removing the Module

Turning a PSA part off hides it and keeps its records. Uninstalling Project Management deletes
rates, expenses, resources, requests, invoices, invoice lines, revenue rows and change requests
with everything else; the Modules page counts them first. Payments records stay in Payments.
