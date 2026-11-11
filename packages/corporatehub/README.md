# BarnCRM Corporate Hub

## Purpose

An organization's documents, policies, compliance obligations and contracts (plan Section 5.8,
ADR-NEXT `NEXT-corporate-hub-module.md`, D-118): a library of documents on Salesforce Files,
policy acknowledgments, a compliance calendar with the history of each completed cycle,
agreements with renewal and notice dates, and templates shipped as data. Board governance
(CH-09 to CH-20; ADR-NEXT `NEXT-corporate-hub-board-governance.md`): boards and committees,
seats and terms, meetings with attendance, quorum, minutes, motions and votes, disclosures,
action items, self-assessments and an availability poll; members act through the board portal
template (PB-02). The GDPR set (CH-05) is a later item on the same model.

## First ships in

Release **1.7** (CH-01 to CH-04, CH-06 to CH-08); board governance in releases 1.10, 1.11 and
1.14 (CH-09 to CH-20, PB-02).

## Depends on

- BarnCRM Core

Nothing here references another module. Files are standard Salesforce Files. Template text is
general guidance, not legal advice.

## Contents

- Objects: `Hub_Document__c` (Library Document, 29CH1), `Policy_Acknowledgment__c` (29CH2),
  `Compliance_Obligation__c` (29CH3), `Compliance_Cycle__c` (29CH4), `Agreement__c` (29CH5),
  the settings `Corporate_Hub_Settings__c` (29CH6) and its Setting Definition rows (section
  Corporate Hub). Board governance: `Board__c`, `Board_Member__c`, `Board_Meeting__c`,
  `Meeting_Attendee__c`, `Board_Motion__c`, `Board_Vote__c`, `Meeting_Action_Item__c`,
  `Board_Assessment__c` and `Assessment_Answer__c` (29CH7 to 29CH15).
- Custom permission `Corporate_Hub_Manage`.
- Apex: `HubPolicy` (versions, reviews, acknowledgments), `HubCompliance` (completing a cycle),
  `HubReminders` (the nightly step, through `CorporateHubNightlyJobProvider`), `HubTemplates`
  (loads the shipped templates once per key), `CorporateHubSettings`, `CorporateHubController`
  (the page and panels), `CorporateHubAccessSync` and `CorporateHubPostInstall`; `HubBoard`
  (seats, meetings, minutes, voting, the poll, action items, self-assessments, giving
  participation by describe), `HubBoardController` (the Board and Meeting panels) and
  `CorporateHubPortalExtension` (the board portal's actions, which Core's
  `PortalActionExtensions` finds by name).
- Static resources: `BarnCorporateHubTemplates` (the template set: obligations Off, policies
  Draft) and `BarnHelp_CorporateHub` (help and message text).
- Custom notification type `Corporate_Hub_Reminder` (the bell reminders).
- Lightning components: `corporateHubHome` (the Corporate Hub page), `hubDocumentPanel` (the
  Policy panel), `hubCompleteCycle` (the Compliance panel) and the framework-free
  `corporateHubModel`; record pages `Hub_Document_Record_Page` and
  `Compliance_Obligation_Record_Page`, set as each object's default.
- Tabs: Corporate Hub, Library Documents, Compliance Obligations and Agreements. No app of its own (ADR-0192):
  the tabs join BarnCRM and BarnCRM Console through the catalog row's `Staff_Tabs__c`.
