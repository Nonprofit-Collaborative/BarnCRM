# ADR-0219: Projects PSA: rate cards, time and expense approvals, resource management, invoices, recognized revenue and change requests, each behind its own setting

**Status:** Accepted (builder decision, for Brandon to confirm)
**Date:** 2026-11-12
**Source:** D-197 (Brandon, 2026-11-12: "With 1.20, also please build out the full featured PSA
tool"), plan Section 6.0a release 1.20, items PM-06 to PM-12. Supersedes ADR-0208
`0208-project-management-module.md` decision 6 (light PSA) and decision 7 (no invoice) where
they conflict; keeps every other ADR-0208 decision. Builds on ADR-0017 and ADR-0024 (trigger
dispatcher and automation registry), ADR-0131 and ADR-0194 (module sets follow roles, fewer
sets), ADR-0164 (help text JSON), ADR-0166 (nightly dispatcher) and ADR-0192 (module tabs in
the BarnCRM apps), and on ADR-0201 and ADR-0207 (the Payments seam by name, as Events uses it).
D-197 was amended on 2026-11-12 (Brandon): with the Payments module installed, an invoice can be
paid online through Payments' hosted checkout and a paid payment marks it Paid, through Payments'
listener extension, so Projects stays dependent on Core only. Projects itself processes no
payment.

## Context

ADR-0208 shipped a light PSA layer (time, assignments, budgets, utilization, a billable time
CSV) and listed per-person rates, skills and scheduling, approvals, expenses and revenue
recognition as the next steps. D-197 asks for all of them in release 1.20, plus invoice
records, with no payment processing in Projects (online payment only through the Payments
module, when installed). Many organizations use Project Management only for
planning; the Track time and budgets setting already hides time for them, and D-197 asks that
each PSA part have its own switch so nothing changes for an organization until it turns a part
on.

The Projects Apex is small and the shared Apex budget is tight, so the design leans on
roll-up summaries, formulas and validation rules wherever they replace Apex, and adds one
object only where a field or an existing object cannot do the job. For each object and key
field below, "Without it" names what breaks.

## Decision

### 1. Settings: one switch per PSA part, all off at install

`Projects_Settings__c` gains seven checkboxes and one number, each with a Setting Definition
row in the Projects section (module `Projects`, Help Path `projects-psa.md`):

| Setting (Setting Definition) | Field | Default | Part |
|---|---|---|---|
| Use rate cards (`Projects_Rates_Enabled`) | `Rates_Enabled__c` | Off | PM-06 |
| Approve time and expenses (`Projects_Approvals_Enabled`) | `Approvals_Enabled__c` | Off | PM-07 |
| Track expenses (`Projects_Expenses_Enabled`) | `Expenses_Enabled__c` | Off | PM-08 |
| Manage resources (`Projects_Resources_Enabled`) | `Resources_Enabled__c` | Off | PM-09 |
| Create invoices (`Projects_Billing_Enabled`) | `Billing_Enabled__c` | Off | PM-10 |
| Show financials and recognize revenue (`Projects_Revenue_Enabled`) | `Revenue_Enabled__c` | Off | PM-11 |
| Track change requests (`Projects_Change_Requests_Enabled`) | `Change_Requests_Enabled__c` | Off | PM-12 |
| Take invoice payments online (`Projects_Online_Payments_Enabled`) | `Online_Payments_Enabled__c` | Off | PM-10 |
| Invoice payment return page (`Projects_Invoice_Return_Url`) | `Invoice_Return_Url__c` | The org's My Domain address, filled in at install (never blank) | PM-10 |
| Invoice due days (`Projects_Invoice_Due_Days`) | `Invoice_Due_Days__c` | 30 (1 to 365) | PM-10 |

Every part ships off because each changes what an existing page shows or counts. Track time
and budgets stays the master switch: when it is off, every PSA part is hidden whatever its own
setting says. With every PSA switch off, the module behaves exactly as release 1.18: one
Hourly Rate per project, time counts when it is saved, no invoice.

Without per-part switches, an organization that wants only approvals would also get invoices
and rate cards on its pages; D-197 asks for them.

### 2. Rates (PM-06): a rate card object, resolved in order, snapshot on the time entry

**Project Rate (`Project_Rate__c`)**: one row is either a person's rate (Person, a User) or a
role's rate (Role, the same text as a Project Assignment's Role), never both (validation rule),
with a Bill Rate (required), an optional Cost Rate, Effective From (required) and Effective To.
Org-wide, Public Read Only, edited by Projects Admin. Without it there is nowhere to say that
two people on the same project bill differently, which is PM-06's point.

