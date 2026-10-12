# Reference: Nonprofit Cloud and Agentforce Nonprofit Data Model

Status: research reference, not a settled decision. Feeds two later features:

- **X-07 Gift Transaction mirror** (Connect package, v0.6; plan Sections 4.5, 4.12).
- **C-14 Agentforce Nonprofit import templates** (Import framework, v0.2; plan Sections 4.9, 6.3).

Nothing here changes the canonical model or creates a dependency. Every Nonprofit Cloud
object named below is optional and is only ever touched from the Connect package behind
dynamic Apex (plan Section 4.2 hard rules, Section 6.3 dependency rule). Last verified
2026-09-09.

## 1. How this was verified, and what could not be read

`developer.salesforce.com`, `help.salesforce.com`, `resources.docs.salesforce.com` and
`trailhead.salesforce.com` are all refused by this environment's egress proxy (HTTP 403
on CONNECT, organization policy). No official page could be fetched directly. Three
channels were used instead:

1. **Web search result snippets from the official pages**, giving object identity, a
   one-line purpose, API version, and licensing statements. Official URLs are cited per
   object below and are the authority; read them before implementing.
2. **`forcedotcom/d360-mcp-server`** (Salesforce-owned GitHub repository, Apache-2.0),
   file `src/main/resources/mappings/<Object>_DMO_Mappings.xml`. Each declares a
   `sourceObjectName` and a `sourceField` per CRM field, so it is a Salesforce-published
   list of field API names per object.
3. **Retrieved org metadata in public repositories** (for example `dnstommy/gearset-demo`
   and `ProvisioPartners/ESSCDevOps`): `objects/<Object>/fields/*.field-meta.xml`, report
   types and layouts from real Nonprofit Cloud orgs, giving relationship and picklist types.

**Confidence marks:** field API names below are corroborated by at least two of the three
channels. Types marked `*` are inferred from the field name and use, not read from a
describe call. **Before X-07 or C-14 code is written, run a describe against a real
Nonprofit Cloud org and correct this file.** Nothing here was invented; where a value was
not found, it says so.

