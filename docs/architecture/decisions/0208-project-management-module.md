# ADR-0208: The BarnCRM Project Management module: its own package on Core for every edition, projects with phases, tasks and milestones, templates, a light PSA layer (time, assignments, budgets against actuals, billable export) and status updates

**Status:** Accepted (builder decision, for Brandon to confirm)
**Date:** 2026-11-11
**Amended:** 2026-11-12, D-197: decisions 6 and 7 are superseded where they conflict by ADR-0219
`0219-projects-psa.md` (the full PSA: rates, approvals, expenses, resources, invoices, revenue
and change requests, each behind its own setting).
**Source:** plan Section 6.0a release 1.18 (PM-01 to PM-05), D-175, D-38 (Core, universal, then
nonprofit modules), Section 1.5 (BarnCRM moves no money, no services); builds on ADR-0013,
ADR-0017, ADR-0131 (module access sync), ADR-0164 (help text JSON), ADR-0166 (nightly
dispatcher) and ADR-0192 (module tabs in the BarnCRM apps).

## Context

D-175 asks for "a PM Module which can handle projects in various ways, including Salesforce
implementation projects. Perhaps this will be a PSA tool." PM-01 is the spec and this ADR, and
it settles whether the module grows into a PSA (professional services automation) tool. Projects
here are of four kinds: a Salesforce implementation (often the organization's own BarnCRM
rollout, or one a consultant runs for a client), a program launch or other program work, internal
work (a move, an audit, a campaign build) and client work for an outside organization. Every
organization, nonprofit or not, runs projects, so the module is universal (both editions).

## Decision

1. **Its own package, Core only, both editions.** `packages/projects`, package `BarnCRM Project
   Management`, module key `Projects`. Core ships the catalog row `BarnCRM_Module.Projects`
   (editions `Standard;Nonprofit`, Sort Order 54, no probe object: its Setting Definition rows
   name the module, #1053). No app of its own (ADR-0192): its Projects Home, Projects and Time
   Entries tabs join BarnCRM and BarnCRM Console before Error Log. Install leaves the module off,
   as every module. No other module is referenced.
2. **Project types are a picklist, not separate objects.** Salesforce Implementation, Program,
   Internal, Client and Other on one Project (`Project__c`). The client or stakeholder is any
   Core Account (organization or household) and Contact, by lookup; no Person Account, no new
   person object, no standard object beyond Account, Contact and User.
3. **Phases, tasks and milestones.** Project Phase (`Project_Phase__c`) and Project Task
   (`Project_Task__c`) are master-detail children of the project; a task looks up its phase
   (filtered to the same project). A milestone is a task with Milestone checked: a dated point
   with no effort of its own, the way most PM tools draw it. The project's Percent Complete is a
   formula over roll-ups (tasks Done over tasks not Cancelled), so reports read it without Apex.
   A phase's progress and its bar on the timeline are worked out in the browser
   (`c/projectsModel`, framework-free JS).
4. **Templates two ways (PM-03).** Shipped templates are JSON in the static resource
   `Projects_Templates` (a Salesforce Implementation template with Discovery, Design, Build, Data
   Migration, Testing, Training and Go-Live, and a Program Launch template), each phase and task
   placed by day offsets from the start date. An organization's own template is any project with
   Is Template checked: New Project From Template copies its phases, tasks and assignment roles,
   moving every date by the difference between the template's start and the new start. Template
   projects are left out of health, the at-risk card and the default list views. Dates are
   calendar days, not working days.
5. **Health is a rule, written by Apex (PM-05).** Only an Active project has a health. Off Track:
   its Target Date has passed, or its Actual Hours are over its Budget Hours. At Risk: a
   milestone is past due, a task is past due by At Risk Days or more (setting, 7), or Actual
   Hours have reached Budget Warning Percent (setting, 90) of Budget Hours. Otherwise On Track.
   The reasons are written to Health Reasons. `ProjectHealth` runs as a 6:40 AM step of the
   nightly run (ADR-0166, with its own switch, on) and on Refresh Health on the project page.
   There is no trigger: the module ships no automation on save.
6. **PSA is kept, as a light layer (PM-04), and can be hidden.** Time Entry (`Time_Entry__c`,
   master-detail to project, lookups to task and user), Project Assignment
   (`Project_Assignment__c`: a user, a role, planned hours and dates) and the project's Budget
   Hours, Budget Amount and Hourly Rate, with Actual Hours, Billable Hours, Actual Cost and
   Remaining Budget as roll-ups and formulas. Utilization on Projects Home compares each person's
   logged hours in a date range with their capacity (Weekly Capacity Hours, setting, 40) and
   their planned hours (assignments prorated by the days that fall in the range). The Time
   Tracking setting (on) hides Log Time, utilization and the export when an organization uses
   projects only for planning. Not built: per-person rates, resource skills and scheduling,
   approvals of time, expenses, revenue recognition. They are the next PSA steps if Brandon wants
   them.
7. **Billing stays free of payment processing.** **Export Billable Time** (Manage Projects)
   downloads a CSV of billable time entries in a date range, built in the browser with Core's
   `c/findCsv`, and stamps their Exported Date, for the organization's own accounting or
   invoicing system. BarnCRM makes no invoice and takes no payment.
8. **Status updates (PM-05).** Project Status Update (`Project_Status_Update__c`, master-detail
   to project) is a dated report: health, percent complete and hours as of that day, a summary,
   accomplishments, next steps and risks. **Draft Status Update** on the project page writes one
   filled from the record (tasks done since the last update, open tasks and milestones due in the
   next 14 days, the health reasons and blocked tasks), for the owner to edit and share. The
   **Projects at Risk** card (`projectsAtRisk`) lists Active projects that are At Risk or Off
   Track, with their reasons and an Only Mine filter; it is on Projects Home and can be added to
   any Lightning Home or app page.
9. **Access (ADR-0131, D-191).** Projects Admin (with Manage Projects) goes to BarnCRM Admin
   holders, Projects Staff to Team Member and Fundraising Staff, Projects Read Only to Read Only,
   by `ProjectsAccessSync`; it only gives. Projects are Public Read/Write so a team can share the
   work; an admin can tighten the sharing and share projects to teams. Manage Projects is needed
   to export billable time; everything else follows object access.
10. **Reports, not a dashboard.** Report types and four reports in a BarnCRM Projects folder
    (projects at risk, overdue tasks, time by person this month, billable time last month). No
    CRM Analytics, no dashboard in this release.

## Consequences

- The module adds six objects (five records objects and a settings object), three permission
  sets, one custom permission, one static resource of templates, one nightly step, no trigger and
  no external endpoint.
- Health is as fresh as the last nightly run or Refresh Health; a task marked late today shows on
  the at-risk card tomorrow morning, or as soon as someone refreshes the project.
- Percent Complete counts tasks, not hours: a project of one large and nine small tasks reads 90%
  when the nine are done. Weighting by estimated hours is a formula change if it is wanted.
- Time is entered per project and optionally per task; a person's rate is the project's rate.

## Alternatives considered

- Salesforce standard Task and Event for project tasks: activities cannot be master-detail
  children, have no roll-ups, and mix project work with call logging.
- A separate Milestone object: one more object for a dated point that a flagged task already
  is.
- Templates only as JSON: an organization could not save its own without editing JSON; only as
  records: the shipped Salesforce implementation template would need data loaded at install.
- A full PSA (rates by person, approvals, invoices): far more Apex against a tight budget for
  needs no organization has asked for yet; the light layer leaves room for it.
- A trigger to keep health current on every save: automation on save for a value a nightly rule
  and a button keep fresh enough.
