# AppExchange Submission Notes

The false-positive and justification notes for the Salesforce AppExchange security review of
BarnCRM Core. Each scanner finding below is either a tool limitation or a documented design
decision, with the code location and the decision record that explains it.

Scans of 2026-10-28 used Salesforce Code Analyzer 5.16.0 with `sf` 2.155.7: the AppExchange
selector, all rules (PMD, ESLint, retire-js, regex, Flow, CPD), and the Graph Engine (SFGE) on
Core. There are no severity 1 findings, and no High or Critical manual findings in Core. The
Graph Engine log shows 54 path-timeout notices, so its coverage is partial. Decision records
are in `docs/architecture/decisions/`; the working checklist is
`docs/contributor-guide/security-checklist.md`.

## Graph Engine ApexFlsViolation (30 Sites)

52 hits at 30 distinct sites, severity 2. SFGE does not recognise `WITH USER_MODE` or
`AccessLevel.USER_MODE` as a field-level security check, and it cannot follow
`Security.stripInaccessible` to the records used afterwards. Every other site is a documented
`SYSTEM_MODE` read or write of data the package owns. All paths are under
`packages/core/main/default/classes/`.

### User Mode Sites (Scanner False Positives)

| Site | Operation and object | Access mode used | Why it is safe | ADR |
| ---- | -------------------- | ---------------- | -------------- | --- |
| `AutomationControl.cls:97` | UPDATE `Automation_Setting__c` (`Enabled__c`) | `Database.update(..., AccessLevel.USER_MODE)` | Class is `with sharing`; the switch is changed with the caller's own access, and only the switch field is sent. | ADR-0021 |
| `ErrorLogController.cls:65` | UPDATE `Error_Log__c` (`Status__c`) | `Database.update(..., AccessLevel.USER_MODE)` | Class is `with sharing`; acknowledging an entry uses the caller's own access. | ADR-0021 |
| `HouseholdOfPersonController.cls:90` | UPDATE `Household_Member__c` (`Is_Primary__c`) | `Database.update(..., AccessLevel.USER_MODE)` | Class is `with sharing`; a person-initiated write with the caller's own access. | ADR-0021 |
| `HouseholdOfPersonController.cls:181` | INSERT `Account` (person) | `Database.insert(..., AccessLevel.USER_MODE)` | Class is `with sharing`; the person is created with the caller's own access. | ADR-0021 |
| `ImportController.cls:702` | INSERT `ContentVersion` (uploaded import file) | `Database.insert(..., AccessLevel.USER_MODE)` | Class is `with sharing`; SFGE reports ternary placeholders (`TODO_SFGE_Ternary_0`) as unknown fields. | ADR-0021 |
| `SettingsService.cls:961` | INSERT `Setting_Change__c` (audit row) | `Database.insert(..., AccessLevel.USER_MODE)` | Class is `with sharing`; confirmed user mode (the review had it as probable). | ADR-0021 |

### Stripped Read Site

| Site | Operation and object | Access mode used | Why it is safe | ADR |
| ---- | -------------------- | ---------------- | -------------- | --- |
| `HouseholdSelector.cls:590` | READ `Account` (`getHouseholdsForMerge`, the households a merge compares) | `WITH SYSTEM_MODE` query, then `readableRecords` calls `Security.stripInaccessible(AccessType.READABLE, ...)` and returns only the stripped records | A display read: the class is `with sharing`, object access is checked, and every field the user cannot read is removed before anything is built. Stripped rather than `WITH USER_MODE`, which refuses the whole query when one field is unreadable. SFGE cannot follow the returned stripped list. | ADR-0021 |

### System Mode Sites (Documented Package Bookkeeping and Upkeep)

Each class header, or the comment at the site, states the system mode choice. All classes are
`with sharing` unless the row says otherwise.

