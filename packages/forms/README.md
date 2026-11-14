# BarnCRM Forms

## Purpose

Forms staff build once and fill in many times: multi-step forms, conditional questions, matching
to existing people and organizations through Core's matchers, and records created or updated in
BarnCRM (C-42a, ADR-0175 `0175-forms-module.md`). The engine other modules reuse: Event
Management registrations, V-09, the donation page and Scholarships applications.

## First ships in

Release **1.1** (C-42a engine and builder). C-42b adds public forms on a Salesforce Site and C-42c
file upload and save and resume.

## Depends on

- BarnCRM Core

Nothing in this package references another module. A module attaches a form to its own records
through Core's `FormAttachmentExtension` seam and holds the form's record identifier as text.

## Contents

- Objects: `Form__c`, `Form_Version__c`, `Form_Submission__c` (canonical model Sections 29ZW to
  29ZY).
- Permission sets `Forms_Admin`, `Forms_Staff`, `Forms_Read_Only`, given by role through
  `FormsAccessSync`; install steps in `FormsPostInstall`.
- App `BarnCRM_Forms` (BarnCRM Forms, logo `BarnCRM_Forms_Logo`), visible through the Forms
  permission sets; left out of scratch and Developer Edition orgs (ADR-NEXT, module apps). The
  Forms and Form Submissions tabs also join BarnCRM and BarnCRM Console through the catalog row's
  `Staff_Tabs__c` and `scripts/org/module-app-tabs.py`; the Form and Form Submission record pages
  are each object's org default.
