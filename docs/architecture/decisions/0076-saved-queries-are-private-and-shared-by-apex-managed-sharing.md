# ADR-0076: Saved queries are private and shared by Apex managed sharing

**Status:** Accepted (builder decision)
**Date:** 2026-10-12
**Source:** plan Section 4.9 (Find, C-34: "save the query, share it with other users of the
tool"); builds on ADR-0021 and ADR-0047

## Context

Find (C-34) lets a person save a query and share it with everyone else who uses Find. A query
names no records, but it can carry what someone was looking for ("Last Name equals Smith",
"Major donors to review"), and a person who has not shared a query expects nobody else to see
it. The plan asks for a shared flag. The question is what makes an unshared query private and
a shared one readable by others, inside a managed package, with no Setup steps (plan Section
2.3). Sharing rules are not shipped by this project, and a criteria-based sharing rule would be
a Setup-managed piece of configuration the admin can break without knowing.

## Decision

- `Saved_Query__c` ships with the Private sharing model. The owner reads and edits their own
  queries through ordinary user-mode access.
- Sharing is an Apex managed share: one `Saved_Query__Share` row with the reason
  `Shared_With_Find_Users`, granting Read to the org's All Internal Users group. `Shared__c`
  is the flag the person sees; the share row follows it.
- Only the owner may set or clear `Shared__c`. `FindController` checks ownership and the
  `Find_And_Export_Records` permission first, then calls `SavedQuerySharingWriter`, which
  runs `without sharing` and inserts or deletes the share row. This is the only system-mode
  write in Find, of the kind ADR-0021 allows: package-owned data, reached only after the
  caller is authorized, inputs validated, header comment naming this ADR. Inserting a share
  with an Apex sharing reason needs system mode, because users cannot create such shares.
- Everything else (list, open, save, delete, run, export) is user mode. A shared query runs
  with the reader's own access.

## Alternatives considered

- **Public Read Only and the flag only filters the list.** Simplest, with no system-mode code.
  Rejected: an unshared query would still be readable by every user through reports, list
  views and the API, which is not what "not shared" means to the person who saved it.
- **A `without sharing` read of rows where Shared is true.** One small system-mode read
  instead of a write. Rejected: it bypasses the platform's own record access, so reports and
  list views would disagree with Find about who can see a query.
- **A criteria-based sharing rule on Shared.** Declarative, but sharing rules are org
  configuration an admin can edit or delete in Setup, and this project ships none.

## Consequences

- One `without sharing` class (about 40 lines) to keep in the security review notes, next to
  ADR-0021's writers.
- An owner change keeps Apex managed shares, so a reassigned shared query stays shared; the
  new owner may unshare it.
- The All Internal Users group includes users without the Find permission; they gain Read on
  the query record, which holds no records and grants no record access, and they cannot open
  Find. Accepted rather than adding a group that would need membership upkeep.
