# BarnCRM Funders

## Purpose

Funder pipeline (grants applied for and awarded), reporting requirements and deadlines with
reminders, government award fields, multi-year award schedules, restricted fund tracking, the
Grant Calendar, an answer library, requirements linked to Logic Models outcomes, funder report
templates and the Board Dashboard (plan Section 5.5, ADR-0161 `0161-funders-module.md`, ADR-0162
`0162-funders-restricted-funds-schedules-calendar.md`, ADR-0163 `0163-funders-reporting-links.md`).

## First ships in

Release **0.16** (F-01 funder pipeline, F-02 reporting requirements and reminders, F-04
government award fields, F-05 award schedules, F-06 funder report template, F-07 board dashboard,
F-14 answer library). F-03 restricted fund tracking, F-08 deadline calendar and L-06 outcome
links follow in 0.17.

## Depends on

- BarnCRM Core
- BarnCRM Rollup Builder

Nothing in this package references Giving or Programs (ADR-0162
`0162-funders-restricted-funds-schedules-calendar.md` decision 1): a grant may name a program
and a Giving fund by record identifier (text), resolved by describe only where a `Program__c` or
`Fund__c` object exists.

## Contents

- Objects: `Grant__c`, `Grant_Requirement__c`, and the custom setting `Funders_Settings__c`
  (canonical model Sections 29ZH to 29ZJ).
- The **Grant Pipeline** tab (`grantPipeline`), with its framework-free module
  `grantPipelineModel` and the thin controller `GrantPipelineController`; the program picker
  (`grantProgram`) on the Grant record page.
- The morning reminder job (`GrantReminderScheduler`, `GrantReminderBatch`).
- `Grant_Payment__c` (29ZM), an award's schedule, with the Award Schedule card (`grantSchedule`,
  framework-free `grantScheduleModel`, `GrantScheduleController`) on the Grant record page.
- `Grant_Fund_Entry__c` (29ZL), a restricted grant's ledger, kept in step with received payments
  by `GrantPaymentService.syncLedger`; the Giving Fund card (`grantFund`, `GrantFundController`,
  `GrantFundService`) on the Grant record page.
- The **Grant Calendar** tab (`grantCalendar`, framework-free `grantCalendarModel`,
  `GrantCalendarController`), reading the same rows as Upcoming Deadlines through
  `GrantDeadlineSelector`.
- `Grant_Answer__c` (29ZN), the answer library (`grantAnswerLibrary`, framework-free
  `grantAnswerModel`, `GrantAnswerController`).
- The Logic Models outcomes card on a requirement (`grantOutcomes`, `GrantOutcomeController`,
  `GrantOutcomeService`), resolved by describe only where Logic Models is installed.
- `Funder_Report_Template__c` (29ZO) and its shipped defaults, merged in the browser by the
  Funder Report card (`grantReport`, framework-free `grantReportModel`, `GrantReportController`).
- The **Funders Board** tab (`fundersBoard`, framework-free `fundersBoardModel`,
  `FundersBoardController`).
- Permission sets Funders Admin, Staff and Read Only, given by role through `FundersAccessSync`.
