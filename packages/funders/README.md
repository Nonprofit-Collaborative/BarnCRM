# BarnCRM Funders

## Purpose

Funder pipeline (grants applied for and awarded), reporting requirements and deadlines with
reminders, and later restricted fund tracking, government award fields, multi-year award
schedules and grant management (plan Section 5.5, ADR-NEXT `NEXT-funders-module.md`).

## First ships in

Release **0.16** (F-01 funder pipeline, F-02 reporting requirements and reminders). F-03
restricted fund tracking follows in 0.17.

## Depends on

- BarnCRM Core
- BarnCRM Rollup Builder
- BarnCRM Giving

Release 0.16 references no Giving object; F-03 and F-05 will. Nothing in this package references
Programs: a grant may name a program by its record identifier (text), resolved by describe only
where a `Program__c` object exists.

## Contents

- Objects: `Grant__c`, `Grant_Requirement__c`, and the custom setting `Funders_Settings__c`
  (canonical model Sections 29ZH to 29ZJ).
- The **Grant Pipeline** tab (`grantPipeline`), with its framework-free module
  `grantPipelineModel` and the thin controller `GrantPipelineController`; the program picker
  (`grantProgram`) on the Grant record page.
- The morning reminder job (`GrantReminderScheduler`, `GrantReminderBatch`).
- Permission sets Funders Admin, Staff and Read Only, given by role through `FundersAccessSync`.