**Resolution order (R-PM9), for a time entry's person, project and date:**

1. the person's rate whose dates cover the entry's date (latest Effective From wins);
2. else the role's rate, for the person's role on that project (their Project Assignment whose
   dates cover the date, else any assignment on the project), else their Project Resource's
   Default Role (PM-09), whose dates cover the entry's date;
3. else the project's Hourly Rate as the Bill Rate, with no Cost Rate.

Bill Rate and Cost Rate resolve separately down the same order: a person row with no Cost Rate
leaves the cost to the role row. Project-specific rate cards (a client's discounted rate) are
not built: the project Hourly Rate covers a flat project rate, and a project-level override
can be added later as a fourth, first tier without changing stored data.

**Snapshot.** `Time_Entry__c` gains Bill Rate and Cost Rate, written when the entry is created
and again when its date, person, project or task changes, while it is neither approved nor
invoiced. Formulas Amount (Hours times Bill Rate) and Cost Amount (Hours times Cost Rate) feed
roll-ups. Without the snapshot a rate change would rewrite past revenue and cost, which is
what PM-06 says must not happen. Entries logged before rates were turned on have no rate until
**Apply Rates** (Manage Projects, on Projects Home) stamps every unlocked entry with a blank
Bill Rate; there is no nightly rate job.

**Rates off:** nothing is stamped; Actual Cost stays Actual Hours times Hourly Rate. Rates on:
Actual Cost becomes the sum of the entries' Amounts (`Time_Amount__c`); the formula reads
`$Setup.Projects_Settings__c.Rates_Enabled__c`, so no Apex decides it.

**Cost is admin-only.** Cost Rate, Cost Amount, Labor Cost and a revenue month's Cost Amount
are readable only with Projects Admin: cost rates are close to salaries. Staff and Read Only
see bill rates and amounts.

### 3. Timesheets and approvals (PM-07): status on the time entry, no Timesheet object

`Time_Entry__c` gains **Status** (Open, Submitted, Approved, Rejected; not required, no
default), **Approved By** (User) and **Rejection Reason**. The weekly timesheet is a grid
(Monday to Sunday) over a person's entries, not a record.

Why not a Timesheet object per person per week: a week's time spans several projects whose
managers differ, so a timesheet record would need one approver per line anyway, and it would
add an object, a parent lookup, roll-ups and a create-on-first-entry rule for no state the
entries cannot hold. Submit, approve, reject and lock all work per entry; the grid groups them.

- **Counted time (R-PM10).** An entry counts as actual, billable and exportable when its Status
  is blank or Approved. Blank is time logged while approvals were off (and all time before
  1.20), so turning approvals on never un-counts history and no data migration is needed. The
  roll-ups `Actual_Hours__c` and `Billable_Hours__c` filter Status not equal to Open,
  Submitted, Rejected, and so do the new roll-ups.
- **Flow (R-PM11).** With approvals on, a new entry starts Open (set on insert by the entry
  handler when Status is blank). The person submits a week (Open and Rejected entries of that
  week become Submitted) and may recall it (Submitted back to Open) until it is decided. The
  project manager approves or rejects each entry or a whole person-week; a rejection needs a
  reason.
- **Who approves.** The project manager is the project's **owner** (`Project__c.OwnerId`): no
  new field, and My Projects and Only Mine already mean "projects I manage". Projects Admin
  (Manage Projects) can approve anything. Validation rule `Approval_By_Manager` refuses
  Approved or Rejected from anyone else, so the rule holds for every path (grid, list edit,
  API).
- **Locks (validation rules).** `Locked_When_Submitted_Or_Approved`: a Submitted entry's hours,
  date, person, task, billable flag and rates can be changed only by the project manager or
  Projects Admin; an Approved entry's (and its Status) only by Projects Admin. `Locked_When_Invoiced`:
  an entry on an invoice line cannot change at all, by anyone, until the invoice is voided.
  `Status_Not_Cleared`: Status cannot be set back to blank. A rate written for the first time
  (blank before) is allowed through the locks, so Apply Rates can fill older approved entries.
- Staff cannot delete time (unchanged), so a lock cannot be dodged by deleting.
- **Approvals off:** the handler leaves Status blank and everything counts as today.

Without Status on the entry, "only approved time is billed, exported or counted as actual"
cannot be a roll-up filter and would need Apex wherever totals are read.

### 4. Expenses (PM-08): one object, the same flow

**Project Expense (`Project_Expense__c`)**, master-detail to Project: Person, Date, Category
(Travel, Lodging, Meals, Mileage, Software, Supplies, Other; open picklist), Amount (more than 0),
Billable, Description, and the same Status, Approved By, Rejection Reason and Invoice Line as a
time entry, with the same validation rules. The receipt is a file on the expense (Files related
list), so no field holds it. Project gains `Expense_Amount__c` (roll-up of counted expenses).
Without the object, expenses could only be typed into invoices by hand and never reach cost,
margin or approval.

### 5. Resource management (PM-09): a resource per person, requests per project, allocation computed

- **Skills: a global value set, not an object.** `Project_Skills` (a global picklist value set
  the admin edits in Setup) feeds two multi-select fields. A Skill object plus a junction would
  add two objects for a list of names; levels of skill are not built.
- **Project Resource (`Project_Resource__c`)**: one per person who can be staffed: Person
  (User, required), Skills, Weekly Capacity Hours (blank uses the Weekly capacity hours
  setting), Default Role and Active. Without it there is nowhere to hold a person's skills or a
  part-time person's capacity: Salesforce rules out custom fields on User here (ADR-0013 keeps
  standard objects to Account, Contact and User lookups). One row per person is kept by the
  Staffing page, which edits the existing row; if a second row is made by hand, the oldest wins.
