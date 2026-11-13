# Project Management

## What It Does

BarnCRM Project Management is an optional module, in both editions, for running projects of any
kind: a Salesforce implementation (your own BarnCRM rollout, or one you run for a client), a
program launch, internal work or client work.

- **Projects** (PM-02): type, status, client organization and contact, start and target dates,
  owner and a description. Percent Complete counts the tasks that are done.
- **Phases, tasks and milestones** (PM-02): phases such as Discovery or Build, tasks with an
  owner, dates, an estimate and a status, and milestones (a task marked Milestone, such as
  Go-Live). The project page shows each phase's progress on a timeline.
- **Templates** (PM-03): a shipped Salesforce Implementation template (Discovery, Design, Build,
  Data Migration, Testing, Training and Go-Live) and a Program Launch template, and any project
  of your own marked Is Template.
- **Time and budgets** (PM-04): time entries (billable or not), people assigned to a project
  with a role and planned hours, budget hours and amount against actual hours and cost,
  utilization by person, and a CSV of billable time for your own accounting or invoicing system.
- **Health and status updates** (PM-05): each active project is On Track, At Risk or Off Track
  by a rule you tune, with its reasons; a status update drafted from the project for you to edit;
  a Projects at Risk card for any home page; and four reports.
- **PSA** (PM-06 to PM-12, release 1.20): rate cards, timesheets and approvals, expenses,
  resource management, invoices (with Pay Online through BarnCRM Payments when installed),
  financials and recognized revenue, and change requests, each behind its own setting and off
  until you turn it on. See [Project Management PSA](projects-psa.md).

## Install and Turn On

1. Install BarnCRM Project Management from BarnCRM Settings, **Modules** (both editions).
2. Turn it on in the same list. Install leaves it off.
3. Within the hour (or at once with **Finish Setup**) BarnCRM Admin holders get Projects Admin,
   the Team Member and Fundraising Staff roles get Projects Staff, and Read Only gets Projects
   Read Only.
4. The Projects Home, Projects and Time Entries tabs appear in BarnCRM and BarnCRM Console, before
   Error Log.

## Access

| Permission set | Who gets it | What it allows |
|---|---|---|
| Projects Admin | BarnCRM Admin holders | Everything, including delete and **Manage Projects** (Export Billable Time) |
| Projects Staff | Team Member and Fundraising Staff roles | Create and edit projects, phases, tasks, assignments, time entries and status updates; no delete |
| Projects Read Only | Read Only role | Read everything |

Projects are shared Public Read/Write so a team can work together. To keep client projects
private, set the Project object's sharing to Private in Setup and share projects with a public
group or role; phases, tasks, time and updates follow their project.

## Settings

BarnCRM Settings, **Projects**:

| Setting | Default | What it does |
|---|---|---|
| Track time and budgets | On | Shows Log Time and the budget lines on the project page, and Utilization and Export Billable Time on Projects Home. Turn it off to use projects for planning only. |
| Days late before at risk | 7 | How many days past due an open task must be before its project is At Risk (1 to 365). |
| Budget warning percent | 90 | The share of Budget Hours that, once used, makes a project At Risk (1 to 100). |
| Weekly capacity hours | 40 | One person's working hours in a week, for utilization (1 to 168). |

The health check runs each morning at 6:40 AM as part of BarnCRM's nightly run (BarnCRM
Settings, **Automation**, Nightly Jobs, where it can be switched off).

## Projects, Phases and Tasks

Create a project from **Projects Home**, **New Project From Template**, or with **New** on the
Projects tab. Until the org has a project (templates do not count), Projects Home opens with
**Start Your First Project** for anyone who may create one (D-200 R4); its **Start a Project**
button goes to the New Project From Template form. A project's page shows:

- the health badge and its reasons, with **Refresh Health**;
- progress: tasks done of tasks, the percent complete, and, with time tracking on, Estimated,
  Actual and Budget Hours and the cost against the Budget Amount;
- each phase with its dates as a bar on the project's timeline, its progress and its tasks;
- **Add Task** in a phase, a status menu on each task (Done stamps Completed Date), and the
  milestone flag;
- **Log Time** and **Draft Status Update**.

Phases and tasks can also be edited in their related lists. A task's phase must be on the same
project. Status values: Planned, Active, On Hold, Completed and Cancelled for a project; Not
Started, In Progress, Blocked, Done and Cancelled for a task.

## Templates

**New Project From Template** lists the shipped templates first, then your own.

- **Salesforce Implementation**: Discovery, Design, Build, Data Migration, Testing, Training and
  Go-Live, with tasks such as stakeholder interviews, data mapping, user acceptance testing and
  the Go-Live milestone, about 14 weeks from the start date.
- **Program Launch**: Plan, Prepare, Launch and Review, about 10 weeks.

To make your own, build a project the way you want it (phases, tasks with dates and estimates,
assignments with roles and planned hours), then check **Is Template**. A new project from it
copies the phases, tasks (as Not Started) and assignment roles (without the person), with every
date moved to the new start date. Template projects never get a health and are left out of the
Active and At Risk lists. Dates move by calendar days, so check weekend dates after copying.

## Time, Assignments and Budgets

- **Log Time** on the project page records hours for a day, optionally on a task, billable or
  not; the Time Entries tab lists every entry. Hours must be more than 0 and at most 24.
- **Assignments** (related list) name a person, their role, planned hours and dates.
- **Budget Hours**, **Budget Amount** and **Hourly Rate** on the project give Actual Cost
  (Actual Hours times the rate) and Remaining Budget. There is one rate per project.
- **Utilization** on Projects Home shows, for a date range, each person's logged and billable
  hours, their planned hours (assignments counted for the days that fall in the range), their
  capacity and the share of it used.
- **Export Billable Time** (Manage Projects) downloads a CSV of billable time in a date range,
  with project, client, task, person, date, hours, rate and amount, and stamps each entry's
  Exported Date so the next export skips it unless you include exported entries. Use the file
  in your accounting or invoicing system.

## Health and Status Updates

An Active project that is not a template is:

- **Off Track** when its Target Date has passed, or its Actual Hours are over its Budget Hours;
- **At Risk** when a milestone is past due, a task is past due by the Days late before at risk
  or more, or the hours used reach the Budget warning percent of Budget Hours;
- **On Track** otherwise.

The nightly check covers up to 2,000 projects (Active ones first by target date, plus any with a
health already set). When it reaches 2,000 it writes a warning to the Error Log, and projects
beyond it are not checked that night; use **Refresh Health** on those.

Health Reasons lists each reason. **Draft Status Update** writes a dated Project Status Update
with the health, percent complete and hours, what was done since the last update, what is due in
the next 14 days, and the risks. Edit it, then share the record or print the page.

The **Projects at Risk** card is on Projects Home. To put it on a Lightning home page, open the
home page in the Lightning App Builder and drag **Projects at Risk** onto it.

## Reports

The BarnCRM Projects folder holds Projects at Risk, Overdue Project Tasks, Time by Person This
Month and Billable Time Last Month, on the Projects, Project Tasks and Time Entries report types.

## Common Mistakes

- A project never shows a health: it is not Active, or it is marked Is Template.
- A new project from a template has no people on its tasks: templates copy roles, not people.
  Fill in Assigned To and the assignments.
- Utilization shows nobody: no time was logged in the range, or Track time and budgets is off.

## Removing the Module

Turn it off in BarnCRM Settings, **Modules**: the health check stops and the records stay.
Uninstalling deletes every project, phase, task, assignment, time entry and status update; the
Modules page counts them first.
