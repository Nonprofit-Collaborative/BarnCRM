# ADR-0134: A household merge runs in system mode once BarnCRM has authorized it

**Status:** Accepted (owner decision, Brandon, 2026-10-25)
**Date:** 2026-10-25
**Source:** QA finding U2 (household merge fails for BarnCRM staff); extends ADR-0021 and
departs from its rule that household record deletes stay in user mode (ADR-0021, ADR-0109)

## Context

A household merge (C-09, canonical model R-H13) ends with the platform's own account merge,
so that activities, files, notes and every lookup any package points at the household follow
it to the survivor. That merge deletes the household that goes away. It ran in
`AccessLevel.USER_MODE`, so it needed Delete on Account, and under sharing it needed delete
access to that one record, which only its owner and the owner's managers hold.

The BarnCRM Staff permission set grants Edit on Account and deliberately not Delete. C-09
decided that anyone who can edit both households may merge them, with no separate permission.
The two did not agree: every staff member was refused with "The two households could not be
combined, so nothing was changed", unless their profile happened to grant Delete on Account.

ADR-0021 allows system mode only for package owned values, and `HouseholdWriter` and ADR-0109
keep household deletes in user mode because a household is a record people own.

## Decision

The owner decided not to grant Delete on Account or Contact to any staff role. Instead the
platform merge of two households runs in `AccessLevel.SYSTEM_MODE` and `without sharing`, in
one dedicated class, `HouseholdMergeWriter`, which carries a header naming ADR-0021 and this
ADR. It is reached only from `HouseholdMergeService.mergeHouseholds`, after:

- the two records are read in user mode and confirmed as two different BarnCRM households
  that are not Nonprofit Cloud households;
- the person holds Edit on Account (BarnCRM Staff and BarnCRM Admin grant it);
- the platform's record access view (`UserRecordAccess`, read in user mode) reports edit
  access to both households, so sharing still decides which households a person may merge;
- on the Duplicates panel, the person also holds `Manage_BarnCRM_Settings`.

Everything else in the merge stays in user mode: moving the people, writing the chosen field
values, and every read a screen shows. A person who could not edit a household cannot merge
it away.

Merging two people is unchanged. It is Salesforce's own Compare and merge, which BarnCRM does
not run, and Salesforce allows it only to people with Delete on Contact (or on Account, for
person accounts). Staff ask an admin.

## Alternatives considered

- **Grant Delete on Account to BarnCRM Staff.** Rejected by the owner: it lets staff delete any
  household or organization they can edit, which is far wider than combining two households.
- **A new custom permission for merging.** Adds a permission to hand out for work C-09 already
  decided belongs to anyone who can edit both records, and would still need system mode.
- **Keep user mode and document the Delete requirement.** Leaves the feature broken for the
  roles it is built for.

## Consequences

- Staff merge households with no Delete permission. The platform still records the merge in
  the survivor's history.
- `HouseholdMergeWriter` joins the ADR-0021 writers that security review reads against that
  ADR's conditions, with this ADR's checks in place of "package owned values only".
- A person whose sharing gives edit but not delete access to a household can now merge it
  away. That is the C-09 rule (edit access to both is enough), now enforced as written.