- **Resource Request (`Resource_Request__c`)**, master-detail to Project: Role (required),
  Skills, Hours (required, more than 0), Start Date and End Date (required, end on or after
  start), Status (Open, Filled, Cancelled; default Open), Assignment (the Project Assignment
  that filled it, same project) and Notes. **Fill** on the Staffing page picks a person (people
  whose skills include all requested skills are listed first, then by free capacity in the
  dates), creates the Project Assignment with the request's role, hours and dates, links it and
  sets Filled (R-PM15). Without the object, a need for "a data migration specialist, 60 hours in
  March" has no record until someone is picked.
- **Allocation view: computed, not stored (R-PM14).** For each active resource and each week
  in a range, allocated hours are their Project Assignments' Planned Hours spread evenly over the
  assignment's working days (Monday to Friday, Start Date to End Date) that fall in the week,
  against their capacity; open Resource Requests show as unfilled demand. Logged hours come from
  counted time. Worked out in the browser in a framework-free module, as utilization is
  (R-PM5). A stored allocation row would only copy what the assignments already say.

### 6. Billing (PM-10): billing type per project, invoice records, online payment only through the Payments module

- `Project__c` gains **Billing Type** (Time and Materials, Fixed Fee, Retainer, Not Billed;
  default Time and Materials; blank on older projects reads as Time and Materials) and
  **Retainer Amount** (per month). Fixed Fee uses the project's Budget Amount plus approved
  changes as the fee.
- **Milestone billing.** `Project_Task__c` gains **Billing Amount** (only on a milestone,
  validation rule `Billing_Amount_On_Milestone`) and **Invoice Line**. A milestone is billable
  once Done. Without the field, fixed fee projects could not be billed in parts.
- **Project Invoice (`Project_Invoice__c`)**, master-detail to Project: Invoice Number (auto
  number `INV-{000000}`), Bill To (Account) and Bill To Contact (both copied from the project's
  client when built, editable), Status (Draft, Sent, Paid, Void; default Draft), Invoice Date,
  Due Date (Invoice Date plus Invoice due days, set on Send when blank), Period Start, Period
  End, Paid Date, Exported Date, Notes (printed) and Total (roll-up of its lines). One invoice
  is for one project; a client invoice covering several projects is not built.
- **Numbering.** An auto number: atomic, never reused, a voided invoice keeps its number. The
  display format can be changed in Setup by an organization that wants its own prefix.
