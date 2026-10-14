# ADR-0079: Data hygiene checks are Find queries built at request time

**Status:** Accepted (builder decision)
**Date:** 2026-10-12
**Source:** plan Section 6 row C-28 ("Data hygiene console (orphans, missing households, bad
addresses)", "Uses C-34 saved queries"); plan Section 4.8 (Health Check, orphaned records);
builds on ADR-0021, ADR-0047, ADR-0048 and
`0076-saved-queries-are-private-and-shared-by-apex-managed-sharing.md`

## Context

C-28 asks for one page that finds orphans, people with no household and bad addresses, built
on the saved queries of Find (C-34). Health Check (C-21, ADR-0048) already reports people with
no household and empty households, with a capped count and five links, and says bulk cleanup
belongs to C-28. Four questions needed an answer:

1. Where a check's query lives: shipped records, shipped metadata, or built in code.
2. How a count and the list Find shows are kept in agreement.
3. How "Open in Find" reaches Find, which (as built in C-34) opens a saved query from its own
   list and reads no page state, and which this branch may not change because Bulk update
   (C-35) is being built on it in parallel.
4. What to do with a check Find cannot express: Find has no conditions on child records.

## Decision

- **Built in Apex at request time.** `DataHygieneService` holds the checks. Each check builds
  its R-SQ1 query document when it is counted or opened: API names come from schema tokens
  (so a namespace added later is carried automatically), the household record type is
  matched by developer name through `RecordType.DeveloperName`, and the document depends on
  the org's membership mode where the question does. Nothing is shipped as a record, custom
  metadata row or static resource, so a check cannot be edited, deleted or left stale by an
  upgrade: read only by construction.
- **One document, counted and listed.** The count is `SELECT COUNT()` over the same document:
  the object is checked with `QueryFieldCatalog`, the filter is rendered by
  `RollupFilterParser.toBoundClause` (every value bound, every field from the running user's
  describe), and the query runs through `Database.countQueryWithBinds` with
  `AccessLevel.USER_MODE`. It stops at 2,000 (`QueryCompiler.MAX_ROWS`) and says "more than".
  A check whose object or field the user cannot see shows the refusal instead of a number.
  The count therefore matches what Find lists for the same person.
- **Open in Find saves the person's own copy.** The console writes the document as a
  `Saved_Query__c` owned by the person, unshared, named "Data hygiene: " plus the check name,
  updating their existing copy of that name if there is one, in user mode through
  `FindController.saveQuery` (so it is compiled, checked and stored exactly as Find stores a
  query). It then navigates to the Find tab with `c__savedQueryId` in the page state. Find
  today ignores that state and the person picks the query from **Saved queries**; reading it
  so Find opens the query directly is a small follow-up to `findRecords` once C-35 has merged.
  (Follow-up done since: `findRecords` reads the state key, opens the saved query and runs it.)
- **Gated by the Find permission.** Every console action requires `Find_And_Export_Records`.
  The console is a way into Find and adds no access of its own, so no new permission.
- **Empty households read Member Count.** A household is counted when its `Member_Count__c`
  is zero or empty (R-H11), which Find can express, rather than by reading memberships, which
  it cannot. It differs from Health Check only while a Member Count is stale.
- **A check Find cannot express is counted without the Find action.** People with no
  household in junction mode means "no current Household Member row", a child condition. Its
  count reuses `HouseholdOrphanSelector`, exactly as Health Check counts it, and the row says
  Find cannot list it yet (C-36). A check that is not a query at all is not offered: whether a
  household name still matches the naming rule needs every name recomputed.
- **The checks.** People with no household, households with nobody in them, memberships that
  name nobody (R-M4), addresses that belong to nobody (R-AD1, owner deleted), default
  addresses missing a street, city or postal code, and default addresses whose verification
  failed (R-AD6). All Core, none naming Giving or Connect.
- **Health Check keeps its two findings.** It answers "is BarnCRM set up right" with
  headline counts and five links; the console answers "which records need tidying" with full
  lists. The admin guide pages say so, and Health Check's page points to the console.

## Alternatives considered

- **Ship package-owned saved queries (records created by the post-install script).** Rejected:
  a Saved Query is owned by a person and private (R-SQ4), so a shipped one would need an owner,
  a share and an upgrade path; a stored document would also hold API names fixed at install
  and one membership mode, and an admin could edit or delete it.
- **Ship the documents as custom metadata or a static resource.** Read only, but the names are
  fixed text (no namespace safety), the mode-dependent check needs two rows and a selector,
  and the record type still needs resolving in code. More moving parts for the same result.
- **Pass the document to Find in the page state.** Simplest for the person, but Find would
  have to accept a query document from a URL, and `findRecords` may not change on this branch.
  Recorded as the follow-up above, with a saved query Id rather than a document.
- **Show the records in the console itself.** Rejected: it duplicates Find's grid, export and
  the start of Bulk update.
- **Move Health Check's two orphan findings to the console.** Out of scope here and would
  change C-21's shipped behaviour; recorded as a question for the owner instead.

## Consequences

- Each "Open in Find" writes or updates one Saved Query owned by the person. Pressing it again
  resets that copy to the check's query; the admin guide says to use Save as to keep changes.
- The count and the Find list agree for the same person. Two people may see different counts.
- Adding a check is one method in `DataHygieneService`, its labels and its admin guide row.
- `findRecords` reading `c__savedQueryId` was a recorded follow-up (after C-35 merges). It is
  done: Find opens and runs the saved query the link names.
