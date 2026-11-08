# Without Sharing Register

Every top-level Apex class that BarnCRM ships `without sharing`, what it reaches past sharing
for, and the decision that allows it. Architect review RT-14; checked by
`scripts/ci/check-without-sharing-register.py`, which fails when a class here is missing from
the code or a `without sharing` class is missing here. Inner classes take their outer class's
entry. Test classes are not listed.

The default is `with sharing` or `inherited sharing` and user-mode queries and DML (plan Section
4.13). ADR-0021 (system mode writes for package owned data) and its extensions (ADR-0027 for
scheduled upkeep, ADR-0057 and ADR-0134) are the authority for every exception. The reasons fall
into six kinds:

| Kind | Meaning |
|---|---|
| Integrity | A rule must see records the saving user cannot (a duplicate, a dependent record), or the rule would pass when it should refuse. Read only. |
| Upkeep | Package-owned records or fields are kept correct after a save, whoever saved; the user may not be able to edit the other record. |
| Org job | A scheduled or queued job works on the whole org, not on what its scheduler can see. |
| Org figure | A total or count must be the organization's figure, not the viewer's share. |
| Platform | The platform allows the write only as the system (an Apex sharing reason share, a protected custom setting). |
| Portal | Called by the portal integration user, which has no object access; every read and write is scoped in code to the verified portal person and their template (ADR-0185 portal builder). |

## Core

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| AffiliationUpkeepSelector | Integrity | Overlapping affiliations owned by someone else, so the primary-affiliation rule still refuses them | ADR-0021 category 2 |
| AffiliationUpkeepWriter | Upkeep | The person's primary affiliation fields and their other affiliations, which the saver may not be able to edit | ADR-0021 category 2 |
| AutomationSettingsWriter | Platform | The automation pause on the protected org settings and the Automation Setting rows from the shipped registry | ADR-0021 |
| EmptyHouseholdTidyBatch | Org job | Every empty household, read and deleted as the scheduler, with the dependents check reaching every child record | ADR-0021, ADR-0036 |
| ErrorDigestWriter | Platform | The digest run record on the protected org settings | ADR-0021, ADR-0027 |
| ErrorLogEventHandler | Upkeep | Writes the Error Log entry from the event, whoever raised it | ADR-0021 |
| ErrorLogWriter | Upkeep | Writes the Error Log entry even when the user cannot create one | ADR-0021 |
| HouseholdMergeWriter | Upkeep | The platform account merge, which needs delete access to the household that goes away, once BarnCRM has authorized the merge | ADR-0021, ADR-0134 |
| OrgSettingsSystemWriter | Platform | Saves keys on the protected org-level settings record for the named system writers | ADR-0021, ADR-0027 |
| RecordRetentionBatch | Org job | Deletes the history rows past their retention (setting changes, merge journal, finished and abandoned imports and their staged rows, Error Log entries, field use counts) the scheduler may not see, so none is left for ever | ADR-0021, ADR-0027, ADR-0166 |
| RelationshipUpkeepSelector | Integrity | The reciprocal and duplicate relationships owned by someone else | ADR-0021 category 2, ADR-0109 |
| RelationshipUpkeepWriter | Upkeep | The other side of a relationship, usually owned by another user | ADR-0021 category 2, ADR-0109 |
| SavedQuerySharingWriter | Platform | Shares on saved queries with an Apex sharing reason | ADR-0076, ADR-0021 |
| SeasonalAddressSelector | Org job | Every household due a seasonal address swap, so none is silently left out | ADR-0021, ADR-0027 |
| SeasonalAddressWriter | Org job | The package's own address records for the nightly swap (the copy into standard address fields stays in user mode) | ADR-0021, ADR-0027 |
| SetupChangeCopyJob | Org job | The package's own copy of Setup changes, written and pruned in full | ADR-0021 |
| WhatsNewSeenWriter | Platform | The running user's own row of a protected hierarchy setting | ADR-0021, ADR-0087 |
| WhereUsedSelector | Integrity | Every saved query, private ones included, before a field is retired | ADR-0021 |

## Rollup Builder

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| RollupAggregator | Org figure | Every source row of a total, so a total does not depend on who saved | ADR-0015, ADR-0021 |
| RollupChanges | Org figure | Records along a rollup's path beyond the first reference | ADR-0021 |
| RollupClearBatch | Org job | Blanks a rollup field on every target record | ADR-0021 |
| RollupDependents | Org figure | Source rows under a parent whose attribute changed | ADR-0021 |
| RollupFullRecalcBatch | Org job | Every record of a target entity, and the queue | ADR-0021 |
| RollupLargeParentBatch | Org job | Every source row of a parent too large for one job | ADR-0021, ADR-0116 |
| RollupQueue | Upkeep | The engine's own queue, written by any save | ADR-0021 |
| RollupRecalcErrorHandler | Upkeep | The failed batch's records, handed back to the queue | ADR-0021 |
| RollupWriter | Upkeep | Rollup fields, usually read-only to the people who see them | ADR-0021 |

