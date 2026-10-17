# Canonical Data Model

**Version:** v0.3
**Status:** governing specification for the v0.1, v0.2, and v0.3 builds
**Last updated:** 2026-09-25

## 1. Purpose

This document is the platform-neutral specification of the BarnCRM data model. It
defines entities, attributes, relationships, and business rules in ordinary language,
independent of Salesforce. Each entity then cites the Salesforce metadata that
implements it.

It exists for three reasons (plan Section 4.4):

1. It keeps a far-future non-Salesforce runtime possible at near-zero cost today.
2. It is the best documentation a contributor or an AI agent can be given: one file that
   explains the whole shape of the data without reading the code.
3. It forces every schema addition through a moment of definition.

## 2. Rules

1. **No field is added to a Salesforce object that is not first added here with a
   one-line definition.** This is the first checkbox in the definition of done (plan
   Section 7.4). The canonical-model commit comes before the metadata commit.
2. The same rule covers picklist values, custom settings keys, and custom metadata
   fields, not only custom object fields.
3. Where this document and a Salesforce platform constraint disagree, the platform wins
   and the deviation is recorded as an ADR in `decisions/` with the workaround (plan
   Section 9.3).
4. Attribute names here are human names. Salesforce API names appear only in the
   implementation subsection of each entity.
5. Labels use plain language, not Salesforce language, and Core's labels are neutral: no
   Core label, help text, option, message or seeded record says "nonprofit" or uses
   nonprofit-only vocabulary (gift, donor, donation, grant, fundraising, receipt, pledge,
   appeal), because Core alone is the Standard Edition. The exceptions are text shown only
   when Giving (or another module) is installed; the names of Salesforce products (NPSP,
   Nonprofit Cloud, Gift Transaction) shown only when Core detects that product in the org;
   import column aliases that only match file headers; and the Nonprofit Edition choice
   (C-30). Giving's labels use giving language: "Gift" not "Donation Transaction," "Fund"
   not "General Accounting Unit" (plan Section 7.1). See ADR-0062
   (`decisions/0062-core-names-other-products-only-when-detected.md`), which amends ADR-0059
   decision 5.

## 3. Versioning

This is **v0.3**. It covers three iterations, and each part says which one owns it:

- **Part A and Part B** are v0.1: the constituent entities and the platform configuration
  entities that the v0.1 features require.
- **Part C** is v0.2 in Core: the rollup engine's configuration and the import framework.
- **Part D** is the Giving package, v0.2 for gifts, allocations, funds, and appeals, and
  v0.3 for commitments, installments, soft credits, and tributes.
- **Part E** is v0.3 in Core: relationships, affiliations, and addresses.

Later iterations extend it. Section 30 lists what is deliberately absent and when it
arrives, so no one adds it early, and Section 32 says which package owns each entity.

## 4. Conventions

- **Entity names** are singular PascalCase with spaces where natural: `Household`,
  `Household Member`, `Contact`, `Organization`.
- **Attribute types** are platform-neutral:
  `text`, `long text`, `boolean`, `integer`, `decimal`, `date`, `datetime`,
  `picklist(value, value, ...)`, `reference(Entity)`.
- **Required** means required by our business rules, not necessarily enforced by a
  platform-level required flag. Where a rule is conditional the definition says so.
- **Computed** attributes are marked in the Required column as `computed`. Their inputs
  and formulas are documented in the entity's rules section.
- Every attribute has a one-line definition, written so an admin recognizes their data.
- Every entity cites its **Salesforce implementation**: object, record type, and field
  API names. No namespace prefix appears anywhere (plan Section 4.3).

### Person references

Every attribute that points at a person carries **a pair of references, and exactly one of
them is set**: a Contact reference for orgs where people are Contacts, and an Account
reference for orgs where people are person Accounts. Both are always defined, because the
same package runs in both kinds of org and no feature code branches on which is in use
(ADR-0005).

The pair is named the same way everywhere:

| Entity | Contact side | Account side |
|---|---|---|
| Gift, Commitment | Donor Contact | Donor Account |
| Soft Credit | Contact | Account |
| Relationship | Contact, Related Contact | Person Account, Related Person Account |
| Affiliation | Contact | Person Account |
| Address (personal owner) | Contact | Person Account |
| Tribute | Honoree Contact, Notification Recipient Contact | Honoree Account, Notification Recipient Account |
| Import Row | Contact 1, Contact 2 | Person 1 Account, Person 2 Account |
| Household Member | Contact | Account |
| Volunteer Sign-up, Volunteer Hours | Contact | Account |
| Volunteer Skill, Volunteer Requirement | Contact | Account |

**No packaged metadata references a Person Account field** (plan Section 4.2 and
ADR-0009). The Account side is a plain lookup to Account. Whether a given account is a
person, and any name data held on it, is read dynamically at run time through
`HouseholdService`, so the package installs and behaves correctly in an org where Person
Accounts are not enabled.

Because a person can be an Account, the person attributes that v0.1 defined on Contact
(Deceased, Household Role, Exclude From Household Name, Exclude From Greetings, Preferred
Name) exist on Account as well. The Account copies are specified in Sections 5 and 7 with
the rest of the v0.1 model.

---

# Part A: Constituent entities

These are the four entities the v0.1 iteration builds (plan Section 9.1 step 4).

## 5. Household

### Definition

The unit of relationship and recognition for individual donors: one mailing address, one
greeting, one giving history (plan Section 13). A household groups the people a
nonprofit treats as a single donor for acknowledgment and reporting purposes. It is not
a legal entity and it does not imply a shared residence in every case, though it usually
does.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The household's display name, for example "The Smith Family"; recomputed from members unless Custom Name is set. |
| Formal Greeting | text | computed | The salutation used on formal correspondence, for example "Mr. and Mrs. John Smith". |
| Informal Greeting | text | computed | The salutation used on personal correspondence, for example "John and Jane". |
| Custom Name | boolean | yes (defaults false) | When true, Name, Formal Greeting, and Informal Greeting are never recomputed; the staff member's wording stands. |
| Primary Contact | reference(Contact) | no | The household member who receives correspondence when only one person can be named. In junction mode it mirrors the primary member (R-M3), and a person stored as a Person Account is named by their person contact. |
| Member Count | integer | computed | The number of current (not ended, not deceased-excluded) members of the household. |
| Anniversary | date | no | A household-level date the organization keeps, most often a wedding anniversary. |
| Record Type | picklist(Household, Organization) | yes | Distinguishes a household from an organization; a Household always carries Household. |
| Sample Data | boolean | yes (defaults false) | True when the record was created by the sample data loader so it can be removed in one action. |

### Relationships

- **Household to Contact**, one to many, through membership. The mechanism depends on
  the membership mode (see rules below) and is never referenced directly by callers.
- **Household to Household Member**, one to many, in junction mode only.
- Household is the target of the giving rollups defined from v0.2 onward. Those rollup
  target fields belong to the Giving package and are listed in Section 26, not here.
- **Household to Address**, one to many, from v0.3 (Section 29).

### Rules

Drawn from plan Section 4.6 and the acceptance criteria in Section 10.2.

**R-H1 Automatic creation in contact mode.** In contact mode, inserting a Contact with
no Account creates a Household Account named per the naming rules, in the same
transaction, and attaches the Contact to it. This is controlled by the
`Auto_Create_Households__c` setting, default on. Bulk safety is required: 200 Contacts
inserted in one DML operation create their households without exceeding platform limits.
The person a household is created for is named its Primary Contact (R-H10), as junction
mode marks them the primary member.

**R-H2 Automatic creation in junction mode.** In junction mode, saving a new person who
belongs to no household creates a Household Account named per the naming rules and a
Household Member record joining them to it, with the role Head and the primary flag set.
The same `Auto_Create_Households__c` setting governs it, so one switch answers "does a new
person get a household" in both membership modes. The person may be stored as a Contact
or, in an org shaped that way, as a person record on Account: both take this path. A
person a Household Member record already joins to a household is left alone. Bulk safety
is required here too: 200 people inserted in one DML operation get their households and
their membership records without exceeding platform limits.

A Contact inserted in junction mode with its Account set to a household joins that
household: one Household Member record is created for it, as an ordinary member, and
automatic creation then leaves it alone. An Account that is an organization (an employer,
in this mode) or a native Nonprofit Cloud household gets no membership record.

This rule previously said that a person stored as an account got no household unless a
second setting asked for it. ADR-0037 retires that setting and records why.

**R-H3 Membership modes.** Membership has two modes, and both sit behind a single Apex
service so that no other code knows which is in use:

- *Contact mode* (default): the Contact's Account reference points at the Household.
  Simple, reportable, NPSP-compatible, and compatible with every AppExchange app that
  assumes a Contact belongs to an Account.
- *Junction mode* (required when Person Accounts are enabled, optional otherwise): a
  Household Member record joins a person to a household. This allows one person in more
  than one household (divorced parents, students) and preserves membership history.

The mode is an org-level setting (`Household_Membership_Mode__c`). Callers use
`HouseholdService`; direct reads of the membership mechanism outside that service are a
review failure.

**R-H4 Naming and greetings computation.** Name, Formal Greeting, and Informal Greeting
are computed from the household's members. Inputs:

- Each member's first name, preferred name (used in place of first name when present),
  last name, and salutation.
- Each member's Household Role, used for ordering.
- Each member's Deceased flag, Exclude From Household Name flag, and Exclude From
  Greetings flag.
- The org's configured patterns: `Household_Name_Pattern__c`,
  `Formal_Greeting_Pattern__c`, `Informal_Greeting_Pattern__c`.
- The org's `Include_Deceased_In_Name__c` setting.

Default patterns (plan Section 4.6 and 10.2):

| Case | Name | Formal Greeting | Informal Greeting |
|---|---|---|---|
| Members share a surname | "The Smith Family" | "Mr. and Mrs. John Smith" | "John and Jane" |
| Members have differing surnames | "Smith and Jones Household" | Both members listed with their own salutations and surnames | Both first names |
| One member | "The Smith Family" | "Mr. John Smith" | "John" |

Each value fits its field, whose length is read from the describe (255 for all three). A list
too long for it names as many leading members (or surnames) as fit and counts the rest, through
the org-language labels `Core_Households_ListAndOthers` and `Core_Households_ListAndOneOther`:
"Garcia, Lee and 28 others Household". A single value still too long is cut back to
its last whole word. The household is saved either way; before this, a household of about 30
was refused, leaving its name, greetings and member count stale.

**R-H5 Member ordering.** Members are ordered by Household Role (Head first, then Spouse
or Partner, then Child, then Other, then no role). Within a role the primary member comes
first, then the earliest created member, then first name, so that a household's name and
greetings are stable across recomputations. The primary is read from the source of truth
for the membership mode: the household's Primary Contact in contact mode, the Is Primary
flag on the membership rows in junction mode (R-M3). The mirrored Primary Contact is never
read back into the ordering in junction mode.

**R-H6 Hyphenated and differing surnames.** A hyphenated surname is treated as one
surname and is never split. Two members are treated as sharing a surname only on an
exact match; otherwise the differing-surname pattern applies.

**R-H7 Deceased handling.** A member marked deceased is excluded from greetings. Whether
they remain in the household name is controlled by `Include_Deceased_In_Name__c`. When
the org chooses to keep a deceased member in formal correspondence, the formal greeting
offers a "the late" form, for example "Mrs. Jane Smith and the late Mr. John Smith".

**R-H8 Custom name override.** When Custom Name is true, no automatic recomputation
changes Name, Formal Greeting, or Informal Greeting. This is the mechanism that keeps
"The Reverend and Mrs. Smith" as staff typed it.

**R-H9 Exclusions.** Exclude From Household Name removes a member from the name
computation only; Exclude From Greetings removes them from both greetings only. The two
flags are independent.

**R-H10 Primary contact.** A household has at most one primary contact, and that contact
must be a current member of the household. When the primary contact leaves the
household, the reference is cleared and the next member by ordering is proposed, not
silently assigned. In contact mode that is the Primary Contact field itself; in junction
mode it is the membership marked Is Primary, which Primary Contact mirrors (R-M3). In
contact mode, setting or changing Primary Contact to a Contact whose Account is not that
household is refused before save; clearing it, or saving a household whose primary has
since left, is never refused.

**R-H11 Member count.** Member Count is recomputed on every membership change (insert,
update, delete, undelete, reparent, merge) and counts current members only. The field
carries no default value: it is written by household upkeep and only ever onto a household,
so an organization, which upkeep skips by record type, is left with an empty Member Count
rather than a count of zero it never earned.

Upkeep reads every member in system mode (ADR-0021), whichever object holds the person, so
the count does not depend on the packaged access of whoever happened to save the record.
A current member whose own record the upkeep read did not return is still counted, and is
still moved by a merge or a split, because a household quietly recounted smaller is how a
household gets renamed, emptied under R-H12, and its members lost. Such a member
contributes nothing to the household name or the greetings, because there is no name to
contribute. What a screen shows is read separately, with the running user's own access, and
a member that read cannot return is not shown.

This holds whichever object the person is stored on. Where people are person accounts, a
change to the person is a membership change on the same terms as a change to a contact:
deleting the person, restoring them from the recycle bin, and changing any of the
attributes R-H4 builds the wording from (first name, surname, salutation, preferred name,
deceased, household role, and the two exclusion flags) all recount and rewrite every
household that person belongs to. The delete side of that cannot be done after the fact:
see the note under R-M4 on what the platform does to a membership row when the person it
names is deleted.

**R-H12 Reparenting and empty households.** Moving a contact to a different household
recalculates both households' member counts and, once Giving is installed, their giving
rollups. The vacated household is deleted when it is empty, `Delete_Empty_Households__c`
is on, nothing outside BarnCRM depends on the account (ADR-0036), and no installed module
still credits records to it (ADR-0070,
`0070-empty-household-tidy-up-keeps-households-with-gifts.md`). A module reports its
credited records through the Core extension point `HouseholdDependentsExtension`, found by
class name the way Health Check finds its extensions; Giving reports every household that
a Gift or a Commitment names in its Household field, because those lookups clear on delete
and a gift keeps the household it was given to (R-G2). Such a household is kept without an
Error Log entry: keeping a donor's past household is the ordinary outcome of a move, not
something an administrator has to act on. "Empty" is
measured in BarnCRM's own membership, which is the only membership BarnCRM can
see, so a household that also carries a Salesforce Nonprofit Cloud household group or its
membership rows reads as empty here while being anything but. The account is the master of
that group, so deleting the account would destroy it rather than orphan it. A household
left in place for that reason is reported to the Error Log at Info severity, naming the
household: it is a correct outcome, not a failure.

Deleting people never deletes their household at the time; moving them still tidies it as above. Deleting
a household purges from the Recycle Bin the contacts and membership rows already deleted from
it, so neither an undelete nor the bulk delete undo (R-BD5) could bring the people back.

**R-H12a Households emptied by deleting people.** A delete that leaves a household with no
members stamps the household's `Emptied_By_Deletion__c` with the day; a merge does not stamp
(R-H13), and any later settle that finds the household with a member clears the stamp. The
nightly empty household tidy-up (`EmptyHouseholdTidyScheduler`, ADR-0120) moves a stamped
household to the Recycle Bin, never a hard delete, once all of these hold, read in system mode
and in every membership mode:

- it has no Contact whose Account is the household and no Household Member row, current or
  ended, naming it and a person who still exists (an erased person is anonymized in place, not
  deleted, so their ended row keeps it); a row whose person was deleted names nobody and goes
  with the household;
- no Contact whose Account was the household and no Household Member row naming it is still
  in the Recycle Bin (`ALL ROWS`, `IsDeleted = true`): those are exactly the records deleting
  the household would purge, so its former members can no longer be restored either way;
- nothing outside BarnCRM depends on it (ADR-0036), no installed module credits records to it
  (`HouseholdDependentsExtension`, ADR-0070), and no other record of any object points at it
  through any child relationship of Account (read by describe, so Core names no module object).
  Shares, field history, feed records and big objects are bookkeeping and do not count. Nor do
  Core's own records of the household, identified by field: its addresses
  (`Address__c.Account__c`), which go to the Recycle Bin with it in the same transaction (the
  platform clears their lookup when the household follows, so restoring both re-links by hand),
  and the import rows that created it (`Import_Row__c.Household__c`, an audit
  record whose lookup clears). An unreadable relationship is logged by name and keeps that
  chunk's households.

A household that fails the last rule is kept and stays on the Health Check and Data Hygiene
lists of households without members, which is where an administrator reviews it. A household
whose former members are still in the Recycle Bin is kept quietly and looked at again each
night. A relationship that cannot be read keeps every household in that run. The tidy-up is on
unless `Keep_Households_Of_Deleted_People__c` is set, and it is independent of
`Delete_Empty_Households__c`, which governs moves only. A household emptied before the stamp
existed carries no stamp and is not tidied. Counts go to the debug log; a refused delete goes
to the Error Log.

**R-H13 Merge and split.** Two households can be merged (members move to the surviving
household, rollups recalculate, names and greetings recompute unless Custom Name is set)
and a contact can be split out to a new or existing household. Both are front-end
actions on the record page, not Setup operations.

Two households only: an organization is never a merge target, and the two records must
be different. A merge moves membership first, in whichever membership mode is active,
then applies the field values a person chose, then uses the platform's own account merge
so that activities, files, notes, and every lookup from another entity follow the record
that goes away. A merge is not reversible and is audited by the platform's own record
history rather than by a log this model defines. Membership changes made by a merge or a
split settle through one hook (member count and naming in v0.1, giving rollups from v0.2)
so that no caller has to know what settling involves. That settle-up never tidies the
surviving household away: the empty household rule (R-H12) is about the household somebody
was the last to leave, and the survivor of a merge is the record the merge exists to keep,
so two empty households merge into one empty household rather than into nothing.

**R-H14 Recompute action.** Changing a naming pattern in the settings console shows a
preview against five fixed sample households, computed in memory from the patterns being
typed: nothing is read from or written to the org's own households. The console also
offers a "Recompute all households" batch. Starting it confirms that the batch has been
queued; the batch runs in the background and reports neither progress nor completion to
the console, and its counts are written to the debug log only. Recomputation never touches
households with Custom Name set.

### Salesforce implementation

- **Object:** Account, record type `Household`. Organizations use record type
  `Organization`. Both record types ship with compact layouts and share one Lightning
  record page built with Dynamic Forms and one fallback page layout (ADR-0043).
- **Standard fields used:** `Name` (the computed household name).
- **Custom fields on Account:**

| Attribute | API name | Type |
|---|---|---|
| Formal Greeting | `Household_Formal_Greeting__c` | Text |
| Informal Greeting | `Household_Informal_Greeting__c` | Text |
| Custom Name | `Custom_Name__c` | Checkbox |
| Primary Contact | `Primary_Contact__c` | Lookup to Contact |
| Member Count | `Member_Count__c` | Number |
| Anniversary | `Anniversary__c` | Date |
| Sample Data | `Sample_Data__c` | Checkbox |
| Sample Data Key | `Sample_Data_Key__c` | Text(20) (v0.4) |
| Emptied By Deletion | `Emptied_By_Deletion__c` | Date (R-H12a) |

- **Person attributes on Account.** The five person attributes listed under Contact
  (Section 7) are present on Account as well, with the same API names and the same
  definitions: `Deceased__c`, `Household_Role__c`, `Exclude_From_Household_Name__c`,
  `Exclude_From_Greetings__c`, `Preferred_Name__c`. They belong to the person, not to the
  household, and they exist on both objects so that an org that stores people as accounts
  carries them on the person's own record. They are not shown on Household or Organization
  layouts.

- **Service:** `HouseholdService` (membership abstraction), `HouseholdNamingService`
  (R-H4 to R-H9), `HouseholdSelector` (all SOQL).

---

## 6. Household Member

### Definition

A person's membership in a household over a period of time. Used only in junction mode.
It is what allows one person to belong to more than one household and what preserves the
history of who was in a household when.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Contact | reference(Contact) | conditional | The person, when the person is represented as a Contact. |
| Account | reference(Account) | conditional | The person's own account, where the person is represented as an account rather than as a Contact (a Person Account). Never a household: the household side is the Household attribute below. |
| Household | reference(Household) | yes | The household the person belongs to. |
| Role | picklist(Head, Spouse or Partner, Child, Other) | no | The person's role in this household, used for greeting order and reporting. |
| Is Primary | boolean | yes (defaults false) | Marks the member who receives correspondence when only one person can be named. |
| Start Date | date | no | The date the person joined the household. |
| End Date | date | no | The date the person left the household; empty means current. |

### Relationships

- **Household Member to Contact**, many to one.
- **Household Member to Household**, many to one.
- Together these form the many-to-many join between people and households.

### Rules

**R-M1 Mode gating.** Household Member records exist only in junction mode. In contact
mode the object is present in the org (it ships with the package) but carries no records
and no automation writes to it.

**R-M2 Current membership.** A member is current when End Date is empty or in the
future. Only current members count toward Member Count, naming, and greetings.

**R-M3 One primary.** At most one current member of a household has Is Primary true, and
the primary member is mirrored to the household's Primary Contact (ADR-0044, primary
contact mirrors the primary member).

- The mirror is the member's Contact where the person is a Contact, and the person
  account's own person contact where the person is a Person Account. A Contact lookup on
  Account accepts a person contact (verified in a person accounts org on 2026-09-23). The
  person contact is read only through dynamic Apex and only where the org has Person
  Accounts, so the model keeps no dependency on them.
- With no current primary member, Primary Contact is empty (R-H10).
- A save of one Household Member record, made by a person, that would make it a second
  current primary member of its household is refused before the save (label
  `Core_Households_ErrorSecondPrimary`), pointing to Make primary. A save of more than one
  record, or one arriving through the APIs, the Bulk API or background Apex, is a load and
  is not refused (ADR-0108, `0108-a-second-primary-is-refused-on-a-single-save.md`): with
  more than one current primary, the first of them in R-H5 order is mirrored and no
  membership row is changed.
- `HouseholdService` is the only writer in junction mode. It settles the mirror on every
  membership change (a row added, changed, ended, removed or restored, a person deleted or
  restored, a move, a merge, a split), before the household is renamed. Setting or changing
  Primary Contact on a household by hand in junction mode is refused, with a message that
  points to Make primary on the members panel. An organization is never affected (R-O3).
- A merge in junction mode does not offer Primary Contact as a choice: the survivor keeps
  its primary member, and the other household's primary member keeps the flag only when the
  survivor has none.
- A membership whose End Date is in the future stops being current on that date with no
  save to react to; the mirror follows at that household's next membership change, as
  Member Count does (R-H11).
- **A person's household** in junction mode, wherever one household has to be named for a
  person (rollups to the person's household, imports, addresses, donation matching),
  is the household of their current primary membership, and with none, of their earliest
  current membership: earliest Start Date, a membership with no Start Date counting as
  earliest, then the row created first. Where a person is primary in more than one, the
  earliest of those is the answer. A person with any current membership always has one.

**R-M4 Person representation.** Exactly one of Contact or Account identifies the person:
Contact where the person is a Contact, the person's own Person Account where Person
Accounts are enabled. Both empty, or both pointing at people, is invalid.

Deleting the person record is where "both empty" would otherwise come from. Both person
lookups clear themselves when the record they point at is deleted, which leaves a row that
identifies nobody, and the platform does not fill the lookup in again when the person is
restored from the recycle bin. So a membership row is removed with the person it names,
before the deletion empties it, and brought back when that person is: membership follows
the person, current rows and ended ones alike. Membership history therefore survives
everything except the deletion of the household it is history of and the deletion of the
person it is history of. Rules R-M2 and R-H11 already ignore a row that identifies nobody,
so a row orphaned before this was so, or by a deletion made with the automation switched
off, is counted by nothing and named in nothing; it is simply left.

The validation rule `Membership_Names_One_Person` enforces this on every save that creates
a row or changes who it names, whoever makes it. It does not fire on other edits, so a row
the platform emptied can still be ended or corrected.

**R-M5 No direct callers.** All reads and writes go through `HouseholdService`. Feature
code never branches on membership mode.

**R-M6 One current membership per person per household.** A person has at most one
current membership (R-M2) in a given household; ended ones beside it are history and are
kept. A save that would make a second one (a new current row, or an edit that changes the
person or the household on a row, or brings an ended row back) is refused before it is
written, so a hand-made or loaded row cannot count one person twice. The check runs in the
Household Member trigger, reads in system mode (ADR-0021), and is stood down with that
trigger's automation; `HouseholdService` already never writes a second one. An edit that
does none of those things is let through, so a duplicate left by a platform merge, which
fires no trigger, can still be ended.

### Salesforce implementation

- **Object:** `Household_Member__c` (junction).
- **Fields:** `Contact__c` (Lookup to Contact), `Account__c` (Lookup to Account),
  `Household__c` (Lookup to Account), `Role__c` (Picklist: Head, Spouse or Partner, Child,
  Other), `Is_Primary__c` (Checkbox), `Start_Date__c` (Date), `End_Date__c` (Date).
- `Household__c` is the household side of the junction and `Contact__c` or `Account__c` is
  the person side. `Household__c` is a required lookup with a cascade delete, matching the
  attribute table above: a membership row with no household says nothing, and a household
  that is deleted takes its own membership rows with it rather than leaving rows pointing at
  a record that is gone. Membership history survives everything except the deletion of the
  household it is history of.
- A lookup rather than a master-detail relationship is used so that membership rows are not
  owned by the household record for sharing and roll-up purposes, and so that the same
  object shape works in both membership modes.

---

## 7. Contact

### Definition

A person the organization knows: a member, a household member, a volunteer, a program
participant, a board member, a donor (with Giving), or a staff contact at an organization.
The Contact is the person; the Household is how the organization addresses and credits them.

### Attributes

Only the attributes v0.1 adds or relies on are listed. Standard name, email, phone, and
address fields are used as the platform provides them.

| Attribute | Type | Required | Definition |
|---|---|---|---|
| First Name | text | no | The person's given name as recorded. |
| Last Name | text | yes | The person's surname; the platform requires it. |
| Salutation | text | no | The title used in formal correspondence, for example Mr., Mrs., Dr. |
| Preferred Name | text | no | The name the person prefers to be called, used in greetings in place of first name when present. |
| Deceased | boolean | yes (defaults false) | Marks a person who has died; excluded from greetings and from most outreach. |
| Household Role | picklist(Head, Spouse or Partner, Child, Other) | no | The person's role in their household, used for greeting order. |
| Exclude From Household Name | boolean | yes (defaults false) | Leaves this person out of the computed household name. |
| Exclude From Greetings | boolean | yes (defaults false) | Leaves this person out of both computed greetings. |
| Personal Email | email | no | The person's own email address, the one they read at home. |
| Work Email | email | no | The email address this person uses at work. |
| Alternate Email | email | no | A third email address for a person who has one, for example a seasonal or a school address. |
| Preferred Email | picklist(Personal, Work, Alternate) | no | Which of the three addresses the organization should write to. Leaving it empty means the org is not using the three addresses at all. |
| Employer | reference(Organization) | no | The organization this person works for, used to recognize the employer when a matching gift arrives (G-10). |
| Household | reference(Household) | conditional | The household this person belongs to; in contact mode this is the person's Account. |
| Sample Data | boolean | yes (defaults false) | True when the record was created by the sample data loader so it can be removed in one action. |

### Relationships

- **Contact to Household**, many to one in contact mode (one household per person), many
  to many in junction mode through Household Member.
- **Contact to Organization**, in v0.1 only the platform's own Contact to Account
  reference where an org chooses to relate a person to an organization directly. The
  Affiliation entity that models this properly arrives in v0.3 (Section 28).
- **Contact to Contact**, from v0.3, through Relationship (Section 27).
- Contact is a target of the giving rollups listed in Section 26 from v0.2.

### Rules

**R-C1 Every person has a household.** In contact mode a Contact inserted with no
Account gets one created (R-H1). In junction mode a Contact inserted with no membership
gets a household and the membership record that joins them to it (R-H2). A Contact is
never left without a household unless automatic creation is turned off.

**R-C2 Naming inputs.** Preferred Name, when present, replaces First Name in the
informal greeting and in any pattern that uses a personal name. Salutation feeds the
formal greeting.

**R-C3 Deceased.** Setting Deceased triggers recomputation of the household's greetings
and, depending on `Include_Deceased_In_Name__c`, its name.

**R-C4 Record type.** The package ships no Contact record type. Nothing in the package
reads a person's record type, and an org can add its own Contact record types (ADR-0041).

**R-C5 Person Accounts.** Where Person Accounts are enabled, a person may be represented
as a Person Account rather than a Contact. `HouseholdService` presents both uniformly;
no feature code branches on it.

**R-C6 Preferred email.** The standard email is the address the platform and every email
tool reads, so it is kept in step with the choice. When Preferred Email names one of the
three addresses, the standard email is copied from that address on every save of the
person, before the record is written. When Preferred Email is empty nothing is copied and
the standard email is left exactly as it was entered, so an org that never fills the three
addresses in sees no change in behavior at all. When Preferred Email names an address that
is empty the save is refused with a message that says which address to fill in: blanking
the standard email would quietly cut the person off from every mailing.

### Salesforce implementation

- **Object:** Contact, with no packaged record type (R-C4).
- **Standard fields used:** `FirstName`, `LastName`, `Salutation`, `AccountId`
  (household membership in contact mode).
- **Custom fields on Contact:**

| Attribute | API name | Type |
|---|---|---|
| Deceased | `Deceased__c` | Checkbox |
| Household Role | `Household_Role__c` | Picklist: Head, Spouse or Partner, Child, Other |
| Exclude From Household Name | `Exclude_From_Household_Name__c` | Checkbox |
| Exclude From Greetings | `Exclude_From_Greetings__c` | Checkbox |
| Preferred Name | `Preferred_Name__c` | Text |
| Sample Data | `Sample_Data__c` | Checkbox |
| Sample Data Key | `Sample_Data_Key__c` | Text(20) (v0.4) |
| Employer | `Employer__c` | Lookup to Account |

The seven above are person attributes, present on both Contact and Account with the same
API names so that Person Accounts carry them (Section 5). `HouseholdService.Person` is the
shape naming and greetings read, so no naming code knows which object a person came from.

- **Email fields on Contact, and on Account with the same API names (v0.5):**

| Attribute | API name | Type |
|---|---|---|
| Personal Email | `Personal_Email__c` | Email |
| Work Email | `Work_Email__c` | Email |
| Alternate Email | `Alternate_Email__c` | Email |
| Preferred Email | `Preferred_Email__c` | Picklist: Personal, Work, Alternate (restricted) |

These four are person attributes like the seven above and are carried on Account for the
same reason. The standard email R-C6 keeps in step is `Email` on Contact and, where the org
stores people as accounts, the account object's own person email field.
`PreferredEmailService` is the only class that touches the account one, and it names it as
text and checks that the object has it before writing, exactly as `PersonRecordSelector`
does with the person name fields (Section 4 "Person references", ADR-0009).

- **Employer on the Account side:** in Person Account orgs the same attribute exists on
  Account as `Employer__c`, added there with the other person attributes (Section 4
  "Person references"). Both are plain lookups to Account, and neither is restricted by
  record type in metadata, because record types are the subscriber's to change; the
  matching gift service checks that the employer is an organization at run time (R-G11).

---

## 8. Organization

### Definition

A company, foundation, government agency, congregation, school, or other institution the
nonprofit knows: an organizational donor, an employer whose staff give, a funder, or a
partner. Organizations are not households and never carry household naming or greetings.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The organization's legal or commonly used name, entered by staff and never computed. |
| Record Type | picklist(Household, Organization) | yes | Always Organization for this entity. |
| Primary Contact | reference(Contact) | no | The person you deal with at this organization. |
| Sample Data | boolean | yes (defaults false) | True when the record was created by the sample data loader so it can be removed in one action. |

### Relationships

- **Organization to Contact**, one to many, for people the platform relates to the
  organization. The typed, dated Affiliation entity arrives in v0.3 (Section 28).
- Organizations are donors in their own right from v0.2 onward, where a Gift's donor is
  either a Contact or an Account (Section 18), and they are targets of the giving rollups
  in Section 26.

### Rules

**R-O1 Never renamed by automation.** No naming or greeting computation touches an
Organization. Household automation is gated on record type.

**R-O2 No automatic creation.** Organizations are created by staff or by the importer,
never implicitly from a Contact insert.

**R-O3 Shared fields.** Primary Contact is the same Account field the Household entity
uses; the field is shared across record types and its meaning differs by record type as
defined above. Member Count, Anniversary, the two greeting fields, and Custom Name are
not shown for Organization records on the Account record page.

### Salesforce implementation

- **Object:** Account, record type `Organization`.
- **Fields:** standard `Name`; `Primary_Contact__c` (shared with Household, above);
  `Sample_Data__c` (Checkbox, shared field definition with Household, above);
  `Sample_Data_Key__c` (Text(20), shared with Household, holding the key the generated
  sample set knows this organization by).

---

# Part B: Platform configuration entities

These entities are not constituent data. They exist because v0.1 features require them
(plan Sections 4.8 and 10.3), and they are governed by the same rule as everything else:
nothing is added to them in Salesforce before it is added here.

## 9. Error Log

### Definition

One caught exception or handled failure, recorded where an administrator can find it in
the app rather than in debug logs (plan Sections 2.3 and 4.8).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Timestamp | datetime | yes | When the error occurred. |
| User | reference(User) | no | The user whose action produced the error, where there was one. |
| Context | text | yes | The feature or source that produced the error, in plain language, for example "Household naming". |
| Record Reference | text | no | The identifier of the record involved, so the admin can open it. |
| Object Name | text | no | The kind of record involved, in the platform's name for it, so an admin can group errors by what they affect. |
| Message | long text | yes | A human-readable explanation of what went wrong and what to do about it. |
| Technical Detail | long text | no | Exception type, stack trace, and query or DML detail, for a developer or a support request. |
| Severity | picklist(Info, Warning, Error, Critical) | yes | How badly the failure affects the org's data or operations. |
| Status | picklist(New, Acknowledged, Resolved, Ignored) | yes | Where the admin has got to with this error. |

### Rules

**R-E1** Every caught exception in packaged code writes an Error Log record with a
message an administrator can act on. A silent catch is a review failure.
**R-E2** Error Log writing never itself throws; a failure to log is swallowed rather
than masking the original error.
**R-E3** The Hub shows a tile of unresolved errors, and an optional digest email goes to
the administrators (feature C-23, v0.6, R-E5).
**R-E4 The entry outlives the transaction it documents.** Most failures worth recording
end in a rollback: the save is refused and everything written in that transaction is
undone, an Error Log row included. So an entry is not written directly. It is published as
an **Error Log Event**, which the platform delivers whether or not the transaction commits,
and a subscriber writes the row. A direct write remains only as the fallback for when
publishing itself fails. Publishing is governed by Create on the event, so all three
packaged permission sets grant Read and Create on **Error Log Event**, Read Only
included. A user holding none of them falls back to the direct write, and for that user
the entry survives only when the transaction commits.
**R-E5 The digest counts; it never quotes.** The error digest is one email per recipient
about the entries created since the window the last digest covered that are still New:
how many, how many by Context and by Severity, and the newest 25 by record name with a link
to each, plus a link to the whole list. It never carries Message, Technical Detail or
Record Reference, so it holds less about a donor than the entries themselves. It goes only
to active users of the org (those holding Manage BarnCRM Settings, or those whose email
addresses the administrator lists), at most 50 of them, addressed to each user record so
that it does not count against the daily limit on email sent to addresses. A run that finds
nothing new sends nothing. One daily job, started and stopped in the settings console,
sends it at most once a day or once a week as the administrator chooses; a run that sent or
found nothing moves the covered window on, and a run that could not send leaves it where it
was, so no entry is counted twice or dropped. A run reads at most the newest 2,000 entries
and says "more than 2,000" beyond that, so a flooded Error Log cannot stop the digest. A
digest that is scheduled but has not run for two days is a Health Check warning (ADR-0055).
**R-E6 Entries are kept for a set time.** Each run of the daily Error Log job (the digest's)
first starts a batch that deletes every entry, whatever its Status, created more than
`Error_Log_Retention_Days__c` days before (default 180, 0 keeps every entry). The delete is
package upkeep in system mode (ADR-0021) and puts the entries in the Recycle Bin. Saving the
setting deletes nothing (owner decision, 2026-10-13, ADMIN-26).

### Salesforce implementation

- **Object:** `Error_Log__c`, surfaced as an admin-only tab in the BarnCRM app. The
  record name is the auto number `ERR-{000000}`.
- **Fields:** `Timestamp__c` (DateTime), `User__c` (Lookup to User), `Context__c` (Text),
  `Record_Reference__c` (Text), `Object_Name__c` (Text), `Message__c` (Long Text Area),
  `Technical_Detail__c` (Long Text Area), `Severity__c` (Picklist: Info, Warning, Error,
  Critical), `Status__c` (Picklist: New, Acknowledged, Resolved, Ignored).
- **Event:** `Error_Log_Event__e`, a platform event with publish behavior Publish
  Immediately, carrying the same values so that they survive a rollback (rule R-E4):
  `Message__c`, `Technical_Detail__c` (Long Text Area), `Context__c`,
  `Record_Reference__c`, `Object_Name__c`, `Severity__c`, `User_Id__c` (Text). The event
  has no Status: every entry is written as New.
- **Service:** `ErrorLogger`, with `ErrorLogWriter` (publishes the event, and is the only
  class allowed to write the object directly, in system mode, so that a failure is recorded
  even for a user without create access), `ErrorLogEventHandler` (the subscriber that
  writes the rows) and `ErrorLogSelector`.

---

## 10. Automation Setting

### Definition

One packaged automation, with a description an administrator can understand and a switch
to turn it off. This is the NPSP trigger-handler table done on the front end (plan
Sections 3.2 and 4.8), and it is what lets Maria get unstuck during an import without
calling anyone.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Automation Name | text | yes | The stable identifier of the automation, matching its entry in the shipped registry. |
| Description | long text | yes | What this automation does, in the language an administrator uses. |
| Enabled | boolean | yes (defaults true) | Whether the automation runs; unchecking it bypasses the handler. |
| Always Runs | boolean | yes (defaults false) | Whether this automation enforces a rule rather than providing a convenience. An automation marked this way runs whatever the switch, the pause and the bypass say, and its switch is shown off and disabled in the console (ADR-0024). |
| Handler Class | text | no | The packaged code the dispatcher runs for this automation, copied from the shipped registry. |
| Object Name | text | no | The kind of record this automation runs on, copied from the shipped registry. |
| Execution Order | integer | no | The order in which this automation runs relative to others on the same kind of record. |
| Package Default | boolean | yes (defaults false) | Whether this record was materialized from the shipped registry rather than created by hand, so that "Restore defaults" knows what it owns. |

### Related org-level control

The global pause is not a property of any single automation. It is held in the org
settings entity (Section 12) as `Automation_Paused_Until__c`: a datetime after which
automation resumes by itself. While it is in the future, no packaged trigger logic runs
and the Hub shows a banner. This satisfies the C-04 acceptance criterion ("Pause all
automation for 2 hours") and the auto-expiry requirement in C-23.

Since C-23 the end of a pause is also recorded. Pausing schedules a one-time job for the
moment the pause ends; the job clears the value and writes the Setting Change for the
resume, as the Resume button does. The comparison with the clock still decides whether
automation runs, so it resumes on time even when the job is late; the job is what puts the
resume in the audit trail. Who paused is read from the Setting Change that started the
pause rather than stored a second time (R-A5, ADR-0055).

### Rules

**R-A1** Every packaged trigger goes through the trigger framework and is therefore
bypassable (plan Section 7.2).
**R-A2** Records are materialized on install from the shipped registry custom metadata,
and new automations added by an upgrade are materialized without touching the admin's
existing on and off choices (Decision D-06).
**R-A3** Turning an automation off never deletes data and never suppresses error
logging.
**R-A4** An automation marked Always Runs enforces a rule rather than providing a
convenience, so the dispatcher does not consult the bypass, the pause or the switch for it.
The console still lists it, with its switch off and disabled and a line saying why, and a
request to switch it on or off is refused (ADR-0024).
**R-A5 A pause always ends by itself, on the record.** The global pause lasts 1, 2, 4, 8
or 24 hours, 2 unless the administrator chooses otherwise. Its end is written when it
starts, a one-time job clears it at that moment and records the resume as a Setting Change,
and resuming by hand or pausing again cancels that job. The job clears only the end it was
scheduled for, so it can never end a newer pause. A pause in effect that no job is
scheduled to end, or that ends more than 24 hours ahead, is a Health Check warning. Neither
the pause nor its end moves any automation's switch, and neither touches an Always Runs
automation (R-A4).

### Salesforce implementation

- **Object:** `Automation_Setting__c` with `Automation_Name__c` (Text, external id,
  unique), `Description__c` (Long Text Area), `Enabled__c` (Checkbox),
  `Always_Runs__c` (Checkbox, default false), `Handler_Class__c` (Text),
  `Object_Name__c` (Text), `Execution_Order__c` (Number),
  `Is_Package_Default__c` (Checkbox). The record name holds the automation's label as the
  admin reads it.
- **Shipped defaults:** `Automation_Registry__mdt` (Section 13).
- **Org-level pause:** `BarnCRM_Settings__c.Automation_Paused_Until__c`.
- **Service:** `AutomationControl`, `TriggerDispatcher`.

---

## 11. Setting Change

### Definition

An audit entry recording that a setting was changed, by whom, when, and from what to
what. Required by the C-03 acceptance criterion that every settings change is logged
(who, when, old, new).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Setting Name | text | yes | The setting that changed, recorded by its stable key. |
| Old Value | long text | no | The value before the change, blank when the setting had never been set. |
| New Value | long text | no | The value after the change, blank when the setting was cleared. |
| Changed By | reference(User) | yes | The user who made the change. |
| Changed At | datetime | yes | When the change was saved. |
| Deployment Id | text (18) | no | For a change made through the custom metadata manager, the metadata deployment that applied it; blank for every other change. The manager reads it to tell the page the save finished (R-S6). |

### Rules

**R-S1** Every write through the settings service produces exactly one Setting Change
record per setting actually changed. Saving a page without changing anything writes
nothing.
**R-S2** Setting Change records are never edited or deleted by packaged code.
**R-S3** Values are stored as text so that any setting type can be audited uniformly.
**R-S4** A value that is not set is recorded as nothing, never as empty text. Unset and
cleared are the same state on a hierarchy custom setting, the platform stores empty text
as nothing anyway, and an audit row that claimed otherwise could never read back what it
was written with.
**R-S5** A value arrives at the settings service in whatever Apex type its caller holds,
not only as text. A Datetime handed in as a Datetime is stored as it is: `String.valueOf`
of a Datetime is not the ISO 8601 form the service parses back, so a round trip through
text would refuse the package's own writes.
**R-S6** A custom metadata record changed through the custom metadata manager is audited
once the deployment succeeds, not when it is requested: the deployment's callback writes
one Setting Change with Setting Name `<Type>.<DeveloperName>`, the old and new values as
JSON, Changed By set to the user who saved, and Deployment Id set. A failed deployment
writes no Setting Change; it writes an Error Log entry whose Record Reference is the
deployment Id.

### Salesforce implementation

- **Object:** `Setting_Change__c` with `Setting_Name__c`, `Old_Value__c`, `New_Value__c`
  (Long Text Area), `Changed_By__c` (Lookup to User), `Changed_At__c` (DateTime),
  `Deployment_Id__c` (Text 18). The record name is the auto number `SC-{000000}`.
- **Service:** `SettingsService`; `CustomMetadataDeployCallback` for R-S6.

---

## 12. BarnCRM Settings

### Definition

The org's simple, org-wide toggles and values: feature flags, mode selections, and
naming pattern choices. Stored as a protected hierarchy custom setting so that the
settings console can write them synchronously and so that they are cacheable (Decision
D-06).

Core is neutral (plan Section 4.1, C-29, ADR-0059): a key lives here only if Core reads it or
it means the same thing to any organization. The console and the object are labelled **BarnCRM
Settings**, and its API name is `BarnCRM_Settings__c` (it was `Nonprofit_Settings__c` until
the API name pass, ADR-0063, which supersedes ADR-0059 decision 6). Seven keys this section listed before v0.6, the tax
identification number, the four receipt signer and file keys, and the default fund and
appeal, are read only by Giving and moved to `Giving_Settings__c` (Section 21A) in C-29, with
their API names and definitions unchanged.

### v0.1 keys

This is the **starting inventory** for v0.1. It is not closed. Each feature pull request
may add keys, and must add them here first.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Coexistence_Mode__c` | picklist(Standalone, NPSP, NonprofitCloud) | Standalone | How this org coexists with what is already installed; set by the Setup Assistant after automatic detection and confirmable later (plan Section 4.5). Shown as Standalone, NPSP coexistence and Nonprofit Cloud coexistence. Standalone is always offered; NPSP coexistence only when `OrgShapeDetector` finds NPSP (`hasNpsp`); Nonprofit Cloud coexistence only when it finds Nonprofit Cloud objects (`hasIndustriesNonprofit`); the saved value is always offered. The Setup Assistant and the console offer the same list. Recommended: Nonprofit Cloud coexistence, else NPSP coexistence, else Standalone (ADR-0062). |
| `Household_Membership_Mode__c` | picklist(Contact, Junction) | Contact | Whether household membership uses the Contact's Account reference or the Household Member junction. |
| `Auto_Create_Households__c` | boolean | true | Whether saving a new person who belongs to no household creates one automatically. Governs both membership modes, and both objects a person can be stored on (R-H1, R-H2). |
| `Delete_Empty_Households__c` | boolean | true | Whether a household left with no members is deleted. |
| `Keep_Households_Of_Deleted_People__c` | boolean | false | Whether households emptied by deleting people are kept rather than moved to the Recycle Bin by the nightly tidy-up (R-H12a). Inverted so the tidy-up is on for new installs and for orgs upgrading with saved settings, with nothing to apply in Apex. |
| `Household_Name_Pattern__c` | text | The {LastName} Family | The pattern used to compute a household's name. |
| `Formal_Greeting_Pattern__c` | text | {Salutation} {FirstName} {LastName} | The pattern used to compute the formal greeting. |
| `Informal_Greeting_Pattern__c` | text | {FirstName} | The pattern used to compute the informal greeting. |
| `Include_Deceased_In_Name__c` | boolean | false | Whether a deceased member remains in the computed household name. |
| `Automation_Paused_Until__c` | datetime | empty | While in the future, all packaged automation is paused; it resumes by itself at this time. |
| `Setup_Steps_Completed__c` | text (255) | empty | The comma separated keys of the Setup Assistant steps the administrator has marked done, so the Hub checklist remembers progress across sessions. |
| `Setup_Steps_Skipped__c` | text (255) | empty | The comma separated keys of the Setup Assistant steps the administrator chose to skip for now, so a skipped step moves out of the way without counting as done. |
| `Setup_Started_At__c` | datetime | empty | When the administrator first changed something in the Setup Assistant, so the completion screen can say how long setup took. |
| `Organization_Legal_Name__c` | text (255) | empty | The organization's legal name, as it appears on its official filings. Giving prints it on receipts and year-end statements. |
| `Organization_Address__c` | text (255) | empty | The organization's mailing address as one line, as it is printed on letters and documents. Custom settings have no long text field, so a single 255 character line is the format. |

### v0.2 keys

Added by the v0.2 features: the rollup engine (C-13) and the import framework (C-14). The
Setup Assistant (C-12) keys arrived early and are listed in the table above, where
`Setup_Steps_Completed__c` and `Setup_Steps_Skipped__c` are what was planned here as
`Setup_Assistant_Steps_Complete__c`, and the two default record identifiers shipped with the
assistant that wrote them (they are Giving keys from v0.6, Section 21A). The two rollup keys
published here, `Rollup_Mode_Default__c` and `Rollup_Processing__c`, moved with the engine to
the BarnCRM Rollup Builder module's own `Rollup_Settings__c` (Section 14B, ADR-0125), with
their API names and definitions unchanged.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Fiscal_Year_Start_Month__c` | picklist(1 to 12) | 1 | The month the organization's fiscal year begins, used by every fiscal-year-aware rollup window (R-R3). |
| `Import_Chunk_Size__c` | integer | 200 | How many rows an import processes per chunk; lower it on an org with heavy custom automation. |
| `Import_Trial_Rows__c` | integer | 25 | How many of a file's first rows a trial import commits before the rest (R-IB16); the wizard starts from it and the administrator can change it per file. Held between 1 and 2,000. |

Custom settings do not support a long text attribute, so each step list holds a comma
separated set of keys within 255 characters, which the eight step checklist fits with
room to spare.

### v0.3 keys

Added by the v0.3 features: commitments (G-07), soft credits (G-08), relationships (C-15),
and addresses (C-17).

Three keys published here in v0.3 are no longer Core keys. ADR-0017 gives each package its
own settings object, so `Automatic_Household_Soft_Credits__c`,
`Installment_Generation_Horizon_Months__c` and `Installment_Overdue_Grace_Days__c` live on
the Giving package's own `Giving_Settings__c` and are specified in Section 21A. Core kept
`Default_Fund__c` and `Default_Appeal__c` until v0.6, when C-29 moved them to Giving as well:
the Setup Assistant now writes them through Giving's step (ADR-0059).

| Key | Type | Default | Definition |
|---|---|---|---|
| `Contact_Address_Change_Behavior__c` | picklist(Update household, Create personal address) | Update household | What happens when a person's address is edited: the household moves, or that person gets an address of their own (R-AD5). |
| `Relationship_Auto_Reciprocal__c` | boolean | true | Whether the package creates and maintains the other side of every relationship (R-RL1). The default is applied in Apex by `SettingsService`, not by the field's own default value (ADR-0035). |
| `Seasonal_Address_Last_Run__c` | datetime | empty | When the seasonal address swap job last completed, shown on the Hub; written by the job (C-18, R-AD4, R-AD8). |
| `Seasonal_Address_Last_Run_Summary__c` | text | empty | What the last seasonal swap run did, in one sentence: how many addresses moved in, how many moved back, and how many failed (R-AD8). |

The commitment keys (`Installment_Generation_Horizon_Months__c`,
`Installment_Overdue_Grace_Days__c`, `Auto_Apply_Gifts_To_Installments__c`, and the
nightly run stamps listed in Section 21A) and `Automatic_Household_Soft_Credits__c` are
Giving keys and live on `Giving_Settings__c`, the Giving package's own protected hierarchy
custom setting, not on `BarnCRM_Settings__c`: a dependent package cannot add fields to
an object Core owns (ADR-0017). They are listed here because this section is the whole
settings inventory, and the settings console reads every registered settings object
through `Setting_Definition__mdt`, so an admin sees one console whichever object holds
the value.

### v0.5 keys

Added by Import 2.0 (C-19).

| Key | Type | Default | Definition |
|---|---|---|---|
| `Import_Undo_Retention_Days__c` | integer | 30 | How many days after a commit an import can still be undone. Stamped onto the batch when it commits, so changing it never moves the deadline of an import that has already run (R-IB7). |

### v0.6 keys

Added by the error digest (C-23, R-E5). The digest is switched on and off by scheduling
its job from the console, as the nightly jobs are (ADR-0038), so it has no on and off key.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Error_Digest_Recipients__c` | text (255) | empty | The email addresses of the users who receive the error digest, separated by commas. Each has to belong to an active user of this org. Empty sends it to every active user holding Manage BarnCRM Settings. |
| `Error_Digest_Frequency__c` | picklist(Daily, Weekly) | Daily | How often the error digest may be sent. Stored as text (ADR-0019); empty reads as Daily. |
| `Error_Digest_Covered_Until__c` | datetime | empty | The end of the window the last digest run covered; the next digest counts entries created after it. Written by the job. |
| `Error_Digest_Last_Run__c` | datetime | empty | When the digest job last ran, whether or not it sent anything. Written by the job. |
| `Error_Digest_Last_Run_Summary__c` | text (255) | empty | What the last digest run did, in one sentence. Written by the job. |
| `Error_Log_Retention_Days__c` | number(4, 0) | 180 | How many days an Error Log entry is kept before the daily Error Log job deletes it (R-E6). 0 keeps every entry; otherwise 1 to 3,650. Added 2026-10-13 (owner decision, ADMIN-26). |

### v0.7 keys

Added by Find (C-34, Section 29D), bulk update (C-35, Section 29E) and bulk delete (C-37,
Section 29E, R-BD2). Shown in the console's Import section.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Find_Export_Row_Limit__c` | integer | 50000 | The most rows one Find export writes (R-SQ3). From 1 to 500,000; empty reads as 50,000. |
| `Bulk_Update_Run_Limit__c` | integer | 48000 | The most records one bulk update may change (R-BU2). From 1 to 48,000; empty or out of range reads as the nearest end. |
| `Bulk_Delete_Run_Limit__c` | integer | 10000 | The most records one bulk delete may delete (R-BD2). From 1 to 48,000; empty reads as 10,000, out of range as the nearest end. |
| `Import_Row_Retention_Days__c` | integer | 90 | How many days after an import finished its staged rows are kept before the nightly Import row cleanup removes them (R-IR5, D-40). From 1 to 3650; 0 keeps them for ever; empty reads as 90, over 3650 as 3650. |
| `Bulk_Chunk_Size__c` | integer | 200 | Records each chunk of a bulk update or bulk delete handles (R-BU2, R-BD2). From 10 to 200; empty reads as 200, out of range as the nearest end. Stamped on the job when it starts. |

### v0.8 keys

Added by the suite choice (C-30) and the Module Manager (C-24).

| Key | Type | Default | Definition |
|---|---|---|---|
| `Suite__c` | picklist(Community, Impact) | empty | Which edition the administrator chose in the Setup Assistant's first step: the Standard Edition (Core alone, the full core suite of tools) or the Nonprofit Edition (Core with Giving). Any org may choose either; empty until chosen. Shown as Standard Edition and Nonprofit Edition. When `Impact`, the modules step, the Module Manager and the home Modules card offer the nonprofit modules; otherwise Core shows none that is not installed. It installs and removes nothing (ADR-0072, `0072-suite-choice-is-the-first-setup-step.md`). Chosen once in the Setup Assistant; changed later only through the console's Change edition control or Setup, Custom Settings (ADR-0124, `0124-edition-gates-visibility.md`). |
| `Modules_Turned_Off__c` | text (255) | empty | The comma separated names of the installed modules the administrator turned off in the Module Manager. While a module is listed, its automations do not run, except those that always run (ADR-0024); Core cannot be listed. Written by the Module Manager, not edited as a setting (ADR-0073, `0073-module-manager-turns-automation-off-and-never-installs.md`). |
| `Features_Turned_On__c` | text (255) | empty | The comma separated keys of the Core features turned on (`DataManager`, `DuplicateReview`, `OrgOptimizer`, `HouseholdUpkeep`, `Addresses`, `Relationships`, `Affiliations`, `PreferredEmail`). Empty means every feature is on: an org upgraded from before features existed. A new install stores `None` (every feature off) until first-run setup; finishing it with every feature unticked stores `NoneChosen` (every feature off, setup done). A key once added is never removed: features are one-way. While a key is missing, its tabs' BarnCRM Tab permission sets are held by nobody, its rows are hidden in BarnCRM Settings, and its group's automations do not run. Written by General, Features and first-run setup, not edited as a setting (ADR-0124, `0124-edition-gates-visibility.md`). |

### Field utilization keys

None. ADR-0086 added three (`Field_Utilization_Objects__c`, `Field_Utilization_Last_Run__c`,
`Field_Utilization_Last_Run_Summary__c`); ADR-0101 `0101-field-utilization-on-demand.md`
removed them when the count moved to Org Optimizer and runs on demand (Section 29F).

### Job notification key

Added by the Core quality pass (Q-04). The notification itself is the platform's custom
notification, type `BarnCRM_Job_Finished`, sent by `JobNotifier`; nothing about it is stored on
a BarnCRM record.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Job_Notifications__c` | boolean | true | Whether the person who starts a long job by hand (import and its undo, bulk update, bulk delete and their undos, sample data load, rollup recalculation, seasonal address swap, duplicate scan, household name recompute) gets one notification when the job finishes or stops. Scheduled runs never notify. Applied in Apex by `SettingsService` (ADR-0035). |

### Org Optimizer keys

Added by Org Optimizer (ADR-0103 `0103-org-optimizer-and-data-manager-pages.md`). Shown in
the console's General section. Each number has a minimum and a maximum (D-40); a value out of
range reads as the nearest end.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Stale_Record_Years__c` | integer | 5 | Years without a change before the Data quality check People not changed lists a person (R-SQ6). From 1 to 20; empty reads as 5. |
| `Unused_Login_Days__c` | integer | 90 | Days without a login before Unused setup lists an active user. From 30 to 365; empty reads as 90. |
| `Unused_Report_Days__c` | integer | 365 | Days without a run before Unused setup lists a report. From 90 to 1,095; empty reads as 365. |

### Health Check keys

Added by ADMIN-7 (ADR-0106 `0106-health-check-on-home-shows-the-last-result.md`). BarnCRM Home
shows the last full Health Check result instead of running every check on each load.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Health_Check_Last_Run__c` | datetime | empty | When Health Check last ran in full for someone with Manage BarnCRM Settings. Written by Health Check, without an audit row. |
| `Health_Check_Last_Result__c` | text (255) | empty | How many findings that run had, as three counts separated by commas: to fix (Error), to be aware of (Warning), for information (Info). Written by Health Check with `Health_Check_Last_Run__c`; read only to show the last result. |

### Rules

**R-N1 Protected and hierarchical.** The custom setting is protected (invisible to
subscriber Setup as editable configuration) and hierarchical, so the org-level values
are what packaged code reads.
**R-N2 Written from the app.** Values are written synchronously by Apex from the
settings console, never by asking the admin to open Setup (plan Section 2.3).
**R-N3 Cache invalidation.** Values are read with `getOrgDefaults()`, which the platform
serves from its own custom settings cache and refreshes when a save commits, and are held in
a per-transaction static that every write clears. So a change takes effect on the next
transaction and never appears stale beyond ten seconds (C-03 acceptance criterion). Core
ships no Platform Cache partition (ADR-0094).
**R-N4 Audited.** Every write produces a Setting Change record (Section 11).
**R-N5 Extension procedure.** A feature that needs a new key adds a row to the table
above in the same pull request that adds the field, with its default and its one-line
definition.

### Salesforce implementation

- **Custom setting:** `BarnCRM_Settings__c`, hierarchy, protected.
- **Picklist keys are stored as text.** Custom settings do not support picklist fields on
  the platform, so `Coexistence_Mode__c` and `Household_Membership_Mode__c` are Text
  fields holding one of the values listed above, validated by `SettingsService` rather
  than by the field. The console renders them as a choice list, so Maria never types a
  value. Recorded as ADR-0019.
- **Service:** `SettingsService`, with the console LWCs `settingsConsole`,
  `settingsSearch`, `householdNamingSettings`.
- **Permission:** editing requires the `Manage_BarnCRM_Settings` custom permission, labelled
  Manage BarnCRM Settings; users without it see a read-only view naming the permission.

---

## 12A. What's New Seen

### Definition

For one person, the newest release whose notes they have dismissed from the What's new card on
the BarnCRM home page (C-27). It exists so that each person sees each release's notes once. It
holds no setting anybody chooses: it is written only by that person's Dismiss.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Person | reference(User) | yes | The person this record belongs to. One record per person at most. |
| Last Seen Version | text (20) | no | The release version, as dot separated numbers such as 0.12, that was current when this person last dismissed the card. |

### Rules

**R-WN1 Per person only.** A record belongs to one person. No organization-wide or profile
value exists, and none is read: a person with no record has never dismissed the card.
**R-WN2 What is shown.** The current version is the highest version among the shipped Release
Note records (Section 13). A person with no record sees the notes of the current version only.
A person with a record sees every note whose version is higher than their Last Seen Version,
newest version first. A person whose Last Seen Version is the current one or higher sees
nothing.
**R-WN3 Versions compare as numbers.** Versions are compared part by part as whole numbers, so
0.12 is newer than 0.9, and a missing part counts as zero, so 0.12 and 0.12.0 are the same
release. A version that is not dot separated whole numbers is ignored: a note carrying one is
never shown, and a stored Last Seen Version carrying one reads as no record.
**R-WN4 Dismiss.** Dismissing stores the current version as the person's Last Seen Version.
With no notes shipped, Dismiss stores nothing.

### Salesforce implementation

- **Custom setting:** `Whats_New_Seen__c`, hierarchy, protected, with user-level records only
  (`SetupOwnerId` is the person). Not a key on `BarnCRM_Settings__c`, because a user-level
  record of that setting would hide the organization's values from that person (ADR-0087,
  `0087-whats-new-from-packaged-release-notes.md`).

| Attribute | API name | Type | Notes |
|---|---|---|---|
| Last Seen Version | `Last_Seen_Version__c` | Text(20) | Written in system mode by `WhatsNewSeenWriter` (ADR-0021), for the running user only. |

- **Service:** `WhatsNewController`, with the LWC `whatsNew` on the BarnCRM home page.

---

## 13. Shipped defaults (custom metadata)

Package-shipped defaults are read-only to admins and are materialized into the
corresponding records by the post-install script on first install and on "Restore
defaults." Upgrades update the shipped defaults without touching the admin's records.
This is how upgrade safety (Principle 6) is achieved (Decision D-06).

### Setting Definition

`Setting_Definition__mdt`: the catalog of everything the BarnCRM Settings console shows,
one row per setting or per section that a component renders, so that a feature adds its
settings to the console by shipping rows rather than by editing the console.

| Field | Type | Definition |
|---|---|---|
| DeveloperName | text | The stable identifier of this console row. |
| Label | text | The setting's name as the admin sees it in the console. |
| `Setting_Key__c` | text (80) | The API name of the settings field this row edits; blank for rows that render a component instead of a single value. |
| `Settings_Object__c` | text (80), default `BarnCRM_Settings__c` | The protected hierarchy custom setting this row reads and writes, so a module can ship rows against its own settings object (Decision ADR-0017). Every row states it explicitly, because a default is not re-applied when a record is redeployed or upgraded; `check-setting-object-explicit.py` enforces it. |
| `Section__c` | text (80) | The left navigation group this row belongs to, for example Households, Automation, Access, Health. |
| `Module__c` | text (40) | The package that ships this row, for example Core or Giving. |
| `Data_Type__c` | picklist(Checkbox, Text, Number, Picklist, DateTime, Record, RecordTypeList, Component) | How the console renders and validates this row. Record is a record picker storing one record Id; RecordTypeList is a checkbox list of the active record types of an object, storing their developer names separated by commas (ADR-0074, settings console pickers). |
| `Picklist_Values__c` | long text | The choices for a picklist row, as semicolon separated `value:label` pairs. |
| `Record_Object__c` | text (80) | The object a Record row picks from, or whose record types a RecordTypeList row lists, by API name without a namespace prefix. Blank for every other data type. |
| `Component__c` | text (80) | The Lightning web component rendered when the data type is Component. Core components only: the console imports them by name at compile time (Decision ADR-0020). |
| `Navigation_Target__c` | text (80) | The Lightning tab a module's own settings page lives on, used when the data type is Component and no component is named, because Core cannot import a component from a package that depends on it (Decision ADR-0020). |
| `Description__c` | long text | The plain-language help shown under the control. |
| `Help_Path__c` | text (255) | The admin guide path, relative to `docs/admin-guide/`, behind the row's Learn more link. |
| `Required_Permission__c` | text (80) | Optional. The API name of a custom permission, without a namespace prefix; when set, the console shows the row only to someone who has it (the name as given, else with the package namespace). For a module page whose controller only a module permission set opens (X-01, ADR-0058). |
| `Sort_Order__c` | number | The order of this row inside its section. |
| `Min_Value__c` | number(18, 2) | Number rows only: the lowest value the console accepts. The console marks a lower value before Save, and `SettingsService` refuses it on the server whoever saves it, naming the setting and the range (owner decision 2026-10-13, ADMIN-27). Every shipped Number row sets it. |
| `Max_Value__c` | number(18, 2) | Number rows only: the highest value accepted, enforced the same way. Every shipped Number row sets it. |

### Automation Registry

`Automation_Registry__mdt`: the catalog of packaged automations, materialized into
Automation Setting records (Section 10) on install and on upgrade.

| Field | Type | Definition |
|---|---|---|
| DeveloperName | text | The stable identifier of the automation, matched to Automation Setting. |
| Label | text | The automation's name as the admin sees it. |
| `Description__c` | long text | What the automation does, in nonprofit language. |
| `Enabled_By_Default__c` | boolean | Whether the automation is on when it is first materialized. |
| `Always_Runs__c` | boolean, default false | Whether this automation enforces a rule rather than providing a convenience, so it cannot be switched off from the console or suppressed by a pause (ADR-0024). Copied to `Automation_Setting__c.Always_Runs__c` when the record is materialized. |
| `Handler_Class__c` | text | The Apex handler the trigger dispatcher invokes. |
| `Object_Name__c` | text | The object whose trigger this automation runs on. |
| `Execution_Order__c` | integer | The order in which handlers run for that object. |
| `Module__c` | text (40) | The module that ships this automation, for example Giving or Mirror; blank means Core. The Module Manager turns a module's automations off by this name (C-24). |

The custom field API names are given here because two of the plain names in the original
draft ("Object" and "Order") are platform reserved words, and because the materialized
`Automation_Setting__c` fields carry the same names (Section 10). v0.1 ships the type with
no records: the first records arrive with feature C-01, which ships the first two trigger
handlers.

### Rollup Definition Default

`Rollup_Definition_Default__mdt` (v0.2): the rollup definitions the package ships,
materialized into `Rollup_Definition__c` records (Section 14) on install and on "Restore
defaults", matched by Definition Key. The BarnCRM Rollup Builder module and Giving ship rows;
the metadata type itself belongs to the BarnCRM Rollup Builder module (ADR-0125).

| Field | API name | Type | Definition |
|---|---|---|---|
| DeveloperName | `DeveloperName` | text | The stable identifier of the shipped definition. |
| Label | `MasterLabel` | text | The rollup's name as the admin sees it. |
| Description | `Description__c` | long text | What this number means, in nonprofit language. |
| Definition Key | `Definition_Key__c` | text | The key written to the materialized record and matched on upgrade. |
| Source Object | `Source_Object__c` | text | The entity whose records are aggregated. |
| Target Object | `Target_Object__c` | text | The entity that carries the number. |
| Relationship Path | `Relationship_Path__c` | text | The path from source to target, in the notation in R-R1. |
| Aggregate | `Aggregate__c` | picklist(SUM, COUNT, MIN, MAX, FIRST, LAST, AVG) | The calculation applied. |
| Source Field | `Source_Field__c` | text | The attribute aggregated, empty for COUNT. |
| Order By Field | `Order_By_Field__c` | text | The attribute that decides first and last. |
| Target Field | `Target_Field__c` | text | The attribute that receives the result. |
| Filter JSON | `Filter_JSON__c` | long text | The source filter document (R-R2). |
| Target Filter JSON | `Target_Filter_JSON__c` | long text | The target filter document (R-R8). |
| Fiscal Year Aware | `Fiscal_Year_Aware__c` | boolean | Whether the calculation is limited to a fiscal year window. |
| Fiscal Year Offset | `Fiscal_Year_Offset__c` | integer | Which window: 0, -1, or -2. |
| Fiscal Date Field | `Fiscal_Date_Field__c` | text | The date attribute the window is measured on, written to the materialized definition. |
| Mode | `Mode__c` | picklist(Real-time, Scheduled, Both) | The mode the materialized definition starts in. |
| Default Active | `Default_Active__c` | boolean | Whether the definition is active when it is first materialized. |
| Package | `Package__c` | text | The package that ships this row, so Giving's rows are materialized only when Giving is installed. |

### Import Template Default

`Import_Template_Default__mdt` (v0.2): the import templates the package ships,
materialized into `Import_Template__c` records (Section 15) the same way. Its fields
mirror the template's own attributes.

| Field | API name | Type | Definition |
|---|---|---|---|
| DeveloperName | `DeveloperName` | text | The stable identifier of the shipped template. |
| Label | `MasterLabel` | text | The template's name as the admin sees it. |
| Description | `Description__c` | long text | What kind of file this template reads. |
| Template Key | `Template_Key__c` | text | The key written to the materialized record and matched on upgrade. |
| Column Mapping JSON | `Column_Mapping_JSON__c` | long text | The mapping document (R-IT1). |
| Default Values JSON | `Default_Values_JSON__c` | long text | The defaults document (R-IT1). |
| Matching Rule | `Matching_Rule__c` | picklist(Email exact, Name plus postal code, External ID) | The matching rule the template starts with. |
| Person Mode | `Person_Mode__c` | picklist(Contacts, Person Accounts) | Whether the template creates Contacts or person Accounts, overridden from the detected org shape on materialization. For a row with a Target Object it instead says which org the row is for (R-D3). |
| Default Active | `Default_Active__c` | boolean | Whether the template is offered when it is first materialized. |
| Target Object | `Target_Object__c` | text (255) | Optional. The API name of the one object the template loads, unprefixed (R-IT12); empty for a people template. Copied to the template's Target Object (V-06). |
| Load Operation | `Load_Operation__c` | picklist(Insert, Update by record Id, Update by a matching field, Upsert by external ID) | Optional. What a row of a one-object template does; empty means Insert. Copied to the template. |
| Load Match Field | `Load_Match_Field__c` | text (255) | The field rows are found by under Upsert by external ID or Update by a matching field, unprefixed; required under both. Copied to the template. |

### Relationship Type

`Relationship_Type__mdt` (v0.3): the mapping from a relationship type to its reciprocal,
read by the relationship service when it maintains the other side of a connection
(Section 27, R-RL3).

| Field | API name | Type | Definition |
|---|---|---|---|
| DeveloperName | `DeveloperName` | text | The stable identifier of the shipped type. |
| Label | `MasterLabel` | text | The type as the admin sees it, for example Parent. |
| Type | `Type__c` | text | The type as it appears in the Type picklist. |
| Reciprocal Type | `Reciprocal_Type__c` | text | The type the other side takes, for example Child for Parent. |
| Is Gendered | `Is_Gendered__c` | boolean | Whether the reciprocal depends on a person's gender; false on every shipped row, and the package ships no gendered mapping. |
| Active | `Active__c` | boolean | Whether this mapping is applied. Clearing it is how an administrator archives a row they added (R-D2). |
| Description | `Description__c` | long text | What this relationship means, in nonprofit language. |
| Is Shipped | `Is_Shipped__c` | boolean, default false | True on every row the package ships; false on a row an administrator added through the custom metadata manager. A shipped row is read only in the app (R-D2). |

The API names are given here, as they are for Automation Registry above, because the
shipped records name fields and a record that names a field its type does not define
refuses the whole deployment.

Relationship Type is the one shipped list that also holds the organization's own rows,
because the relationship service reads it directly rather than through a materialized
copy. Administrators add, edit and archive their rows from the Custom metadata page in
BarnCRM Settings (ADR-0085, `0085-custom-metadata-manager-edits-only-types-read-directly.md`).

### Release Note

`Release_Note__mdt` (C-27): the notes the What's new card on the BarnCRM home page shows after
an upgrade, one record per note. Unlike the types above it is never materialized into records:
it is read as shipped (R-WN2, Section 12A). The type belongs to Core, and any package that
depends on Core may ship its own records; Core never names them.

| Field | API name | Type | Definition |
|---|---|---|---|
| DeveloperName | `DeveloperName` | text | The stable identifier of the note. |
| Label | `MasterLabel` | text | The note's name in Setup; not shown on the card. |
| Version | `Version__c` | text (20) | The product release this note describes, as dot separated numbers such as 0.12. One numbering for every package, because a release ships them together. |
| Headline | `Headline__c` | text (255) | The note in one line, shown in bold. |
| Details | `Details__c` | long text | Optional. Plain text, one point per line; each line is shown as one item under the headline. |
| Sort Order | `Sort_Order__c` | number | Optional. The order of this note within its version, lowest first; a note without one comes last. |
| Module | `Module__c` | text (40) | Optional. The package the note describes, for example Giving, shown beside the headline. |

### BarnCRM Module

`BarnCRM_Module__mdt` (ADR-0124, `0124-edition-gates-visibility.md`): the catalog of BarnCRM
modules Core can offer before they are installed, one record per module, read as shipped and
never materialized. Core ships the records, because a module that is not installed cannot
announce itself. Whether a module is installed is still detected (`ModuleDetectionService`);
this type says only which editions offer it, how to tell it is here, and where its
description, installer and app are. A future module, or a Core feature that becomes a module
(such as BarnCRM Rollup Builder, record `Rollups`), needs only a new record. `Requires__c`
names the modules a module's package needs installed first (ADR-0125
`0125-rollup-builder-module.md`, D3).

| Field | API name | Type | Definition |
|---|---|---|---|
| DeveloperName | `DeveloperName` | text | The module's name as Core reports it, for example `Giving`; it is also the name `Modules_Turned_Off__c` and Setting Definition `Module__c` use. |
| Label | `MasterLabel` | text | The module's name shown to administrators, always starting `BarnCRM `, for example `BarnCRM Giving`. |
| Editions | `Editions__c` | text (40) | The stored edition values that offer the module, separated by semicolons: `Impact` for a nonprofit module, `Community;Impact` for one both editions offer. An installed module is listed whatever this says. |
| Package Folder | `Package_Folder__c` | text (40) | The module's folder under `packages/`, whose README is its "What this module does" link. |
| Install Version Id | `Install_Version_Id__c` | text (18) | The published package version Id (`04t`) Salesforce's installer opens, or empty until the module is first published. |
| Sort Order | `Sort_Order__c` | number | The order modules are listed in, lowest first, after Core. |
| Probe Object | `Probe_Object__c` | text (80) | Optional. An object of the module's own, unprefixed (for example `Rollup_Definition__c`): when this package's object by that name exists, the module counts as installed. For a module whose code still ships in Core or that announces no settings rows; empty means detection by announcement alone. |
| App Name | `App_Name__c` | text (80) | Optional. The developer name of the module's own Lightning app, unprefixed (for example `Fundraising`), where its Settings tab lives. The Modules section links an installed module to it; empty means no link yet. |
| Requires | `Requires__c` | text (255) | Optional. The modules this module's package needs installed first, as their DeveloperNames separated by semicolons, in install order (for example `Rollups` for Giving, `Rollups;Giving` for Funders and Mirror). While one of them is not installed, the module's row in the Modules section and the Setup Assistant says to install it first. Empty means none. |

### Rules

**R-D1** These lists are the **starting inventory** for the iterations covered here and
each feature pull request may extend them. Any new custom metadata field is added to the
tables above before the metadata file is created.
**R-D2** The custom metadata manager edits only the types registered in
`CustomMetadataManagerService` as admin-editable; today that is Relationship Type alone.
For a registered type: a row with `Is_Shipped__c` true is never changed by the manager;
a row the manager creates has `Is_Shipped__c` false, is not protected, and has a
DeveloperName starting `Org_`, a prefix no shipped row uses, so a later package version
can never ship a row with the same name; archiving clears the type's active field and
restoring sets it, since the Apex Metadata API cannot delete a record. Types materialized
into custom object records (Rollup Definition Default, Import Template Default, Receipt
Template Default) and types that describe packaged code or pages (Automation Registry,
Setting Definition) are not registered: the admin edits the materialized records instead,
and a row they added to the code catalogs would point at nothing.
**R-D3 Materializing a one-object template** (V-06). An Import Template Default row with a
Target Object becomes a one-object template (R-IT12): its Target Object, Load Operation and Load
Match Field are copied to the template, and its column mapping names the entity `Record`
(R-IT1). It is materialized only when the target object exists in the org and every field and
`lookupField` its mapping names is in the org's describe, so a row a module ships never becomes
a template that cannot run; a row skipped for this is written to the Error Log once per run.
Its Person Mode is not overridden: the row is materialized only where it matches the org's
people (Contacts, or Person Accounts where the org has them), so a module ships one row per
mode under the same Template Key when its mapping names a person's lookup or a person account
field, and only one of them ever becomes a template. A Delete by record Id template is never
shipped. A row's Matching Rule is copied as for any template and not used by a one-object
load.

---

# Part C: Core additions for v0.2

These entities are built by the v0.2 iteration in the Core package (features C-12, C-13,
C-14). They are configuration and staging entities, not constituent data, and they follow
the storage split in ADR-0006: the admin manages them as lists, so they are custom
objects, and the defaults the package ships for them are custom metadata materialized on
install (Section 13).

The fourth v0.2 Core feature, the full Setup Assistant (C-12), adds no entity. Its
resumable checklist records step completion in the BarnCRM Settings key
`Setup_Assistant_Steps_Complete__c` (Section 12), and its "pick default fund and appeal"
step writes `Default_Fund__c` and `Default_Appeal__c` in the same place.

## 14. Rollup Definition

### Definition

One calculated number: which records are counted, how they reach the record that shows
the number, what is aggregated, and when it is recalculated. This is the whole
configuration surface of the rollup engine (plan Section 4.10, feature C-13). An
administrator creates and edits these with a filter builder, and never types SOQL (plan
Section 2.3), in the Rollup Builder, a tab of its own where every rollup, shipped or
admin-made, is created and edited (`decisions/0082-barncrm-owns-its-rollup-engine.md`). The
Rollups section of the settings console opens it. The engine, this entity, the Rollup Queue
(Section 14A) and the shipped defaults type belong to the BarnCRM Rollup Builder module, not
Core (`decisions/0125-rollup-builder-module.md`).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The rollup's name as the admin sees it, for example "Household total giving". |
| Description | long text | no | What this number means, in the language an administrator uses. |
| Definition Key | text | yes | The stable identifier of this rollup, matching the shipped default it came from; unique. |
| Source Entity | text | yes | The entity whose records are aggregated, for example Gift. |
| Target Entity | text | yes | The entity that carries the calculated number, for example Household. |
| Relationship Path | text | yes | How a source record reaches its target, written in the path notation below; supports the household membership abstraction. |
| Aggregate | picklist(SUM, COUNT, MIN, MAX, FIRST, LAST, AVG, COUNT_DISTINCT, ANY, NONE, TEXT_LIST, TEXT_LIST_DISTINCT) | yes | The calculation applied to the matching source records (R-R15). |
| Source Attribute | text | conditional | The attribute aggregated; required for every aggregate except COUNT, ANY and NONE. |
| Order By Attribute | text | conditional | The attribute that decides which record is first or last; required for FIRST and LAST. For a text list, optional: the order the values are listed in. |
| Delimiter | picklist(Comma, Semicolon, New line) | no (defaults Comma) | What separates the values of a text list (R-R15); read only by TEXT_LIST and TEXT_LIST_DISTINCT. |
| Target Attribute | text | yes | The attribute on the target entity that receives the result; its type must suit the aggregate (R-R15). |
| Filter | long text | no | Which source records count, held as a filter document (see R-R2); empty means all of them. |
| Target Filter | long text | no | Which target records this definition maintains, held in the same filter format; empty means all of them. |
| Fiscal Year Aware | boolean | yes (defaults false) | Whether the calculation is limited to one fiscal year window. |
| Fiscal Year Offset | integer | conditional | Which window: 0 this fiscal year, -1 last, -2 two years ago; required when Fiscal Year Aware is true. |
| Fiscal Date Attribute | text | conditional | The date attribute the window is measured on, for example the gift date; required when Fiscal Year Aware is true and the attribute being aggregated is not itself the date. |
| Mode | picklist(Real-time, Scheduled, Both) | yes | When the number is recalculated (R-R4); defaults from the org's rollup mode default. Shown to the admin as Instantly, Every night and Both (recommended). |
| Last Calculated | datetime | computed | When this definition last completed a calculation, of any scope. |
| Is Package Default | boolean | yes (defaults false) | Marks a definition materialized from a shipped default rather than created by the admin. |
| Active | boolean | yes (defaults true) | Whether the engine runs this definition; turning it off never deletes the values already calculated. |

### Relationships

- **Rollup Definition to shipped default**, many to one by Definition Key, for the
  definitions the package ships (Section 13, `Rollup_Definition_Default__mdt`).
- Rollup Definition names its source and target entities as text, not as references, so a
  Core definition can drive a Giving object without Core holding a reference to the
  Giving package (R-R7).

### Rules

**R-R1 Path notation.** Relationship Path is a sequence of segments separated by ` > `.
Each segment is either a reference attribute on the entity reached so far, or one of the
mode-resolved tokens below. Alternatives are separated by ` | ` and are evaluated in
order: the first alternative that resolves to a record is the target for that source
record, and a source record whose alternatives all resolve to nothing is not counted.

| Token | Meaning |
|---|---|
| `{Household}` | The household of the person reached so far, resolved by `HouseholdService`: the Contact's Account reference in contact mode, the current `Household_Member__c` row in junction mode. |
| `{HouseholdMembers}` | Every current member of the household reached so far, resolved the same way and in the same two modes. |

Examples: `Household__c` (a gift to the household it already resolved to),
`Donor_Contact__c > {Household}` (a gift to its contact donor's household),
`Household__c | Donor_Account__c` (a gift to its household when it has one, otherwise to
the account that gave it).

The engine resolves the tokens through `HouseholdService` and never reads
`Contact.AccountId` or `Household_Member__c` directly, so the same packaged definitions
are correct in contact mode and in junction mode, including where the donor is a person
Account (ADR-0005 and Section 4 "Person references"). No packaged definition names a
Person Account field in metadata; where a filter must test one, the field name appears
inside the filter document as text and is resolved dynamically at run time (plan
Section 4.2).

**R-R2 Filter representation.** Filter and Target Filter are stored as one filter
document per definition, in the format below, rather than as child Filter Condition
records.

```
{
  "version": 1,
  "logic": "1 AND (2 OR 3)",
  "conditions": [
    { "id": 1, "field": "Status__c", "operator": "equals", "value": "Received" },
    { "id": 2, "field": "Amount__c", "operator": "greater than", "value": 0 },
    { "id": 3, "field": "Type__c", "operator": "in", "value": ["Grant", "Stock"] }
  ]
}
```

Operators: equals, not equals, less than, less or equal, greater than, greater or equal,
contains, does not contain, starts with, is null, is not null, in, not in. The `logic`
key is optional and defaults to every condition joined by AND.

*Extensions added with Find (C-34), still version 1.* Every addition is new syntax a
version 1 reader refuses rather than misreads, so the version number does not change.

- **Relative dates.** Three more operators, for date and date/time fields only: `this
  year` and `last year` (no value; calendar years in the running user's time zone) and
  `last n days` (value: a whole number from 1 to 3650; today and the n days before it).
  They render as the platform's date literals (`THIS_YEAR`, `LAST_YEAR`,
  `LAST_N_DAYS:n`), never as typed text: the number is read as an integer and written
  back from that integer.
- **Parent fields.** `field` may be a path through lookups, written with relationship
  names (`Household__r.Name`), at most two lookups deep. Each segment is checked against
  the running user's describe of the object it is on.
- **Typed values.** The filter builder writes a number as a JSON number, a checkbox as
  `true` or `false`, a date as `YYYY-MM-DD`, a date/time as `YYYY-MM-DDThh:mm:ssZ`, and
  `in` and `not in` as a list. A reader that knows the object coerces each value to the
  field's type and refuses one that does not fit.
- **Operators by field type.** The builder offers only what suits the field: text, email,
  phone and URL get equals, not equals, contains, does not contain, starts with, in, not
  in and the two null tests; picklists get equals, not equals, in, not in and the null
  tests; numbers, currency and percent get the six comparisons and the null tests; dates
  and date/times get those plus the three relative operators; checkboxes get equals only;
  lookups and Ids get equals, not equals, in, not in and the null tests. Fields the
  platform cannot filter on (long text, compound address and location fields) are not
  offered.

The filter builder (`filterBuilder`, one Core component) is the only writer of the
document, for both the Rollups page and Find, and it reads field lists from the running
user's describe through `QueryFieldCatalog`, so it never offers a field the user cannot
see.

*Why a document and not child rows.* Nothing the plan requires breaks without child rows.
A filter is never managed as a list in its own right: it is built, saved, and shipped as
part of one definition, so child rows would add parent-child DML ordering, orphan
cleanup, a sort attribute, and a second sharing surface for no gain. Materializing a
shipped default stays one record instead of a parent plus n children, cloning a
definition stays one copy, and a definition exported to a JSON file in the repository
stays one row. The cost is that individual conditions are not reportable and the platform
cannot validate them, so the settings service validates the document on save, the filter
builder is the only writer, and the `version` key exists so the format can change without
anyone having to guess what an older row meant.

**R-R3 Fiscal-year windows.** When Fiscal Year Aware is true, the window is computed at
run time from the org's fiscal year start month (Section 12) and Fiscal Year Offset, and
it is measured on the Fiscal Date Attribute. A definition that sums an amount has no date
of its own to bound, so the attribute that decides which year a record falls in is named
separately; a definition that aggregates a date directly may leave it empty, and the
attribute being aggregated is used.
Windows are never stored on the definition, so changing the fiscal year start month and
recalculating is enough to correct every fiscal rollup in the org.

**R-R4 Modes.** Real-time (shown as Instantly) keeps the number current as source records
change. By default a save marks the target records (R-R11), writes them to the Rollup Queue
(Section 14A) and returns, and the queue recalculates them just after the save, usually within
a minute; a bulk change (an import, a data loader run, a large update) goes the same way and
finishes within minutes (ADR-0098
`0098-real-time-rollups-recalculated-just-after-the-save.md`). With
`Rollup_Processing__c` set to In_Save (Section 14B), a normal save recalculates in the same save
instead, when the queries it is planned to spend fit what the transaction has left; a bulk
change, a save already running in the background, or one without the room is queued. Scheduled (shown as Every night)
recalculates in the nightly full run. Both (shown as Both (recommended)) does the first and
reconciles with the second, so the nightly run is the safety net for anything the first
missed; it is the mode the packaged giving definitions ship with, because it is the
combination that keeps the numbers visibly right (Principle 2). Real-time needs a trigger on
the source entity (R-R12); where there is none, the definition is recalculated only by the
nightly run and on demand. The stored values are unchanged; only what the admin reads is.

A merge has its own path, whichever `Rollup_Processing__c` says (of people, Section 29A, or of households,
R-H13).
The platform refuses a trigger's write to a record while it is in a merge, so the
survivors' real-time totals are recalculated just after the merge is saved, by a small
queued job (`SurvivorRecalculation` in `RollupService`) that runs only the real-time
definitions targeting the merged entity. When there are more than 50 survivors, or the save
cannot queue another job, the survivors go to the Rollup Queue (Section 14A) instead, and a
survivor the platform still refuses in the job is queued to be tried again
(ADR-0092, `0092-merge-survivors-recalculated-after-the-merge.md`).

**R-R5 Freshness.** Last Calculated on the definition answers "when was this number last
calculated" for the admin looking at the rollup list. The record page answer comes from
one last-calculated attribute per target entity, not one per target attribute; the
reasoning is in Section 26.

**R-R6 Upgrade safety.** Definitions with Is Package Default true are created from
`Rollup_Definition_Default__mdt` on install and on "Restore defaults", matched by
Definition Key. An upgrade adds newly shipped definitions and never overwrites a
definition the admin has edited (ADR-0006). An admin who does not want a packaged
definition sets Active to false; packaged code never deletes an admin's records.

**R-R7 No cross-package reference.** Source Entity, Target Entity, Source Attribute,
Target Attribute, and Order By Attribute are text. Core therefore drives rollups over
Giving objects without holding a reference to them, which the package dependency
direction forbids (ADR-0014).

**R-R8 Disjoint targets.** Two active definitions may write the same Target Attribute on
the same Target Entity only when their Target Filters make their target record sets
disjoint. This is what lets one total giving attribute on Account serve households
through one definition and organizations and person Accounts through another. The
Rollup Builder refuses a save of an active definition that would overlap another active one on
the same attribute: when either has no Target Filter, when the two Target Filters are the same
document, or when a record in the org meets both (one query per such pair, as the saving user).
Disjointness by construction cannot be decided from two arbitrary filters, so two filters no
current record meets together are allowed; the engine then writes each record from the
definition whose filter admits it.

**R-R9 Idempotency and negative amounts.** Recalculating any set of records produces the
same result as calculating it the first time, and every aggregate is correct in the
presence of the negative gifts that refunds and write-offs create (ADR-0010, ADR-0011). A
definition that sums money therefore has to admit both sides of a reversal: the negative
gift and the original whose status the reversal changed. A status filter that admits only
Received breaks this rule rather than serving it, which is what ADR-0022 corrects in the
packaged defaults of Section 26.

**R-R10 Validation on save.** The target attribute must exist and be writable, the
aggregate must suit the source attribute type, and FIRST and LAST must have an Order By
Attribute. A definition that fails validation is not saved, and the message names the
problem in plain language. The checks sit in two places:

- **Every save** (the "Check rollups before saving" automation) refuses a target attribute
  whose type does not suit the aggregate (R-R15) and a COUNT_DISTINCT or text list with no
  Source Attribute. It leaves an entity or attribute the org does not have to the planner, so
  a definition for a module that is not installed can still be saved.
- **The Rollup Builder's save** (`RollupBuilderController`) also refuses: a blank name; a
  target entity or attribute the org does not have, or cannot write; a source entity the org
  does not have, or a path whose first segment on any alternative is not a reference
  attribute of the source; a Source Attribute the source does not have; SUM and AVG of
  anything but a number, currency or percent, and MIN and MAX of anything but those or a
  date; FIRST and LAST with no Order By Attribute; a fiscal window whose offset is not 0, -1 or
  -2 or whose date attribute is not a date; a filter document that cannot be read or names an
  attribute the entity does not have; and an overlap under R-R8.

A definition written another way (an import, the API) that fails a Builder check is left out of
the run by the planner, which records why in the Error Log.

**R-R11 Recompute, and what marks a target.** Every calculation, instant, queued, nightly
or on demand, recomputes each affected target record from all its source records; nothing
is added to or subtracted from a stored total, which is what makes R-R9 hold when two
calculations overlap. A source change marks a target record for recalculation when it
touches an attribute a definition reads: the source, order-by and fiscal date attributes,
the path attributes, any attribute named in the filter, and attributes read through a
relationship (for example a gift's status, which the fund totals read from Gift Allocation
as `Gift__r.Status__c`). A changed path marks both the old and the new target; a delete
marks the old target, including when a parent record is deleted and its source records go
with it, which fires no trigger on them (deleting a gift removes its allocations, so the
gift's delete marks their funds); an undelete marks the target again. A person who changes
household marks both households, in both membership modes. A save recalculates only the
definitions that marked a target, never every definition on its entity (ADR-0099
`0099-rollups-recalculate-only-what-a-save-changed.md`); a full run calculates every
definition it covers. The definitions one calculation runs on one target entity are
calculated together, one write per target record, and a value that did not change is not
written.

**R-R12 Where real time comes from.** Each package ships the trigger registration for its
own source entities (Automation Registry, Section 13). An administrator's own entity has no
packaged trigger, so real time on it comes from one of two places: a trigger the Rollup
Builder generates and deploys for the administrator (one line that hands the changed
records to the engine, plus its test, named from the entity so the same code is produced in
every org), or a record-triggered Flow built from the shipped template. Editing a rollup
never regenerates the trigger, because the rollup's settings live only in the definition.
When the last active definition on that entity is removed, the Builder offers to remove the
generated trigger, and Health Check reports a generated trigger that no active definition
uses. A generated trigger is switched off like any other automation, through an Automation
Setting row (Section 10) the Builder creates with Is Package Default false.

**R-R13 Freshness stamps are written when the work is done.** A calculation writes
`Rollups_Last_Calculated__c` on a target record in the same write as its totals (Section
26), and a definition's Last Calculated is set when the run that covers it has finished,
not when it was queued (R-R5). Because unchanged values are not written (R-R11), a record
whose totals a run confirmed without changing keeps its earlier stamp; the definition's Last
Calculated is what says the run happened. Stamping every record on every run would rewrite
every target record every night, which is the load the changed-only rule removes.

**R-R14 One full run at a time, and nothing lost when a chunk stops.** A full recalculation
(the nightly run, Recalculate, Recalculate all) does not start while another is running: the
second start is refused, names the running job, and tells the admin to try again when it
finishes. A chunk of a full run that the platform stops with an error the run cannot catch
(a governor limit) has its target records written to the Rollup Queue (Section 14A), so they
are recalculated within minutes rather than at the next night.

**R-R15 Aggregates and the target types they fill.** Each aggregate fills only the target
types below; any other pairing is refused on save (R-R10) and by the planner.

| Aggregate | What it answers | Target attribute types |
|---|---|---|
| SUM, AVG, MIN, MAX | The total, the average, the smallest and the largest value of the Source Attribute. | number, currency, percent, date, datetime |
| COUNT | How many records match. | number, currency, percent, date, datetime (as before; a number is what makes sense) |
| FIRST, LAST | The Source Attribute of the record with the lowest (FIRST) or highest (LAST) Order By Attribute. | number, currency, percent, date, datetime, text, long text |
| COUNT_DISTINCT | How many different values the Source Attribute holds among the matching records. | number |
| ANY | True when at least one record matches, false when none does. | checkbox |
| NONE | True when no record matches, false when at least one does. | checkbox |
| TEXT_LIST | The Source Attribute of every matching record, joined by the Delimiter. | text, long text |
| TEXT_LIST_DISTINCT | The same, with each value listed once. | text, long text |

- **Blanks.** A blank Source Attribute is never counted by COUNT_DISTINCT and never listed by
  a text list. FIRST and LAST take the first record's value even when it is blank; a filter
  condition "is not null" on the Source Attribute skips such records. ANY and NONE read no
  Source Attribute: the filter says which records count, so "any gift over 1,000" is ANY with
  the filter `Amount__c greater than 1000`.
- **Ties.** When two records have the same Order By Attribute, FIRST and LAST take the one
  with the lower record Id, so the answer is the same on every run (R-R9).
- **Order of a text list.** By the Order By Attribute when there is one, ascending, records
  with a blank one last; otherwise alphabetically by value, ignoring case. Ties go to the lower
  record Id. TEXT_LIST_DISTINCT keeps the first occurrence of each value, compared exactly
  (letter case counts), and so does COUNT_DISTINCT.
- **Delimiter.** Comma joins with a comma and a space, Semicolon with a semicolon and a space,
  New line with a line break. A value that contains the delimiter is written as it is, not
  escaped, so a list of names that contain commas reads best with Semicolon or New line.
- **Values into text.** A number, date or checkbox copied into text by FIRST, LAST or a text
  list is written as its plain value (`1250.00`, `2026-03-01`, `true`; a datetime in UTC as
  `2026-03-01 14:05`), not converted between currencies.
- **Cut at the field length.** A text result longer than the target attribute holds is cut at
  the attribute's length, so the save never fails on it and the same value is written on every
  run.
- **Exact under recompute.** Every aggregate here is recomputed from all the source records of
  each marked target (R-R11), so an instant, queued, nightly or on-demand calculation gives the
  same answer; none of them needs a fallback to a full recalculation. COUNT_DISTINCT and the
  text lists read the matching rows rather than a grouped answer, so a value found on the
  records of two household members, or of two path alternatives, is counted once.

### Salesforce implementation

- **Object:** `Rollup_Definition__c`, listed and edited in the settings console.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Definition Key | `Definition_Key__c` | Text, External Id, unique |
| Source Entity | `Source_Object__c` | Text |
| Target Entity | `Target_Object__c` | Text |
| Relationship Path | `Relationship_Path__c` | Text |
| Aggregate | `Aggregate__c` | Picklist: SUM, COUNT, MIN, MAX, FIRST, LAST, AVG, COUNT_DISTINCT, ANY, NONE, TEXT_LIST, TEXT_LIST_DISTINCT (labels Sum, Count, Minimum, Maximum, First, Last, Average, Count distinct, Any, None, Text list, Text list, each value once) |
| Delimiter | `Delimiter__c` | Picklist: Comma, Semicolon, New line (default Comma) |
| Source Attribute | `Source_Field__c` | Text |
| Order By Attribute | `Order_By_Field__c` | Text |
| Target Attribute | `Target_Field__c` | Text |
| Filter | `Filter_JSON__c` | Long Text Area |
| Target Filter | `Target_Filter_JSON__c` | Long Text Area |
| Fiscal Year Aware | `Fiscal_Year_Aware__c` | Checkbox |
| Fiscal Year Offset | `Fiscal_Year_Offset__c` | Number (0 decimals) |
| Fiscal Date Attribute | `Fiscal_Date_Field__c` | Text |
| Mode | `Mode__c` | Picklist: Real-time, Scheduled, Both (labels Instantly, Every night, Both (recommended); the same on `Rollup_Mode_Default__c`) |
| Last Calculated | `Last_Calculated__c` | DateTime |
| Is Package Default | `Is_Package_Default__c` | Checkbox |
| Active | `Active__c` | Checkbox |

- **Shipped defaults:** `Rollup_Definition_Default__mdt` (Section 13).
- **Automation:** one registry row on `Rollup_Definition__c`, `Rollup_Definition_Validation`
  ("Check rollups before saving"), handler `RollupDefinitionValidationHandler`, execution order
  10, the save check of R-R10 and R-R15. It checks an insert and an edit of the aggregate, the
  target or the source attribute, so switching a definition on or off never re-checks it. It
  pauses while the module is turned off (ADR-0125 `0125-rollup-builder-module.md`, decision
  9); a definition saved then that cannot be planned is refused by `RollupPlanner` and logged
  on every run, so no total is written wrong.
- **Settings keys:** `Fiscal_Year_Start_Month__c` (Section 12), `Rollup_Mode_Default__c`
  (Section 14B).
- **Field history:** tracked on Source Entity, Target Entity, Relationship Path, Aggregate,
  Source Attribute, Target Attribute, Filter, Target Filter, Mode and Active, so "who changed
  how this total is calculated" has an answer (owner decision 2026-10-12; a platform feature,
  completed with the Rollup Builder, which set Filter and Target Filter). Long text attributes
  record that they changed, not the values.
- **Rollup Builder:** the `Rollup_Builder` tab and app page, `rollupBuilder` (which nests the
  Rollups list, `rollupDefinitions`, with New, Edit and Copy), `rollupWizard` (the five steps)
  and `rollupFilterBuilder` (R-R2 documents, built once and shared with Find, plan Section
  4.9). `RollupBuilderController` describes the org for the steps, in the running user's
  describe, and saves a definition in user mode after the checks of R-R10 and R-R8. A new
  definition gets the Definition Key `Custom_` followed by 16 random hexadecimal characters,
  and Is Package Default false; an edited one keeps its key. Its preview (S12) calculates the
  unsaved definition for one record through `RollupEngine.preview`, which writes nothing, and
  counts the target records it would maintain in user mode. `RollupController.estimateFullRun`
  counts the records Recalculate all goes through at a fixed rough rate (1,650 records a
  minute, to be measured on an org), and `runTonight` sets up one 2:00 AM run through
  `RollupScheduler.scheduleTonight` only when the nightly run is not scheduled. Needs
  attention (S13), `rollupNeedsAttention` under the list, reads the Rollup Queue in user mode
  through `RollupAttentionController` (records waiting and the oldest's age, one row per record
  of each Failed entry named by describe, at most 200, whether the nightly run is scheduled and
  how the last full run ended); its Retry, for the selected records' entries or all, goes
  through `RollupQueue.retry`, which sets them Pending with Attempts 0 and no Next Attempt in
  system mode (R-RQ4, R-RQ5).
- **Service:** `RollupService`, `RollupSelector`, `RollupFilterParser` and `RollupScheduler`,
  in front of BarnCRM's own aggregation core (`decisions/0082-barncrm-owns-its-rollup-engine.md`;
  the vendored apex-rollup tree, `RollupAdapter`, `Rollup__mdt` and `RollupCalcItem__c` were
  deleted in slice S9). That core is
  `RollupEngine` (one pass per target entity), `RollupPlanner` (definitions into source queries), `RollupAggregator` (the calculator), `RollupCurrency` (target record currency),
  `RollupWriter` (changed-only writes), `RollupChanges` (which targets a save marks, R-R11),
  `RollupQueue` (the queue processor, Section 14A), and `RollupFullRecalcBatch` (the full and
  nightly recalculation: one batch pass per target entity in turn, records with many source rows
  in smaller chunks or alone, Last Calculated stamped when the last pass finishes, R-R13, one
  run at a time, R-R14) with `RollupRecalcErrorHandler` queueing a stopped chunk's records from
  `BatchApexErrorEvent` (R-R14).
- **Flow action and template (R-R12):** `RollupRecalcAction`, the invocable action "Recalculate
  rollups", takes the saved record and its prior values (generic, so it serves any entity) and
  marks targets exactly as a packaged trigger does (R-R11): in the same save when few, queued
  otherwise, and always queued for a record being deleted, since a Flow runs before the delete.
  It does nothing while all automation is paused. `Recalculate_Rollups_Template` is a
  record-triggered Flow template (on Contact, never active) an administrator saves as her own
  copy and points at her entity.

## 14A. Rollup Queue

### Definition

The list of target records waiting for their totals to be recalculated, and of the ones that
could not be. A bulk change (R-R4) writes the records it affected here instead of
recalculating them in the same save, and one background processor works through the list
(`decisions/0082-barncrm-owns-its-rollup-engine.md`). It is also what the Rollup Builder's
"Needs attention" list reads and what its Retry acts on, so one entity serves as queue,
failure list and retry.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The entry's identifier, assigned automatically. |
| Target Entity | text | yes | The entity whose records are listed, for example Account or Fund. |
| Record Ids | long text | yes | The identifiers of the target records to recalculate, at most 200, held as text (R-RQ2). |
| Record Count | integer | yes | How many identifiers Record Ids holds, so "records waiting" is a sum rather than a parse. |
| Definition Ids | long text | no | The identifiers of the Rollup Definitions whose change queued the entry, held as text. Empty means every active definition on the target entity (R-R11). |
| Status | picklist(Pending, Failed) | yes (defaults Pending) | Pending: waiting for the processor. Failed: tried five times without success; waits for Retry. |
| Attempts | integer | yes (defaults 0) | How many times the processor has tried these records. |
| Next Attempt | datetime | no | The earliest time the processor tries these records again after a failure; empty means now. |
| Last Error | long text | no | What went wrong on the last attempt, in plain language first, for the Needs attention list. |

### Relationships

- None. Record Ids, Definition Ids and Target Entity are text, never references (R-RQ2). An
  entry names the definitions that queued it, and only those active ones are recalculated for
  its records; an entry with no Definition Ids (a full run's hand-off, an entry written before
  the attribute existed) recalculates every active definition on its target entity (R-R11).

### Rules

**R-RQ1 Append-only for writers.** A transaction that changes source records inserts entries
(one per target entity, split at 200 identifiers) and never updates or deletes one. Only the
processor updates or deletes entries. Two writers therefore never contend for the same entry.

**R-RQ2 Identifiers as text.** A reference to the target would lock the target record when the
entry is inserted, so a large import touching one household would queue behind itself.
Identifiers held as text lock nothing. The cost is that an entry is not reportable by target;
the Needs attention list resolves the names.

**R-RQ3 How the processor works.** It reads Pending entries whose Next Attempt has passed,
merges and sorts their identifiers, recalculates a slice for the union of the entries'
definitions (R-R11), and deletes the entries it
finished. Target records that failed are written back as a new entry with Attempts increased
and Next Attempt set later each time; after the fifth attempt the entry is Failed. The
processor runs again while Pending entries remain. A second processor started by accident is
harmless, because recalculation recomputes (R-R11). A writer starts a processor only when none
is queued. A waiting processor may start and finish before the writer commits, so a transaction
that inserted entries and queued no processor (one was waiting, it asked earlier with nothing
pending, or its job allowance was used) publishes one `Rollup_Queue_Ready__e`, whose subscriber
asks again after commit; the subscriber, which inserts none, never publishes (ADR-0117,
`0117-rollup-queue-asks-again-after-commit.md`). When automation is paused, or the event cannot
be published, the nightly run, the
end of a pause, Retry and Start now on the Needs attention list start one for the Pending
entries. A save inside a Queueable job never starts
the processor: the platform lets a Queueable queue one job, and that job belongs to the running
job's own next step (the household soft credit recompute, a subscriber's integration). Instead
the transaction publishes one `Rollup_Queue_Ready__e` (publish after commit, however many
entries it wrote), and its subscriber calls `RollupService.startQueuedRecalculation`, which
starts the processor unless one is already waiting (ADR-0100). A job that rolls back publishes
nothing. If the event cannot be published, the entries wait for the next processor a later save
starts, the one a BarnCRM job starts itself when its chain ends, or the nightly run. The
processor's own chain respects the platform's chain depth limit: a run as deep as its chain may
go (the chain's own maximum when one is set, otherwise five, the Developer Edition, trial and
scratch org limit) publishes the same event instead of queuing the next run, so a fresh chain
starts after it commits. It logs nothing: on a busy org it happens every few runs. Before this the refused
link stopped the chain and left Pending entries until the nightly run. A run that stops on
something it cannot catch, such as a governor limit, is handled by its finalizer, which logs it
to the Error Log. Only the records the run was recalculating are charged: they move to a new
entry with one more attempt and the reason in Last Error (Failed after the fifth), and the rest
of each entry it held stays as it was. An entry charged by a stopped run merges only with others
charged the same way, for the same entity and attempts, and a run takes a quarter as many records
per attempt (50, 12, 3, then 1 of a 200 slice), so a record that stops every run holding it ends
Failed alone while the records it shared runs with are recalculated. Entries whose save was
refused (R-RQ4) are already one record each, so their retries merge and run at the full slice. A single record that stopped its run on the query row limit goes to the large
parent route instead (R-RQ6). The finalizer then publishes the same event rather than queuing
the next run itself, because the platform queues at most five jobs in a row from the finalizers
of failed jobs. Before this a stopped run halved the next run's slice and queued it, and a record
too large for any slice left every entry Pending with nothing to process it. A run also takes
records only up to a row budget (60 percent of the rows a transaction may read), estimated as in
R-RQ6, and returns the rest to the queue for the next run uncharged. Rows its recalculation of
one target entity actually read count against the budget in place of their estimate, so an
entity that read more than its estimate leaves less for the entities after it. This protects only
the later entities: an entity's records are recalculated in one call, so its own records are
taken on their estimates alone.

**R-RQ4 Failures are visible.** A Failed entry stays until someone presses Retry (which sets it
back to Pending with Attempts 0) or the nightly full run recalculates its records successfully
(which deletes it). Each processor and nightly run writes one summary entry to the Error Log
(Section 9) when anything failed, so the Hub's error tile sees it. Health Check reports Failed
entries, and Pending entries older than an hour.

**R-RQ5 Written in system mode.** Entries are the engine's own bookkeeping and are written
under ADR-0021, so a gift saved by a user who cannot see the queue still queues its totals.
The engine's automation switch and the global pause (Section 10) stop entries being written
and processed; the nightly run puts the totals right afterwards in Both mode.

**R-RQ6 Large parents are recalculated by a batch.** An aggregate query counts every row it
aggregates towards the rows one transaction may read (50,000), so a record with tens of
thousands of source rows (a General Fund, a large organization donor) cannot be recalculated by
the processor at any slice size (ADR-0116,
`0116-rollup-large-parents-recalculated-by-a-batch.md`). A record's source rows are estimated
as its largest stored COUNT total times the queries its definitions plan; a filtered or fiscal
year COUNT is a floor, and a record with no COUNT to go by is taken as ten rows per query. The
stored totals of every active COUNT definition on the entity count, not only those of the
definitions the run calculates: an entry that names only a SUM or MAX (ADR-0099) otherwise took
a fund with 25,000 allocations as unknown, and its queries stopped the run.
Before a run recalculates its slice, a record estimated at two fifths of that limit or more
(below the run's row budget of three fifths, R-RQ3, leaving room for the run's other queries and
the target records' automation, and for a low estimate) is moved to a new entry and handed to
the large parent batch; a record below it stays in the queue, alone in a run if it must be. A
stored count goes stale while a load adds children faster than the queue recalculates (a fund
stored 3,200 of its 26,102 allocations), so the run also measures what each query of an entity's
recalculation read: before a further query would take the transaction past four fifths of the
limit, taken to read as much as the largest query before it, the recalculation stops with
nothing written and that entity's records in the run go to the batch as an estimated one does. A
single record that stopped its run on the query row limit (R-RQ3) goes to the batch too. No other failure goes there. The batch reads each
planned query's source rows in chunks, runs the query over each chunk's rows only and folds the
partial answers together, which merge exactly as path alternatives do (R-R1; a distinct count or
distinct list keeps one entry per value), then writes each record once, with partial success,
through the same target filters, currency handling and write as any other recalculation (R-R8,
R-R13). It owns the entries it was given: it charges each one attempt as it takes them (Failed
after the fifth), holds them with Next Attempt an hour ahead, renewed with every chunk, deletes
them when the totals are written and releases them with the reason when a chunk stops, so a run
that dies leaves them due again rather than lost. One batch runs at a time: a run starts only
under a lock on the org-level `Rollup_Run_Lock__c` record (created the first time), so two
processors routing records at the same moment cannot both find none running and both start one.
Entries routed while one runs, or when the lock cannot be taken in time, wait two minutes,
uncharged, and are routed again.

### Salesforce implementation

- **Object:** `Rollup_Queue__c`, auto-number Name with format `RQ-{0000000}`, private sharing,
  readable by the BarnCRM Admin permission set and written only by the engine.

| Attribute | API name | Type |
|---|---|---|
| Target Entity | `Target_Object__c` | Text (80) |
| Record Ids | `Record_Ids__c` | Long Text Area |
| Record Count | `Record_Count__c` | Number (0 decimals) |
| Definition Ids | `Definition_Ids__c` | Long Text Area |
| Status | `Status__c` | Picklist: Pending, Failed |
| Attempts | `Attempts__c` | Number (0 decimals) |
| Next Attempt | `Next_Attempt__c` | DateTime |
| Last Error | `Last_Error__c` | Long Text Area |

- **Service:** `RollupQueue`, which writes entries and is the one processor (a Queueable with a
  finalizer); the Rollup Builder's Needs attention list reads and retries entries.
- **Batch:** `RollupLargeParentBatch`, the large parent route (R-RQ6): a batch over the source
  rows of each planned query, Ids only, chained query by query and entity by entity.
- **Custom setting:** `Rollup_Run_Lock__c`, hierarchy, protected, no fields. Its one org-level
  record is the row a large parent run locks before it starts (R-RQ6); the code creates it the
  first time and nothing else reads or writes it.
- **Event:** `Rollup_Queue_Ready__e`, a platform event with no fields, publish behavior Publish
  After Commit, published at most once per transaction by a save inside a Queueable job, or by
  one that queued entries and no processor (R-RQ3).
  `RollupQueueReadyTrigger` subscribes and starts the processor.

---

## 14B. Rollup Settings

### Definition

The BarnCRM Rollup Builder module's own org-wide settings (ADR-0125,
`0125-rollup-builder-module.md`, decision 6). ADR-0017 gives every module package its own
protected hierarchy custom setting, so the two rollup keys Core held on `BarnCRM_Settings__c`
(Section 12) moved here with the engine, with their API names and definitions unchanged. The
values an org stored on the Core object are not carried over: an org that changed either one
sets it again. Their Setting Definition rows name this object in `Settings_Object__c`, so the
settings console shows them in its Rollups section as before.

- **Custom setting:** `Rollup_Settings__c`, hierarchy, protected.
- **Defaults (ADR-0035):** both keys are text, so the field default only fills a record the
  platform creates; the readers in `RollupService` treat blank, and anything outside the
  allowed values, as the shipped value.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Rollup_Mode_Default__c` | picklist(Real-time, Scheduled, Both) | Both | The mode a new rollup definition takes unless the admin changes it. Shown as Instantly, Every night and Both (recommended), as on the definition (R-R4). |
| `Rollup_Processing__c` | picklist(Background, In_Save) | Background | When Real-time and Both totals are recalculated (R-R4): Background (shown as Just after the save (recommended)) queues them in the save and the Rollup Queue recalculates them just after it; In_Save (shown as During the save) recalculates a normal save's totals in it. Blank means Background. |

---

## 15. Import Template

### Definition

A reusable mapping from the columns of a spreadsheet to the entities and attributes they
describe, together with the matching rules and default values that decide whether a row
creates a record or updates one (plan Section 4.9, feature C-14). A template is what lets
Maria load the same payment processor export every month without rebuilding the mapping.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The template's name as the admin sees it, for example "Generic contact list". |
| Description | long text | no | What kind of file this template reads, with an example of its columns. |
| Template Key | text | yes | The stable identifier of this template, matching the shipped default it came from; unique. |
| Column Mapping | long text | yes | The mapping from source column names to canonical targets, held as a mapping document (see R-IT1). |
| Person Matching Rule | picklist(Email exact, Name plus postal code, External ID) | yes | How an incoming row's people are matched to people the org already has before new ones are created (R-IT2). |
| Person Match Field | text | no | Under the External ID person rule, the API name of the field people are matched on, one marked External ID or Unique (R-IT8); empty means the first external identifier the user may read. |
| Organization Matching Rule | picklist(Name exact, External ID) | no | How a row's organization is matched to an organization the org already has; empty means Name exact (R-IT2). |
| Organization Match Field | text | no | Under the External ID organization rule, the API name of the account field organizations are matched on (R-IT8). |
| Several Matches | picklist(Reject the row, Use the most recently changed) | no | What happens when the key a row is looked for by finds more than one record; empty means Reject the row (R-IT9). |
| Use Duplicate Rules | boolean | yes (defaults false) | Whether people and organizations the rule found nobody for, or a one-object row that would create a record, are also matched through the org's active duplicate rules (R-IT16). |
| Default Values | long text | no | Values applied to every row that does not carry its own, held in the same document format. |
| Person Mode | picklist(Contacts, Person Accounts) | yes | Whether a person in this file becomes a Contact or a person Account; defaulted from the detected org shape. |
| Is Package Default | boolean | yes (defaults false) | Marks a template materialized from a shipped default rather than built by the admin. |
| Is Recurring | boolean | yes (defaults false) | Marks a template used for an ongoing feed, so the Hub can show how long it is since the last load. |
| Source Name | text | conditional | The named source of a recurring feed, for example "Monthly processor export"; required when Is Recurring is true. |
| Last Import Date | date | computed | The date a batch using this template last completed, shown on the Hub. |
| Active | boolean | yes (defaults true) | Whether the template is offered in the import wizard. |
| Payment Matching | picklist(Always create, Match or create, Match only, Never match) | no | Whether an imported record pays a scheduled payment it matches (used by modules that load payments; with Giving, a gift matched to a payment the donor already owes); empty means Match or create (R-IT7, R-DM5). |
| Match Date Window Days | integer | no | How many days either side of a scheduled payment's due date a gift may fall and still match it; empty means the org's default (R-IT7, Section 21A). |
| Match Amount Tolerance | decimal | no | How far a gift's amount may differ from a scheduled payment's expected amount and still match it; empty means the org's default (R-IT7, Section 21A). |
| Target Object | text | no | The API name of the one object this template loads, as describe gives it; empty for a template that loads people and organizations (R-IT12). |
| Load Operation | picklist(Insert, Update by record Id, Update by a matching field, Upsert by external ID, Delete by record Id) | no | What a row of a one-object template does; empty means Insert (R-IT12, R-BD7). |
| Load Match Field | text | conditional | Under Upsert by external ID, the API name of the target object's External ID field rows are found by; under Update by a matching field, the API name of the text, email or phone field they are found by; required under both (R-IT12). |
| Lookup Not Found | picklist(Reject the row, Leave it empty) | no | What a row of a one-object template does when a lookup column finds no record; empty means Reject the row (R-IT13). |
| Related Object | text | no | The API name of the object a one-object template also creates related records of, as describe gives it; empty for none (R-IT17). |
| Related Parent Field | text | conditional | The API name of the Related Object's lookup field that points at the Target Object; required with a Related Object (R-IT17). |

### Relationships

- **Import Batch to Import Template**, many to one: every batch records the template it
  ran with, so a result can still be explained after the template changes.

### Rules

**R-IT1 Mapping document.** Column Mapping and Default Values are held as one document
per template, in the format below, for the same reasons the rollup filter is (R-R2): a
mapping is built and saved as one unit in the two-column picker, and is shared as a
single JSON file in `data/import-templates/` so the community can contribute
processor-specific templates (plan Section 4.9).

```
{
  "version": 1,
  "columns": [
    { "source": "Donor Email", "target": "Contact1.Email" },
    { "source": "Gift Amount", "target": "Gift.Amount__c" },
    { "source": "Fund", "target": "Allocation.Fund" }
  ],
  "defaults": [
    { "target": "Gift.Type__c", "value": "Check" }
  ]
}
```

Targets are written as `Entity.Attribute` using the row entity names in R-IR1, so a
template can be read without knowing the object model. A one-object template (R-IT12) uses
the one entity `Record`, whose attributes are the target object's field API names, and a
lookup column may carry `"lookupField"`, the parent field it names its parent by (R-IT13):

```
{ "source": "Program", "target": "Record.Program__c", "lookupField": "Program_Code__c" }
```

Any column may also carry `"transforms"`, the steps that change its values as they load
(R-IT15).

**R-IT2 Matching rules in plain language.** The wizard states what each matching rule
does and what it risks, for example that "Name plus postal code" merges two people who
share a name at one address. No rule is offered without that sentence (plan Section 2.3). People and organizations have
a rule each (ADR-0068, `0068-import-matching-per-entity-and-per-file-values.md`): a person by
Email exact, Name plus postal code, or External ID; an organization by Name exact (compared
ignoring case and surrounding spaces) or External ID, and only among organization accounts.
The organization rule applies only where the mapping names an organization.

**R-IT8 A chosen matching field.** Under External ID the template names the field: one the
object marks External ID or Unique, holding text or an email, that the importing user may
read. For people it is a Contact field, or an Account field where Person Mode is Person
Accounts; for organizations it is an Account field. The row gives the value through a column
mapped to that field on the entity (for example `Contact1.Member_Number__c` or
`Organization.Charity_Number__c`). The field is checked against describe when the template is
saved and again when rows are matched; one that no longer qualifies matches nobody and the
run log says so. An empty Person Match Field means the first external identifier field the
user may read, which is how templates saved before C-32 matched. A row with no value in the
field is not matched and its person or organization is created (an organization only with a
name).

**R-IT9 Several matches.** When the key a row is looked for by finds more than one record
(R-IB12 says which key), Several Matches decides: Reject the row, the default, with a message
naming the problem; or Use the most recently changed record, by Last Modified Date as the chunk
reads it, the later created winning a tie. Either way the row's Several Matches box is ticked
(Section 17) and the run log says once that such rows exist. It applies to people and
organizations alike. A lookup stopped at its row cap is not a several-matches case: its keys
find nobody alone, as R-IB12 describes.

**R-IT10 A record ID in the file.** A column can be mapped to a person's or the
organization's Salesforce record ID (`Contact1.Id`, `Contact2.Id`, `Organization.Id`; ADR-0069,
`0069-import-record-id-matching-and-match-only.md`). A row giving one is matched to that record
and no rule is asked: the ID must be a valid record ID of the object the entity is stored on
(Contact, or Account in Person Accounts mode, for a person; Account for an organization), the
record must exist and be visible to the importing user, a person account must have a person
record type and an organization the Organization record type. A row whose ID fails any of these
is rejected with the reason, and nothing is created for it: an ID given but not found never
creates a record. The ID itself is never written to a field. A blank ID cell is no ID, and the
row is matched by its rule. A value for every row of a file may not give a person's ID (R-IB14).

**R-IT11 Custom fields on people and organizations.** A column can be mapped to any field of
the person's or the organization's object that the importing user may create or edit, by its
API name (for example `Contact1.Member_Since__c` or `Organization.Region__c`). The wizard offers
these from describe: fields the user may read and create or edit, not formula, roll-up, auto
number, lookup, compound address or location fields, not system fields, not the package's own
bookkeeping fields (the import batch tag, the sample data marks, the household fields the
household automation writes), and not a field the fixed column list already offers. For people
it lists Contact fields in contact terms, which R-IT3 translates in Person Accounts mode; for
organizations it lists Account fields that are not person account fields. Values are written
as the other attributes are (R-IB12): read as the field's type the one way every import reads
it (ISO or the user's locale for dates and date times, numbers as spreadsheets export them
in the user's locale, with currency symbols or codes, grouping marks and a minus sign or
accounting brackets for a negative, refusing a value whose decimal mark cannot be told, times), never
clearing a stored value with a blank, and a field the user may not write is skipped and named in
the run log. A value the field cannot take (unreadable, or text longer than the field) rejects
the row with the field and value named, as a one-object load does (R-IT12). A matched record
counts as changed only where a value differs as the field holds it (numbers as numbers, dates as
dates) and text exactly: a correction of capitals is a change.
A checkbox reads `true`, `yes`, `y`, `1`, `x`, `checked`, `on` or `t` as ticked and `false`,
`no`, `n`, `0`, `off` or `f` as cleared, ignoring case and surrounding spaces; one reading
serves every import, people and one-object alike. Any other value is never read as cleared: a
people import skips that field on that row, notes the row, the column and the value in the run
log, and loads the rest of the row (a one-object load rejects the row, R-IT12).

**R-IT12 A template that loads one object.** A template with a Target Object loads each row
as one record of that object (ADR-0080, `0080-import-load-one-object.md`), through the same
batch, dry run, results, journal and undo as any import, in the running user's own access. The
object and every field come from the running user's describe, when the template is saved and
in every chunk. Load Operation decides what a row does:

- **Insert** creates one record per row.
- **Update by record Id** changes the record named by the row's `Record.Id`. An ID that is not
  a valid ID of the target object, or names no record the user can see, rejects the row, and
  nothing is created for it.
- **Update by a matching field** changes the record whose Load Match Field (any text, email or
  phone field of the object that the user may read and filter on) holds the row's value,
  compared ignoring case. A row with no value in the field, or whose value no record holds, is
  rejected, and nothing is created for it. A value several records hold follows Several Matches
  (R-IT9). The field is subject to the large object guard (R-IT13).
- **Upsert by external ID** finds the record whose Load Match Field (a field the object marks
  External ID, holding text or an email, that the user may read) holds the row's value,
  compared ignoring case; it changes that record, or creates one when none holds the value. A
  row with no value in the field is rejected. A value several records hold follows Several
  Matches (R-IT9).
- **Delete by record Id** deletes the record named by the row's `Record.Id`, through the bulk
  delete job rather than the loader's save (R-BD7).

The loader reads the existing records itself, in user mode, and never calls the platform's
upsert, so the dry run decides exactly as the commit will and the journal holds each value
before. An update writes only the values that differ from the record's, and a row that changes
nothing is Matched. A value its field cannot take (a date or number that cannot be read, a
checkbox value that is neither ticked nor cleared under R-IT11, text longer than the field) rejects the row, naming
the field and the value, because a row is one record. A row naming the same record as an
earlier row of the file (the same ID or Load Match Field value) is rejected wherever the file's chunks
fall, through a digest in its Processor Key (Section 17). Under Match only (R-IB15) a row that
would create a record is rejected. A value for every row of the file (R-IB14) may not be the
record ID or the Load Match Field. Each row's resulting record is written to its Resulting
Record. A row a save refuses carries the platform's words. Account and Contact load by Update
by record Id or Update by a matching field only (R-IT14).

**R-IT13 Lookup columns.** A column mapped to a lookup field of the target object names its
parent by the column's `lookupField` (R-IT1): the record ID when it is empty or `Id`, or else
the parent's name field or any of the parent's text, email or phone fields that the user may
read and filter on, compared ignoring case and surrounding spaces. A lookup that can point at
more than one object is read by record ID only. Parents are found in user mode, one query per
column and chunk, and a parent the user cannot see is not found. When none is found, Lookup Not
Found decides: Reject the row (the default), naming the column and the value, or Leave it empty,
loading the rest of the row and saying once in the run log that lookups were left empty. A value
that finds several parents follows Several Matches (R-IT9) and ticks the row's Several Matches.

The large object guard: a field the platform indexes (the record ID, the name field, a field
marked External ID or Unique, and a standard Email field) may always be matched on. Any other
field a lookup or the template's record key names is matched only when its object holds at most
100,000 records the user can see, counted in user mode with a capped count, once per object per
transaction; above that the template is refused (dry run and every chunk alike), naming the
field and the object, because an unindexed search of a large object is slow and can time out.

**R-IT14 What a load may write.** An object may be loaded only when all of these hold, decided
from describe at run time, so a new object is judged without a code change:

1. It is a custom object, not a custom setting, custom metadata, platform event, big object or
   external object; or a standard object that describe calls searchable and queryable.
2. Its name does not end in Share, History, Feed or ChangeEvent.
3. It is not a Salesforce setup or security object: User, Group, GroupMember, QueueSobject,
   Profile, UserRole, PermissionSet, PermissionSetAssignment, PermissionSetGroup,
   PermissionSetGroupComponent, PermissionSetLicenseAssign, SetupEntityAccess,
   ObjectPermissions, FieldPermissions, RecordType, Organization, UserLicense,
   UserPackageLicense, NetworkMember.
4. It is not the package's own bookkeeping (`Import_Template__c`, `Import_Batch__c`,
   `Import_Row__c`, `Import_Journal__c`, `Error_Log__c`, `Setting_Change__c`,
   `Automation_Setting__c`, `Rollup_Definition__c`), not `Household_Member__c` (membership is
   written only through the household service, R-M5), and not an object a dependent package
   names through the data protection seam (`DataProtectionExtension`; Giving names receipts,
   receipt runs, receipt number sequences, acknowledgments and acknowledgment runs).
5. The user can read it and query it, and can create records of it for Insert, edit them for
   either Update, or both for Upsert.

Account and Contact may be loaded only by Update by record Id or Update by a matching field: people, households and
organizations are created by a people template, which builds households (R-IR1a). Delete by
record Id (R-BD7) is not a load and follows the bulk delete's rules instead.

These fields are never written, whatever the file holds: the fields the platform keeps (Id,
created and modified stamps, system mod stamp, last activity, viewed and referenced dates),
formula and auto number fields, every Rollup Definition target on the object, the batch tag
(R-IB3), the sample data marks, any package field whose name ends in Last Calculated, the
household fields the household automation keeps on accounts and contacts (greetings, member
count, custom name, household role, primary contact, primary affiliation), and a household's
Name. A column mapped to one is
named once in the run log and skipped; so is a field the user may not create or edit, asked of
describe for each row according to whether it creates or updates.

**R-IT17 Related records in the same file.** A one-object template with a Related Object and a
Related Parent Field (ADR-0111, `0111-load-related-records.md`) also creates records of the
Related Object from the same rows. Its columns are mapped to `Related.<field API name>`, with
the same lookups (R-IT13), value reading, access and never-written rules as `Record` columns
(R-IT12, R-IT14); a column mapped to the Related Parent Field is skipped, because the load fills
it. The Related Object must be one a load may create (R-IT14, Account and Contact never), the
field a lookup or master-detail of it pointing at the Target Object only, which the user may
create; else the template is refused, as is Insert, since the parent key must be a stored
field:

- **Parent key.** The row's record key (R-IT12): its record ID under Update by record Id, its
  Load Match Field value under the other two operations. The first row of the pass with a key is
  the parent row and loads its `Record` columns; a later row with the same key (by digest,
  wherever the chunks fall) adds a related record to that parent and its `Record` columns are
  not loaded, instead of being rejected as a repeat.
- **Order.** In each chunk the parents are found and saved first, then the related records are
  created, each with the Related Parent Field set to its parent. A parent row is always the
  earliest row of its key, so it is in the same chunk as its related rows or an earlier one. A
  later chunk finds an earlier chunk's parent by its key in user mode, under the template's
  Several Matches (R-IT9).
- **Partial failure.** A parent row's Processor Key holds a digest that says whether its
  parent was saved. A related row whose parent row was rejected is rejected with "parent
  failed", and nothing is created for it. A related record the platform refuses rejects its
  row; the parent stays. A row without a key is rejected (R-IT12). Under Match only (R-IB15) a
  related record, which always creates, rejects its row.
- **Results.** A row's Status is its parent's outcome (Matched for a later row of the key),
  unless the row was rejected for its parent or its related record; its Related Status says
  what its related record did or would do; its Second Resulting Record holds the related
  record. The run log counts the related records created and rejected.
- **Undo.** Each chunk journals its related records on Created pages written after its parents'
  pages, so the undo's Created pass (newest page first) deletes related records before the
  parents they point at; a related record made by the commit never counts as something its
  parent gained (R-IB9).

**R-IT15 Changing a column's values (the transform document).** A column of the mapping
document may carry `"transforms"`, an ordered list of at most 10 steps that change the
column's value before it is matched or written (ADR-0081, `0081-data-transform-document.md`):

```
{ "source": "Last", "target": "Contact1.LastName",
  "transforms": [ { "op": "trim" }, { "op": "proper" } ] }
```

| `op` | Parameters | What it does |
|---|---|---|
| `trim` | none | Removes leading and trailing white space and turns each run of white space into one space. |
| `upper`, `lower` | none | Every letter as a capital, or as a small letter. |
| `proper` | none | A capital for each letter that starts a word (a run of letters, digits and apostrophes), every other letter small. |
| `replace` | `text` (required, at most 255 characters), `replaceWith` (at most 255), `matchCase` (default false), `wholeValue` (default false) | Replaces each occurrence of `text`, read as literal text, with `replaceWith`; under `wholeValue`, replaces the value only when the whole value equals `text`. |
| `ifBlank` | `value` (required, at most 255) | The value, when the value so far is blank. |
| `append` | `columns` (1 to 5 source column names of the same row), `separator` (at most 10, default one space) | Adds the named columns' values after the value so far, leaving blank ones out, joined by the separator. |
| `date` | `dateOrder`: `MDY`, `DMY` or `YMD` | Reads the first three numbers, separated by any characters that are not digits, in that order (a two-digit year below 50 is 20xx, otherwise 19xx) and writes the date as `YYYY-MM-DD`; a value that is not a real date under the order is left unchanged. |
| `map` | `pairs`: 1 to 100 of `{ "text", "value" }` (`text` required, each at most 255), `otherwise` (at most 255), `matchCase` (default false) | The `value` of the first pair whose `text` equals the trimmed value; an unmatched value that is not blank becomes `otherwise` when it is not blank, and is kept otherwise. A blank value stays blank. |
| `ifThen` | `test`: `equals`, `contains` or `blank`; `text` (required unless `blank`, at most 255), `value` (at most 255, empty clears), `otherwise` (at most 255), `matchCase` | When the trimmed value equals `text`, contains it, or is blank, the value becomes `value`; when not, it becomes `otherwise` if that is not blank, and is kept otherwise. Only the value so far is tested, never another column. |
| `part` | `separator` (required, 1 to 10), `position` (1 to 50), `fromEnd` (default false) | Splits the value on the literal separator and keeps part `position`, counted from the start or the end, trimmed; blank when there is no such part. |
| `first`, `last` | `count` (1 to 255) | The first or last `count` characters; a shorter value is kept whole. |
| `shiftDate` | `amount` (a whole number, at most 36,600 days or 1,200 months either way), `unit`: `days` or `months` | Reads the first three numbers year first (so `2025-12-31` and a stored date with a time both read), adds the amount and writes `YYYY-MM-DD`; adding months keeps the day where the month has it, otherwise the month's last day. A value that is not a date, or a result outside the years 1700 to 4000, is left unchanged. |
| `today` | `whenBlank` (default false) | Today's date as `YYYY-MM-DD` in the running user's time zone; under `whenBlank`, only when the value so far is blank. |

The steps from `map` on were added by ADR-0112 (`0112-more-transform-steps.md`); a document
whose steps may use them carries `"version": 2` (the mapping document of R-IT1 and the bulk
update definition of R-BU1). A reader that does not know an `op` skips that step, as below.

Steps run in order, before values for every row (R-IB14): a step's output that is blank is
filled by a file or template value like any blank cell. A document is checked when it is saved
(an unknown `op`, a missing or oversized parameter, more than 10 steps, or an `append` naming
no column refuses the save with the column named); a stored step that fails the check is skipped
on read, as the rest of R-IT1 is forgiving. No step evaluates an expression, calls code, reads a
record or uses a pattern the administrator typed: `replace` quotes its text. The engine is
`DataTransform` in Core, which knows nothing of imports: it takes a value and the other values
of the row by name, so bulk update (C-35) can apply the same steps to a record's fields.

**R-IT16 Matching through the org's duplicate rules.** A people template with Use Duplicate
Rules ticked also asks the org's active duplicate rules (ADR-0081,
`0081-data-transform-document.md`) about each person and organization of a chunk that its rule
(R-IT2, R-IT8) found nobody for, that no record ID names (R-IT10), that no earlier row of the
pass is creating (R-IB12) and whose row is not already rejected. The row's values for the
entity, as stored names (R-IT11), are set on an unsaved record of the entity's object (Contact,
or Account in Person Accounts mode, for a person; Account for an organization), copying only
fields the user may read and create that hold text, an email, a phone, a URL or a picklist value,
and passed to the platform's duplicate matcher, at most 50 records a call. Matches of another
object are ignored. The matched identifiers are then read in user mode, keeping only records the
user can see and, for accounts, of the entity's kind (a person record type for a person account,
the Organization record type for an organization). One record kept matches; several follow
Several Matches (R-IT9). A row whose two people are matched to one record is rejected. In a dry
run an organization an earlier chunk would create is not asked about (the commit finds it by its
key). A row matched this way has Matched By Duplicate Rule ticked (Section 17) and the run log
says that such rows exist. The active rules are read first (`DuplicateRule`, user mode): when
the object has none the user can see, or the matcher raises, the entity is matched by its rule
alone and the run log says so; nothing is rejected for it. A matcher failure is written to the
Error Log only when a rule was known to be active.

For a one-object template (R-IT12) with Use Duplicate Rules ticked, the rules are asked only
under Insert and Upsert by external ID, and only about a row that would create a record: a
record ID or upsert key match always wins and is never asked about. The row's own values (not
its lookups), as the target object's fields, go on an unsaved record of the target object (of the
row's record type when it gives one) through the same matcher, 50 a call, read back in user
mode with any record type. One record kept is updated with the row instead of a record being
created, and the row has Matched By Duplicate Rule ticked; several follow Several Matches
(R-IT9). Records that rows of an earlier chunk of the pass created or loaded are set aside
before the choice, so the commit decides as the dry run (an earlier update changes a record's
LastModifiedDate, and a created record was never there for the dry run); a row whose matches
were all loaded by earlier rows, or whose one match another row of the chunk loads, is rejected,
as a repeated key is (R-IT12). Field changes an earlier chunk of the commit makes can still
change what the rules match for a later row; that limit is documented. Under Upsert, a row
matched to a record whose key field holds a different non-blank value is rejected rather than
overwrite that key; a blank key is filled in. With no active rule, the rows create and the run
log says so; when a rule is active (or the rules cannot be read) and the matcher fails, the
asked rows are rejected rather than risk a duplicate. The wizard offers the box for a one-object
template only under those two operations.

**R-IT18 Rows to load: skip rows and one row per key.** The R-IT1 document may carry
`"skipRows"`, at most 5 rules `{ "column", "test", "text" }` whose `test` is `equals`,
`contains` or `blank` (`text` required unless `blank`, at most 255), and `"uniqueBy"`, at most
5 column names (ADR-0113, `0113-import-row-rules.md`). Both read a row's cells as uploaded,
before any column change (R-IT15), trimmed and ignoring capitals. When a page of the file is
staged, a row any rule matches, and a row whose `uniqueBy` cells (not all empty) equal an
earlier row's, is staged with Status Skipped and the reason in Error Message; every other row
with a key keeps the key's digest in Row Key, which later pages look up. No pass reads a
Skipped row, so the dry run and the commit see the same rows, and the run log counts them. A
mapping whose rules are incomplete or too many is refused on save; a stored one that fails the
check skips nothing.

**R-IT19 An empty cell that clears.** A `Record` column (R-IT12) may carry `"blankClears":
true`. Under Update or Upsert, when that column's cell is empty after values for every row
(R-IB14) have filled blanks, the record's field is cleared if it holds a value: an ordinary
change, compared, journaled with the value before (R-IJ3) and put back by undo. A record the
load creates is not affected. A required field or a checkbox is never cleared, and the run log
names it once. The run log counts the values cleared, or that a commit would clear in a dry
run. A people template ignores `blankClears`: a blank never clears a field there.

**R-IT3 Person mode.** Person Mode is proposed from the org shape detected by the Setup
Assistant: Person Accounts where the org uses them, Contacts otherwise. The admin can
override it per template, and the processor resolves the person references in R-IR1
accordingly. A template names a person's attributes in contact terms whatever the mode. In
Person Accounts mode each is written to, compared with and read from the account field the
org has for it: the contact name prefixed with Person for a standard field (Email to
PersonEmail, MailingStreet to PersonMailingStreet, HasOptedOutOfEmail to
PersonHasOptedOutOfEmail, DoNotCall to PersonDoNotCall, Birthdate to PersonBirthdate), a
contact custom field's `__pc` form, and otherwise the account field of the same name
(FirstName, LastName, Salutation, Phone). The person fields are found in the org's describe
and never named in the source (Section 4.2 of the plan, ADR-0013).

**R-IT4 Upgrade safety.** Templates with Is Package Default true are materialized from
`Import_Template_Default__mdt` on install, on every upgrade (each package's post-install
script adds the templates it ships, D-41) and on "Restore defaults", matched by Template
Key, and are never overwritten once the admin has edited them (ADR-0006). A shipped template
the admin deleted is added again by the next upgrade; switching it off keeps it out of the
list.

**R-IT6 Recurring sources are shown, not fetched.** A template the administrator marks Is
Recurring names its feed in Source Name, for example "Monthly processor export", and Source
Name is required while Is Recurring is true. The Hub lists every active recurring template
with its source and its Last Import Date, oldest first and "never" for a source not yet
loaded, so Maria can see which feed she has not loaded this month (plan Section 4.9, "Ongoing
imports"). Marking a template recurring changes nothing about how a file is imported: the
file is still uploaded, dry run and committed by a person. Nothing loads a file on a
schedule, because an import nobody watched is an import nobody checked before it wrote.

**R-IT7 Donation matching values live on the template, and only Giving reads them.** A
template that loads gifts carries how its gifts are matched to scheduled payments
(Section 25N, R-DM1 to R-DM6): the behaviour, the date window and the amount tolerance. They
are Core attributes because a package cannot add attributes to another package's object
(ADR-0014), and they are plain values, never references, so Core can hold them without
knowing what they mean. The wizard shows them only when a gift processor is installed and
the mapping loads a gift; an empty value means the org's default (ADR-0052). A commit does not
read them: it runs under the values its dry run recorded on the batch (R-IB11, R-DM7), so a
template edited after the dry run changes the next dry run, not the commit.

**R-IT5 What ships.** Core ships the generic contact list template (v0.2); Giving ships the
generic gift list template. The migration templates (v0.5) are rows of the same type, and
all of them ship from Giving, the way Giving ships its rollup definition defaults, so they
are created only in an org that has Giving. That includes the two that load only people,
because they name nonprofit products, which Core shows only where they apply (rule 5), and
detecting the old product would be the wrong gate: a migration usually goes into a fresh org where it is
not installed (ADR-0062). Each has a sample export in
`docs/admin-guide/samples/` that `check-custom-metadata.py` compares with its headings.

| Template Key | Package | Reads |
|---|---|---|
| `npc_person_accounts` | Giving | An export of Nonprofit Cloud person accounts |
| `npc_gift_transactions` | Giving | An export of gift transaction designations whose donor is a person, one row per designation |
| `npc_organization_gifts` | Giving | The same export whose donor is not a person |
| `npc_undesignated_gifts` | Giving | An export of gift transactions with no designation |
| `npsp_contacts` | Giving | An export of NPSP contacts |
| `npsp_payments` | Giving | An export of paid NPSP payments whose opportunity's account is individual |
| `npsp_organization_payments` | Giving | The same export whose account is not individual |

A migration template is a mapping document and nothing else: its column headings are the
other system's API names as a Data Loader export heads them, held as data, so no package
gains a metadata or compile-time reference to the source objects (ADR-0013). They are new
shipped-default rows, not new attributes. One template reads one export shape, because an
import saves the file's own columns back to the template it used (admin guide, "Migrating
from Nonprofit Cloud", section 5).

### Salesforce implementation

- **Object:** `Import_Template__c`.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Template Key | `Template_Key__c` | Text, External Id, unique |
| Column Mapping | `Column_Mapping_JSON__c` | Long Text Area |
| Person Matching Rule (labelled Matching Rule before v0.7) | `Matching_Rule__c` | Picklist: Email exact, Name plus postal code, External ID |
| Person Match Field | `Person_Match_Field__c` | Text (255) |
| Organization Matching Rule | `Organization_Matching_Rule__c` | Picklist: Name exact, External ID |
| Organization Match Field | `Organization_Match_Field__c` | Text (255) |
| Several Matches | `Several_Matches__c` | Picklist: Reject the row, Use the most recently changed |
| Use Duplicate Rules | `Use_Duplicate_Rules__c` | Checkbox |
| Default Values | `Default_Values_JSON__c` | Long Text Area |
| Person Mode | `Person_Mode__c` | Picklist: Contacts, Person Accounts |
| Is Package Default | `Is_Package_Default__c` | Checkbox |
| Is Recurring | `Is_Recurring__c` | Checkbox |
| Source Name | `Source_Name__c` | Text |
| Last Import Date | `Last_Import_Date__c` | Date |
| Active | `Active__c` | Checkbox |
| Payment Matching (labelled Donation Matching, API name `Donation_Matching__c`, before v0.6) | `Payment_Matching__c` | Picklist: Always create, Match or create, Match only, Never match |
| Match Date Window Days | `Match_Date_Window_Days__c` | Number (3, 0) |
| Match Amount Tolerance | `Match_Amount_Tolerance__c` | Currency (16, 2) |
| Target Object | `Target_Object__c` | Text (255) |
| Load Operation | `Load_Operation__c` | Picklist: Insert, Update by record Id, Update by a matching field, Upsert by external ID, Delete by record Id |
| Load Match Field | `Load_Match_Field__c` | Text (255) |
| Lookup Not Found | `Lookup_Not_Found__c` | Picklist: Reject the row, Leave it empty |
| Related Object | `Related_Object__c` | Text (255) |
| Related Parent Field | `Related_Parent_Field__c` | Text (255) |

- **Shipped defaults:** `Import_Template_Default__mdt` (Section 13).
- **Service:** `ImportTemplateService` (materialization and save), `ImportTemplateSelector`,
  `ImportMapping` (the mapping document in R-IT1), `ImportColumnLibrary` (the known column
  names automatic mapping suggests from), LWC `importWizard` (where a template is marked
  recurring), `HubController` and LWC `hubRecurringFiles` (the recurring sources list, R-IT6).
  One-object templates (R-IT12 to R-IT14): `ImportObjectSchema` (the objects, fields, keys and
  parents describe offers, and reading a value as its field's type), `ImportObjectLoader` (one
  chunk), `DataProtectedFields` with the `DataProtectionExtension` seam and
  `DataProtectionExtensions` (what a load never writes), LWC `importLoadOptions`.
  Column changes (R-IT15): `DataTransform` (the engine, shared with bulk update), LWC
  `importColumnTransforms`. Duplicate rules (R-IT16): `ImportDuplicateRuleMatcher`.

---

## 16. Import Batch

### Definition

One data job: a file import (one upload: the file, the template it was read with, what
happened, and the log of it) or, from v0.7, a bulk update (C-35, Section 29E: the query and the
changes, and what happened). An import is the unit an administrator dry-runs, commits, and in
v0.5 undoes; a bulk update is committed when it starts and is undone the same way
(plan Section 4.9, ADR-0047).

Labels (ADR-0047): the object reads **Data Job** (plural **Data Jobs**, record name **Job
Number**) and the lookups to it from Import Row and Import Journal **Data Job**. The tab and
its app page keep the label **Import** (owner decision 2026-10-13: "Import is more accurate").
The API names (`Import_Batch__c`, the `Import` tab and flexipage, the lookup fields) are
unchanged.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The batch's identifier, assigned automatically. |
| Import Template | reference(Import Template) | yes | The mapping this batch was read with. |
| File Reference | text | yes | The identifier of the uploaded file stored as a Salesforce File, so the original can be downloaded again. Empty when the file was over 2.5 MB or could not be saved; the import still runs. |
| File Name | text | yes | The name of the file as the admin uploaded it. |
| Status | picklist(Draft, Parsing, Dry run, Dry run complete, Committing, Trial complete, Complete, Retrying, Failed, Undoing, Undone, Undo failed) | yes | Where this batch has got to. Retrying: a committed import is taking in its fixed rejected rows (R-IB17). |
| Is Dry Run | boolean | yes (defaults true) | Whether this pass only previewed what would happen; a committed batch has run at least one dry run first. |
| Row Count | integer | computed | How many rows the file contained. |
| Rows Created | integer | computed | How many rows created at least one new record. |
| Rows Updated | integer | computed | How many rows updated an existing record. |
| Rows Matched | integer | computed | How many rows matched an existing record and changed nothing. |
| Rows Rejected | integer | computed | How many rows failed and appear in the exceptions file. |
| Run Log | long text | no | The plain-language log of the run, including the reason for a failure. |
| Started At | datetime | computed | When processing began. |
| Completed At | datetime | computed | When processing finished, successfully or not. |
| Chunk Size | integer | yes | Rows per chunk for this run, defaulted from the org's import chunk size. |
| Undo Deadline | datetime | no | The end of the window in which this batch can be undone, stamped at commit from the org's undo retention setting (R-IB7). |
| Committed By | reference(User) | no | The user who committed the batch, empty while it is a dry run. |
| Expected Count | integer | no | The number of rows the administrator expects the file to hold, a control total checked by the dry run (R-IB10). |
| Expected Amount | decimal | no | The total the administrator expects the file's gift amounts to add up to, a control total checked by the dry run (R-IB10). |
| File Amount | decimal | computed | The total of the file's gift amounts as the last pass read them, written only when an entity processor reads amounts (R-IB10). |
| Processor Settings | long text | computed | The settings the entity processor ran the last dry run under, as a document only that processor reads; the commit runs under them (R-IB11). |
| Template Snapshot | long text | computed | The template as the last dry run started with it; that dry run and the commit run under it (R-IB1). |
| Pass Number | integer | computed | How many dry runs and commits have been started on this batch; the current one is the latest (R-IB13). |
| Job Id | text | computed | The job running the current dry run or commit, so a pass still running can be told from one the platform aborted (R-IB13). |
| File Values | long text | no | Values applied to every row of this file that does not carry its own, held as the defaults half of a mapping document (R-IT1, R-IB14). |
| Match Only | boolean | yes (defaults false) | When true, this file only matches: a row whose person or organization matches no record is rejected rather than creating one (R-IB15). |
| Operation | picklist(Import, Update, Delete) | yes (defaults Import) | What kind of data job this is: a file import, a bulk update (R-BU1) or a bulk delete (R-BD1). Empty on a batch created before v0.7, which reads as Import. |
| Bulk Update Definition | long text | conditional | For a bulk update, the query document, the changes and the confirmed count it ran with (R-BU1); for a bulk delete, the query document and the confirmed count (R-BD1); empty for an import. |
| Rows Deleted | integer | computed | How many records a bulk delete deleted (R-BD3); empty for any other data job. |
| Trial Rows | integer | computed | How many of the file's first rows a trial import committed (R-IB16); empty when the file was committed whole. |
| Retry After Row | integer | computed | While a retry of the import's rejected rows is open, the highest row number before it: the fixed rows are numbered after it, and the retry's dry run and commit read only them (R-IB17). Empty otherwise. |

### Relationships

- **Import Batch to Import Row**, one to many, and the rows are deleted with the batch.
- **Import Batch to the records it created**, one to many, through the Created By Import
  Batch reference that Household, Contact, Organization, and Gift each carry (R-IB3).

### Rules

**R-IB1 Dry run first.** A batch is committed only after a dry run has completed against
the same file and template, and the dry run makes the same resolution decisions the
commit will make. The preview counts and the downloadable exceptions file come from the
Import Row records the dry run wrote. A dry run is refused on a batch that has started a
commit, or is in any undo status: a dry run over a committed batch would mark it a dry run
(so it could never be undone), clear its completion time, and a second commit would move its
undo window. "The same template" means the template as the dry run read it: when a dry run
starts, the batch records the template (its mapping, values for every row, matching rules and
person mode) as Template Snapshot, every chunk of that dry run and the commit after it run
under the snapshot, and an edit to the template since changes the next dry run and not the
commit. A batch with no snapshot (one previewed before this rule) runs under the template.
A row is checked in full (its people matched and validated) before any record it names is
created, so a row rejected for its person creates no organization, in the dry run as in the
commit; a row whose save fails part way keeps what was saved and points at it.

**R-IB2 Chunked and asynchronous.** Rows are processed in chunks of Chunk Size in Batch
Apex, with progress visible on the batch record, so a file of hundreds of thousands of
rows completes without the admin watching a spinner (plan Section 4.9).

**R-IB3 Batch tagging.** Every record a batch creates carries a Created By Import Batch
reference to it. This is what makes undo possible in v0.5 without journaling creations,
and it is what lets an admin answer "where did these 400 households come from" today. The
reference exists on Household and Organization (both Account record types), on Contact,
and on Gift. A household is made by the household automation rather than by the import, so
the import tags it straight afterwards, and only when the household was made for a person
this import created: a household an existing person already had is never tagged.

**R-IB4 Idempotence per row.** Re-running the same file with the same template matches
rather than duplicates, given the same matching rule. The External ID matching rule is
the one that guarantees this for gift feeds.

**R-IB5 Failure is partial, not silent.** A row that fails does not roll back the batch.
It is recorded on its Import Row with a message an administrator can act on, counted in
Rows Rejected, and written to the Error Log where the cause was an exception (R-E1).

**R-IB6 Undo.** Undo Deadline is written from v0.2 so that the window is known from the
first batch. The undo action itself, and the journal of updates it needs, are C-19 in v0.5
and are specified in R-IB7 to R-IB9 and Section 17A.

**R-IB7 The undo window is stamped, not computed.** At commit, Undo Deadline is written as
the commit time plus `Import_Undo_Retention_Days__c`, for a commit that failed part way as
well as one that completed, because the chunks that ran did write. It is read from the batch from then
on, so lengthening the setting does not reopen an import whose window has closed and
shortening it does not close a window an administrator was told they had. An undo asked for
after the deadline is refused, in a sentence naming the date it passed.

**R-IB8 Undo is scoped to one named batch, counts before it deletes, and runs once.**

1. **One batch, named by its identifier.** Every query the undo makes is filtered by the
   Created By Import Batch reference equal to one bound batch identifier, or by the journal's
   own reference to that batch. Nothing in the undo path filters on a checkbox, a date range,
   a status, a name or a user to decide what to delete, and there is no undo of more than one
   batch. A flag can be true of records nobody meant to include; a batch identifier cannot.
2. **Counted, shown, then confirmed.** The first step counts what carries the tag, by kind
   (people, households, organizations, and each object an entity processor tags, R-IB9), adds
   the records a one-object load journaled as created (R-IT12, Section 17A) under that object's
   plural label, and shows those numbers with the batch's name and file name. The undo starts only when the number the person confirms is still the number
   counted, so it can only delete a set somebody has seen the size of.
3. **Once.** The batch's status moves from Complete to Undoing inside a locked read of the
   batch, so a second request, while the first runs or after it has finished, is refused
   rather than queued. A dry run, or a batch already Undone, is refused the same way. An
   undo that stopped on an unexpected error ends Undo failed and may be run again: a record
   it already deleted no longer carries the tag, and a value it already put back is left
   alone. A chunk the platform stopped (a governor limit cannot be caught) counts as an
   error: the undo reads its job's error count when it finishes and ends Undo failed. An
   undo whose job is no longer queued or running (it was aborted) is treated as Undo failed
   too, so it can be run again rather than staying Undoing for ever.
4. **Deleted, not destroyed.** Records go to the recycle bin by the ordinary delete, in the
   running user's own permissions. Nothing in the undo path empties it, so a mistaken undo
   is recoverable for as long as the platform keeps them.

**R-IB9 What undo does to each record.**

- **It deletes what the batch created, and never what it matched.** Only records carrying
  this batch's tag are deleted (R-IB3): the people it created, the households it created for
  them, and the organizations it created. The tag is written when the record is created and
  never afterwards, so a record the batch matched or updated cannot be in scope. People are
  deleted first, then accounts, so a household can be judged after its imported members are
  gone. A one-object load (R-IT12) tags nothing, because its object has no tag: the records it
  created are named on the batch's Created journal pages (Section 17A) and deleted in a pass of
  their own, after the values are put back and before any module's pass. A journaled record is
  deleted only when it was created by the committer between the commit's start and its
  completion; any other is kept and journaled, so a journal entry can never delete somebody
  else's record. The checks below apply to these records as to tagged ones.
- **It keeps a tagged record that has gained something since.** A tagged record is kept,
  counted and journaled with the reason, when:
  - any record points at it through any reference the org can filter on (a gift, a soft
    credit, a membership, an address, an activity, anything in any package, found by
    describing the record's child relationships, never by naming an object), and was created
    after the batch completed, or was created while the commit ran by somebody other than the
    person who committed it; a record carrying this batch's own tag does not count, since the
    undo deletes it too (an aborted commit's household naming its new person as Primary
    Contact);
  - the record itself was edited since: by somebody other than the committer after the
    commit started, or by anybody more than ten minutes after it completed (the ten minutes
    are the import's own follow-on work, such as rollups and household naming, which runs as
    the committer); or an activity has been logged on it. A rollup save the import set off is
    not an edit, whoever ran it (the committer or the Automated Process user that starts the
    Rollup Queue): it is told by `Rollups_Last_Calculated__c`, which the rollup writes in the
    same save whatever the running user's access, the record's last save falling within five
    seconds after that stamp, and the stamp no later than sixty minutes after the commit
    completed, a fixed window the Rollup Queue drains well within (ADR-0119). A later rollup save may hide a real edit and keeps the record; so does
    a save on an object without the stamp, which cannot be told apart;
  - for a household or an organization, a person this import did not create is still on it,
    or Nonprofit Cloud records depend on it (ADR-0036), or an installed module still credits
    records to it, asked through `HouseholdDependentsExtensions` as the empty household
    tidy-up asks (R-H12): a gift or pledge that points at the household without having been
    created since the import, such as an older gift whose donor was changed, which the first
    bullet cannot see. A module that cannot answer keeps the household, journaled as not
    checked.

  Work the undo itself does (a household renamed as its imported members are deleted) is
  not counted. Because such a save, or a rollup a delete sets off (a donor's totals once
  their imported gifts are gone), would hide an edit made before it, the undo first judges
  every tagged record, in one judging pass per delete pass before anything is put back or
  deleted, and carries the records found edited to the delete passes; a record saved during
  the undo by the undo or by a rollup is kept only when it was found edited then (ADR-0119).
  A check that cannot run, or would leave the delete too few queries, keeps the
  record and journals that it was not checked. A record the person undoing cannot delete is
  kept and journaled with the reason. Deleting a donor clears the donor on every gift
  recorded against them since, which would change giving totals; the import's records are
  not worth anybody's later work. A person stored as an account is not kept for its own
  contact record, which is itself rather than somebody else.
- **It puts back what the batch overwrote, where nobody has changed it since.** For each
  update in the journal (Section 17A), an attribute whose current value is still the value
  the import wrote is set back to the value before the import. An attribute somebody has
  changed since is left as it is and journaled as not put back, because restoring a value
  weeks later would silently overwrite their correction.
- **It removes what an entity processor created, on the processor's terms.** An entity
  processor (R-IR6) names the objects it tags with the batch, and the undo deletes those
  records first, before the people, in a pass per object, with the same one-batch filter, the
  same checks above and the same delete in the running user's own mode. Core names none of
  those objects: their types come from the processor and every query is built from describe.
  The processor adds its own reasons to keep, for its records and for Core's: the Giving
  processor keeps a gift with an issued receipt, and the person, household or organization
  that such a gift still names (R-GI9). The counts shown before the undo include each such
  object by its plural label.

When the undo finishes, one line is added to the Run Log: who ran it, when, and how many
records it deleted, kept and put back.

The counts shown before an undo, the checks that decide what is kept, and the status and
run log writes are read and written in system mode (ADR-0021): a count or a check that
cannot see a record would report "nothing there" about exactly the record that matters, and
the status is the package's own bookkeeping. Every delete and every value put back is in the
running user's own mode.

**R-IB10 Control totals.** An administrator may give a file two control totals before its
dry run: how many rows it holds and what its gift amounts add up to, from the deposit slip or
the processor's own report. Both are optional. The dry run compares Expected Count with Row
Count and Expected Amount with File Amount, the total the entity processor read from every
row that carries a readable gift amount, rejected or not, because the question is whether
this is the file on paper. Each comparison is written to the Run Log with both numbers, and
while either differs a commit is refused with a sentence naming them; the administrator
corrects the file or the totals and runs a new dry run. An Expected Amount with no processor
installed cannot be checked and is refused the same way (ADR-0052).

**R-IB11 A commit runs under the settings its dry run showed.** An entity processor whose
decisions depend on settings (for Giving, donation matching's behaviour, date window and
amount tolerance, R-DM7) takes them once, on the dry run's first chunk, and hands them back
with each chunk's result (R-IR6). The dry run records them on the batch as Processor Settings,
replacing the last dry run's, and the commit hands the batch, with them, to the processor,
which runs under them rather than under the template or the org settings as they stand at
commit. A template edited between the dry run and the commit therefore changes the next dry
run and not the commit. A batch whose dry run recorded none (one dry run before this rule)
runs under the template, as before. Processor Settings is one document Core never reads, not
an attribute per setting: the values are the processor's own (an empty template value means a
Giving setting Core cannot resolve), and a module's settings do not become Core attributes
beyond the template values R-IT7 already carries (ADR-0014).

**R-IB12 A dry run counts a new record once, however many chunks name it.** The commit
creates a new person or organization in the first chunk that names it, and every later chunk
finds it by the template's matching rule and counts the row Matched (or Updated). A dry run
saves nothing for a later chunk to find, so it writes, in the dry run only, a 64-bit digest
of the matching key of each person and organization it would create onto the row that would
create it (Person 1 Key, Person 2 Key, their Name Keys, Organization Key, Section 17). Each chunk looks up only
its own rows' keys among the rows earlier chunks of the same pass processed (R-IB13), so what a chunk
holds and reads depends on the chunk, not on how many rows came before it, and a dry run of
half a million rows needs no more heap for this than one of a thousand. A later row whose
key is among them is counted as matching that record, not as creating it again, and is not
refused for a missing last name, exactly as in the commit. A person is remembered only when
the commit could find them again by the same key, so what is written and what is matched are
the same fields: an email is written to a contact's Email or a person account's PersonEmail,
and matched there; a postal code is written to a contact's MailingPostalCode or a person
account's PersonMailingPostalCode only when the person's own column gave it (a household's
postal code alone is not written to the person), and matched there. A person account is
also matched on its BillingPostalCode, where a person loaded by another tool often holds its
postal code; that only finds more of the people already there and changes nothing about what
the dry run remembers. A matching field the importing user may not read is not matched on
(a user-mode query naming it would fail the chunk), and the run log names it, since every
person in the file then counts as new. Where the importing user
may not write the field, the commit's new person does not carry it, so under that rule the
commit creates such a person again and the dry run counts it again.
Within one chunk the commit creates a new person once as well: rows naming the same new person
by the same matching key, in either person column, share the record the first of them creates
(first people are saved before second people, and a second person whose row has a first
person before one whose row has not), and are not joined to a household for it. When that
person cannot be saved, the rows sharing them are rejected with the reason. The dry run walks
the chunk in the same order and counts the same row as the one that creates. Unlike a person
an earlier chunk would create, a later row of the same chunk must still carry a last name,
because rows are checked before anybody is saved. One difference remains: a later row that brings a value the first row did
not is Updated in the commit but Matched in the dry run, which has no saved record to compare
it with; both count it once.

**A row's two people are two people.** When the Email or Name + Postal rule gives a row's two
people one key (a couple with one surname and postal code, or one shared email), each is
matched, shared and remembered by that key narrowed to their own first name: against the
org's records (a record matches when its key and its first name both agree), against earlier
rows of the chunk and against earlier chunks, in the commit and the dry run alike. Loading the
same file again matches both rather than creating the second again. Every person an import
creates is remembered under both the shared key and the narrowed one.

**A person with a first name is found only by it (ADR-0067).** Under the same two rules, a
row's person with a first name is looked for by the key narrowed to it, in the org, among the
people earlier chunks create and among those earlier rows of the chunk create, and nowhere
else. A record holding the shared key under another first name, or under none, is somebody
else: the person is created, and that record is neither matched nor renamed, however many
records hold the key (one, as with John Smith alone at a postal code and a "Jane Smith" row,
or several, as with a couple). A new record is the safe failure, left for the duplicate scan
(R-DP3); taking somebody else would rename them. The shared key alone finds a person only when
the row gives no first name (R-IT9 decides when it finds several), and since a blank incoming value never
clears a stored one, such a row renames nobody. A row naming alone the second person of a
couple of the same chunk waits until the couple is saved (first people are saved before second
people) and then shares that partner, so both rows name one person in the couple's one
household, whichever row comes first. A lookup of the org reads at most 5,000 records,
filtered on both the last names and the postal codes of the chunk; where it stops at that cap,
another holder of the key may be unseen, so a row with no first name finds nobody by those
keys and its person is created, and a warning is logged. First names are compared ignoring
case, surrounding spaces and runs of inner spaces ("Mary  Ann" is "Mary Ann"), and nothing
else: "Jáne" is not "Jane", an initial ("J.") is not the name it stands for, and there is no
short-form matching ("Bob" is not "Robert"), so each is created. A row whose two people also
share a first name cannot be told apart and is rejected, saying so. Under the Email rule a
second person with no last name of their own therefore matches only a record with the same
email and first name; otherwise they are to be created, and are rejected without a last name
as any new person is. Where the key a row is looked for by (narrowed to its first name, or
shared when it gives none) finds several records, Several Matches decides (R-IT9): by default
the row is rejected, where before v0.7 the earliest created was taken. In a dry run a person an
earlier chunk would create counts as a holder of their keys, because the commit will find them.
An organization is found by its rule's key the same way, and several organizations holding it
are the same case.

**An import saves past a duplicate alert, not past a block.** People, organizations and
household names are saved past a duplicate rule that only alerts, as an administrator's bulk
load is: the file is people the organization chose to add, and an alert would otherwise
reject every row resembling somebody, the second person of a couple included. The pair is
left for the duplicate scan to propose (R-DP3, ADR-0050). A rule the org set to block still
blocks, and the row is rejected with the rule's own message. The dry run saves nothing, so no
duplicate rule runs in it: a row a blocking rule will refuse is counted as creating there.

**R-IB13 One pass at a time, and each pass reads only its own rows.** Starting a dry run or
a commit is refused while a job for that batch is actually running (queued, preparing,
processing or holding), saying an import is already running on it; the batch is read and
locked for the check, so two starts at once cannot both pass it. The status alone does not
refuse: a pass the platform aborted, or whose finish failed, leaves the batch in Dry run or
Committing with no job behind it, and it can simply be started again. A Committing batch with
no running job reads as Failed, with the commit's user and undo window stamped, so the chunks
it wrote can be undone (R-IB7); for that undo the commit ended when its job did, or when it
started where the job is no longer on record, so every change made since, the committer's
own included, is kept (R-IB9). Such a batch cannot be dry run or committed again. Each start adds one to the batch's Pass Number and changes
nothing else on the rows: there is no reset of the staged rows before a pass, which for a
large file would be more writes than one transaction allows. Instead every pass processes
every row of the batch, and each chunk clears what an earlier pass left on its rows (status,
message, the records resolved and the keys) before working them out again, and stamps them
with the pass. A key is looked up only on rows stamped with the current pass (R-IB12), so a
key from an earlier pass is never read. While a pass runs, rows it has not reached yet still
show the last pass's outcome; the batch's counts are read back when it finishes, by which time
every row belongs to it.

**R-IB14 Values for every row of a file.** The wizard can give a file values that apply to
each of its rows, for example every row's appeal (ADR-0068,
`0068-import-matching-per-entity-and-per-file-values.md`). They are held on the batch as
`{ "version": 1, "defaults": [ { "target": "Entity.Attribute", "value": "..." } ] }`, the
defaults half of the R-IT1 document, so the dry run and the commit of the file use the same
values and the template is not changed. A row's own value wins, then the file's value, then
the template's default: each fills only a blank. A file value may not target a person's name
parts, full name or email, or the field people are matched on under External ID (R-IT8),
since every row would then be one person; the batch is refused with that reason. It may name
an organization. The entity processor receives the row's values with the file's values
applied, as it receives the template's defaults (R-IR6).

**R-IB16 A trial of the first rows, then the rest, in one batch.** After a dry run completes,
the administrator may commit only the file's first N rows (N from `Import_Trial_Rows__c`,
default 25, changeable per file, held between 1 and 2,000) for real, so validation rules,
required fields and the org's own automation are met before the whole file runs. The trial is
a commit under the dry run's template (R-IB1) over the first N rows in file order; it records N
as Trial Rows and ends in Trial complete, counting only the rows it processed. From Trial
complete the administrator may commit the remaining rows (every row after the trial's last) into
the same batch, under the same template; that commit ends Complete (or Failed) and counts every
row of the file. A dry run is refused once the trial has committed (R-IB1). Trial complete is
undoable like Complete, and one undo covers both commits, because both tag and journal under the
one batch (R-IB3, R-IB8); the undo deadline is stamped again by the second commit (R-IB7). A
trial that fails ends Failed, can be undone, and offers no remaining rows.

**R-IB15 Match only.** The wizard can mark a file Match only (ADR-0069,
`0069-import-record-id-matching-and-match-only.md`), for a file meant to update records the org
already has. A row whose organization or either person matches no record, by its rule or by a
record ID (R-IT10), is rejected with a message saying the file creates nobody; nothing is
created for it. The dry run and the commit reject the same rows. Matched records are updated as
in any import, and an entity processor still loads the rest of a matched row (R-IR6). The
choice belongs to the file, not the template, and is set again for each upload.

**R-IB17 Retrying the rejected rows.** A committed import's rejected rows can be fixed and
loaded into the same batch, so one undo still covers everything the import created. A retry
opens only on an import (not a bulk update or delete) that is Complete with rejected rows, or
that already has a retry open; only for the user who committed it; only while its undo is
allowed (R-IB8) and its staged rows are kept (R-IR5); and never while a pass runs. Opening one
sets Status to Retrying and Retry After Row to the batch's highest row number, discarding the
rows of an earlier unfinished retry. The fixed file is staged into the batch while it is
Retrying (staging is otherwise closed once a batch has run), at most 10,000 rows, each numbered
Retry After Row plus its file row number less one. The retry's dry run reads only rows after
Retry After Row, counts only them, and keeps the batch a commit: Is Dry Run, Started At,
Completed At, File Amount and Committed By are left as the commit set them, its log is added
after the commit's, and the control totals are not checked again. The retry's commit runs
under the template the commit ran with (R-IB1), keeps Started At so undo covers both runs,
reads the retry's rows and the earlier Rejected rows, marks each earlier Rejected row Retried
without processing it, and processes the rest; its finish counts every row (a Retried row
counts as nothing), clears Retry After Row and re-stamps the undo deadline. Undo is allowed
while a retry is open, as for the commit (R-IB8).

### Salesforce implementation

- **Object:** `Import_Batch__c`, auto-number Name with format `IB-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Import Template | `Import_Template__c` | Lookup to `Import_Template__c` |
| File Reference | `File_Id__c` | Text (18) |
| File Name | `File_Name__c` | Text |
| Status | `Status__c` | Picklist: Draft, Parsing, Dry run, Dry run complete, Committing, Trial complete, Complete, Retrying, Failed, Undoing, Undone, Undo failed |
| Is Dry Run | `Is_Dry_Run__c` | Checkbox |
| Row Count | `Row_Count__c` | Number |
| Rows Created | `Rows_Created__c` | Number |
| Rows Updated | `Rows_Updated__c` | Number |
| Rows Matched | `Rows_Matched__c` | Number |
| Rows Rejected | `Rows_Rejected__c` | Number |
| Run Log | `Run_Log__c` | Long Text Area |
| Started At | `Started_At__c` | DateTime |
| Completed At | `Completed_At__c` | DateTime |
| Chunk Size | `Chunk_Size__c` | Number |
| Undo Deadline | `Undo_Deadline__c` | DateTime |
| Committed By | `Committed_By__c` | Lookup to User |
| Expected Count | `Expected_Count__c` | Number (9, 0) |
| Expected Amount | `Expected_Amount__c` | Currency (16, 2) |
| File Amount | `File_Amount__c` | Currency (16, 2) |
| Processor Settings | `Processor_Settings_JSON__c` | Long Text Area (32768) |
| Template Snapshot | `Template_Snapshot_JSON__c` | Long Text Area (131072) |
| Pass Number | `Pass_Number__c` | Number (9, 0) |
| Job Id | `Job_Id__c` | Text (18) |
| File Values | `File_Values_JSON__c` | Long Text Area (32768) |
| Match Only | `Match_Only__c` | Checkbox (default false) |
| Operation | `Operation__c` | Picklist: Import, Update, Delete (default Import) |
| Bulk Update Definition | `Operation_JSON__c` | Long Text Area (131072) |
| Rows Deleted | `Rows_Deleted__c` | Number (9, 0) |
| Trial Rows | `Trial_Rows__c` | Number (9, 0) |
| Retry After Row | `Retry_After_Row__c` | Number (9, 0) |

- **Batch tag on other objects:** `Created_By_Import_Batch__c`, a Lookup to
  `Import_Batch__c`, on Account (households and organizations), on Contact, and on
  `Gift__c`. The Account and Contact fields ship in Core with the import framework; the
  `Gift__c` field ships in Giving (Section 18).
- **Settings keys:** `Import_Chunk_Size__c` and `Import_Undo_Retention_Days__c`
  (Section 12).
- **Remembered between chunks, in a dry run only:** the digests of the records earlier chunks
  would create are kept on those rows (`Person_1_Key__c`, `Person_2_Key__c`,
  `Organization_Key__c`, Section 17) and each chunk queries only the digests it needs through
  `ImportRowSelector.createdDigestsWrittenEarlier` (R-IB12). Nothing is carried in the batch's
  state.
- **Service:** `ImportBatchService`, `ImportBatchSelector`, `ImportProcessorBatch`,
  `ImportUndoService` and `ImportUndoBatch` (R-IB7 to R-IB9), `ImportController` (the one
  Aura-enabled entry point the import screens call), LWC `importWizard`, `importResults`,
  `dataJobHistory` (recent data jobs and their undo; on the Import page it lists imports only,
  and bulk updates and deletes are listed on the Bulk Update page, Section 29E).

---

## 17. Import Row

### Definition

One row of the uploaded file, staged so that it can be previewed, explained, corrected,
and reprocessed (plan Section 4.9). A row is not one record: it can describe a household,
up to two people, an organization, a gift with allocations, and a soft credit, and the
processor resolves those in dependency order.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Import Batch | reference(Import Batch) | yes | The upload this row came from. |
| Row Number | integer | yes | The row's position in the file, so a message can name it. |
| Raw Values | long text | yes | The row's original column values exactly as uploaded, held as a document keyed by column name. |
| Status | picklist(Pending, Matched, Created, Updated, Rejected, Skipped, Retried) | yes | What the processor did with this row, or would do in a dry run. Retried: a rejected row a retry's commit replaced with its fixed row (R-IB17). |
| Error Message | long text | no | Why the row was rejected, in language an administrator can act on. |
| Household | reference(Household) | computed | The household this row resolved to. |
| Contact 1 | reference(Contact) | computed | The first person, where people are Contacts. |
| Person 1 Account | reference(Organization) | computed | The first person, where people are person Accounts. |
| Contact 2 | reference(Contact) | computed | The second person, where people are Contacts. |
| Person 2 Account | reference(Organization) | computed | The second person, where people are person Accounts. |
| Organization | reference(Organization) | computed | The organization this row resolved to. |
| Gift | text | computed | The gift this row resolved to, held as a record identifier (R-IR2); for a one-object template, the record the row created, updated or matched (R-IT12). Labelled Resulting Record. |
| Soft Credit | text | computed | The soft credit this row resolved to, held as a record identifier (R-IR2); for a one-object template with related records, the related record the row created (R-IT17). Labelled Second Resulting Record. |
| Related Status | text | computed | For a one-object template with related records, what the row's related record did or would do in a dry run: Created or Rejected; empty when the row has none (R-IT17). |
| Person 1 Key | text | computed | In a dry run only, a digest of the matching key of the first person this row would create, so later chunks count that person once (R-IB12). Cleared when the row is processed again. |
| Person 2 Key | text | computed | The same for the second person. |
| Person 1 Name Key | text | computed | The same digest of the first person's key narrowed to their first name, so a later row finds them by either (R-IB12). |
| Person 2 Name Key | text | computed | The same for the second person. |
| Organization Key | text | computed | The same for the organization this row would create. |
| Pass Number | integer | computed | The pass of its import that last processed this row (R-IB13). |
| Several Matches | boolean | computed | True when the key this row's person or organization was looked for by found more than one record, whether the row was rejected for it or given the most recently changed one (R-IT9). |
| Matched By Duplicate Rule | boolean | computed | True when the org's duplicate rules, not the template's rule or the row's key, matched this row's person, organization or one-object record (R-IT16). |
| Processor Key | text | computed | In a dry run only, a digest the entity processor writes for what this row would load, so later chunks of the same dry run can see it (R-IR6). Core never reads its meaning. For a one-object template, Core writes it in both passes: a digest of the record ID or upsert value the row names, so a later row naming the same record is rejected (R-IT12), or with related records the parent row's key digest, one form when its parent was saved and another when it failed (R-IT17). |
| Row Key | text | computed | When the template has One row per key columns, a digest of this row's key cells, written as the row is staged so a later page finds it (R-IT18). Empty for a skipped row or a row with no key. |

### Relationships

- **Import Row to Import Batch**, many to one, and rows are deleted with their batch.
- Import Row to the records it resolved: to Core records by reference, to Giving records
  by identifier (R-IR2).

### Rules

**R-IR1 Row entities and resolution order.** A row is read as up to nine entities named
`Household`, `Contact1`, `Contact2`, `Organization`, `Affiliation`, `Gift`, `Allocation`,
`SoftCredit` and `Tribute` in the template's mapping document, and they are resolved in
dependency order: organization, household, people, membership and affiliation, gift,
allocations, soft credit, tribute. Resolution is idempotent per row (R-IB4). A row of a
one-object template (R-IT12) is read as the one entity `Record` instead, with `Related` when
it loads related records (R-IT17), and none of the others.

**R-IR1a What a row means for households.** A row is one household. The row's first
person is saved first and is given a household by the ordinary creation path (R-H1 in
contact mode, R-H2 in junction mode), which is the household the row then records. The
row's second person is joined to that same household rather than being given one of their
own, through `HouseholdService` (R-M5), so the join is written the way this org holds
membership: the person's own account reference in contact mode, a Household Member record
in junction mode, for a person stored as a Contact and for a person stored as an account
alike. Two people on one row are therefore one household with two members in every
membership mode and on both person objects. Three consequences follow. A second person who
is created for a row that has no first person (the row named nobody else, or that person
failed to save) gets a household of their own, because there is nothing to join. A second
person who matched somebody the org already has keeps the household they already belong
to: an import never moves an existing person into another household. And nobody is given a
household and then taken out of it, because automatic creation is suspended while the
people who are about to be joined are saved.

**R-IR2 Giving links are identifiers, not references.** Gift and Soft Credit are stored
as record identifiers rather than lookups. Import Row lives in Core and `Gift__c` and
`Soft_Credit__c` live in Giving, and a base package cannot hold a reference to an object
in a package that depends on it. The Giving package reads and writes these two attributes
by identifier. The cost is that the two links are not clickable in the standard record UI
and cannot be reported on through a relationship; the results screen resolves and links
them, and ADR-0014 records the deviation from the literal field list in plan Section 4.9.

**R-IR2a The household is named from the row.** Where a row maps a household name, that
name is written to the household the row resolved to and the household is marked as
custom named, so the naming patterns leave it alone from then on (R-H8). This holds
however the household was made, including the one junction mode creates with a membership
record.

**R-IR3 Person references.** A row resolves its people to Contacts or to person Accounts
according to the template's Person Mode, never to both (Section 4 "Person references").

**R-IR4 Raw values are never rewritten.** Raw Values holds what was uploaded. A
correction is made by fixing the file and re-running, not by editing the staged row, so
the batch remains an accurate record of what was loaded.

**R-IR5 Retention.** Rows are kept for `Import_Row_Retention_Days__c` days (90 unless the
admin changes it, 0 for ever) after their batch's last pass completed (`Completed_At__c`), then
deleted by the nightly Import row cleanup job (`ImportRowPurgeScheduler`, listed in Health
Check's nightly jobs), so a large import does not sit in storage forever (D-40). The batch
keeps its counts and run log. Undo does not read the rows: it reads the tag on the records and
the journal (R-IB9, Section 17A). A batch whose rows were removed cannot be run again; a pass is
refused, saying so.

**R-IR6 Entities Core cannot resolve.** Core resolves `Organization`, `Household`,
`Contact1`, `Contact2` and `Affiliation` (R-AF5). `Gift`, `Allocation`, `SoftCredit` and `Tribute`
belong to features or packages Core may not reference (ADR-0014), so the processor offers
them to an optional `ImportEntityProcessor` implementation, the class named
`GiftImportProcessor`, found by namespace and name with `Type.forName` (the mechanism in
ADR-0017). Where none is installed it leaves those columns staged on the row, says so in the
run log, and counts the row on what it did resolve. A row is never rejected for carrying a
column nothing can load yet. The contract, which ADR-0052 records:

- **Targets.** The processor names the columns it loads, with their labels, and the column
  picker offers them. Where no processor is installed the picker offers the shipped gift
  columns marked as kept with the row and not loaded.
- **Resolve.** Called once per chunk, after Core has resolved the organization, the household
  and the people and written them onto the rows (their references, and Status Rejected with
  the reason where Core rejected the row), with each row's values grouped by entity and the
  file's values and the template's defaults applied (R-IB14). It must be bulk safe, must write nothing when the pass is a dry
  run, and must not throw: a failure belongs on its row. It returns a note for the run log,
  the total of the gift amounts it read, for the control totals (R-IB10), and in a dry run the
  settings it ran under, which the commit is held to (R-IB11).
- **Carried state.** Each chunk runs in its own transaction. A processor that needs to know
  what earlier chunks of the same run decided (the scheduled payments already matched, R-DM4)
  keeps it in `ImportEntityProcessors.carriedState`, a string the import batch holds between
  chunks and sets again before each one. Core never reads it, and a chunk that fails does not
  change it. What grows with every row belongs on the rows instead: in a dry run the
  processor writes a digest to a row's Processor Key, and a later chunk asks
  `ImportRowSelector.processorDigestsWrittenEarlier` for only the digests it holds (in Giving,
  the external IDs already loaded, R-DM1).
- **Undo.** The processor names the objects it tags with the batch and gives its reasons to
  keep records (R-IB9).

**R-IR7 What a row comes to.** The processor reports each row it handled by setting its
Status and, for Giving, its Gift and Soft Credit identifiers: Rejected with the reason,
Created when it created something, or Matched when it found what the row describes already
there. Core folds that into the row's status: a rejection wins over anything Core did, so a
row whose gift failed is counted rejected and appears in the exceptions file even when its
person was created; a creation makes the row Created; a match leaves Core's own outcome. A
person created for a row whose gift was then rejected stays, carries the tag, and is matched
when the corrected row is loaded again.

### Salesforce implementation

- **Object:** `Import_Row__c`, auto-number Name with format `IR-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Import Batch | `Import_Batch__c` | Master-Detail to `Import_Batch__c` |
| Row Number | `Row_Number__c` | Number |
| Raw Values | `Raw_Values_JSON__c` | Long Text Area |
| Status | `Status__c` | Picklist: Pending, Matched, Created, Updated, Rejected, Skipped, Retried |
| Error Message | `Error_Message__c` | Long Text Area |
| Household | `Household__c` | Lookup to Account |
| Contact 1 | `Contact_1__c` | Lookup to Contact |
| Person 1 Account | `Person_1_Account__c` | Lookup to Account |
| Contact 2 | `Contact_2__c` | Lookup to Contact |
| Person 2 Account | `Person_2_Account__c` | Lookup to Account |
| Organization | `Organization__c` | Lookup to Account |
| Resulting Record | `Gift_Id__c` | Text (18) |
| Second Resulting Record | `Soft_Credit_Id__c` | Text (18) |
| Person 1 Key | `Person_1_Key__c` | Text (16), External ID (indexed) |
| Person 2 Key | `Person_2_Key__c` | Text (16), External ID (indexed) |
| Person 1 Name Key | `Person_1_Name_Key__c` | Text (16), External ID (indexed) |
| Person 2 Name Key | `Person_2_Name_Key__c` | Text (16), External ID (indexed) |
| Organization Key | `Organization_Key__c` | Text (16), External ID (indexed) |
| Processor Key | `Processor_Key__c` | Text (16), External ID (indexed) |
| Row Key | `Row_Key__c` | Text (16), External ID (indexed) |
| Pass Number | `Pass_Number__c` | Number (9, 0) |
| Several Matches | `Several_Matches__c` | Checkbox |
| Matched By Duplicate Rule | `Duplicate_Rule_Match__c` | Checkbox |
| Related Status | `Related_Status__c` | Text (20) |

The seven keys (Row Key included) and the row's Pass Number are bookkeeping written and read in system mode
(ADR-0021), in no permission set. The keys are marked External ID only so that they are
indexed; they are not unique, and nothing outside the import reads them.

- **Service:** `ImportRowProcessor`, `ImportMatcher`, `ImportRowSelector`,
  `ImportEntityProcessor` (the interface a dependent package implements to resolve the row
  entities Core cannot, R-IR6), `ImportEntityResult` (what one chunk of it returns) and
  `ImportEntityProcessors` (finds the installed implementation).

---

## 17A. Import Journal

### Definition

The record of the changes an import made to records it did not create, kept so that an undo
can put them back (plan Section 4.9: "updates are journaled for reversal"), and of what an
undo left in place and why (feature C-19).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The journal page's identifier, assigned automatically. |
| Import Batch | reference(Import Batch) | yes | The import this page belongs to. |
| Phase | picklist(Commit, Created, Undo) | yes | Whether this page records the changes an import made, the records a one-object import created (R-IJ3), or the undoing of it. |
| Entry Count | integer | yes | How many entries this page holds, so a total is a sum rather than a parse. |
| Entries | long text | yes | The entries themselves, held as one document per page (R-IJ2). |

### Relationships

- **Import Journal to Import Batch**, many to one, and the pages are deleted with the batch.

### Rules

**R-IJ1 One page per chunk, not one record per change.** A page is written as each chunk of
a commit finishes, holding one entry per record that chunk updated; a chunk that updated
nothing writes no page. A hundred thousand row import therefore leaves hundreds of journal
records rather than a hundred thousand. A page that would overflow its attribute, or hold
more than 200 entries, is split into two pages, never shortened, because a shortened entry is
a change that can no longer be put back; the 200 keeps an undo's putting back of one page
inside one transaction's limits. A single entry too large for any page is left out and
written to the Error Log, and the chunk's other entries are still written. The price is that an entry is not a record and cannot be reported on by itself;
the counts an administrator reports from live on the batch (Section 16).

**R-IJ2 The entry document.** Values are held as typed values (text, number, true or false,
a date as `YYYY-MM-DD`), so a value put back is the value that was there.

```
{
  "version": 1,
  "entries": [
    { "action": "Updated", "object": "Contact", "id": "003...", "row": 13,
      "fields": { "Email": { "before": "old@example.org", "after": "new@example.org" } } },
    { "action": "Kept", "object": "Account", "id": "001...", "label": "The Smith Family",
      "reason": "A person this import did not create is in this household." },
    { "action": "NotRestored", "object": "Contact", "id": "003...", "field": "Email",
      "reason": "Changed since the import." },
    { "action": "Failed", "object": "Contact", "id": "003...",
      "reason": "The platform's own message, for example a validation rule's." },
    { "action": "Created", "object": "Program_Session__c", "id": "a01...", "row": 14 },
    { "action": "Deleted", "object": "Contact", "id": "003...", "label": "Ana Ramirez" }
  ]
}
```

**R-IJ3 What is journaled.** A commit journals updates: the attributes a row changed on
a record the import did not create, with the value before and the value written, in full. A
record an import of people creates needs no entry because it carries the tag (R-IB3), and a
matched or rejected row changed nothing and is recorded on its staged row (Section 17). A
one-object import (R-IT12) creates records of an object with no tag, so each record it
creates is journaled as a Created entry (object, ID, file row) on pages of their own, Phase
Created, at most 100 to a page so an undo deletes one page inside one transaction's limits;
the undo reads them as R-IB9 says. A bulk update (R-BU3) journals, for each record it saved,
the fields whose value changed, before and after, and for each record the platform refused, a
Failed entry with the reason; a record that already held the new values is not saved and not
journaled. A bulk delete (R-BD3) journals a Deleted entry (object, ID, the record's name) for
each record it deleted, and a Failed entry for each record the platform refused; its undo
journals a NotRestored entry, with no field, for each record it could not bring back. An undo
journals the
records it kept and the values it did not put back, each with its reason; the records it
deleted are counted in the Run Log rather than listed, because the recycle bin lists them.

**R-IJ4 Written in system mode, and never fatal.** The journal is the package's own
bookkeeping and is written under ADR-0021, so a run by a user who cannot edit these records
is still journaled. A journal write that fails is logged to the Error Log and said in the
Run Log rather than failing a chunk whose records are already saved; that chunk's updates
cannot then be put back, and the Run Log is what says so.

**R-IJ5 Who and when.** A page carries no user or time attribute of its own. Its standard
created by and created date say who ran the pass and when, and the batch carries Committed
By, Started At and Completed At.

### Salesforce implementation

- **Object:** `Import_Journal__c`, auto-number Name with format `IJ-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Import Batch | `Import_Batch__c` | Master-Detail to `Import_Batch__c` |
| Phase | `Phase__c` | Picklist: Commit, Created, Undo |
| Entry Count | `Entry_Count__c` | Number |
| Entries | `Entries_JSON__c` | Long Text Area |

- **Service:** `ImportJournalService` (writes and reads pages), `ImportRowProcessor` (writes
  the commit phase), `ImportObjectLoader` (writes the commit and created phases of a one-object
  import), `ImportUndoBatch` (writes the undo phase), LWC `dataJobHistory`.

---

# Part D: Giving entities

These entities are built by the Giving package. Sections 18 to 21 are v0.2 (features
G-01 to G-06); Sections 22 to 25 are v0.3 (features G-07 to G-11). Section 21A is the
Giving package's own settings object, which ADR-0017 introduced. Section 26 lists the
rollup definitions the Giving package ships and the target attributes they write.

Giving depends on Core, so Giving may hold references to Core objects and Core may not
hold references to Giving objects (ADR-0014). `Gift__c` is the gift system of record and
no entity here references Opportunity, Campaign, Lead, Case, or any Industries object
(ADR-0004).

## 18. Gift

### Definition

One received transaction: money, stock, or goods that arrived, from one donor, on one
date (plan Section 4.11). A gift is a fact about something that happened, which is why a
refund is another gift rather than an edit (ADR-0010).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The gift's identifier, assigned automatically. |
| Donor Contact | reference(Contact) | conditional | The person credited with the gift, where people are Contacts. |
| Donor Account | reference(Organization) | conditional | The account credited with the gift: an organization, a household giving in its own name, or a person Account. |
| Household | reference(Household) | computed | The household credited with the gift, derived from the donor when the gift is given and kept when the donor later moves households (R-G2). |
| Gift Date | date | yes | The date the gift was received, which is the date that appears on the receipt. |
| Amount | decimal | yes | The money received, negative for a refund or a write-off, and zero on an in-kind gift, which is goods rather than money (R-G12). |
| Payment Method | picklist(Cash, Check, Card, ACH, Stock, In-kind, Grant, Other) | yes | How the gift arrived. Labelled Type before v0.6; the API name is still `Type__c`. |
| Status | picklist(Received, Pending, Refunded, Written off, Cancelled) | yes | Where the gift stands; Received, Refunded and Written off count in the packaged giving totals, so a reversal nets against its original (ADR-0022), and Pending and Cancelled do not. Cancelled is a Pending gift that will never be paid (R-G16). |
| Appeal | reference(Appeal) | no | The fundraising effort this gift responded to. |
| Acknowledgment Status | picklist(Not required, To acknowledge, Acknowledged, Do not acknowledge) | yes (defaults To acknowledge) | Whether this gift still needs a thank you. |
| Acknowledgment Date | date | no | The date the thank you was sent. |
| Receipt Number | text | no | The number of the receipt issued for this gift, unique across the org and never reused. |
| Tribute | reference(Tribute) | no | The honor or memorial this gift was given under (v0.3, R-G8). |
| Matched Gift | reference(Gift) | no | The employer's matching gift that this gift produced, or the employee gift that this gift matches (v0.3, G-10). |
| Commitment | reference(Commitment) | no | The pledge or recurring commitment this gift pays toward (v0.3). |
| Installment | reference(Installment) | no | The scheduled installment this gift fulfills (v0.3). |
| External Id | text | no | The identifier this gift carries in the system it came from, unique, used to make imports and the inbound API idempotent. |
| Payment Reference | text | no | The processor's transaction reference, check number, or deposit reference, for reconciliation against the bank. |
| Original Gift | reference(Gift) | conditional | The gift this one refunds or writes off; required when Amount is negative (R-G3). |
| Refund Reason | text | no | Why the money went back or the gift was written off, typed by the person recording it and carried on the negative gift (R-G3). |
| In-kind Description | long text | conditional | What was given, when the gift is goods or services rather than money. Required on an in-kind gift and empty on every other gift, and it is the text the receipt prints (v0.4, G-18, R-G12). |
| Fair Market Value | decimal | no | What the goods were worth, recorded for the organization's own reporting and never printed on a receipt or a statement (v0.4, G-18, R-G12, R-RC12, ADR-0030). |
| Benefit Description | long text | no | What the donor received in return for the gift, described as it must be printed on the receipt (v0.4, G-13, R-RC7). |
| Benefit Value | decimal | no | The organization's good faith estimate of what the benefit was worth, which the receipt subtracts to state the deductible amount (v0.4, G-13, R-RC7). |
| Intangible Religious Benefits | boolean | yes (defaults false) | Whether the only thing the donor received in return was an intangible religious benefit, which is a sentence the receipt must carry instead of a value (v0.4, G-13, R-RC7). |
| Created By Import Batch | reference(Import Batch) | no | The import that created this gift, so it can be found and, from v0.5, undone. |
| Posted to Accounting | datetime | no | When the gift was marked as entered in the accounting system; empty while it is not. Package written (v0.6, G-20, R-G13). |
| Posted to Accounting By | reference(User) | no | Who marked it posted; empty while it is not (v0.6, G-20, R-G13). |

### Relationships

- **Gift to Donor**, many to one, to exactly one of Donor Contact or Donor Account
  (R-G1 and Section 4 "Person references").
- **Gift to Household**, many to one, derived rather than entered (R-G2).
- **Gift to Gift Allocation**, one to many; the allocations are deleted with the gift.
- **Gift to Fund**, indirectly, through its allocations only. A gift has no fund
  reference of its own, because a gift can be split.
- **Gift to Appeal, Commitment, Installment, Tribute, Matched Gift, Original Gift**, many
  to one in each case.
- Gift is the source of almost every rollup in Section 26.

### Rules

**R-G1 Exactly one donor.** A gift has a Donor Contact or a Donor Account, never both and
never neither. Donor Account carries an organization, a household giving in its own name,
or a person Account, and the three are told apart by record type and by the dynamic
person-account test in Section 4, never by a static field reference.

**R-G2 Household is derived.** Household is written by the package, not by the user: from
the donor contact's household through `HouseholdService`, from the person Account's
household the same way in junction mode, from the Donor Account itself when that account
is a household, and left empty when the donor is an organization. It is derived when the
gift is saved and recomputed only when the gift's donor changes. A gift stays credited to
the household it was credited to when it was given: when the donor later moves households
(a reparent, a split, or a membership ending), their past gifts stay with the household
they left and only gifts given after the move are credited to the new one (ADR-0071,
`0071-a-gift-keeps-the-household-it-was-given-to.md`; R-H12). A household merge is not a
move: the platform account merge carries the merged household's gifts to the survivor
(R-H13). Household rollups reached through current membership, such as automatic household
soft credits, follow current membership instead.

**R-G3 Refunds and write-offs.** A refund or a write-off is a new gift with a negative
Amount and Original Gift set, never an edit and never a deletion (ADR-0010). The package
sets the original gift's Status to Refunded or Written off when the linked negative gift
is saved. The negative gift's own Status is Received, because it is a transaction that
happened, and it carries the same type and date semantics as any other gift. The reason the
money went back is typed once, on the negative gift, in Refund Reason: the original gift is
not edited to hold it, because editing the original is the thing this rule exists to
prevent. A partial refund leaves the original at Received, because part of it is still a
gift the organization holds. Only a Received gift is refunded or written off: a Pending gift
held no money to give back, and one that will never be paid is cancelled instead (R-G16,
ADR-0054).

**R-G4 Amount immutability.** Once a Receipt Number is present, Amount, Gift Date, the
donor references, and the In-kind Description do not change, and the gift is not deleted.
Receipt Number itself is written only by the receipting feature, from the sequence in
Section 25C: it is read only in every packaged permission set, a gift is never created
carrying one, and a save that sets, changes or clears it is refused unless the receipting
code is renumbering that gift (ADR-0033). A number typed in by hand belongs to no receipt,
locks the gift, can be issued again later by the sequence as a year end statement, and
leaves the gift permanently unreceiptable, so the first write is refused for the same
reason later ones are.
The in-kind description is in that list because it is printed on the document the donor
holds; Fair Market Value is not, because it never is (R-G12, ADR-0030). A correction voids the
receipt and reissues (ADR-0010). This is enforced in the domain layer from v0.2, before
the receipting feature exists in v0.4, so no early data escapes the rule. The enforcement
runs from its own automation, `Gift_Receipt_Lock`, which is marked Always Runs (R-A4), so
switching an automation off or pausing all automation does not lift the lock. The one way
past it is the `Override_Receipt_Lock` custom permission, which ships on no permission set
and in no permission set group: an administrator assigns it in Setup, makes the change, and
removes it again. Every change made under the override writes an Error Log entry at Warning
severity naming the gift, its receipt number, and what changed (ADR-0024).

**R-G5 Allocation totals.** Every gift's allocations total its Amount (R-GA1). A gift
saved with no allocation gets one allocation for the whole amount to the org's default
fund.

**R-G6 Automatic naming.** Name is assigned by the platform in the format `G-000001`.
Staff never type a gift name, and the number is not a receipt number.

**R-G7 Idempotent intake.** External Id is unique. The importer and the inbound API in
Mirror both match on it, so re-sending a gift never creates a second one. The inbound API
answers a resend with the gift already recorded and never edits it, so it cannot change a
receipted gift; a resend whose amount differs is refused as a conflict (ADR-0051).

**R-G8 Tribute link.** The authoritative link between a gift and a tribute is the
Tribute's own Gift reference (Section 25). The Gift's Tribute reference is a mirror the
package maintains, kept because gift list views, gift reports, and the receipt merge need
the tribute without a subquery.

**R-G9 Fields present before their feature.** Acknowledgment Status, Acknowledgment Date,
Receipt Number, In-kind Description, and Fair Market Value are defined in v0.2 and used
by v0.4 features (G-12, G-13, G-18). They ship in v0.2 so that `Gift__c` is not altered
later, which matters because altering a packaged object's field set after orgs hold data
is the change that upgrades handle worst.

**R-G10 No standard-object reference.** Nothing on this entity points at Opportunity or
Campaign. The mirrors live in Mirror (ADR-0004). The Opportunity mirror's Opportunity ID is a
text attribute Mirror adds to Gift, not a reference (Section 29C).

**R-G11 Matching gift linkage (G-10).** An employer's matching gift is linked to the
employee's gift through Matched Gift, which both records carry, so the link is visible
from either side. The link is accepted only when the employer's gift has an Account donor
whose record type is Organization and the employee's gift has a person donor, and, where
the employee's Employer is set, only when it names that same organization. Linking creates
one automatic soft credit on the employer's gift, crediting the employee with Role Matched
Donor and the employer gift's amount; unlinking clears both references and removes that
credit, together with the negative credits described below. A gift matches at most one
other gift. Neither gift may have been refunded or written off at the moment the link is
made: a link that outlived the money would go on crediting the employee for a match the
organization gave back.

A refund of a linked employer gift reverses that credit rather than removing it, the way
every other automatic credit reverses (R-SC5, ADR-0031). The negative gift recording the
refund or the write-off carries a negative Matched Donor credit for the same person,
prorated to the amount returned, so an employer gift of 500 with 200 returned leaves the
employee recognized for 300 and one fully returned leaves them recognized for nothing. A
refund of the *employee's* gift does not touch the credit: the employer's money is still
money the organization holds. The link itself survives a refund and is not cleared
automatically, because it is the record of what the money was.

**R-G12 In-kind gifts carry no amount (G-18, ADR-0030).** A gift of goods or services is a
Gift with Type In-kind. Its Amount is zero, because an in-kind gift is not money the
organization holds and no money rollup, report or dashboard may treat it as though it were,
and its worth is carried on Fair Market Value instead. An in-kind gift must carry an In-kind
Description, which is what the receipt prints; a gift that is not in-kind carries neither the
description nor the fair market value, so a type changed in error cannot leave a value behind
that later reads as an in-kind gift. Fair Market Value is never negative and never appears on
a rendered receipt or statement (R-RC7, R-RC12, ADR-0016): the donor substantiates what donated
property was worth, the organization describes what it received. In-kind giving is reported on
its own two rollups in Section 26, In-kind Value and In-kind Gift Count, so a donor of goods
has a total and a count without either one entering Total Giving, a donor level (ADR-0028) or
a retention report (ADR-0026). Because Amount is zero and never changes, a mistaken in-kind
gift is corrected by writing it off or by correcting the description, not by a negative gift:
R-G3 has nothing to reverse.

**R-G13 Posted to accounting (G-20, ADR-0053).** A gift is posted when Posted to Accounting is
set. Posted to Accounting and Posted to Accounting By are read only in every packaged
permission set and are written only by `GiftPostingService`, through `GiftPostingWriter` in
system mode (ADR-0021); any other save that sets, changes or clears them is refused by R-G14's
automation. Marking posted needs the `Post_Gifts` custom permission, touches only gifts that are
in the books (R-G14) and not yet posted, and leaves every other gift unchanged, so marking the
same gifts twice changes nothing. Unposting needs `Post_Gifts` and a reason, clears both
attributes, and writes an Error Log entry at Warning naming the gift, who posted it and when, and
the reason. A gift batch's Posted status (R-GB4) is a different thing: it says the batch's lines
became gifts, not that the gifts are in the books.

**R-G14 Posted gifts and closed periods are locked (G-20, ADR-0053).** A gift is **in the books**
when its Status is Received, Refunded or Written off and its Type is not In-kind, which is what
the accounting export reads (ADR-0051). A gift is **locked** when it is in the books and is either
posted (R-G13) or dated on or before Books Closed Through (Section 21A). While a gift is locked:

- Gift Date, Amount, Donor Contact, Donor Account, Type, Payment Reference and Original Gift do
  not change, and its allocations are not added, changed or deleted (R-GA5);
- its Status may move among Received, Refunded and Written off, which is what R-G3 does to an
  original, and may not move to Pending;
- it is not deleted.

No gift enters the books in a closed period: an insert, an undelete, or an update that leaves a
gift in the books and dated on or before Books Closed Through when it was not locked before, is
refused. A refund or write-off of a locked gift is a negative gift dated today, which is always
open because Books Closed Through is at least two days before today, so today is open in every
time zone and R-G3 is unaffected. A Pending gift is never written off (R-G3), so no reversal moves
one into the books; a Pending gift dated in a closed period that will never be paid is cancelled,
which the lock allows because neither Pending nor Cancelled is in the books (R-G16). Every other
attribute stays editable.

**R-G15 What a locked gift names is not deleted (G-20, ADR-0053).** Donor Contact, Donor Account
and Original Gift are cleared by the platform when the record they name is deleted, and no gift
trigger runs when that happens. So a person or organization that a locked gift names as donor,
and a gift that a locked gift names as its original, is not deleted. A merge is not a delete for
this rule: the losing record's gifts move to the surviving one (C-20). The same override and the
same Error Log entry as R-G14 apply.

**R-G16 A Pending gift that will never be paid is cancelled (ADR-0054).** Cancelled
is a status, not a money event: no negative gift is created, and a Cancelled gift is outside every
packaged giving total, the accounting export, receipts and statements, acknowledgments and the
retention reports, because each of them counts only Received, Refunded and Written off (Section
26, ADR-0022, ADR-0051). Status moves only these ways around it: Pending to Cancelled, and
Cancelled back to Pending when the gift turns out to be coming after all. No other status moves to
or from Cancelled, and Pending does not move to Refunded or Written off. A gift may be created
Cancelled, which is what an import of history needs. Cancelling unlinks the gift from the
installment it was expected to pay, so the installment is recalculated and is open for the next
gift, as a delete would leave it (R-CM4); the commitment link stays, as history, and moving the
gift back to Pending does not link it again. Its soft credits are kept and count nowhere, because
the soft credit totals read the gift's status (ADR-0023), and it is not half of a new matching gift
pair (R-G11). Every move into or out of Cancelled writes an Error Log entry at Info naming the
gift and who moved it. These rules run from the Gift core rules automation, so pausing automation
lets a data load set any status.

The enforcement runs from `Gift_Posting_Lock` and `Gift_Allocation_Posting_Lock`, both Always
Runs (R-A4). The one way past is the `Override_Posting_Lock` custom permission, on no permission
set: every save or delete it lets through writes an Error Log entry at Warning naming the gift and
what changed. It is separate from `Override_Receipt_Lock` (R-G4), which reaches nothing but the
receipt.

### Salesforce implementation

- **Object:** `Gift__c`, auto-number Name with format `G-{000000}`, private
  organization-wide default recommended (plan Section 4.13).

| Attribute | API name | Type |
|---|---|---|
| Donor Contact | `Donor_Contact__c` | Lookup to Contact |
| Donor Account | `Donor_Account__c` | Lookup to Account |
| Household | `Household__c` | Lookup to Account |
| Gift Date | `Gift_Date__c` | Date |
| Amount | `Amount__c` | Currency |
| Payment Method | `Type__c` | Picklist: Cash, Check, Card, ACH, Stock, In-kind, Grant, Other |
| Status | `Status__c` | Picklist: Received, Pending, Refunded, Written off, Cancelled |
| Appeal | `Appeal__c` | Lookup to `Appeal__c` |
| Acknowledgment Status | `Acknowledgment_Status__c` | Picklist: Not required, To acknowledge, Acknowledged, Do not acknowledge |
| Acknowledgment Date | `Acknowledgment_Date__c` | Date |
| Receipt Number | `Receipt_Number__c` | Text, External Id, unique, package written (R-G4) |
| Tribute | `Tribute__c` | Lookup to `Tribute__c` (v0.3) |
| Matched Gift | `Matched_Gift__c` | Lookup to `Gift__c` (v0.3) |
| Commitment | `Commitment__c` | Lookup to `Commitment__c` (v0.3) |
| Installment | `Installment__c` | Lookup to `Installment__c` (v0.3) |
| External Id | `External_Id__c` | Text, External Id, unique |
| Payment Reference | `Payment_Reference__c` | Text |
| Original Gift | `Original_Gift__c` | Lookup to `Gift__c` |
| Refund Reason | `Refund_Reason__c` | Text |
| In-kind Description | `In_Kind_Description__c` | Long Text Area (v0.4) |
| Fair Market Value | `Fair_Market_Value__c` | Currency (v0.4) |
| Benefit Description | `Benefit_Description__c` | Long Text Area (v0.4) |
| Benefit Value | `Benefit_Value__c` | Currency (v0.4) |
| Intangible Religious Benefits | `Intangible_Religious_Benefits__c` | Checkbox (v0.4) |
| Created By Import Batch | `Created_By_Import_Batch__c` | Lookup to `Import_Batch__c` |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |
| Posted to Accounting | `Accounting_Posted_At__c` | Date/Time, package written (v0.6, R-G13) |
| Posted to Accounting By | `Accounting_Posted_By__c` | Lookup to User, package written (v0.6, R-G13) |

- **Service:** `GiftService`, `GiftDomain`, `GiftSelector`, LWC `quickGiftEntry` (G-03).
- **Receipt lock:** handler `GiftReceiptLockHandler`, registry record
  `Automation_Registry.Gift_Receipt_Lock` (execution order 5, Always Runs), custom
  permission `Override_Receipt_Lock` (granted to nobody by the package).
- **Posting and period lock (G-20):** `GiftPostingLock` holds the R-G14 rules, run by
  `GiftPostingLockHandler` from registry record `Automation_Registry.Gift_Posting_Lock`
  (execution order 15, after `Gift_Core_Rules` fills in an empty date, Always Runs).
  `GiftPostingService` marks and unposts (R-G13) through `GiftPostingWriter`. Custom permissions
  `Post_Gifts` (on `Giving_Admin` and Mirror's `Accounting_Export`) and `Override_Posting_Lock`
  (granted to nobody). LWC `giftPosting` on the gift page shows the posting and offers Unpost; LWC
  `accountingPeriods` sets Books Closed Through.
- **Named records (R-G15):** `GiftPostingLock.enforceOnDelete` refuses deleting an original;
  `GiftDonorDeleteGuardHandler` runs on Contact and Account from registry records
  `Automation_Registry.Gift_Donor_Delete_Guard_Contact` and `..._Account` (Always Runs), through
  Core's own triggers.

---

## 19. Gift Allocation

### Definition

The part of a gift that belongs to one fund (plan Section 4.11). A gift that is entirely
unrestricted still has one allocation, so that fund totals are answered by one query and
never by two different rules.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The allocation's identifier, assigned automatically. |
| Gift | reference(Gift) | yes | The gift being split. |
| Fund | reference(Fund) | yes | The fund this part of the gift is designated to. |
| Amount | decimal | yes | The amount designated to this fund. |
| Percent | decimal | computed | This allocation's share of the gift, shown so staff can enter and check a split either way. |

### Relationships

- **Gift Allocation to Gift**, many to one, and allocations are deleted with their gift.
- **Gift Allocation to Fund**, many to one.

### Rules

**R-GA1 Allocations total the gift.** The allocations of a gift total its Amount exactly.
A save that would leave a gift over-allocated or under-allocated is rejected with a
message naming the difference. Percent is maintained from Amount, and an admin entering
percentages has them converted to amounts on save, with the rounding difference added to
the largest allocation so the total is exact.

**R-GA2 Default allocation.** A gift saved with no allocation receives one allocation for
its whole amount to the org's default fund (Section 12). This is what makes fund
reporting complete without asking staff to think about designation on every gift.

**R-GA3 Negative gifts allocate negatively.** A refund's allocations mirror the original
gift's allocations with negative amounts, so fund totals correct themselves.

**R-GA4 Appeal and donor defaults.** Where an appeal names a default fund, a gift entered
against that appeal is allocated to it unless staff choose otherwise. This is a proposal
in the entry form, never a rule that rewrites a saved allocation.

**R-GA5 A locked gift's allocations are fixed (G-20).** An allocation whose gift is locked
(R-G14) is not inserted, deleted, or changed in Fund, Amount or Percent, so each fund's share of a
gift in the books stays what the books hold. The same override and the same Error Log entry as
R-G14 apply.

### Salesforce implementation

- **Object:** `Gift_Allocation__c`, auto-number Name with format `GA-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Gift | `Gift__c` | Master-Detail to `Gift__c` |
| Fund | `Fund__c` | Lookup to `Fund__c` |
| Amount | `Amount__c` | Currency |
| Percent | `Percent__c` | Percent |

- **Service:** `AllocationService`, `AllocationDomain`.
- **Lock (R-GA5):** `GiftAllocationPostingLockHandler`, registry record
  `Automation_Registry.Gift_Allocation_Posting_Lock` (execution order 20, after
  `Gift_Allocation_Totals` works out the amount, Always Runs).

---

## 20. Fund

### Definition

A designation or restriction on how money may be used: the general fund, a building
fund, a scholarship fund, a restricted grant (plan Section 13). NPSP calls this a General
Accounting Unit and Nonprofit Cloud calls it a Gift Designation; the label the admin sees
is Fund (plan Section 7.1).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The fund's name as staff and the board know it, for example "Annual Fund". |
| Description | long text | no | What this fund pays for and any restriction attached to it. |
| Active | boolean | yes (defaults true) | Whether the fund is offered when allocating a new gift. |
| Restricted | boolean | yes (defaults false) | Whether a donor or funder limited this money to a purpose, which makes its balance a compliance obligation. |
| Accounting Code | text | no | The code this fund carries in the organization's accounting system, used by the export in Mirror. |
| Is Default | boolean | yes (defaults false) | Marks the fund that receives a gift with no explicit allocation. |

### Relationships

- **Fund to Gift Allocation**, one to many. A fund reaches gifts only through
  allocations.
- Fund is a rollup target (Section 26).

### Rules

**R-F1 One default fund.** At most one fund has Is Default true. Setting it on a second
fund clears the first, and the Setup Assistant's "pick default fund" step writes the
org's default fund key from this flag.

**R-F2 Deactivation, not deletion.** A fund that has received gifts is deactivated rather
than deleted, so historical allocations keep their meaning. Deletion is blocked while
allocations exist.

**R-F3 Accounting code uniqueness.** Accounting Code, where used, is unique, because the
accounting export keys on it.

**R-F4 The default fund key holds an identifier.** The org's default fund is held in the
Core settings key `Default_Fund__c` as a record identifier rather than a reference,
because Core cannot hold a lookup to a Giving object (ADR-0014). The Giving package
resolves it and the settings console presents a fund picker, so the admin never sees an
identifier.

### Salesforce implementation

- **Object:** `Fund__c`.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Active | `Active__c` | Checkbox |
| Restricted | `Restricted__c` | Checkbox |
| Accounting Code | `Accounting_Code__c` | Text, unique |
| Is Default | `Is_Default__c` | Checkbox |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

Rollup target attributes on `Fund__c` are listed in Section 26.

- **Service:** `FundService`.

---

## 21. Appeal

### Definition

A fundraising effort: a year-end mailing, a gala, a spring appeal, a giving day (plan
Section 13). The word campaign is avoided in the interface because Salesforce's Campaign
object means something specific and is unavailable on Platform licenses.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The appeal's name as staff know it, for example "Year-end mailing 2026". |
| Description | long text | no | What this appeal was, who it went to, and what it asked for. |
| Goal | decimal | no | The amount this appeal set out to raise. |
| Cost | decimal | no | What the appeal cost to run, so net return can be shown. |
| Start Date | date | no | The date the appeal went out or opened. |
| End Date | date | no | The date the appeal closed. |
| Parent Appeal | reference(Appeal) | no | The larger effort this appeal is part of, for example a gala within a capital campaign. |
| Active | boolean | yes (defaults true) | Whether the appeal is offered when entering a new gift. |
| Net Raised | decimal | computed | Total raised less cost, calculated live from the two values. |
| Percent To Goal | decimal | computed | Total raised as a share of goal, calculated live, empty when no goal is set. The Percent formula returns the plain ratio (0.5 for half) and Salesforce displays it as 50%. |

### Relationships

- **Gift to Appeal**, many to one. Response rollups are not attributes an admin fills in;
  they arrive as Rollup Definitions (Section 26).
- **Appeal to Parent Appeal**, many to one, forming a shallow hierarchy.
- **Commitment to Appeal**, many to one, from v0.3.

### Rules

**R-AP1 Response numbers come from rollups.** Total raised, gift count, and the
fiscal-year windows on an appeal are packaged Rollup Definitions, not fields staff or
automation write by hand. This is the same engine every other total uses, so the numbers
cannot drift apart (plan Section 4.10).

**R-AP2 Hierarchy without recursion.** Parent Appeal may not form a cycle, and a parent's
packaged totals count gifts given directly to the parent only. Totals across a hierarchy
come from a grouped report, because a recursive rollup is a materially harder engine and
nothing in the plan requires one.

**R-AP3 Net and percent are calculated live.** Net Raised and Percent To Goal are derived
from Total Raised, Cost, and Goal at read time, so they carry no staleness and need no
recalculation.

**R-AP4 No Campaign reference.** An optional link to a standard Campaign exists only in
Mirror (plan Section 4.12): the Campaign ID attribute and the one-way copy of Section 29B,
both shipped by the Mirror package, so Giving itself never names Campaign.

### Salesforce implementation

- **Object:** `Appeal__c`.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Goal | `Goal__c` | Currency |
| Cost | `Cost__c` | Currency |
| Start Date | `Start_Date__c` | Date |
| End Date | `End_Date__c` | Date |
| Parent Appeal | `Parent_Appeal__c` | Lookup to `Appeal__c` |
| Active | `Active__c` | Checkbox |
| Net Raised | `Net_Raised__c` | Formula (Currency) |
| Percent To Goal | `Percent_To_Goal__c` | Formula (Percent) |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

Rollup target attributes on `Appeal__c` are listed in Section 26.

- **Service:** `AppealService`.

---

## 21A. Giving Settings

### Definition

The Giving module's own org-wide toggles and values. ADR-0017 gives every module package
its own protected hierarchy custom setting, because a dependent package cannot add fields
to the Core settings object and Core must not carry fields for modules that are not
installed (Principle 3).

Core keeps the settings that Core itself reads. Everything that only the Giving package reads
lives here, including, from v0.6, the default fund and appeal and the receipt identity keys
that C-29 moved out of Core (ADR-0059).

### v0.3 keys

Moved here from Section 12 by ADR-0017, with their definitions unchanged.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Automatic_Household_Soft_Credits__c` | boolean | true | Whether a gift from one household member automatically soft credits the household's other current members (R-SC3). |
| `Installment_Generation_Horizon_Months__c` | integer | 12 | How far ahead installments are generated for an open-ended recurring commitment, so the schedule does not generate rows forever (R-CM2). |
| `Installment_Overdue_Grace_Days__c` | integer | 5 | How many days after its due date an unpaid installment waits before it is marked Overdue (R-IN2). |

### v0.4 keys

| Key | Type | Default | Definition |
|---|---|---|---|
| `Donor_Levels_Enabled__c` | boolean | false | Whether donor levels are assigned at all. Off until the organization has built its ladder, because a wrong ladder is worse than none (R-DL7). |
| `Donor_Level_Source_Field__c` | text | `Total_Giving__c` | Which giving total the ladder is measured on, named as one of the packaged rollup attributes of Section 26 (R-DL1). Stored as text under ADR-0019. |
| `Donor_Levels_Last_Recalculated__c` | datetime | empty | When the nightly or on demand level pass last completed, shown read only on the Donor Levels page, the same freshness promise the rollups make (Principle 2). |
| `Installment_Top_Up_Last_Run_Summary__c` | text | empty | What the last top up run did, in one sentence: how many recurring commitments were extended, and how many chunks failed. A timestamp on its own says the job woke up, not that it did anything (R-IN5). |
| `Installment_Overdue_Last_Run__c` | datetime | empty | When the overdue pass last completed, whether or not it marked anything. Empty means the pass has never run in this org, which is a different thing from a pass that ran and found nothing overdue (R-IN2, R-IN5). |
| `Installment_Overdue_Last_Run_Summary__c` | text | empty | What the last overdue pass did, in one sentence: how many payments it marked Overdue, or that it found none (R-IN5). |

Added by acknowledgments (G-12, ADR-0032).

| Key | Type | Default | Definition |
|---|---|---|---|
| `Acknowledgments_Enabled__c` | boolean | false | Whether gifts are placed in the acknowledgment queue as they are saved. Off until the organization has written its rules, because a thank you that goes out with the wrong wording cannot be recalled (R-AK5). |
| `Acknowledgment_From_Address__c` | text | empty | The organization wide email address acknowledgments are sent from, named by its address. Empty means they are sent from the user who ran the send, which is what a small organization usually wants. |
| `Acknowledgments_Last_Run__c` | datetime | empty | When the last acknowledgment send finished, shown read only on the Acknowledgments page (R-AK12). |
| `Acknowledgments_Last_Run_Summary__c` | text | empty | What that run did, in one sentence, because a bare timestamp says the job woke up and not that it sent anything (R-AK12). |
Added by receipting (G-13). The organization's legal name and address, which a receipt
prints, are Core keys on `BarnCRM_Settings__c` (Section 12): any organization has them. The
tax identification number, the logo, the signature and the signer's name and title were Core
keys until v0.6 and are Giving keys now (see the v0.6 table below).

| Key | Type | Default | Definition |
|---|---|---|---|
| `Receipt_Number_Prefix__c` | text | R | The prefix printed before the year and the counter in a receipt number (R-RS2). |
| `Receipt_Next_Counter__c` | integer | 1 | The counter a new numbering series starts at, so an organization moving from another system continues its own sequence. |
| `Receipt_Statement_Year__c` | integer | empty | The tax year the year end run reports on, which an administrator sets in January and leaves alone. |
| `Receipt_Place_Of_Issue__c` | text | empty | The city and region the receipt is issued from, printed on the document. |
| `Receipt_Renderer__c` | text | empty | Which renderer produces the PDF, as one of the two keys ADR-0016 names (`Blob PDF`, `Visualforce`) and never a class name; empty means the shipped one. A key outside that list is refused before any class is resolved or constructed. Stored as text and validated in Apex per ADR-0019. It exists because ADR-0016 names a fallback implementation and the spike that would settle the question needs an org (ADR-0016, "Consequences"). |
| `Receipt_Print_Logo__c` | boolean | true | Whether the organization's logo is printed on receipts and statements. Off is a complete answer: a receipt with no images is a valid receipt (R-RC13), and this is also the switch an organization uses if the image path turns out not to work in its org. |
| `Receipt_Logo_Width_Mm__c` | integer | 40 | How wide the logo prints, in millimetres. One number rather than a style sheet: a wordmark and a square crest cannot both look right at one fixed width, and the template is not the place to fix that (ADR-0016, "the admin edits text and tokens, not CSS"). |
| `Receipt_Logo_Delivery__c` | text | empty | Which of ADR-0016's three image routes the logo is delivered by: empty means the shipped route, the file download URL. It exists for the same reason `Receipt_Renderer__c` does, and it is retired when the second spike closes (R-RC13). Stored as text under ADR-0019. |

### v0.5 keys

Added by donation matching (G-24). Shown in the console's Import section, beside the Core
import settings, because that is where an administrator looks for how an import behaves.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Donation_Match_Date_Window_Days__c` | integer | 7 | How many days either side of a scheduled payment's due date an imported gift may fall and still be matched to it, for a template that does not set its own (R-DM3). |
| `Donation_Match_Amount_Tolerance__c` | decimal | 0 | How far an imported gift's amount may differ from a scheduled payment's expected amount and still be matched to it, for a template that does not set its own; zero means the amounts must be equal (R-DM3). |

### v0.6 keys

Added by the posting flag and period lock (G-20, ADR-0053). Set on the Accounting Periods page,
reached from the Giving section of the console, and deliberately not named by a Setting
Definition row, so the console's generic save cannot write it past the page's checks.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Books_Closed_Through__c` | date | empty | The last day of the latest closed accounting period; empty means no period is closed. Gifts in the books dated on or before it are locked (R-G14). It is at least two days before today (so today is open in every time zone) and moves only forward; moving it back or clearing it needs `Override_Posting_Lock` and writes an Error Log entry at Warning. Every change is a Setting Change. |

Moved from `BarnCRM_Settings__c` by C-29 (ADR-0059), API names unchanged. The Setup Assistant
writes them through the steps Giving contributes, and the console shows them in the sections
it showed them in before.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Organization_EIN__c` | text (20) | empty | The organization's tax identification number (the EIN in the United States), printed on receipts. Moved from Section 12 by C-29. |
| `Receipt_Logo_Document_Id__c` | text (18) | empty | The Salesforce file identifier of the logo printed on receipts and letters. Moved from Section 12 by C-29. |
| `Receipt_Signature_Document_Id__c` | text (18) | empty | The Salesforce file identifier of the scanned signature printed on receipt letters. Moved from Section 12 by C-29. |
| `Receipt_Signer_Name__c` | text (80) | empty | The name of the person who signs receipt letters. Moved from Section 12 by C-29. |
| `Receipt_Signer_Title__c` | text (80) | empty | The job title of the person who signs receipt letters. Moved from Section 12 by C-29. |
| `Default_Fund__c` | text (18) | empty | The record identifier of the fund a gift is allocated to when nobody says otherwise, chosen in the Setup Assistant's fund and appeal step, which Giving contributes (R-F4, ADR-0014). Moved from Section 12 by C-29. |
| `Default_Appeal__c` | text (18) | empty | The record identifier of the appeal a gift is credited to when nobody says otherwise, on the same terms as the default fund. Moved from Section 12 by C-29. |

### Rules

**R-GS1 Same contract as Core settings.** Protected, hierarchical, written synchronously
from the settings console and never from Setup, audited as a Setting Change, and extended
only by adding a row to the table above in the pull request that adds the field (R-N1 to
R-N5 apply unchanged).

**R-GS2 One console, several settings objects.** The Giving keys appear in the same
BarnCRM Settings console as the Core keys, in the Giving section (the moved receipt
identity keys in the Organization section, beside the legal name they print with). The console reaches
them because each shipped `Setting_Definition__mdt` row names its settings object, so an
administrator never learns that there is more than one place the values are stored.

**R-GS3 Absent module, absent setting.** An org without the Giving package has none of
these keys, which is what makes a module that is off leave nothing behind.

### Salesforce implementation

- **Custom setting:** `Giving_Settings__c`, hierarchy, protected.

| Attribute | API name | Type |
|---|---|---|
| Automatic Household Soft Credits | `Automatic_Household_Soft_Credits__c` | Checkbox |
| Installment Generation Horizon Months | `Installment_Generation_Horizon_Months__c` | Number(18, 0) |
| Installment Overdue Grace Days | `Installment_Overdue_Grace_Days__c` | Number(18, 0) |
| Auto Apply Gifts To Installments | `Auto_Apply_Gifts_To_Installments__c` | Checkbox |
| Installment Top Up Last Run | `Installment_Top_Up_Last_Run__c` | Date/Time |
| Installment Top Up Last Run Summary | `Installment_Top_Up_Last_Run_Summary__c` | Text(255) |
| Installment Overdue Last Run | `Installment_Overdue_Last_Run__c` | Date/Time |
| Installment Overdue Last Run Summary | `Installment_Overdue_Last_Run_Summary__c` | Text(255) |
| Receipt Number Prefix | `Receipt_Number_Prefix__c` | Text(10) |
| Receipt Next Counter | `Receipt_Next_Counter__c` | Number(18, 0) |
| Receipt Statement Year | `Receipt_Statement_Year__c` | Number(4, 0) |
| Receipt Place Of Issue | `Receipt_Place_Of_Issue__c` | Text(80) |
| Receipt Renderer | `Receipt_Renderer__c` | Text(60) |
| Receipt Print Logo | `Receipt_Print_Logo__c` | Checkbox |
| Receipt Logo Width Mm | `Receipt_Logo_Width_Mm__c` | Number(3, 0) |
| Receipt Logo Delivery | `Receipt_Logo_Delivery__c` | Text(40) |
| Acknowledgments Enabled | `Acknowledgments_Enabled__c` | Checkbox |
| Acknowledgment From Address | `Acknowledgment_From_Address__c` | Text(255) |
| Acknowledgments Last Run | `Acknowledgments_Last_Run__c` | Date/Time |
| Acknowledgments Last Run Summary | `Acknowledgments_Last_Run_Summary__c` | Text(255) |
| Donation Match Date Window Days | `Donation_Match_Date_Window_Days__c` | Number(3, 0) |
| Donation Match Amount Tolerance | `Donation_Match_Amount_Tolerance__c` | Currency(16, 2) |
| Books Closed Through | `Books_Closed_Through__c` | Date (v0.6) |
| Organization EIN | `Organization_EIN__c` | Text(20) (v0.6, from Core) |
| Receipt Logo Document Id | `Receipt_Logo_Document_Id__c` | Text(18) (v0.6, from Core) |
| Receipt Signature Document Id | `Receipt_Signature_Document_Id__c` | Text(18) (v0.6, from Core) |
| Receipt Signer Name | `Receipt_Signer_Name__c` | Text(80) (v0.6, from Core) |
| Receipt Signer Title | `Receipt_Signer_Title__c` | Text(80) (v0.6, from Core) |
| Default Fund | `Default_Fund__c` | Text(18) (v0.6, from Core) |
| Default Appeal | `Default_Appeal__c` | Text(18) (v0.6, from Core) |

- **Service:** Core `SettingsService`, reading and writing this object through the
  `Settings_Object__c` field on `Setting_Definition__mdt` (ADR-0017).

---

## 22. Commitment

### Definition

A promise to give: a pledge with a fixed total paid in installments, or a recurring gift
with an open-ended schedule (plan Section 13, feature G-07, v0.3). One entity covers both
because the difference between them is a type and an end condition, not a different shape
of data.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The commitment's identifier, assigned automatically. |
| Type | picklist(Pledge, Recurring) | yes | Pledge is a fixed total paid over time; Recurring is an open-ended schedule. |
| Donor Contact | reference(Contact) | conditional | The person who made the commitment, where people are Contacts. |
| Donor Account | reference(Organization) | conditional | The account that made the commitment: an organization, a household, or a person Account. |
| Household | reference(Household) | computed | The household credited with the commitment, derived exactly as a gift's is (R-G2). |
| Amount | decimal | yes | The amount expected in each installment. |
| Frequency | picklist(Weekly, Every two weeks, Monthly, Quarterly, Twice a year, Yearly) | yes | How often an installment falls due. |
| Day of Month | integer | no | The day an installment falls due for monthly and less frequent schedules; a day past the end of a short month falls on that month's last day. |
| Start Date | date | yes | The date the first installment falls due. |
| End Date | date | conditional | The date the schedule ends; required for a pledge, empty for an open-ended recurring gift. |
| Status | picklist(Active, Paused, Completed, Cancelled) | yes (defaults Active) | Where the commitment stands. |
| Expected Total | decimal | conditional | The total promised; required for a pledge, empty for an open-ended recurring gift. |
| Installments Planned | integer | conditional | How many installments the pledge is paid in; required for a pledge. |
| Fund | reference(Fund) | no | The fund the gifts paying this commitment are allocated to by default. |
| Appeal | reference(Appeal) | no | The fundraising effort this commitment came from. |
| Paid To Date | decimal | computed | The total of gifts received against this commitment (Section 26). |
| Balance | decimal | computed | Expected Total less Paid To Date, calculated live (R-CM5). |

### Relationships

- **Commitment to Donor**, many to one, to exactly one of Donor Contact or Donor Account
  (Section 4 "Person references").
- **Commitment to Installment**, one to many; installments are deleted with the
  commitment.
- **Gift to Commitment**, many to one, directly and through the installment a gift pays.
- **Commitment to Fund and Appeal**, many to one.

### Rules

**R-CM1 Exactly one donor.** As R-G1, and the household is derived the same way.

**R-CM2 Installment generation.** The package generates installments from Start Date,
Frequency, Day of Month, and either Installments Planned (a pledge) or the org's
generation horizon (a recurring gift, so an open-ended schedule does not generate rows
forever). Generation is idempotent: regenerating never duplicates an installment and
never deletes one that has a gift against it.

**R-CM3 Pause and cancel.** Pausing stops generation and leaves existing installments in
place. Cancelling stops generation and marks unpaid future installments Skipped. Neither
deletes history.

**R-CM4 Completion.** A pledge is Completed when its balance reaches zero or below. A
recurring commitment is never completed automatically; it ends when staff cancel it or
when End Date passes. Deleting a gift undoes what it did: the installment it paid takes its
status again from the gifts still linked (R-IN2), and a Completed pledge that was fully paid
with the deleted gifts' received amounts and is not without them is Active again. A pledge
staff completed short of its total stays Completed, because no deleted gift completed it.
Restoring a gift from the recycle bin applies it again.

**R-CM5 Balance is calculated live.** Balance is Expected Total less Paid To Date for a
pledge and empty for a recurring commitment, which has no expected total to subtract
from. It is derived at read time rather than stored, because a difference of two numbers on the same record
cannot be stale and needs no recalculation pass. The household-level pledge balance
aggregates this value (Section 26). If the aggregation engine chosen in ADR-0011 cannot
aggregate a calculated attribute, Balance becomes a stored attribute written by the
commitment domain in the same transaction as Paid To Date, and this rule is updated with
the reason.

**R-CM6 Amount changes are forward-looking.** Changing Amount or Frequency regenerates
future installments only. Installments that are paid or partially paid are never
rewritten, because a gift already refers to them.

### Salesforce implementation

- **Object:** `Commitment__c`, auto-number Name with format `CM-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Type | `Type__c` | Picklist: Pledge, Recurring |
| Donor Contact | `Donor_Contact__c` | Lookup to Contact |
| Donor Account | `Donor_Account__c` | Lookup to Account |
| Household | `Household__c` | Lookup to Account |
| Amount | `Amount__c` | Currency |
| Frequency | `Frequency__c` | Picklist: Weekly, Every two weeks, Monthly, Quarterly, Twice a year, Yearly |
| Day of Month | `Day_of_Month__c` | Number (0 decimals) |
| Start Date | `Start_Date__c` | Date |
| End Date | `End_Date__c` | Date |
| Status | `Status__c` | Picklist: Active, Paused, Completed, Cancelled |
| Expected Total | `Expected_Total__c` | Currency |
| Installments Planned | `Installments_Planned__c` | Number (0 decimals) |
| Fund | `Fund__c` | Lookup to `Fund__c` |
| Appeal | `Appeal__c` | Lookup to `Appeal__c` |
| Balance | `Balance__c` | Formula (Currency) |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

Rollup target attributes on `Commitment__c`, including Paid To Date, are listed in
Section 26.

- **Settings keys** (on `Giving_Settings__c`, Section 12):
  `Installment_Generation_Horizon_Months__c`, `Auto_Apply_Gifts_To_Installments__c`,
  `Installment_Top_Up_Last_Run__c`, `Installment_Top_Up_Last_Run_Summary__c`.
- **Service:** `CommitmentService`, `CommitmentSelector`, `CommitmentTriggerHandler`,
  `GiftCommitmentHandler`, `InstallmentTopUpSchedulable`, `InstallmentTopUpBatch`,
  `GivingScheduler`, `GivingJobsController`.

---

## 23. Installment

### Definition

One expected payment on a commitment: what is due, when, and what has been paid against
it (plan Section 4.11, feature G-07, v0.3). Overdue and upcoming reports are queries over
this entity, which is why it exists rather than being computed on the fly.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The installment's identifier, assigned automatically. |
| Commitment | reference(Commitment) | yes | The commitment this installment belongs to. |
| Sequence | integer | yes | The installment's position in the schedule, counting from one. |
| Due Date | date | yes | The date this installment is expected. |
| Expected Amount | decimal | yes | The amount expected on that date. |
| Status | picklist(Scheduled, Paid, Partially paid, Overdue, Skipped) | yes (defaults Scheduled) | Where this installment stands. |
| Paid Amount | decimal | computed | The total of gifts received against this installment (Section 26). |

### Relationships

- **Installment to Commitment**, many to one, and installments are deleted with their
  commitment.
- **Gift to Installment**, many to one: one installment can be paid by more than one
  gift, which is what makes partial payment representable.

### Rules

**R-IN1 Generated, not typed.** Installments are created by the package from the
commitment schedule (R-CM2). Staff may change a due date or an expected amount on a
single installment, and regeneration respects a changed row rather than overwriting it.

**R-IN2 Status is derived.** Paid when Paid Amount reaches Expected Amount, Partially
paid when it is above zero and below it, Overdue when it is below Expected Amount and the
due date is more than the org's grace period in the past, Scheduled otherwise. Skipped is
the one status only a person sets.

**R-IN3 Payment linkage.** A gift pays an installment by referencing it. The gift also
carries the commitment, so a payment that does not correspond to any scheduled
installment still counts toward the commitment. A gift that names a commitment and no
installment is linked to that commitment's earliest unpaid installment by the package
when `Auto_Apply_Gifts_To_Installments__c` is true, which is the default, because staff
entering a cheque against a pledge know the pledge and not the row number.

**R-IN4 Sequence is stable.** Sequence is assigned at generation and does not change when
an installment is skipped or paid late, so an installment can be named the same way in a
report a year later.

**R-IN5 The nightly passes are switched on in the console and visible there.** Nothing in
the Giving module marks an installment Overdue or extends a recurring schedule until an
administrator schedules the nightly jobs from the Nightly Jobs page of the Nonprofit
Settings console, and the same page stops them (ADR-0031). Each pass records when it last
finished and one sentence saying what it did, whether or not it changed anything, so a
pass that ran and found nothing overdue reads differently from a pass that never ran. The
console warns that a pass is stale only when the jobs are scheduled: an org that has not
switched them on is told that instead, because it has not missed a run that was never
going to happen. A failure inside a pass goes to the Error Log and the rest of the run
carries on (R-E1).

### Salesforce implementation

- **Object:** `Installment__c`, auto-number Name with format `IN-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Commitment | `Commitment__c` | Master-Detail to `Commitment__c` |
| Sequence | `Sequence__c` | Number (0 decimals) |
| Due Date | `Due_Date__c` | Date |
| Expected Amount | `Expected_Amount__c` | Currency |
| Status | `Status__c` | Picklist: Scheduled, Paid, Partially paid, Overdue, Skipped |

Rollup target attributes on `Installment__c`, including Paid Amount, are listed in
Section 26.

- **Settings keys** (on `Giving_Settings__c`, Section 12): `Installment_Overdue_Grace_Days__c`.
- **Service:** `InstallmentSelector`, `InstallmentTriggerHandler`, `InstallmentSchedulable`.

---

## 24. Soft Credit

### Definition

Recognition for influencing a gift without legally giving it: a spouse, a solicitor, an
honoree, an employer whose match the gift produced (plan Section 13, feature G-08, v0.3).
A soft credit never changes who is hard credited, and it is never added into a hard credit
total.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The soft credit's identifier, assigned automatically. |
| Gift | reference(Gift) | yes | The gift being credited. |
| Contact | reference(Contact) | conditional | The person credited, where people are Contacts. |
| Account | reference(Organization) | conditional | The account credited: an organization, a household, or a person Account. |
| Role | picklist(Household Member, Matched Donor, Solicitor, Honoree, Influencer, Other) | yes | Why this person or organization is credited. |
| Custom Role | text | conditional | The role in the org's own words; required when Role is Other. |
| Amount | decimal | yes | The amount credited, which defaults to the gift's amount. |
| Percent | decimal | computed | The credited amount as a share of the gift. |
| Is Automatic | boolean | yes (defaults false) | Marks a credit the package created and maintains, as opposed to one a person entered. |

### Relationships

- **Soft Credit to Gift**, many to one, and soft credits are deleted with their gift.
- **Soft Credit to the credited party**, many to one, to exactly one of Contact or Account
  (Section 4 "Person references").

### Rules

**R-SC1 Exactly one credited party.** Contact or Account, never both and never neither.

**R-SC2 Soft credits are never hard credits.** No packaged rollup adds a soft credit into
a total giving attribute. Soft credit totals are their own attributes (Section 26), and
the interface always labels them as recognition.

**R-SC3 Automatic household-member credits.** When the org's automatic household soft
credit setting is on, every current member of the donor's household other than the donor
receives a soft credit with Role Household Member, Is Automatic true, and the gift's full
amount. This holds for every gift, including a negative gift recording a refund, whose
credits are negative in the same way, and including a gift whose own status has since
become Refunded or Written off (R-SC5). These records are maintained by the package: they
are recreated when household membership changes and removed when the setting is turned
off. A credit a person entered
is never touched by that maintenance, which is what Is Automatic is for.

**R-SC4 Amounts may exceed the gift.** The soft credits on a gift may total more than the
gift, because two people can each be recognized for the whole of it. This is recognition,
not accounting, and no validation caps it.

**R-SC5 Negative gifts.** A refund produces matching negative soft credits, so recognition
totals correct themselves the same way giving totals do. That negative credit is the only
reversal recognition gets: the gift being refunded keeps the credits it earned, and the
two rows cancel. A gift of 250 refunded in full leaves a credit of 250 on the original and
a credit of minus 250 on the negative gift, and the recognition total is zero (ADR-0023).
This holds for every automatic credit, whatever its role. A household credit follows the
donor onto the negative gift; a Matched Donor credit is mirrored onto the negative gift
that reverses the employer's gift, prorated to the amount returned, so a partial refund
nets to the amount the employer still holds (R-G11, ADR-0031).

**R-SC3a How a membership change reaches the credits.** The recompute a membership change
causes is queued, not done in the saving transaction: a household's giving history has no
bound, and moving one person between households must not fail on the size of it. The most
recent 500 gifts of each affected household are recomputed, a bound set by the soft credit
rows they imply rather than by the gifts themselves; a household that has given more than
that has the rest corrected the next time each of those gifts is saved.

**R-SC6 Automatic credits are recomputed, not accumulated.** The package recomputes a
gift's automatic credits whenever its donor, its amount, or its status changes, and
removes them when the gift is deleted. A refund does not remove them: the reversal is
R-SC5's negative credit, and doing both would take a fully refunded gift's recognition to
minus its own amount rather than to zero (ADR-0023). A status change therefore still
triggers a recompute but no longer changes its outcome. Recomputation is idempotent:
running it twice over the same gift leaves the same records. Manual credits are never
read, changed, or deleted by it.

**R-SC7 A credited party is credited once per gift and role.** Two automatic credits for
the same person, the same gift, and the same role are a duplicate, and the package keeps
the first. Staff may still enter a manual credit for a person who already holds an
automatic one, because a spouse can also be the solicitor.

### Salesforce implementation

- **Object:** `Soft_Credit__c`, auto-number Name with format `SC-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Gift | `Gift__c` | Master-Detail to `Gift__c` |
| Contact | `Contact__c` | Lookup to Contact |
| Account | `Account__c` | Lookup to Account |
| Role | `Role__c` | Picklist: Household Member, Matched Donor, Solicitor, Honoree, Influencer, Other |
| Custom Role | `Custom_Role__c` | Text |
| Amount | `Amount__c` | Currency |
| Percent | `Percent__c` | Percent |
| Is Automatic | `Is_Automatic__c` | Checkbox |

- **Settings keys:** `Automatic_Household_Soft_Credits__c` (Section 12).
- **Service:** `SoftCreditService`, `SoftCreditDomain`.

---

## 25. Tribute

### Definition

The honor or memorial a gift was given under, and who should be told about it (plan
Section 13, feature G-09, v0.3). A tribute is what turns a memorial gift into a letter the
family receives.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The tribute's identifier, assigned automatically. |
| Gift | reference(Gift) | yes | The gift given in honor or in memory. |
| Type | picklist(In honor of, In memory of) | yes | Whether the person honored is living or has died, which changes the letter. |
| Honoree Name | text | conditional | The name of the person honored, as the donor gave it; required when there is no honoree record. |
| Honoree Contact | reference(Contact) | no | The person honored, where they are a Contact the org knows. |
| Honoree Account | reference(Organization) | no | The person honored, where people are person Accounts. |
| Notification Recipient Contact | reference(Contact) | no | The person to be told about the gift, where they are a Contact. |
| Notification Recipient Account | reference(Organization) | no | The person to be told about the gift, where people are person Accounts. |
| Notification Recipient Name | text | no | The name and address of the person to be told, where they are not a record in the org. |
| Notification Sent | boolean | yes (defaults false) | Whether the notification has gone out. |
| Notification Sent Date | date | no | The date the notification was sent. |
| Message | long text | no | What the donor asked to be conveyed, quoted in the notification. |

### Relationships

- **Tribute to Gift**, many to one, and a tribute is deleted with its gift.
- **Tribute to Honoree** and **Tribute to Notification Recipient**, many to one, each to
  a Contact or a person Account, never both (Section 4 "Person references").

### Rules

**R-TR1 One tribute per gift.** At most one tribute exists for a gift, enforced in the
domain layer, and the gift carries a mirror reference to it (R-G8).

**R-TR2 An honoree does not have to be a record.** Honoree Name stands alone when the
person honored is not in the database, which is the common case for memorials. At least
one of Honoree Name, Honoree Contact, or Honoree Account is present.

**R-TR3 Notification without a record.** The same is true of the notification recipient:
a name and address is enough, and creating a Contact for a bereaved family is a choice the
org makes, not a thing the package requires.

**R-TR4 Sent date follows the flag.** Notification Sent Date is written when Notification
Sent is set, and neither is cleared by automation once set.

**R-TR5 Never an amount.** A tribute never states the gift's amount, because the
notification to a family does not disclose it.

**R-TR6 A memorial is never notified to the person who died.** An In memory of tribute
whose honoree is a record marked deceased, whether that record is a Contact or an Account,
may not name that same person as the notification recipient. Notifying an honoree who is
not marked deceased is allowed, because an In honor of gift to a foundation may quite
properly tell that foundation. The message says who is named and what to do, because the usual
cause is picking the wrong name from a list.

### Salesforce implementation

- **Object:** `Tribute__c`, auto-number Name with format `TR-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Gift | `Gift__c` | Master-Detail to `Gift__c` |
| Type | `Type__c` | Picklist: In honor of, In memory of |
| Honoree Name | `Honoree_Name__c` | Text |
| Honoree Contact | `Honoree_Contact__c` | Lookup to Contact |
| Honoree Account | `Honoree_Account__c` | Lookup to Account |
| Notification Recipient Contact | `Notification_Recipient_Contact__c` | Lookup to Contact |
| Notification Recipient Account | `Notification_Recipient_Account__c` | Lookup to Account |
| Notification Recipient Name | `Notification_Recipient_Name__c` | Text |
| Notification Sent | `Notification_Sent__c` | Checkbox |
| Notification Sent Date | `Notification_Sent_Date__c` | Date |
| Message | `Message__c` | Long Text Area |

- **Service:** `TributeService`.

---

## 25A. Donor Level

### Definition

One rung of the organization's giving ladder: a name a nonprofit uses for a group of
donors ("Leadership Circle", "Sustainer"), and the amount at which a donor reaches it.
The NPSP Levels successor (plan Section 5.2, feature G-14).

A level is not a calculation. It is a label put on a number that has already been
calculated: the giving totals the packaged rollups maintain on the donor's own record
(Section 26). That is what keeps a donor's level and the total shown next to it from
disagreeing, and it is why nothing here aggregates a gift.
## 25B. Receipt

### Definition

The record of a document a donor is holding (feature G-13, v0.4, ADR-0010 and ADR-0016). A
receipt is not an internal note: in the United States it is what a donor files with a tax
return, so once it is issued its number, its amount, its date and its stored PDF are facts
about the world and none of them change. A correction is a void and a new receipt, never an
edit.

Two kinds exist. A **per gift** receipt covers one gift. A **consolidated statement** covers
every qualifying gift a donor gave in one statement year, which is what most organizations
send in January.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the organization calls this group of donors, as it appears on the donor's record and in reports. |
| Description | long text | no | What the level means and what a donor at it is offered, in the organization's own words. |
| Minimum Amount | currency | yes | The amount at which a donor reaches this level. A donor whose amount equals it is at this level. |
| Maximum Amount | currency | no | The amount at which a donor has passed beyond this level. A donor whose amount equals it is at the next level up. Empty means this is the top of the ladder. |
| Active | boolean | yes (defaults true) | Whether the level takes part in assignment. An inactive level keeps its name on the donors already at it and receives nobody new. |

### Relationships

- **Donor Level to donor**, one to many, in two directions: the level a donor is at now,
  and the level that donor was at before (R-DL4). The donor is a Household, an
  Organization, a person Account, or a Contact (R-DL3).
- Donor Level has no reference to Gift, to Rollup Definition, or to any settings record.
  Which number the ladder is measured on is a setting (Section 21A), not a reference.

### Rules

**R-DL1 One ladder, measured on one number.** The active levels form a single ladder for
the whole organization, ordered by Minimum Amount, and every donor is placed on it by one
number: the giving total named by `Donor_Level_Source_Field__c` (Section 21A). That
setting names one of the packaged rollup attributes of Section 26, so the number a level
is measured on is a number the donor's record already shows, calculated once by the rollup
engine under the status filter of ADR-0022, and never recalculated here. A ladder measured
on a second, privately calculated number would disagree with the donor's own total on
screen, which is the defect this rule exists to prevent.

**R-DL2 Which level a donor is at.** The assigned level is the active level with the
greatest Minimum Amount that is at most the donor's amount, and whose Maximum Amount is
empty or greater than that amount. A donor whose amount is below every Minimum Amount, or
whose amount is empty, is at no level, and no level is a legitimate answer rather than an
error. Where two active levels overlap, the one with the greater Minimum Amount wins, so
a badly built ladder is still deterministic.

**R-DL3 Whose level it is.** Three kinds of record carry a level, and they are exactly the
three the giving totals of Section 26 are written to: a Household Account, an Account that
is an organization or a person, and a Contact. A household and its members can therefore
sit at different levels, which is correct: they are answers to different questions, and
each one is read from the total on that same record.

Household membership mode does not enter into it. Because the level reads a total already
written to the record, the household membership abstraction was applied when that total
was calculated (R-R1), and no membership is resolved a second time here. Contact mode and
junction mode give the same result for the same reason.

**R-DL4 Previous level, and movement.** When assignment produces a level different from
the one on the record, the level the record held moves to Previous Donor Level and Donor
Level Changed Date is set to the date of the change. When assignment produces the level
already held, nothing is written, so Donor Level Changed Date keeps saying when the donor
last moved rather than when the calculation last ran. Previous Donor Level is the record
of where the donor came from, and it is never cleared by a later assignment.

**R-DL5 A donor whose total falls.** A refund, a write-off, or a corrected gift lowers the
total the ladder reads, and the level follows it down in the same save. The level always
states the level the current number earns, because a level that disagreed with the total
printed beside it would be worse than no level at all (Principle 2). What is retained is
the previous level and the date: a donor who drops from Leadership Circle to Sustainer
reads as Sustainer, previously Leadership Circle, changed today, so the movement is
visible to the person who has to decide what to do about it. Levels are not a floor; an
organization that awards a level permanently records that on the donor, not here.

**R-DL6 When assignment runs.** The same three answers the rollup engine gives (R-R4).
Real time: assignment happens in the save that changes the source total, which includes
the save the rollup engine itself makes when a gift lands, and it runs before the record
is written so it costs no second update. Scheduled: a nightly pass re-places every donor,
which is what catches a fiscal year turning over and a ladder edited yesterday. On demand:
the Recalculate button on the Donor Levels page does the scheduled pass now. Assignment is
idempotent in all three: running it twice over unchanged data writes nothing the second
time.

**R-DL7 Off until it is set up.** `Donor_Levels_Enabled__c` defaults false and no level
records ship, because a ladder's amounts belong to the organization and a wrong one is
worse than none. While it is off, nothing is assigned and nothing is cleared: the levels
already assigned stay on the records, exactly as an inactive Rollup Definition keeps the
values it calculated (R-R6).

**R-DL8 Editing the ladder.** Changing an amount, adding a rung, or deactivating one takes
effect for a donor at their next assignment, so the console offers Recalculate and the
admin guide says to press it. Deleting a level record removes the name from every donor
holding it, current and previous, which is the platform's behavior for a lookup and cannot
be softened; deactivating a level instead keeps the history and stops new assignments,
which is why the Active attribute exists.

**R-DL9 Nothing shipped, nothing overwritten.** The package ships no Donor Level records
and never edits one. An upgrade cannot change an organization's ladder because there is
nothing packaged to conflict with it (ADR-0006).

### Salesforce implementation

- **Object:** `Donor_Level__c`, a rung of the ladder, listed and edited from the Donor
  Levels page in the settings console.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Minimum Amount | `Minimum_Amount__c` | Currency |
| Maximum Amount | `Maximum_Amount__c` | Currency |
| Active | `Active__c` | Checkbox |

- **Fields on Account** (shipped by Giving, shown read only in the Giving section of
  Giving's own Account and Contact record pages):

| Attribute | API name | Type |
|---|---|---|
| Donor Level | `Donor_Level__c` | Lookup to `Donor_Level__c` |
| Previous Donor Level | `Previous_Donor_Level__c` | Lookup to `Donor_Level__c` |
| Donor Level Changed Date | `Donor_Level_Changed_Date__c` | Date |

- **Fields on Contact** (shipped by Giving): the same three API names, with the same types
  and the same definitions.

- **Settings keys:** `Donor_Levels_Enabled__c`, `Donor_Level_Source_Field__c`, and
  `Donor_Levels_Last_Recalculated__c` on `Giving_Settings__c` (Section 21A).
- **Validation rule:** Maximum Amount, when it is filled in, is greater than Minimum
  Amount.
- **Automation:** `Donor_Level_Assignment` in `Automation_Registry__mdt`, one row for
  Account and one for Contact, both naming `DonorLevelTriggerHandler`, both bypassable and
  pausable like every other packaged automation (R-A1).
- **Service:** `DonorLevelService`, `DonorLevelSelector`, `DonorLevelTriggerHandler`,
  `DonorLevelBatch`, `DonorLevelSchedulable`, `DonorLevelWriter` (ADR-0021), and
  `DonorLevelController` for the page.

---

| Name | text | computed | The receipt record's identifier, assigned automatically. It is not the receipt number. |
| Receipt Number | text | yes | The number printed on the document, allocated once by the package sequence and never reused. |
| Type | picklist(Per gift, Consolidated statement) | yes | Whether this document covers one gift or a donor's whole year. |
| Status | picklist(Issued, Void) | yes (defaults Issued) | Whether the document still stands. |
| Statement Year | integer | yes | The tax year the document reports on. |
| Gift | reference(Gift) | conditional | The gift receipted; present on a per gift receipt and empty on a consolidated statement. |
| Donor Contact | reference(Contact) | conditional | The donor, where people are Contacts. |
| Donor Account | reference(Organization) | conditional | The donor, where the donor is an organization, a household giving in its own name, or a person Account. |
| Household | reference(Household) | no | The household credited, derived from the donor the same way a gift's household is (R-G2). |
| Total Amount | decimal | yes on an issued receipt | The amount the document states: the gift's amount, or the sum of the lines on a statement. A receipt reconciled from a consumed number carries zero, because no document was produced. |
| Issue Date | date | yes on an issued receipt | The date printed on the document. A reconciled receipt carries the date it was accounted for. |
| Content Document Id | text | no | The Salesforce file identifier of the stored PDF, so the record and its document find each other without a query on the link table. |
| Void Reason | text | conditional | Why the document was voided; required when Status is Void. |
| Voided On | datetime | conditional | When the document was voided; required when Status is Void. |
| Replaces | reference(Receipt) | no | The voided receipt this one was issued to replace. |
| Replaced By | reference(Receipt) | no | The receipt issued to replace this one, written on the original when it is voided and reissued. |
| Receipt Run | reference(Receipt Run) | no | The batch run that issued this receipt, empty when a person issued it one at a time. |
| Series Key | text | yes | The numbering series this number came from: receipt type plus statement year. |
| Donor Year Key | text | no | Donor, statement year and type as one value, unique, so a retried batch chunk reissues nothing. |

### Relationships

- **Receipt to Gift**, many to one, on a per gift receipt only. Deleting a gift does not
  delete its receipt: the receipt lock refuses the delete while a receipt exists (R-G4).
- **Receipt to Donor**, many to one, to exactly one of Donor Contact or Donor Account
  (Section 4 "Person references").
- **Receipt to Receipt**, through Replaces and Replaced By, which point at each other.
- **Receipt to Receipt Run**, many to one.
- **Receipt to its stored file**, one to one, as a `ContentVersion` linked to the receipt
  and, on a per gift receipt, to the gift. It is not linked to the donor: a
  `ContentDocumentLink` grants access to a file through the record it names, and every Core
  role can read a Contact and an Account (R-RC11, ADR-0034).

### Rules

**R-RC1 Issued means immutable.** A receipt's number, type, statement year, donor, total
amount, issue date and stored file do not change after it is issued. The only writes an
issued receipt accepts are the void fields and Replaced By (ADR-0010).

**R-RC2 A number is consumed once and never reused.** Numbers come from the sequence in
Section 25C. Gaplessness is not attempted at the database level, because a rolled back
transaction cannot un-consume a number that another transaction has already moved past.

**R-RC3 Every consumed number is accounted for, by one of two mechanisms.** For the
statement series, a number whose generation failed is reconciled into a receipt with Status
Void and Void Reason `Generation failed`, and that reconciliation runs at the end of every
batch run. For the per gift series there is no reconciliation pass: the allocation and the
receipt insert share one transaction and a failure rolls both back, so a failed issue
consumes no number. Either way an auditor asking what happened to number N gets a record
rather than silence. A per gift caller that catches a generation failure and commits anyway
breaks this rule, and the Health Check finding in C-11 counts only reconciled records, so it
would not see the result (ADR-0016, "Numbering").

**R-RC4 Voiding never touches the stored file.** A void writes Void Reason and Voided On
and leaves the document exactly as the donor received it. Deleting the file is not a void.

**R-RC5 Regeneration is a void plus a new receipt.** The replacement takes the next number
from the same series and carries Replaces; the original carries Replaced By. Nothing
regenerates a receipt in place.

**R-RC6 One donor, and a gift only on a per gift receipt.** Exactly one of Donor Contact
and Donor Account is set. Gift is required on a per gift receipt and empty on a
consolidated statement.

**R-RC7 The tax content is code, not template prose.** The renderer emits, per gift: the
no goods or services sentence by default; for a quid pro quo benefit, the benefit
description, the good faith estimate of its value, and the deductible amount; and the
intangible religious benefits sentence when the gift carries that flag. An in-kind gift
prints the donor supplied description and never a value the organization asserts. An
administrator edits wording and tokens around these sentences and never the sentences
themselves (ADR-0016, IRS Publication 1771).

**R-RC8 A statement states the status of every line.** A consolidated statement prints
each gift's status on that gift's line, not once in a footer, so a reader cannot mistake
which of a year's gifts was refunded. Pending and Cancelled gifts are not on it: no money
arrived (R-G16).

**R-RC9 One receipt per donor, year and type, per run.** Donor Year Key is unique, so a
batch chunk that is retried after a failure resumes the run rather than issuing a second
document to the same donor. The key is cleared when the receipt is voided, so a reissue is
possible.

**R-RC10 Read only to everyone.** No packaged permission set grants Edit or Delete on
Receipt to any role, including the administrator's, and the fields above are read only in
every packaged permission set. The package writes them; a person never does.

**R-RC11 A receipt document is reached only through Receipt and Gift.** The stored file is
linked to its receipt, and on a per gift receipt to its gift, and to nothing else. A
`ContentDocumentLink` grants access through the record it names rather than through
`Receipt__c`, so linking the donor Contact or Account would give the file to every role that
can read a donor, including roles that hold no Giving permission set. The link is written with
`ShareType` Viewer, which caps what it can grant at reading (R-RC1), and `Visibility`
InternalUsers (AllUsers on an org with no external users, where the platform refuses
InternalUsers and AllUsers reaches the same internal users). The donor's route to the document is the Receipts related list on their record
(ADR-0034).

**R-RC12 An in-kind gift's document states no money amount (G-18).** A receipt that puts a
figure next to a gift of goods is read as a cash contribution of that amount, which is the one
thing a receipt for donated property must not say. So:

- On a per gift receipt for an in-kind gift, the Amount token renders as a phrase naming the
  goods or services rather than as a currency figure, whatever the template asked for; the
  document adds a note saying in plain words that no value has been stated, because the phrase
  in the letter does not say that outright; and the receipt's Total Amount is zero, because a
  receipt record states what its document states. The value the organization recorded stays on
  the gift (R-G12), where it belongs.
- On a consolidated statement, an in-kind gift is a line carrying its date, its type and its
  status with no amount, it is left out of the total the statement states, and the statement
  carries one sentence saying that gifts of goods or services are listed without a value and
  are not part of the total. A donor who adds the lines up and gets a different number from the
  total is owed that sentence.

The description still prints, once per in-kind gift, through the sentences of R-RC7. The
charity describes the property and the donor values it.

**R-RC13 What the document is branded with, and what it is valid without.** Every document
prints the organization's legal name and address and its tax identification number. The name
and address are the letterhead, and the letterhead is code, not template (ADR-0065,
`0065-receipt-letters-are-edited-as-rich-text.md`): the package prints them in a block above
the letter whatever the letter says, so an administrator editing the letter can neither delete
nor misplace them. A letter saved before that decision still carries its own letterhead block
(`class="letterhead"`); while it does, the package prints the logo only, and the letter's
block prints the name. The tax identification number prints in the signature block.

The logo is optional, is printed only when the organization has uploaded one and left the
Print Logo On Receipts setting on, and is sized by one setting.

**How an image reaches the renderer is ADR-0016's second spike, and that spike is open**: it
cannot be closed without a real org. The delivery route is therefore a setting with the three
routes ADR-0016 names, so that settling it in an org is a settings change rather than a package
version, exactly as the renderer itself is (`Receipt_Renderer__c`). Because **a receipt with no
images at all is a valid receipt**, nothing in this rule is allowed to fail a document: a logo
that cannot be resolved is written to the Error Log at Warning severity and the document is
produced without it.

### Salesforce implementation

- **Object:** `Receipt__c`, auto-number Name with format `RC-{000000}`, private
  organization-wide default recommended (plan Section 4.13).

| Attribute | API name | Type |
|---|---|---|
| Receipt Number | `Receipt_Number__c` | Text(50), External Id, unique |
| Type | `Type__c` | Picklist: Per gift, Consolidated statement |
| Status | `Status__c` | Picklist: Issued, Void |
| Statement Year | `Statement_Year__c` | Number(4, 0) |
| Gift | `Gift__c` | Lookup to `Gift__c` |
| Donor Contact | `Donor_Contact__c` | Lookup to Contact |
| Donor Account | `Donor_Account__c` | Lookup to Account |
| Household | `Household__c` | Lookup to Account |
| Total Amount | `Total_Amount__c` | Currency, not universally required, see the attribute table |
| Issue Date | `Issue_Date__c` | Date, not universally required, see the attribute table |
| Content Document Id | `Content_Document_Id__c` | Text(18) |
| Void Reason | `Void_Reason__c` | Text(255) |
| Voided On | `Voided_On__c` | Date/Time |
| Replaces | `Replaces__c` | Lookup to `Receipt__c` |
| Replaced By | `Replaced_By__c` | Lookup to `Receipt__c` |
| Receipt Run | `Receipt_Run__c` | Lookup to `Receipt_Run__c` |
| Series Key | `Series_Key__c` | Text(80) |
| Donor Year Key | `Donor_Year_Key__c` | Text(120), External Id, unique |

- **Service:** `ReceiptService`, `ReceiptSelector`, `ReceiptNumberSequence`,
  `ReceiptContentBuilder`, `ReceiptRenderer` and `BlobToPdfReceiptRenderer`,
  `ReceiptLogoSource` (R-RC13), `ReceiptFileWriter` (ADR-0021), batch
  `ReceiptStatementBatch`, LWC `receiptTemplates` and `receiptRunConsole`.

---

## 25C. Receipt Number Sequence

### Definition

The package owned counter that hands out receipt numbers, one row per series, where a
series is a receipt type plus a statement year (ADR-0016). It is not a Salesforce
auto-number: an auto-number cannot be prefixed per organization, cannot be restarted per
year, and cannot be read back so that a consumed number can be accounted for.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The series key, so the row reads for itself in a list view. |
| Series Key | text | yes | Receipt type plus statement year, unique. |
| Receipt Type | text | yes | The receipt type this series numbers. |
| Statement Year | integer | yes | The statement year this series numbers. |
| Prefix | text | yes | The prefix printed before the year and the counter, copied from settings when the series is created. |
| First Counter | integer | yes | The counter the series started at, so the consumed range has a lower bound. |
| Next Counter | integer | yes | The next counter to hand out. |

### Relationships

- **Receipt Number Sequence to Receipt**, one to many, by Series Key rather than by a
  lookup: a receipt keeps its number after the series row is archived.

### Rules

**R-RS1 One locked row per series.** An allocation selects the series row `FOR UPDATE`,
reads Next Counter, and advances it by the size of the block requested. A batch chunk
allocates its whole block in one update rather than one number at a time. The lock is held
until the transaction ends, not until the allocation returns, so the block keeps the wait to
one per chunk rather than one per document but does not make it short (ADR-0016,
"Consequences").

**R-RS2 The number format is fixed.** `{prefix}-{statement year}-{counter zero padded to
six digits}`. Prefix and starting counter come from settings; nothing else about the format
is configurable, because a receipt number that changes shape mid-year is a number an
auditor cannot follow.

**R-RS3 Consumed is consumed.** Next Counter never moves backward, and no code path
rewrites it to fill a gap. The reconciliation in R-RC3, not the sequence, is what answers
for a missing number.

### Salesforce implementation

- **Object:** `Receipt_Number_Sequence__c`, Text Name.

| Attribute | API name | Type |
|---|---|---|
| Series Key | `Series_Key__c` | Text(80), External Id, unique |
| Receipt Type | `Receipt_Type__c` | Text(40) |
| Statement Year | `Statement_Year__c` | Number(4, 0) |
| Prefix | `Prefix__c` | Text(10) |
| First Counter | `First_Counter__c` | Number(18, 0) |
| Next Counter | `Next_Counter__c` | Number(18, 0) |

- **Service:** `ReceiptNumberSequence`, a writer class under ADR-0021.

---

## 25D. Receipt Run

### Definition

One generation run: which type, which statement year, when it started and finished, and
what it produced (ADR-0016). It exists so that a run can be watched while it is going and
reconstructed afterward, and because a year end run over tens of thousands of donors is
long enough that "did it finish" is a real question.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The run's identifier, assigned automatically. |
| Type | picklist(Per gift, Consolidated statement) | yes | What the run generates. |
| Statement Year | integer | yes | The year the run reports on. |
| Status | picklist(Queued, Running, Completed, Completed with errors, Failed) | yes | Where the run stands. |
| Started | datetime | no | When the batch began. |
| Finished | datetime | no | When the batch ended. |
| Donors Processed | integer | yes (defaults 0) | How many donor records the run examined. |
| Receipts Issued | integer | yes (defaults 0) | How many documents the run produced. |
| Errors | integer | yes (defaults 0) | How many chunks failed, each of which is also in the Error Log. |
| Async Job Id | text | no | The platform job identifier, so a stuck run can be found. |

### Relationships

- **Receipt Run to Receipt**, one to many.

### Rules

**R-RR1 A chunk failure never aborts the run.** A failed chunk is counted, written to the
Error Log with the donors it covered, and the run continues. A run that ends with any
failed chunk is Completed with errors, never Completed.

**R-RR2 A run is resumed, not restarted.** Re-running the same type and statement year
skips donors that already hold an issued receipt for that year, because Donor Year Key is
unique (R-RC9).

**R-RR3 Counts are the run's own.** Donors Processed, Receipts Issued and Errors are
written by the batch as it goes, so a run that is still going shows real progress.

### Salesforce implementation

- **Object:** `Receipt_Run__c`, auto-number Name with format `RR-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Type | `Type__c` | Picklist: Per gift, Consolidated statement |
| Statement Year | `Statement_Year__c` | Number(4, 0) |
| Status | `Status__c` | Picklist: Queued, Running, Completed, Completed with errors, Failed |
| Started | `Started__c` | Date/Time |
| Finished | `Finished__c` | Date/Time |
| Donors Processed | `Donors_Processed__c` | Number(18, 0) |
| Receipts Issued | `Receipts_Issued__c` | Number(18, 0) |
| Errors | `Errors__c` | Number(18, 0) |
| Async Job Id | `Async_Job_Id__c` | Text(18) |

- **Service:** `ReceiptRunService`, batch `ReceiptStatementBatch`.

---

## 25E. Receipt Template

### Definition

The editable wording around a receipt: the letter an administrator writes, with merge
tokens for the organization, the donor, the amounts and the dates (ADR-0006 puts structured
configuration an admin manages as a list in a packaged custom object, and ADR-0016 puts the
template bodies there).

The template is HTML restricted to what the Visualforce PDF rendering service supports: no
web fonts, no JavaScript, no `data:` URI images, and page headers and footers only through
`@page` margin boxes. The tax sentences in R-RC7 are not in the template and cannot be
edited out of it.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the administrator calls this template. |
| Type | picklist(Per gift, Consolidated statement) | yes | Which kind of document this template lays out. |
| Body | long text | yes | The HTML with merge tokens. |
| Active | boolean | yes (defaults false) | Whether this is the template the package uses for its type. |

### Relationships

- **Receipt Template to Receipt**, none. A receipt records the document it produced, not
  the template it came from, because the stored PDF is the document of record and the
  template will have changed by the time anyone asks.

### Rules

**R-RT1 One active template per type.** Activating a template deactivates the other
templates of the same type. Generating with no active template of the required type is an
error with a readable message, not a blank document.

**R-RT2 Tokens are a closed set.** Only the tokens the package documents are merged; an
unknown token is left as typed rather than silently emptied, so a typo is visible on the
proof rather than invisible on the donor's copy.

**R-RT3 The tax sentences are appended by code.** Whatever the body says, the renderer adds
the sentences R-RC7 requires. A template that also types them produces them twice, which is
the administrator's to fix, and a template that omits them still produces a valid receipt.

**R-RT4 The shipped letters arrive at install, and writing one needs Manage BarnCRM
Settings.** `Receipt_Template_Default__mdt` is materialized by the Giving post-install script,
at install and at every upgrade, creating only what the org does not have (ADR-0029). The
Receipts page carries a Restore the shipped letters action for an install whose step failed,
and issuing a receipt with no letter of that kind materializes the shipped one under
`Issue_Receipts`. Saving a body, switching a letter on, and restoring the shipped letters all
check `Manage_BarnCRM_Settings` and write in user mode (ADR-0034).

### Salesforce implementation

- **Object:** `Receipt_Template__c`, Text Name.

| Attribute | API name | Type |
|---|---|---|
| Type | `Type__c` | Picklist: Per gift, Consolidated statement |
| Body | `Body__c` | Long Text Area (32768) |
| Active | `Active__c` | Checkbox |

- **Shipped defaults:** `Receipt_Template_Default__mdt`, with `Template_Name__c`,
  `Receipt_Type__c` and `Body__c`, one row per receipt type, materialized into
  `Receipt_Template__c` by `GivingPostInstall` (R-RT4).
- **Service:** `ReceiptTemplateService`, LWC `receiptTemplates`, reached from the Nonprofit
  Settings console as a Component row.

---

## 25F. Acknowledgment Rule

### Definition

The organization's answer to "which thank you does this gift get" (feature G-12, v0.4,
ADR-0032). A rule matches a gift on the things a fundraising office actually sorts gifts
by, and resolves to a channel and, for email, to the standard email template that carries
the wording.

A rule is not a filter on a report. It is evaluated on the save of every gift, first
matching rule wins, so the order of the rules is the organization's editorial judgment
about which thank you takes precedence.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the organization calls this rule, for example "Major gifts, over $1,000". |
| Description | long text | no | When this rule is meant to apply, in the organization's own words. |
| Active | boolean | yes (defaults true) | Whether the rule takes part in matching. An inactive rule matches nothing and is kept rather than deleted. |
| Order | integer | yes | Where the rule sits in the list. The lowest numbered matching rule wins. |
| Channel | picklist(Email, Letter, None) | yes | How the donor is thanked, or that this kind of gift is not acknowledged. |
| Email Template | text | conditional | The developer name of the standard email template this rule sends; required when Channel is Email. Chosen from a picker of the org's active templates, by name, on the Acknowledgments page (ADR-0066, `0066-acknowledgment-rule-template-picker-and-generated-plan-keys.md`). |
| Minimum Amount | currency | no | The smallest gift this rule matches. Empty means no lower bound. |
| Maximum Amount | currency | no | The largest gift this rule matches. Empty means no upper bound. |
| Gift Type | picklist(Cash, Check, Card, ACH, Stock, In-kind, Grant, Other) | no | The one gift type this rule matches. Empty means any type. |
| Appeal | reference(Appeal) | no | The one appeal this rule matches. Empty means any appeal, and no appeal. |
| First Gift Only | boolean | yes (defaults false) | Whether the rule matches only a donor's first gift. |

### Relationships

- **Acknowledgment Rule to Acknowledgment**, one to many: every acknowledgment records the
  rule that produced it, so a rule that sent the wrong letter can be traced to what it sent.
- **Acknowledgment Rule to Appeal**, many to one, as a matching criterion.
- Acknowledgment Rule has no reference to Gift. A gift does not carry the rule that matched
  it, because rules are re-evaluated when the queue is sent (R-AK3).

### Rules

**R-AK1 First matching rule wins.** Active rules are considered in Order, lowest first, and
the first one whose criteria all match the gift decides the channel and the template. Ties
on Order are broken by Name, so a badly ordered list is still deterministic. A gift matching
no rule is left exactly as it is: no channel, no send, and the status it already had.

**R-AK2 What a rule can match on.** Amount range (inclusive at both ends), gift type,
appeal, and whether the gift is the donor's first. An empty criterion is not a criterion:
an empty Gift Type matches every type rather than matching gifts with no type. First Gift
Only is true for a gift where the donor, the Contact or the Account that the gift credits,
has no other gift of a positive amount, counted at the moment the gift is saved rather than
read from a rollup, because the rollup for a gift being inserted has not been calculated
yet.

**R-AK3 Rules are evaluated twice, on purpose.** On the save of a gift, to decide whether it
joins the queue, and again when the queue is sent, to decide which template each queued gift
gets. Nothing is stored on the gift in between. An administrator who fixes a rule's template
on Tuesday morning therefore fixes it for the gifts that arrived on Monday and have not gone
out yet, which is what she expects and what a stored channel would have prevented.

**R-AK4 Channel None means not required.** A rule whose channel is None sets the gift's
Acknowledgment Status to Not required, which is the organization saying this kind of gift
does not get a thank you. It is not the same as Do not acknowledge, which is a person's
decision about one gift and which no rule ever overwrites (R-AK6).

**R-AK5 Nothing is shipped, nothing is overwritten.** The package ships no rules. An org
with no rules acknowledges nothing automatically, which is the correct behavior for a
feature that sends mail to donors on the organization's letterhead.

---

## 25G. Acknowledgment

### Definition

One thank you, recorded (feature G-12, ADR-0032). The row exists so that the questions
asked in January have answers: did this go, when, by which letter, to which address, and
did it go twice.

An acknowledgment is not a receipt (Section 25B). It carries no number, it is not
immutable, it may legitimately happen more than once for the same gift, and it has no
statutory content.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The record's identifier, assigned automatically. |
| Gift | reference(Gift) | yes | The gift being acknowledged. |
| Rule | reference(Acknowledgment Rule) | no | The rule that produced this acknowledgment; empty when a person acknowledged the gift outside the rules. |
| Channel | picklist(Email, Letter) | yes | How this one went out. |
| Template | text | no | The developer name of the email template used, as it was at the time, so a letter that has since been rewritten can still be identified. |
| Status | picklist(Queued, Sent, Failed) | yes (defaults Queued) | Where this acknowledgment stands. A letter stays Queued until the letters are marked sent. |
| Sent On | datetime | conditional | When it went; set when Status becomes Sent. |
| Recipient Contact | reference(Contact) | no | The person it was addressed to. |
| Recipient Email | email | no | The address it was sent to, kept because the contact's address changes and the question is where it actually went. |
| Failure Reason | text | conditional | Why it did not go, in a sentence a person can read; required when Status is Failed. |
| Run | reference(Acknowledgment Run) | no | The run that produced it, empty when a person produced it one at a time. |
| Gift Key | text | no | The gift's identifier, unique, held while this acknowledgment stands and cleared when the gift is deliberately queued again (R-AK7). |

### Relationships

- **Acknowledgment to Gift**, many to one. A gift may hold several acknowledgments over its
  life; at most one of them holds the Gift Key.
- **Acknowledgment to Acknowledgment Run**, many to one.
- **Acknowledgment to Acknowledgment Rule**, many to one.

### Rules

**R-AK6 The gift's two fields are the summary, the record is the truth.** Acknowledgment
Status and Acknowledgment Date on Gift (R-G9) are written from the ledger and never the
other way around: a row reaching Sent sets the gift to Acknowledged and stamps the date. The
fields exist because a list view and a report need one column, not a subquery. Where they
disagree with the ledger the ledger is right, and Do not acknowledge on a gift is a person's
instruction that no automation and no run ever overwrites.

**R-AK7 A gift is thanked once unless a person says otherwise.** Gift Key is unique and
holds the gift's identifier from the moment the row is written, which is before anything is
sent. A second row for the same gift therefore cannot be inserted, so a batch chunk retried
after a partial failure resumes rather than sending again, and two people pressing Send at
once produce one thank you. The key is cleared in exactly two cases: the send failed, so the
gift is retried; or a person set the gift's Acknowledgment Status back to To acknowledge,
which is the deliberate act of thanking a donor again. Both leave the earlier row in place,
so "we sent it twice" reads as two rows rather than as silence.

**R-AK8 Only a positive received gift is ever acknowledged.** A gift whose Status is
Refunded, Written off, Pending or Cancelled, and any gift whose Amount is zero or negative, is never
queued and never sent, so the negative gift that records a refund (R-G3) is outside this
feature entirely. Refunding a gift does not withdraw its acknowledgment: the donor was
thanked, and that happened.

**R-AK9 A failure is one row, not a run.** A send that fails marks its own row Failed with
the reason, clears its key so the next send retries it, and writes an Error Log entry naming
the gift. The rest of the chunk goes out.

A gift with nobody to email, an organization gift with no primary contact for example, gets
no row at all. Nothing went wrong and nothing was attempted, so there is nothing to record
about the thank you; the run counts it, names it in one Error Log entry for the whole chunk,
and leaves the gift in the queue, where a letter rule or a corrected contact will pick it up.
A row per night for a gift that will never have an email address is noise on the donor's
record, which is the thing this ledger exists to keep clean.

---

## 25H. Acknowledgment Run

### Definition

One send (ADR-0032). It exists for the same reason the receipt run does, and for one more:
a letter run owns the merge file, which is the thing the administrator actually leaves
Salesforce with.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The run's identifier, assigned automatically. |
| Channel | picklist(Email, Letter) | yes | What the run does. |
| Status | picklist(Queued, Running, Ready to merge, Completed, Completed with errors, Failed) | yes | Where the run stands. Ready to merge belongs to a letter run whose file is written and whose letters have not yet been marked sent. |
| Started | datetime | no | When the run began. |
| Finished | datetime | no | When the run ended. |
| Gifts Processed | integer | yes (defaults 0) | How many gifts the run examined. |
| Acknowledgments Sent | integer | yes (defaults 0) | How many thank yous it produced. |
| Errors | integer | yes (defaults 0) | How many failed, each of which is also in the Error Log. |
| Async Job Id | text | no | The platform job identifier, so a stuck run can be found. |
| Merge File Document Id | text | no | The Salesforce file identifier of the letter merge CSV, on a letter run. |

### Relationships

- **Acknowledgment Run to Acknowledgment**, one to many.

### Rules

**R-AK10 A failed send never aborts the run.** Counted, logged, and the run continues. A run
that ends with any failure is Completed with errors, never Completed, which is the same
promise the receipt run makes (R-RR1).

**R-AK11 A letter run is finished by a person.** The run writes the merge file and stops at
Ready to merge with its rows Queued. Marking it sent, which the Acknowledgments page offers
and which nothing does automatically, stamps the rows and the gifts and closes the run. The
package cannot know whether a letter was printed, so it does not pretend to.

**R-AK12 The run is visible without being opened.** Last run and last run summary are held
on Giving Settings and shown on the Acknowledgments page, the same freshness promise the
seasonal address swap makes (R-AD8), so an administrator can see that last night's send
happened without finding the run record.

### Salesforce implementation

- **Objects:** `Acknowledgment_Rule__c` (Text Name), `Acknowledgment__c` (auto-number Name
  with format `AK-{000000}`) and `Acknowledgment_Run__c` (auto-number Name with format
  `AR-{000000}`), all three shipped by Giving.

| Attribute | API name | Type |
|---|---|---|
| Description | `Description__c` | Long Text Area |
| Active | `Active__c` | Checkbox |
| Order | `Order__c` | Number(4, 0) |
| Email Template | `Email_Template__c` | Text(80) |
| Minimum Amount | `Minimum_Amount__c` | Currency |
| Maximum Amount | `Maximum_Amount__c` | Currency |
| Gift Type | `Gift_Type__c` | Picklist: Cash, Check, Card, ACH, Stock, In-kind, Grant, Other |
| Appeal | `Appeal__c` | Lookup to `Appeal__c` |
| First Gift Only | `First_Gift_Only__c` | Checkbox |

- **Fields on `Acknowledgment__c`:**

| Attribute | API name | Type |
|---|---|---|
| Gift | `Gift__c` | Lookup to `Gift__c` |
| Rule | `Rule__c` | Lookup to `Acknowledgment_Rule__c` |
| Template | `Template__c` | Text(80) |
| Sent On | `Sent_On__c` | Date/Time |
| Recipient Contact | `Recipient_Contact__c` | Lookup to Contact |
| Recipient Email | `Recipient_Email__c` | Email |
| Failure Reason | `Failure_Reason__c` | Text(255) |
| Run | `Run__c` | Lookup to `Acknowledgment_Run__c` |
| Gift Key | `Gift_Key__c` | Text(18), External Id, unique |

- **Fields on `Acknowledgment_Run__c`:**

| Attribute | API name | Type |
|---|---|---|
| Started | `Started__c` | Date/Time |
| Finished | `Finished__c` | Date/Time |
| Gifts Processed | `Gifts_Processed__c` | Number(18, 0) |
| Acknowledgments Sent | `Acknowledgments_Sent__c` | Number(18, 0) |
| Errors | `Errors__c` | Number(18, 0) |
| Async Job Id | `Async_Job_Id__c` | Text(18) |
| Merge File Document Id | `Merge_File_Document_Id__c` | Text(18) |

  `Channel__c` (Picklist: Email, Letter, None on the rule; Email, Letter on the other two)
  and `Status__c` (Picklist: Queued, Sent, Failed on the acknowledgment; Queued,
  Running, Ready to merge, Completed, Completed with errors, Failed on the run) are shipped
  on the objects named above.

- **Settings keys:** `Acknowledgments_Enabled__c`, `Acknowledgment_From_Address__c`,
  `Acknowledgments_Last_Run__c` and `Acknowledgments_Last_Run_Summary__c` on
  `Giving_Settings__c` (Section 21A).
- **Validation rules:** on the rule, Maximum Amount above Minimum Amount when both are
  filled in, and an Email Template named when Channel is Email.
- **Automation:** `Gift_Acknowledgment` in `Automation_Registry__mdt`, naming
  `GiftAcknowledgmentHandler`, execution order 40, switchable and pausable like every other
  convenience (R-A1, and deliberately not `Always_Runs__c`, ADR-0024).
- **Service:** `AcknowledgmentRuleService`, `AcknowledgmentService`,
  `AcknowledgmentSelector`, `AcknowledgmentWriter` (ADR-0021), `AcknowledgmentSender` with
  `MessagingAcknowledgmentSender`, `AcknowledgmentBatch`, `AcknowledgmentScheduler`,
  `AcknowledgmentLetterMerge`, and `AcknowledgmentController` for the page.
- **Custom permission:** `Send_Acknowledgments`, granted to Giving Admin and Giving Staff.
- **Page:** LWC `acknowledgments` on the `Acknowledgments` tab and flexipage, reached from
  the Giving section of the BarnCRM Settings console by navigation (ADR-0020).

---

## 25I. Stewardship Plan Template

### Definition

A named sequence of follow-up work an organization repeats: the tasks that should happen
after a first gift, after a large gift, after a pledge starts. The NPSP Engagement Plans
successor (plan Section 5.2, feature G-15).

The template is the recipe, not the work. It holds what starts the sequence and the steps
it lays out; a `Stewardship_Plan__c` is one running copy of it on one donor, and the tasks
belong to the people who have to do them.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the administrator calls the plan, for example "First gift welcome". |
| Plan Key | text | yes | A stable key, unique, so a shipped default is recognized on upgrade without matching on a name the administrator may have changed. Generated from the plan name when an administrator creates a plan, made unique with a number suffix, and never shown or changed afterwards (ADR-0066, `0066-acknowledgment-rule-template-picker-and-generated-plan-keys.md`). |
| Active | boolean | yes (defaults false) | Whether the plan can start. An inactive template keeps the plans it already started. |
| Trigger Event | picklist(Manual, First gift, Gift received, Commitment started) | yes | What starts a plan from this template. Manual means a person starts it and nothing starts it automatically. Commitment started means a pledge or a recurring gift became active (R-SP3a). |
| Minimum Amount | currency | no | For the two gift events, the smallest gift that starts a plan. Blank means any amount. |
| Description | long text | no | What this plan is for, in the administrator's words, shown when a person picks a plan to start by hand. |

### Relationships

- **Stewardship Plan Template to Stewardship Plan Step**, one to many, master detail. A
  template's steps have no meaning apart from it, so deleting a template takes its steps.
- **Stewardship Plan Template to Stewardship Plan**, one to many, lookup. A running plan
  keeps working when its template is deleted, because the tasks it created are already real
  work assigned to real people (R-SP8).

### Rules

**R-SP1 A trigger event does not make a plan mandatory.** Every automatic start goes
through `TriggerDispatcher` like every other packaged automation, so an administrator can
switch stewardship off before a bulk import and switch it back on afterwards (rule R-A1).
Nothing here is exempt from the automation switch.

**R-SP2 Only an active template starts anything.** Deactivating a template stops new plans
and leaves running ones alone.

**R-SP3 First gift means the donor's first.** The First gift event starts a plan only when
the gift being saved is the only gift the donor has that counts toward giving totals, using
the same status set the giving rollups use (Section 26). A refund that arrives later does
not retroactively unstart the plan, because the welcome has already been sent.

**R-SP3a Commitment started means the commitment became active.** A plan on this event
starts when a commitment is created already Active, and when an existing commitment moves
into Active from any other status. Both, because a pledge entered as Active and a pledge
entered as Paused and turned on a week later are the same event to the donor. A resumed
commitment therefore starts a plan again only once the earlier plan has been closed, since
R-SP6 still holds. Nothing starts for a commitment created Paused, Completed or Cancelled,
and Minimum Amount is not read here: the amount condition belongs to the two gift events,
which is what the Amount Only For Gift Events rule already enforces at save.

### Salesforce implementation

- **Object:** `Stewardship_Plan_Template__c`, Giving package.

| Attribute | API name | Type |
|---|---|---|
| Plan Key | `Plan_Key__c` | Text, unique, external id |
| Active | `Active__c` | Checkbox |
| Trigger Event | `Trigger_Event__c` | Picklist: Manual, First gift, Gift received, Commitment started |
| Minimum Amount | `Minimum_Amount__c` | Currency (18, 2) |
| Description | `Description__c` | Long Text Area |

- **Service:** `StewardshipService`, with `StewardshipSelector` reading and
  `StewardshipWriter` writing, following the pattern the rest of Giving uses.
- **Settings console:** the Stewardship Plans page, component `stewardshipPlans` with
  `StewardshipPlanController` behind it, on the `Stewardship_Plans` tab and flexipage and
  registered as a `Setting_Definition__mdt` Component row reached by navigation (ADR-0020).
  Templates, their steps, their order and their Active state are all administered there, so
  no part of setting a plan up needs Setup or a raw object tab.

---

## 25J. Stewardship Plan Step

### Definition

One task a template lays out, and when it comes due relative to the day the plan starts.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The step's identifier, assigned automatically. |
| Plan Template | reference(Stewardship Plan Template) | yes | The template this step belongs to. |
| Order | number | yes | The order the steps are listed in and created in. |
| Subject | text | yes | The task's subject, which is what the assignee sees in their list. |
| Days After Start | number | yes (defaults 0) | How many days after the plan starts this task is due. |
| Assign To | picklist(Record owner, Plan starter, Specific user) | yes | Who gets the task. Record owner is the owner of the donor record the plan runs on. |
| Assigned User | reference(User) | conditional | Required when Assign To is Specific user, ignored otherwise. |
| Priority | picklist(Low, Normal, High) | yes (defaults Normal) | The task's priority. |
| Comments | long text | no | The task's description, copied onto every task the step creates. |

### Relationships

- **Stewardship Plan Step to Stewardship Plan Template**, many to one, master detail.

### Rules

**R-SP4 A step with no assignee resolves to the person who started the plan.** Where Assign
To is Record owner and the donor record has no owner the package can read, or where
Assigned User names a user who is inactive, the task goes to the person who started the
plan rather than to nobody. A task nobody owns is a task nobody does.

**R-SP5 A due date never lands in the past.** Days After Start is counted from the day the
plan starts, so a plan started today with a step at day zero is due today. Negative values
are refused at save.

### Salesforce implementation

- **Object:** `Stewardship_Plan_Step__c`, Giving package. Name is an auto number, `SPS-{00000000}`.

| Attribute | API name | Type |
|---|---|---|
| Plan Template | `Stewardship_Plan_Template__c` | Master-Detail to `Stewardship_Plan_Template__c` |
| Order | `Order__c` | Number (3, 0) |
| Subject | `Subject__c` | Text (255) |
| Days After Start | `Days_After_Start__c` | Number (4, 0) |
| Assign To | `Assign_To__c` | Picklist: Record owner, Plan starter, Specific user |
| Assigned User | `Assigned_User__c` | Lookup to User |
| Priority | `Priority__c` | Picklist: Low, Normal, High |
| Comments | `Comments__c` | Long Text Area |

---

## 25K. Stewardship Plan

### Definition

One running copy of a template on one donor: what started it, when, and whether it is still
going. It exists so that a person can see which sequences are open on a donor, and so the
same sequence does not start twice on the same event.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The plan's identifier, assigned automatically. |
| Plan Template | reference(Stewardship Plan Template) | yes | The template this plan was made from. |
| Contact | reference(Contact) | conditional | The donor, where people are Contacts. |
| Account | reference(Organization) | conditional | The donor, where the donor is an organization or where people are person Accounts. |
| Gift | reference(Gift) | no | The gift that started the plan, where a gift event did. |
| Commitment | reference(Commitment) | no | The commitment that started the plan, where the Commitment started event did. |
| Status | picklist(Running, Complete, Cancelled) | yes (defaults Running) | Where the sequence stands. |
| Started Date | date | yes | The day the plan started, which is the day its due dates count from. |
| Completed Date | date | no | The day the plan was marked complete or cancelled. |

### Relationships

- **Stewardship Plan to Contact or Organization**, many to one. Exactly one of the two is
  set, following the person reference convention in Section 4.
- **Stewardship Plan to Task**, one to many. Each task carries the plan on its `WhatId`, so
  the tasks a plan created are visible from the plan without a package field on Task.

### Rules

**R-SP6 One running plan per template per donor.** Starting a template on a donor that
already has a Running plan from that template is refused with a readable message rather
than creating a second set of the same tasks. Completing or cancelling the first one frees
the donor for another.

**R-SP7 Tasks are created once, when the plan starts.** All of a template's steps become
tasks at start, dated from Started Date. Editing a template afterwards does not reach back
into plans already running, because the tasks are already in people's lists and rewriting
them would move work someone has planned their week around.

**R-SP8 The package never deletes a task it created.** Cancelling a plan sets its status and
its Completed Date and leaves every task alone. A task is a person's record of their own
work, and an open task on a cancelled plan is theirs to close. Deleting a template does not
touch running plans or their tasks for the same reason.

**R-SP9 A failure to start a plan never fails the gift.** The starter runs after the gift is
saved and logs to Error Log (rule R-E1). A stewardship plan that could not start is a follow
up that did not happen; a gift that could not save is money the organization lost track of,
and the second is worse.

**R-SP10 Completion is a person's judgment in v0.4.** A plan is marked Complete by whoever
decides the sequence is done. The package does not close a plan automatically when its last
task closes: that needs automation on Task, which the package does not ship, and the plan's
status is a record of intent rather than a derived count. This is recorded here as a
deliberate limit rather than an omission, and it is the first thing to revisit if plans are
found sitting Running long after their work finished.

### Salesforce implementation

- **Object:** `Stewardship_Plan__c`, Giving package. Name is an auto number, `SP-{00000000}`.

| Attribute | API name | Type |
|---|---|---|
| Plan Template | `Stewardship_Plan_Template__c` | Lookup to `Stewardship_Plan_Template__c` |
| Contact | `Contact__c` | Lookup to Contact |
| Account | `Account__c` | Lookup to Account |
| Gift | `Gift__c` | Lookup to `Gift__c` |
| Commitment | `Commitment__c` | Lookup to `Commitment__c` |
| Status | `Status__c` | Picklist: Running, Complete, Cancelled |
| Started Date | `Started_Date__c` | Date |
| Completed Date | `Completed_Date__c` | Date |

- **Automation:** two `Automation_Registry__mdt` rows, both order 60 and neither always
  running: `Stewardship_Plan_Starter`, handler `StewardshipTriggerHandler`, on `Gift__c`,
  and `Stewardship_Plan_Starter_Commitment`, handler `StewardshipCommitmentHandler`, on
  `Commitment__c`. Two rows rather than one because the switch is per row, and an
  administrator loading a year of gifts has no reason to also stop the commitments she
  enters by hand from starting their plans.

---

## 25L. Gift Batch

### Definition

One sitting's worth of gifts, typed from a stack of paper, checked against the total the
bank was given, and then posted (plan Section 4.11, feature G-17). A batch is a container
for entry and a control on entry, not a second kind of gift: once it is posted it holds
nothing but the record of what it produced.

The reason the entity exists is the control total. A deposit slip says the stack totals
4,812.50, and the batch refuses to post until what was typed says the same thing. A batch
that posts while it is out of balance produces gifts nobody will check again.

G-17 does not stage its lines through the import framework (Sections 16 and 17), although
the plan points there: ADR-0045 records why.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The batch's identifier, assigned automatically. |
| Description | text | no | What this stack of paper is, in the words of the person typing it: "Tuesday mail, 14 March". |
| Status | picklist(Open, Posted) | yes (defaults Open) | Whether the batch is still being typed or has produced its gifts. Written only by posting (R-GB4). |
| Control Total | decimal | yes, to post | The total from the deposit slip or the adding machine tape, which the entered total has to match (R-GB3). |
| Entered Total | decimal | computed | The sum of the amounts on the batch's lines. Held nowhere: computed from the lines every time it is shown or checked (R-GB2). |
| Default Gift Date | date | no (defaults today) | The date a line's gift is dated when the line gives no date of its own (R-GB1). |
| Default Payment Method | picklist(Cash, Check, Card, ACH, Stock, Grant, Other) | no (defaults Check) | How the gifts arrived, when a line does not say. It becomes the gift's Type (Section 18). In-kind is not offered (R-GR3). |
| Default Fund | reference(Fund) | no | The fund a line's gift is designated to when the line names none. Empty means the org's default fund (R-GA2). |
| Default Appeal | reference(Appeal) | no | The appeal a line's gift responded to when the line names none. |

### Relationships

- **Gift Batch to Gift Batch Row**, one to many, master-detail; the lines are deleted with
  the batch and share its sharing.
- **Gift Batch to Fund and to Appeal**, many to one, as defaults for its lines only.
- A Gift Batch has no reference to Gift, and Gift none to it. The gifts a posting produced
  are reached through the lines that produced them, so a gift is never explained by two
  records.

### Rules

**R-GB1 A line's empty values are the batch's.** Gift Date, Payment Method, Fund and Appeal
on a line are overrides. Where a line leaves one empty, posting uses the batch's value, read
at the moment of posting. So correcting a default before posting corrects every line that
did not choose its own, and a line that did choose stays as it was.

**R-GB2 The entered total is computed, never stored.** It is the sum of the line amounts,
computed when it is shown and again inside the posting transaction. A stored copy of a sum
is a second place for the number to be wrong, and this is the one number the feature exists
to get right.

**R-GB3 A batch out of balance does not post.** Posting is refused unless the batch has a
control total, has at least one line, and the entered total equals the control total
exactly. The refusal states the difference and its direction. The check is made on the
server inside the transaction that would create the gifts, so a stale browser cannot post
an unbalanced batch.

**R-GB4 A batch posts once.** Posting reads the batch with a row lock, refuses if it is
already Posted, and sets Status to Posted in the transaction that inserts the gifts. A
second post, from a second tab or a double click, waits on the lock and then finds the
batch Posted. Status is read only in every packaged permission set and is written only by
posting (ADR-0021), so no one can close a batch by hand without its gifts. Once Posted, the
batch's business attributes (description, control total, status and the four defaults) do not
change again, which also means Status never returns to Open. Its owner still can, so an
administrator can reassign a departed person's batches.
Deleting a batch is granted only to the Giving admin permission set; deleting a posted
batch removes the record of the deposit and leaves its gifts untouched.

**R-GB5 Posting is all or nothing.** Every line of a balanced batch becomes a gift, or none
does. A partial post would leave gifts that no longer total what the bank was given, so a
line the platform refuses rolls the whole posting back, and the message names the line.

**R-GB6 Posted gifts are ordinary gifts.** Posting inserts `Gift__c` records in user mode
through the same triggers a single gift goes through: the household is derived, the default
allocation is created, rollups run and the receipt lock applies (Sections 18 and 19). Where
a line's fund (its own or the batch's) is set, the gift's single default allocation is
pointed at it afterwards, the path quick gift entry takes, so the allocations still total
the gift (R-GA1). Every posted gift has Status Received.

### Salesforce implementation

- **Object:** `Gift_Batch__c`, auto-number Name with format `GB-{000000}`, sharing model
  Private, as for `Gift__c`, because a batch's lines show exactly what a gift shows.

| Attribute | API name | Type |
|---|---|---|
| Description | `Description__c` | Text(255) |
| Status | `Status__c` | Picklist: Open (default), Posted |
| Control Total | `Control_Total__c` | Currency |
| Default Gift Date | `Default_Gift_Date__c` | Date, default today |
| Default Payment Method | `Default_Payment_Method__c` | Picklist: Cash, Check (default), Card, ACH, Stock, Grant, Other |
| Default Fund | `Default_Fund__c` | Lookup to `Fund__c` |
| Default Appeal | `Default_Appeal__c` | Lookup to `Appeal__c` |

- **Validation rule:** `Posted_Batch_Is_Final` (R-GB4).
- **Service:** `GiftBatchService`, `GiftBatchSelector`, `GiftBatchWriter` (the Status and
  line Gift writes, under ADR-0021), `GiftBatchController`, LWC `giftBatchEntry` on the
  record page `Gift_Batch_Record_Page`.

---

## 25M. Gift Batch Row

### Definition

One line of a batch: one donor, one amount, one check number, waiting to become a gift. It
exists as a saved record from the moment it is saved, so a stack of twenty checks survives
the browser being closed and the interruption halfway down the pile.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The line's identifier, assigned automatically; lines are shown in the order they were created. |
| Gift Batch | reference(Gift Batch) | yes | The batch this line belongs to. |
| Donor Contact | reference(Contact) | conditional | The person who gave, where people are Contacts. |
| Donor Account | reference(Organization) | conditional | The account that gave: an organization, a household giving in its own name, or a person Account. |
| Amount | decimal | yes, to post | What the check or the cash was for. |
| Gift Date | date | no | The date this gift was received, when it differs from the batch's (R-GB1). |
| Payment Method | picklist(Cash, Check, Card, ACH, Stock, Grant, Other) | no | How this gift arrived, when it differs from the batch's. |
| Payment Reference | text | no | The check number or deposit reference, which is what makes a batch reconcilable against the bank statement. |
| Fund | reference(Fund) | no | The fund this gift is designated to, when it differs from the batch's. |
| Appeal | reference(Appeal) | no | The appeal this gift responded to, when it differs from the batch's. |
| Installment | reference(Installment) | no | The scheduled payment this line's gift pays, chosen by the person or chosen in advance as the only suggestion (R-GR5, R-DM8). Empty means a gift on its own. |
| Gift | reference(Gift) | computed | The gift this line produced, written by posting and empty before it (R-GB6). |

### Relationships

- **Gift Batch Row to Installment**, many to one, optional; cleared if the installment is
  deleted.
- **Gift Batch Row to Gift Batch**, many to one, master-detail, not reparentable.
- **Gift Batch Row to Donor**, many to one, to exactly one of Donor Contact or Donor Account
  by the time the batch posts (Section 4 "Person references").
- **Gift Batch Row to Gift**, one to one, and only after posting.

### Rules

**R-GR1 Exactly one donor, by posting time.** A line is typed a field at a time, so a line
with no donor, or with no amount, can be saved. Posting refuses a line with neither donor
or with both, and names the line.

**R-GR2 A line is checked twice, and the second check is the one that counts.** The grid
tells the person what is missing as they type. Posting applies the same checks on the
server, and posting is what refuses. Nothing trusts the browser.

**R-GR3 A line is money received.** Its amount must be greater than zero: a refund is
recorded against the gift it reverses (R-G3), never typed into a deposit. In-kind is not a
payment method a line can have, because an in-kind gift carries no amount (R-G12) and is
entered one at a time with its description.

**R-GR4 A line of a posted batch is closed.** Once its batch is Posted, a line cannot be
added to the batch or changed. The one change allowed is the platform clearing Gift when
that gift is deleted, because refusing it would let a posted batch stop a gift from ever
being deleted. Deleting a line of a posted batch is refused by the entry screen but not by
the database: see "Known gaps in shipped rules" in Section 30. The platform clearing
Installment when that installment is deleted is allowed for the same reason.

**R-GR5 A line pays the payment it names, or nothing.** A line's Installment is offered and
suggested as R-DM8 says, using the line's date or the batch's (R-GB1). Posting checks every
named installment again, in the posting user's mode, before any gift is created: one that is
no longer a candidate of the line's donor refuses the post and names the line (R-GB5). A
posted gift carries the line's Installment and that installment's Commitment. Two lines may
name one installment.

### Salesforce implementation

- **Object:** `Gift_Batch_Row__c`, labelled Gift Batch Line, auto-number Name with format
  `GBR-{000000}`, sharing model ControlledByParent. No tab and no page layout: lines are
  read and typed in the batch's grid.

| Attribute | API name | Type |
|---|---|---|
| Gift Batch | `Gift_Batch__c` | Master-Detail to `Gift_Batch__c`, relationship `Rows` |
| Donor Contact | `Donor_Contact__c` | Lookup to Contact |
| Donor Account | `Donor_Account__c` | Lookup to Account |
| Amount | `Amount__c` | Currency |
| Gift Date | `Gift_Date__c` | Date |
| Payment Method | `Payment_Method__c` | Picklist: Cash, Check, Card, ACH, Stock, Grant, Other |
| Payment Reference | `Payment_Reference__c` | Text(255), the length of the gift's |
| Fund | `Fund__c` | Lookup to `Fund__c` |
| Appeal | `Appeal__c` | Lookup to `Appeal__c` |
| Installment | `Installment__c` | Lookup to `Installment__c`, cleared if the installment is deleted |
| Gift | `Gift__c` | Lookup to `Gift__c`, cleared if the gift is deleted |

- **Validation rule:** `Posted_Batch_Rows_Are_Final` (R-GR4).

---

## 25N. Gift import and donation matching

### Definition

How a row of an imported file becomes a gift (feature G-23), and how that gift is matched to
a payment the donor already owes (feature G-24). This section adds no object: the import is
Core's (Sections 15 to 17A) and the records it makes are the ordinary Giving records of
Sections 18 to 25. What it defines is the Giving package's `ImportEntityProcessor` (R-IR6),
the class `GiftImportProcessor`, and the rules it keeps (plan Section 4.9, "Row semantics"
and "Donation matching (Giving)"). The choices the plan leaves open are recorded in ADR-0052.

### Rules

**R-GI1 Which rows carry a gift.** A row carries a gift when it has a value for any `Gift`,
`Allocation`, `SoftCredit` or `Tribute` attribute. A row that carries an allocation, a soft
credit or a tribute but no gift amount is rejected, because there is nothing to allocate or
credit. Rows Core rejected are left alone.

**R-GI2 The donor.** The gift's donor is the row's first person (a Contact, or a person
Account in person account mode) when the row has one, and otherwise its organization. The
virtual attribute `Gift.Donor`, from a column or the template's defaults, overrides that with
`Contact1`, `Organization` or `Household` (the household the row resolved to). A row whose
donor is not there is rejected with a sentence saying which donor was missing. In a dry run a
donor Core would create has no identifier yet; the gift is then reported as one that would be
created, and it is matched to nothing (R-DM2).

**R-GI3 The gift.** Gift attributes are written by API name, as `Gift.Amount__c` or
`Gift.Gift_Date__c`, onto any gift attribute the running user may create, except the ones the
package writes itself: Household, Status, Receipt Number, Tribute, Commitment, Installment,
Original Gift, Matched Gift, Created By Import Batch and Sample Data. Status is always
Received. Amount, Gift Date and Type are required (Type from a column or the template's
default, never guessed), except that an In-kind gift has no amount (R-G12): an empty amount
reads as 0 and any other amount rejects the row. A date is read as `YYYY-MM-DD` or in the
running user's locale; a value that cannot be read rejects the row rather than defaulting.
Type is matched to its picklist ignoring case, with a short list of the words payment files
use ("credit card" is Card, "cheque" is Check, "bank transfer" is ACH, "in kind" is In-kind);
anything else rejects the row and names the accepted values. The virtual attribute
`Gift.Appeal` names an appeal by name or identifier; an appeal that does not exist rejects the
row. The gift carries Created By Import Batch (R-IB3).

**R-GI4 The allocations.** `Allocation.Fund` names one fund, by name, accounting code or
identifier; an inactive fund is accepted, because a migration names funds that have since
closed. A split names each part with a number: `Allocation.Fund1` with `Allocation.Amount1`
or `Allocation.Percent1`, `Allocation.Fund2` with `Allocation.Amount2` or
`Allocation.Percent2`, and so on; an attribute with no number is part 1. One fund and no
amount or percent is the whole gift, and is applied the way every entry screen applies a
chosen fund (`GiftService.applyChosenFunds`). A split must add up: its amounts to the gift's
amount, or its percents to 100, and a split that does not is rejected in the dry run with the
difference. A split is saved with the gift's default allocation suppressed and all its parts in
one save, because R-GA1 refuses every intermediate state. A row with no fund gets the default
allocation (R-GA2).

**R-GI5 The soft credit.** `SoftCredit.Role__c` makes a soft credit and must be one of the
role values, ignoring case; `SoftCredit.Custom_Role__c` is required with Other. The credited
party is the row's second person unless the virtual attribute `SoftCredit.Party` names
`Contact1`, `Contact2`, `Organization` or `Household`. `SoftCredit.Amount__c` defaults to the
gift's amount (R-SC4 allows either). A credit the package has already made for the same
party and role, such as the automatic household member credit (R-SC3), is not duplicated: the
row records that credit instead.

**R-GI6 The tribute.** `Tribute.Type__c` makes a tribute and must be In honor of or In memory
of. The other tribute attributes are written by API name (`Tribute.Honoree_Name__c`,
`Tribute.Notification_Recipient_Name__c`, `Tribute.Message__c`); an honoree name is required
when nothing else names the honoree (R-TR2).

**R-GI7 A row's gift is saved whole or not at all.** The gift, its allocations, its soft credit
and its tribute are one unit. When a part after the gift fails, the gift is deleted, which
takes its other parts with it, and the row is rejected with the platform's reason. A row
therefore never leaves half a gift behind, and loading the corrected row again creates it once.

**R-GI8 Idempotent and truthful.** The dry run makes every decision the commit makes that
does not need a save: the donor, the gift's values, the funds, the appeal, the split, the
match. Validation the gift triggers do (for example an in-kind gift with no description,
R-G12) is reported by the commit on its row. The processor returns the total of every
readable gift amount in the chunk, rejected rows included, for the control totals (R-IB10).

**R-GI9 What an undo keeps.** The undo deletes the gifts the batch created (R-IB9), which
takes their allocations, soft credits and tributes. It keeps, and journals with the reason, a
gift that carries a Receipt Number, that any receipt names (issued or void), or whose donor
has an issued year-end statement for the gift's year, because a document the donor holds
lists it (ADR-0010, ADR-0024); a person holding `Override_Receipt_Lock` does not change this.
It also keeps a person, household or organization that a kept gift, or a soft credit on one,
still names, so a donor is never deleted from under a gift that stays.

**R-DM1 The order of matching.** An incoming gift is matched first to an existing gift by
External Id, then to an open installment of the same donor. A gift found by External Id is
the row's gift: the row is Matched, the gift is not changed, and the row's allocations, soft
credit and tribute are not loaded again. This holds under every behaviour except Never match
(R-DM5), so re-running a file never duplicates a gift (R-IB4, R-G7). A row repeating the
External Id of an earlier row of the same run is that row's gift under every behaviour, Never
match included: within a chunk it shares the earlier row's outcome, and across chunks it is
Matched when an earlier chunk loaded the gift (or, in a dry run, would load it), so the dry
run and the commit agree.

**R-DM2 Which installments are candidates.** An installment is a candidate when its Status is
Scheduled, Overdue or Partially paid, its commitment's Status is Active or Paused, and the
commitment belongs to the gift's donor: its Donor Contact or Donor Account is the donor, or
its Household is the donor's household. A donor that does not exist yet has no candidates.

**R-DM3 The window and the tolerance.** A candidate matches when its Due Date is within the
date window of the gift's date, either side, and its Expected Amount differs from the gift's
amount by no more than the amount tolerance. Each comes from the template (R-IT7), and when
the template is empty from the org's defaults (`Donation_Match_Date_Window_Days__c`, 7, and
`Donation_Match_Amount_Tolerance__c`, 0: the amounts must be equal). A commit uses the
values its dry run took (R-DM7).

**R-DM4 Closest date wins, and a tie is refused.** Among matching candidates the one whose
due date is closest to the gift's date wins. Two at the same distance are a tie: the row is
rejected naming both, because choosing between two payments is a decision for a person.
Within one run an installment an earlier row claimed is no longer a candidate, in a dry
run as in a commit: the claims are carried from chunk to chunk (R-IR6).

**R-DM5 Four behaviours.** The template's Donation Matching is one of:

- **Match or create** (the default): a matched installment is paid by the new gift, and a
  gift that matches nothing is created on its own.
- **Always create**: installments are not looked at; a gift is created on its own.
- **Match only**: a gift that matches nothing is rejected, saying so.
- **Never match**: a row whose gift would match an installment, or whose External Id names a
  gift that existed before the run, is rejected naming what it matched.

**R-DM6 A match is a link, and the numbers follow.** A matched gift is created with its
Installment and that installment's Commitment set, so the installment's status and the
commitment's paid to date and balance update through the ordinary gift triggers and rollups
(R-IN2, R-IN3, Section 26). Nothing else is written to the installment or the commitment.

**R-DM7 The commit matches as the dry run did.** The behaviour, the window and the tolerance
are resolved (template, else org setting, else shipped default) once per dry run, on its first
chunk, carried to its later chunks and recorded on the batch (R-IB11). The commit reads them
from the batch, never from the template or the settings, so an edit made after the dry run
cannot make the commit match, refuse or create what the dry run did not show. A batch with no
recorded values, or values that cannot be read, falls back to the template.

**R-DM8 A gift entry screen suggests, and a person decides.** Quick Gift Entry (G-03) and a
gift batch line (G-17, R-GR5, checked again at posting) offer the chosen donor's candidates (R-DM2, with no date bound) as payments the new gift can pay,
with None always offered. A candidate whose due date and expected amount fall within R-DM3's
window and tolerance, taken from the org's settings (no template is involved), is marked
suggested. It is chosen in advance only when it is the only one suggested, and then it is
shown chosen with a note saying why; otherwise None is chosen. R-DM4's choice by closest date
and R-DM5's behaviours do not apply: the person sees the choice and may change it. The save
checks the chosen installment again in the saving user's mode: it must still be a candidate of
the gift's donor, and a gift of goods (R-G12) pays none; otherwise the save is refused, beside
the choice, and nothing is written. A gift saved with a choice carries the Installment and
that installment's Commitment, and the numbers follow as in R-DM6. Two gifts may pay one
installment: each counts toward it.

### Salesforce implementation

- **Gift entry:** `GiftEntryPayments` (the candidates for a donor, the suggestion and the
  check at save, R-DM8), using `DonationMatcher.matching` for R-DM3 and
  `InstallmentSelector.selectOpenForDonors` for R-DM2.
- **Service:** `GiftImportProcessor` (the `ImportEntityProcessor` Core finds by name),
  `GiftImportRow` (one row's gift as read), `GiftImportReferences` (funds and appeals),
  `GiftImportCredits` (soft credit and tribute), `GiftImportSelector` (funds, appeals and open
  installments, within the importing user's sharing), `GiftImportIntegritySelector` (what
  already exists: gifts by external ID, and the receipts, statements and gifts an undo must
  keep; `without sharing` under ADR-0021), `DonationMatcher` (R-DM1 to R-DM7),
  `GiftImportRunState` (what one run carries from chunk to chunk: the claimed payments, and in
  a dry run the matching values it took, R-DM7). In a dry run an external ID loaded is not
  carried: its 64-bit digest (of the lowercased value) is written to the row's Processor Key
  and later chunks query only their own digests (R-IR6), while a commit finds those gifts by
  the batch stamp. The claimed payments are still carried, one identifier per matched gift, so
  a run that matches hundreds of thousands of scheduled payments is the remaining heap limit.
- **Settings keys** (on `Giving_Settings__c`, Section 21A):
  `Donation_Match_Date_Window_Days__c`, `Donation_Match_Amount_Tolerance__c`.
- **Template attributes** (on `Import_Template__c`, Section 15): `Payment_Matching__c`,
  `Match_Date_Window_Days__c`, `Match_Amount_Tolerance__c`.

---

## 26. Packaged default rollups

### Definition

The Rollup Definitions the Giving package ships and the attributes they write (plan
Sections 4.6 and 4.10, features G-02 and G-11). They are shipped as
`Rollup_Definition_Default__mdt` rows and materialized as `Rollup_Definition__c` records
on install (Section 13, R-R6). Every one of them is editable and deactivatable by the
admin.

The Giving package owns these target attributes, including the ones that sit on the
standard Account and Contact objects. An org without Giving installed has none of them,
which is Principle 3.

### Target scopes

Account carries households, organizations, and, in Person Account orgs, people. One
target attribute therefore serves three kinds of record, filled by three definitions whose
target record sets are disjoint (R-R8).

| Scope | Target entity | Target filter | Relationship path from Gift |
|---|---|---|---|
| Household | Account, record type Household | record type is Household | `Household__c` |
| Account (organization or person) | Account, any other record type | record type is not Household | `Donor_Account__c` |
| Contact | Contact | none | `Donor_Contact__c` |

Definition keys follow the scope: `Household_Total_Giving`, `Account_Total_Giving`,
`Contact_Total_Giving`, and so on, so a shipped default can be found by name.

### Giving totals on Account and Contact

Every definition here uses source entity Gift with the base filter `Status` in
`Received`, `Refunded`, `Written off`, and mode Both. The set, rather than `Status equals
Received`, is what makes R-R9 true: a refund is a negative gift whose own status is
Received while the original it reverses is moved to Refunded, so a filter that admitted
only Received would keep the negative rows and drop the positive one, and a fully refunded
gift would subtract itself twice (ADR-0022). Pending, Cancelled, Failed, and any other status that
does not represent money the organization holds stay outside the filter.

The rows that count, rather than add, carry `Amount__c` greater than 0 on top of that
status set, so that a gift given once and refunded in full reads as one gift and a total
of zero. A count and a sum here answer different questions on purpose: how many gifts this
donor gave, and what the organization is left holding.

| Target attribute | Aggregate | Source attribute | Extra filter | Definition |
|---|---|---|---|---|
| `Total_Giving__c` | SUM | `Amount__c` | none | The total of all gifts ever received from this donor, net of anything given back. |
| `Gift_Count__c` | COUNT | none | `Amount__c` greater than 0 | How many gifts this donor has given, counting a gift once whether or not it was later refunded. |
| `First_Gift_Date__c` | MIN | `Gift_Date__c` | `Amount__c` greater than 0 | The date of this donor's first gift, which is what "new donor" reporting counts from. |
| `Last_Gift_Date__c` | MAX | `Gift_Date__c` | `Amount__c` greater than 0 | The date of this donor's most recent gift, which is what lapsed-donor reporting counts from. |
| `Largest_Gift__c` | MAX | `Amount__c` | `Amount__c` greater than 0 | The largest single gift this donor has given. Without the amount condition a donor whose whole history was refunded would have a negative gift as their largest. |
| `Giving_This_Year__c` | SUM | `Amount__c` | fiscal year offset 0 | Total given in the current fiscal year. |
| `Giving_Last_Year__c` | SUM | `Amount__c` | fiscal year offset -1 | Total given in the previous fiscal year, which is the "LY" in LYBUNT. |
| `Giving_Two_Years_Ago__c` | SUM | `Amount__c` | fiscal year offset -2 | Total given two fiscal years ago, used by SYBUNT and retention reporting. |
| `Gifts_Last_Year__c` | COUNT | none | `Amount__c` greater than 0, fiscal year offset -1 | How many gifts this donor gave in the previous fiscal year, counting a gift once whether or not it was later refunded. A sum cannot answer this: a donor whose only gift last year was refunded inside that same year sums to zero while having given, and a donor whose sole activity last year was a refund of an older gift sums to less than zero while having given nothing. The retention reports read this attribute to tell a retained donor from a reactivated one (G-16, ADR-0026). |

### In-kind giving on Account and Contact

An in-kind gift is a Gift with Type In-kind whose Amount is zero (R-G12, ADR-0030), so it
adds nothing to any row in the table above and is excluded from every row that counts, which
is what keeps a donated vehicle out of Total Giving, out of Largest Gift, out of a donor level
(ADR-0028) and out of the retention reports (ADR-0026). These two rows are where it does
appear. They take the same status set and add `Type__c` equals `In-kind`.

| Target attribute | Aggregate | Source attribute | Extra filter | Definition |
|---|---|---|---|---|
| `In_Kind_Value__c` | SUM | `Fair_Market_Value__c` | `Type__c` equals `In-kind` | What this donor's gifts of goods and services were worth, as the organization recorded them. Reported beside Total Giving and never added to it. |
| `In_Kind_Gift_Count__c` | COUNT | none | `Type__c` equals `In-kind` | How many gifts of goods and services this donor has given. There is no amount condition here, because a donor can give goods whose value they never told the organization and that gift still happened. |

Two further definitions on the same targets use different sources:

| Target attribute | Source | Aggregate | Source attribute | Filter | Definition |
|---|---|---|---|---|---|
| `Pledge_Balance__c` | Commitment | SUM | `Balance__c` | Type is Pledge and Status is Active or Paused | What this donor has promised and not yet paid. |
| `Total_Soft_Credits__c` | Soft Credit | SUM | `Amount__c` | gift status in the set above | The total this donor is recognized for without being hard credited. |
| `Soft_Credit_Count__c` | Soft Credit | COUNT | none | gift status in the set above, `Amount__c` greater than 0 | How many gifts this donor is recognized on. |

Relationship paths for the two non-Gift sources follow the same scope table, reading
`Household__c`, `Donor_Account__c`, or `Donor_Contact__c` on Commitment and `Account__c`
or `Contact__c` on Soft Credit.

### Totals on Giving objects

| Target entity | Target attribute | Source | Aggregate | Source attribute | Filter | Definition |
|---|---|---|---|---|---|---|
| Fund | `Total_Raised__c` | Gift Allocation | SUM | `Amount__c` | gift status in the set above | Everything ever designated to this fund. |
| Fund | `Total_Raised_This_Year__c` | Gift Allocation | SUM | `Amount__c` | gift status in the set above, fiscal year offset 0 | Designated to this fund in the current fiscal year. |
| Fund | `Gift_Count__c` | Gift Allocation | COUNT | none | gift status in the set above, `Amount__c` greater than 0 | How many gifts have been designated to this fund. |
| Fund | `Last_Gift_Date__c` | Gift Allocation | MAX | `Gift__r.Gift_Date__c` | gift status in the set above, `Amount__c` greater than 0 | The most recent gift to this fund. |
| Appeal | `Total_Raised__c` | Gift | SUM | `Amount__c` | status in the set above | What this appeal brought in. |
| Appeal | `Gift_Count__c` | Gift | COUNT | none | status in the set above, `Amount__c` greater than 0 | How many gifts responded to this appeal. |
| Commitment | `Paid_To_Date__c` | Gift | SUM | `Amount__c` | status in the set above | What has been paid against this commitment. |
| Installment | `Paid_Amount__c` | Gift | SUM | `Amount__c` | status in the set above | What has been paid against this scheduled installment. |

The fund definitions aggregate Gift Allocation but filter and read attributes on the
parent gift, written with a relationship-qualified name such as `Gift__r.Status__c`. That
is a requirement on the aggregation engine, recorded here so that it is part of the
vendoring evaluation in ADR-0011 rather than a surprise during the build. It has a second
half that R-R11 states: a change to the gift (its status, or its delete, which removes its
allocations without firing their trigger) has to mark the gift's funds for recalculation,
because the allocation row the fund total counts was not itself saved.

Appeal donor count is deliberately absent: counting distinct donors is not one of the
seven aggregates the engine offers (plan Section 4.10), and a grouped report answers it
without a new engine capability.

### Freshness: one last-calculated attribute per target entity

Every target entity carries a single `Rollups_Last_Calculated__c` datetime, written when
a rollup pass over that entity completes. There is not one per target attribute.

*Why.* The requirement is that a rollup shows when it was last calculated (Principle 2,
plan Section 4.10). Two questions are actually asked, and one attribute each answers
them: "when was this record's giving last recalculated", answered on the record page by
the entity-level attribute, and "when did this particular rollup last run", answered in
the settings console by Last Calculated on the Rollup Definition (R-R5). A per-attribute
sibling would add eleven datetime attributes to Account and eleven to Contact, all
carrying the same value whenever the pass that writes them is the same pass, which it is:
the engine recalculates a target record's definitions together. The cost of the choice is
that a single definition recalculated on its own moves the whole entity's stamp, which is
why the definition keeps its own Last Calculated as well.

### Salesforce implementation

- **Fields on Account** (shipped by Giving, shown read only in the Giving section of
  Giving's own Account and Contact record pages, ADR-0064 on the donor record pages):

| Attribute | API name | Type |
|---|---|---|
| Total Giving | `Total_Giving__c` | Currency |
| Gift Count | `Gift_Count__c` | Number |
| First Gift Date | `First_Gift_Date__c` | Date |
| Last Gift Date | `Last_Gift_Date__c` | Date |
| Largest Gift | `Largest_Gift__c` | Currency |
| Giving This Year | `Giving_This_Year__c` | Currency |
| Giving Last Year | `Giving_Last_Year__c` | Currency |
| Giving Two Years Ago | `Giving_Two_Years_Ago__c` | Currency |
| Gifts Last Year | `Gifts_Last_Year__c` | Number |
| Pledge Balance | `Pledge_Balance__c` | Currency |
| Total Soft Credits | `Total_Soft_Credits__c` | Currency |
| Soft Credit Count | `Soft_Credit_Count__c` | Number |
| In-kind Value | `In_Kind_Value__c` | Currency |
| In-kind Gift Count | `In_Kind_Gift_Count__c` | Number |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Fields on Contact** (shipped by Giving): the same fifteen API names, with the same
  types and the same definitions.

- **Fields on `Fund__c`:**

| Attribute | API name | Type |
|---|---|---|
| Total Raised | `Total_Raised__c` | Currency |
| Total Raised This Year | `Total_Raised_This_Year__c` | Currency |
| Gift Count | `Gift_Count__c` | Number |
| Last Gift Date | `Last_Gift_Date__c` | Date |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Fields on `Appeal__c`:**

| Attribute | API name | Type |
|---|---|---|
| Total Raised | `Total_Raised__c` | Currency |
| Gift Count | `Gift_Count__c` | Number |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Fields on `Commitment__c`:**

| Attribute | API name | Type |
|---|---|---|
| Paid To Date | `Paid_To_Date__c` | Currency |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Fields on `Installment__c`:**

| Attribute | API name | Type |
|---|---|---|
| Paid Amount | `Paid_Amount__c` | Currency |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Shipped defaults:** one `Rollup_Definition_Default__mdt` row per line in the tables
  above, per scope.
- **Service:** the Core engine (Section 14); Giving ships definitions, not engine code.

---

# Part E: Core additions for v0.3

These three entities are built by the v0.3 iteration in the Core package (features C-15,
C-16, C-17). They are constituent data: they describe how the people and organizations in
Part A are connected and where they live.

## 27. Relationship

### Definition

A connection between two people: spouses, a parent and a child, two colleagues, a friend
who introduced a donor (feature C-15, v0.3). This is the successor to NPSP's relationship
object, and its defining behavior is that the package maintains the other side of the
connection so that staff never enter it twice.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The relationship's identifier, assigned automatically. |
| Contact | reference(Contact) | conditional | The person this relationship is described from, where people are Contacts. |
| Person Account | reference(Organization) | conditional | The person this relationship is described from, where people are person Accounts. |
| Related Contact | reference(Contact) | conditional | The other person, where people are Contacts. |
| Related Person Account | reference(Organization) | conditional | The other person, where people are person Accounts. |
| Type | picklist(Spouse, Partner, Parent, Child, Sibling, Grandparent, Grandchild, Friend, Colleague, Employer contact, Other) | yes | What the other person is to this person, read from this person's side. |
| Reciprocal Type | picklist(same values as Type) | computed | What this person is to the other one, filled from the shipped type mapping. |
| Status | picklist(Current, Former) | yes (defaults Current) | Whether the relationship still holds. |
| Start Date | date | no | When the relationship began. |
| End Date | date | no | When the relationship ended; empty means current. |
| Description | long text | no | Anything staff need to remember about the connection. |
| Reciprocal Relationship | reference(Relationship) | computed | The record that describes the same connection from the other person's side. |
| Is Reciprocal Managed | boolean | yes (defaults true) | Whether the package keeps the other side in step with this one. |

### Relationships

- **Relationship to each person**, many to one, to exactly one of Contact or Person
  Account on each side (Section 4 "Person references").
- **Relationship to Relationship**, one to one, pairing the two sides of one connection.

### Rules

**R-RL1 The package owns the other side.** Saving a relationship creates the mirrored
record from the other person's side, with the two sides pointing at each other and the
mirrored record's Type set from the reciprocal mapping. Editing Status, Start Date, End
Date, or Description on either side updates the other. Deleting either side deletes both.
This is controlled by the org's automatic reciprocal setting, which is on by default. On by
default means on before the org has saved anything: a checkbox on a hierarchy custom setting
reads back false, not its declared default, until Apex puts the shipped value on the record
(ADR-0035).

**R-RL2 Is Reciprocal Managed is the opt-out.** An org that needs the two sides to differ
(a relationship described asymmetrically, or one imported from a system that already holds
both sides) clears Is Reciprocal Managed on a record, and the package stops synchronizing
it while leaving the pairing reference intact.

**R-RL3 Reciprocal types come from shipped metadata.** The mapping from a type to its
reciprocal is `Relationship_Type__mdt` (Section 13). It ships gender-neutral: Parent maps
to Child, Child maps to Parent, Spouse and Partner and Sibling and Friend and Colleague
map to themselves, Grandparent maps to Grandchild, Employer contact maps to Colleague, and
anything unmapped maps to Other. No shipped row is gendered, so no reciprocal ever asserts
a person's gender from a relationship.

**R-RL4 A person is not related to themselves.** The two sides must be different people,
and a duplicate relationship of the same type between the same two people is rejected with
a message naming the existing record. A duplicate is counted in one direction: the same
person on this side, the same person on the other side, and the same type. A to B as
Parent and B to A as Parent are two different relationships and both are allowed, which is
what makes the mirrored record of A to B as Parent (B to A as Child) legal rather than a
duplicate of anything.

**R-RL4a Pairing prefers a record that is already there.** Before the package creates the
other side it looks for a relationship that is already the other side and is not paired
with anything: the two people the other way round, of exactly the reciprocal type, with no
Reciprocal Relationship set. Finding one, it pairs the two records instead of creating a
third. This is what makes an import that already carried both sides, and a restore from
the recycle bin that brought both sides back, settle into one pair rather than into
duplicates. A restore that brings back only one side first looks in the recycle bin for the
other side deleted with it and restores that record, so restoring one side, then the other,
or both at once, always ends with the original pair.

**R-RL5 Status follows the dates.** Setting End Date sets Status to Former on both sides.
Clearing it returns both to Current. Status is never left disagreeing with the dates.

**R-RL6 Relationships are not household membership.** A relationship never changes who is
in a household. Spouses in one household have both a household membership and, optionally,
a Spouse relationship, and the two mechanisms do not read each other.

### Salesforce implementation

- **Object:** `Relationship__c`, auto-number Name with format `RL-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Contact | `Contact__c` | Lookup to Contact |
| Person Account | `Person_Account__c` | Lookup to Account |
| Related Contact | `Related_Contact__c` | Lookup to Contact |
| Related Person Account | `Related_Person_Account__c` | Lookup to Account |
| Type | `Type__c` | Picklist: Spouse, Partner, Parent, Child, Sibling, Grandparent, Grandchild, Friend, Colleague, Employer contact, Other |
| Reciprocal Type | `Reciprocal_Type__c` | Picklist, same values as `Type__c`, not restricted: BarnCRM always writes it from the relationship type mapping, whose values the custom metadata page checks against `Type__c`, so a custom type added to `Type__c` alone saves |
| Status | `Status__c` | Picklist: Current, Former |
| Start Date | `Start_Date__c` | Date |
| End Date | `End_Date__c` | Date |
| Description | `Description__c` | Long Text Area |
| Reciprocal Relationship | `Reciprocal_Relationship__c` | Lookup to `Relationship__c` |
| Is Reciprocal Managed | `Is_Reciprocal_Managed__c` | Checkbox |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

- **Shipped defaults:** `Relationship_Type__mdt` (Section 13).
- **Settings key:** `Relationship_Auto_Reciprocal__c` (Section 12), registered in
  `SettingsService.SHIPPED_DEFAULTS` so a fresh org gets it switched on (ADR-0035).
- **Service:** `RelationshipService`, `RelationshipDomain`, `RelationshipSelector`.
- **Automation:** two registry rows on `Relationship__c`. `Relationship_Validation`, handler
  `RelationshipValidationHandler`, execution order 10, holds the defaults and the rules
  (R-RL3, R-RL4, R-RL5). `Relationship_Reciprocal`, handler
  `RelationshipMaintenanceHandler`, execution order 30, writes and removes the other side.
  Two rows so that switching the upkeep off from the Automation page leaves every rule
  running. The service stands both automations down by name while it writes the other side,
  which is how a mirrored write does not re-enter the trigger that made it and is not
  checked a second time against the record it mirrors.

---

## 28. Affiliation

### Definition

A person's connection to an organization: an employee, a board member, a congregant, a
staff contact at a funder (feature C-16, v0.3). This is the successor to NPSP's
affiliation object, and it is what lets a person be related to an organization without
leaving their household.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The affiliation's identifier, assigned automatically. |
| Contact | reference(Contact) | conditional | The person, where people are Contacts. |
| Person Account | reference(Organization) | conditional | The person, where people are person Accounts. |
| Organization | reference(Organization) | yes | The organization the person is connected to. |
| Role | text | no | What the person does there, in the org's own words, for example "Board chair". |
| Status | picklist(Current, Former) | yes (defaults Current) | Whether the person is still connected to the organization. |
| Is Primary | boolean | yes (defaults false) | Marks the organization this person is chiefly associated with. |
| Start Date | date | no | When the connection began. |
| End Date | date | no | When the connection ended; empty means current. |
| Description | long text | no | Anything staff need to remember about the connection. |

### Relationships

- **Affiliation to the person**, many to one, to exactly one of Contact or Person Account
  (Section 4 "Person references").
- **Affiliation to Organization**, many to one.
- **Contact to Primary Affiliation**, many to one: the person's primary organization,
  maintained by the package (R-AF2).

### Rules

**R-AF1 One person, one organization, dated.** A person may have many affiliations at
once, and the same person and organization may be affiliated more than once over time, so
long as the date ranges do not overlap for the same role.

**R-AF2 One primary per person.** At most one current affiliation per person has Is
Primary true. Setting it on a second clears the first, and the package mirrors the
primary organization to the person's Primary Affiliation reference so that a list view or
a mail merge can show an employer without a subquery.

**R-AF3 Affiliation is not household membership.** Setting an affiliation never changes
the person's household or their Account reference in contact mode. This is the mistake the
entity exists to prevent: a donor who works at a foundation is still a member of their
household.

**R-AF4 Status follows the dates.** As R-RL5: setting End Date sets Status to Former, and
a former affiliation is never the primary one.

**R-AF5 Created by the importer.** A spreadsheet row that names an employer creates or
matches an affiliation (R-IR1), which is how most affiliations in a converted org arrive. A
people import links the row's first person to the row's organization once both are resolved,
after the people are saved: a current affiliation of that person with that organization is
matched and nothing is written; otherwise one is created with the row's `Affiliation`
attributes, through the ordinary rules (R-AF1 to R-AF4, so it is primary only when R-AF2 makes
it so). Two rows of a chunk naming the same pair make one. The dry run counts the row as
creating something and writes nothing, unless an earlier row of the file, in its chunk or an
earlier one, would link the same pair, which the commit then finds (R-IB12): a person or an
organization the run would create is told apart by the key a later row finds it by. A created affiliation carries no batch tag: it is
journaled as Created (R-IJ3) and an undo deletes it before the people and organizations. The
second person is not linked, as NPSP's import links only its first contact with its first
account.

### Salesforce implementation

- **Object:** `Affiliation__c`, auto-number Name with format `AF-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Contact | `Contact__c` | Lookup to Contact |
| Person Account | `Person_Account__c` | Lookup to Account |
| Organization | `Organization__c` | Lookup to Account |
| Role | `Role__c` | Text |
| Status | `Status__c` | Picklist: Current, Former |
| Is Primary | `Is_Primary__c` | Checkbox |
| Start Date | `Start_Date__c` | Date |
| End Date | `End_Date__c` | Date |
| Description | `Description__c` | Long Text Area |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

- **Field on Contact:** `Primary_Affiliation__c`, a Lookup to Account, maintained by the
  package (R-AF2). In Person Account orgs the same attribute exists on Account as
  `Primary_Affiliation__c`, added there with the other person attributes (Section 4
  "Person references"). It holds the **organization**, not the Affiliation record: the
  point of the field is that a list view or a mail merge can show an employer without a
  subquery, and an Affiliation id would not do that. The label an admin sees is Primary
  Affiliation because that is the nonprofit's word for it.
- **Automation:** two registry rows on `Affiliation__c`. `Affiliation_Validation`, handler
  `AffiliationValidationHandler`, execution order 10, holds the defaults and the rules
  (R-AF1, R-AF4). `Affiliation_Primary`, handler `AffiliationMaintenanceHandler`, execution
  order 30, settles who is primary. Two rows so that switching the upkeep off from the
  Automation page leaves every rule running. The service stands both automations down by
  name while it clears the primary flag from a person's other affiliations.
- **Service:** `AffiliationService`, `AffiliationDomain`.

---

## 29. Address

### Definition

A place a household, an organization, or a person receives mail (plan Section 4.7,
feature C-17). Addresses exist as records rather than as fields so that a household can
have more than one, so that a seasonal address can take over automatically, and so that
history is not lost when someone moves.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The address's identifier, assigned automatically. |
| Account | reference(Household) | conditional | The household or organization this address belongs to. |
| Contact | reference(Contact) | conditional | The person this address belongs to, for an address that is theirs rather than their household's. |
| Person Account | reference(Organization) | conditional | The person this address belongs to, where people are person Accounts. |
| Type | picklist(Home, Work, Mailing, Seasonal, Other) | yes | What kind of address this is. |
| Street | long text | no | The street address, including any second line. |
| City | text | no | The city or town. |
| State | text | no | The state, province, or region. |
| Postal Code | text | no | The postal or ZIP code. |
| Country | text | no | The country. |
| Seasonal Start Month | integer | conditional | The month a seasonal address takes over; required when Type is Seasonal. |
| Seasonal Start Day | integer | conditional | The day of that month; required when Type is Seasonal. |
| Seasonal End Month | integer | conditional | The month a seasonal address stops being used; required when Type is Seasonal. |
| Seasonal End Day | integer | conditional | The day of that month; required when Type is Seasonal. |
| Is Default | boolean | yes (defaults false) | Marks the address currently written to the standard address fields. |
| Verification Status | picklist(Unverified, Verified, Failed) | yes (defaults Unverified) | Whether an address verification service has confirmed this address. |
| Latest Verified Date | date | no | When verification last succeeded. |
| Replaced By Seasonal | boolean | yes (defaults false) | Marks the address the seasonal swap displaced, so the job knows which address to put back when the season ends. |

### Relationships

- **Address to its owner**, many to one, to exactly one of Account, Contact, or Person
  Account (R-AD1).
- Addresses have no relationship to gifts or receipts: a receipt reads the owner's default
  address at the time it is issued and stores the text it printed (v0.4, G-13).

### Rules

**R-AD1 One owner.** Exactly one of Account, Contact, or Person Account is set. An address
owned by an account is the household's or the organization's; an address owned by a person
is theirs alone and does not affect their household.

**R-AD2 One default per owner.** At most one address per owner has Is Default true.
Setting it on a second clears the first. Within one save that marks several addresses of
one owner as default, the last of them keeps the flag. Clearing the flag on an owner's only
default, with no other put in use in the same save, is refused (label
`Core_Address_CannotUntickOnlyDefault`). When the default is deleted, the newest remaining
address that is not Seasonal is promoted, and a Seasonal one only when nothing else is left.
The first address added from the address card to an owner with none is saved as default.

**R-AD3 Default propagation.** The default address is copied to the standard address
fields, so every standard feature, report, and third-party app keeps working: to the
Account's billing address for a household or an organization, and to the Contact's mailing
address for a person. The copy happens on save and on the seasonal swap, and the standard
fields are never the place a change is made.

Where people are person accounts, the person's mailing fields are written instead of a
contact's. An account is written that way only when its record type is a person type. In a
person accounts org those mailing fields exist on every account record, but only a person
account will accept a value in one, so the org's shape is not the question: the record's
is. A household member, or an owner named in Person Account, that turns out to be a
household or an organization is left out of the copy rather than written and refused, which
would refuse the address the user was saving along with it.

**R-AD4 Seasonal swap.** A daily scheduled job makes the seasonal address the default
while today falls inside its range, and restores the previous default when the range ends.
Ranges may wrap the end of the year, so a November to March range is one range and not two.
A range is inclusive at both ends: an address used from November 1 to March 31 is in use on
November 1 and on March 31, and out of use on April 1.

The job works one owner at a time and does exactly one of four things for each:

1. A seasonal address is in season and is not the default: the current default is marked
   Replaced By Seasonal, its default flag is cleared, and the seasonal address becomes the
   default.
2. The default is a seasonal address whose season has ended: the address marked Replaced By
   Seasonal becomes the default again and that mark is cleared. If no address carries the
   mark, the most recently created address that is not seasonal is promoted instead, and if
   the owner has no other address the seasonal one stays in place rather than leaving the
   owner with no address at all.
3. Two seasonal addresses are in season on the same day, which is a data entry mistake: the
   oldest wins so the outcome does not change from night to night, and the run records the
   collision in the Error Log rather than choosing silently.
4. Nothing to do: the right address is already the default.

Nothing else on the address is touched, and the propagation to the standard address fields
(R-AD3) is the address automation's work rather than the job's, so switching that automation
off stops the copy without stopping the swap.

**R-AD8 The run is visible.** Every run records when it finished and what it did (how many
addresses moved in, how many moved back, how many failed), and both are shown on the Hub
home page and on the Addresses page of the settings console, where the schedule is also
started and stopped. A failure on one owner is written to the Error Log and the run
continues: one household with an unreachable address never stops the rest of the org
swapping. The job reads and writes in system mode, because a nightly reconciliation of
package owned data must not depend on what the person who happened to schedule it can see
(ADR-0027).

**R-AD5 Contact address change behavior.** When a person's address is edited, the org's
contact address change behavior setting decides what happens: update the household's
address, so everyone in the household moves together, or create a personal address for
that person alone. The setting is explained in those words in the settings console, not in
terms of objects.

**R-AD6 Verification is a placeholder.** Verification Status and Latest Verified Date are
never written by packaged code. They exist so that a third-party verification app can
write them and so that a report can find unverified addresses. Third-party verification is
out of scope (plan Section 4.7).

**R-AD7 History is kept.** Moving a household creates a new address and clears the old
one's default flag. The old address is not deleted, so a mailing sent last year can still
be explained.

### Salesforce implementation

- **Object:** `Address__c`, auto-number Name with format `AD-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Account | `Account__c` | Lookup to Account |
| Contact | `Contact__c` | Lookup to Contact |
| Person Account | `Person_Account__c` | Lookup to Account |
| Type | `Type__c` | Picklist: Home, Work, Mailing, Seasonal, Other |
| Street | `Street__c` | Text Area |
| City | `City__c` | Text |
| State | `State__c` | Text |
| Postal Code | `Postal_Code__c` | Text |
| Country | `Country__c` | Text |
| Seasonal Start Month | `Seasonal_Start_Month__c` | Number (0 decimals) |
| Seasonal Start Day | `Seasonal_Start_Day__c` | Number (0 decimals) |
| Seasonal End Month | `Seasonal_End_Month__c` | Number (0 decimals) |
| Seasonal End Day | `Seasonal_End_Day__c` | Number (0 decimals) |
| Is Default | `Is_Default__c` | Checkbox |
| Verification Status | `Verification_Status__c` | Picklist: Unverified, Verified, Failed |
| Latest Verified Date | `Latest_Verified_Date__c` | Date |
| Replaced By Seasonal | `Replaced_By_Seasonal__c` | Checkbox |

- **Standard fields written:** `Account.BillingStreet`, `BillingCity`, `BillingState`,
  `BillingPostalCode`, `BillingCountry`; `Contact.MailingStreet`, `MailingCity`,
  `MailingState`, `MailingPostalCode`, `MailingCountry`.
- **Settings keys:** `Contact_Address_Change_Behavior__c`, `Seasonal_Address_Last_Run__c`,
  `Seasonal_Address_Last_Run_Summary__c` (Section 12).
- **Service:** `AddressService`, `AddressTriggerHandler`, `AddressSelector` (the
  Addresses card reads and saves through Lightning Data Service, with no controller,
  ADR-0093 record reads through Lightning Data Service); and for the seasonal swap
  `SeasonalAddressService`,
  `SeasonalAddressSelector`, `SeasonalAddressWriter`, `SeasonalAddressBatch`,
  `SeasonalAddressScheduler`, `SeasonalAddressController`.

---

## 29A. Duplicate Dismissal

### Definition

A record of a person deciding that two records the duplicate scan proposed are not the same
household or the same person (plan Section 5.1, feature C-20). It exists so that a decision a
person already made is not asked again the next time the scan runs.

Nothing else about duplicates is stored here. The suggestions themselves are platform
records: the platform's duplicate rules write a Duplicate Record Set and its Duplicate Record
Items, and the BarnCRM scan writes the same two standard objects for duplicates that were
already in the org before anybody looked. BarnCRM adds no object for a suggestion, no
matching logic of its own, and no copy of what the platform found (R-DP1).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The dismissal's identifier, assigned automatically. |
| Pair Key | text | yes | The two record identifiers, sorted and joined, that a person said are not duplicates. Unique, so the same pair is dismissed once. |
| Reason | text | no | Why they are not duplicates, in the words of the person who decided: "twin sisters at the same address". |

### Relationships

- **Duplicate Dismissal to the two records it is about**, by identifier rather than by
  lookup. The pair is two Contacts or two Accounts, and one lookup field cannot point at
  either object, so the identifiers are held as text.

### Rules

**R-DP1 The platform detects, BarnCRM reviews.** What counts as the same person or the
same household is decided by the org's own active duplicate rules for Contact and Account,
and nothing else. BarnCRM ships no matching rule and no duplicate rule (ADR-0050): every
org starts with the platform's standard rules for both objects switched on, and an
administrator's own rules are used exactly as written. No packaged code compares two records
field by field to decide whether they are duplicates.

**R-DP2 Only pairs BarnCRM can act on are proposed.** A suggestion is two people, or two
households. A pair of accounts where either side is not a household (an organization, or a
person stored as an account) is passed over, because the household merge (R-H13) is the only
account merge BarnCRM performs and a suggestion nobody can act on here is noise. A household
that also carries a Nonprofit Cloud household group (`PartyRelationshipGroup`) is passed over
and refused by the merge (ADR-0036), and so is a pair naming a person account's contact half,
which the platform cannot merge with a contact. The panel applies the same rule to sets a
duplicate rule wrote on save, and hides a set whose every pair is dismissed (R-DP5).

**R-DP3 The scan finds what the rules would have found.** A duplicate rule runs when a record
is saved, so records already in the org, and records saved past an alert, are never compared
with each other. The scan asks the platform to evaluate its active duplicate rules against
the people and households that already exist, fifty records at a time, and writes a
Duplicate Record Set of exactly two items for each new pair it is given back. It never
proposes a pair that is already in a suggestion, and never one that has been dismissed. It is
started by a person from BarnCRM Settings and is not scheduled. It refuses to start when no
duplicate rule for Contact or Account is active, because a scan with nothing to evaluate would
report a clean org rather than an org nobody is checking.

**R-DP4 A merge is one pair at a time, previewed, and confirmed by a person.** No packaged
code merges or deletes records in bulk, and no automation merges anything. Two households are
merged by the household merge (R-H13) and nothing else. Two people are merged with the
platform's own merge, reached from the Potential Duplicates card on the person's record page,
because the platform already carries related records across safely.

**R-DP5 A dismissal is remembered, a suggestion is not.** Dismissing a suggestion writes a
Duplicate Dismissal for each pair in it and then deletes its Duplicate Record Set, which
removes the grouping and never touches the records. An administrator can delete a dismissal,
which is how a pair is put back in front of a reviewer. A household merge from the review
page deletes the suggestion without a dismissal, because the pair no longer exists.

### Salesforce implementation

- **Object** `Duplicate_Dismissal__c`, with an auto number Name. Sharing is public read/write:
  a dismissal is the organization's decision, and a scan run by one administrator must pass
  over a pair another administrator dismissed.

| Attribute | API name | Type | Notes |
|---|---|---|---|
| Pair Key | `Pair_Key__c` | Text(40), unique, external id | The two 18 character identifiers in ascending order, joined with a hyphen. |
| Reason | `Reason__c` | Text(255) | Optional. |

- **Suggestions** are the standard objects `DuplicateRecordSet` and `DuplicateRecordItem`,
  read with `DuplicateRule`. They are read and written in user mode, so a reviewer is never
  shown a pair containing a record they cannot see. Salesforce licenses them only to Sales
  Cloud and Service Cloud users, so no Core role grants them: the optional permission set
  `BarnCRM_Duplicate_Review` does, and the panel says so to anyone without it (ADR-0050).
- **People merges** are the platform's. When a contact, or a person stored as an account, is
  deleted by a merge (`MasterRecordId` filled in `after delete`), its memberships are
  recreated on the survivor in junction mode (all or none; only current rows count as already
  a member; a household whose primary member was merged away gets the survivor as its
  primary, R-M3), the households it was in are recounted but not tidied away, and the
  real-time rollups that target the merged entity are recalculated for the survivors only.
  For a person stored as an account that is the rollups on Account and on the survivor's
  person contact. An account merge of households (R-H13) recalculates the surviving
  household's real-time rollups the same way.
- **Merge settlement** (PEOPLE-15) runs just after any Salesforce merge, in a queued job
  (`MergeSettlement`): a person in both merged households keeps one membership, a household
  that took in members is recounted and renamed, a survivor keeps one default address (the one
  matching its standard address fields: billing for a household or organization, mailing for a
  contact or a person account, read by name so Core runs without person accounts; otherwise
  the newest), and a person loses relationships with themselves and second copies and has
  their primary affiliation chosen again. A merge that cannot queue the job (inside a
  Queueable, or with no queueable job left) publishes `Merge_Settlement_Ready__e` instead, and
  its subscriber queues the job after the merge commits (ADR-0118). Only a publish the
  platform refuses leaves the survivors to an administrator, named in the Error Log as a
  warning.
- **Event:** `Merge_Settlement_Ready__e`, a platform event, publish behavior Publish After
  Commit. `Household_Ids__c`, `Owner_Ids__c` and `Person_Ids__c` (Long Text Area, 32,768) each
  carry up to 200 comma-separated survivor identifiers; more survivors make more events.
  `MergeSettlementReadyTrigger` subscribes, as the Automated Process user, in batches of 50
  (`PlatformEventSubscriberConfig` `MergeSettlementReadyTriggerConfig`, no running user), and
  queues one settlement job per event, resuming from a checkpoint when its transaction can
  queue no more and retrying a batch it could queue nothing for. The three packaged permission sets
  grant Read and Create on it, as on `Rollup_Queue_Ready__e`.
- **Matching** is `Datacloud.FindDuplicatesByIds`, which evaluates the org's active duplicate
  rules. It is called for one object at a time, and for households only among accounts: a
  call that includes a person stored as an account is refused by the platform when no person
  account rule is active.
- **Merge** of households is `HouseholdMergeService` (R-H13). The Contact record page carries
  the platform's Potential Duplicates card (`runtime_sales_merge:mergeCandidatesPreviewCard`),
  which is where the platform's own person merge starts. The Account record page does not
  carry it, so a household is never merged past R-H13.
- **Service:** `DuplicateService`, `DuplicateSelector`, `DuplicateScanBatch`,
  `DuplicateController`. The review page is the `duplicateReview` panel on the Households page
  of BarnCRM Settings.

---

# Part F: Mirror additions for v0.6

The Mirror package is the only place a standard Salesforce object such as Campaign or
Opportunity may be named (plan Section 4.2), and even there only through dynamic Apex, so
Mirror installs on an org where the object is absent and its feature says it is unavailable.
The inbound gift API and the accounting export add nothing to the model (Section 30). Campaign
sync (X-02) adds one attribute to Appeal and Mirror's own settings object. The Opportunity
mirror (X-01) adds one attribute to Gift and two keys to that settings object.

---

## 29B. Campaign Sync

### Definition

A one-way copy of each appeal to a standard Salesforce Campaign, so that Campaign Members,
email tools and other marketing apps that only know Campaign see the organization's appeals
(plan Section 4.12, feature X-02). The appeal is the record staff edit; the Campaign follows
it. Nothing on a Campaign is ever copied back to an appeal.

Campaign sync is not an entity of its own. It is one attribute on Appeal, held by Mirror
because Giving may not name Campaign, and a switch on Mirror Settings. There is no link
object: an appeal has at most one Campaign, so the link is the attribute (ADR-0056, Campaign
sync keeps its link on the appeal).

### Attributes added to Appeal

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Campaign ID | text (18) | no | The record identifier of the Campaign this appeal is copied to. Written by Campaign sync when it creates the Campaign; an administrator may type an existing Campaign's identifier to link to it, or clear it to have a new Campaign made. Unique, so two appeals never share one Campaign. |

It is held as text rather than as a lookup because a lookup to Campaign is a compile-time
reference: Mirror would then refuse to install on an org without Campaign, which ADR-0013
and plan Section 4.2 forbid.

### Mirror Settings keys (v0.6)

| Key | Type | Default | Definition |
|---|---|---|---|
| `Campaign_Sync_Enabled__c` | boolean | false | Whether saving an appeal creates or updates its Campaign. Off at install, because an org that has Campaigns of its own must decide before BarnCRM adds more (R-CS1). |

### Rules

**R-CS1 Off until switched on.** Campaign sync does nothing until an administrator turns it
on in BarnCRM Settings. It also does nothing where the org has no Campaign object (a
Platform-only org), and the Campaign sync page says so rather than offering a switch that
cannot work. It is a registered automation on Appeal (`Campaign_Sync`), so it can also be
paused or switched off like any other (ADR-0040). The setting is authoritative: it says
whether the feature is wanted, and Sync all appeals follows it alone. The automation switch
only pauses the copy made on save, and has no effect while the setting is off.

**R-CS2 What is copied.** Name to Name, Description to Description, Start Date to Start
Date, End Date to End Date, Goal to Expected Revenue, Cost to Actual Cost, Active to Active,
and Parent Appeal to Parent Campaign (the parent appeal's Campaign, or none while the parent
has none). Nothing else is written: a new Campaign takes the org's defaults for Type and
Status, and the Campaign's own totals (from Opportunities) are the platform's. A Campaign
field changed by hand is overwritten the next time its appeal changes in one of these
attributes.

**R-CS3 When it is copied.** When an appeal is created, and when it is saved with a change to
one of the attributes in R-CS2, to its Campaign ID, or while it has no Campaign yet. The
Campaign is created or updated in the same save, before the appeal is written, so the new
Campaign ID is stored with the appeal and never in a second save. A Campaign whose values
already match is not updated.

**R-CS4 In the saver's own access.** The Campaign is written in user mode, with the access
of the person saving the appeal. Campaign is a standard object BarnCRM does not own, so
an elevated write (ADR-0021) is not available for it. Someone who cannot create or edit
Campaigns (in Salesforce that needs the Marketing User box on their user record as well as
Campaign permissions) still saves the appeal; the appeal simply stays without a Campaign.
One Warning is written to the Error Log when such a person creates appeals, at most once per
transaction; their later edits are skipped without one, so the log is not flooded.

**R-CS5 A failure never refuses the appeal.** A Campaign the platform refuses (a validation
rule on Campaign, a required field the org added, sharing) is written to the Error Log at
Warning with the appeal and the platform's message. The appeal saves, and keeps no Campaign
ID when none was created. However many appeals are refused, their Warnings are written in one
statement. A save too large to copy within the transaction's query and DML limits (thousands
of appeals in one Apex transaction) saves its appeals uncopied, logs one Warning, and leaves
them to Sync all appeals.

**R-CS6 Catching up.** The Campaign sync page shows how many appeals have a Campaign and how
many do not, and offers **Sync all appeals**, which runs R-CS2 over every appeal the person
can see, in the background, as that person. It is how the appeals that existed before the
feature was turned on get their Campaigns, and how appeals saved by someone without Campaign
access (R-CS4) are caught up. It needs the Manage BarnCRM Settings permission, and only one
runs at a time.

**R-CS7 Never deleted.** Deleting an appeal leaves its Campaign in place, with its members
and history; restoring the appeal restores the link. BarnCRM never deletes a Campaign it
did not just create. The one deletion is Sync all appeals undoing its own work: a Campaign it
created for an appeal whose Campaign ID it then could not store is deleted in the same run, so
the next run does not make a second one. A Campaign it cannot delete is named in a Warning.
A linked Campaign that has been deleted, or that the person saving cannot see, is reported
as R-CS5 describes and is not replaced: clearing the appeal's Campaign ID makes a new one.

**R-CS8 One appeal, one Campaign.** Campaign ID is unique, so a Campaign mirrors at most one
appeal, and a typed value that is not a Campaign's identifier is refused on save. It is also
the key the Opportunity mirror (X-01) will read to put a mirrored gift's Opportunity in the
Campaign of the gift's appeal, which is why it is an indexed external identifier.

### Salesforce implementation

- **Attribute on `Appeal__c`, shipped by Mirror** (in `packages/mirror`, not Giving):

| Attribute | API name | Type |
|---|---|---|
| Campaign ID | `Campaign_Id__c` | Text(18), unique, external ID, case sensitive |

- **Custom setting:** `Mirror_Settings__c`, hierarchy, protected, Mirror's own under
  ADR-0017.

| Attribute | API name | Type |
|---|---|---|
| Campaign Sync Enabled | `Campaign_Sync_Enabled__c` | Checkbox |

- **Automation:** `Automation_Registry__mdt` row `Campaign_Sync` on `Appeal__c`, order 50,
  enabled by default, handler `CampaignSyncTriggerHandler`, running before insert and before
  update. Its switch row is created by `MirrorPostInstall`, which Mirror gains for this.
- **Service:** `CampaignSyncService` (the copy), `CampaignSyncSelector` (appeal and Campaign
  reads, Campaign by dynamic query only), `CampaignSyncBatch` (R-CS6),
  `CampaignSyncController` and the `campaignSync` page reached from the Giving section of
  BarnCRM Settings. Permission set: `Campaign_Sync`.

## 29C. Opportunity Mirror

### Definition

A copy between gifts and standard Salesforce Opportunities, in one direction per org (plan
Section 4.12, feature X-01). **Gifts to Opportunities** copies each gift to an Opportunity, so
NPSP rollups, NPSP soft credits, Campaign totals and other apps that only know Opportunity see
the organization's giving. **Opportunities to Gifts** is for an org whose online giving tool
writes Opportunities: each won Opportunity becomes a gift. The org chooses one direction or
neither, never both, and a reconciliation page shows where the two sides disagree.

The Opportunity mirror is not an entity of its own. It is one attribute on Gift, held by
Mirror because Giving may not name Opportunity, two keys on Mirror Settings, and one
automation. There is no link object: a gift has at most one Opportunity, so the link is the
attribute, as it is for Campaign sync (Section 29B, ADR-0058).

### Attributes added to Gift

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Opportunity ID | text (18) | no | The record identifier of the Opportunity this gift is mirrored to or was made from. Written by the mirror; an administrator may type an existing Opportunity's identifier to link to it, or clear it. Unique, so two gifts never share one Opportunity. |

It is text rather than a lookup for the reason Section 29B gives: a lookup to Opportunity would
stop Mirror installing on an org without Opportunity (ADR-0013).

### Mirror Settings keys (v0.6)

| Key | Type | Default | Definition |
|---|---|---|---|
| `Opportunity_Mirror_Direction__c` | text | empty | `GiftsToOpportunities`, `OpportunitiesToGifts` or `Off`, shown as Gifts to Opportunities, Opportunities to Gifts and Off. Empty reads as Off (R-OM1). |
| `Opportunity_Mirror_Start__c` | datetime | empty | Opportunities to Gifts only: an Opportunity becomes a gift only when its Close Date is on or after this date, read as a date in the org's default time zone. Empty means no Opportunity becomes a gift (R-OM7). |
| `Opportunity_Mirror_Record_Types__c` | text | empty | Opportunities to Gifts only: the record types, by API name and separated by commas, whose won Opportunities become gifts. Empty means every record type (R-OM7). |
| `Opportunity_Mirror_Last_Run__c` | datetime | empty | Written by the runs, not by an administrator: when the last completed run started (R-OM8). |
| `Opportunity_Mirror_Last_Summary__c` | text | empty | Written by the runs: one sentence saying what the last completed run did (R-OM8). |

### Rules

**R-OM1 One direction, off until chosen.** The mirror does nothing until an administrator
chooses a direction in BarnCRM Settings, and one setting holds the choice, so two directions
can never be active at once. It also does nothing where the org has no Opportunity object, and
the Opportunity mirror page says so. The Gifts to Opportunities copy made on save is a
registered automation on Gift (`Opportunity_Mirror`), so it can be paused or switched off like
any other (ADR-0040); the setting is authoritative, and the runs of R-OM8 follow it alone.

**R-OM2 Which gifts are copied.** In Gifts to Opportunities, a gift gets an Opportunity when it
counts in the giving totals: Status Received, Refunded or Written off (ADR-0022). That includes
the negative gift recording a refund or a write-off, whose Opportunity has a negative Amount,
so an NPSP total nets exactly as the BarnCRM total does, and an in-kind gift, whose Amount
is zero (R-G12). A Pending or Cancelled gift gets no Opportunity. A copied gift that moves to
Cancelled keeps its Opportunity, moved to the lost stage; one that moves back to Pending keeps
its Opportunity at the stage it has (R-OM3). Neither is ever deleted.

**R-OM3 What is copied.** Amount to Amount; Gift Date to Close Date; Status to Stage, as the
won stage for a gift in the totals, the lost stage for a Cancelled gift, and the Opportunity's
own stage left as it is for a Pending gift, so linking an open Opportunity to a pledge never
closes it; Donor Account to Account, or Household when the donor is a person stored as a
contact (the BarnCRM household, which in an org running NPSP alongside is not the NPSP
household); the appeal's Campaign ID (Section 29B) to Campaign, when it names a Campaign and the
saver may read Campaigns and the appeal's Campaign ID (otherwise Campaign is left as it is,
never cleared); and the donor person as the primary Contact Role (Donor
Contact, or the person contact of a person account), with Role `Donor` when the org's role list
has it. The won stage is the org's active stage named `Closed Won` when it is a won stage, and
otherwise its first active won stage by order; the lost stage is found the same way from
`Closed Lost`. On creation only, the Opportunity is named from the donor and the gift date, and
takes the record type `Donation` when the org has one the saver may use; a Donation record type
whose sales process lacks the chosen stage makes the insert fail, which is logged as R-OM6
describes. Nothing else is written.
A copied field changed by hand on the Opportunity is overwritten the next time its gift changes
in one of these attributes.

**R-OM4 When it is copied.** In Gifts to Opportunities, when a gift is created, and when it is
saved with a change to an attribute in R-OM3 or to its Opportunity ID, or while it has no
Opportunity yet. The Opportunity is created or updated in the same save, before the gift is
written, so its identifier is stored with the gift and never in a second save. An Opportunity
whose values already match is not updated.

**R-OM5 In the saver's own access.** Opportunities and Contact Roles are written in user mode,
with the access of the person saving the gift. Opportunity is a standard object BarnCRM does
not own, so an elevated write (ADR-0021) is not available for it. The copy needs Opportunity
create and edit, and nothing else: the Opportunity ID is written onto the gift being saved by
the automation itself, so a person without the Opportunity Mirror permission set, who cannot
see that attribute, still has their gifts copied. Someone who cannot create and edit
Opportunities still saves the gift, which stays uncopied until a run of R-OM8 copies it. One
Warning says so, written when such a person creates or changes gifts in a save they made
themselves, at most once per transaction; none is written from a background job, since an import
of many chunks would repeat it for every chunk.

**R-OM6 A failure never refuses the gift.** An Opportunity the platform refuses (a validation
rule on Opportunity, a required field the org added, a closed stage the org's rules forbid) is
logged and the gift saves. Refusals are grouped: one Warning per distinct platform message per
transaction, or per run, giving the count and naming up to ten gifts, so a rule that refuses
every gift of a large import writes a handful of entries rather than one per gift; at most 50
distinct messages are kept, and any further ones are counted together. A copy starts only while
half of the transaction's queries and DML statements, and 40 percent of its CPU time, are still
unspent, since the org's own Opportunity automation (NPSP's rollups, say) runs inside the same
save and its cost cannot be measured in advance. A save that does not leave that room saves its
gifts uncopied, logs one Warning, and leaves them to the next run.

**R-OM7 Opportunities to Gifts.** Each won Opportunity whose Close Date is on or after the start
date (a date in the org's default time zone), whose record type is one of those listed when any
are, and that no gift names, becomes a gift: the donor is the primary Contact Role's contact (a
person account's account where people are accounts, R-G1), or else the Opportunity's Account;
Amount is the Opportunity's Amount, which must be above zero; Gift Date is its Close Date; Type
Other; Status Received; Appeal is the appeal whose Campaign ID is the Opportunity's Campaign;
and Opportunity ID is set in the same insert, so the unique attribute stops a second gift even
when two runs overlap. Giving's own rules then derive the household and the default allocation,
as for any gift. A gift made this way is never edited by the mirror afterwards, so a receipted
or posted gift is never touched (R-G4, R-G14); a later change to its Opportunity shows on the
reconciliation page instead. An Opportunity that cannot become a gift (no donor, an amount not
above zero, a gift rule such as a closed period) is logged as R-OM6 describes and tried again
by the next run; an Opportunity another run has just made a gift of is counted as unchanged.
Gifts are created in user mode, as the person who started the run.

**R-OM8 Runs.** The Opportunity mirror page offers **Run now** and a nightly schedule
(Schedule and Stop, the shape of ADR-0038, at 01:30). A run follows the chosen direction: in
Gifts to Opportunities it copies every gift in the totals that has no Opportunity yet, which is
how the gifts that existed before the mirror was turned on, and those saved by someone without
Opportunity access, are caught up, and every linked gift changed since the last completed run
started, which puts right a change whose copy was skipped; in Opportunities to Gifts it applies
R-OM7. Starting a run or the schedule needs the Manage BarnCRM Settings permission, and only
one run is in progress at a time. A run executes as the person who started or scheduled it, in
user mode. While automation is paused (ADR-0055) or the `Opportunity_Mirror` switch is off, a
run does nothing and writes one Info entry saying so, checked when it starts and before each
chunk, because Giving's own rules are paused too and a gift made then would never get its
household or allocation. A run that completes writes a summary at Info to the Error Log and
records its start time and summary on Mirror Settings, which the page shows. Health Check
warns when the nightly run is scheduled, the direction is chosen, and no run has completed for
more than two days (ADR-0055 point 7).

**R-OM9 Never deleted.** Deleting a gift leaves its Opportunity in place, and one Warning per
delete names the gifts and their Opportunities; the reconciliation page then shows each as a
won Opportunity without a gift, for the administrator to decide. In Opportunities to Gifts the
next run makes a new gift from such an Opportunity while it is still won, and the Warning says
so. BarnCRM never deletes an Opportunity it did not just create. The one deletion is a run undoing
its own work: an Opportunity it created for a gift whose Opportunity ID it then could not store
is deleted in the same run, so the next run does not make a second one, and one it cannot delete
is named in a Warning. A linked Opportunity that has been deleted, or that the person saving
cannot see, is logged as "deleted or not visible to you" and is not replaced: clearing the
gift's Opportunity ID makes a new one.

**R-OM10 One gift, one Opportunity.** Opportunity ID is unique, so an Opportunity mirrors at
most one gift, and a typed value that is not an Opportunity's identifier is refused on save. A
15 character identifier is stored in its 18 character form. Typing an existing Opportunity's
identifier links to it, and the gift's values then overwrite that Opportunity's copied fields.

**R-OM11 Reconciliation.** For a date range, the reconciliation page compares the gifts in the
totals dated in the range with the won Opportunities closed in the range, both as the person
viewing can see them, and shows each side's count and total and the differences: a gift with no
Opportunity; a gift whose Opportunity is deleted or not visible; a linked gift and Opportunity
whose amount, date or won state disagree; and a won Opportunity with no gift visible to the
viewer. It reads in user mode and writes nothing, and a viewer who cannot read Opportunity, its
Name, Amount and Close Date, or the gift's Opportunity ID is refused in words. A range holding
more than 10,000 gifts or 10,000 won Opportunities, or more than the transaction can read in
one go, is refused rather than shown in part, as the accounting export is (ADR-0051); the
reads stop at 10,001 records a side, so a very large range is refused rather than failing. In Gifts to
Opportunities it offers **Copy these gifts again**, a run over every gift in the range, linked
or not, which puts right what R-OM3 copies. In Opportunities to Gifts the differences are shown
only, because a gift is never edited from its Opportunity.

### Salesforce implementation

- **Attribute on `Gift__c`, shipped by Mirror** (in `packages/mirror`, not Giving):

| Attribute | API name | Type |
|---|---|---|
| Opportunity ID | `Opportunity_Id__c` | Text(18), unique, external ID, case sensitive |

- **Custom setting `Mirror_Settings__c`** (Section 29B) gains:

| Attribute | API name | Type |
|---|---|---|
| Opportunity Mirror Direction | `Opportunity_Mirror_Direction__c` | Text(40) |
| Opportunity Mirror Start | `Opportunity_Mirror_Start__c` | Date/Time |
| Opportunity Mirror Record Types | `Opportunity_Mirror_Record_Types__c` | Text(255) |
| Opportunity Mirror Last Run | `Opportunity_Mirror_Last_Run__c` | Date/Time |
| Opportunity Mirror Last Summary | `Opportunity_Mirror_Last_Summary__c` | Text(255) |

- **Automation:** `Automation_Registry__mdt` row `Opportunity_Mirror` on `Gift__c`, order 50,
  after `Gift_Core_Rules` derives the household, enabled by default, handler
  `OpportunityMirrorTriggerHandler`, running before insert, before update and after delete. Its
  switch row is created by `MirrorPostInstall`.
- **Service:** `MirrorSync` (the comparisons, limit headroom, identifier checks and grouped
  Warnings shared with Campaign sync), `OpportunityMirrorService` (Gifts to Opportunities),
  `OpportunityGiftService` (Opportunities to Gifts), `OpportunityMirrorSelector` (gift and
  Opportunity reads, Opportunity by dynamic query only), `OpportunityMirrorBatch` and
  `OpportunityMirrorSchedulable` (R-OM8), `OpportunityMirrorReconciliation` (R-OM11),
  `OpportunityMirrorController` and the `opportunityMirror` page reached from the Giving section
  of BarnCRM Settings, `MirrorSettingsWriter` (the runs' record of their last completed run)
  and `MirrorHealthCheckExtension` (the stale run finding, through the ADR-0057 seam).
  Permission set: `Opportunity_Mirror`, which also carries the custom permission
  `Use_Opportunity_Mirror`: the page's reads require it, and the console shows the page's row
  only to someone who has it (the Setting Definition's `Required_Permission__c`).
- **List view** `Gifts_And_Opportunities` on Gift, shipped by Mirror, where Opportunity ID is
  typed or cleared (R-OM10).

---

## 29D. Saved Query (and the query document)

### Definition

A named, reusable Find query (plan Section 4.9, feature C-34): which object, which columns,
which records, in what order and how many. Each belongs to the person who saved it, who may
share it, read only, with everyone who uses Find. A saved query holds no records and grants
access to none: whoever runs it sees what their own access allows.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text (80) | yes | The name the person gave it. |
| Object | text (255) | yes | API name of the object the query reads, copied from the document so the list can show and filter it without parsing JSON. |
| Query | long text | yes | The query document (R-SQ1). |
| Shared | boolean | no | True when everyone who uses Find can open it (R-SQ4). Default false. |
| Owner | reference(User) | yes | The person who saved it; only they can change, share or delete it. |

### Rules

**R-SQ1 Query document.** Find, saved queries and bulk update (C-35) share one document:

```
{
  "version": 1,
  "object": "Gift__c",
  "fields": ["Name", "Amount__c", "Donor_Contact__r.LastName"],
  "filter": { "version": 1, "conditions": [ ... ] },
  "orderBy": [{ "field": "Gift_Date__c", "direction": "DESC" }],
  "limit": 200
}
```

`fields` holds 1 to 20 field paths (relationship names, at most two lookups deep, the same
paths as R-R2); `filter` is an R-R2 filter document, or absent for every record; `orderBy`
holds at most one entry, `direction` ASC or DESC; `limit` is 1 to 2,000 rows shown. The
`version` key exists for the reason R-R2 gives.

Advanced Find (C-36) adds three optional keys, still at version 1, so every earlier document
reads unchanged:

```
  "related": [
    { "object": "Gift__c", "field": "Household__c", "has": false,
      "filter": { "version": 1, "conditions": [ ... ] } }
  ],
  "children": [
    { "relationship": "Contacts", "fields": ["Name", "Email"], "limit": 10 }
  ],
  "aggregate": { "function": "sum", "field": "Amount__c", "groupBy": "Status__c" }
```

`related` holds at most two related-records conditions (R-SQ8), `children` at most two
related record columns of 1 to 5 field paths and a `limit` of 1 to 10 (R-SQ8), and
`aggregate` the last summary chosen (R-SQ9): `function` is `count`, `sum`, `min` or `max`,
`field` is required except for `count`, and `groupBy` is optional.

**R-SQ2 Compiled, never typed.** `QueryCompiler` turns a document into SOQL using only names
taken from the running user's describe (`QueryFieldCatalog`): an object or field the user
cannot see is refused with a message naming it. Every filter value is a bind variable, a
relative date is a date literal written from an integer (R-R2), and the query runs through
`Database.queryWithBinds` with `AccessLevel.USER_MODE`, so CRUD, field-level security and
sharing apply. The SOQL shown to the admin is rendered from the same document with the values
written in, for display only; no SOQL text is ever accepted (ADR-0047).

**R-SQ3 Export.** An export reads the same document in pages ordered by Id (the document's
own order is ignored for paging), at most 2,000 rows a page, and stops at Export Row Limit
(`Find_Export_Row_Limit__c`). The file is CSV, UTF-8 with a byte-order mark, built in the
browser. The browser's stop is a convenience, not a control: the pages are served to anyone
with Find, in their own access. Only an export to Files (R-SQ12) enforces the limit on the
server.

**R-SQ12 Export to Files** (C-36; ADR-0115, `0115-find-export-to-files.md`). A Batch Apex job
run as the person reads the document's filter in Id order in user mode, at most Export Row
Limit rows (the query's LIMIT, so the server never reads more), with the document's own
columns and none of its `related` entries. It writes the rows as R-SQ3's CSV (same cell rules,
header of the column labels the page sent, values as the page shows them: dates `yyyy-MM-dd`,
date and times in ISO 8601 UTC) into `ContentVersion` files owned by the person, a new file
every 50,000 rows or about 4 million characters, each with the header row, titled
`<Object>-<date>-<job>-part-<n>`. Nothing else is stored: the page finds the files by the
person's own files whose title carries the job, and polls the job's `AsyncApexJob`. When the
job ends it tells the person (Q-04 `JobNotifier`), opening the first file. A query that fails
to compile is refused before the job starts. Permission: `Find_And_Export_Records` (R-SQ5).

**R-SQ4 Sharing.** Saved Query is Private. Sharing is an Apex managed share with the reason
Shared With Find Users, to the org's All Internal Users group, granting Read. Only the owner
can set or clear Shared, and the share row follows the flag. The share row is the one
system-mode write here, recorded in ADR-0076
(`0076-saved-queries-are-private-and-shared-by-apex-managed-sharing.md`); every other read
and write runs as the user.

**R-SQ5 Permission.** Every Find action requires the `Find_And_Export_Records` custom
permission, which opens the tool and grants no record access.

**R-SQ6 Data hygiene copies (C-28).** The Data Hygiene tab builds each check's query document
in code when it is counted or opened, from schema tokens and the org's membership mode; no
check is stored in the package. Its count is `SELECT COUNT()` over that same document, bound
and in user mode, capped at 2,000. "Open in Find" saves the document as a Saved Query owned by
the person, unshared, named "Data hygiene: " plus the check name, replacing the query of their
own saved query of that name if there is one. Nothing else about Saved Query changes
(ADR-0079, `0079-data-hygiene-checks-are-find-queries-built-at-request-time.md`).
Three person checks read standard Contact fields: no email, phone, mobile, mailing city or
postal code on a living person; Deceased with an email and Email Opt Out not ticked; and
Last Modified Date older than `Stale_Record_Years__c` years, the cut-off written into the
document when it is built.

**R-SQ7 Typed queries are read into the document in the browser.** A person may type a query
in a subset of SOQL (`SELECT`, `FROM`, `WHERE`, `ORDER BY`, `LIMIT`; the admin guide lists
what each accepts). The browser parses it into a query document and loads that document into
the builder; the server never receives the text. Every check of R-SQ2 then applies to the
document as to one built by hand, so there is one enforcement path (ADR-0078,
`0078-typed-find-queries-are-parsed-into-the-query-document.md`). Text the parser cannot map
onto the document, including anything R-R2 has no operator for, is refused before anything is
sent.

**R-SQ8 Related records.** A `related` entry names a child object and its lookup to the
query's object; both come from the running user's describe, the lookup must be readable,
filterable and point at the query's object, and the child object must be queryable. It
compiles to `Id IN (SELECT lookup FROM child WHERE ...)`, or `NOT IN` when `has` is false,
with the entry's R-R2 filter bound as any other (its own bind names), and is joined to the
document's filter with AND. A `children` entry names a child relationship of the query's
object, found in describe, and compiles to a subquery in the select list of the grid query
and the export pages, newest first by Created Date, at most `limit` rows per record. Counts,
bulk update selections and summaries ignore `children`.

**R-SQ9 Summaries.** A summary compiles the document's object, filter and `related` entries to
one aggregate query with `GROUP BY` the `groupBy` path (a groupable field, at most two lookups
deep), and runs it in user mode. `sum` takes a number field, `min` and `max` a number, date or
date and time field, each aggregatable. A summary is refused when more than 20,000 records
match (counted first, at most 20,001), so the count and the aggregate stay inside one
request's query rows, and shows at most 2,000 groups.

**R-SQ10 Editing results.** A person who holds `Bulk_Update_Records` as well (R-BU6) may edit
the results grid. A save sends at most 200 records, each an Id of the query's object and
values for fields that pass R-BU4; each value is typed as a bulk update's set value is, and an
empty value clears a field that may be empty. The records are read again as the person, a
field whose value is unchanged is not written, and the rest are saved with
`Database.update(records, false, AccessLevel.USER_MODE)`. Each save is one data job with
Operation Update (R-BU1), committed and complete when the request ends, whose definition
holds the query object, the record Ids as an R-R2 `in` condition, no changes and the count;
one commit journal page holds an Updated or Failed entry per record (R-IJ3), so the save is
listed and undone as a bulk update is (R-BU5).

**R-SQ11 Excel export.** An Excel export reads exactly the pages of R-SQ3 and writes, in the
browser, one sheet with a header row of column labels, numbers as numbers, dates and times as
dates, and everything else as text. The workbook is written by BarnCRM's own module, with no
third-party code (the same reasoning as ADR-0049).

### Salesforce implementation

- **Object:** `Saved_Query__c`, sharing model Private.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (80, standard) |
| Object | `Object_Name__c` | Text (255) |
| Query | `Query_JSON__c` | Long Text Area (131072) |
| Shared | `Shared__c` | Checkbox, default false |

- **Apex sharing reason:** `Shared_With_Find_Users__c` (Apex sharing reason API names end in `__c`).
- **Settings key:** `Find_Export_Row_Limit__c` (Section 12, v0.7 keys).
- **Services:** `QueryCompiler`, `QueryFieldCatalog`, `RollupFilterParser` (bound mode),
  `FindController`, `SavedQuerySharingWriter`; from C-36 `FindInlineEditService` (R-SQ10).
- **Browser modules:** `findQueryText` (R-SQ7), `xlsxWriter` (R-SQ11), `findCsv`.
- **Permission:** custom permission `Find_And_Export_Records`, in `BarnCRM_Admin` and in its own
  permission set `BarnCRM_Find_And_Export`, assignable alone.
- **UI:** the Find tab (app page `Find`, component `findRecords`), built on `filterBuilder`.
- **Data hygiene (R-SQ6):** services `DataHygieneService`, `DataHygieneController`; UI the Data quality section
  of the Org Optimizer tab (app page `Data_Hygiene`, shell `orgOptimizer`, component
  `dataHygieneConsole`).

---

## 29E. Bulk update

### Definition

Up to five changes to every record a Find query returns (plan Section 4.9, feature C-35): set
a field to a value, clear it, copy another field of the same record into it, or change its own
value with transform steps (C-37, R-BU7). A bulk update
adds no object of its own: it is a data job (Section 16) with Operation Update, journaled in
the import journal (Section 17A) and undone as an import is (ADR-0047; builder decisions in
ADR-0077, `0077-bulk-update-runs-as-the-user-from-a-find-query.md`).

### Rules

**R-BU1 A data job with no rows.** A bulk update is an `Import_Batch__c` with Operation Update,
no template, no file and no staged rows. Its Bulk Update Definition holds, as one document,
the query document (R-SQ1), the changes and the count the person confirmed:

```
{
  "version": 1,
  "query": { "version": 1, "object": "Contact", "fields": ["Name"], "filter": { ... } },
  "changes": [
    { "field": "MailingCity", "action": "set", "value": "Portland" },
    { "field": "Preferred_Email__c", "action": "copy", "source": "Work_Email__c" },
    { "field": "Title", "action": "clear" },
    { "field": "MailingStreet", "action": "transform",
      "transforms": [ { "op": "replace", "text": "St.", "replaceWith": "Street" } ] }
  ],
  "confirmedCount": 37
}
```

The record set comes only from the query document, compiled by `QueryCompiler` as the person
(R-SQ2); no SOQL text is accepted. The query's columns, order and row count are ignored: the
job reads the fields its changes need, in Id order.

**R-BU2 Counted, confirmed, and a ceiling.** The preview counts the matching records as the
person, in user mode, and shows the first five before and after. The start counts again and is
refused when none match, when more match than the person confirmed, or when more match than
`Bulk_Update_Run_Limit__c`. One request may read just under 50,000 rows, so the count reads at
most the run limit plus one, and the limit is held to 48,000. When the count starts, the job
stamps Committed By, Started At, Row Count (the count), Chunk Size (from `Bulk_Chunk_Size__c`)
and the Undo Deadline (R-IB7), and runs in Batch Apex, at most 200 records a chunk. A person
lists and undoes their own bulk jobs; a person with Manage BarnCRM Settings may also list and
undo everyone's.

**R-BU3 Only records that still match, as the person.** The job reads at most the confirmed
number of records, in Id order, in user mode. Each chunk reads its records again with the
query's filter, so a record changed since so that it no longer matches is left alone and
counted in the Run Log. Each record is saved with `Database.update(records, false,
AccessLevel.USER_MODE)`, so access, validation rules, duplicate rules and automation apply and
one refusal does not stop the rest. Rows Updated counts the records saved, Rows Matched those
that already held the new values (not saved), and Rows Rejected those the platform refused.
Each chunk writes one commit journal page (R-IJ1, R-IJ3).

**R-BU4 What a bulk update never writes.** A target field must be on the query's object (no
path to another record), editable by the person (`isUpdateable`, which excludes formula,
auto-number and system fields), of a type a value can be written to, and not one the package
keeps: the target of any Rollup Definition (active or not, read when the job is checked, so a
new rollup is protected without a code change), and the fields the household automation and
the package write (R-IT14's list: the household greetings, custom name, role and member count,
the primary contact and primary affiliation, the import tag `Created_By_Import_Batch__c`, the
sample data marks), and any field ending `Last_Calculated__c`. The object must be editable by
the person and not one of the package's bookkeeping objects (data jobs, import rows and
templates, the journal, the error log, settings and setting changes, automation settings,
rollup definitions, duplicate dismissals, saved queries) or an object a module protects through
`DataProtectionExtensions`, a custom setting, or a Salesforce setup object (users, groups,
profiles, roles, permission sets and their assignments, record types, the organization). The
protected list is one list, `DataProtectedFields`, shared with the one-object import (R-IT14). A
copy needs a compatible source: the same type; any text, email, phone, URL or picklist into a
text field; any number into a number field; a lookup into a lookup that can point at the same
kind of record. A value to set is typed for its field before the job starts; a restricted
picklist takes only its active values. Locks on another module's records (a posted gift, an
issued receipt) are not listed here: their triggers refuse the save, and the record is
journaled as Failed.

**R-BU5 Undo.** The undo is the import undo (R-IB8): counted and confirmed, once, within the
Undo Deadline. For a data job whose Operation is Update it runs the restore pass only, and it
restores any object its journal names that describe still finds, where an import restores
only people, households and organizations. A value is put back only where the record still
holds the value the bulk update wrote; anything else is journaled as not put back.

**R-BU6 Permission.** Every bulk update action requires the `Bulk_Update_Records` custom
permission and, because every bulk update starts from a Find query, `Find_And_Export_Records`
(R-SQ5). Neither grants record access.

**R-BU7 Change with steps.** A change whose action is `transform` carries `transforms`, a list
of steps in the transform document of R-IT15 (ADR-0081), and changes each record's own value.
For each record the job reads the target's value as text and applies the steps with
`DataTransform.apply`; an `append` step names fields of the same record by API name, each a
field of the query's object the person may read, read with the record and passed to the engine
by `DataTransform.key(apiName)`. The result is saved as the field's type: blank clears the
field (refused for that record when the field is required), a checkbox reads `true`, `yes` or
`1` as true, a number drops everything but digits, the point and the minus sign, a date reads
`YYYY-MM-DD`, and a text field takes the text as it is. A result the field cannot take (too
long, not a number or date, a value a restricted picklist lacks) is not shortened or guessed:
that record is journaled as Failed with the reason, and the rest still save. A change with
steps is checked when it is previewed and when the job starts: it is refused when it has no
step, when `DataTransform.problems` names any, when an `append` names a field the person may
not read, or when the target is a lookup. Comparison is exact (`equals`), so a step that only
changes capitals still writes and journals the record. The preview shows each sampled record's
own result, and the reason in place of a result the field cannot take.

### Bulk delete (C-37)

Deletes every record a Find query returns (plan Section 4.9; owner decision 2026-09-23; builder
decisions in ADR-0091, `0091-bulk-delete-from-a-find-query-with-undelete.md`). Like a bulk
update, it is a data job with no rows of its own.

**R-BD1 A data job with Operation Delete.** A bulk delete is an `Import_Batch__c` with
Operation Delete, no template, no file and no staged rows. Its Bulk Update Definition holds the
query document and the confirmed count: `{ "version": 1, "query": { ... }, "confirmedCount":
112 }`. The record set comes only from the query document, compiled by `QueryCompiler` as the
person (R-SQ2).

**R-BD2 Counted, confirmed, and a ceiling.** As R-BU2, with `Bulk_Delete_Run_Limit__c` (default
10,000, held between 1 and 48,000). The preview also names, from describe, the kinds of child
record the platform deletes with each record (child relationships marked cascade delete whose
object the person may read). The Undo Deadline is stamped at the start as the earlier of the
import undo window (R-IB7) and 15 days, the time the platform keeps a deleted record in the
Recycle Bin.

**R-BD3 Only records that still match, as the person.** The job reads at most the confirmed
number of records, in Id order, in user mode. Each chunk reads its records again with the
query's filter; a record that no longer matches is left alone and counted in the Run Log. Each
chunk deletes with `Database.delete(records, false, AccessLevel.USER_MODE)`, so access,
automation and locks apply and one refusal does not stop the rest. Rows Deleted counts the
records deleted and Rows Rejected those the platform refused. Each chunk writes one commit
journal page: a Deleted entry for each deleted record and a Failed entry for each refusal
(R-IJ2, R-IJ3). Child records the platform deleted with a parent are not journaled: they come
back when their parent is undeleted.

**R-BD4 What a bulk delete never deletes.** The object must pass `DataProtectedFields`'
object rule (R-IT14: not the package's bookkeeping, a module's protected object, household
membership rows, a custom setting, a setup object, or an object that is never loaded), and
describe must say the person may delete its records and that the platform can undelete them
(`isDeletable`, `isUndeletable`). Locks on another module's records refuse the delete through
their own triggers, and the record is journaled as Failed.

**R-BD5 Undo is undelete.** Counted and confirmed, once, within the Undo Deadline, with the
same guards as the import undo (R-IB8: Undoing latches the job, and an undo that stops can be
run again). The undo reads the commit journal pages, one page a chunk, and for each Deleted
entry finds the record in the Recycle Bin (read with `ALL ROWS` in system mode, by the Id the
journal holds): a record still deleted is undeleted with `Database.undelete(ids, false,
AccessLevel.USER_MODE)`; a record no longer in the Recycle Bin is counted as purged; a record
somebody already restored is left alone. Each record not brought back is journaled as
NotRestored with the reason, and the Run Log says how many were restored, purged and refused.

**R-BD6 Permission.** Every bulk delete action requires the `Bulk_Delete_Records` custom
permission and `Find_And_Export_Records`. `Bulk_Delete_Records` is in its own permission set
only, `BarnCRM_Bulk_Delete`, and in no role. Neither grants record access. What reads no query
needs only `Bulk_Delete_Records`: the list of jobs, a job's progress, the undo, and a delete by
file (R-BD7), which needs import access instead of Find.

**R-BD7 Delete by file** (ADR-0114, `0114-delete-by-file.md`). A one-object template (R-IT12)
whose Load Operation is Delete by record Id names, in each row's `Record.Id`, a record to
delete; every other column is ignored. The operation is offered only to a person holding
`Bulk_Delete_Records`, for an object R-BD4 allows (people included), and the template is refused
without them.

- **Dry run.** The file is staged and dry run as any import. A row is Matched, with the record
  in its Resulting Record, when its ID is a valid ID of the target object naming a record the
  person can see in user mode; otherwise it is Rejected, as is a row naming the same record as
  an earlier row (R-IT12's Processor Key digest). Nothing is deleted.
- **Confirmed start.** The import commit is replaced by a start that takes the confirmed
  count: refused unless the dry run completed, the count typed equals the Matched rows, and
  that count is within the run limit (R-BD2). The preview names the cascade kinds as R-BD2.
  The start turns the same `Import_Batch__c` into a bulk delete: Operation Delete, a definition
  `{ "version": 1, "source": "file", "object": "...", "confirmedCount": 112 }`, the Undo
  Deadline of R-BD2, so it leaves the import history and is listed, undone and refused by the
  import undo as any bulk delete (R-BD5).
- **The job.** `BulkDeleteBatch` reads at most the confirmed number of the batch's Matched
  rows in system mode (they are bookkeeping, ADR-0021), and each chunk reads their Resulting
  Records again in user mode: a record gone or hidden since the dry run is counted as no longer
  matching. Deleting, journaling, Rows Deleted and the undo are as R-BD3 and R-BD5.

**R-BD8 Download these records first.** Before the count is typed, the panel offers a download
of every record the delete would delete: the query's matches, or a delete by file's Matched
rows' records. The browser reads them page by page, 200 records a page in Id order after the
last Id read, each page read in user mode with every field the person may read (describe's
`isAccessible`; compound address and location fields and binary fields are left out, an
address's parts are kept), Id first. It writes them as CSV with Find's export rules (R-SQ3).
Nothing is written on the server and nothing is deleted; the download is optional and does not
change the count to type. It needs what the delete's preview needs (R-BD6). Child records the
platform deletes with a parent are not in it.

### Salesforce implementation

- **Objects:** none of its own; `Import_Batch__c` (`Operation__c`, `Operation_JSON__c`,
  `Rows_Deleted__c`) and `Import_Journal__c` (Sections 16 and 17A).
- **Settings keys:** `Bulk_Update_Run_Limit__c` and `Bulk_Delete_Run_Limit__c` (Section 12, v0.7
  keys).
- **Bulk delete services:** `BulkDeleteService` (check, preview, start, undo),
  `BulkDeleteBatch` (the job), `BulkDeleteUndoBatch` (the undelete), `BulkDeleteController`;
  component `bulkDelete`, opened from Find's results, and `dataJobHistory` on the Bulk Update
  tab. Custom permission `Bulk_Delete_Records`, permission set `BarnCRM_Bulk_Delete`.
- **Services:** `BulkUpdateFields` (which fields and objects can be written, from the shared
  `DataProtectedFields` list, and how a value or a copy is typed), `BulkUpdateService` (check, preview, start, recent jobs),
  `BulkUpdateBatch` (the job), `BulkUpdateController`; `QueryCompiler` gains the count and the
  chunk read; `ImportUndoService` and `ImportUndoBatch` handle the Update operation.
- **Permission:** custom permission `Bulk_Update_Records`, in `BarnCRM_Admin` and in its own
  permission set `BarnCRM_Bulk_Update`, assigned beside `BarnCRM_Find_And_Export`.
- **UI:** component `bulkUpdate`, opened from Find's results with the query, and on the Bulk
  Update tab (app page `Bulk_Update`) listing recent bulk updates with their progress and undo.

---

## 29F. Field Utilization Snapshot

### Definition

One count of how many records hold a value in one field, for one object and one record type,
counted in Org Optimizer's Field utilization section and saved there with "Save these counts"
(plan Section 6.1 item 10, ADR-0086 `0086-field-utilization-ships-in-core.md`, ADR-0101
`0101-field-utilization-on-demand.md`). Every row of one save carries the same Taken At, so a
saved count is the set of rows sharing it, and a trend is the same object, field and record type
across saves. Neutral: it names no nonprofit concept and is in Core.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The snapshot's identifier, assigned automatically. |
| Object Name | text | yes | The API name of the object counted, as describe gives it. |
| Field Name | text | yes | The API name of the field counted, as describe gives it. |
| Field Label | text | yes | The field's label when it was counted, for reports. |
| Record Type | text | no | The developer name of the record type the count is for. Empty when the object has no record types, or for its records with none. |
| Filled Count | number | yes | Records in this group with a value in the field. |
| Record Count | number | yes | Records in this group that were looked at. |
| Fill Rate | percent | computed | Filled Count divided by Record Count. |
| Sampled | boolean | yes | True when the count covers a sample of recent records rather than all of them. |
| Taken At | datetime | yes | When the counts were saved. |

### Rules

**R-FU1 Describe only.** The object picker lists the objects Find offers (accessible, queryable,
not a custom setting, deprecated, share, history, feed, change event, metadata, event, external
or big object), minus this object; every call checks the chosen name against the global describe
again. Fields come from that object's describe. No typed text reaches a query.
**R-FU2 What is counted.** A field is counted when the runner can read it and either create or
edit it, and it is not a formula, roll-up, auto number, checkbox, compound (address or
location) or non-nillable field.
**R-FU3 User mode.** Every count, read and write is in user mode, so a count covers the records
the person on the page can see. Written into the page and the admin guide.
**R-FU4 Count, else sample.** A filterable field is counted with one `COUNT(field)` query
grouped by record type, one query row per group. A field that is not filterable, or whose
count is refused, is counted on the 200 most recently modified records and its rows are
Sampled. A field whose sample also fails is listed on the page as not counted.
**R-FU5 Size limit.** An object holding more than 1,000,000 records is not counted; the page
says so.
**R-FU6 Groups with no records are not stored.** A record type with no records produces no row.
**R-FU7 On demand, saved by choice.** Counting runs synchronously from the page, 40 fields per
call (10 when the object holds more than 100,000 records); each call reads the record totals
again. Nothing is stored until the person chooses "Save these counts"; the save checks each
row's object, field and record type against describe and caps Filled Count at Record Count.
Rows are never edited and no job deletes them; old rows are cleared with Bulk delete or any
standard delete.
**R-FU8 Previous count shown.** The page shows the object's latest saved count next to the
current one, with the change in percentage points.

### Salesforce implementation

- **Object** `Field_Utilization_Snapshot__c`, auto number Name `FUS-{000000}`, public read only
  sharing, reports on, no activities, feeds or history. Only `BarnCRM_Admin` is granted it:
  Read, Create, Delete, View All and Modify All (the last so an administrator's user-mode
  delete reaches another administrator's rows).

| Attribute | API name | Type | Notes |
|---|---|---|---|
| Object Name | `Object_Name__c` | Text(80) | |
| Field Name | `Field_Name__c` | Text(80) | |
| Field Label | `Field_Label__c` | Text(255) | |
| Record Type | `Record_Type__c` | Text(80) | Developer name. |
| Filled Count | `Filled_Count__c` | Number(18, 0) | |
| Record Count | `Record_Count__c` | Number(18, 0) | |
| Fill Rate | `Fill_Rate__c` | Formula (Percent) | Blank when Record Count is 0. |
| Sampled | `Sampled__c` | Checkbox | Default false. |
| Taken At | `Taken_At__c` | DateTime | |

- **Service:** `FieldUtilizationService` (plan, count, save), `FieldUtilizationSelector`
  (latest saved count), `FieldUtilizationController` (every method requires
  `Manage_BarnCRM_Settings`). The page is the `fieldUtilization` component, embedded in Org
  Optimizer, its only host (no app page or tab of its own).

---

---

## 29G. Interaction Note

### Definition

A note a staff member writes about a conversation, a meeting or a visit with a person or an
account: when it happened, what kind of interaction it was, who took part and what was said
(plan Section 5.1, feature C-39). It is the lightweight version of a contact report.

An interaction note is not an entity of its own. It is a completed platform activity (a Task)
logged through the packaged action "Log an interaction". The package adds no object, no field
on Task or Activity, and no automation on Task (ADR-0089,
`0089-interaction-notes-are-completed-tasks.md`).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Subject | text | yes | A short line that says what the interaction was about. |
| Date | date | yes (defaults today) | The day the interaction happened, which may be earlier than the day the note is written. |
| Kind | picklist (the org's Task Type values) | no (defaults Meeting) | What kind of interaction it was: a meeting, a call, a visit, or another value the org keeps. |
| Notes | long text | no | What was said and what was agreed. |
| Staff member | reference(User) | yes (defaults the person logging it) | Who held the interaction. |
| People | reference(Contact), one or several | no | The people who took part. Several only where the org relates multiple contacts to tasks. |
| Account | reference(Account) | no | The household or organization the note is about. Set from the account the note is logged on, or derived by the platform from the person's account. |
| Status | picklist | yes (always Completed) | Completed, so the note is history rather than a to-do. |

### Relationships

- **Interaction Note to Contact**, many to one (many to many where the org relates multiple
  contacts to tasks), through `WhoId`.
- **Interaction Note to Account**, many to one, through `WhatId` when logged on an account and
  through the platform-derived `AccountId` when logged on a person.

### Rules

**R-IN1 An interaction note is history.** It is created Completed and dated the day the
interaction happened. Next steps are an open task, not a field on the note.

**R-IN2 Visibility follows the record.** A note is readable by anyone who can see the person or
the account it is on. There is no per-note confidentiality (ADR-0089, owner question).

**R-IN3 Where it shows.** A note logged on a person shows on the person's timeline and on the
timeline of the account their contact points at: the household in contact mode, the employer
or nothing in junction mode. A note logged on an account shows on that account.

**R-IN4 No packaged schema on activities.** Nothing in the package reads, writes or extends
Task for this feature beyond the action that creates it.

### Salesforce implementation

- **Object:** Task (standard), Status Completed.
- **Standard fields used:** `Subject`, `ActivityDate` (Date), `Type` (Kind), `Description`
  (Notes), `OwnerId` (Staff member), `WhoId` (People), `WhatId` and `AccountId` (Account),
  `Status`.
- **Quick actions:** `Contact.Log_Interaction` (Create on Task, parent field Who) and
  `Account.Log_Interaction` (Create on Task, parent field What), labelled "Log an interaction".
  Predefined values: Status Completed, ActivityDate `TODAY()`, Type Meeting.
- **Placement:** Dynamic Actions on `Contact_Record_Page` (Edit, Log an interaction, Delete)
  and `Account_Record_Page` (after Edit, for every record type), and the action list of the
  Account fallback layout (ADR-0043).

---

## 29H. Erasure

### Definition

The record that a person was erased at their request (the right to be forgotten): who erased
them, when, under which request, and what changed. It never holds an erased value
(ADR-0110, `0110-erase-a-person-anonymizes-in-place.md`).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The erasure's identifier, assigned automatically. |
| Contact | reference(Contact) | conditional | The anonymized person, where people are Contacts. |
| Person Account | reference(Organization) | conditional | The anonymized person, where people are person Accounts. |
| Erased Record Id | text | yes | The same person's record Id as text, kept if the record is deleted later. |
| Request Reference | text | no | The organization's own reference for the request, for example a ticket number. Never a name or an address. |
| Details | long text | yes | Each record the erasure changed, by object and Id, with what was done and the labels of the fields emptied. |

### Relationships

- **Erasure to the person**, many to one, to exactly one of Contact or Person Account (Section 4
  "Person references").

### Rules

**R-ER1 Anonymize in place.** Erasing a person empties every field of their record that can be
empty, except the fields `DataProtectedFields` protects, owner, record type, currency, the
Individual link, and the fields an installed module keeps (`PersonErasureExtension`). The name
becomes "Erased person"; opt-out flags are set and other checkboxes go back to their default. The
record is never deleted, so gifts and totals keep pointing at it.

**R-ER2 Contact points and connections.** The person's own addresses are deleted. Relationships
on either side and affiliations are ended (End Date today, or the Start Date if later) and lose
their description; an affiliation also loses its role and primary flag.

**R-ER3 Households.** The person leaves every household: the contact's account is emptied in
contact mode, and each current membership is ended in junction mode
(`HouseholdService.endMembershipsFor`). Upkeep then recounts, renames and tidies away as on any
move (R-H11, R-H12). A household left empty and kept is anonymized as in R-ER1, named "Erased
household", with Custom Name on and its addresses deleted. Where the org stores people as
accounts, the person account fields a household (a business account) cannot carry are left alone.

**R-ER4 Platform privacy records.** The linked Individual, where the org has one, is emptied as
in R-ER1 and marked Forget this Individual. Field history of the person and the Individual is
deleted after the erasure commits where the user may delete it. Records the erasure deletes are
emptied from the Recycle Bin.

**R-ER5 As the user, all or nothing.** What to change is read in system mode; every change is
made in user mode. A record or a field holding a value that the user cannot edit refuses the
erasure before anything changes, and any refusal during the run takes everything back. The
Erasure record is written in system mode (ADR-0021) and no packaged permission set may edit or
delete it.

**R-ER6 Preview.** The preview runs the erasure inside a savepoint and rolls it back, so it lists
exactly what the erasure would change.

**R-ER7 Who may erase.** Only a user with the custom permission `Erase_People`, who types the
person's current name to confirm. A person with an Erasure record is not erased again.

**R-ER8 Modules decide about their own records.** Each installed module implementing
`PersonErasureExtension` changes its own records in the same transaction and reports what it
changed and kept. A module that is installed but cannot answer refuses the erasure.

**R-ER9 An erased person is not an orphan.** A person an Erasure record names is left out of
"people with no household" in Health Check and data hygiene, in both membership modes.

**R-ER10 Activities and files are listed, not erased.** Tasks and events naming the person (by
WhoId, WhatId, TaskRelation or EventRelation) and files linked to the person
(ContentDocumentLink) are counted and listed as kept, for the admin to delete by hand.

### Salesforce implementation

- **Object:** `Erasure__c`, auto-number Name with format `ER-{000000}`, sharing Read, no tab.

| Attribute | API name | Type |
|---|---|---|
| Contact | `Contact__c` | Lookup to Contact (clears on delete) |
| Person Account | `Person_Account__c` | Lookup to Account (clears on delete) |
| Erased Record Id | `Erased_Record_Id__c` | Text(18) |
| Request Reference | `Request_Reference__c` | Text(80) |
| Details | `Details__c` | Long Text Area(131072) |

- **Permission:** custom permission `Erase_People`, in permission set `BarnCRM_Erase_People`
  only (in no permission set group). `BarnCRM_Admin` and `BarnCRM_Erase_People` read
  `Erasure__c`; nothing grants edit or delete.
- **Service:** `PersonErasure`, `PersonErasureExtension`, `PersonErasureExtensions`,
  `PersonErasureHistoryCleanup`.

---

# Part G: Volunteers entities

Built by the v0.8 iteration in the BarnCRM Volunteers module (`packages/volunteers`, module key
`Volunteers`, Nonprofit Edition only), which depends on Core and BarnCRM Rollup Builder
(ADR-0127). Sections 29I to 29O cover V-01 to V-03: who
volunteers, what work there is, when it happens, who is booked, the hours actually given, and
the totals. There is no Volunteer entity: a volunteer is a person the organization already
knows, so the profile is a set of person attributes the module ships on Contact and Account.
Every attribute here, the person attributes included, is shipped by Volunteers, never by Core.

## 29I. Volunteer profile

### Definition

The attributes that make a person a volunteer (feature V-01). They are person attributes, so
they exist on Contact and on Account under the same API names (Section 4, "Person
references").

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Volunteer Status | picklist(Prospective, Active, Inactive) | no | Where this person stands with the volunteer program. Empty means not a volunteer, which is most people. |
| Volunteer Since | date | no | The day this person started volunteering, when the organization wants to state it rather than infer it from the first hours. |
| Emergency Contact Name | text | no | Who to call if something happens to this person on site. |
| Emergency Contact Phone | text | no | The number to call for that person. |
| Availability Days | multi-select picklist(Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday) | no | The days this person is usually free to volunteer (V-04). |
| Availability Times | multi-select picklist(Morning, Afternoon, Evening) | no | The parts of the day this person is usually free (V-04). |

The rollup targets that carry a person's hours are on the same two objects and are listed in
Section 29O.

### Relationships

- A person reaches their hours through Volunteer Hours (29M) and their bookings through
  Volunteer Sign-up (29L), each naming them with a Contact and Account pair.

### Rules

**R-VP1 Volunteer Status is a statement, not a calculation.** The module never writes it. An
organization that wants "active means hours in the last year" builds a report or list view on
the hours totals, because every organization draws that line differently.

**R-VP2 The emergency contact is free text.** Not a reference to another person: the person to
call is very often not in the database.

**R-VP3 Nothing here is required to record hours.** Hours can be entered for any person,
whether or not Volunteer Status is set, so a walk-in is recorded in one save.

### Salesforce implementation

- **Custom fields on Contact, and on Account with the same API names** (shipped by
  Volunteers):

| Attribute | API name | Type |
|---|---|---|
| Volunteer Status | `Volunteer_Status__c` | Picklist: Prospective, Active, Inactive |
| Volunteer Since | `Volunteer_Since__c` | Date |
| Emergency Contact Name | `Emergency_Contact_Name__c` | Text(100) |
| Emergency Contact Phone | `Emergency_Contact_Phone__c` | Phone |
| Availability Days | `Availability_Days__c` | Multi-Select Picklist, 7 values |
| Availability Times | `Availability_Times__c` | Multi-Select Picklist, 3 values |

---

## 29J. Volunteer Job

### Definition

A piece of work the organization needs volunteers for: sorting the food pantry, driving the
van, staffing the front desk (V-01). It is the durable thing; a shift (29K) is one dated
occurrence of it.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the job is called, in the words the coordinator uses when asking for help. |
| Description | long text | no | What the volunteer will be doing, and anything to know before arriving. |
| Location | text | no | Where the work happens, when it is the same for every shift. |
| Coordinator | reference(User) | no | The staff member who runs this job. |
| Active | boolean | yes (defaults true) | Whether this job is offered when a new shift is scheduled. |
| Total Hours | decimal | computed | Approved hours ever recorded against this job. |
| Last Volunteer Date | date | computed | The most recent day anybody worked this job. |
| Rollups Last Calculated | datetime | computed | When BarnCRM last worked out this job's totals. |

### Relationships

- **Volunteer Job to Volunteer Shift**, one to many; the shift is a detail of the job.
- **Volunteer Job to Volunteer Hours**, one to many, so hours can be recorded against a job
  with no shift.
- Coordinator is a User, not a person pair: a coordinator is staff who logs in.

### Rules

**R-VJ1 A used job is deactivated, not deleted.** A job with shifts or hours is not deleted;
the message says to clear Active instead (as R-F2 for a fund).

**R-VJ2 An inactive job keeps its history.** Clearing Active stops it being offered on a new
shift and changes nothing already recorded, including its totals.

### Salesforce implementation

- **Object:** `Volunteer_Job__c`, name field Text, label Job Name.

| Attribute | API name | Type |
|---|---|---|
| Description | `Description__c` | Long Text Area(32768) |
| Location | `Location__c` | Text(255) |
| Coordinator | `Coordinator__c` | Lookup to User |
| Active | `Active__c` | Checkbox, default true |
| Total Hours | `Total_Hours__c` | Number(10, 2) |
| Last Volunteer Date | `Last_Volunteer_Date__c` | Date |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Service:** `VolunteerJobTriggerHandler`, `VolunteerJobSelector`.

---

## 29K. Volunteer Shift

### Definition

One dated occurrence of a job: the Saturday pantry sort on 14 March, nine until noon, four
volunteers wanted (V-01). It is what a volunteer signs up for and what a coordinator counts
heads on.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What this shift is called. BarnCRM writes it from the job and the start when it is left empty. |
| Volunteer Job | reference(Volunteer Job) | yes | The work being done. A shift is a detail of its job. |
| Start Time | datetime | yes | When the shift starts. |
| End Time | datetime | yes | When the shift ends. |
| Volunteers Needed | integer | yes (defaults 1) | How many people the coordinator wants on this shift. |
| Location | text | no | Where this shift happens, when it differs from the job's usual place. |
| Status | picklist(Open, Cancelled, Completed) | yes (defaults Open) | Where the shift stands. A cancelled shift is kept, so the people booked on it can still be found. |
| Shift Schedule | reference(Shift Schedule) | no | The recurring schedule that created this shift (V-07), empty for a shift created by hand. |
| Slots Filled | integer | computed | How many people are signed up and have not cancelled. |
| Slots Remaining | integer | computed | Volunteers Needed less Slots Filled. Negative when more came than were asked for, which is information, not an error. |
| Total Hours | decimal | computed | Approved hours recorded against this shift. |
| Rollups Last Calculated | datetime | computed | When BarnCRM last worked out this shift's totals. |

### Relationships

- **Volunteer Shift to Volunteer Job**, many to one, as a detail of the job.
- **Volunteer Shift to Volunteer Sign-up**, one to many; the sign-up is a detail of the shift.
- **Volunteer Shift to Volunteer Hours**, one to many, optional on the hours side.

### Rules

**R-VS1 A shift belongs to a job.** Master-detail, so who can see a shift is decided by who
can see its job: shifts are the schedule, not private data.

**R-VS2 A shift names itself.** A shift saved without a name gets one from its job and start,
for example "Food pantry sort: 14 Mar 2026, 9:00 AM". A typed name is never overwritten.

**R-VS3 A shift ends after it starts.** A validation rule, so it holds with automation off.

**R-VS4 Volunteers Needed is a target, not a limit.** A sign-up is never refused because a
shift is full; Slots Remaining goes negative and the coordinator sees it.

**R-VS5 Cancelling is not deleting.** Status Cancelled keeps the shift and its sign-ups.
Deleting a shift takes its sign-ups with it and leaves its hours, with the job, in place.

### Salesforce implementation

- **Object:** `Volunteer_Shift__c`, name field Text, label Shift Name, sharing Controlled By
  Parent.

| Attribute | API name | Type |
|---|---|---|
| Volunteer Job | `Volunteer_Job__c` | Master-Detail to `Volunteer_Job__c`, relationship name Shifts |
| Start Time | `Start_Time__c` | DateTime, required |
| End Time | `End_Time__c` | DateTime, required |
| Volunteers Needed | `Volunteers_Needed__c` | Number(4, 0), default 1 |
| Location | `Location__c` | Text(255) |
| Status | `Status__c` | Picklist: Open, Cancelled, Completed |
| Shift Schedule | `Shift_Schedule__c` | Lookup to `Shift_Schedule__c` (clears on delete) |
| Slots Filled | `Slots_Filled__c` | Number(4, 0) |
| Slots Remaining | `Slots_Remaining__c` | Formula (Number): `Volunteers_Needed__c` less `Slots_Filled__c` |
| Total Hours | `Total_Hours__c` | Number(10, 2) |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Validation rules:** `End_After_Start` (R-VS3).
- **Service:** `VolunteerShiftTriggerHandler`, `VolunteerShiftSelector`.

---

## 29L. Volunteer Sign-up

### Definition

A person booked onto a shift (V-02). It is the intention; Volunteer Hours (29M) is the record
of what happened. Staff enter sign-ups; there is no portal (V-09 is out of scope).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | An auto number: a sign-up is identified by its person and shift. |
| Volunteer Shift | reference(Volunteer Shift) | yes | The shift the person is booked onto. A sign-up is a detail of the shift. |
| Contact | reference(Contact) | conditional | The person, where people are Contacts. |
| Account | reference(Account) | conditional | The person, where people are person Accounts. |
| Status | picklist(Signed up, Confirmed, Attended, No show, Cancelled) | yes (defaults Signed up) | Where this booking stands, up to whether the person turned up. |
| Notes | text | no | Anything the coordinator needs to remember about this booking. |

### Relationships

- **Volunteer Sign-up to Volunteer Shift**, many to one, as a detail of the shift.
- **Volunteer Sign-up to a person**, through the Contact and Account pair (Section 4).
- **Volunteer Sign-up to Volunteer Hours**, one to at most one, when attendance created the
  hours (R-VU3).

### Rules

**R-VU1 Exactly one person.** Contact or Account, never both, never neither (validation rule).

**R-VU2 One sign-up per person per shift.** A second one for the same person on the same
shift is refused, naming the shift: it is always a mistake and would double the filled count.

**R-VU3 Marking attendance can write the hours.** When Attendance Creates Hours is on (29N),
moving a sign-up to Attended creates one Volunteer Hours entry for that person, dated the
shift's start, for the shift's length, against the shift and its job, naming the sign-up.
Marking attendance again creates no second entry, and moving the sign-up away from Attended
deletes nothing: removing hours a coordinator may have approved is left to a person.

**R-VU4 A cancelled sign-up stops counting.** Slots Filled counts sign-ups whose Status is not
Cancelled, so someone who drops out frees the place without the booking being deleted.

### Salesforce implementation

- **Object:** `Volunteer_Signup__c`, name field AutoNumber `VS-{000000}`, sharing Controlled
  By Parent.

| Attribute | API name | Type |
|---|---|---|
| Volunteer Shift | `Volunteer_Shift__c` | Master-Detail to `Volunteer_Shift__c`, relationship name Signups |
| Contact | `Contact__c` | Lookup to Contact |
| Account | `Account__c` | Lookup to Account |
| Status | `Status__c` | Picklist: Signed up, Confirmed, Attended, No show, Cancelled |
| Notes | `Notes__c` | Text Area(255) |

- **Validation rules:** `Exactly_One_Person` (R-VU1).
- **Service:** `VolunteerSignupService`, `VolunteerSignupTriggerHandler`,
  `VolunteerSignupSelector`.

---

## 29M. Volunteer Hours

### Definition

Time a person actually gave, entered by staff and approved by a coordinator (V-02). Every
volunteer number in the product is calculated from it, which is why approval is part of the
record.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | An auto number: an entry is identified by its person, date and job. |
| Contact | reference(Contact) | conditional | The person who gave the time, where people are Contacts. |
| Account | reference(Account) | conditional | The person who gave the time, where people are person Accounts. |
| Household | reference(Household) | computed | The household credited with this time. BarnCRM fills it in from the person. |
| Volunteer Job | reference(Volunteer Job) | conditional | The work that was done. Filled from the shift when a shift is named. |
| Volunteer Shift | reference(Volunteer Shift) | no | The shift the time was given on, when it was a scheduled shift. |
| Volunteer Sign-up | reference(Volunteer Sign-up) | no | The booking these hours were created from, when attendance created them. |
| Date Worked | date | yes | The day the time was given. |
| Hours | decimal | yes | How many hours, to two decimal places. |
| Status | picklist(Submitted, Approved, Rejected) | yes (defaults Submitted) | Where this entry stands with the coordinator. |
| Approved By | reference(User) | computed | Who approved or rejected the entry. |
| Approved Date | datetime | computed | When they did it. |
| Rejection Reason | text | conditional | Why the entry was rejected; required when rejecting. |
| Notes | text | no | What the person did, when it is worth recording. |

### Relationships

- **Volunteer Hours to a person**, through the Contact and Account pair (Section 4).
- **Volunteer Hours to Household**, many to one, written by the module, never typed (R-VG2),
  the same shape as Gift so a household total is a rollup over one reference.
- **Volunteer Hours to Volunteer Job, Volunteer Shift and Volunteer Sign-up**, many to one,
  plain lookups, so hours survive a shift or sign-up being deleted.

### Rules

**R-VG1 Exactly one person.** Contact or Account, never both, never neither (validation rule).

**R-VG2 The household is derived.** From the person's household through `HouseholdService`,
in both membership modes, as R-G2 does for a gift: set when the entry is saved, recomputed
only when its person changes, empty when the person has no household. Hours stay with the
household they were given in when the person later moves (ADR-0071).

**R-VG3 An entry names a job.** A validation rule requires the job or the shift; the module
fills the job from the shift, so a shift deleted later leaves the hours with their job.

**R-VG4 Hours are greater than zero** (validation rule): zero hours is a mistake or an
attendance record, and attendance is a sign-up.

**R-VG5 Approval is a status moved by a service.** Status, Approved By and Approved Date are
moved only by `VolunteerHoursService`, which refuses a user without the custom permission
`Manage_Volunteers`; a Status change made any other way is refused. It is not a Salesforce
approval process (ADR-0127, decision 4).

**R-VG6 Only approved hours count.** Every rollup in 29O filters on Status equals Approved.
With Hours Require Approval off (29N), entries are created Approved, by the saving user at the
save time, and count at once.

**R-VG7 An approved entry is locked.** While Status is Approved, its person, Date Worked and
Hours cannot change: the coordinator moves it back to Submitted, edits it and approves it
again. A validation rule, so it holds with automation off.

**R-VG8 Rejecting says why.** A rejection without a Rejection Reason is refused by the
service.

### Salesforce implementation

- **Object:** `Volunteer_Hours__c`, name field AutoNumber `VH-{000000}`, sharing Private.

| Attribute | API name | Type |
|---|---|---|
| Contact | `Contact__c` | Lookup to Contact |
| Account | `Account__c` | Lookup to Account |
| Household | `Household__c` | Lookup to Account |
| Volunteer Job | `Volunteer_Job__c` | Lookup to `Volunteer_Job__c` |
| Volunteer Shift | `Volunteer_Shift__c` | Lookup to `Volunteer_Shift__c` (clears on delete) |
| Volunteer Sign-up | `Volunteer_Signup__c` | Lookup to `Volunteer_Signup__c` (clears on delete) |
| Date Worked | `Date_Worked__c` | Date, required |
| Hours | `Hours__c` | Number(6, 2), required |
| Status | `Status__c` | Picklist: Submitted, Approved, Rejected |
| Approved By | `Approved_By__c` | Lookup to User |
| Approved Date | `Approved_Date__c` | DateTime |
| Rejection Reason | `Rejection_Reason__c` | Text(255) |
| Notes | `Notes__c` | Text Area(255) |

- **Validation rules:** `Exactly_One_Person` (R-VG1), `Job_Or_Shift_Required` (R-VG3),
  `Hours_Must_Be_Positive` (R-VG4), `Approved_Hours_Are_Locked` (R-VG7).
- **Custom permission:** `Manage_Volunteers`, in `Volunteers_Coordinator` and
  `Volunteers_Admin` (R-VG5).
- **Service:** `VolunteerHoursService`, `VolunteerHoursTriggerHandler`,
  `VolunteerHoursSelector`.

---

## 29N. Volunteer Settings

### Definition

The Volunteers module's own org-wide settings (ADR-0017: each module owns a protected
hierarchy custom setting), edited in the BarnCRM Settings console's Volunteers section and on
the module's own Volunteer Settings page, never in Setup. Defaults are applied in Apex
(ADR-0035): a blank or out of range value reads as the shipped one.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Hours_Require_Approval__c` | boolean | true | Whether hours are entered as Submitted and wait for a coordinator. Off means an entry is Approved as it is saved and counts at once (R-VG6). |
| `Attendance_Creates_Hours__c` | boolean | true | Whether marking a sign-up Attended writes the hours for that shift (R-VU3). |
| `Shift_Horizon_Weeks__c` | integer, 1 to 52 | 8 | How many weeks ahead recurring schedules keep their shifts created (V-07). |

### Salesforce implementation

- **Custom setting:** `Volunteer_Settings__c`, hierarchy, protected.

| Key | API name | Type |
|---|---|---|
| Hours Require Approval | `Hours_Require_Approval__c` | Checkbox, default true |
| Attendance Creates Hours | `Attendance_Creates_Hours__c` | Checkbox, default true |
| Shift Horizon Weeks | `Shift_Horizon_Weeks__c` | Number(2, 0) |

- **Setting Definition rows:** `Settings_Object__c` `Volunteer_Settings__c`, `Module__c`
  Volunteers, `Section__c` Volunteers, one per key.

---

## 29O. Packaged default volunteer rollups

### Definition

The Rollup Definitions Volunteers ships for hours on a person, a household, a job and a shift,
and the filled count on a shift (V-03). They follow Section 26: shipped as
`Rollup_Definition_Default__mdt` rows with `Package__c` Volunteers, materialized by
`VolunteersPostInstall` into the Rollup Builder module's `Rollup_Definition__c` (Section 14),
each editable and deactivatable by the admin. Volunteers ships definitions, not aggregation
code, and requires BarnCRM Rollup Builder (ADR-0127, decision 1).

Target scopes are Section 26's three disjoint ones, with paths from Volunteer Hours:
Household (record type Household, `Household__c`), Account (record type not Household,
`Account__c`) and Contact (`Contact__c`). Definition keys follow the scope, for example
`Household_Volunteer_Hours_Total`.

### Volunteer totals on Account and Contact

Source Volunteer Hours, base filter Status equals Approved (R-VG6), mode Both, fiscal windows
on Date Worked. Five rows per scope, fifteen in all.

| Target attribute | Aggregate | Source attribute | Extra filter | Definition |
|---|---|---|---|---|
| `Volunteer_Hours_Total__c` | SUM | `Hours__c` | none | Every approved hour this person or household has given. |
| `Volunteer_Hours_This_Year__c` | SUM | `Hours__c` | fiscal year offset 0 | Approved hours in the current fiscal year. |
| `Volunteer_Hours_Last_Year__c` | SUM | `Hours__c` | fiscal year offset -1 | Approved hours in the previous fiscal year. |
| `First_Volunteer_Date__c` | MIN | `Date_Worked__c` | none | The first day this person gave time, which a service award counts from. |
| `Last_Volunteer_Date__c` | MAX | `Date_Worked__c` | none | The most recent day they gave time, which a lapsed volunteer report counts from. |

### Totals on Volunteers objects

Four rows, mode Both.

| Target entity | Target attribute | Source | Aggregate | Source attribute | Filter |
|---|---|---|---|---|---|
| Volunteer Job | `Total_Hours__c` | Volunteer Hours | SUM | `Hours__c` | Status equals Approved |
| Volunteer Job | `Last_Volunteer_Date__c` | Volunteer Hours | MAX | `Date_Worked__c` | Status equals Approved |
| Volunteer Shift | `Total_Hours__c` | Volunteer Hours | SUM | `Hours__c` | Status equals Approved |
| Volunteer Shift | `Slots_Filled__c` | Volunteer Sign-up | COUNT | none | Status not equal to Cancelled (R-VU4) |

### Rules

**R-VR1 Freshness without Giving.** `Rollups_Last_Calculated__c` on Account and Contact is
shipped by Giving (Section 26). In an org without Giving the engine finds no stamp there and
writes none: the totals are right, and the person page shows no "last calculated" line.
Volunteers ships no second stamp, because two packages cannot define one API name on Account
and a differently named twin would answer the same question twice. Jobs and shifts carry the
module's own stamp.

**R-VR2 Turned off, then on.** While Volunteers is turned off (ADR-0073) its registry rows do
not run, so its saves queue no recalculation. After Turn on the totals catch up at the next
nightly run (mode Both), or at once with Recalculate all.

### Salesforce implementation

- **Fields on Contact, and on Account with the same API names** (shipped by Volunteers):

| Attribute | API name | Type |
|---|---|---|
| Volunteer Hours Total | `Volunteer_Hours_Total__c` | Number(10, 2) |
| Volunteer Hours This Year | `Volunteer_Hours_This_Year__c` | Number(10, 2) |
| Volunteer Hours Last Year | `Volunteer_Hours_Last_Year__c` | Number(10, 2) |
| First Volunteer Date | `First_Volunteer_Date__c` | Date |
| Last Volunteer Date | `Last_Volunteer_Date__c` | Date |

- **Shipped defaults:** 19 `Rollup_Definition_Default__mdt` rows, `Package__c` Volunteers,
  `Mode__c` Both, `Default_Active__c` true.
- **Automation Registry:** `Volunteers_Rollups_Hours` (Volunteer Hours) and
  `Volunteers_Rollups_Signup` (Volunteer Sign-up), handler `RollupTriggerHandler`, order 90,
  `Module__c` Volunteers.

---

## 29P. Skill

Sections 29P to 29V cover V-04 to V-08, beside the volunteer profile, Job
(`Volunteer_Job__c`), Shift (`Volunteer_Shift__c`), Sign-up (`Volunteer_Signup__c`), Hours
(`Volunteer_Hours__c`) and Volunteer Settings (`Volunteer_Settings__c`) of Sections 29I to 29O
(ADR-0127). Nothing here is added to Core except the three Import Template Default fields in
Section 13. A person reference is the pair in Section 4: `Contact__c` and `Account__c`, exactly
one set.

### Definition

One entry in the organization's list of volunteer skills and interests, for example "Spanish",
"Forklift licence" or "Working with children" (feature V-04). The list is the admin's own; the
package ships no skills.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The skill as staff see it in pickers and filters. |
| Description | long text | no | What the skill means here, for example which licence counts. |
| Active | boolean | yes (defaults true) | Whether the skill is offered when a skill is added to a person or a job. |

### Relationships

- **Skill to Volunteer Skill** and **Skill to Job Skill**, one to many.

### Rules

**R-SK1 Archive, do not delete.** A skill that a person or a job holds cannot be deleted; the
admin clears Active instead. An inactive skill stays on the people and jobs that hold it and is
not offered for new ones.

### Salesforce implementation

- **Object:** `Skill__c`, Text Name (80), sharing Read, tab in the Volunteers app.

| Attribute | API name | Type |
|---|---|---|
| Description | `Description__c` | Long Text Area (2000) |
| Active | `Active__c` | Checkbox, default true |

---

## 29Q. Volunteer Skill

### Definition

That a person has a skill or is interested in one (feature V-04). When a person can volunteer
is held on the person, in the multi-select attributes `Availability_Days__c` and
`Availability_Times__c` that the volunteer profile defines.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | An identifier assigned automatically. |
| Contact | reference(Contact) | conditional | The person, where people are Contacts. |
| Person Account | reference(Organization) | conditional | The person, where people are person Accounts. |
| Skill | reference(Skill) | yes | The skill or interest. |
| Type | picklist(Skill, Interest) | yes (defaults Skill) | Skill: the person can do it. Interest: the person would like to. |

### Relationships

- **Volunteer Skill to the person**, many to one, to exactly one of Contact or Person Account.
- **Volunteer Skill to Skill**, many to one.

### Rules

**R-VK1 One person.** Exactly one of Contact and Person Account is set (Section 4).

**R-VK2 Duplicates are harmless.** The skills editor on the person never adds a pair the person
already holds. A duplicate written another way (an import, the API) changes no answer, because
matching asks whether a person holds a skill, not how many times, so no automation guards it.

**R-VK3 Matching a shift.** "Find volunteers" for a shift lists people whose Volunteer Status is
Active, who hold every skill of Type Skill that the shift's job lists (Section 29R), and whose
`Availability_Days__c` includes the shift's weekday and whose `Availability_Times__c` includes
the part of the day the shift starts in (before 12:00, 12:00 to 17:00, from 17:00). A person
with no availability recorded is listed last rather than left out. Interests matching the job's
skills are shown beside each name; they never filter.

### Salesforce implementation

- **Object:** `Volunteer_Skill__c`, auto-number Name `VK-{000000}`, sharing Read.

| Attribute | API name | Type |
|---|---|---|
| Contact | `Contact__c` | Lookup to Contact (deletes this record when the person is deleted) |
| Person Account | `Account__c` | Lookup to Account (deletes this record when the person is deleted) |
| Skill | `Skill__c` | Lookup to `Skill__c` (refuses deleting a skill in use, R-SK1) |
| Type | `Type__c` | Picklist: Skill, Interest |

- **Validation rule:** `Volunteer_Skill_One_Person` (R-VK1).

---

## 29R. Job Skill

### Definition

A skill a job needs (feature V-04), used to find volunteers for its shifts (R-VK3).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | An identifier assigned automatically. |
| Job | reference(Job) | yes | The job. |
| Skill | reference(Skill) | yes | The skill the job needs. |

### Relationships

- **Job Skill to Job**, many to one; deleting the job deletes its job skills.
- **Job Skill to Skill**, many to one.

### Salesforce implementation

- **Object:** `Job_Skill__c`, auto-number Name `JK-{000000}`, sharing controlled by the job.

| Attribute | API name | Type |
|---|---|---|
| Job | `Job__c` | Master-Detail to `Volunteer_Job__c` |
| Skill | `Skill__c` | Lookup to `Skill__c` (refuses deleting a skill in use, R-SK1) |

---

## 29S. Volunteer Requirement

### Definition

One onboarding step for one person: an application, a background check or an orientation,
with where it stands and when it lapses (feature V-05). A person has one requirement row per
step they have started, and a new row when a lapsed step is done again.

The result of a background check is kept here and nowhere else: no person field records it, so
it is seen only by those who may see requirements and it leaves with them (R-VQ4).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | An identifier assigned automatically. |
| Contact | reference(Contact) | conditional | The person, where people are Contacts. |
| Person Account | reference(Organization) | conditional | The person, where people are person Accounts. |
| Type | picklist(Application, Background check, Orientation) | yes | Which onboarding step this is. The admin may add values. |
| Status | picklist(Not started, In progress, Completed, Not approved) | yes (defaults Not started) | Where the step stands. |
| Completed Date | date | conditional | The day the step was completed; required when Status is Completed. |
| Expires | date | no | The day a completed step lapses, for example a background check valid for two years; empty means it does not lapse. |
| Notes | text | no | A short note for the coordinator, such as the reference of the check. Never the findings of a check. |
| Is Current | boolean | computed | True when Status is Completed and Expires is empty or not before today. |

### Relationships

- **Volunteer Requirement to the person**, many to one, to exactly one of Contact or Person
  Account.

### Rules

**R-VQ1 One person.** Exactly one of Contact and Person Account is set (Section 4).

**R-VQ2 Dates.** Completed Date is required when Status is Completed and may not be in the
future; Expires may not be earlier than Completed Date.

**R-VQ3 Readiness is shown, not enforced.** The volunteer profile shows each Type's most recent
row and whether it is current. Nothing in v0.8 refuses a sign-up or hours for a person whose
steps are not current; the coordinator decides.

**R-VQ4 Kept to coordinators, erased with the person.** Requirements are private records: the
Volunteers Admin and Volunteers Coordinator permission sets read and edit all of them, and the
Volunteers Staff and Volunteers Read Only sets grant no access. Erasing a person (Section 29H)
deletes their requirement rows and empties them from the Recycle Bin, through the Volunteers
`PersonErasureExtension`, and the Erasure record lists them by Id only.

### Salesforce implementation

- **Object:** `Volunteer_Requirement__c`, auto-number Name `VR-{000000}`, sharing Private.

| Attribute | API name | Type |
|---|---|---|
| Contact | `Contact__c` | Lookup to Contact (deletes this record when the person is deleted) |
| Person Account | `Account__c` | Lookup to Account (deletes this record when the person is deleted) |
| Type | `Type__c` | Picklist: Application, Background check, Orientation |
| Status | `Status__c` | Picklist: Not started, In progress, Completed, Not approved |
| Completed Date | `Completed_Date__c` | Date |
| Expires | `Expires__c` | Date |
| Notes | `Notes__c` | Text (255) |
| Is Current | `Is_Current__c` | Formula (Checkbox) |

- **Validation rules:** `Volunteer_Requirement_One_Person` (R-VQ1), `Volunteer_Requirement_Dates`
  (R-VQ2).
- **Erasure:** `VolunteersErasureExtension` implements `PersonErasureExtension` (R-ER8).

---

## 29T. Shift Schedule

### Definition

A repeating pattern of shifts for one job, for example "every Saturday, 9:00 to 12:00, four
volunteers" or "Tuesdays and Thursdays every other week" (feature V-07). The schedule creates
ordinary shifts a set number of weeks ahead, and the shifts are then signed up for, cancelled
and counted like any other. ADR-0128 (`0128-volunteer-recurring-shifts.md`) records why.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the coordinator calls the schedule, for example "Saturday sorting". |
| Job | reference(Job) | yes | The job whose shifts the schedule creates. |
| Weekdays | multi-select(Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday) | yes | The days of the week a shift falls on. |
| Every N Weeks | integer | yes (defaults 1) | 1 for every week, 2 for every other week, and so on, counted from the week of Start Date. |
| Start Time | time | yes | When each shift starts. |
| End Time | time | yes | When each shift ends, later the same day. |
| Start Date | date | yes | The first day a shift may fall on. |
| End Date | date | no | The last day a shift may fall on; empty means the schedule runs until it is ended. |
| Volunteers Needed | integer | yes (defaults 1) | The places on each shift, copied to the shift's Volunteers Needed. |
| Location | text | no | Where the shifts happen, copied to each shift; empty means the job's location. |
| Active | boolean | yes (defaults true) | Whether the schedule still creates shifts. |
| Created Through | date | computed | The last day the schedule has created shifts for. Kept by the generator; never edited. |

### Relationships

- **Shift Schedule to Job**, many to one; deleting the job deletes its schedules.
- **Shift Schedule to Shift**, one to many, through the shift's `Shift_Schedule__c` lookup.

### Rules

**R-SSC1 Which days.** A day is a shift day when its weekday is in Weekdays, it is on or after
Start Date and on or before End Date (if any), and the number of whole weeks between the Monday
of Start Date's week and the Monday of its own week divides by Every N Weeks. Start Time and End
Time are read in the org's default time zone, so a 9:00 shift starts at 9:00 local time on both
sides of a daylight saving change, whoever's job created it.

**R-SSC2 A rolling horizon.** An active schedule keeps shifts created from today to
`Shift_Horizon_Weeks__c` weeks ahead (Volunteer Settings, default 8). Each run creates the
shift days after Created Through (or from today, if later), up to the horizon and End Date, then
moves Created Through forward. A day that already has a shift from this schedule is skipped. Each
created shift is Open, linked to the schedule, and takes the schedule's job, times, Volunteers
Needed and Location.

**R-SSC3 When it runs.** Saving a schedule queues a run for it, so its shifts appear without
waiting for the night (the `Shift_Schedule_Rules` automation). Every night the Volunteers
nightly job runs every active schedule in a batch (ADR-0128). A run takes a lock on the schedule's row first, so the
queued run and the nightly run never create the same day twice. Nothing runs while the module
is turned off; turning it back on catches up at the next nightly run.

**R-SSC4 Editing changes only future shifts with no sign-ups.** When Weekdays, Every N Weeks,
Start Time, End Time, Start Date, End Date, Volunteers Needed or Location changes, the
schedule's shifts that start after now, are not Cancelled and have no sign-up record of any
status are deleted, Created Through is cleared, and a run recreates them from the new pattern.
Past shifts, shifts with sign-ups and Cancelled shifts are never changed, and a day holding one
of them is not given a second shift. The save tells the coordinator how many future shifts were
kept as they were. Changing only Name changes no shift.

**R-SSC5 Ending a schedule.** Clearing Active, or setting End Date earlier, deletes the future
shifts it no longer covers that have no sign-ups and are not Cancelled; the rest are kept.
Deleting a schedule does the same for all its future shifts, and the shifts kept lose their
link to it. A coordinator who wants one day off cancels that shift: a deleted shift is created
again by the next edit of its schedule, a Cancelled one is not.

**R-SSC6 Scale.** The nightly batch takes ten schedules per transaction, so one transaction
creates at most ten schedules' worth of shifts at the longest horizon the setting allows.

### Salesforce implementation

- **Object:** `Shift_Schedule__c`, Text Name (80), sharing controlled by the job.

| Attribute | API name | Type |
|---|---|---|
| Job | `Job__c` | Master-Detail to `Volunteer_Job__c` |
| Weekdays | `Weekdays__c` | Multi-Select Picklist: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday |
| Every N Weeks | `Every_N_Weeks__c` | Number (2, 0), default 1 |
| Start Time | `Start_Time__c` | Time |
| End Time | `End_Time__c` | Time |
| Start Date | `Start_Date__c` | Date |
| End Date | `End_Date__c` | Date |
| Volunteers Needed | `Volunteers_Needed__c` | Number (4, 0), default 1 |
| Location | `Location__c` | Text (255) |
| Active | `Active__c` | Checkbox, default true |
| Created Through | `Created_Through__c` | Date, read only in every permission set |

- **Validation rule:** `Shift_Schedule_Valid`: Weekdays not empty, Every N Weeks 1 to 52, End
  Time after Start Time, End Date not before Start Date, Volunteers Needed at least 1.
- **Automation:** registry row `Shift_Schedule_Rules` (`ShiftScheduleTriggerHandler`), which
  applies R-SSC4 and R-SSC5 and queues `ShiftScheduleGenerator`; nightly job `ShiftScheduleBatch`
  supplied by `VolunteersNightlyJobProvider` (`NightlyJobProvider`).
- **Health Check:** an active schedule whose Created Through is more than two days short of the
  horizon (or End Date) is reported as "schedule horizon not filled".

---

## 29U. Volunteer Letter Template

### Definition

The wording of a volunteer hours letter or certificate: HTML with merge tokens for the
organization, the person, the hours and the period (feature V-08). Letters are produced by the
Volunteers package's own generator through the Visualforce PDF rendering service, not by
Giving's receipts (ADR-0129, `0129-volunteer-letters.md`). The HTML is restricted to what that
service renders, as for receipts (Section 25E).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the administrator calls this template. |
| Type | picklist(Hours letter, Certificate) | yes | Which kind of document this template lays out. |
| Body | long text | yes | The HTML with merge tokens. |
| Active | boolean | yes (defaults false) | Whether this is the template used for its type. |
| Template Key | text | no | The shipped default it came from; empty for a template the administrator wrote. Unique. |

### Rules

**R-VL1 One active template per type.** Activating a template deactivates the others of its
type. Generating with no active template of the type asked for is refused with a readable
message.

**R-VL2 Tokens are a closed set.** `{OrganizationName}` and `{OrganizationAddress}` (Core's
`Organization_Legal_Name__c` and `Organization_Address__c`), `{PersonName}`, `{FirstName}` (the
Preferred Name when set), `{Hours}`, `{FromDate}`, `{ToDate}`, `{JobList}` (each job with its
hours in the period) and `{Today}`. Every merged value is HTML escaped. An unknown token is left
as typed, so a typo shows on the proof.

**R-VL3 What a letter counts.** Hours is the sum of the person's hours with Status Approved and
a Date Worked from From Date to To Date, read in the user's own access. A person with no
approved hours in the period gets no letter and is listed as skipped.

**R-VL4 What a letter is.** Each letter is one PDF file linked to the person's record and to
nothing else; the file is the record that it was sent. Generating needs the custom permission
`Manage_Volunteers`; a list of people is generated in a batch of ten people per transaction.

**R-VL5 The shipped templates arrive at install.** `Volunteer_Letter_Template_Default__mdt` is
materialized by `VolunteersPostInstall` at install and at every upgrade, creating only the
templates whose Template Key the org does not have and never changing an existing one
(Section 13). A materialized template is Active when its type has no active template. The
template list has a Restore the shipped templates action that does the same.

### Salesforce implementation

- **Object:** `Volunteer_Letter_Template__c`, Text Name (80), sharing Read; edited only through
  the Volunteers Admin permission set.

| Attribute | API name | Type |
|---|---|---|
| Type | `Type__c` | Picklist: Hours letter, Certificate |
| Body | `Body__c` | Long Text Area (32768) |
| Active | `Active__c` | Checkbox |
| Template Key | `Template_Key__c` | Text (80), External ID, Unique |

- **Shipped defaults:** `Volunteer_Letter_Template_Default__mdt`, one row per type
  (`Hours_Letter`, `Certificate`), with `Template_Name__c` (Text 80), `Letter_Type__c` (Text 40)
  and `Body__c` (Long Text Area 32768); DeveloperName is the Template Key.
- **Service:** `VolunteerLetterService`, `VolunteerLetterBatch`, `VolunteerLetterRenderer`
  (`Blob.toPdf`).

---

## 29V. Volunteer hours import template

### Definition

The shipped import template that loads a spreadsheet of volunteer hours with the Core import,
one row per hours record (feature V-06). It adds no entity: it is an `Import_Template_Default__mdt`
row shipped by Volunteers that loads one object (R-IT12, R-D3).

### Rules

**R-VH1 The shipped rows.** Volunteers ships two rows with the Template Key `volunteer_hours`:
one with Person Mode Contacts, whose person column fills `Contact__c`, and one with Person Mode
Person Accounts, whose person column fills `Account__c`. Only the one matching the org's people
is materialized (R-D3). Target Object `Volunteer_Hours__c`, Load Operation Insert.

**R-VH2 Columns.**

| Column | Loads | Found by |
|---|---|---|
| Email | The person (`Contact__c` or `Account__c`) | The person's email: `lookupField` `Email` on Contact, `PersonEmail` on Account |
| Job | The job | The job's name |
| Date | Date Worked | |
| Hours | Hours | |
| Notes | Notes | |

Status is not a column; the template's default value sets it to Submitted, so imported hours
wait for approval like hours entered by hand. A row whose email or job finds nobody is rejected
(Lookup Not Found, Reject the row), and an email held by several people follows Several Matches
(R-IT9). The household on each hours record is set by the hours automation, as for hours
entered by hand.

**R-VH3 Large orgs.** A standard Email field may always be matched on (R-IT13). Where people
are person Accounts the lookup is on `PersonEmail`, which the large object guard must count as
indexed for an org of more than 100,000 accounts; the V-06 Core work adds it, by name as text.

---

## 30. Deferred to later iterations

These entities exist in the product plan but are deliberately **not** part of v0.1, v0.2,
or v0.3. They are listed here so that nobody adds them early, and so that the iteration
that owns them is unambiguous. Each will be specified in this document by the iteration
that builds it, before its metadata is created.

| Entity | Package | Iteration | Plan reference |
|---|---|---|---|
| Receipt | Giving | v0.4 (G-13) | Section 4.11, ADR-0010 |
| Donor Level | Giving | v0.4 (G-14) | Section 5.2 |
| Program, Service, Enrollment, Attendance, Service Delivery, Outcome | Programs | v0.9 | Section 5.4 |
| Funder pipeline entities (grant, reporting deadline, award compliance) | Funders | v0.9 | Section 5.5 |
| Mirror adapter entities and mirror mappings | Mirror | v0.6 onward | Section 4.12 |

Receipt left this table in v0.4 and is specified in Sections 25B to 25E, together with
Receipt Number Sequence, Receipt Run and Receipt Template. Acknowledgment Rule left it in
the same iteration and is specified in Section 25F, together with Acknowledgment (25G) and
Acknowledgment Run (25H).

Stewardship Plan left this table in v0.4 as well and is specified in Sections 25I to 25K,
as Stewardship Plan Template, Stewardship Plan Step and the running Stewardship Plan.

Gift Batch left this table in v0.5 and is specified in Section 25L, together with Gift
Batch Row (25M), the line of a batch.

The v0.6 inbound gift API (X-03) and accounting export (X-04) add no Mirror entity (the export is
gated by the custom permission `Export_Accounting`, on the `Accounting_Export` permission set, see
the 2026-10-12 accounting export row of Section 31): the
API writes ordinary gifts through Giving, and the export reads gifts and allocations and
records nothing (ADR-0051). The posting flag plan Section 4.12 mentions is G-20's, in Giving:
two attributes on Gift and one Giving settings key, and no new entity (R-G13, R-G14, ADR-0053).

Campaign sync (X-02) left this table in v0.6 and is specified in Section 29B. It adds no
entity: one attribute on Appeal, shipped by Mirror, and Mirror's own settings object. The
Gift Transaction mirror and NPSP household adoption are still to come.

The Opportunity mirror (X-01) left this table in v0.6 and is specified in Section 29C. It adds no
entity either: one attribute on Gift, shipped by Mirror, and two keys on Mirror Settings.

Volunteer Job, Shift, Sign-up and Hours left this table in v0.8 and are specified in Sections
29I to 29O with the volunteer person attributes, Volunteer Settings and the shipped volunteer
rollups (V-01 to V-03, ADR-0127). There is no Volunteer entity.

Skill, Volunteer Skill, Job Skill, Volunteer Requirement, Shift Schedule and Volunteer Letter
Template left this table in v0.8 (V-04 to V-08) and are specified in Sections 29P to 29U, with
the volunteer hours import template in 29V.

Two v0.4 entities have attributes that already exist on `Gift__c` from v0.2, because the
object is not worth altering later for fields this cheap: Acknowledgment Status,
Acknowledgment Date, and Receipt Number for G-12 and G-13, and In-kind Description and
Fair Market Value for G-18 (R-G9).

### Known gaps in shipped rules

Rules this document states that the shipped code does not implement. They are listed here
so that a reader is not told the product does something it does not, and so that the gap
is closed deliberately rather than discovered.

| Rule | Gap | Why it is open |
|---|---|---|
| R-GR4 (Section 25M) | A line of a posted batch can still be deleted through the API or a report by someone holding delete access on lines. | Validation rules do not run on delete, and a trigger for this alone costs more than the risk: the entry screen refuses it, the gifts are untouched, and only the record of the deposit loses a line. Revisit if an org reports it. |

Closed: R-M3's Primary Contact mirror, on 2026-09-23 by C-22 (ADR-0044, primary contact
mirrors the primary member).

---

## 31. Change log

| Version | Date | Change |
|---|---|---|
| v0.1 | 2026-09-06 | Initial model: Household, Household Member, Contact, Organization, plus the platform configuration entities Error Log, Automation Setting, Setting Change, Nonprofit Settings, and the shipped-defaults custom metadata Naming Pattern and Automation Registry. |
| v0.1 | 2026-09-07 | C-05 review fix: Error Log entries are published as `Error_Log_Event__e` (Publish Immediately) and written by a subscriber, so an entry survives the rollback it documents (new rule R-E4). |
| v0.1 | 2026-09-07 | C-04 and C-05 build. Error Log gains Object Name. Automation Setting gains Handler Class, Object Name, Execution Order, and Package Default, all copied from the shipped registry when a record is materialized. Automation Registry field API names fixed ("Object" and "Order" are reserved words). Error Log and Setting Change record names recorded as auto numbers. Nonprofit Settings picklist keys recorded as text, per ADR-0019. |
| v0.1 | 2026-09-07 | C-01 and C-02 build. Added `Household__c` (Lookup to Account) to Household Member: the original field list named the household side and the person side with the same attribute, so junction mode had no way to say which household a membership belonged to. `Account__c` is now defined as the person side only, matching R-M4. Recorded the naming service's token forms: `{FirstName}`, `{LastName}`, and `{Salutation}`, with the `{!Token}` spelling accepted as an alias so patterns copied from formula fields keep working. |
| v0.1 | 2026-09-07 | Junction membership made a first-class v0.1 path for orgs that store people as accounts (product owner priority change). The five Contact person attributes (`Deceased__c`, `Household_Role__c`, `Exclude_From_Household_Name__c`, `Exclude_From_Greetings__c`, `Preferred_Name__c`) are now present on Account with the same API names and definitions, because a person stored as an account carries them on that record. Naming and greetings read a person through the `HouseholdService.Person` shape rather than through Contact, so one set of rules serves both. |
| v0.2 | 2026-09-07 | Core: Rollup Definition (Section 14) with the filter document format and the mode-resolved path notation; Import Template, Import Batch, and Import Row (Sections 15 to 17) with the Created By Import Batch tag on Household, Contact, Organization, and Gift. Giving: Gift, Gift Allocation, Fund, and Appeal (Sections 18 to 21), and the packaged default giving rollups (Section 26). Nonprofit Settings gains `Fiscal_Year_Start_Month__c`, `Default_Fund__c`, `Default_Appeal__c`, `Rollup_Mode_Default__c`, `Import_Chunk_Size__c`, and `Setup_Assistant_Steps_Complete__c`. Shipped defaults gain `Rollup_Definition_Default__mdt` and `Import_Template_Default__mdt`. Published for build, objects not yet created. |
| v0.3 | 2026-09-07 | Giving: Commitment, Installment, Soft Credit, and Tribute (Sections 22 to 25) with their rollup targets. Core: Relationship, Affiliation, and Address (Sections 27 to 29), the Primary Affiliation reference on Contact, and the shipped defaults `Relationship_Type__mdt`. Nonprofit Settings gains `Automatic_Household_Soft_Credits__c`, `Installment_Generation_Horizon_Months__c`, `Installment_Overdue_Grace_Days__c`, `Contact_Address_Change_Behavior__c`, `Relationship_Auto_Reciprocal__c`, and `Seasonal_Address_Last_Run__c`. Published for build, objects not yet created. |
| v0.3 | 2026-09-07 | Convention added: person references are a Contact and Account pair with exactly one set (Section 4), following the change of first customer to Nonprofit Cloud and Agentforce Nonprofit orgs where individuals are person Accounts. Import Row and Import Template carry the person-mode attributes this requires. |
| v0.3 | 2026-09-07 | Giving G-08, G-09, G-10: the Employer attribute on Contact and on Account (`Employer__c`), rule R-G11 (matching gift linkage), rules R-SC6 and R-SC7 (automatic soft credits are recomputed and deduplicated), rule R-TR6 (a memorial is never notified to the person who died), and the gift status Received filter on the two soft credit rollups in Section 26. |
| v0.3 | 2026-09-07 | Giving: Gift gains `Refund_Reason__c`, so the reason a refund or a write-off was recorded is held on the negative gift rather than by editing the original (R-G3, G-04). Giving Settings added as Section 21A: `Giving_Settings__c` holds the three v0.3 Giving keys that ADR-0017 moved out of `Nonprofit_Settings__c`, and Section 12 records the move. |
| v0.3 | 2026-09-07 | Commitments (G-07, G-11): Giving Settings gains `Auto_Apply_Gifts_To_Installments__c` and `Installment_Top_Up_Last_Run__c`, and Section 12 records that the Giving keys live on `Giving_Settings__c` rather than `Nonprofit_Settings__c` (ADR-0017). R-CM5 states that Balance is empty for a recurring commitment; R-IN3 states the automatic linking of a gift to the earliest unpaid installment. |
| v0.3 | 2026-09-07 | Sections renumbered to keep the document in reading order: the former Section 14 "Deferred to later iterations" is now Section 30 and the former Section 15 "Change log" is now Section 31. Section 32 "Entity ownership by package" is new. |
| v0.3 | 2026-09-07 | C-10 sample data loader: added `Sample Data` (`Sample_Data__c`, Checkbox, default false) to Household, Contact, and Organization so the sample data set can be removed in one action. |
| v0.1 | 2026-09-07 | C-03: added the shipped-defaults type Setting Definition (Section 13), which drives the Nonprofit Settings console, and the Nonprofit Settings key `Setup_Steps_Completed__c` (Section 12), which records Setup Assistant progress. |
| v0.1 | 2026-09-07 | C-03, following ADR-0017: added `Settings_Object__c` to Setting Definition, so each package owns its own protected hierarchy custom setting and the console reads and writes any registered one. |
| v0.1 | 2026-09-07 | C-03, following ADR-0020: added `Navigation_Target__c` to Setting Definition, so a module's settings page is reached by navigation while Core's own panels are imported by name. |
| v0.2 | 2026-09-07 | C-12: added the Nonprofit Settings keys that the full Setup Assistant fills in (Section 12): the organization identity keys used on receipts (`Organization_Legal_Name__c`, `Organization_EIN__c`, `Organization_Address__c`, `Receipt_Logo_Document_Id__c`, `Receipt_Signature_Document_Id__c`, `Receipt_Signer_Name__c`, `Receipt_Signer_Title__c`), the giving defaults written only when the Giving module is present (`Default_Fund__c`, `Default_Appeal__c`), and the assistant's own progress keys `Setup_Steps_Skipped__c` and `Setup_Started_At__c`. The v0.2 key planned as `Setup_Assistant_Steps_Complete__c` shipped as `Setup_Steps_Completed__c` plus `Setup_Steps_Skipped__c`. |
| v0.1 | 2026-09-08 | C-05 review fix: all three packaged permission sets grant Read and Create on `Error_Log_Event__e`, because publishing is governed by Create on the event (rule R-E4). |
| v0.1 | 2026-09-08 | C-01 follow-up, R-H10 enforced in code. No object or field added. Household upkeep now clears Primary Contact when the person it names is no longer a current member, in both membership modes, and promotes nobody in their place: R-H10 already said the next member is proposed and not silently assigned, so the code follows the rule rather than the rule following the code. An organization shares the Primary Contact field (R-O3) and is never touched by this upkeep. |
| v0.1 | 2026-09-08 | C-09 merge and split build. No object or field added. R-H13 gains the paragraph above on what a merge does, in what order, and what audits it. Recorded against R-M3: a move carries a person's role and primary flag with them, but never gives a household a second primary, so a merge or a split of people who were each primary in their own household leaves the survivor with one. |
| v0.1 | 2026-09-08 | C-01 and C-02 review round. `Household__c` on Household Member is now a required lookup with a cascade delete, matching the "Required: yes" already in the attribute table. The Salesforce note that a household could be deleted without touching membership history was written before the field was required and is corrected: a deleted household now takes its own membership rows with it, which is the only case where history is lost.
| v0.3 | 2026-09-08 | G-08, G-09, G-10 review round. R-SC3a records that the membership change recompute is queued and capped at 500 gifts per household. R-TR6 now reads Deceased on Account as well as Contact, and allows notifying an honoree who is not marked deceased. R-G11 refuses a link where either gift has been refunded or written off. |
| v0.3 | 2026-09-08 | C-15 and C-16 automation split (product owner decision). No object or field added. Relationships and affiliations each ship two `Automation_Registry__mdt` rows instead of one: `Relationship_Validation` (order 10, `RelationshipValidationHandler`) with `Relationship_Reciprocal` (order 30, `RelationshipMaintenanceHandler`), and `Affiliation_Validation` (order 10, `AffiliationValidationHandler`) with `Affiliation_Primary` (order 30, `AffiliationMaintenanceHandler`). Switching the maintenance automation off no longer switches off that object's validation, which is what an administrator pausing automation before a bulk import needs. `applyDefaults` sits with the validation handler because the status and date rules (R-RL5, R-AF4) have to survive the upkeep being off. Both services now bypass the validation row alongside their own while they write. |
| v0.3 | 2026-09-08 | C-13 rollup adapter build. `Rollup_Definition__c` and `Rollup_Definition_Default__mdt` created as Sections 14 and 13 specify, with one correction: both gain `Fiscal_Date_Field__c`. R-R3 said the fiscal window is computed from the start month and the offset but never said which date attribute it is measured on, and every fiscal definition in Section 26 sums an amount rather than a date, so the window had nothing to bound. The attribute is optional and falls back to the attribute being aggregated, which is right for a rollup that aggregates a date. `Mode__c` on the definition ships with Both as its default value, matching R-R4 and the shipped Giving rows. |
| v0.3 | 2026-09-08 | C-17 Addresses build. `Address__c` and its fields, list views, compact layout, and validation rules created as specified in Section 29, with two recorded deviations: `Street__c` ships as Text Area (255) because the platform has no long text field that a list view or a validation rule can read, and `Contact_Address_Change_Behavior__c` ships as Text(40) on `Nonprofit_Settings__c` per ADR-0019 rather than as a picklist. `Verification_Status__c` defaults to Unverified and is left writable for a third party verification app (R-AD6); no packaged code writes it. |
| v0.3 | 2026-09-08 | G-02 defect fix (ADR-0022). No object or field added. Section 26's base filter changes from `Status equals Received` to `Status` in `Received`, `Refunded`, `Written off`, because R-G3 moves a fully refunded gift's status while leaving the negative gifts that reverse it at Received, so the old filter kept the negatives, dropped the positive, and subtracted a refunded gift twice. The count rows, largest gift, and the two date rows additionally require `Amount__c` greater than 0, so a gift given once and refunded in full reads as one gift and a total of zero. All 38 gift sourced, Gift Allocation sourced and Soft Credit sourced `Rollup_Definition_Default__mdt` rows updated; the three Pledge Balance rows filter on Commitment status and are unaffected. R-R9 gains the sentence that makes this a consequence of the rule rather than an exception to it. |
| v0.3 | 2026-09-08 | G-08 rule collision resolved (ADR-0023). No object, field, or rollup row changed. R-SC5 and R-SC6 collided on a full refund: R-SC5 creates a negative automatic credit on the negative gift while R-SC6 removed the original gift's automatic credits once its status became Refunded or Written off, so a fully refunded gift of 250 left a recognition total of minus 250 rather than zero. R-SC6 no longer removes credits on refund; removal is now only for a deleted gift. R-SC5 states the resulting pair explicitly and R-SC3 states that a gift keeps its household credits after its status is reversed. Section 26's soft credit rows already read gift status through the widened set from ADR-0022, so they need no further change and now carry both halves of the pair. |
| v0.3 | 2026-09-08 | G-04 receipt lock (ADR-0024). `Automation_Registry__mdt` and `Automation_Setting__c` each gain `Always_Runs__c` (Checkbox, default false): an automation marked that way enforces a rule rather than providing a convenience, so the dispatcher ignores the bypass, the pause and the switch for it, and the console shows its switch off and disabled with a reason (new rule R-A4). Giving ships the `Gift_Receipt_Lock` automation (order 5, `GiftReceiptLockHandler`) carrying the two enforcement calls that used to run inside `Gift_Core_Rules`, and the custom permission `Override_Receipt_Lock`, which is on no permission set and in no permission set group. R-G4 restated: the lock survives the automation switch, the override is a deliberate act in Setup, and every use of it is written to the Error Log at Warning severity. No object added. |
| v0.4 | 2026-09-08 | G-15 stewardship plans. Three objects added: `Stewardship_Plan_Template__c` (Section 25I) with `Plan_Key__c`, `Active__c`, `Trigger_Event__c`, `Minimum_Amount__c` and `Description__c`; `Stewardship_Plan_Step__c` (25J) as its master detail child; and the running `Stewardship_Plan__c` (25K), which carries the person reference pair `Contact__c` and `Account__c` with exactly one set. Rules R-SP1 to R-SP10. Two limits are recorded as decisions rather than gaps: R-SP7 does not reach back into running plans when a template is edited, and R-SP10 leaves completion to a person because closing a plan from its last task would need packaged automation on Task. Tasks hang off the plan through `WhatId`, so no package field is added to a standard object. |
| v0.4 | 2026-09-08 | G-15 gaps closed. `Stewardship_Plan__c` gains `Commitment__c` (Lookup), because the Commitment started event now starts plans and a plan started that way had nothing recording what started it. New rule R-SP3a says what the event means: a commitment created Active, or an existing commitment moving into Active from any other status. The automation is two registry rows rather than one, `Stewardship_Plan_Starter` on `Gift__c` and `Stewardship_Plan_Starter_Commitment` on `Commitment__c`, so each is switchable on its own. Templates, steps, step order and the Active state are now administered on a Stewardship Plans page in the settings console rather than on raw object tabs, which is what the every setting in the console rule requires. R-SP10 is unchanged: completion is still a person's judgment. |
| v0.4 | 2026-09-08 | G-16 retention reports. One attribute added: `Gifts_Last_Year__c` (Number) on Account and Contact, filled by three new `Rollup_Definition_Default__mdt` rows (`Household_Gifts_Last_Year`, `Account_Gifts_Last_Year`, `Contact_Gifts_Last_Year`) as a COUNT over Gift with the ADR-0022 count filter and fiscal year offset -1. It is the one retention question no shipped attribute could answer: whether a donor gave last fiscal year, counted rather than summed. Everything else G-16 needs was already here, so LYBUNT, SYBUNT and the conversion report add no fields and read `Last_Gift_Date__c`, `First_Gift_Date__c` and `Gift_Count__c`, which already carry the count filter. No object added (ADR-0025, ADR-0026). |
| v0.4 | 2026-09-08 | C-18 seasonal address swap build. `Address__c` gains `Replaced_By_Seasonal__c` (Checkbox, default false): R-AD4 said the previous default is restored when a season ends but nothing recorded which address that was, so an owner with a home address, a work address and a winter address had no unambiguous address to go back to. `Nonprofit_Settings__c` gains `Seasonal_Address_Last_Run_Summary__c` (Text 255) alongside the `Seasonal_Address_Last_Run__c` timestamp already specified in v0.3: a bare timestamp says the job woke up, not that it did anything, and "visible last run" is the half of C-18 that makes the job trustworthy. R-AD4 restated with the four outcomes per owner and the inclusive boundary days; R-AD8 added for the visible run and the system mode posture (ADR-0027). |
| v0.4 | 2026-09-08 | G-14 donor levels (ADR-0028). New Section 25A, `Donor_Level__c`, with `Minimum_Amount__c`, `Maximum_Amount__c`, `Description__c` and `Active__c`, and three fields shipped by Giving on both Account and Contact: `Donor_Level__c`, `Previous_Donor_Level__c` and `Donor_Level_Changed_Date__c`. Giving Settings gains `Donor_Levels_Enabled__c`, `Donor_Level_Source_Field__c` and `Donor_Levels_Last_Recalculated__c`. A level is a label on a giving total the rollup engine already maintains (R-DL1), never a second aggregation, so the ladder cannot disagree with the total printed beside it and the household membership modes are resolved once, by the rollup, rather than twice. Donor Level is removed from the deferred table in Section 30 and its ownership row now points at Section 25A. |
| v0.4 | 2026-09-08 | G-13 receipting (ADR-0016). Four objects added: `Receipt__c` (Section 25B), `Receipt_Number_Sequence__c` (25C), `Receipt_Run__c` (25D) and `Receipt_Template__c` (25E), with rules R-RC1 to R-RC10, R-RS1 to R-RS3, R-RR1 to R-RR3 and R-RT1 to R-RT3. Gift gains `Benefit_Description__c`, `Benefit_Value__c` and `Intangible_Religious_Benefits__c`, which is what a receipt needs to state a quid pro quo disclosure and the intangible religious benefits sentence; the deductible amount is computed by the renderer rather than stored, because a stored copy of a subtraction is a second place for it to be wrong. Giving Settings gains `Receipt_Number_Prefix__c`, `Receipt_Next_Counter__c`, `Receipt_Statement_Year__c`, `Receipt_Place_Of_Issue__c` and `Receipt_Renderer__c`, and its implementation subsection now lists every key it holds. Receipt leaves Section 30. |
| v0.4 | 2026-09-08 | C-10 sample data extended to the Giving module and to connections. `Sample Data` (`Sample_Data__c`, Checkbox, default false) added to `Gift__c`, `Fund__c`, `Appeal__c`, `Commitment__c`, `Relationship__c` and `Affiliation__c`, so every record the sample loader creates can be found and removed in one action; a gift's allocations, soft credits and tributes, and a commitment's installments, are details of a flagged record and go with it. `Sample Data Key` (`Sample_Data_Key__c`, Text(20)) added to Account and Contact: it holds the key the generated file gives a household, an organization or a person, which is how the Giving sample gifts find the donor they belong to across the asynchronous chain. No object added. |
| v0.1 | 2026-09-09 | C-01 documentation corrections. No object, field, or code changed. The duplicated "Person attributes on Account" bullet in Section 5 is removed. Household Member's `Account` attribute is retyped `reference(Account)` and defined as the person's own account only, because `reference(Household)` read as a second household reference and invited the confusion R-M4 exists to prevent. R-M3's Primary Contact mirror is recorded as unimplemented and unimplementable as written, and listed in Section 30 as a known gap. R-H14 now says what the console does: a preview over fixed sample households rather than the org's own, and a recompute batch that confirms it was queued and then reports nothing further. |
| v0.3 | 2026-09-09 | C-15 defect found by the first org run: the reciprocal upkeep never ran on a fresh org. `Relationship_Auto_Reciprocal__c` ships on, but a checkbox on a hierarchy custom setting read through `getOrgDefaults()` before the org has saved comes back false rather than carrying its declared default, so `RelationshipService` read the feature as switched off and wrote no other side, silently. No object or field added: the shipped value is now declared in `SettingsService.SHIPPED_DEFAULTS` and applied to the unsaved record, and `scripts/ci/check-setting-defaults.py` fails the build for any checkbox that ships on and is not registered (ADR-0035). |
| v0.4 | 2026-09-09 | G-10 refund propagation (ADR-0031). No object, field, or rollup row changed. ADR-0023 left one credit unreversed: the Matched Donor credit R-G11 creates sits on the employer's gift, and the negative gift recording a refund is not half of a matching pair, so a refunded match left the employee recognized for the full amount. R-G11 and R-SC5 restated: the negative gift carries a negative Matched Donor credit for the same person, prorated to the amount returned, so an employer gift of 500 with 200 returned leaves the employee recognized for 300. Only the employer's gift reverses the credit, the link survives the refund, and unlinking removes both halves. Section 26's soft credit rows already read gift status through the widened set from ADR-0022 and need no change. |
| v0.4 | 2026-09-09 | G-18 in-kind gifts (ADR-0030). No object added. Two attributes added on both Account and Contact, `In_Kind_Value__c` (Currency) and `In_Kind_Gift_Count__c` (Number), filled by six new `Rollup_Definition_Default__mdt` rows across the three scopes of Section 26, filtered to `Type__c` equals `In-kind` on top of the ADR-0022 status set. Rule R-G12 records what an in-kind gift is: a Gift of Type In-kind whose Amount is zero, whose worth is on `Fair_Market_Value__c`, which is never printed on a receipt, and whose description is required and is printed. R-G4 gains `In_Kind_Description__c`, because it appears on the document the donor holds. The `Amount_Cannot_Be_Zero` validation rule is narrowed to gifts that are not in-kind, and `In_Kind_Needs_Description`, `In_Kind_Has_No_Amount`, `In_Kind_Fields_Need_In_Kind_Type` and `Fair_Market_Value_Not_Negative` are added. |
| v0.4 | 2026-09-09 | G-12 acknowledgments (ADR-0032). Three objects added: `Acknowledgment_Rule__c` (Section 25F), `Acknowledgment__c` (25G) and `Acknowledgment_Run__c` (25H), with rules R-AK1 to R-AK12. No field is added to `Gift__c`: `Acknowledgment_Status__c` and `Acknowledgment_Date__c` were shipped in v0.2 for this feature (R-G9), and the rule that matched a gift is deliberately not stored on it, so that an edited rule applies to the gifts already queued (R-AK3). Giving Settings gains `Acknowledgments_Enabled__c`, `Acknowledgment_From_Address__c`, `Acknowledgments_Last_Run__c` and `Acknowledgments_Last_Run_Summary__c`. The wording of an emailed thank you lives in a standard `EmailTemplate` rather than in a packaged template object, which is what the plan's note on G-12 asks for and is the whole of the difference between this feature and receipting. Acknowledgment Rule leaves Section 30.
| v0.4 | 2026-09-09 | G-13 receipt number tampering fixed (ADR-0033). No object or field added. `Gift__c.Receipt_Number__c` becomes read only in `Giving_Staff` and `Giving_Admin`, matching `Giving_Read_Only`, and the receipt lock refuses every write to it, including the first one and including an insert, unless the receipting code is renumbering that gift. R-G4 restated: the number comes from the sequence in Section 25C or it does not exist. A number typed on by hand belonged to no receipt, locked the gift irreversibly, could be issued again later by the sequence, and left the gift unreceiptable, which is the collision ADR-0016 says nobody can recover from. The write moves from user mode to `GiftReceiptNumberWriter` in system mode under ADR-0021, because a field nobody may edit cannot be written in user mode, and the renumbering allowance changes from a transaction wide flag to the set of gift Ids being renumbered, so it no longer reaches an unrelated gift saved in the same transaction. |
| v0.4 | 2026-09-09 | G-13 receipting defects found by security review (ADR-0034). No object or field added. Section 25B gains R-RC11: a receipt's stored file is linked to its receipt and, on a per gift receipt, to its gift, and never to the donor Contact or Account, because a `ContentDocumentLink` grants access to a file through the record it names and every Core role can read a donor. The relationship bullet is corrected to match. Section 25E gains R-RT4: the shipped letters are materialized by the Giving post-install script rather than by a cacheable controller method, which cannot perform DML, and every write to `Receipt_Template__c` checks `Manage_Nonprofit_Settings`. |
| v0.4 | 2026-09-09 | C-01 person account trigger defect. No object or field added. The person account path ran on insert and update only, so deleting a person left their household with a stale Member Count and stale wording and their membership row identifying nobody, undeleting them did nothing, and the only person change that rewrote a household name was the household's own custom name box. R-H11 now says plainly that a person stored as an account is a member on the same terms as a contact, and R-M4 records what happens to a membership row when the person it names is deleted, and why the row is removed with the person rather than left to the platform. |
| v0.4 | 2026-09-09 | C-17 address propagation defect, found by the first org run on a person accounts org. No object or field added. R-AD3 gains the record type test: the person mailing fields exist on every account in a person accounts org, so `AddressService` asked the org whether it had them and then wrote them on whatever account it was holding. A household member, or an owner named in Person Account, that is a household or an organization was written through fields it cannot carry, the platform refused the update, and the address the user was saving was refused with it, with a message about permissions that named nothing true. The write is now decided by the account's record type, read once per save through `HouseholdSelector.getAccountRecordTypes` as an ADR-0021 upkeep read, and an account that holds no person is left out of the copy. Invisible on the Platform-only shape (ADR-0013), where the fields do not exist and the path returns early. |
| v0.4 | 2026-09-09 | C-14 import defect: a row with two people in it. No object or field added. Section 16 gains R-IR1a (what a row means for households) and R-IR2a (the household is named from the row). The importer joined a row's second person to the first person's household by writing the person's account reference, which is contact mode's mechanism, and skipped the join entirely where the org stores people as accounts. In junction mode that reference joined nobody and stopped the automatic path from acting, so a couple imported into the configuration the product recommends became two households or one household and one person with none. The join now goes through `HouseholdService.addMembers`, and automatic creation is suspended while the people about to be joined are saved, so nobody is given a household and then taken out of it. |
| v0.4 | 2026-09-09 | G-07 defect fix: nothing in a real org scheduled the Giving nightly jobs, so no installment was ever marked Overdue. `Giving_Settings__c` gains `Installment_Overdue_Last_Run__c` (Date/Time), `Installment_Overdue_Last_Run_Summary__c` (Text 255) and `Installment_Top_Up_Last_Run_Summary__c` (Text 255): the overdue pass recorded nothing at all, so "it has never run" and "it ran and found nothing overdue" were the same blank, and the top up carried a bare timestamp that said the job woke up rather than what it did. New rule R-IN5: the nightly passes are scheduled and stopped from the Nightly Jobs page of the settings console (ADR-0038), each records what it did, and a stale warning is shown only when the jobs are actually scheduled. No object added. |
| v0.3 | 2026-09-09 | C-17 deploy defect, found by the first org run to validate `Address__c` on its own. No rule changed. `Street__c` shipped with a `length` of 255 on a `TextArea` field, which the metadata schema does not accept: `TextArea`'s 255 character limit is fixed by the type, not settable, and only `LongTextArea` takes a `length`. The `length` element is removed; the field is unchanged in every way an admin or a user sees. `Address_Compact` shipped listing `Street__c`, which the platform also refused: no text area field, long or short, can appear in a compact layout. `Street__c` is removed from `Address_Compact`, which now reads Type, City, State, Default. Street is still visible everywhere a text field can appear: the four list views in Section 29 and the page layout are unaffected. |
| v0.4 | 2026-09-09 | G-18 receipt branding, and what a document for donated property may not print. No object added. R-RC12 says what a receipt for an in-kind gift may not say: no currency figure where the template asked for an amount, no amount on an in-kind statement line, in-kind gifts left out of the total a statement states with one sentence explaining the difference, and a Total Amount of zero on the receipt record, because a receipt record states what its document states and the fair market value stays on the gift (R-G12). R-RC13 says what a document is branded with: the legal name and address print from the template, or from a block above the letter when the template did not place them, on the same reasoning as the gift lines of R-RC8; the tax identification number prints in the signature block; the logo is optional and sized by one setting; and the image delivery route is a setting because ADR-0016's second spike cannot be closed without an org, so an unresolvable logo is logged at Warning severity and the document is produced without it. Giving Settings gains `Receipt_Print_Logo__c`, `Receipt_Logo_Width_Mm__c` and `Receipt_Logo_Delivery__c`. The two rules this branch numbered R-RC11 and R-RC12 are renumbered here, because ADR-0034 took R-RC11 first. |
| v0.4 | 2026-09-15 | X-09 native household guards (product-plan Section 11.2 item 9, mutual exclusion). No object or field added. `HouseholdSelector.nativeHouseholdAccountsAmong` is the single predicate, built on the existing ADR-0036 delete guard probe and short circuited by `OrgShapeDetector.hasNativeHouseholdGroups`, that every guard below asks. The naming batch and the naming path in `HouseholdService.afterMembershipChange` leave out an Account that already carries a native Nonprofit Cloud household group and count what they skipped. Automatic household creation, in both membership modes, does not make a second household for a person already linked to one, by the weaker but safe rule of asking the person's own Account. `AddressService` never writes the billing or person mailing fields of such an Account, from a default address or by propagation to its members. Health Check gains an informational finding naming how many native households were found, and a warning naming how many Accounts carry both household models at once, from a new `HouseholdSelector.nativeHouseholdCollisionCount` probe. No migration and no sync: an Account with both models keeps whatever name, greetings and address it already has until an administrator settles it on one model. |
| v0.4 | 2026-09-15 | C-16 review fix. No object or field added. `Primary_Affiliation__c` was maintained by `AffiliationService` (R-AF2) but shown nowhere: added, read only, to the Contact page layout in the Person section and to the Contact compact layout, so a list view or a mail merge can show a person's employer as the field's own description says. The matching field on Account is left off both Account page layouts: per Section 28, it is populated only in Person Account orgs, and neither the Household nor the Organization record type is a person, so it has nowhere on those layouts to belong. Also removed the internal feature tag "(C-10)" from the inline help text and description of `Sample_Data__c` and `Sample_Data_Key__c` on Account and Contact, since a feature ID means nothing to a nonprofit user; the same tag was removed from the Relationship, Affiliation, Commitment, Gift, Fund, and Appeal copies of `Sample_Data__c` in the same pass, so no field help or description in either package carries a feature ID now. |
| v0.4 | 2026-09-15 | C-01 defect, found by a Sales Cloud readiness audit. No object or field added. In junction mode a person's household is a `Household_Member__c` row, not the account their contact points at, but `ContactTriggerHandler` read the household from `Contact.AccountId` in every context, which in junction mode is an employer or nothing. So renaming, deleting and restoring a person stored as a contact quietly did nothing to their household: the count stayed stale, the dead person stayed in the name and both greetings, the membership row survived naming nobody because `Contact__c` empties itself on delete, and undelete never put them back. `AccountTriggerHandler` had always handled the account half of this correctly (see the 2026-09-09 C-01 person account row above); only the contact half was missing. `ContactTrigger` now declares before delete, and the handler mirrors the account one: memberships are removed in before delete while they still name the person, the departing households are carried to after delete, after undelete restores them, and a rename asks `householdIdsForPeople` which households to rewrite. Contact mode is unchanged by construction, since each of those calls answers empty outside junction mode. R-M4 and R-H11 now hold for both representations of a person, which matters because a Platform-only org (ADR-0013) can only run junction mode with contacts, and a mixed org holds both. |
| v0.4 | 2026-09-15 | Deploy stability: `packages/core/main/default/labels/CustomLabels.labels-meta.xml` (391 labels, 141 KB) split into per-feature label files, following the pattern already used for Address, Import, CoreRollups, Relationship, SeasonalAddress and Affiliation. No label was renamed, so no Apex or LWC reference changed. Groups of 8 or more labels, grouped by the second underscore-separated segment of `fullName`, became their own file: Access (33), AutomationControl (16), HealthCheck (73), HouseholdMembersPanel (13), HouseholdMerge (39), HouseholdNamingSettings (18), Households (19), HubHome (11), SampleData (31), Settings (23), SetupAssistant (84, after the four removals below). Groups under 8 (Automation, CoexistenceMode, ErrorLog, ErrorLogTile, HouseholdNaming, SettingsSearch, 27 labels total) were merged into `CoreShared.labels-meta.xml`. Four unreferenced Setup Assistant labels were deleted in the same pass, each re-verified with a grep of `packages/` for `.cls`, `.js` and `.html` consumers before removal: `Core_SetupAssistant_AllDoneMessage`, `Core_SetupAssistant_MarkDoneButton`, `Core_SetupAssistant_MarkNotDoneButton`, `Core_SetupAssistant_OpenButton`. Two label values were reworded without renaming the label: `Core_HouseholdNamingSettings_Recompute` from "Recompute all households" to "Update all household names", and `Core_HouseholdNamingSettings_RecomputeStarted` from "Recompute started. Households are being brought up to date in the background." to "Updating household names in the background." Verified: the 387 labels written across the new and shared files plus the 4 deleted equal the original 391, no label name is duplicated across files, and all 486 distinct `System.Label.X` and `@salesforce/label/c.X` references under `packages/core/` resolve to exactly one file. |
| v0.5 | 2026-09-15 | C-25: added the email attributes `Personal_Email__c`, `Work_Email__c`, `Alternate_Email__c` and `Preferred_Email__c` to the person attributes (Section 7), on both Contact and Account, with rule R-C6. When Preferred Email is set, the standard email is copied from the address it names on every save; when it is empty nothing is copied; when the address it names is empty the save is refused rather than the standard email being blanked. |
| v0.5 | 2026-09-22 | Removed the Naming Pattern custom metadata type (its four fields and six shipped records) before the first package version, by the owner's decision. Nothing read it: household naming reads the three pattern fields on Nonprofit Settings. A custom metadata type is effectively permanent once packaged, so it goes now rather than never. |
| v0.5 | 2026-09-23 | G-17 gift batch entry (ADR-0045). Two objects added: `Gift_Batch__c` (Section 25L) and its master-detail child `Gift_Batch_Row__c` (25M), with rules R-GB1 to R-GB6 and R-GR1 to R-GR4. The batch holds the control total and four defaults; a line holds only what varies, and its empty values are resolved from the batch at posting (R-GB1). The entered total is computed, never stored (R-GB2). Posting locks the batch, refuses an unbalanced or already posted batch, inserts ordinary gifts in user mode, and rolls everything back if any line fails. Status and a line's Gift are written only by posting; validation rules keep a posted batch and its lines unchanged. No trigger and no registry entry. The import framework is not used: ADR-0045 records why. No field added to an existing object. Gift Batch leaves Section 30. |
| v0.5 | 2026-09-23 | C-21 Health Check v2 (ADR-0048). No object, field, settings key or rollup row added. Health Check reads state the model already defines: shipped rollup definitions, automation switch rows and import templates not yet materialized from their shipped defaults (Section 13), the nightly rollup run when an active definition is in Scheduled or Both mode (Section 14). Recorded against R-A2: an `Automation_Setting__c` row whose registry entry is no longer shipped is left alone, because no fix deletes a record. `Automation_Setting__c` rows are now materialized by Core's and Giving's post-install scripts, one per shipped registry entry not yet present, never touching an existing row (before C-21 nothing created them). Recorded against R-R6: a shipped rollup default is not materialized when an active, administrator-made definition (`Is_Package_Default__c` false) already writes the same target entity and attribute; shipped defaults are not counted against each other, because household and organization pairs write one attribute for different accounts. Health Check detects orphans without changing them (cleanup is C-28): a person in no household, reported only while `Auto_Create_Households__c` is on (R-C1), which in contact mode is a Contact with no Account (a Contact whose Account is an Organization belongs to it, Section 7) and in junction mode a Contact or person account with no current Household Member row (R-M2, R-M4; a Contact whose Account is a Household is left to the membership check); and a Household with no current member (in contact mode no Contact on it, in junction mode no current row naming a person). Person accounts are recognised by the org's person record types, never by a person account field. |
| v0.5 | 2026-09-23 | C-20 duplicate detection (ADR-0050). One object added, `Duplicate_Dismissal__c` (Section 29A) with `Pair_Key__c` and `Reason__c`, which holds a decision rather than a finding. Detection is the org's own active duplicate rules; BarnCRM ships none, and the suggestions are the standard `DuplicateRecordSet` and `DuplicateRecordItem` records. A scan started from Nonprofit Settings evaluates those rules against the people and households already in the org. Rules R-DP1 to R-DP5 added. |
| v0.6 | 2026-09-23 | X-03, X-04 and X-06, the Mirror integration surface (ADR-0051). No object or field added. R-G7 is reworded: the inbound gift API answers a resend with the gift already recorded and never edits it, and refuses a resend whose amount differs. The accounting export reads `Gift__c`, `Gift_Allocation__c` and `Fund__c` and writes nothing: the posting flag plan Section 4.12 names belongs to G-20 in Giving, and no Mirror object records export runs. Section 30 notes that X-03 and X-04 add no Mirror entity. |
| v0.5 | 2026-09-23 | Removed the packaged Contact record type, its compact layout, and the list view that filtered on it, by the owner's decision (R-C4, ADR-0041). It drove no behavior: no code, rule or page branched on it, and the sample data loader was the only code that set it. People are now created with the org's default Contact record type. No field changed; the `Household_Role__c` picklist values it listed are all active on the master record type. |
| v0.5 | 2026-09-23 | No object or field added. The Account, Contact, Gift and Commitment record pages show their fields with Dynamic Forms (ADR-0043). R-O3 now holds on the Account record page: the Name and Greetings section, which carries Member Count, Anniversary, Custom Name and the two greetings, shows only for the Household record type. Account keeps one fallback page layout for both record types, and no layout is assigned to a profile. |
| v0.5 | 2026-09-23 | C-22, product-plan Section 11.2 item 8. No object or field added. R-M3's second half is implemented and its known-gaps row in Section 30 closed (ADR-0044, primary contact mirrors the primary member): in junction mode `Primary_Contact__c` mirrors the current member marked Is Primary, as that member's Contact or, for a Person Account, its person contact, and a hand edit of it on a household is refused. R-H5 now states the primary tiebreak the code already applied and which source each mode reads it from. R-H10 and the Household attribute table say which record is the mark in each mode. |
| v0.5 | 2026-09-23 | C-19 Import 2.0. New Section 17A, `Import_Journal__c`, a page per chunk recording the updates an import made (value before and value written) and what an undo kept or did not put back, with rules R-IJ1 to R-IJ5. `Import_Batch__c` status gains Undoing and Undo failed; R-IB6 restated and R-IB7 (the undo window is stamped at commit), R-IB8 (one named batch, counted and confirmed, once, to the recycle bin) and R-IB9 (deletes only tagged records, keeps a tagged record that has gained something since, puts back only values nobody has changed since) added. R-IB3 now says the import tags the household it made a new person. R-IT6 added: a recurring template is listed on the Hub with its last import date, and nothing loads a file on a schedule. `Nonprofit_Settings__c` gains `Import_Undo_Retention_Days__c`. R-IR5 notes that undo does not read the staged rows. |
| v0.5 | 2026-09-23 | C-19 review. No object or field added. R-IB1: a dry run is refused on a batch that has started a commit or is in an undo status. R-IB8: a chunk the platform stopped, or an undo job that is no longer running, ends Undo failed. R-IB9: a tagged record is kept when anything created since points at it through any reference the org can filter on (not only custom ones), when something was created during the commit by somebody else, when the record was edited since or has an activity, and when the person undoing cannot delete it; the system-mode reads and writes are recorded against ADR-0021. R-IJ1: a page holds at most 200 entries, and one oversized entry is logged rather than losing the chunk's journal. |
| v0.6 | 2026-09-24 | X-02 Campaign sync (ADR-0056, Campaign sync keeps its link on the appeal). New Part F and Section 29B, rules R-CS1 to R-CS8. `Appeal__c` gains `Campaign_Id__c` (Text 18, unique, external ID), shipped by Mirror rather than Giving, because Giving may not name Campaign and a lookup to Campaign would stop Mirror installing where Campaign is absent. New custom setting `Mirror_Settings__c` with `Campaign_Sync_Enabled__c` (default off). New automation `Campaign_Sync` on Appeal. No object added. R-AP4 points at Section 29B. Review changes of 2026-09-25: R-CS1 names the setting as the authoritative switch; R-CS4 logs a saver without access once, on create; R-CS5 writes refusals in one statement and skips a save too large to copy; R-CS7 lets Sync all appeals delete a Campaign it created and could not link. |
| v0.6 | 2026-09-24 | G-20 posting flag and period lock (ADR-0053). No object added. `Gift__c` gains `Accounting_Posted_At__c` (Date/Time) and `Accounting_Posted_By__c` (Lookup to User), both package written and read only in every permission set (R-G13). `Giving_Settings__c` gains `Books_Closed_Through__c` (Date), set on the Accounting Periods page and named by no Setting Definition row. New rules R-G13 (posting and unposting), R-G14 (a gift in the books that is posted or dated in a closed period is locked; nothing enters the books in a closed period) and R-GA5 (a locked gift's allocations are fixed). Two Always Runs automations, `Gift_Posting_Lock` and `Gift_Allocation_Posting_Lock`, and two custom permissions, `Post_Gifts` and `Override_Posting_Lock`, the second on no permission set. |
| v0.6 | 2026-09-24 | Cancelled gift status, by the owner's decision (ADR-0054, amending G-04, ADR-0022, ADR-0023 and ADR-0031). No object added. `Gift__c.Status__c` gains Cancelled. New R-G16: a Pending gift that will never be paid is cancelled, with no negative gift, outside every total, the export and receipts, and allowed in a closed period; it moves only between Pending and Cancelled and unlinks its installment. R-G3: only a Received gift is refunded or written off. R-G14, R-AK8, R-RC8 and Section 26 name Cancelled. |
| v0.6 | 2026-09-24 | C-23 automation pause with automatic resume, and the error digest (ADR-0055). No object added. `Nonprofit_Settings__c` gains five keys (Section 12, v0.6 keys): `Error_Digest_Recipients__c`, `Error_Digest_Frequency__c`, `Error_Digest_Covered_Until__c`, `Error_Digest_Last_Run__c` and `Error_Digest_Last_Run_Summary__c`. New rules R-A5 (a pause ends by itself through a one-time job that records the resume) and R-E5 (the digest counts and links, never quotes, and goes only to active users); R-E3 reworded to point at R-E5. |
| v0.5 | 2026-09-24 | G-23 gift import and G-24 donation matching (ADR-0052). No object added. `Import_Template__c` gains `Donation_Matching__c`, `Match_Date_Window_Days__c` and `Match_Amount_Tolerance__c` (R-IT7); `Import_Batch__c` gains the control totals `Expected_Count__c`, `Expected_Amount__c` and `File_Amount__c` (R-IB10); `Giving_Settings__c` gains `Donation_Match_Date_Window_Days__c` and `Donation_Match_Amount_Tolerance__c`. R-IR1 adds the `Tribute` row entity; R-IR6 states the entity processor contract and R-IR7 how a row's outcome is folded; R-IB8 and R-IB9 let an undo delete what an entity processor tagged, with the processor's reasons to keep. New Section 25N, rules R-GI1 to R-GI9 and R-DM1 to R-DM6. |
| v0.5 | 2026-09-24 | G-24 follow-up (ADR-0052, amended). `Import_Batch__c` gains `Processor_Settings_JSON__c`, one document the entity processor fills in a dry run and reads back in the commit, which Core never reads. R-IB11 added: a commit runs under the settings its dry run showed. R-DM7 added: donation matching's behaviour, window and tolerance are taken once per dry run and the commit uses them, not the template as edited since. R-IR6 and R-IT7 say so. |
| v0.5 | 2026-09-24 | C-14 defect. No object or field added. R-IB12: a commit no longer creates a new person once per row when several rows of one chunk name them; the rows share the first row's record, and the dry run counts them the same way. |
| v0.5 | 2026-09-24 | C-14 first names. No field added. R-IB12: a person is found by the key narrowed to their first name before the shared key, which alone finds them only when one person holds it or the row gives no first name; otherwise they are created. The same in the org, across chunks and within a chunk. |
| v0.5 | 2026-09-24 | C-14 passes. `Import_Batch__c` and `Import_Row__c` gain `Pass_Number__c`, and `Import_Batch__c` gains `Job_Id__c`. R-IB13 added: a start is refused while the batch's job is running (a pass whose job was aborted reads Failed and can start again, and an aborted commit can be undone), the synchronous reset of every staged row is removed (it failed past 10,000 rows), and each chunk clears and stamps its own rows so keys are read only by the pass that wrote them. |
| v0.5 | 2026-09-24 | C-14 dry run at scale. `Import_Row__c` gains `Person_1_Key__c`, `Person_2_Key__c`, `Person_1_Name_Key__c`, `Person_2_Name_Key__c`, `Organization_Key__c` and `Processor_Key__c`, indexed digests a dry run writes on the row that would create a record or load an external ID. R-IB12 and R-IR6: the digests are looked up per chunk instead of carried in the batch's state, so a dry run's heap no longer grows with the rows before the chunk. |
| v0.5 | 2026-09-24 | C-14 dry run fix. No object or field added. R-IB12 added: a dry run carries, across chunks, digests of the people and organizations it would create, so a later chunk naming one counts it matched, as the commit does, rather than created again. |
| v0.5 | 2026-09-24 | Import engine review fixes. No object or field added. R-IT3: in Person Accounts mode a person's contact attributes are written to the account's person fields (PersonEmail, PersonMailingStreet, PersonHasOptedOutOfEmail and the rest), found by describe, where before only the name, salutation and phone were written. R-IB12: a person account is matched on the fields it is written to, PersonEmail and PersonMailingPostalCode, and also on BillingPostalCode, where another tool often put it; a matching field the user may not read is skipped and named in the run log, and the dry run remembers a person it would create only where the commit writes the matched field, now including a person account and excluding a field the importing user may not write. |
| v0.6 | 2026-09-25 | X-01 Opportunity mirror (ADR-0058). New Section 29C, rules R-OM1 to R-OM11. `Gift__c` gains `Opportunity_Id__c` (Text 18, unique, external ID), shipped by Mirror for the reason Section 29B gives. `Mirror_Settings__c` gains `Opportunity_Mirror_Direction__c` (one direction or Off, empty reads as Off) and `Opportunity_Mirror_Start__c`. New automation `Opportunity_Mirror` on Gift. No object added. R-G10 names the attribute. Review changes of 2026-09-25: R-OM3 leaves a Pending gift's stage alone and omits Campaign where the saver cannot read it; R-OM5 needs only Opportunity create and edit; R-OM6 requires half the query and DML limits unspent and caps the distinct messages; R-OM7 gains an optional record type list (`Opportunity_Mirror_Record_Types__c`) and reads the start date in the org's time zone; R-OM8 rechecks linked gifts changed since the last completed run, skips a run while automation is paused or the switch is off, records the last completed run (`Opportunity_Mirror_Last_Run__c`, `Opportunity_Mirror_Last_Summary__c`) and has a Health Check finding; R-OM9 warns when a linked gift is deleted; R-OM11 caps its counts and refuses a viewer without read access. Setting Definition gains `Required_Permission__c`, and `HealthCheckExtensions` looks up Mirror's extension as well as Giving's (ADR-0057 amended). |
| v0.6 | 2026-09-25 | G-20 follow-up: Health Check finding for unposted gifts in a closed period (ADR-0053's recorded follow-up, ADR-0057). No object, field or rule added: the finding reports what R-G14 already locks, a gift with a counting status (ADR-0022) and a type other than In-kind, dated on or before Books Closed Through, whose `Accounting_Posted_At__c` is still empty, capped and linked the way C-21's orphan findings already are. Because Core may not name a gift or a closed period (C-29), Core gains a small extension seam instead of a new Core check: `HealthCheckExtension`, an interface, and `HealthCheckExtensions`, a resolver that finds an implementation by name with `Type.forName`, the same shape `ImportEntityProcessor` already uses for the opposite direction (R-IR6). `HealthCheckService.run()` folds a found extension's findings into the one report, isolated the way one failing check already is. Giving ships the one implementation, `GivingHealthCheckExtension`, delegating to `HealthCheckGivingChecks`, grouped the way ADR-0039 groups Core's own checks. |
| v0.6 | 2026-09-25 | C-29 neutral Core (ADR-0059). No object added. Seven keys move from `Nonprofit_Settings__c` (Section 12) to `Giving_Settings__c` (Section 21A) with their API names and definitions unchanged: `Default_Fund__c`, `Default_Appeal__c`, `Organization_EIN__c`, `Receipt_Signer_Name__c`, `Receipt_Signer_Title__c`, `Receipt_Logo_Document_Id__c` and `Receipt_Signature_Document_Id__c`. `Organization_Legal_Name__c` and `Organization_Address__c` stay in Core with neutral definitions. Nothing is migrated: no package version exists, so no org holds values on the old fields. Section 12 is labelled BarnCRM Settings, its API name unchanged. Section 32 gains the ownership of components that are not entities: the app, the Setup Assistant steps, the Health Check findings, the roles and the custom permissions. |
| v0.6 | 2026-10-12 | Neutral Core wording (ADR-0062). No object or field added, no API name changed. Rule 5 in Section 2 states that Core is neutral, with the Giving, detected-product, import-alias and edition exceptions. Section 12: `Coexistence_Mode__c` says which modes are offered when and which is recommended; the third mode is shown as Nonprofit Cloud coexistence. Section 15: the example name is "Generic contact list"; R-IT5 ships the generic gift list and every migration template, including `npc_person_accounts` and `npsp_contacts`, from Giving; `Donation_Matching__c` is labelled Payment Matching. |
| v0.6 | 2026-10-12 | API name pass (ADR-0063). No object or field added. `Nonprofit_Settings__c` is renamed `BarnCRM_Settings__c` (Section 12) with every field unchanged, and the custom permission `Manage_Nonprofit_Settings` is renamed `Manage_BarnCRM_Settings`. The other renames of that pass are recorded below as they land. |
| v0.6 | 2026-10-12 | API name pass, access and navigation (ADR-0063). No object or field added. Permission sets `Nonprofit_Admin`, `Nonprofit_Staff`, `Nonprofit_Read_Only` and `Nonprofit_Duplicate_Review` are renamed `BarnCRM_Admin`, `BarnCRM_Staff`, `BarnCRM_Read_Only` and `BarnCRM_Duplicate_Review`; the permission set group `Nonprofit_Admin_Group` is renamed `BarnCRM_Admin_Group`; the app `Nonprofit_Hub` is renamed `BarnCRM`; the tabs and flexipages `Nonprofit_Hub_Home` and `Nonprofit_Settings` are renamed `BarnCRM_Home` and `BarnCRM_Settings`. |
| v0.6 | 2026-10-12 | API name pass, stored values and the import field (ADR-0063). No object or field added. `Import_Template__c.Donation_Matching__c` is renamed `Payment_Matching__c` (Section 15), with the same picklist values. The `Coexistence_Mode__c` value `AgentforceNonprofit` becomes `NonprofitCloud` (Section 12). The shipped Import Template key `generic_donor_list` becomes `generic_contact_list`, and the Health Check keys `nonprofit_admin` and `no_nonprofit_admin` become `admin_role` and `no_admin`. |
| v0.6 | 2026-10-12 | UX review item 2 (ADR-0064, Giving ships the donor record pages). No object or field added. The giving rollups, the donor level and `Rollups_Last_Calculated__c` on Account and Contact are shown read only in a Giving section of Giving's own `Giving_Account_Record_Page` and `Giving_Contact_Record_Page`, with Dynamic Related Lists for Gifts, Commitments and Soft Credits and a New Gift quick action (`Account.New_Gift`, `Contact.New_Gift`), activated in the Fundraising app. Principle 2 (a rollup shows when it was last calculated) now holds on the donor's record. |
| v0.6 | 2026-10-12 | UX review item 10. No object or field added. `Gift__c.Type__c` is relabelled Payment Method (label only; the API name is unchanged), so the gift record, Quick Gift Entry, gift batches, import and the accounting export all say payment method. `Gift_Compact` and `Commitment_Overview` gain the donor (`Donor_Contact__c`, `Donor_Account__c`). On `Gift_Record_Page` (Dynamic Forms, ADR-0043) Donor Contact shows only when Donor Account is empty and Donor Account only when it is filled (R-G1 allows one donor), Original Gift and Refund Reason only when filled, and Matched Gift only when filled or when the donor is an account; the page gains the activity panel (ADR-0042). |
| v0.6 | 2026-10-12 | UX review quick wins. No object or field added. One minimal fallback page layout each (ADR-0043) for Relationship, Affiliation, Receipt, Receipt Run, Acknowledgment, Acknowledgment Rule, Acknowledgment Run, Stewardship Plan and Stewardship Plan Template, which had tabs and no layout. |
| v0.6 | 2026-10-12 | Import first names (ADR-0067, plan Section 11.2 item 17, option a). No object or field added. R-IB12: a row's person with a first name is matched only to a record with that first name; a record holding the shared key under another first name or none is not matched or renamed, and the person is created, where before a sole holder was matched and renamed. The shared key alone finds a person only when the row gives no first name. First names are compared ignoring case and runs of spaces, not accents, initials or short forms. |
| v0.7 | 2026-10-12 | C-32 import matching and per-file values (ADR-0068, `0068-import-matching-per-entity-and-per-file-values.md`). `Import_Template__c` gains `Person_Match_Field__c`, `Organization_Matching_Rule__c`, `Organization_Match_Field__c` and `Several_Matches__c`, and `Matching_Rule__c` is labelled Person Matching Rule. `Import_Batch__c` gains `File_Values_JSON__c`; `Import_Row__c` gains `Several_Matches__c`. R-IT2 gives organizations a rule of their own; R-IT8 (a chosen matching field), R-IT9 (several matches, rejected by default) and R-IB14 (values for every row of a file) added. R-IB12: several holders of a key no longer resolve to the earliest created. |
| v0.7 | 2026-10-12 | C-32 record ID matching, match only and custom fields (ADR-0069, `0069-import-record-id-matching-and-match-only.md`; plan Section 11 open question 15 answered yes). `Import_Batch__c` gains `Match_Only__c`. R-IT10 (a record ID in the file matches that record, and one not found rejects the row), R-IT11 (custom fields on people and organizations, offered from describe) and R-IB15 (a file that only matches) added. |
| v0.6 | 2026-10-12 | The empty household tidy-up keeps a household with gifts (ADR-0070, `0070-empty-household-tidy-up-keeps-households-with-gifts.md`; resolves the open follow-up of `0071-a-gift-keeps-the-household-it-was-given-to.md`). No object or field added. R-H12: an emptied household is also kept when an installed module still credits records to it, reported through the new Core extension point `HouseholdDependentsExtension`; Giving reports households named by a Gift's or a Commitment's Household field. Such a household is kept without an Error Log entry. |
| v0.6 | 2026-10-12 | A gift keeps the household it was given to (ADR-0071, `0071-a-gift-keeps-the-household-it-was-given-to.md`; plan decision D-20). No object or field added. R-G2 amended: a gift's Household is derived when the gift is saved and again when its donor changes, and is not recomputed when the donor's household membership changes, so a donor who moves households leaves their past gifts with the household they were given to. A household merge still carries the merged household's gifts to the survivor (R-H13). Household rollups reached through current membership, such as automatic household soft credits, follow current membership. The Gift Household attribute says so. This matches what the Giving trigger already did. |
| v0.7 | 2026-10-12 | C-34 part 1, the shared filter builder. No object or field added. R-R2 gains, still at version 1, three relative date operators (`this year`, `last year`, `last n days`), parent field paths up to two lookups deep, typed values, and the operators each field type is offered. One Core component, `filterBuilder`, is the document's only writer for both the Rollups page and Find; it reads fields from the running user's describe through `QueryFieldCatalog`. `RollupFilterParser` renders the relative operators as date literals. |
| v0.7 | 2026-10-12 | C-35 bulk update (ADR-0077, `0077-bulk-update-runs-as-the-user-from-a-find-query.md`). New Section 29E, rules R-BU1 to R-BU6; no new object. `Import_Batch__c` gains `Operation__c` (Import, Update) and `Operation_JSON__c`, and Section 16's definition covers both kinds of data job. R-IJ2 and R-IJ3: the journal gains the Failed entry. BarnCRM Settings gains `Bulk_Update_Run_Limit__c` (Section 12, v0.7 keys). New custom permission `Bulk_Update_Records` and permission set `BarnCRM_Bulk_Update`. |
| v0.7 | 2026-10-12 | C-34 Find. New Section 29D, Saved Query (`Saved_Query__c`: `Object_Name__c`, `Query_JSON__c`, `Shared__c`; Private, Apex sharing reason `Shared_With_Find_Users`), rules R-SQ1 to R-SQ5, including the query document. BarnCRM Settings gains `Find_Export_Row_Limit__c` (Section 12, v0.7 keys). New custom permission `Find_And_Export_Records` and permission set `BarnCRM_Find_And_Export`. ADR-0076 `0076-saved-queries-are-private-and-shared-by-apex-managed-sharing.md`. |
| v0.7 | 2026-10-12 | C-36 Advanced Find (ADR-0078, `0078-typed-find-queries-are-parsed-into-the-query-document.md`). No object, field or settings key added. R-SQ1 gains three optional keys at version 1 (`related`, `children`, `aggregate`). New rules R-SQ7 (typed queries parsed in the browser into the document), R-SQ8 (related-records conditions as semi-joins and anti-joins, related record columns as subqueries), R-SQ9 (summaries), R-SQ10 (editing results, journaled as an Update data job) and R-SQ11 (Excel export). New service `FindInlineEditService`. |
| v0.7 | 2026-10-12 | C-28 Data hygiene console. No object or field added. New rule R-SQ6: the Data Hygiene tab builds each check's query document in code, counts it in user mode over the same document, and opens it in Find by saving an unshared Saved Query owned by the person. The checks read rules already defined: R-C1 and R-M2 (no household), R-H11 (Member Count), R-M4 (a membership naming nobody), R-AD1 (an address with no owner), R-AD3 (the default address) and R-AD6 (Verification Status). ADR-0079 `0079-data-hygiene-checks-are-find-queries-built-at-request-time.md`. |
| v0.7 | 2026-10-12 | C-33 load one object (ADR-0080, `0080-import-load-one-object.md`). `Import_Template__c` gains `Target_Object__c`, `Load_Operation__c`, `Load_Match_Field__c` and `Lookup_Not_Found__c`; `Import_Journal__c.Phase__c` gains Created. R-IT12 (a template that loads one object: insert, update by record Id, upsert by external ID), R-IT13 (lookup columns by ID, name or a unique field) and R-IT14 (the allow-list of objects and the fields never written) added. R-IT1 gains the `Record` entity and `lookupField`; R-IR1, R-IB8, R-IB9 and R-IJ3 say how a one-object import's creations are journaled and undone; Import Row's Resulting Record and Processor Key serve one-object rows. |
| v0.7 | 2026-10-12 | C-37 data transforms and dedupe on import (ADR-0081, `0081-data-transform-document.md`). R-IT1 columns gain `transforms`; R-IT15 (the transform document and the `DataTransform` engine shared with bulk update) and R-IT16 (matching through the org's active duplicate rules) added. `Import_Template__c` gains `Use_Duplicate_Rules__c`; `Import_Row__c` gains `Duplicate_Rule_Match__c`. |
| v0.6 | 2026-10-12 | Rollup engine ownership (`decisions/0082-barncrm-owns-its-rollup-engine.md`, rollup slice S4). Specified ahead of the build; no metadata changed yet. New Section 14A, Rollup Queue (`Rollup_Queue__c`), the append-only list of target records waiting for recalculation, with rules R-RQ1 to R-RQ5. Section 14: R-R4 reworded (a normal save updates the totals in the same save, a bulk change is queued and finishes within minutes, the nightly run is the safety net) and the Mode labels become Instantly, Every night and Both (recommended), stored values unchanged, also on `Rollup_Mode_Default__c` (Section 12); new R-R11 (recompute, and which changes mark a target, including a gift's status and delete for fund totals and both households on a move), R-R12 (where real time comes from: packaged registrations, a trigger the Rollup Builder generates for an admin's own entity, or the Flow template) and R-R13 (freshness stamps written when the work is done), and field history on ten definition attributes. Section 26 records the fund half of R-R11. Section 30 lists the four rollup rules the current engine does not meet. |
| v0.6 | 2026-10-12 | Rollup engine swap (`decisions/0082-barncrm-owns-its-rollup-engine.md`, rollup slice S8). No object or field added. BarnCRM's own engine is the only path for real time, the queue, Recalculate, Recalculate all and the nightly run; `RollupBatch` is removed. The Mode picklist labels become Instantly, Every night and Both (recommended) on `Rollup_Definition__c`, `Rollup_Definition_Default__mdt` and the `Rollup_Mode_Default__c` setting, stored values unchanged. R-R4 loses its interim sentence; new R-R14 (one full run at a time, and a stopped chunk's records are queued). The four rollup rows in Section 30 are closed. |
| v0.6 | 2026-10-12 | Rollup operations slice (`decisions/0082-barncrm-owns-its-rollup-engine.md`, decision 10). `Rollup_Definition__c.Aggregate__c` gains COUNT_DISTINCT, ANY, NONE, TEXT_LIST and TEXT_LIST_DISTINCT, and the definition gains `Delimiter__c` (Comma, Semicolon, New line). New rule R-R15 says which target types each aggregate fills (checkbox targets for ANY and NONE, text targets for FIRST, LAST and the text lists), how blanks, ties, order, the delimiter and the field length are handled, and that every aggregate stays exact under recompute. R-R10 records what the save checks today. The shipped-default type `Rollup_Definition_Default__mdt` keeps its seven aggregates and has no delimiter: no shipped rollup uses the new ones. |
| v0.6 | 2026-10-12 | Quick Gift Entry pays a scheduled payment (ADR-0084, `0084-gift-entry-pays-a-scheduled-payment.md`). No object or field added. New rule R-DM8: the entry form offers the donor's open installments (R-DM2), marks those within the donation matching window and tolerance as suggested, chooses one in advance only when it is the only one suggested, and checks the choice again at save. The gift carries `Installment__c` and `Commitment__c`, which `Gift__c` already had. |
| v0.6 | 2026-10-12 | Gift batch lines pay a scheduled payment (`0084-gift-entry-pays-a-scheduled-payment.md`). `Gift_Batch_Row__c` gains `Installment__c` (Lookup to `Installment__c`, cleared on delete), so a choice survives saving the grid. New rule R-GR5: posting checks every named installment again and refuses the post naming the line; the gift carries the installment and its commitment. `Posted_Batch_Rows_Are_Final` refuses a change to Installment on a posted line, except the platform clearing it. R-DM8 names batch lines. No object added. |
| post-1.0 | 2026-10-12 | Field utilization (plan Section 6.1 item 10, ADR-0086 `0086-field-utilization-ships-in-core.md`). New Section 29F, `Field_Utilization_Snapshot__c`, rules R-FU1 to R-FU8. `BarnCRM_Settings__c` gains `Field_Utilization_Objects__c`, `Field_Utilization_Last_Run__c` and `Field_Utilization_Last_Run_Summary__c` (Section 12, field utilization keys). |
| v0.6 | 2026-10-12 | C-27 What's new after an upgrade (ADR-0087, `0087-whats-new-from-packaged-release-notes.md`). New Section 12A, `Whats_New_Seen__c`, a protected hierarchy custom setting with user-level records only and one field, `Last_Seen_Version__c`, with rules R-WN1 to R-WN4. New shipped type Release Note in Section 13, `Release_Note__mdt`, with `Version__c`, `Headline__c`, `Details__c`, `Sort_Order__c` and `Module__c`, read as shipped and never materialized. |
| v0.9 | 2026-10-12 | C-39 interaction notes (ADR-0089, `0089-interaction-notes-are-completed-tasks.md`). New Section 29G, rules R-IN1 to R-IN4. No object, field or picklist value added: an interaction note is a completed Task logged through the packaged action "Log an interaction" (`Contact.Log_Interaction`, `Account.Log_Interaction`), which fills Status Completed, Date today and Type Meeting. Visibility follows the record (R-IN2); per-note confidentiality is an owner question. |
| post-1.0 | 2026-10-13 | Core quality pass Q-04, job notifications. No object added. `BarnCRM_Settings__c` gains `Job_Notifications__c` (Section 12, job notification key), shipped on and registered in `SettingsService.SHIPPED_DEFAULTS` (ADR-0035). The notification is the platform custom notification type `BarnCRM_Job_Finished`. |
| v0.6 | 2026-10-12 | Accounting export custom permission. No object or field added. Mirror gains the custom permission `Export_Accounting`, held by the `Accounting_Export` permission set and no other. `AccountingExportController.exportGifts` and `markPosted` refuse in words (label `Mirror_AccountingExport_NoExportPermission`) a user without it, checked with `FeatureManagement.checkPermission`. `Post_Gifts` is unchanged. |
| 1.x (built ahead) | 2026-10-12 | C-37 bulk update steps and bulk delete (ADR-0091, `0091-bulk-delete-from-a-find-query-with-undelete.md`; ADR-0081). Section 29E: R-BU1 gains the `transform` change, new R-BU7 (change with steps through `DataTransform`), and a Bulk delete subsection, rules R-BD1 to R-BD6. `Import_Batch__c.Operation__c` gains Delete and `Import_Batch__c` gains `Rows_Deleted__c`. R-IJ2 and R-IJ3: the journal gains the Deleted entry. BarnCRM Settings gains `Bulk_Delete_Run_Limit__c` (Section 12, v0.7 keys). New custom permission `Bulk_Delete_Records` and permission set `BarnCRM_Bulk_Delete`, in no role. |
| v0.6 | 2026-10-13 | Rollup Queue and Queueable jobs (rollup comparison run on `oi-test`). No object or field added. R-RQ3: a save inside a Queueable leaves the processor to a later save, to the job's own chain end (`RollupService.startQueuedRecalculation`) or to the nightly run, because taking the job's one chained job stopped the sample data load with "Too many queueable jobs added to the queue: 2". |
| v0.6 | 2026-10-13 | Merge survivors recalculated after the merge (ADR-0092, `0092-merge-survivors-recalculated-after-the-merge.md`). No object or field added. R-R4 gains the merge exception: the platform refuses a trigger's write to a record mid-merge, so the survivors' real-time totals are recalculated by the `SurvivorRecalculation` queued job just after the merge, falling back to the Rollup Queue for more than 50 survivors or when no job can be queued. |
| v0.11 | 2026-10-13 | Security checklist follow-up. No object or field added. R-E4 unchanged: the three packaged permission sets keep Read and Create on Error Log Event, because the org refuses Create on a platform event without Read. |
| v0.6 | 2026-10-13 | Real-time rollups recalculated just after the save (ADR-0098, `0098-real-time-rollups-recalculated-just-after-the-save.md`, Core quality pass Q-01). BarnCRM Settings gains `Rollup_Processing__c` (Section 12, Background or In_Save, default Background). R-R4: by default a save queues its marked targets and the Rollup Queue recalculates them just after the save; In_Save keeps recalculation in the save when the planned queries fit. R-RQ3: the nightly run, the end of a pause, Retry and Start now start a processor for Pending entries no save started one for. R-RQ4: Health Check reports Failed entries and Pending entries older than an hour. No object added. |
| v0.6 | 2026-10-13 | Rollup Queue ready event (ADR-0100, `0100-rollup-queue-ready-event-from-queueable-jobs.md`). New platform event `Rollup_Queue_Ready__e` (no fields, Publish After Commit), subscribed by `RollupQueueReadyTrigger`; the three packaged permission sets grant Read and Create on it, as on `Error_Log_Event__e`. R-RQ3: a save inside a Queueable publishes one event per transaction and its subscriber starts the processor, so those totals stay near real time without taking the job's one chained job. |
| post-1.0 | 2026-10-13 | Field utilization on demand (ADR-0101, `0101-field-utilization-on-demand.md`, owner decision). `BarnCRM_Settings__c` loses `Field_Utilization_Objects__c`, `Field_Utilization_Last_Run__c` and `Field_Utilization_Last_Run_Summary__c`. Section 29F: R-FU1 (objects as Find offers them), R-FU5, R-FU7 (on demand, saved by choice, no retention job) and R-FU8 (previous saved count shown) rewritten; `Field_Utilization_Snapshot__c` unchanged. |
| v0.6 | 2026-10-13 | Health Check on Home shows the last result (ADMIN-7, ADR-0106 `0106-health-check-on-home-shows-the-last-result.md`). No object added. `BarnCRM_Settings__c` gains `Health_Check_Last_Run__c` and `Health_Check_Last_Result__c` (Section 12, Health Check keys). |
| v0.6 | 2026-10-13 | Error Log retention (owner decision 2026-10-13, ADMIN-26). `BarnCRM_Settings__c` gains `Error_Log_Retention_Days__c` (default 180; Section 12, v0.6 keys). New rule R-E6: the daily Error Log job deletes entries older than that, whatever their status. No object added. |
| v0.6 | 2026-10-13 | A range on every number setting (owner decision 2026-10-13, ADMIN-27). `Setting_Definition__mdt` gains `Min_Value__c` and `Max_Value__c` (Section 13); every shipped Number row sets both, and the console and `SettingsService` refuse a value outside them. No object added. |
| v0.11 | 2026-10-13 | Household Member integrity (PEOPLE-25). No object or field added. R-M4 is now enforced by the validation rule `Membership_Names_One_Person` on a save that creates a row or changes who it names. New R-M6: one current membership per person per household, refused before the save by the Household Member trigger (label `Core_Households_ErrorAlreadyCurrentMember`). R-M3's tolerance of two primaries from a data load is unchanged. |
| v0.11 | 2026-10-13 | Address defaults (PEOPLE-22, PEOPLE-49). No object or field added. R-AD2 now says what happens to several defaults in one save, refuses clearing an owner's only default, prefers a non-seasonal address when the default is deleted, and makes the first address added from the card the default. `Seasonal_Day_In_Range` accepts only days the month has (February 29 allowed). |
| v0.11 | 2026-10-13 | Households and people quality pass (ADR-0107, `0107-a-persons-household-and-primary-contact-in-both-modes.md`). No object or field added. R-H1: the person a household is created for is its Primary Contact. R-H2: a Contact inserted in junction mode with its Account set to a household joins it with one membership record. R-H10: in contact mode a Primary Contact who is not a member is refused before save. R-M3 gains a person's household: the primary membership, else the earliest current one. |
| v0.11 | 2026-10-13 | A second primary is refused on a single save (ADR-0108, `0108-a-second-primary-is-refused-on-a-single-save.md`). No object or field added. R-M3: a one-record save by a person that would give a household a second current primary member is refused before the save (label `Core_Households_ErrorSecondPrimary`); a load of many records, or through the APIs or background Apex, is tolerated and settled as before. |
| post-1.0 | 2026-10-13 | Erase a person (owner decision 2026-10-13, ADR-0110 `0110-erase-a-person-anonymizes-in-place.md`). New Section 29H, `Erasure__c` with `Contact__c`, `Person_Account__c`, `Erased_Record_Id__c`, `Request_Reference__c` and `Details__c`, rules R-ER1 to R-ER10 (R-ER9 and R-ER10 owner decisions 2026-10-13). New custom permission `Erase_People` and permission set `BarnCRM_Erase_People`, in no role. |
| v0.6 | 2026-10-13 | Core quality pass, import (IMPORT-4, IMPORT-8). No object or field added. R-IT11: people and organization values are read as Load one object reads them, a value the field cannot take rejects the row, and a change is decided on typed values with capitals counting. |
| v0.6 | 2026-10-13 | Core quality pass, import (IMPORT-1). `Import_Batch__c` gains `Template_Snapshot_JSON__c`. R-IB1: a dry run records the template it started with, and that dry run and the commit run under it, so a template edited after the preview does not change the commit. |
| v0.6 | 2026-10-13 | Core quality pass, import (IMPORT-3). No object or field added. R-IB1: a row's organization is created only after its people are matched and validated, so a rejected row creates nothing and the dry run counts what the commit does; a rejected row points at what it saved. |
| v0.6 | 2026-10-13 | Core quality pass, import (IMPORT-10, owner decision). No object or field added. R-AF5 states how a people import creates or matches the first person's affiliation with the row's organization, journaled as Created for undo; R-IR6: Core resolves the `Affiliation` entity. |
| v0.6 | 2026-10-13 | Core quality pass, import (IMPORT-22, IMPORT-23). No object or field added. The wizard's fixed columns are served by the server with labels, adding Affiliation: role; File Reference is empty for a file over 2.5 MB. |
| v0.6 | 2026-10-13 | Core quality pass, import (IMPORT-19, D-41). No object or field added. R-IT4: shipped import templates are added on install and on every upgrade by each package's post-install script. |
| v0.6 | 2026-10-13 | Core quality pass, import (D-40). No object added. `BarnCRM_Settings__c` gains `Import_Row_Retention_Days__c` (v0.7 keys table, Import section). R-IR5: staged rows are deleted nightly once their batch finished more than that many days ago, and a batch without its rows cannot run again. |
| v0.6 | 2026-10-13 | Core quality pass, import (number reading). No object or field added. R-IT11: numbers are read as spreadsheets export them in the user's locale (currency symbols and codes, grouping marks, accounting brackets); a value whose decimal mark cannot be told is refused. |
| v0.6 | 2026-10-13 | Trial import (data tools parity rank 4). `Import_Batch__c` gains `Trial_Rows__c` and the Status value Trial complete; BarnCRM Settings gains `Import_Trial_Rows__c` (default 25). New rule R-IB16: commit the first N rows, then the remaining rows into the same batch, one undo for both. |
| v0.6 | 2026-10-13 | Load one object lookups by any field (data tools parity). No object or field added. R-IT13: a lookup may name its parent by any text, email or phone field the user may read and filter on, and the large object guard refuses an unindexed field on an object over 100,000 records. |
| v0.6 | 2026-10-13 | Load one object updates by a field you choose (data tools parity). `Import_Template__c.Load_Operation__c` gains Update by a matching field, and Load Match Field serves it. R-IT12 gains that operation, which finds each row's record by any text, email or phone field, rejects a row it finds nothing for, and follows Several Matches; Account and Contact may use it (R-IT14). |
| v0.6 | 2026-10-13 | Load one object related records (data tools parity; ADR-0111, `0111-load-related-records.md`). `Import_Template__c` gains `Related_Object__c` and `Related_Parent_Field__c`; `Import_Row__c` gains `Related_Status__c`, and its Second Resulting Record holds the related record. New rule R-IT17: parents and related records from one file, parent key dedupe, parents saved first, related rows of a failed parent rejected, one undo for both. |
| v0.6 | 2026-10-13 | Retrying the rejected rows (data tools parity). `Import_Batch__c` gains `Retry_After_Row__c` and the Status value Retrying; `Import_Row__c.Status__c` gains Retried. New rule R-IB17: a committed import's fixed rejected rows are staged, previewed and committed into the same batch, and one undo covers both runs. |
| 1.x (built ahead) | 2026-10-13 | More transform steps (ADR-0112, `0112-more-transform-steps.md`). No object or field added. R-IT15 gains `map`, `ifThen`, `part`, `first`, `last`, `shiftDate` and `today`; the R-IT1 mapping document and the R-BU1 bulk update definition are written as version 2. R-BU7 applies them unchanged. |
| 1.x (built ahead) | 2026-10-13 | Import row rules (ADR-0113, `0113-import-row-rules.md`). R-IT1 gains `skipRows`, `uniqueBy` and a column's `blankClears`; new R-IT18 (skip rows and one row per key, decided at staging, Status Skipped) and R-IT19 (an empty cell clears a one-object field only where its column says so, journaled). `Import_Row__c` gains `Row_Key__c` (Text 16, External ID, bookkeeping in no permission set). |
| v0.6 | 2026-10-14 | Tier 1 scale test findings. No object or field added. R-H4: a name or greeting fits its field, a long list naming the first members and counting the rest. R-RQ3: the processor hands off to `Rollup_Queue_Ready__e` at the chain depth limit instead of queuing a run the platform refuses. |
| v0.6 | 2026-10-14 | Large rollup parents (ADR-0116, `0116-rollup-large-parents-recalculated-by-a-batch.md`, tier 1 scale test). No object or field added. New R-RQ6: a record whose source rows are more than one transaction may read is recalculated by `RollupLargeParentBatch`, chunk by chunk over its source rows, with one write at the end; records are routed there by an estimate from stored counts, or as a lone record that stopped its run on the query row limit. R-RQ3: a run takes records up to a row budget; a run that stops charges only the records it was recalculating, which are retried alone and a quarter as many at a time so only the record that keeps stopping runs ends Failed; and the finalizer starts the next processor through `Rollup_Queue_Ready__e` instead of halving the slice and queuing it, which the platform stopped after five failed jobs in a row and left 826 entries Pending. |
| v0.6 | 2026-10-14 | Rollup Queue enqueue race (ADR-0117, `0117-rollup-queue-asks-again-after-commit.md`, tier 1 scale rerun). No object or field added. R-RQ3: a transaction that inserted entries and queued no processor publishes `Rollup_Queue_Ready__e`, so the check runs again after it commits; before this a processor waiting at the save could finish before the save committed, and a parallel Bulk API load left 47 entries Pending with no processor. |
| post-1.0 | 2026-10-14 | Households emptied by deleting people (D-89, ADR-0120, `0120-households-of-deleted-people-are-tidied-once-unrestorable.md`, amends D-88). Account gains `Emptied_By_Deletion__c` (Date); `BarnCRM_Settings__c` gains `Keep_Households_Of_Deleted_People__c` (shipped false, so the tidy-up is on). New rule R-H12a: a nightly tidy-up moves such a household to the Recycle Bin once none of its former members' contacts or membership rows remain there and nothing else points at it. |
| v0.6 | 2026-10-14 | Large parent route efficiency (ADR-0116, tier 1 scale rerun). New protected hierarchy custom setting `Rollup_Run_Lock__c` (no fields, Section 14A implementation). R-RQ6: a record goes to the batch only when its estimate reaches two fifths of the query row limit (was a fifth; the run budget stays three fifths), and a run starts only under a lock on that setting's org-level record, so concurrent processors no longer start batches side by side. R-RQ3: the hand-off at the chain depth limit is no longer logged. |
| v0.6 | 2026-10-14 | Merge settlement always runs (ADR-0118). New platform event `Merge_Settlement_Ready__e` (Publish After Commit; `Household_Ids__c`, `Owner_Ids__c`, `Person_Ids__c`, 200 identifiers each per event), subscribed by `MergeSettlementReadyTrigger`; the three packaged permission sets grant Read and Create on it. A merge inside a Queueable, or with no queueable job left, publishes it instead of only logging a warning, so its survivors are settled. A person account survivor keeps the default address matching its mailing fields, not the newest. |
| v0.6 | 2026-10-14 | Import undo and rollup saves (ADR-0119, `0119-import-undo-judges-edits-before-deleting.md`, 25,000 row gift import scale test). No object or field added. R-IB9: a rollup save the import set off, told by the `Rollups_Last_Calculated__c` stamp written in it (whatever the running user's access) and dated within sixty minutes of the commit completing, is not an edit, whoever ran it; a later one keeps the record; the undo judges every tagged record for edits before it puts back or deletes anything, so a rollup either sets off, or the undo's own save, cannot hide an earlier edit. Before this, undoing an import that created people and gifts kept 7,229 of 8,333 people, saved by the Automated Process user as their totals were recalculated. |
| v0.6 | 2026-10-14 | Rollup queue row budget (ADR-0116, 25,000 row gift import scale test). No object or field added. R-RQ6: a record's estimate reads the stored totals of every active COUNT definition on its entity, not only those the run calculates, so a large parent whose entries name only a SUM or MAX still goes to the batch. R-RQ3: rows a run's recalculation of one entity read count against its row budget in place of their estimate. Before this two Rollup Queue runs stopped on "Too many query rows: 50001" while a fund's allocations rose to 25,000. |
| v0.6 | 2026-10-14 | Rollup queue row ceiling (ADR-0116, 25,000 row scale rerun). No object or field added. R-RQ6: a queue run measures what each query of an entity's recalculation read, and before a further query would pass four fifths of the query row limit it stops, writes nothing and sends that entity's records to the large parent batch. Before this a fund whose stored count was stale (3,200 of 26,102 allocations) was estimated small, its second query stopped four runs on "Too many query rows: 50001", and it was narrowing towards Failed. |
| v0.6 | 2026-10-14 | Editions, features, modules and first-run setup (ADR-0124, `0124-edition-gates-visibility.md`). New field `Features_Turned_On__c` on BarnCRM Settings (the Core features turned on; one-way). New shipped type `BarnCRM_Module__mdt` (`Editions__c`, `Package_Folder__c`, `Install_Version_Id__c`, `Sort_Order__c`, `Probe_Object__c`, `App_Name__c`): which editions offer each module, replacing the module list and installer Ids held in Apex. |
| v0.6 | 2026-10-14 | The rollup engine leaves Core for the BarnCRM Rollup Builder module (ADR-0125, `0125-rollup-builder-module.md`). No object or field added or renamed. Rollup Definition, Rollup Queue, Rollup Run Lock, `Rollup_Queue_Ready__e` and Rollup Definition Default (shipped default) move to `packages/rollups` with their API names unchanged (Section 32). Core reaches the engine only through `RollupEngineExtension`. `Rollup_Mode_Default__c` and `Rollup_Processing__c` stay on `BarnCRM_Settings__c` until the module's own settings object is added. |
| v0.6 | 2026-10-14 | Rollup Settings added as Section 14B (ADR-0125, decision 6): `Rollup_Settings__c`, the BarnCRM Rollup Builder module's protected hierarchy custom setting, holds `Rollup_Mode_Default__c` and `Rollup_Processing__c`, moved from `BarnCRM_Settings__c` (Section 12) with their API names and definitions unchanged. Stored values are not carried over. |
| v0.6 | 2026-10-15 | BarnCRM Rollup Builder in the module catalog (ADR-0125, D3 and decision 11). New field `Requires__c` on `BarnCRM_Module__mdt`: the modules a module's package needs installed first. Record `Rollups` gets `Package_Folder__c` `rollups` and `App_Name__c` `BarnCRM_Rollup_Builder`; Giving requires `Rollups`, Funders and Mirror `Rollups;Giving`. |
| v0.8 | 2026-10-17 | Volunteers V-01 to V-03 (ADR-0127). New Part G, Sections 29I to 29O: the volunteer person attributes on Contact and Account (shipped by Volunteers, not Core), `Volunteer_Job__c`, `Volunteer_Shift__c`, `Volunteer_Signup__c`, `Volunteer_Hours__c`, the module's `Volunteer_Settings__c` and 19 shipped volunteer rollups (Status Approved, mode Both) through BarnCRM Rollup Builder. Rules R-VP, R-VJ, R-VS, R-VU, R-VG and R-VR. Section 4 gains the volunteer person pairs. Specified ahead of the build; no metadata yet. |
| v0.8 | 2026-10-17 | Volunteers V-04 to V-08 (ADR-0128 `0128-volunteer-recurring-shifts.md`, ADR-0129 `0129-volunteer-letters.md`). New in Part G, all in Volunteers: Skill (`Skill__c`, 29P), Volunteer Skill (`Volunteer_Skill__c`, 29Q), Job Skill (`Job_Skill__c`, 29R), Volunteer Requirement (`Volunteer_Requirement__c`, 29S), Shift Schedule (`Shift_Schedule__c`, 29T), Volunteer Letter Template (`Volunteer_Letter_Template__c` and the shipped `Volunteer_Letter_Template_Default__mdt`, 29U) and the volunteer hours import template (29V). Rules R-SK, R-VK, R-VQ, R-SSC, R-VL and R-VH. Core: `Import_Template_Default__mdt` gains `Target_Object__c`, `Load_Operation__c` and `Load_Match_Field__c`, and new rule R-D3 says how a one-object template is materialized. Section 13 now says `Rollup_Definition_Default__mdt` belongs to the Rollup Builder module (ADR-0125); Sections 30 and 32 move Programs to v0.9. Specified ahead of the build; no metadata yet. |

---
## 32. Entity ownership by package
One row per entity in the model, so a contributor or an agent can tell at a glance which
package owns a thing and which iteration creates it. Package configuration entities are
included; standard objects the packages extend are named by the entity that governs them.
| Entity | Package | Iteration | Section |
|---|---|---|---|
| Household (Account, record type Household) | Core | v0.1 | 5 |
| Household Member | Core | v0.1 | 6 |
| Contact | Core | v0.1 | 7 |
| Organization (Account, record type Organization) | Core | v0.1 | 8 |
| Error Log | Core | v0.1 | 9 |
| Automation Setting | Core | v0.1 | 10 |
| Setting Change | Core | v0.1 | 11 |
| BarnCRM Settings | Core | v0.1, extended v0.2, v0.3, v0.5 and v0.6 | 12 |
| Naming Pattern (shipped default) | Core | v0.1 | 13 |
| Automation Registry (shipped default) | Core | v0.1 | 13 |
| Rollup Definition | BarnCRM Rollup Builder (Core until ADR-0125) | v0.2, moved 2026-10-14 | 14 |
| Rollup Queue | BarnCRM Rollup Builder (Core until ADR-0125) | v0.6 (rollup engine), moved 2026-10-14 | 14A |
| Rollup Run Lock | BarnCRM Rollup Builder (Core until ADR-0125) | v0.6 (rollup engine), moved 2026-10-14 | 14A |
| Rollup Queue Ready (platform event) | BarnCRM Rollup Builder (Core until ADR-0125) | v0.6 (rollup engine), moved 2026-10-14 | 14A |
| Rollup Definition Default (shipped default) | BarnCRM Rollup Builder (Core until ADR-0125) | v0.2, moved 2026-10-14 | 13 |
| Rollup Settings | BarnCRM Rollup Builder | v0.6, keys from v0.2 (ADR-0125) | 14B |
| Import Template | Core | v0.2 | 15 |
| Import Template Default (shipped default) | Core | v0.2 | 13 |
| Import Batch | Core | v0.2 | 16 |
| Import Row | Core | v0.2 | 17 |
| Import Journal | Core | v0.5 | 17A |
| Gift | Giving | v0.2 | 18 |
| Gift Allocation | Giving | v0.2 | 19 |
| Fund | Giving | v0.2 | 20 |
| Appeal | Giving | v0.2 | 21 |
| Giving Settings | Giving | v0.2, keys from v0.3 and v0.4 | 21A |
| Giving rollup target attributes on Account and Contact | Giving | v0.2 | 26 |
| Commitment | Giving | v0.3 | 22 |
| Installment | Giving | v0.3 | 23 |
| Soft Credit | Giving | v0.3 | 24 |
| Tribute | Giving | v0.3 | 25 |
| Relationship | Core | v0.3 | 27 |
| Relationship Type (shipped default) | Core | v0.3 | 13 |
| Affiliation | Core | v0.3 | 28 |
| Address | Core | v0.3 | 29 |
| Duplicate Dismissal | Core | v0.5 | 29A |
| Saved Query | Core | v0.7 | 29D |
| Field Utilization Snapshot | Core | not scheduled (plan Section 6.1 item 10) | 29F |
| What's New Seen | Core | v0.6 | 12A |
| Release Note (shipped, read as shipped) | Core, records from any package | v0.6 | 13 |
| Interaction Note (Task, no packaged schema) | Core | v0.9 | 29G |
| Erasure | Core | not scheduled (owner decision 2026-10-13) | 29H |
| Acknowledgment Rule | Giving | v0.4 | 25F |
| Acknowledgment | Giving | v0.4 | 25G |
| Acknowledgment Run | Giving | v0.4 | 25H |
| Donor Level | Giving | v0.4 | 25A |
| Receipt | Giving | v0.4 | 25B |
| Receipt Number Sequence | Giving | v0.4 | 25C |
| Receipt Run | Giving | v0.4 | 25D |
| Receipt Template | Giving | v0.4 | 25E |
| Stewardship Plan Template | Giving | v0.4 | 25I |
| Stewardship Plan Step | Giving | v0.4 | 25J |
| Stewardship Plan | Giving | v0.4 | 25K |
| Gift Batch | Giving | v0.5 | 25L |
| Gift Batch Row | Giving | v0.5 | 25M |
| Gift Transaction mirror | Mirror | v0.6 | 30 |
| Opportunity mirror (Opportunity ID on Gift) | Mirror | v0.6 | 29C |
| Campaign sync (Campaign ID on Appeal) | Mirror | v0.6 | 29B |
| Mirror Settings | Mirror | v0.6 | 29B |
| Volunteer profile and volunteer totals on Account and Contact | Volunteers | v0.8 | 29I, 29O |
| Volunteer Job | Volunteers | v0.8 | 29J |
| Volunteer Shift | Volunteers | v0.8 | 29K |
| Volunteer Sign-up | Volunteers | v0.8 | 29L |
| Volunteer Hours | Volunteers | v0.8 | 29M |
| Volunteer Settings | Volunteers | v0.8 | 29N |
| Skill | Volunteers | v0.8 | 29P |
| Volunteer Skill | Volunteers | v0.8 | 29Q |
| Job Skill | Volunteers | v0.8 | 29R |
| Volunteer Requirement | Volunteers | v0.8 | 29S |
| Shift Schedule | Volunteers | v0.8 | 29T |
| Volunteer Letter Template | Volunteers | v0.8 | 29U |
| Volunteer Letter Template Default (shipped default) | Volunteers | v0.8 | 29U |
| Volunteer hours import template (Import Template Default rows) | Volunteers | v0.8 | 29V |
| Programs entities | Programs | v0.9 | 30 |
| Funders entities | Funders | v0.9 | 30 |
| NPSP household adoption | Mirror | v0.9 | 30 |
| Organization legal name and address keys | Core | v0.2 | 12 |
| Default fund and appeal, tax identification number, receipt signer and file keys | Giving (Core until v0.6) | v0.2, moved v0.6 | 21A |

**Components that are not entities (C-29, ADR-0059).** Core is the Standard Edition on its own,
so nothing below that is nonprofit-specific ships in Core.

| Component | Package | Mechanism |
|---|---|---|
| Hub app (labelled BarnCRM), Home, Households, Organizations, Import and Settings tabs | Core | Metadata |
| Fundraising app (the nonprofit app) and its tabs | Giving | Metadata (ADR-0018) |
| Setup Assistant: seven neutral steps (fit, naming, access, identity, modules, data, check) | Core | `SetupAssistantService` |
| Setup Assistant: fund and appeal step, receipt fields and wording of the identity step, first gift check | Giving | `GivingSetupAssistantExtension` through `SetupAssistantExtensions` |
| Health Check: household, access, settings, org shape findings | Core | `HealthCheckService` |
| Health Check: receipt generation, receipt lock override, unposted gifts in a closed period | Giving | `GivingHealthCheckExtension` (ADR-0057) |
| Roles: Admin, Team Member (`Program_Staff`), Coordinator (`Volunteer_Coordinator`), Read Only | Core | Permission set groups |
| Role: Fundraising Staff | Giving | Permission set group |
| Custom permission Manage BarnCRM Settings | Core | Metadata |
| Custom permissions for gifts, receipts, posting and acknowledgments | Giving | Metadata |
| Volunteers app, permission sets, custom permission Manage Volunteers, coordinator dashboard and reports | Volunteers | Metadata (ADR-0127) |

Two rows differ from plan Section 6 because the first customers are now Nonprofit Cloud
orgs: the Gift Transaction mirror is v0.6, brought forward from
v0.9, and NPSP household adoption is v0.9, moved back from v0.6. The plan's roadmap table
is the place that reprioritization is recorded permanently; this table follows it.