| Site | Operation and object | Access mode used | Why it is safe | ADR |
| ---- | -------------------- | ---------------- | -------------- | --- |
| `AutomationSettingSelector.cls:14` | READ `Automation_Setting__c` | `WITH SYSTEM_MODE` | The framework's on and off switch read; no record data is returned and nothing is written. The console read (`selectAllForConsole`) is user mode. | ADR-0021 |
| `AutomationSettingsWriter.cls:54` | INSERT `Automation_Setting__c` (materialized switch rows) | `AccessLevel.SYSTEM_MODE`, `without sharing` writer | Rows come from the shipped registry; `Always_Runs__c` is not editable by any packaged permission set. Caller gates verified (`AutomationControl.cls:126,318`). | ADR-0021, ADR-0024 |
| `CustomMetadataManagerSelector.cls:63` | READ `Setting_Change__c` (`Deployment_Id__c`) | `WITH SYSTEM_MODE` | Returns only whether a deployment finished, to a caller the controller has already checked holds Manage BarnCRM Metadata. | ADR-0021 pattern (header states the reasoning) |
| `CustomMetadataManagerSelector.cls:74` | READ `Error_Log__c` (deployment outcome message) | `WITH SYSTEM_MODE` | Same caller gate; returns the deployment failure message only. | ADR-0021 pattern (header states the reasoning) |
| `HouseholdSelector.cls:122` | READ `Contact` (`getContactsByHouseholdIds`) | `WITH SYSTEM_MODE` | Upkeep read feeding member count and names; nothing read here reaches a screen. | ADR-0021 |
| `HouseholdSelector.cls:148` | READ `Contact` (`getContactsByIds`) | `WITH SYSTEM_MODE` | Upkeep read, as above. | ADR-0021 |
| `HouseholdSelector.cls:233` | READ `Contact` (`getContactsWithHouseholds`) | `WITH SYSTEM_MODE` | Upkeep read of `AccountId` and record type only. | ADR-0021 |
| `HouseholdSelector.cls:247` | READ `Account` (`getHouseholdsByIds`) | `WITH SYSTEM_MODE` | Upkeep read feeding the household writer. | ADR-0021 |
| `HouseholdSelector.cls:278` | READ `Account` (`getAccountRecordTypes`) | `WITH SYSTEM_MODE` | Reads `RecordTypeId` only. | ADR-0021 |
| `HouseholdSelector.cls:674` | READ `Household_Member__c` (`getMemberships`) | `WITH SYSTEM_MODE`, no strip at the site | Upkeep read (callers are `HouseholdService` and `HouseholdMemberTriggerHandler`); not a display read. SFGE reports the stripInaccessible message on a path that reaches here. | ADR-0021 |
| `HouseholdSelector.cls:698` | READ `Household_Member__c` (`getMembershipsForPeople`) | `WITH SYSTEM_MODE` | Upkeep read. | ADR-0021 |
| `HouseholdSelector.cls:733` | READ `Household_Member__c` (`getAllMembershipsForPeople`) | `WITH SYSTEM_MODE` | Upkeep read. | ADR-0021 |
| `HouseholdSelector.cls:769` | READ `Household_Member__c` (`getDeletedMembershipsForPeople`) | `WITH SYSTEM_MODE` | Upkeep read. | ADR-0021 |
| `HouseholdSelector.cls:787` | READ `Account` (`getHouseholdsForRecomputeLocator`) | `WITH SYSTEM_MODE` | Batch locator for the household recompute. | ADR-0021 |
| `HouseholdSelector.cls:821` | READ `Contact` (`AccountId` only) | `WITH SYSTEM_MODE` in the private `without sharing` inner class `OccupancyReader` | Answers household ids only, so an emptied household is never deleted because the saving user cannot see its contacts (ADR-0021 category 2). See the sharing table below. | ADR-0021 |
| `ImportBatchSelector.cls:184` | READ `Import_Row__c` | `WITH SYSTEM_MODE` | Staged rows are the package's own bookkeeping; the rows shown to the user are read in user mode. | ADR-0021 |
| `ImportJournalService.cls:203` | INSERT `Import_Journal__c` | `AccessLevel.SYSTEM_MODE` | The undo journal is package-owned bookkeeping, written for the reason ADR-0021 gives. | ADR-0021 |
| `ImportProcessorBatch.cls:62` | READ `Import_Batch__c` (`Retry_After_Row__c`) | `WITH SYSTEM_MODE` | Package bookkeeping; the records the run creates are written in user mode. | ADR-0021 |
| `ImportProcessorBatch.cls:80` | READ `Import_Row__c` (batch locator) | `WITH SYSTEM_MODE`, stated because API 67.0 would otherwise read in user mode | Staged rows feed the processing only; the records a row makes are still written in user mode. | ADR-0021 |
| `ImportRowSelector.cls:140` | READ `Import_Row__c` | `WITH SYSTEM_MODE` | Staged rows are the package's own bookkeeping. | ADR-0021 |
| `ImportTemplateService.cls:782` | UPDATE `Import_Template__c` | `AccessLevel.SYSTEM_MODE` | Restores a shipped template; the value written comes from packaged custom metadata (ADR-0021 condition 2). | ADR-0021 |
| `ImportUndoBatch.cls:153` | READ `Import_Batch__c` (`Operation__c`) | `WITH SYSTEM_MODE` | Package bookkeeping read by the undo run. | ADR-0021 |
| `ScheduledJobSelector.cls:53` | READ `User` (`IsActive`) | `WITH SYSTEM_MODE` | Setup objects are read in system mode so an administrator without View Setup still gets a correct Health Check; returns whether the scheduling owner is active. | ADR-0038 |