- **Project Invoice Line (`Project_Invoice_Line__c`)**, master-detail to the invoice: Type
  (Time, Expense, Milestone, Retainer, Other), Description, Service Date, Quantity, Unit Price,
  Amount (formula Quantity times Unit Price). Lines can be added, changed or removed only while
  the invoice is Draft (validation rule `Draft_Invoice_Only` on add and change).
- **What marks work invoiced.** A lookup **Invoice Line** on the time entry, the expense and
  the milestone task: filled means invoiced. Each lookup clears itself when the line is deleted
  (Set Null), so deleting a Draft invoice frees its work with no Apex. Voiding an invoice clears
  the lookups (the Void action), so the work can be billed again; the void invoice keeps its
  lines as a record. No separate Invoiced checkbox: it would duplicate the lookup.
- **Building an invoice (R-PM16).** **New Invoice** (Manage Projects) on the project page, for a
  period, adds as a Draft: Time and Materials: counted billable time in the period not yet
  invoiced, one line per person and Bill Rate (Quantity hours, Unit Price the rate; entries
  with no rate use the project's Hourly Rate); Fixed Fee: each Done milestone with a Billing
  Amount, completed by the period end and not invoiced, one line each; Retainer: one Retainer line
  per month of the period that has no line yet on an invoice that is not Void, at the Retainer
  Amount; for every billing type, counted billable expenses in the period not yet invoiced, one
  line each. Not Billed projects build no invoice. Other lines are added by hand.
- **Status (R-PM17).** Draft, then **Send** (stamps Invoice Date and Due Date when blank), then
  **Mark Paid** (Paid Date, entered by the admin: BarnCRM takes no payment), or **Void** from
  any of them, which releases the work. Void is final (validation rule `Void_Is_Final`).
- **Printable invoice.** **Print** saves a PDF of the invoice to its Files, made from HTML with
  `Blob.toPdf` as Giving's receipts are; no Visualforce page.
- **Pay Online through BarnCRM Payments (D-197 as amended 2026-11-12).** With the Payments
  module installed and Take invoice payments online on, **Send Payment Link** (Manage Projects)
  on a Sent invoice starts a checkout on the organization's own Stripe or PayPal for the Total
  less Amount Paid, stores the payment's record id in **Payment Key** and the hosted checkout
  address in **Payment Link**, and emails the link to the Bill To Contact. Projects reaches
  Payments the way Events does (ADR-0207, `EventPayments`): `NamespaceUtil.build('PaymentsApi',
  Callable.class, ...)` returns null when Payments is not installed (the action is hidden), and
  `startCheckout` is called with `sourceRecordId` the invoice and `listener`
  `ProjectInvoicePaymentListener`, a `System.Callable` in Projects that Payments builds by name.
  Neither package depends on the other; Projects still depends on Core only (R-PM22).
  - **Paid transition (R-PM22).** Only a report for the invoice's current Payment Key changes
    it: Paid adds the amount to **Amount Paid** and, once Amount Paid reaches Total, sets Status
    Paid and Paid Date to the payment's paid date; Failed and Cancelled change nothing (the link
    can be sent again, replacing the key); a refund lowers Amount Paid and, below Total, sets a
    Paid invoice back to Sent. A Void invoice is never changed by a report (the event is logged).
    BarnCRM issues no refund and keeps no card data; the processor and Payments do the charging.
  - Without the seam, an online payment would need Projects to depend on Payments, which would
    make every planning-only organization install it.
- **CSV for accounting.** **Export Invoices** (Manage Projects, Projects Home) downloads Sent
  and Paid invoices and their lines in a date range with Core's `c/findCsv` and stamps Exported
  Date, as Export Billable Time does for time.

### 7. Financials and recognized revenue (PM-11): stored monthly rows for closed months, computed for the open one

- **Financials card (R-PM21)**, computed on demand from roll-ups: budget (Budget Amount plus
  approved changes), revenue to date (Time and Materials: Billable Amount plus counted billable
  expenses; Fixed Fee: fee times Percent Complete; Retainer: Retainer Amount times months active
  to date), cost (Labor Cost plus Expense Amount, Projects Admin only), margin (revenue less
  cost, and as a percent), invoiced (Sent and Paid totals) and unbilled (revenue less invoiced),
  with a month by month table.
