# ADR-0036: An empty household is deleted only when nothing outside BarnCRM depends on it

**Status:** Accepted
**Date:** 2026-09-09
**Source:** builder decision under plan Section 9.3; refines canonical model R-H12, constrained by ADR-0009, ADR-0013 and ADR-0021

## Context

R-H12 says the vacated household is deleted when it is empty and `Delete_Empty_Households__c`
is on. Until now "empty" was decided from BarnCRM's own membership alone: the record type
is Household, `HouseholdService.getMembers` returns nothing, so the Account goes.

That is the whole of the test, and in an org running Salesforce Nonprofit Cloud it is the wrong
test. A household there is a business Account plus a `PartyRelationshipGroup` record, and its
membership is carried on `AccountContactRelation` rows. BarnCRM owns neither object and
counts neither as a member, so such a household reads as empty on the first day it exists.

`PartyRelationshipGroup.AccountId` is a master-detail to Account with no Update property
(verified against the object reference, recorded in
`docs/architecture/reference/nonprofit-cloud-data-model.md` section 8 item 7). Deleting the
Account therefore does not orphan the native household group, it cascade-deletes it, and the
membership rows go with it. The trigger for that deletion is somebody moving one contact out of
one household: an ordinary edit, made by somebody with no idea that a second household model
exists on the same record.

Two constraints shape any fix. Core has to compile and deploy on a Platform-only org
(ADR-0009, ADR-0013), where neither object exists, so neither name may appear in a
compile-time expression. And a guard that reads with the saving user's own access answers
"nothing depends on this" for every row that user cannot see, which is exactly the wrong
answer to give a delete.

## Decision

**An empty household is deleted only when nothing outside BarnCRM depends on the Account.**
Before deleting, `HouseholdService.deleteEmptyHouseholds` asks
`HouseholdSelector.getAccountsWithNativeDependents` for the accounts that carry a child
`PartyRelationshipGroup` or any `AccountContactRelation` rows, and deletes only the rest.

- Both object names are `String` constants carrying the `// detection-only:` marker
  `scripts/ci/check-standard-objects.sh` requires, and both probes are dynamic queries run
  through `Database.query`, the pattern `OrgShapeSelector` already uses. Each probe checks
  `Schema.getGlobalDescribe()` for the object and checks that it is accessible before querying
  it. An object the org does not have contributes nothing: absence is not a dependency.
- A probe that fails for any other reason reports every account it was asked about as
  dependent. Not being able to answer is not the same as answering no, and the two mistakes do
  not cost the same.
- The probe is an upkeep read under ADR-0021 and runs in system mode. Its four conditions are
  argued in the method header: package upkeep is its only caller, its only input is a set of
  identifiers upkeep computed for itself, it reads one identifier field per object, and it
  elevates nothing else.
- **A household left in place is reported, not swallowed.** It is logged to the Error Log at
  `Info` severity, naming the household and its record identifier, through
  `Core_Households_SkippedNativeDependents`. It is not an error: it is the correct outcome, and
  the administrator who finds an empty household still on their list is owed the reason.

The guard is about the Account, not about Nonprofit Cloud. These two objects are the dependents
that exist today; another one found later is added to the same probe and needs no new decision.

## Alternatives considered

- **Detect the org shape once and switch the setting off there.** Rejected: the shape is a
  property of the org and the hazard is a property of the record. An org can be Platform-only
  and still have a household somebody built a native group on, and a Nonprofit Cloud org has
  plenty of households where the tidy-up is safe and wanted.
- **Delete the group first, then the Account.** Rejected outright. BarnCRM does not own
  that data, and a tidy-up is not a licence to destroy somebody else's household.
- **Refuse to delete anything when the objects exist at all.** Rejected: it turns the setting
  off for a whole class of org on the strength of an installed package, which is the shape of
  answer plan Principle 2 warns against, and it hides the households that really were empty.
- **Log the skip as an error.** Rejected: it is a correct outcome, and an Error Log full of
  correct outcomes is an Error Log nobody reads.
- **Do nothing and document the hazard.** Rejected: the hazard is silent, destructive, and
  reached by an ordinary contact edit.

## Consequences

- In a Nonprofit Cloud org, `Delete_Empty_Households__c` tidies up less than it used to, and
  says so each time. The admin guide and the setting's own description say so too.
- Two more Nonprofit Cloud object names live in Core as detection-only String constants, which
  the CI gate prints on every run for a reviewer to read.
- One more dynamic query pair per batch of emptied households, asked once for the whole batch.
- The probe cannot be exercised against real Nonprofit Cloud objects in an Apex test, so it is
  injectable through `HouseholdSelector.accountsWithNativeDependentsOverride` and both outcomes
  are tested against the injected answer. What is untested is the query text itself, which has
  to be verified in a Nonprofit Cloud org before X-07 ships.
- If a later object turns out to depend on the household Account in the same way, it joins the
  same probe. This decision does not need revisiting for that.
