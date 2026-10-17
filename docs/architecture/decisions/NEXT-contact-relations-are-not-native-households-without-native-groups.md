# ADR-NEXT: Contact relations are not native households in an org without native household groups

**Status:** Proposed
**Date:** 2026-10-17
**Source:** test run in an org with Contacts to Multiple Accounts on and no Nonprofit Cloud
(33 household test failures, one root cause); narrows ADR-0036

## Context

ADR-0036 makes the empty household delete guard keep any Account carrying a native household
group (`PartyRelationshipGroup`) or native membership rows (`AccountContactRelation`), and
treats a probe that cannot answer as "yes". `OrgShapeSelector` applied the same "unknown means
yes" rule to the org-wide question, and counted an object absent from the global describe as
unknown.

So every org without Nonprofit Cloud reported possible native households. In a scratch org
that cost nothing, because the membership object is absent too. With Contacts to Multiple
Accounts on (common in Sales Cloud orgs, and permanent once enabled) the platform creates a
direct membership row for every contact, and keeps an indirect one on the account a contact
leaves. Every BarnCRM household with a member then read as a Nonprofit Cloud household:
names and greetings never updated, addresses did not flow, junction memberships were not
created, emptied households were never tidied, and import undo kept imported people. The
platform also refuses to merge two accounts that share a related contact, and a household
merge always creates one (the moved person is direct on the survivor and indirect on the
other household), so every household merge failed.

## Decision

1. **An object the org does not have is a known "no", not an unknown.**
   `OrgShapeSelector` counts zero native households when `PartyRelationshipGroup` is absent
   from the global describe. A described object the running user cannot read, or a query
   that fails, is still unknown, and unknown is still "yes" (ADR-0036 unchanged there).
2. **Native membership rows count as a native household signal only in an org that has
   native household groups** (`OrgShapeDetector.hasNativeHouseholdGroups`, unknown counting
   as yes). `HouseholdSelector.getAccountsWithNativeDependents` asks about membership rows
   only then; the group itself is always asked about, because it is cascade-deleted with the
   Account whatever the org's shape. The merge and duplicate guards already ignored
   membership rows.
3. **A household merge removes the relations that would block it.** Before
   `Database.merge`, for each contact related to both households, the indirect relation is
   deleted: the one on the household going away by preference, otherwise the one on the
   survivor. The rows are read in system mode (upkeep read, ADR-0021) and deleted in user
   mode; a refusal is logged and stops the merge, and the throw rolls the member move back.
4. **Import undo does not count the platform's own membership row as something gained.**

## Alternatives considered

- **Keep "absent means unknown" and only stop counting membership rows.** Rejected: Health
  Check would still report "could not count" native households on every Platform-only org,
  and any later guard reading the shape would repeat the mistake.
- **Ignore membership rows everywhere.** Rejected: in a Nonprofit Cloud org they are what a
  native household's membership is made of, and the delete guard needs them there.
- **Refuse the merge when relations are shared and ask the administrator to remove them.**
  Rejected: every merge in such an org would need manual cleanup that the merge itself made
  necessary.

## Consequences

- Residual risk, named rather than hidden: the global describe is filtered by the running
  user's permission set licences, so in a Nonprofit Cloud org a user without the licence can
  see no `PartyRelationshipGroup` at all and the org then reads as having no native
  households for that transaction. `HouseholdSelector` already named this risk for the
  delete guard. A user with the licence but without the Group Membership permission set
  still sees the object and stays on the cautious side.
- A merge in an org with Contacts to Multiple Accounts deletes the indirect relation of each
  shared contact, with any role or dates recorded on it. The surviving relation remains.
- Tests simulate membership rows through `HouseholdSelector.nativeMembershipAccountsOverride`
  and `nativeMembershipRowsOverride`, since the object is absent in scratch orgs. A scratch
  shape with Contacts to Multiple Accounts on would test the real platform behaviour; adding
  one is left to the owner, because the setting cannot be turned off.