## Giving

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| AcknowledgmentWriter | Org job | Thanks donors the scheduling user may not see (the screen's selector stays in user mode) | ADR-0021 |
| AskDonorDateSync | Org figure | The donor's next ask date from every open ask, private ones included | ADR-0021 |
| AskReminderWriter | Upkeep | Reminder tasks assigned to the donor's owner | ADR-0021 |
| DonorLevelWriter | Upkeep | The two donor level fields | ADR-0021 |
| GiftImportIntegritySelector | Integrity | A gift already loaded under an external ID, or a receipt that keeps a gift on undo | ADR-0021, ADR-0052 |
| GivingHouseholdDependentsExtension | Integrity | Gifts that keep a household from being deleted | ADR-0021 |
| HealthCheckGivingSelector | Org figure | Every gift for Health Check's counts | ADR-0021, ADR-0057 |
| PledgeReminderWriter | Org job | Reminds donors the scheduling user may not see | ADR-0021 |
| ReceiptNumberSequence | Platform | The receipt number sequence, which no permission set lets anyone write | ADR-0021 |
| ReceiptWriter | Org job | Issues receipts for donors the running user may not see | ADR-0021 |
| StewardshipWriter | Upkeep | Stewardship tasks assigned to the donor's owner | ADR-0021 |

## Volunteers

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| VolunteerErasureSelector | Integrity | Every Volunteers record naming a person being erased, so erasure refuses rather than leaves one | ADR-0021 |
| VolunteerHealthCheckSelector | Org figure | Private volunteer hours for Health Check's counts | ADR-0021, ADR-0057 |
| VolunteerIntegritySelector | Integrity | Hours, sign-ups and attendance entries another staff member made | ADR-0021 |
| VolunteerNudgeSelector | Org job | Every unfilled shift and the email address of each volunteer who has helped on its job, for the morning nudges | ADR-0021 |
| VolunteerReminderSelector | Org job | Every booking and email address for the morning reminders | ADR-0021 |
| VolunteersHouseholdDependentsExtension | Integrity | Private hours that keep a household from being deleted | ADR-0021 |
| VolunteersPortalExtension | Portal | The shift a portal person signs up for and that person's own sign-up to cancel; the integration user has no object access, and each write names only the person Portal Builder verified | ADR-0021, ADR-NEXT portal templates |

## Programs

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| CaseNoteSelector | Integrity | Every case note about a person being erased | ADR-0021 |
| EnrollmentIntegritySelector | Integrity | An open enrollment another staff member entered, once enrollments are private | ADR-0021 |
| ProgramsSharing | Platform | Apex sharing reason shares and the participants group member | ADR-0021 |
| ProgramsSharingBatch | Platform | The same shares, for every enrollment and delivery | ADR-0021 |
| ReferralSelector | Integrity | Every referral about a person being erased | ADR-0021 |
| ServiceDeliveryIntegrity | Integrity | The day's delivery for a person and service that the saver cannot see | ADR-0021 |

## Logic Models

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| IndicatorResultsBatch | Org figure | Every record an indicator counts | ADR-0158 |
| LogicModelIntegritySelector | Integrity | A model someone else owns for the same scope | ADR-0021 |

## Funders

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| GrantReminderSelector | Org job | Every grant requirement for the morning reminders | ADR-0021 |

## Contact Point Sync

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| ContactPointSyncService | Upkeep | The person's managed Contact Points, Individual and Contact Point Links, which the saver may not be able to see or edit | ADR-0021, ADR-0176 contact point sync module |
| ContactPointBackfillBatch | Org job | Every person in the org, synced as a save would; started only from the Contact Point Sync page by a holder of Manage BarnCRM Settings | ADR-0021, ADR-0176 contact point sync module |

## Forms

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| FormIntakeService | Platform | A Site guest user, who has no object access, loads one published public form and version and stores one Received submission; it never reads a person, an organization or any other record, and processing runs later in user mode. It also serves a module's public page (EV-16) and checks only that the form the page names is published and public | ADR-0184 public forms on a Salesforce Site, ADR-0190 public event pages |

## Event Management

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| EventPublicPage | Platform | A Site guest user or the API's integration user reads one event staff marked Public Page (Open or Closed only): its public fields, active tickets, confirmed sessions, seat counts with Show Seats Left, and confirmed speakers' names, headlines and bios with Show Speakers; never the online link, codes, registrations, attendees or other person fields | ADR-0190 public event pages |

## Portal Builder

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| PortalAuth | Portal | Portals, accesses and sessions, and the one Contact an email names, to send and check sign-in codes and resolve sessions; only hashes are stored | ADR-0021, ADR-0185 portal builder |
| PortalData | Portal | The verified person's own Contact and the records a template names, filtered by that person or the catalog's fixed tests; only `edit` fields are written | ADR-0021, ADR-0185 portal builder |

## Event Management

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| EventsPortalExtension | Portal | The open event a portal person proposes a talk for and that person's own proposal to withdraw; the integration user has no object access, and each write names only the person Portal Builder verified | ADR-0021, ADR-NEXT portal templates |

## Mirror

| Class | Kind | What it reaches past sharing for | Authority |
|---|---|---|---|
| MirrorSettingsWriter | Platform | Each mirror's run record on the protected org settings | ADR-0021, ADR-0038 |
