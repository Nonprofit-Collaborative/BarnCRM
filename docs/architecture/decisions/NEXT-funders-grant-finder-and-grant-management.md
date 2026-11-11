# ADR-NEXT: Funders Grant Finder and grant management

**Status:** Proposed (built for release 1.11, F-09 to F-13; awaits owner confirmation)
**Date:** 2026-11-11
**Source:** plan Section 5.5 (F-09 to F-13), D-121 (Grant Finder on the free Grants.gov API, paid
directories only through the organization's own subscription), D-62 (Setup prerequisites shown in
Settings), Section 9.9 (portability); builds on ADR-0161 `0161-funders-module.md`, ADR-0162
`0162-funders-restricted-funds-schedules-calendar.md` and ADR-0163 `0163-funders-reporting-links.md`.

## Context

Funders tracks grants (F-01 to F-08): a pipeline, requirements with reminders, a restricted
ledger, payment schedules. D-121 adds finding grants and managing the work of one: a search of open
funding opportunities, application checklists, document tracking, budget against award, and
renewals. Each could be a new object with its own reminders, calendar entries and permissions. The
Apex budget is tight (69 percent of the org limit), so the design reuses what Funders has.

## Decision

1. **Grant Finder searches Grants.gov, with no key.** `GrantFinder` posts to the public Grants.gov
   search API (`https://api.grants.gov/v1/api/search2`), which needs no account. The endpoint is a
   packaged Remote Site Setting, `BarnCRM_Grants_Gov`, so no Setup step is needed; the Grant Finder
   setting (Funders section, ships on) turns the tab's search off, and its description names the
   remote site an org must keep. Only the words searched leave the org. BarnCRM holds no key and
   calls no paid service; a paid directory (Candid and the like) is not built, and would be added
   later as a second source reached through the organization's own subscription and Named
   Credential.
2. **Save to Pipeline makes a Prospect.** A result becomes a grant at Prospect with the title,
   the close date as Application Deadline, Funding Source Federal, the agency as Federal Agency
   and Funder, the first assistance listing number when it has the 84.287 shape, and the
   opportunity's Grants.gov page in a new `Opportunity_Url__c`. The funder is the organization of
   that exact name the person can read, or a new organization on the org's organization record
   type. A result whose page is already on a grant shows as saved, with a link.
3. **Checklists are requirements.** A Grant Checklist Item (`Grant_Checklist_Item__c`, a tab
   admins keep) names a task, the stage it belongs to, how many days before the application
   deadline it is due, and who does it (blank: the grant's owner). When a grant reaches a stage,
   a switchable automation (`Grant_Checklist`) adds a requirement of the new type Task for each
   active item of that stage not already on the grant (`Checklist_Item__c` remembers the item).
   Tasks are requirements, so they get reminders, the calendar, Health Check and the related list
   with no new code. Done, a new status, closes a task; it is a done status, not open.
4. **Documents are requirements with files.** Letter of Inquiry and Application join the
   requirement types. A document's files are Salesforce Files on the requirement; its version is
   the file's own version number (Upload New Version on the file), so BarnCRM stores no version
   field. A Documents card lists the LOI, application and report requirements with status, due
   and submitted dates and their files, and uploads a file to one. Files count against the org's
   file storage.
5. **Budget lines are a detail of the grant.** A Grant Budget Line (`Grant_Budget_Line__c`) has an
   amount requested and an amount awarded. A Spent restricted fund entry may name its line
   (`Budget_Line__c`, a validation rule keeps it on the same grant). The Budget card compares
   each line's requested, awarded and spent, the totals against the grant's Amount Requested and
   Amount Awarded, and spending not assigned to a line. Spent is summed when the card loads, not
   stored.
6. **Renewals are a link and a requirement.** A grant marked Renewable (`Renewable__c`, default
   off) that is Awarded with an Award End Date gets one open requirement of the new type Renewal,
   due Renewal Lead Days (Funders setting, 90, 1 to 365) before the end date and never before
   today, through a switchable automation (`Grant_Renewal`); a moved end date moves it. The
   requirement reminders remind it. Start Renewal makes the next-cycle grant at Prospect with the
   funder, purpose, program, fund, source, government fields and budget lines copied, the award as
   the new request, and `Renewal_Of__c` naming the grant it renews; the open Renewal requirement
   becomes Done. The Renewals card shows the chain both ways, so the history across years is one
   list.
7. **Thin and portable.** Controllers return plain shapes (`GrantFinderController`,
   `GrantManagementController`); the rules sit in `GrantFinder` and `GrantManagementService`; the
   arithmetic of the cards is in the framework-free module `grantManagementModel.js`. The new
   card text is in the Funders help catalog, not labels.
8. **Access.** Funders Admin keeps checklist items; Staff and Read Only read them. Admin and Staff
   create, edit and delete budget lines; Read Only reads them. Start Renewal and Save to Pipeline
   need create on Grant; uploading a file needs edit on the requirement.

## Consequences

- Two objects (`Grant_Checklist_Item__c`, `Grant_Budget_Line__c`), fields on `Grant__c`
  (`Renewable__c`, `Renewal_Of__c`, `Opportunity_Url__c`), `Grant_Requirement__c`
  (`Checklist_Item__c`) and `Grant_Fund_Entry__c` (`Budget_Line__c`); three requirement types and
  one status; two settings; two automations; one remote site; two tabs.
- Uninstalling Funders deletes checklist items and budget lines with the rest (Module Manager
  lists them).
- A Grants.gov outage or a changed response shows a plain error and is logged; nothing is saved.

## Alternatives considered

- A checklist object of its own, and a document object: more reminders, calendar and Health Check
  code for the same dates and statuses. Rejected for the Apex budget.
- A Named Credential for Grants.gov: needs an admin Setup step for a public, keyless API. Can
  replace the remote site later without a data change.
- A stored version number on documents: duplicates what Files keeps.
