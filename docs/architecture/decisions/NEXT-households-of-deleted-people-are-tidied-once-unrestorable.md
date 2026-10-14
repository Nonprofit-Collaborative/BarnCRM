# ADR-NEXT: A household emptied by deleting people is tidied once they cannot be restored

**Status:** Accepted
**Date:** 2026-10-14
**Source:** product owner decision (Brandon, 2026-10-14, plan Section 12 decision D-89);
amends D-88 (R-H12, deleting people never deletes their household); builds on ADR-0036,
ADR-0070 and ADR-0075; canonical model R-H12a

## Context

D-88 stopped a person delete from deleting the household it empties. Probes on `oi-test`
showed that deleting a household purges from the Recycle Bin every contact deleted from it
before it (`Contact.AccountId`) and every membership row naming it (`Household_Member__c.Household__c`
is a cascade lookup), so the people could no longer be undeleted, nor brought back by the bulk
delete undo. The cost of D-88 is a list of empty households that grows with every delete.

D-89 asks for those households to go to the Recycle Bin, but only once the people they held
can no longer be restored anyway, so that D-88's protection is never traded away.

Three questions shape the answer: which empty households were emptied by deleting people
rather than by a move or a merge, how to know the former members are gone for good, and how
Core, which may not name Giving's objects, knows nothing else still points at the household.

## Decision

**A person delete stamps the household it empties, and a nightly batch tidies stamped
households whose former members have left the Recycle Bin.**

- **The stamp.** `Account.Emptied_By_Deletion__c` (Date) is set by the household settle-up when
  a person delete (contact or person account, not a merge) leaves a household with no members,
  and cleared by any later settle-up that finds a member. Only a stamped household is ever a
  candidate, so a household emptied by a move stays under `Delete_Empty_Households__c`, a
  household a merge emptied stays for a person to merge, and a household that never had members
  is left alone.
- **Former members gone for good.** The batch reads, with `ALL ROWS`, the deleted Contacts whose
  `AccountId` is the household and the deleted `Household_Member__c` rows whose `Household__c` is
  the household. Those two sets are exactly what a delete of the household would purge, and both
  fields survive a soft delete, so an empty answer means no restorable record is lost by the
  delete. Both are read in every membership mode. While either set is non-empty the household is
  kept quietly and asked about again the next night; the Recycle Bin empties itself in 15 days.
- **Nothing else points at it.** Live Contacts or membership rows (current or ended) keep the
  household. Then the ADR-0036 probe, the ADR-0070 extension point, and a generic probe built from
  `Account` child relationship describe: one subquery per relationship, grouped, `LIMIT 1` each,
  in system mode. Shares, field history and feed records are bookkeeping of the household itself
  and are skipped; every other relationship, Core's or a module's or a customer's, keeps the
  household. A relationship that cannot be read keeps every household in the chunk and is
  logged: not being able to answer is not answering no.
- **Kept households are reported where empty households already are.** They stay on Health
  Check's and Data Hygiene's lists of households without members. No Error Log entry: keeping
  them is a correct outcome.
- **The setting.** `Keep_Households_Of_Deleted_People__c`, in the Households section of the
  settings console, shipped false. It is inverted on purpose: an org that has saved its settings
  gets false for a new checkbox on upgrade, and ADR-0035's first-save defaults reach only an org
  that has never saved, so a positive checkbox shipped on would be off in every upgraded org.
- **The schedule.** `EmptyHouseholdTidyScheduler` runs `EmptyHouseholdTidyBatch` nightly at
  1:45, listed in `NightlyJobs` so Health Check's one fix schedules it (ADR-0075). Deletes are
  soft (`Database.delete`, all-or-none off) in system mode; a refused delete is one Error Log
  entry per chunk; counts go to the debug log, since a scheduled run notifies nobody.

## Alternatives considered

- **Tidy every empty household whose bin is clear.** Rejected: it would override an org that
  left `Delete_Empty_Households__c` off for moves, and delete households that never had members.
- **Delete the household with the people and accept the purge.** Rejected by D-88.
- **Wait a fixed number of days.** Rejected: an administrator can empty the Recycle Bin early or
  restore late; reading the bin answers the actual question.
- **Name Giving's objects or rely on the extension alone.** Rejected: Core is neutral (ADR-0059),
  and a customer's own lookup to Account is just as much a dependent as a gift.
- **A positive setting with an upgrade step in `CorePostInstall`.** Rejected: the install path
  cannot tell an org that switched it off from one that never saw it, and ADR-0035 rejected DML
  in the install path for something a read can answer.

## Consequences

- Households emptied before this ships have no stamp and are not tidied.
- A household with anything at all pointing at it, including its own addresses or an old import
  row, is kept; the generic probe is conservative by design and costs a household on a list, not
  data. Import rows age out under R-IR5, after which the household is tidied.
- The generic probe adds a few queries per chunk; the chunk is 100 households so the subquery
  rows stay well under the limits at any org size.
