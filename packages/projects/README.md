# BarnCRM Project Management

## Purpose

Projects of any kind for any organization (D-175, ADR-0208 `0208-project-management-module.md`):
projects with phases, tasks and milestones, templates (a shipped Salesforce Implementation and
Program Launch template, and any project marked Is Template), a light PSA layer (time entries,
assignments, budgets against actuals, utilization, a billable time CSV; no invoices or payments),
health by rule and status updates.

## First ships in

Release **1.18** (PM-01 to PM-05).

## Depends on

- BarnCRM Core

No other module is referenced. Standard objects used: Account, Contact and User (lookups).

## Contents

- Objects: `Project__c`, `Project_Phase__c`, `Project_Task__c`, `Project_Assignment__c`,
  `Time_Entry__c`, `Project_Status_Update__c`, settings `Projects_Settings__c` (canonical model
  29PM1 to 29PM7).
- Permission sets `Projects_Admin`, `Projects_Staff`, `Projects_Read_Only`, given by
  `ProjectsAccessSync`; custom permission `Projects_Manage`.
- Static resources `Projects_Templates` (the shipped templates) and `BarnHelp_Projects` (help
  text).
- One nightly step, `ProjectHealth` at 6:40 AM; no trigger.
- App `BarnCRM_Projects` (BarnCRM Projects, logo `BarnCRM_Projects_Logo`) holds every tab,
  visible through the Projects permission sets; left out of scratch and Developer Edition orgs
  (ADR-0223, module apps). The catalog row's tabs also join the BarnCRM apps before Error Log:
  `Staff_Tabs__c` in BarnCRM and BarnCRM Console, `Admin_Tabs__c` in the admin apps.
- Settings in the Projects section of BarnCRM Settings.
