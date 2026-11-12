# BarnCRM Scholarships and Outbound Grants

## Purpose

Grantmaking for organizations that give money (D-122, plan Section 5.11, ADR-NEXT
`NEXT-scholarships-outbound-grants-module.md`): programs and cycles, applications through BarnCRM
Forms, rubric reviews with reviewer panels, awards and letters, disbursements recorded only
(BarnCRM moves no money), conditions, recipient reports and the applicant portal template.

## First ships in

Release **1.12** (SG-01 to SG-06, SG-08, SG-09, PB-06), with SG-10 from release 1.10.

## Depends on

- BarnCRM Core

Forms and Portal Builder are used when installed, through Core's `FormAttachmentExtension` and
`PortalActionExtension` seams; this package references neither. Giving and Funders are not
referenced.

## Contents

- Objects: `Award_Program__c`, `Award_Cycle__c`, `Award_Application__c`,
  `Application_Review__c`, `Award__c`, `Award_Payment__c` (Disbursement),
  `Award_Requirement__c`, settings `Scholarships_Settings__c` (canonical model 29SG1 to 29SG8).
- Permission sets `Scholarships_Admin`, `Scholarships_Staff`, `Scholarships_Read_Only`, given by
  `ScholarshipsAccessSync`; custom permission `Scholarships_Manage`.
- No app of its own: the tabs join BarnCRM and BarnCRM Console before Error Log through the
  catalog row's `Staff_Tabs__c`.
- Settings in the Scholarships and Grants section of BarnCRM Settings; help text in
  `BarnHelp_Scholarships`.
