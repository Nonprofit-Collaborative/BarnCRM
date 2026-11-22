# ADR-0093: Simple record reads in LWCs go through Lightning Data Service, not Apex

**Status:** Proposed (builder decision)
**Date:** 2026-10-13
**Source:** Core quality pass item Q-06 (Brandon, 2026-10-13: implement the recommended
platform features); plan Section 12 D-23 ("GraphQL in new screens"); plan Section 4.13
(user mode, FLS and sharing); review findings UI-8, UI-13, IMPORT-16, PEOPLE-38, ADMIN-14,
FINDB-14

## Context

D-23 adopted the GraphQL wire adapter for new screens only. The Core review then found the
cost of the older pattern in existing ones. The Addresses, Affiliations and Relationships
cards each read a flat list of one object through a cacheable Apex method: about 400 lines of
controller and test per card that only restate a query the platform can run as the user. The
Apex cache does not see edits made through the record page, so a card can show old rows, and
after a change the card calls a mutating method that returns the list and then refreshes the
same list, two reads per click, while the record's own fields (the default address, the
primary affiliation) stay stale until a reload. Elsewhere, cacheable Apex is called
imperatively right after a save (the settings console, household naming), so the browser
cache can answer with the values from before the save, and the import wizard waits on four
serial calls when it opens.

## Decision

1. **A flat read of records, as the user, uses Lightning Data Service.** The GraphQL wire
   adapter (`lightning/graphql`) for a filtered list, `getRecord` or `getRelatedListRecords`
   for one record or one related list, `getObjectInfo` and `getPicklistValues` for describe.
   A simple write of one record from the same screen uses `updateRecord`, `deleteRecord` or a
   record form. After a write the screen refreshes its own wire and calls
   `notifyRecordUpdateAvailable` for records a trigger changed.
2. **Apex stays where it earns its place:** aggregation or counts, logic across objects or
   org shapes (household membership in either mode), describe work the UI API does not offer
   (the list of loadable objects, Find's field catalog), system-mode reads or writes
   (ADR-0021), long-running jobs and anything polled.
3. **Cacheable only where staleness is harmless.** A read that is wired, or that is pure
   describe or metadata, is `cacheable=true`. A read the screen calls again after its own
   save, or polls, is not cacheable.
4. **Both org shapes.** A query names only BarnCRM's own fields (both person lookups,
   `Contact__c` and `Person_Account__c`, exist in every org) and standard `Name`; never a
   Person Account field such as `IsPersonAccount` or a `__pc` field.

## Consequences

- The three cards lose their controllers and tests, and the permission sets lose the class
  access. Object and field permissions now decide everything, as they already did in user
  mode.
- A refused read or write on these cards shows the card's message but writes no Error Log
  entry from the card itself; a failure inside a trigger still logs as before (R-E1 covers
  exceptions in Apex, and the household members card already worked this way).
- GraphQL query text names fields without a namespace prefix, like the existing field name
  strings in LWCs. When the namespace is registered, the queries in `addressPanel`,
  `affiliationPanel` and `relationshipPanel` need the prefix with the rest of that pass.
- The GraphQL queries cannot be checked offline (the Jest stub ignores the query); a deploy
  and a look at each card in a Contact-household org and a Person Account org confirm them.

## Amendment A1, 2026-11-12: the queries are built from schema imports (D-200 N13)

The namespace readiness pass (release 1.21) settles the prefix question above without a
second copy of each query and without moving the reads back to Apex.

1. **Dynamic queries.** `lightning/graphql` (API 65 or later; the cards are at 67) accepts
   `${}` interpolation inside `gql`. Each card builds its query from `@salesforce/schema`
   imports: the object from `objectApiName`, each field from `fieldApiName`, and each parent
   relationship from its lookup's name with `__c` changed to `__r`. The platform resolves the
   imports with the prefix once the namespace is set, so one query serves both.
2. **Reads by the same names.** The cards read each node and the result list by those same
   constants (`node[STATUS]`, `query[ADDRESS_OBJECT]`), never by a literal field name.
3. **Not chosen: a cacheable Apex DTO read.** It would have brought back the three
   controllers this ADR removed, and the stale Apex cache with them.
4. **Trade-off.** A dynamic query loses the compiler's check that each field exists. The
   schema imports keep that check: a renamed or deleted field fails the import at deploy.

## Amendment A2, 2026-11-22: the AP-03 inventory (D-219)

