# ADR-0142: BarnCRM Admin Keeps View All and Modify All on Account and Contact

**Status:** Accepted (owner decision, 2026-10-28)
**Date:** 2026-10-28
**Source:** pre-AppExchange security review of 2026-10-28, finding C-M2; owner decision
(Brandon, 2026-10-28: "agree" to keeping the grant with a written justification).

## Context

The packaged `BarnCRM_Admin` permission set grants View All and Modify All on `Account` and
`Contact`. Those are standard objects, so the grant overrides the subscriber org's sharing model
for every person, household and organization, not only the ones BarnCRM created. The security
review found no record of why, and AppExchange reviewers treat Modify All on a standard object in
a packaged set as excessive privilege unless the submission explains it.

BarnCRM's data tools run in user mode (plan Section 7.2): Find and its export, Bulk Update, Bulk
Delete, Import updates, Duplicate Matching (scan, review and merge), Erase a Person, and the
household merge and split all read and write with the running user's own access. Household upkeep
(recount, rename, primary contact, address propagation) must also reach members owned by other
users. For the person who configures and cleans the org's data, a private or read-only sharing
model would otherwise leave these tools working on part of the data without saying so: a
duplicate scan that misses the pairs it cannot see, an erasure that leaves records behind, a bulk
fix that skips rows.

## Decision

1. `BarnCRM_Admin` keeps View All and Modify All on `Account` and `Contact`. BarnCRM Staff and
   BarnCRM Read Only never get them.
2. The permission set's description says so, and so does the admin guide's Access page, which
   tells the administrator to give the role only to people trusted with every account and
   contact, and how to hold it back with a muting permission set.
3. The AppExchange submission notes (`docs/contributor-guide/appexchange-submission-notes.md`)
   carry this justification for the reviewer.
4. A new grant of View All or Modify All on a standard object in any packaged set needs its own
   ADR.

## Alternatives considered

- **Drop the grant and move each operation to a system-mode writer** (the ADR-0021 and ADR-0134
  pattern used by `HouseholdMergeWriter`). Rejected: it would turn every data tool into a
  system-mode path, each needing its own exception and caller gate, against the user-mode rule
  the tools are built on, and a reviewer reads many system-mode writers as a larger risk than one
  documented grant to the administrator role.
- **Leave it to each org to grant in Setup.** Rejected: Principle 1 (every setting in the app),
  and the admin role would silently do partial work out of the box.
- **Keep the grant without a record.** Rejected: the review would flag it, and nobody could later
  tell whether it was deliberate.

## Consequences

- Whoever holds BarnCRM Admin can read, edit and delete every account and contact in the org.
  Mitigation: the role is the administrator role, the admin guide and the description say so,
  and an org can mute it.
- The submission must explain the grant; the notes above do.
- Revisit if a BarnCRM tool stops needing org-wide reach, or if a reviewer rejects the
  justification; the system-mode writer alternative is then the fallback.