- **Recognized revenue: a stored row per project per closed month (R-PM19).** **Project Revenue
  (`Project_Revenue__c`)**, master-detail to Project: Month (first day), Method (Time and
  Materials, Fixed Fee, Retainer), Recognized Amount, Cost Amount, Percent Complete (Fixed Fee)
  and Month Key (unique: project id and `YYYY-MM`, so a rerun upserts). A stored row is needed:
  computed on demand, a closed month would change whenever time for it is approved late, a task
  is added (lowering Percent Complete) or a rate is corrected, and an organization's books cannot
  move under a month it has closed.
- **Cumulative rule.** For the month just closed, Recognized Amount is revenue earned through
  that month's last day, as counted now, less every earlier row's Recognized Amount; Cost Amount
  likewise. Time approved late for a closed month lands in the next closed month; a fixed fee
  project whose percent complete drops gets a negative adjustment. Time and Materials earns
  counted billable time and expenses dated through the month end; Fixed Fee earns fee times
  Percent Complete plus counted billable expenses; Retainer earns the Retainer Amount for each
  month from Start Date to the month (through Completed Date when set) plus counted billable
  expenses. Not Billed projects get no rows. Project gains `Recognized_Revenue__c` (roll-up of
  the rows). The open month is computed on the card, never stored.
- **Nightly work.** One new step of the existing nightly run, **Project revenue** (6:42 AM, its
  own switch, on, acting only when Show financials and recognize revenue is on): on the first
  run of a month it writes the rows for the month just ended for Active, On Hold and projects
  Completed in that month, capped at 2,000 projects with an Error Log warning past it (as health
  is). An admin can edit a row (an adjustment) or delete it and rerun **Recognize Revenue** on the
  project page for that month.

### 8. Change requests (PM-12): approval adjusts the budget by roll-up

**Change Request (`Project_Change_Request__c`)**, master-detail to Project: title (name),
Description, Hours and Amount (either may be negative), Status (Draft, Submitted, Approved,
Rejected; default Draft). History tracking is on for Status, Hours and Amount, so who decided and
when is in the field history with no Approved By field.

Project gains `Change_Hours__c` and `Change_Amount__c`, roll-ups of Approved change requests.
The budget a project is measured against is Budget Hours plus Change Hours and Budget Amount
plus Change Amount: Remaining Budget's formula adds Change Amount, the health rule (R-PM2)
compares Actual Hours with Budget Hours plus Change Hours, and the board and financials show
both. Budget Hours and Budget Amount stay the original budget, so the history is never
overwritten. Approval therefore needs no Apex: validation rule `Decision_By_Manager` lets only
the project owner or Projects Admin set Approved or Rejected, and `Approved_Locked` lets only
Projects Admin change an Approved request (which moves the budget back by itself). Without the
object, a budget change has no reason, amount or approval on record.

### 9. Permission sets (ADR-0194: no new set)

No new permission set and no Billing extra permission. Billing, rates and revenue are admin
work in the organizations this module serves; ADR-0194 asks for fewer sets, and an extra
permission would be a fourth Projects set to keep in step. A bookkeeper who is not a BarnCRM
admin is given Projects Admin.

| Object | Projects Admin | Projects Staff | Projects Read Only |
|---|---|---|---|
| Project Rate | Create, edit, delete | Read (no Cost Rate) | Read (no Cost Rate) |
| Project Expense | All | Create, edit (own flow) | Read |
| Project Resource | All | Create, edit | Read |
| Resource Request | All | Create, edit | Read |
| Project Invoice, Invoice Line | All | Read | Read |
| Project Revenue | All | Read (no Cost Amount) | Read (no Cost Amount) |
| Change Request | All | Create, edit | Read |

Approving is not a permission: it is being the project's owner (or Projects Admin), checked by
validation rule. Manage Projects (Projects Admin) builds, sends, voids and exports invoices, sends payment links,
runs Apply Rates and Recognize Revenue. New fields on Project, Time Entry and Project Task follow
the existing sets, with cost fields admin-only.

### 10. Tabs, pages and reports

- Object tabs: **Project Expenses** and **Project Resources** join Staff_Tabs (BarnCRM and
  BarnCRM Console); **Project Rates** and **Project Invoices** join Admin_Tabs (the admin apps).
  Error Log stays last. The Timesheet, Approvals and Staffing pages are Lightning page tabs the
  builders add next to Projects Home.