AP-03 moves the remaining flat reads and single-record writes off Apex. The inventory below is
every `@AuraEnabled` method that `scripts/ci/check-aura-lds.py` matches, plus the near misses a
wider scan found (one query and one write, or one selector call). Each row is converted or
kept, with the reason.

1. **Convert** when the method is one object read as the user, or one record written as the
   user, and anything else it does is shaping the LWC can do (trimming, a default value, the
   object's create or update permission from `getObjectInfo`). The LWC uses the target named,
   and the Apex method and its tests are deleted.
2. **Keep** when the method checks a custom permission or a module setting (custom metadata,
   which the UI API does not read), checks record access (`UserRecordAccess`, which the UI API
   does not expose), uses SOSL or describe, validates input on the server, writes more than one
   record, or composes several objects.
3. **The check.** It now blanks string literals before counting DML, so an error context such
   as `'Bulk update fields'` is not a write; that removed the two Bulk Update false positives.
   Every line of `scripts/ci/aura-lds-allowlist.txt` now says keep (with the reason) or
   convert (with the target); a convert line goes when its module's follow-up lands.
4. **A converted write loses its Error Log entry** from the controller, as the Consequences
   above already accept; a trigger failure still logs.
5. **Error wording stays.** A failed Lightning Data Service write carries the record's own
   message (a validation rule, a trigger's `addError`) under `body.output`; Core's
   `c/findCsv` `messageFrom` reads it first, so the toast says what the Apex method's
   `getDmlMessage` said before.

| Class.method | Package | Kind | Decision and target | Keep-reason |
| --- | --- | --- | --- | --- |
| ErrorLogController.getBugReport | core | read | Converted (AP-03 part 1): `getRecords` on the listed entries, Technical Detail optional | |
| BulkUpdateController.getTargets | core | read | Keep | Describe and the Bulk Update permission (was a false positive) |
| BulkUpdateController.getCopySources | core | read | Keep | Describe and the Bulk Update permission (was a false positive) |
| HouseholdMergeController.canEdit | core | read | Keep | Record edit access (`UserRecordAccess`) |
| HouseholdOfPersonController.makePrimary | core | write | Keep | Writes every member row of the household |
| ImportController.saveFile | core | write | Keep | Import permission, file decoded and stored as a ContentVersion |
| AccessExplorerController.searchPeople | orgoptimizer | read | Keep | SOSL name search and the Access Explorer permission |
| AccessExplorerController.searchPermissionSets | orgoptimizer | read | Keep | PermissionSet is not in the UI API |
| AskPipelineController.moveStage | giving | write | Convert: `updateRecord` | |
| CommitmentController.getSchedule | giving | read | Keep | Two objects and record edit access |
| CommitmentEntryController.save | giving | write | Keep | Server validation and the draft built from the entry |
| FundraisingHomeController.getHome | giving | read | Keep | Composes the home tiles; the one query is a first-run check |
| QuickGiftEntryController.getMatchableGifts | giving | read | Convert: GraphQL (`Gift__c`, employer filter through both donor lookups) | |
| ReceiptController.getTemplates | giving | read | Convert: GraphQL (`Receipt_Template__c` by Type, Name) | |
| ReceiptController.getRuns | giving | read | Convert: GraphQL (`Receipt_Run__c`, latest 10) | |
| RecurringHealthController.createFollowUp | giving | write | Keep | Reads the commitment and writes a Task (two objects) |
| StewardshipPlanController.deleteStep | giving | write | Keep | Manage BarnCRM Settings permission |
| StewardshipPlanController.setActive | giving | write | Keep | Manage BarnCRM Settings permission |
| EligibilityController.saveRules | programs | write | Keep | Rules validated against the program's fields (describe) |
| CohortController.getPersonName | programs | read | Convert: `getRecord`, optional `Contact.Name` and `Account.Name` (confirm in an org) | |
| EventAgendaController.moveSession | events | write | Converted (AP-03 events): `updateRecord` | |
| EventAppointmentsController.addSlots | events | write | Keep | Writes several slots |
| EventProposalReview.removePresenter | events | write | Converted (AP-03 events): `deleteRecord` | |
| EventProposalReview.saveCriteria | events | write | Keep | Criteria JSON validated on the server |
| EventSeatingController.deleteTable | events | write | Converted (AP-03 events): `deleteRecord` | |
| EventSeatingController.saveNeeds | events | write | Converted (AP-03 events): `updateRecord`, trimmed in `eventSeatingModel` | |
| EventSpeakersController.addSpeaker | events | write | Converted (AP-03 events): `createRecord` | |
| EventSpeakersController.assign | events | write | Converted (AP-03 events): `createRecord` | |
| EventSponsorsController.addDeliverable | events | write | Converted (AP-03 events): `createRecord`, trimmed and Type defaulted in `eventSponsorsModel` | |
| EventSponsorsController.removeSponsor | events | write | Converted (AP-03 events): `deleteRecord` | |
| EventSponsorsController.setDeliverableStatus | events | write | Converted (AP-03 events): `updateRecord` | |
| EventVolunteersController.getVolunteers | events | read | Keep | Volunteers jobs through the extension point |
| FormRunnerController.getPublishedForms | forms | read | Convert: GraphQL (`Form__c` Published, by Name) | |
| FormSubmissionController.getSubmission | forms | read | Convert: GraphQL (`Form_Submission__c` with form and version), shaping in a JS module | |
| GrantAnswerController.getLibrary | funders | read | Convert: GraphQL (`Grant_Answer__c` by Name) and `getObjectInfo` | |
| GrantAnswerController.markUsed | funders | write | Convert: `updateRecord` | |
| GrantPipelineController.moveStage | funders | write | Convert: `updateRecord` | |
| GrantPipelineController.recordAward | funders | write | Convert: `updateRecord` | |
| LwcBuilderController.getStudio | lwcbuilder | read | Keep | Returns the module settings (custom metadata) |
| LwcBuilderController.loadComponent | lwcbuilder | read | Keep | Returns the Components Enabled setting |
| LwcBuilderController.saveComponent | lwcbuilder | write | Keep | Definition validated and versioned on the server |
| ProjectBillingController.getInvoiceActions | projects | read | Keep | Billing setting, manage permission, payment availability |
| ProjectBillingController.getProjectBilling | projects | read | Keep | Billing setting and manage permission |
| ProjectBillingController.exportInvoices | projects | read | Keep | Stamps every exported invoice |
| ProjectRequestsController.addComment | projects | write | Converted (AP-03 part 3): `createRecord` | |
| ProjectRequestsController.getRequest | projects | read | Keep (reviewed in AP-03 part 3) | Change Requests setting (custom metadata) read with the request; it enables Create Change Request |
| ProjectRequestsController.getRequests | projects | read | Keep | Requests setting read with the list |
| ProjectRequestsController.saveRequest | projects | write | Converted (AP-03 part 3): `updateRecord`, editable fields listed in the LWC | |
| ProjectStaffingController.saveResource | projects | write | Keep | Upsert by user and the staffing setting |
| ProjectTimesheetController.addExpense | projects | write | Keep | Expenses setting |
| ProjectTimesheetController.getTasks | projects | read | Converted (AP-03 part 3): GraphQL (`Project_Task__c` open, by Sort Order) | |
| ProjectsController.addTask | projects | write | Converted (AP-03 part 3): `createRecord`, blank name refused in the LWC | |
| ProjectsController.getAtRisk | projects | read | Converted (AP-03 part 3): GraphQL (`Project__c` at risk or off track), Only Mine filtered in the LWC | |
| ProjectsController.logTime | projects | write | Keep | Time tracking setting |
| ProjectsController.setTaskStatus | projects | write | Converted (AP-03 part 3): `updateRecord`, Completed Date set in the LWC | |
| ReportingLibrary.remove | reporting | write | Keep | Owner check on a ContentDocument |
| ScholarshipsController.getAward | scholarships | read | Keep | Payments from a second object and the manage permission |
| ScholarshipsController.getBoard | scholarships | read | Keep | Review board across objects, blind review |
| ScholarshipsController.getReview | scholarships | read | Keep | Rubric, the reviewer's own review, blind review |
| VolunteersHomeController.getFirstRun | volunteers | read | Convert: GraphQL (`Volunteer_Job__c`, first 1) and `getObjectInfo` | |

Of the 61 methods, 28 are converted (1 in this part, 27 in the module follow-ups) and 33 stay
in Apex. `ProjectRequestsController.getRequest` was first listed to convert; the projects
follow-up kept it, since the panel's Create Change Request needs the Change Requests setting,
which the UI API does not read.
