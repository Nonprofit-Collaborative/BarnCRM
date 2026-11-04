# ADR-0161: The BarnCRM Funders module: a Grant and its requirements, the funder an organization, a program named by its record identifier

**Status:** Proposed (built as recommended for release 0.16, F-01 and F-02; awaits owner confirmation)
**Date:** 2026-11-02
**Source:** plan Section 4.1 (packaging table), Section 5.5 (F-01 to F-14), Section 6.0a releases
0.16 and 0.17 (D-155), Section 9.9 (portability); builds on ADR-0003, ADR-0013, ADR-0014, ADR-0017,
ADR-0024, ADR-0075, ADR-0124, ADR-0127, ADR-0131, ADR-0151, ADR-0153 and ADR-0154.

## Context

Funders (plan Section 5.5) tracks the money an organization asks funders for and the promises it
makes when it gets it: the pipeline of grants applied for and awarded (F-01), the reports and other
deliverables each award requires, with reminders (F-02), restricted fund tracking (F-03, release
0.17), government award fields (F-04), multi-year award schedules on Giving's Commitment and
Installment (F-05), a funder report merge template (F-06), a board dashboard (F-07), a deadline
calendar (F-08) and an answer library (F-14). Release 0.16 builds F-01 and F-02. Plan Section 6.0a
asks for an ADR before each new module.

Main already lists the package (`packages/funders`, package `BarnCRM Funders`, depending on Core,
the Rollup Builder module and Giving) and Core ships the catalog row `BarnCRM_Module.Funders`
(Nonprofit Edition only, Sort Order 40, requires `Rollups;Giving`). Giving's Ask (ADR-0153) is
the individual donor pipeline; grants differ in shape: a funder organization, an application with
a deadline, an award period, and obligations after the award.

## Decision

1. **The package depends on Core only.** Giving and Rollup Builder were listed too;
   ADR-0162 `0162-funders-restricted-funds-schedules-calendar.md` (decision 1) drops both, links
   a Giving fund by record identifier, as a program is linked (decision 6), and keeps every total
   a platform roll-up summary. The module key is
   `Funders`, so the classes Core finds by name are `FundersAccessSync`, `FundersPostInstall`, `FundersHealthCheckExtension`,
   `FundersNightlyJobProvider` and `FundersSampleData`.
2. **Two objects in release 0.16.** Grant (`Grant__c`, canonical model 29ZH): one request to one
   funder, from prospect to awarded or declined, with the amounts requested and awarded, the
   application deadline, submitted and decision dates, and the award period. Grant Requirement
   (`Grant_Requirement__c`, 29ZI): one report or deliverable the funder expects, a detail of its
   grant, with a type, due date, status and the staff member assigned. A second object rather
   than date fields on the grant, because one award carries any number of reports (interim,
   final, financial) and each needs its own status, owner and reminder.
3. **The funder is an Account.** `Funder__c` is a required lookup to Account with delete Restrict,
   so a funder with grants cannot be deleted by mistake and a merge moves the grants to the
   record kept. The funder is an organization in BarnCRM's sense (plan F-01 note); it is not
   enforced by a rule, because organizations use the org's own record type (ADR-0141) and a rule
   that misread one would refuse real grants. A program officer is the optional Funder Contact.
4. **Stages are a restricted picklist, not a setting.** Prospect, Letter of Inquiry, Invited to
   Apply, Applied (open), then Awarded, Declined or Withdrawn (closed). Unlike asks (ADR-0153,
   decision 2), grant stages are the same everywhere: they follow the funder's process, not the
   organization's, and reminders, Health Check and the board depend on what each stage means.
   History is the platform's field history on Stage, Amount Requested and Amount Awarded.
5. **Stage dates are stamped.** Moving to Applied fills an empty Submitted Date; moving to
   Awarded, Declined or Withdrawn fills an empty Decision Date; a requirement moving to Submitted
   or Accepted fills its empty Submitted Date. Switchable automations (registry rows
   `Grant_Dates` and `Grant_Requirement_Dates`), as for enrollments (ADR-0151, decision 6), so an
   import of history can turn them off.
6. **The program is named by record identifier, never looked up.** `Program_Id__c` holds a
   Programs record identifier as text (ADR-0014, ADR-0154 decision 5), so Funders installs without
   Programs. An automation that always runs (registry row `Grant_Rules`) stores it in its
   18-character form and refuses text that is not a record identifier, or one of another object
   where Programs is installed. The Grant record page offers a program picker only where an
   object named `Program__c` exists, read by describe.