- Page layouts for Project (every new related list), Time Entry, Project Expense (with Files)
  and Project Invoice (with its lines); one invoice record page with the actions (builder C).
- Reports (BarnCRM Projects folder): Time Awaiting Approval, Unbilled Approved Time, Expenses
  This Month, Open Resource Requests, Invoices Outstanding and Recognized Revenue by Month, on
  report types Project Expenses, Project Invoices with Lines, Resource Requests and Project
  Revenue (each builder ships its own).

## Implementation split

The model PR (`feature/psa-model`) ships every object, field, validation rule, roll-up,
formula, list view, tab, layout, global value set, setting field and Setting Definition, the
`ProjectsSettings` accessors (`ratesEnabled`, `approvalsEnabled`, `expensesEnabled`,
`resourcesEnabled`, `billingEnabled`, `revenueEnabled`, `changeRequestsEnabled`,
`onlinePaymentsEnabled`, `invoiceDueDays`, `invoiceReturnUrl`; each switch also false when
Track time and budgets is off), field and object access
in the three permission sets, the `ownedObjects` and catalog tab rows in Core, the admin guide
page `projects-psa.md` and the feature catalog rows. Builders cut from it and own only their
own files, except the shared ones listed.

### Builder A: PM-06 rates, PM-07 timesheets and approvals, PM-08 expenses

- Apex: `ProjectRates` (resolver, R-PM9; `stamp(List<SObject>)` and Apply Rates);
  `ProjectEntryHandler` (TriggerHandler for Time Entry and Project Expense: Open on insert with
  approvals on, rate snapshot) with triggers `TimeEntryTrigger` and `ProjectExpenseTrigger`
  (before insert, before update) and registry rows `Automation_Registry.Time_Entry_Rates_And_Status`
  and `Automation_Registry.Project_Expense_Status` (Always Runs); `ProjectTimesheetController`
  (week read and save, submit, recall, add expense); `ProjectApprovalsController` (queue for the
  user's projects or all with Manage Projects, approve, reject with reason, by entry or
  person-week; stamps Approved By); tests `ProjectRatesTest`, `ProjectEntryHandlerTest`,
  `ProjectTimesheetControllerTest`, `ProjectApprovalsControllerTest`.
- LWC: `projectsTimesheet` (weekly grid with expenses), `projectsApprovals` (queue),
  `projectsTimesheetModel` (framework-free week math and totals); Lightning page tabs and
  flexipages `Projects_Timesheet` and `Projects_Approvals`.
- Reports: Time Awaiting Approval, Expenses This Month; report type Project Expenses.
- Shared files it edits: `ProjectReporting` (Export Billable Time counts only counted time:
  method `billableTime` only), `ProjectsController` and `projectBoard` (Log Time shows Status;
  Add Expense), `Projects_Home` flexipage (Apply Rates action), `BarnHelp_Projects.json` (keys
  prefixed `Projects_Rates_`, `Projects_Timesheet_`, `Projects_Approvals_`, `Projects_Expense_`).

### Builder B: PM-09 resource management

- Apex: `ProjectStaffingController` (resources, requests, candidates for a request, Fill,
  allocation rows for a week range); test `ProjectStaffingControllerTest`.
- LWC: `projectsStaffing` (resources and open requests, Fill), `projectsAllocation` (weekly
  allocation against capacity), `projectsAllocationModel` (framework-free R-PM14); Lightning page
  tab and flexipage `Projects_Staffing`.
- Reports: Open Resource Requests; report type Resource Requests.
- Shared files it edits: `ProjectReporting` (utilization reads a resource's capacity: method
  `utilization` only), `BarnHelp_Projects.json` (keys prefixed `Projects_Staffing_`,
  `Projects_Allocation_`).

### Builder C: PM-10 billing and invoices, PM-11 financials and revenue, PM-12 change requests