## Graph Engine DatabaseOperationsMustUseWithSharing (3 Sites)

The rule fires on database operations in classes that do not enforce sharing. Each site is a
documented `without sharing` writer or reader.

| Site | Class | What it does | Why `without sharing` | ADR |
| ---- | ----- | ------------ | --------------------- | --- |
| `packages/core/main/default/classes/AutomationSettingsWriter.cls:54` | `AutomationSettingsWriter` | Inserts switch rows from the shipped registry | The protected settings take no object or field permissions in a subscriber org; callers check the Manage permission first. | ADR-0021, ADR-0024 |
| `packages/core/main/default/classes/ErrorLogWriter.cls:93` | `ErrorLogWriter` | Writes error entries in system mode, surviving the rollback of the failing transaction | An error must be recorded even when the user has no create access on the Error Log object. | ADR-0021 |
| `packages/core/main/default/classes/HouseholdSelector.cls:821` | `HouseholdSelector.OccupancyReader` (private inner class) | Reads `Contact.AccountId` and answers household ids only | Package upkeep must not depend on what the saving user can see. | ADR-0021 |

## AppExchange Rule Hits

The AppExchange selector (37 PMD rules) reported 36 violations, all severity 3: 26
`ProtectSensitiveData` (14 Core, 12 modules), 7 `AvoidHardcodedCredentialsInFieldDecls`
(3 Core, 4 modules), and 3 `AvoidLwcBubblesComposedTrue`. All are false positives.

### ProtectSensitiveData (Core)

The rule matches field names containing `Key`, `Token` or similar. None of these fields holds a
credential, token or secret. Paths are under `packages/core/main/default/objects/`.

