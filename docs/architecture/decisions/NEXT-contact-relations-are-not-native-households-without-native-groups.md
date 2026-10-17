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
3. **A move removes the relation it left behind, by a content test, not an org-shape test.**
   When BarnCRM changes a contact's account (`HouseholdService` contact mode move and join),
   it then removes the relation between that contact and the household it just left, only
   if the row is now indirect (it was the contact's own account until this move, so this
   move turned it) and nobody recorded Roles, StartDate or EndDate on it. Any other row
   stays. Rows are read in system mode (upkeep read, ADR-0021) and deleted in user mode; a
   row the platform will not remove stays and the delete guard keeps the household. This
   restores the empty household tidy-up where Contacts to Multiple Accounts is on, through
   the unchanged guard in 2.
4. **A household merge deletes nothing of its own.** Its member move applies 3. If any
   person is then still related to both households (a relation somebody made or
   annotated), the merge is refused with the plain existing message, and everything rolls
   back to a savepoint taken before the move. No org-shape gate: the content test is the
   guard.
5. **Import undo does not count the platform's own membership row as something gained**
   where `hasNativeHouseholdGroups()` is false.

## Alternatives considered

- **Keep "absent means unknown" and only stop counting membership rows.** Rejected: Health
  Check would still report "could not count" native households on every Platform-only org,
  and any later guard reading the shape would repeat the mistake.
- **Ignore membership rows everywhere.** Rejected: in a Nonprofit Cloud org they are what a
  native household's membership is made of, and the delete guard needs them there.
- **Delete every shared indirect relation before a merge, where native households are ruled
  out.** Rejected in review: the org-shape answer can be wrong for a user who cannot see the
  object, and even in an org without Nonprofit Cloud such rows can carry roles and dates an
  administrator entered.
- **Refuse every merge with a shared relation.** Rejected: the member move creates one every
  time, so every merge would need manual cleanup that the merge itself made necessary.

## Consequences

- **Tidy-up in an org with Contacts to Multiple Accounts and no Nonprofit Cloud** (for
  example mwdbdevsb) works again for households emptied by a BarnCRM move. A household that
  still has a relation somebody made or annotated, or one emptied by an edit made outside
  BarnCRM's move (for example changing a contact's account on the record page), is kept and
  logged at Info, as ADR-0036 does for any dependent. Import undo likewise keeps an imported
  household that still has relation rows. Revisit if a licence-neutral existence signal is
  confirmed (for example `EntityDefinition` read by an unlicensed user).
- A merge refused over a relation somebody made needs that relation removed by hand first.
- Residual risk for the non-deleting paths: in a Nonprofit Cloud org, a user who cannot see
  the object at all reads the org as having no native households for that transaction, so
  naming or an address save could touch a native household. A user with the licence but
  without the Group Membership permission set still sees the object and stays cautious.
- A move removes an unannotated indirect relation it created in any org, Nonprofit Cloud
  included; the relation existed only because of that move.
- Tests simulate membership rows through `HouseholdSelector.nativeMembershipAccountsOverride`
  and `nativeMembershipRowsOverride`, since the object is absent in scratch orgs. A scratch
  shape with Contacts to Multiple Accounts on would test the real platform behaviour; adding
  one is left to the owner, because the setting cannot be turned off.
