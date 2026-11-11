# BarnCRM Corporate Hub

## Purpose

An organization's documents, policies, compliance obligations and contracts (plan Section 5.8,
ADR-NEXT `NEXT-corporate-hub-module.md`, D-118): a library of documents on Salesforce Files,
policy acknowledgments, a compliance calendar with the history of each completed cycle,
agreements with renewal and notice dates, and templates shipped as data. Board governance
(CH-09 to CH-20) and the GDPR set (CH-05) are later items on the same model.

## First ships in

Release **1.7** (CH-01 to CH-04, CH-06 to CH-08).

## Depends on

- BarnCRM Core

Nothing here references another module. Files are standard Salesforce Files. Template text is
general guidance, not legal advice.

## Contents

- Objects: `Hub_Document__c` (Library Document, 29CH1), `Policy_Acknowledgment__c` (29CH2),
  `Compliance_Obligation__c` (29CH3), `Compliance_Cycle__c` (29CH4), `Agreement__c` (29CH5),
  the settings `Corporate_Hub_Settings__c` (29CH6) and its Setting Definition rows (section
  Corporate Hub).
- Custom permission `Corporate_Hub_Manage`.
- Tabs: Library Documents, Compliance Obligations and Agreements. No app of its own (ADR-0192):
  the tabs join BarnCRM and BarnCRM Console through the catalog row's `Staff_Tabs__c`.