7. **Reminders are tasks and emails to staff, from one morning job.** At 6:00 AM in the org time
   zone, `GrantReminderBatch` finds open requirements (Not Started or In Progress) due within the
   lead time, or up to 30 days overdue, that have not been reminded for their current due date.
   Each gets one task for the person assigned (or the grant's owner when nobody is, or the
   assignee is inactive), on the grant, due on the due date, and, when the email setting is on,
   one email to that person through Core's `EmailSender`. The requirement's `Reminder_Sent_For__c`
   is stamped with the due date, so a requirement is reminded once per due date and moving the
   date reminds again. The job is listed by `FundersNightlyJobProvider`, so Health Check's
   "Schedule all nightly jobs" fix schedules it (ADR-0075), and it does nothing while the module
   is off or both reminder settings are off. Emails go only to BarnCRM users, addressed by user
   record, so they do not count against the org's daily limit for outside addresses.
8. **Three settings, in a Funders section of BarnCRM Settings.** `Funders_Settings__c` (hierarchy
   custom setting, ADR-0017): Create reminder tasks (on), Email reminders (off) and Days before a
   deadline to remind (14, from 1 to 90). Tasks ship on: a missed funder report can cost the next
   award, and a task reaches only the staff member who owns the work, inside Salesforce. Emails
   ship off, as for shift reminders (V-10) and pledge reminders (G-30): outbound email is
   something an admin turns on (integrator decision, 2026-11-02). Shown as
   Setting Definition rows in a new Core section, Funders, under Fundraising.
9. **Three permission sets, given by role.** `Funders_Admin` (everything, including delete) to
   holders of `BarnCRM_Admin`; `Funders_Staff` to the Team Member (`Program_Staff`), Coordinator
   (`Volunteer_Coordinator`) and Fundraising Staff (`Fundraising_Staff`, Giving) roles: create and
   edit grants, create, edit and delete requirements, never delete a grant; `Funders_Read_Only`
   to the Read Only role. Given by `FundersAccessSync` on the Programs pattern (ADR-0127 decision
   3, ADR-0131), never taken away. The custom permission `View_Funder_Pipeline` (plan Section 7)
   is reserved for the first rule that needs one.
10. **Sharing is Public Read/Write.** Grants are the organization's, not a person's, and the small
    teams BarnCRM serves work one pipeline together, as for asks (ADR-0153, decision 6).
    Requirements follow their grant (master-detail).
11. **Built in the app.** The **Grant Pipeline** tab draws open grants by stage with the totals,
    moves a grant to another stage, and lists upcoming and overdue deadlines (application
    deadlines and, from F-02, requirement due dates) with a Mark Submitted action. Its arithmetic
    is a framework-free JavaScript module (`grantPipelineModel`, plan 9.9); `GrantPipelineController`
    is thin and returns plain JSON shapes.
12. **Erasure and merge need no module code.** Grants and requirements carry no personal data
    about the people an organization serves; deleting a funder contact empties Funder Contact
    (SetNull), and a merge moves both lookups to the record kept.

## Room Left for Later Releases

- F-03 adds a restricted ledger on the grant and names a Giving fund by record identifier
  (ADR-0162 `0162-funders-restricted-funds-schedules-calendar.md`); F-12 compares a budget with
  the award and that ledger.
- F-04 adds the government award fields to Grant (assistance listing number, award number,
  drawdowns); the award period is already there.
- F-05 adds Grant Payments, the grant's own schedule (same ADR).
- F-08 draws the same deadline rows (`grantPipelineModel.deadlineRows`) as a calendar.
- L-06 links logic model outcomes to grant requirements of type Deliverable.

## Alternatives Considered

- **Grants as Asks (ADR-0153).** Rejected: an ask has a donor pair, no deadline, no award period
  and no obligations after the win; adding them would burden every individual ask.
- **Grants as Commitments.** Rejected: an application that is declined is not a promise the books
  track (the reason ADR-0153 gave for asks).
- **Keeping Giving as a dependency.** Dropped (decision 1).
- **Requirement dates as fields on Grant.** Rejected: an award has a varying number of reports,
  each with its own status and owner (decision 2).
- **Reminders as emails only, or tasks only.** Rejected: a task stays on the person's list and the
  grant's activity, an email is noticed the same morning; each can be switched off.
- **A rule that the funder is an organization.** Rejected (decision 3).

## Consequences

- Two more custom objects for a Funders user (the Lightning Platform Starter object count,
  ADR-0121), and one more nightly job for Health Check to schedule.
- Core gains a Funders settings section and names the Funders classes it finds by name, as it
  does for the other modules.
- A program deleted in Programs leaves its identifier on the grant; the record page shows it as
  missing and another can be chosen.
- The module can never be offered in the Standard Edition (ADR-0124), and no Opportunity,
  Campaign or Case is used (ADR-0013).