**Update 2026-09-09:** the household and group membership material in Section 4 was
verified directly from the official pages cited there (the object reference pages for
`PartyRelationshipGroup` and `AccountContactRelation`, "Group Membership and Households
Standard Objects", the Group Definitions API resource, and Salesforce Help "Create Groups
and Relationships"). Those claims are marked verified below and no longer depend on the
three channels above. Section 3 is unchanged.

**Not verified at all:** picklist values (Gift Type, Status, Payment Method, Tribute Type,
Soft Credit Role), field lengths and precision, required versus optional flags,
`referenceTo` targets, the `GiftBatch` and `GiftCmtChangeAttrLog` field lists, and every
Volunteer Management object name.

## 2. Licensing and feature gating

- `GiftTransaction` and `GiftCommitment` are retrievable only when the **Fundraising
  Access license** is enabled and the **Fundraising User** system permission is assigned.
  Sources: Fundraising Editions and Permissions
  (`https://help.salesforce.com/s/articleView?id=sfdo.fundraising_editions_and_permissions.htm&type=5`)
  and Security and Permissions for Nonprofit Cloud
  (`https://help.salesforce.com/s/articleView?id=sfdo.npc_nonprofit_cloud_permission_sets.htm&type=5`).
- Every object in Sections 3 and 4 is an **Industries object**: absent from a
  Platform-only org, an NPSP org and a plain Sales Cloud org, and present only with
  Nonprofit Cloud or Agentforce Nonprofit licensing and the Fundraising feature on.
- **Actionable Segmentation** needs its own entitlement (Industry Sales Excellence Add On
  with the Actionable Segmentation permission set):
  `https://help.salesforce.com/s/articleView?id=sf.actionable_segmentation_assign_permissions.htm&type=5`.
- **Data Processing Engine**, which calculates fundraising rollups, ships with the
  Industries clouds and does not exist in a Platform-only org.
- Consequence: X-07 must detect all of this at runtime (`Schema.getGlobalDescribe`,
  `isAccessible`, `isCreateable`) and hide itself when absent. No BarnCRM package ever
  requires a permission set license.

## 3. Fundraising objects

Object pages live under
`https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/`
with the file name given per section (index: `npc_fundraising_standard_objects.htm`). All
fundraising objects below are API version 59.0 and later.

### 3.1 GiftTransaction

`npc_fundraising_api_objects_gifttransaction.htm`. A completed transaction from a gift.
The direct counterpart of BarnCRM `Gift__c`.

| Field | Type | Notes |
|---|---|---|
| `DonorId` | Lookup | The donor. In a Person Accounts org this is an Account (business account or person account). |
| `ContactId` | Lookup* | Contact associated with the transaction, used for organizational gifts. |
| `TransactionDate` | Date* | Date of the transaction. |
| `TransactionDueDate` | Date* | Due date, used for expected and pledged transactions. |
| `OriginalAmount` | Currency* | Amount as originally transacted. Required on the packaged layout. |
| `CurrentAmount` | Currency* | Amount after refunds and adjustments. |
| `RefundedAmount` | Currency* | Total refunded. |
| `NonTaxDeductibleAmount`, `TaxDeductionAmount` | Currency* | Tax split of the gift. |
| `DonorCoverAmount` | Currency* | Amount the donor added to cover fees. |
| `GatewayTransactionFee`, `ProcessorTransactionFee`, `TotalTransactionFee` | Currency* | Fee breakdown. |
| `Status` | Picklist | Transaction status. Values not verified. |
| `GiftType` | Picklist* | Gift type. Values not verified. |
| `PaymentMethod` | Picklist | Payment method. |
| `PaymentInstrumentId` | Lookup | Stored payment instrument. |
| `PaymentIdentifier`, `ProcessorReference`, `GatewayReference` | Text* | External payment references. |
| `CheckDate` | Date* | Check date for check gifts. |
| `IsPaid`, `IsWrittenOff`, `IsFullyRefunded`, `IsPartiallyRefunded` | Checkbox* | State flags. |
| `AcknowledgementStatus`, `AcknowledgementDate` | Picklist, Date* | Acknowledgment tracking. |
| `TaxReceiptStatus` | Picklist* | Receipting state. |
| `CampaignId` | Lookup | Standard Campaign. |
| `OutreachSourceCodeId` | Lookup | The appeal-level source code. |
| `GiftCommitmentId`, `GiftCommitmentScheduleId` | Lookup | Pledge or recurring commitment, and the schedule fulfilled. |
| `MatchingEmployerTransactionId` | Lookup | The employer's matching gift transaction. |
| `LastGatewayProcessedDate`, `LastGatewayResponseCode`, `LastGatewayErrorMessage` | Various* | Gateway result. |
| `Name`, `Description`, `OwnerId` | Text, Text, Lookup | Standard. |

Fields in the Salesforce Data Cloud mapping but not in the org retrieval used here (verify
by describe, several are Education Cloud oriented): `AdvancementType`, `GenerationalCohort`,
`GraduationCohort`, `GraduationAchievement`, `DonorGiftConceptId`, `GiftAgreementId`,
`PartyPhilanthropicRsrchPrflId`, `DataSourceId`, `DataSourceObjectId`.

### 3.2 GiftTransactionDesignation

`npc_fundraising_api_objects_gifttransactiondesignation.htm`. Junction between a gift
transaction and a gift designation, and counterpart of `Gift_Allocation__c`. Fields:
`GiftTransactionId` (Master-Detail), `GiftDesignationId` (Lookup), `Amount` (Currency*),
`Percent` (Percent*), `Name`.

### 3.3 GiftDesignation

`npc_fundraising_api_objects_giftdesignation.htm`. A fund designation assignable to a gift
transaction. Counterpart of `Fund__c`.

`Name`, `Description`, `IsActive`, `IsDefault`, plus rollup fields maintained by Data
Processing Engine: `TotalTransactionAmount`, `TotalTransactionCount`,
`CurrentYearTrxnAmount`, `CurrentYearTransactionCount`, `LastYearTrxnAmount`,
`LastYearTransactionCount`, `LastTwoYearTrxnAmount`, `LastTwoYearTrxnCount`,
`AverageTransactionAmount`, `HighestTransactionAmount`, `LowestTransactionAmount`,
`FirstPaidTransactionDate`, `LastPaidTransactionDate`. No accounting code and no
restricted flag was found, so those `Fund__c` fields have no native target.

### 3.4 GiftDefaultDesignation

`npc_fundraising_api_objects_giftdefaultdesignation.htm`. Default designation split for a
parent record: `ParentRecordId` (Lookup), `GiftDesignationId` (Lookup),
`AllocatedPercentage` (Percent*), `Name`.

### 3.5 GiftCommitment

`npc_fundraising_api_objects_giftcommitment.htm`. A supporter's commitment to give, pledge
or recurring. Counterpart of `Commitment__c`.

`DonorId` (Lookup), `ContactId` (Lookup*), `Status` (Picklist), `RecurrenceType`,
`ScheduleType`, `FulfillmentType`, `FormalCommitmentType`, `GiftVehicle` (Picklist),
`GiftVehicleType` (Picklist), `ExpectedTotalCmtAmount` (Currency*), `EffectiveStartDate`,
`ExpectedEndDate`, `EffectiveTransactionInterval`, `EffectiveTransactionPeriod`,
`CurrentGiftCmtScheduleId` (Lookup), `NextTransactionAmount`, `NextTransactionDate`,
`LastPaidTransactionDate`, `TotalPaidTransactionAmount`, `TransactionPaymentCount`,
`WrittenOffAmount`, `TotCommitmentScheduleAmt`, `TotalCurrentMonth`, `TotalCurrentQuarter`,
`TotalCurrentYear`, `TotalNextYear`, `CampaignId` (Lookup), `OpportunityId` (Lookup), plus
planned giving fields (`ExpectedAssetTransferDate`, `IsAssetTransferExpected`,
`TotalAssetPresentValue`, `PlannedGiftId` and related).

### 3.6 GiftCommitmentSchedule

`npc_fundraising_api_objects_giftcommitmentschedule.htm`. The schedule for fulfilling a
commitment. `GiftCommitmentId` (Master-Detail), `Type`, `StartDate`, `EndDate`,
`TransactionAmount` (Currency*), `TransactionDay`, `TransactionInterval`,
`TransactionPeriod`, `TotalScheduleAmount`, `PaymentMethod` (Picklist),
`PaymentInstrumentId` (Lookup), `CommitmentUpdateReason` (Picklist),
`GiftCommitmentSchdBefEditId` (Lookup, the prior version of the schedule),
`GiftCommitmentStatus`, `CampaignId`, `OutreachSourceCodeId`, `ProcessorReference`.

**Important:** the schedule is a recurrence rule, not a list of installment rows. There is
no per-installment object. Expected installments surface as `GiftTransaction` records with
a future `TransactionDueDate` and an unpaid `Status`.

### 3.7 GiftSoftCredit

`npc_fundraising_api_objects_giftsoftcredit.htm`. Soft credit attributed to a person or
organization for a gift transaction. `GiftTransactionId` (Master-Detail), `RecipientId`
(Lookup), `ContactId` (Lookup*), `Role` (Picklist), `SoftCreditAmount` (Currency*),
`PartialAmount`, `PartialPercent`. Related: `GiftAgreement`, `GiftStewardship`.

### 3.8 GiftTribute

`npc_fundraising_api_objects_gifttribute.htm`. Details and status of a gift tribute.
`GiftTransactionId` (Lookup), `GiftCommitmentId` (Lookup), `TributeType` (Picklist),
`HonoreeContactId` (Lookup), `HonoreeName`, `HonoreeInformation`, `NotificationContactId`
(Lookup), `NotificationContactName`, `NotificationEmail`, `NotificationChannel` (Picklist),
`NotificationMessage`, `NotificationInfo`, `NotificationDate`, `NotificationStatus`
(Picklist).

### 3.9 GiftRefund

`npc_fundraising_api_objects_giftrefund.htm`. A refund of a gift. `GiftTransactionId`
(Master-Detail), `Amount`, `Date`, `Reason` (Picklist), `Status` (Picklist), plus gateway
and processor fee and response fields.

### 3.10 GiftEntry

`npc_fundraising_api_objects_giftentry.htm`. Gifts created individually or in a batch
before processing, and afterwards an audit trail. This is the closest native analogue of
`Gift_Batch__c` plus `Import_Row__c`, and the most useful shape for a gift import template
because one row carries donor, gift and up to three designations.

`GiftBatchId` (Lookup), `DonorId`, `Salutation`, `FirstName`, `LastName`,
`OrganizationName`, `Email`, `HomePhone`, `MobilePhone`, `Street`, `City`, `State`,
`PostalCode`, `Country`, `GiftAmount`, `GiftReceivedDate`, `GiftType`, `PaymentMethod`,
`PaymentIdentifier`, `CheckDate`, `Last4`, `ExpiryMonth`, `ExpiryYear`, `DonorCoverAmount`,
`TotalTransactionFeeAmount`, `CampaignId`, `OutreachSourceCodeId`, `GiftCommitmentId`,
`GiftTransactionId`, `GiftDesignation1Id` / `2Id` / `3Id` with matching `Amount` and
`Percent` fields, `SoftCreditInformation`, `IsSetAsDefault`, `GiftProcessingStatus`,
`GiftProcessingResult`, `LastProcessedDateTime`.

### 3.11 OutreachSourceCode and OutreachSummary

`npc_fundraising_api_objects_outreachsourcecode.htm`. A source code associated with an
outreach campaign: the intersection of a message, a channel and an audience segment. One
Campaign has many outreach source codes. Counterpart of `Appeal__c`. See also
`https://help.salesforce.com/s/articleView?id=sfdo.fundraising_outreach_source_code_campaigns.htm&type=5`.

`Name`, `SourceCode`, `SourceCodeUrl`, `Status` (Picklist), `Description`, `CampaignId`
(Lookup), `MessageChannel`, `MessageChannelPlatform`, `MessageChannelPlatformAccount`,
`MessageContent`, `MessageContentTitle`, `AudienceCount`, `UsageType`.

`OutreachSummary` holds calculated response metrics per source code:
`OutreachSourceCodeId`, `CampaignId`, `GiftCount`, `DonorCount`, `ResponseRate`,
`TotalGiftTransactionAmount`, `AverageGiftAmount`, and one-time and recurring splits.

### 3.12 DonorGiftSummary

`npc_fundraising_api_objects_donorgiftsummary.htm`. Gift summaries for accounts and
contacts, populated by Data Processing Engine, not by trigger. `DonorId` (Master-Detail),
`TotalGiftsAmount`, `GiftCount`, `FirstGiftDate`, `FirstGiftAmount`, `FirstGiftCampaignId`,
`SecondGiftDate`, `LastGiftDate`, `LastGiftAmount`, `HighestGiftAmount`, `LowestGiftAmount`,
`AverageGiftAmount`, `BestGiftYear`, `HighestGiftYearAmount`, `GiftsThisYearAmount`,
`GiftsLastYearAmount`, `GiftsTwoYearsAgoAmount`, `CurrentYearGiftCount`, `LastYearGiftCount`,
`LastTwoYearGiftCount`, `DaysSinceLastGift`, `GivingLevel`, soft credit fields
(`SoftCreditCount`, `TotalHardSoftCredits`, `TotalHardSoftCreditsAmount`, and first, last
and highest soft credit date and amount) and recurring fields (`FirstRecurringStartDate`,
`CurrentRecurringStartDate`, `LastRecurringPaymentDate`, `TotalPaidRcrInstallments`,
`TotalPaidRcrInstlAmt`). Volunteer aggregates also appear in the Data Cloud mapping.

This object is the reason X-07 exists: it is what native donor pages, Agentforce actions
and actionable lists read.

## 4. Constituent objects

- **Person Accounts.** Agentforce Nonprofit represents individuals as person accounts.
  Prerequisite article:
  `https://help.salesforce.com/s/articleView?id=sfdo.NPC_Person_Accounts_and_Party_Relationship_Groups.htm`.
  This is why junction mode is first class for us (plan Sections 4.6 and 6.3).
- **PartyRelationshipGroup**
  (`https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/sforce_api_objects_partyrelationshipgroup.htm`;
  household data model at `psc_data_model_party_relationship_groups.htm`). A group of
  people living together or affiliated with each other; API version 56.0 and later.
  Fields: `AccountId`, `Name`, `Type`, `Subtype` (Picklist), `Category` (Picklist),
  `Status`, `StartDate`, `EndDate`, `GroupSize`, `GroupIncome`, `PrimaryAddress`,
  `Description`. Verified 2026-09-09 from the object reference page:
  - `AccountId` is **Master-Detail, Refers To Account** (the master object), and the page
    lists no Update property, so the group cannot be reparented after insert. Cascade
    delete is the platform rule for master-detail rather than a statement on that page
    (inferred): deleting the household Account deletes its `PartyRelationshipGroup`.
  - `Type` is a restricted picklist with exactly two values, `Group` and `Household`,
    defaulting to `Group`.
  - **The native indicator that an Account is a Nonprofit Cloud household is a
    `PartyRelationshipGroup` with `Type = 'Household'` pointing at it.** There is no field
    on Account.
  - `Name` is an ordinary writable string, `GroupSize` is writable rather than a rollup,
    and `PrimaryAddress` is a compound over individually writable fields. Nothing is
    derived from members, so **automatic household naming is not native** before
    Winter '27.
  - Winter '27 adds automatic household creation and naming as a **paid add-on**:
    Enterprise, Unlimited or Developer edition of Agentforce Nonprofit or Agentforce
    Education, plus the "Automatic Household Creation and Naming" add-on. Secondary
    sources only, no official page was read:
    `https://elevation.solutions/resources/salesforce-winter-27-release-nonprofit-education/`
    and `https://missioninmotion.com/blog/salesforce-nonprofit-cloud-winter-27-highlights`.
  - Licensing: `PartyRelationshipGroup` is an Industries common object and appears in the
    Public Sector, Automotive and OmniStudio guides as well as the Nonprofit Cloud guide,
    so it is **probably** not gated by the Fundraising license (probable, not confirmed).
    What is documented as gating it is the **Group Membership permission set**
    (`https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/group_membership_and_households_business_apis.htm`).
    Consequence for X-07: runtime detection must probe `PartyRelationshipGroup`
    separately from `GiftTransaction`, never infer one from the other.
- **Membership is `AccountContactRelation`. `PartyRelationshipGroupMember` does not
  exist.** Settled 2026-09-09: "Group Membership and Households Standard Objects"
  (`https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/group_membership_and_households_standard_objects.htm`)
  enumerates exactly five objects, `AccountAccountRelation`, `AccountContactRelation`,
  `ContactContactRelation`, `PartyRelationshipGroup` and `PartyRoleRelation`, and
  membership is carried on `AccountContactRelation`. Remove
  `PartyRelationshipGroupMember` as a candidate name wherever the plan still uses it.
  Household fields, with types and descriptions from
  `https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/sforce_api_objects_accountcontactrelation.htm`
  (verified):

  | Field | Type | Notes |
  |---|---|---|
  | `AccountId` | Lookup | The household (or business) account. |
  | `ContactId` | Lookup | The member. |
  | `IsIncludedInGroup` | Checkbox, default false | "Indicates whether the data of a group or a business account is included in the Household". |
  | `IsPrimaryGroup` | Checkbox, default false | |
  | `IsPrimaryMember` | Checkbox, default false | |
  | `Roles` | Multipicklist | Values in the Nonprofit Cloud guide: Daughter, Father, Husband, Mother, Other, Son, Wife. |
  | `DataRollupCategories` | Multipicklist | No documented values, configured per org. |
  | `IsDirect` | Checkbox, read only | System generated. Household relations are indirect, `IsDirect` false. |

  `IsActive`, `StartDate` and `EndDate` also apply, as on the base object.
- **Person accounts on `AccountContactRelation`.** The base object reference
  (`https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_accountcontactrelation.htm`)
  states that the object supports person accounts and that a person account can be a
  related contact on a business account. Salesforce Help "Create Groups and Relationships"
  (`https://help.salesforce.com/s/articleView?id=ind.group_membership_create_groups_relationships.htm`)
  describes adding a member by hand, choosing a contact or a person account. Membership is
  **not** created automatically: it is added by hand or through the Group Definitions API,
  whose request body keys members on `contactId`
  (`https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/connect_resources_group_definitions.htm`).
  Still unconfirmed: whether an `AccountContactRelation` row exists between a person
  account's own Contact and its own Account.
- **PartyRoleRelation**
  (`https://developer.salesforce.com/docs/atlas.en-us.psc_api.meta/psc_api/sforce_api_objects_partyrolerelation.htm`)
  models person-to-person relationships and is the analogue of the Relationship entity
  planned for v0.3.
- **ContactPointAddress.** Addresses hang off the party as contact points, not off Account
  address fields: `ParentId` (Lookup), `Name`, `Address` (compound; the Data Cloud mapping
  exposes `Street`, `City`, `State`, `PostalCode`, `Country`), `AddressType`, `UsageType`,
  `IsPrimary`, `IsDefault`, `IsThirdPartyAddress`, `PreferenceRank`, `ActiveFromDate`,
  `ActiveToDate`, best-time-to-contact fields, `ContactPointPhoneId`. Siblings:
  `ContactPointEmail`, `ContactPointPhone`, `ContactPointConsent`.
- **PersonLifeEvent.** `PrimaryPersonId`, `EventType`, `EventDate`, `ExpirationDate`,
  `IsExpired`. An import source for milestone data only; we have no canonical entity for it.

## 5. Program and volunteer models (summary only)

Program Management uses `Program` (`Name`, `Status`, `StartDateOnly`, `EndDateOnly`,
`Summary`, `ParentProgramId`, enrollee and disbursement counts), `ProgramEnrollment`
(`ProgramId`, `ContactId`, `AccountId`, `Status`, `StartDateOnly`, `EndDateOnly`,
`IsActive`, `IsAnonymous`), `ProgramCohort`, `ProgramCohortMember`, plus the Benefit
family (`Benefit`, `BenefitAssignment`, `BenefitDisbursement`, `BenefitSchedule`,
`BenefitSession`).

**Volunteer Management object API names could not be verified.** The data model page is
`volunteer_mgmt_volunteer_management_data_model.htm` and the lifecycle is described as
profiles, applications, positions, shifts and assignments, but no object API name was
confirmed. Do not write volunteer mappings from this file.

## 6. Mapping table 1: BarnCRM canonical entity to Nonprofit Cloud

Direction is BarnCRM to Nonprofit Cloud; the X-07 mirror is one way (plan Section 4.12).

| Canonical entity | Nonprofit Cloud target | Field mapping | Mismatch and loss |
|---|---|---|---|
| Gift (`Gift__c`) | `GiftTransaction` | Date to `TransactionDate`, amount to `OriginalAmount` and `CurrentAmount`, type to `GiftType`, payment method to `PaymentMethod`, status to `Status`, donor to `DonorId`, appeal to `OutreachSourceCodeId`, external ID to `PaymentIdentifier` | Picklist values differ and need a translation table. Our negative-amount refund gifts have no home: NPC models refunds as `GiftRefund` children plus `RefundedAmount`, so mirroring a refund gift as a transaction double counts. Receipt number and acknowledgment fields align only partly. |
| Allocation (`Gift_Allocation__c`) | `GiftTransactionDesignation` | Amount to `Amount`, percent to `Percent`, fund to `GiftDesignationId` | Clean. Master-detail means allocations are written after the transaction and deleted with it. |
| Fund (`Fund__c`) | `GiftDesignation` | Name to `Name`, description to `Description`, active to `IsActive` | Lossy: no accounting code and no restricted flag natively. The rollup fields on `GiftDesignation` are Data Processing Engine outputs and must not be written by us. |
| Commitment (`Commitment__c`) | `GiftCommitment` plus `GiftCommitmentSchedule` | Expected total to `ExpectedTotalCmtAmount`, start to `EffectiveStartDate`, end to `ExpectedEndDate`, status to `Status`; frequency and day to the schedule's `TransactionPeriod`, `TransactionInterval`, `TransactionDay`; amount to `TransactionAmount` | Our single `Type__c` (Pledge or Recurring) spreads across `RecurrenceType`, `ScheduleType`, `FulfillmentType` and `FormalCommitmentType`. Two native records per one of ours. |
| Installment (`Installment__c`) | No object. An expected `GiftTransaction` with `TransactionDueDate`, an unpaid `Status` and `GiftCommitmentScheduleId` | Structural mismatch: NPC has a recurrence rule, we have materialized rows. Mirroring installments creates transactions that native summaries may count as gifts. Recommended default: do not mirror unpaid installments. |
| Soft credit (`Soft_Credit__c`) | `GiftSoftCredit` | Contact or Account to `RecipientId`, role to `Role`, amount to `SoftCreditAmount`, percent to `PartialPercent` | Role picklist values differ; our custom roles have no native equivalent. |
| Tribute (`Tribute__c`) | `GiftTribute` | Type to `TributeType`, honoree contact to `HonoreeContactId`, honoree name to `HonoreeName`, recipient to `NotificationContactId`, sent flag to `NotificationStatus` | Ours is one record per gift; `GiftTribute` can hang off a transaction or a commitment. |
| Appeal (`Appeal__c`) | `OutreachSourceCode` (preferred) or `Campaign` | Name to `Name`, code to `SourceCode`, status to `Status`, parent appeal to `CampaignId` | Semantic mismatch: our Appeal is roughly Campaign plus source code. Goal, cost and dates have no source code fields. Flattening an appeal hierarchy onto Campaign plus source codes is lossy in either direction. |
| Household (Account, record type Household) | `Account` (business account) plus a `PartyRelationshipGroup` of type Household | Name to `Account.Name`; membership through `AccountContactRelation` | **Record type name collision.** Nonprofit Cloud ships no Household or Organization Account record type, but Nonprofit Cloud implementations very commonly create unprefixed ones by hand with exactly the DeveloperNames `Household` and `Organization`. Two independently retrieved real org metadata sets confirm it: ProvisioPartners/ESSCDevOps has `Household` and `Organization`; dnstommy/gearset-demo has `Household`, `Business_Account` and `Person_Accounts`. BarnCRM ships unprefixed Account record types named `Household` and `Organization` while its namespace is deliberately empty, so installing into an existing Nonprofit Cloud org is a real collision risk, and equally into an NPSP org. Enabling Person Accounts creates a standard record type whose DeveloperName is `PersonAccount`; no record type with DeveloperName exactly `Person` was found anywhere, so `Person` must not be treated as a real name. Separately: creating the household as a business account without the `PartyRelationshipGroup` leaves it invisible to native household features, and greetings and the custom-name flag have no native equivalent. |
| Household Member (`Household_Member__c`) | `AccountContactRelation` | Contact to `ContactId`, household to `AccountId`, role to `Roles`, dates to `StartDate` and `EndDate`, primary to `IsPrimaryMember`, plus `IsIncludedInGroup` and `IsPrimaryGroup` | Our junction can point at an Account (person account) as the person; `AccountContactRelation.ContactId` cannot, so person account members map through the person account's underlying contact. Verified 2026-09-09 that a person account can be a related contact on a business account and that these rows are indirect (`IsDirect` false); still unconfirmed whether a row exists between a person account's own Contact and its own Account. |
| Address (Core address entity) | `ContactPointAddress` | Street, city, state, postal code, country to the compound `Address`; type to `UsageType` or `AddressType`; primary flag to `IsPrimary` | Their model is one contact point per usage; ours is a shared address with propagation. Propagation semantics do not survive the mirror. |
| Household and fund rollups | `DonorGiftSummary`, `GiftDesignation` rollups | None | **Never write these.** They are Data Processing Engine outputs; writing them silently conflicts with the native nightly run. |

## 7. Mapping table 2: import template columns (C-14)

Two templates ship for Agentforce Nonprofit source data, both assuming a CSV export from a
Nonprofit Cloud org (report or Data Loader) imported into BarnCRM.

### 7.1 Template "Agentforce Nonprofit gifts"

| Source object and field | Canonical target | Matching rule |
|---|---|---|
| `GiftTransaction.Id` | `Gift__c` external ID | External ID exact; the update key for the row |
| `GiftTransaction.DonorId`, or `Account.Name` when exported | Gift donor (Account or Contact) | External ID on Account, else household or organization name plus postal code |
| `Account.PersonEmail` or `Contact.Email` | Gift donor Contact | Email exact, then name plus postal code |
| `GiftTransaction.TransactionDate` | `Gift__c` date | n/a |
| `GiftTransaction.OriginalAmount` | `Gift__c` amount | n/a |
| `GiftTransaction.CurrentAmount` | Not imported; used to flag rows where it differs from `OriginalAmount` | n/a |
| `GiftTransaction.GiftType` | `Gift__c` type | Value translation table; unmapped values rejected in the dry run |
| `GiftTransaction.PaymentMethod` | `Gift__c` payment method | Value translation table |
| `GiftTransaction.Status` | `Gift__c` status | Value translation table |
| `GiftTransaction.PaymentIdentifier` | `Gift__c` payment reference | n/a |
| `GiftTransaction.AcknowledgementStatus`, `.AcknowledgementDate` | `Gift__c` acknowledgment status and date | Value translation table |
| `GiftTransaction.OutreachSourceCodeId` or `OutreachSourceCode.Name` | `Appeal__c` | Appeal name exact; create if missing (setting) |
| `GiftTransaction.CampaignId` or `Campaign.Name` | Parent `Appeal__c` | Appeal name exact |
| `GiftTransaction.GiftCommitmentId` | `Commitment__c` | External ID exact |
| `GiftTransactionDesignation.GiftDesignationId` or `GiftDesignation.Name` | `Gift_Allocation__c` fund | Fund name exact; create if missing (setting) |
| `GiftTransactionDesignation.Amount` or `.Percent` | `Gift_Allocation__c` amount or percent | Must total the gift amount or 100 percent |
| `GiftSoftCredit.RecipientId`, `.Role`, `.SoftCreditAmount` | `Soft_Credit__c` | Recipient by external ID, then email |
| `GiftTribute.TributeType`, `.HonoreeName`, `.NotificationContactId` | `Tribute__c` | Honoree by external ID, then name |
| `GiftRefund.Amount`, `.Date`, `.Reason` | A second `Gift__c` with negative amount linked to the original | Original by external ID |

A second variant maps a `GiftEntry` export instead: one `GiftEntry` row already carries
donor name and address, the gift and three designations, matching our row semantics
(plan Section 4.9) almost exactly.

### 7.2 Template "Agentforce Nonprofit constituents"

| Source object and field | Canonical target | Matching rule |
|---|---|---|
| `Account.Id` (person account) | Contact external ID | External ID exact |
| `Account.FirstName`, `.LastName`, `.Salutation` | Contact first name, last name, salutation | Email exact, then first plus last name plus postal code |
| `Account.PersonEmail`, `.PersonMobilePhone` | Contact email and phone | n/a |
| `Account.Id` (business account) | Household Account external ID | External ID exact, then household name plus postal code |
| `PartyRelationshipGroup.Name`, `.Type`, `.StartDate`, `.EndDate` | Household name and dates; a type other than Household imports as an organization or is skipped | Household name exact |
| `AccountContactRelation.AccountId` and `.ContactId` | `Household_Member__c.Account__c` and `.Contact__c` | Both resolved by external ID |
| `AccountContactRelation.Roles` | `Household_Member__c.Role__c` | Value translation table (Head, Spouse or Partner, Child, Other) |
| `AccountContactRelation.StartDate`, `.EndDate` | `Household_Member__c.Start_Date__c`, `.End_Date__c` | n/a |
| `AccountContactRelation.IsPrimaryMember` | `Household_Member__c.Is_Primary__c` | At most one per household; conflicts reported in the dry run |
| `AccountContactRelation.IsIncludedInGroup` | Row filter: false excludes the member from naming and greetings | n/a |
| `ContactPointAddress.Street`, `.City`, `.State`, `.PostalCode`, `.Country`, `.UsageType`, `.IsPrimary` | Address entity fields | Parent by external ID; one primary address per party |
| Person account deceased indicator | `Contact.Deceased__c` | **No native deceased indicator could be found.** One real Nonprofit Cloud customer org (ProvisioPartners/ESSCDevOps) built its own unprefixed `Deceased__c` checkbox on Account. Do not assume a `DeceasedDate` field: that name appears only in a Data Cloud mapping file that suffixes standard field names with `__c` as a naming artefact, and it could not be confirmed on Contact. Open question; describe Account and Contact in a real org before shipping. |
| `PersonLifeEvent.EventType`, `.EventDate` | Not imported in v0.2 | n/a |

## 8. Coexistence risks

1. **Native rollups never see our gifts.** `DonorGiftSummary`, the `GiftDesignation`
   rollup fields and `OutreachSummary` are produced by Data Processing Engine definitions
   that read `GiftTransaction`, `GiftSoftCredit` and `GiftCommitment`. A gift that lives
   only in `Gift__c` is invisible to donor pages, giving levels, `DaysSinceLastGift` and
   every native fundraising dashboard. This is the whole justification for X-07.
2. **They are batch, we are not.** Data Processing Engine runs on a schedule the admin
   builds; the shipped template definitions do nothing until cloned, activated and
   scheduled. Even with the mirror on, native summaries lag ours. The Settings console
   must say so, and Health Check should warn when no schedule exists.
3. **Actionable Segmentation and Agentforce actions read native objects.** Actionable
   lists are built from Data Processing Engine datasets over `GiftTransaction` and
   `DonorGiftSummary`. Unmirrored gifts silently drop out of segments, producing wrong
   mailing lists rather than a visible error.
4. **Double counting.** If the org also runs a payment processor integration that writes
   `GiftTransaction` directly (several do), our mirror plus that integration create two
   transactions for one gift. Exactly one direction per org, an external ID key on the
   mirrored record and a reconciliation report are required (plan Section 4.12).
5. **Refunds and write-offs.** We record a refund as a new negative gift; they use
   `GiftRefund` plus `RefundedAmount`, `IsFullyRefunded` and `IsWrittenOff`. A naive
   mirror overstates giving, so translate or refuse to mirror refunds and say so plainly.
6. **Installments.** Mirroring unpaid `Installment__c` rows as future-dated
   `GiftTransaction` records risks native summaries counting expected money as received.
   Default off.
7. **Person Accounts in junction mode, and deleting a household Account.** With Person
   Accounts enabled a person is an Account. Our `Household_Member__c` points at the person
   through `Account__c`, while native membership uses `AccountContactRelation.ContactId`.
   A person account has an underlying contact, so the two can be kept in step: verified
   2026-09-09 that `AccountContactRelation` supports person accounts, that a person
   account can be a related contact on a business account, that household rows are
   indirect (`IsDirect` false), and that membership is never created automatically (added
   by hand or through the Group Definitions API, which keys members on `contactId`).
   Creating our own household Account for a person who already sits in a
   `PartyRelationshipGroup` still produces two competing households. **Deletion is worse
   than previously stated:** `PartyRelationshipGroup.AccountId` is master-detail to
   Account with no Update property, so deleting an empty household Account (rule R-H12) in
   an org running Nonprofit Cloud does not orphan the group, it destroys it (cascade
   delete inferred from the platform master-detail rule). R-H12 must check for a child
   `PartyRelationshipGroup` before deleting. Still unverified: whether an
   `AccountContactRelation` row exists between a person account's own Contact and its own
   Account.
8. **Writing native rollup fields is a data-integrity bug.** X-07 writes transaction-level
   objects only, never `DonorGiftSummary` or the `GiftDesignation` aggregates.
9. **Licensing.** Without the Fundraising Access license or the Fundraising User
   permission there is no `GiftTransaction` at all. X-07 must degrade silently rather than
   error, and Core never references these objects (`scripts/ci/check-standard-objects.sh`).

## 9. Follow-ups before X-07 and C-14 are built

1. Describe every object in Sections 3 and 4 in a Nonprofit Cloud org; correct types,
   required flags, `referenceTo` and picklist values here.
2. **Household follow-up, largely closed 2026-09-09.** Closed by the official sources
   cited in Section 4: `PartyRelationshipGroupMember` does not exist and membership is
   `AccountContactRelation`; the household field types and picklist values on
   `AccountContactRelation`; `AccountId` as a non-reparentable master-detail and its
   delete consequence (Section 8 item 7); `PartyRelationshipGroup.Type` as the only native
   household indicator; the absence of native household naming before the Winter '27 paid
   add-on; and person account support on `AccountContactRelation`. Still open, as concrete
   queries to run against a real Nonprofit Cloud org:
   - `SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = 'Account'` in a
     **freshly provisioned, untouched** Nonprofit Cloud org. This is the decisive test for
     whether `Household` is a shipped record type DeveloperName or a hand built
     convention, and so for the size of the Section 6 collision risk.
   - Describe `PartyRelationshipGroup` in an org **without** the Fundraising User
     permission, to settle whether it is license gated or only Group Membership permission
     set gated.
   - Query `AccountContactRelation` for a person account: does a row exist between the
     person account's own Contact and its own Account, and what are `IsDirect` and `Roles`
     on household rows created through the Group Definitions API?
   - Describe Account and Contact for a deceased indicator. None is native as far as could
     be found, and `DeceasedDate` must not be recorded as a field name (Section 7.2).
3. Get the Volunteer Management object API names from the official data model page.
4. Record the picklist translation tables (gift type, payment method, status, tribute
   type, soft credit role) as custom metadata, not as code.

## 10. Detection in Core, added 2026-09-15

Core can now tell whether an org already models households the Nonprofit Cloud way. This is
detection only. Nothing acts on the answer yet: the guards that use it, and the migration,
are later work.

`OrgShapeDetector.OrgShape` carries two more fields, both `@AuraEnabled` so Health Check can
show them:

- `hasNativeHouseholdGroups` (Boolean)
- `nativeHouseholdGroupCount` (Integer, null when the count could not be made)

The probe lives in `OrgShapeSelector.nativeHouseholdGroupCount`. It looks
`PartyRelationshipGroup` up in the global describe, checks `isAccessible`, and runs
`SELECT COUNT() FROM PartyRelationshipGroup WHERE Type = 'Household'` through
`Database.countQuery`. The object name and the whole query text are String constants carrying
the `// detection-only:` marker `scripts/ci/check-standard-objects.sh` honors, so Core still
compiles and deploys on a Platform-only org (ADR-0009, ADR-0013). The count is part of the
cached org shape, so it is asked once per transaction.

It is probed on its own and never inferred from `GiftTransaction`, for the reason recorded in
Section 4: the household group is an Industries common object and the Fundraising licence
does not gate it, so an org can have native households without having any fundraising object
at all.

**Unknown is treated as yes.** Any outcome other than a count that actually came back leaves
`nativeHouseholdGroupCount` null and `hasNativeHouseholdGroups` true: the object missing from
the describe, the object not accessible to the running user, or the query throwing. Only a
count that ran and returned zero answers no. The asymmetry is the one ADR-0036 argues for the
delete guard. A false negative would let a later guard silently open, rename or tidy up a
household the customer built in Nonprofit Cloud and BarnCRM does not own. A false positive
only makes that guard cautious about an org that had nothing to protect. `getGlobalDescribe`
is itself filtered by the running user's permission set licences, and the group is gated by
the Group Membership permission set, so "not in the describe map" really is an ambiguous
answer rather than a clean no.

This is a question about the org. The per-record question, whether one particular Account
carries a native household group, stays where it already was, in
`HouseholdSelector.getAccountsWithNativeDependents` under ADR-0036, and is not duplicated.

Still unverified, and inherited from Section 9: the query text itself has never run against a
real Nonprofit Cloud org. Run it before anything is built on the answer.