- Apex: `ProjectBilling` (build, send, mark paid, void, R-PM16 and R-PM17),
  `ProjectBillingController` (AuraEnabled entry points, invoice export rows),
  `ProjectInvoiceDocument` (PDF to Files), `ProjectInvoicePayments` (Send Payment Link through
  `PaymentsApi` by name, R-PM22) and `ProjectInvoicePaymentListener` (`System.Callable`,
  `@NamespaceAccessible`, answers `paymentsChanged` in bulk; name permanent once released), `ProjectFinancials` (R-PM21 card data),
  `ProjectRevenue` (R-PM19 rows, `NightlyStep`, Recognize Revenue); tests
  `ProjectBillingTest`, `ProjectFinancialsTest`, `ProjectRevenueTest`,
  `ProjectInvoicePaymentsTest` (an injected `Callable` stands in for Payments, and the listener
  is called directly, as `EventPaymentsTest` does). Change requests need no
  Apex beyond the health change.
- LWC: `projectsInvoiceBuilder` (New Invoice on the project page), `projectsInvoiceActions`
  (Send, Mark Paid, Void, Print on the invoice page), `projectsFinancials` (project page card),
  `projectsBillingExport` (Export Invoices on Projects Home), `projectsBillingModel`
  (framework-free line grouping and recognition math); flexipage `Project_Invoice_Record_Page`
  with its assignment in the object's action overrides.
- Reports: Unbilled Approved Time, Invoices Outstanding, Recognized Revenue by Month; report types
  Project Invoices with Lines, Project Revenue.
- Shared files it edits: `ProjectHealth` (budget plus Change Hours), `ProjectsNightlyJobProvider`
  (adds `ProjectRevenue.step()`), `projectBoard` (hours line shows budget plus changes),
  `Project_Record_Page` flexipage (financials card, New Invoice), `Projects_Home` flexipage
  (Export Invoices), `BarnHelp_Projects.json` (keys prefixed `Projects_Billing_`,
  `Projects_Invoice_`, `Projects_Financials_`, `Projects_Revenue_`, `Projects_Change_`).

### Every builder

Each also edits, in its own rows or sections only: the three Projects permission
sets (class access and its page tabs), `BarnCRM_Module.Projects` Staff_Tabs (its page tabs),
Core `barnIcons.js` (its page tabs), `scripts/ci/check-apex-budget.py` (the projects cap, raised
by what it measures, with a comment), `docs/admin-guide/projects-psa.md` (its part's section),
`docs/user-guide/projects.md`, `docs/testing-guide/projects.md` (its own test rows),
`docs/overview.md` and `docs/barncrm-features.md` (flips its rows to Built). The integrator
resolves the cap and the shared lines when the three land together.

## Consequences

- Eight objects and one global value set are added: Project Rate, Project Expense, Project
  Resource, Resource Request, Project Invoice, Project Invoice Line, Project Revenue and Change
  Request, and the `Project_Skills` value set. The module's first triggers arrive (Time Entry and Project
  Expense, through the Core dispatcher), so ADR-0208 decision 5's "no automation on save" no
  longer holds for those two objects; projects and tasks still have none.
- One nightly step is added (Project revenue). No external endpoint of Projects' own: online
  invoice payment goes through the Payments module's existing checkout and webhook, and only
  when Payments is installed.
- Existing totals are unchanged at upgrade: Status is blank on every older entry, and blank
  counts.
- A rate correction does not reprice time already logged; Apply Rates fills only blank rates.
  Repricing a logged entry means changing it (which re-stamps) before it is approved.
- Margin is visible to Projects Admin only. Giving Staff read on cost is a two-field change if
  an organization wants its project managers to see it.

## Alternatives considered

- **A Timesheet object per person per week** holding the entries: rejected (section 3); one
  approver per timesheet does not fit a week across projects with different managers.
- **Salesforce Approval Processes:** subscriber orgs cannot edit them cleanly in an unlocked
  source install, they need setup per org, and the rule "owner or Projects Admin" is one
  validation rule.
- **A Project Manager lookup on Project:** a second field that means what Owner already means
  here; it can be added later and read first if organizations need an owner who is not the
  manager.
- **A Billing extra permission:** rejected for now (section 9, ADR-0194).
- **Revenue computed on demand for every month:** rejected (section 7): closed months would move.
- **Change request approval writing into Budget Hours and Amount:** needs an Apex action and a
  flag to stop approval through a plain edit, and loses the original budget.
- **A Skill object with levels:** two more objects; the value set covers matching by skill.
- **Salesforce Invoice, Product or Opportunity objects:** outside Mirror they are ruled out
  (ADR-0013), and BarnCRM invoices are records for the organization's own accounting.
