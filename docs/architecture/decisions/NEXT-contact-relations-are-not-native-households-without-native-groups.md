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

1. **For the paths that only leave a household alone, an absent object is a "no".**
   `OrgShapeSelector` counts zero native households when `PartyRelationshipGroup` is absent
   from the global describe, so naming, greetings, addresses and memberships run. A
   described object the running user cannot read, or a query that fails, is still unknown,
   and unknown is still "yes" (ADR-0036 unchanged there).
2. **For the paths that delete, absence is not enough.** The global describe is filtered by
   the running user's permission set licences, so a user without the Nonprofit Cloud licence
   (or an automated user) may not see the object in an org that has it. No licence-neutral
   signal was confirmed: `EntityDefinition` reports the object to an administrator in a
   Nonprofit Cloud org and not in a Platform-only org, but whether it is filtered the same
   way for an unlicensed user could not be tested read-only. So
   `HouseholdSelector.getAccountsWithNativeDependents` (empty household delete guard, tidy
   batch, import undo account pass) leaves out membership rows only when the object is
   described and the probe counted none of it; otherwise the rows stay the backstop. The
   group itself is always asked about. The merge and duplicate guards already ignored
   membership rows.
3. **A household merge removes the relations that would block it, only where native
   households are ruled out for naming** (`hasNativeHouseholdGroups()` false). Before
   `Database.merge`, for each contact related to both households, the indirect relation is
   deleted: the one on the household going away by preference, otherwise the one on the
   survivor. Rows are read in system mode (upkeep read, ADR-0021) and deleted in user mode.
   Where native households may exist, membership rows can carry roles, dates and fields of
   their own, so nothing is deleted and the merge fails with its plain message. Any failure
   rolls back to a savepoint taken before the member move, is logged, and stops the merge.
4. **Import undo does not count the platform's own membership row as something gained**,
   on the same condition as 3.

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

- **Tidy-up in an org with Contacts to Multiple Accounts and no Nonprofit Cloud** (for
  example mwdbdevsb): a household emptied by a move keeps the indirect relation the platform
  leaves on it, so the empty household delete guard and the tidy batch keep it and log it at
  Info, as ADR-0036 does for any dependent. Import undo likewise keeps an imported household
  that still has relation rows. Naming, addresses, memberships, merges and the import undo
  contact pass work. Revisit if a licence-neutral existence signal is confirmed (for example
  `EntityDefinition` read by an unlicensed user in a Nonprofit Cloud org).
- Residual risk for the non-deleting paths: in a Nonprofit Cloud org, a user who cannot see
  the object at all reads the org as having no native households for that transaction, so
  naming or an address save could touch a native household, and a merge could delete shared
  indirect relations. A user with the licence but without the Group Membership permission
  set still sees the object and stays on the cautious side.
- A merge in an org with Contacts to Multiple Accounts and no native households deletes the
  indirect relation of each shared contact, with any role or dates recorded on it. The
  surviving relation remains.
- Tests simulate membership rows through `HouseholdSelector.nativeMembershipAccountsOverride`
  and `nativeMembershipRowsOverride`, since the object is absent in scratch orgs. A scratch
  shape with Contacts to Multiple Accounts on would test the real platform behaviour; adding
  one is left to the owner, because the setting cannot be turned off.