| Field | Why it is not sensitive |
| ----- | ----------------------- |
| `Duplicate_Dismissal__c.Pair_Key__c` | The two record ids of a dismissed duplicate pair, ascending and hyphen-joined; a uniqueness key. |
| `Import_Batch__c.Pass_Number__c` | Counter of dry runs and commits on an import. |
| `Import_Row__c.Organization_Key__c` | Digest of an organization name, used to match within a dry run. |
| `Import_Row__c.Pass_Number__c` | Counter of the pass that last processed the row. |
| `Import_Row__c.Person_1_Key__c` | Digest of a person matching key, dry run only. |
| `Import_Row__c.Person_1_Name_Key__c` | Digest of a first-name matching key, dry run only. |
| `Import_Row__c.Person_2_Key__c` | Digest of a person matching key, dry run only. |
| `Import_Row__c.Person_2_Name_Key__c` | Digest of a first-name matching key, dry run only. |
| `Import_Row__c.Processor_Key__c` | Digest of what a row would load that a later row may name again. |
| `Import_Row__c.Row_Key__c` | Digest of the row's one-row-per-key cells, for matching staged rows. |
| `Import_Row__c.Soft_Credit_Id__c` | A record identifier (lookup-style reference) to a second record made by a module import. |
| `Import_Template_Default__mdt.Template_Key__c` | Stable identifier of a shipped import template, matched on upgrade. |
| `Import_Template__c.Template_Key__c` | Stable identifier of an import template. |
| `Setting_Definition__mdt.Setting_Key__c` | Name of a setting in the shipped registry. |

The 12 module rows (Giving, Rollups, Volunteers: `Gift_Key__c`, `Series_Key__c`,
`Donor_Year_Key__c`, `Assign_To__c`, `Assigned_User__c`, `Plan_Key__c`, `Definition_Key__c`,
`Bypass_Permission__c`, `Volunteer_Signup__c`, `Template_Key__c`) are the same kind: matching and
idempotency keys, lookups and permission names.

### AvoidHardcodedCredentialsInFieldDecls

| Site | Scope | Why it is not a credential |
| ---- | ----- | -------------------------- |
| `packages/core/main/default/classes/HouseholdNamingService.cls:34` | Core | `TOKEN_FIRST_NAME = '{FirstName}'`, a merge-token constant for household names. |
| `packages/core/main/default/classes/HouseholdNamingService.cls:35` | Core | `TOKEN_LAST_NAME = '{LastName}'`, a merge-token constant. |
| `packages/core/main/default/classes/HouseholdNamingService.cls:36` | Core | `TOKEN_SALUTATION = '{Salutation}'`, a merge-token constant. |
| `packages/giving/main/default/classes/ReceiptContentBuilder.cls:61` | Module (Giving) | `RAW_TOKENS`, receipt merge tokens. |
| `packages/rollups/main/default/classes/RollupPath.cls:29` | Module (Rollups) | `TOKEN_HOUSEHOLD`, a path token. |
| `packages/rollups/main/default/classes/RollupPath.cls:30` | Module (Rollups) | `TOKEN_HOUSEHOLD_MEMBERS`, a path token. |
| `packages/volunteers/main/default/classes/VolunteerLetterTemplates.cls:8` | Module (Volunteers) | `TYPE_CERTIFICATE`, a letter template type name. |

### AvoidLwcBubblesComposedTrue

| Site | Why it is acceptable |
| ---- | -------------------- |
| `packages/core/main/default/lwc/healthCheckPanel/healthCheckPanel.js:372` | Product code. A cancelable `navigatetosection` event carrying only a section name, so a host console can switch section in place. If nobody handles it, the panel navigates itself. No data crosses the shadow boundary. |
| `packages/core/main/default/lwc/firstRunSetup/__tests__/firstRunSetup.test.js:119` | Jest test file, not shipped behavior. |
| `packages/giving/test/jest-mocks/lightning/actions.js:7` | Jest mock file (Giving module), not shipped behavior. |

### Other Rule Hits

| Rule | Where | Reason |
| ---- | ----- | ------ |
| PMD `GlobalVariable` (797 in Core product code) | LWC class fields, for example `accessManager.js:121` | PMD's Rhino JavaScript parser misreads ES class fields as globals. ESLint, the authoritative LWC engine, reports no such issue. Not in the AppExchange selector. |
| PMD `AvoidDebugStatements` (6 in product code) | `ErrorLogWriter.cls:75,99`, `ErrorLogEventHandler.cls:55`, `ErrorLogger.cls:92`, `EmptyHouseholdTidyBatch.cls:126`, `HealthCheckService.cls:702` | Last resort when Error Log writing itself fails; logs the exception message or counts only, as the security checklist allows. |
| Flow `SameRecordUpdate` (2) | `Template_Relationship_Reciprocal.flow-meta.xml:536,558` | Accepted open item in the security checklist: the flow writes the Id of a record created in the same run. |

## Accepted by Design

### View All and Modify All on Account and Contact in BarnCRM Admin

Kept (owner decision, 2026-10-28). The `BarnCRM_Admin` permission set carries View All and
Modify All on `Account` and `Contact`, the standard objects Core's household and person
features work on. The reasons:

- **Merges.** Household and person merge, and the platform merge, need delete access to the
  losing record and edit access to the surviving record, whoever owns them.
- **Erase a Person.** It must find and remove every record of a person wherever it is shared.
- **Household upkeep.** Recount, rename, primary contact, and address propagation reach members
  owned by other users.

BarnCRM Admin is the administrator role and is given deliberately. BarnCRM Staff and BarnCRM Read
Only do not get these permissions. The permission set description states it too. Record:
ADR-0142 (`docs/architecture/decisions/0142-admin-view-all-modify-all-on-account-and-contact.md`).

### BarnCRM Access Manager Permission Set

Kept (ADR-0121, decision D-91). `BarnCRM_Access_Manager` carries Assign Permission Sets and View
All Users.

- It is optional and in no role: it is in no permission set group, and a system administrator
  assigns it in Setup only.
- It exists so a BarnCRM Admin on a full Salesforce license who is not a system administrator can
  give BarnCRM roles from the Access page.
- The Access page checks Manage BarnCRM Settings and the platform permission on every change
  (`AccessService.changeRefusal`, `packages/core/main/default/classes/AccessService.cls:309`,
  called by `requireAssignPermission` before each assignment).
- Assign Permission Sets is admin-equivalent. The admin guide (`docs/admin-guide/access.md`)
  warns about that and says who should hold it.

### Other Accepted Items

| Item | Where | Reason |
| ---- | ----- | ------ |
| Global invocables | `CreatePersonAction`, `FindPeopleAction`, `GetDataJobStatusAction`, `GetHouseholdSummaryAction` | ADR-0104: `with sharing`, user-mode reads and writes. |
| `Error_Log__c` View All for Read Only and Staff | Permission sets | Owner decision D-78. Technical Detail is unreadable to Read Only (field permission `readable=false`); the Message field holds labels and record names only (security checklist section 5). |
| `without sharing` Core classes (18) | For example `HouseholdMergeWriter`, `SavedQuerySharingWriter`, `ErrorLogWriter`, `OrgSettingsSystemWriter`, `AutomationSettingsWriter`, `SeasonalAddress*`, `*Upkeep*`, the purge and tidy batches | Each header cites ADR-0021, 0027, 0057, 0076 or 0134, and each claimed caller gate was verified in code (for example `HouseholdMergeService.cls:242-247`, `FindController.cls:353,367`, `SettingsWriter.cls:46`, `AutomationControl.cls:126,318`, `SeasonalAddressController.cls:50`). |
| Dynamic SOQL (about 60 Core sites) | `QueryCompiler`, `FilterValueBinder`, Find, Import, BulkDelete, BulkUpdate, Household selectors, erasure | Object and field names come from describe, constants or registries; ORDER BY direction, operators and LIMIT are allowlisted; every value is bound. No SOSL. |
| Callouts and secrets | None | No `Http`, Named or External Credentials, Remote Site Settings or CSP sites, session IDs or secrets. Email is plain-text or template-based only. |
| Guest and unauthenticated access | None | No Sites, Experience Cloud targets, profiles or guest settings; template flows ship as Draft. |
| Protected custom settings | `BarnCRM_Settings__c`, `Whats_New_Seen__c` | Hierarchy and Protected; they hold configuration, not secrets. |
