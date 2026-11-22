# ADR-NEXT: Plain Child Lists on Module Record Pages Are Dynamic Related Lists

**Status:** Accepted
**Date:** 2026-11-22
**Source:** plan D-219 (adopt newer GA platform features where they do not hinder adoption),
release 1.36 item PF-01. Extends ADR-0097 (record pages own their actions and lists) from
Giving to every module record page.

## Context

ADR-0097 made the lists on Giving's own record pages Dynamic Related Lists
(`lst:dynamicRelatedList`) with set columns and sort, and kept every custom panel that does
something a list cannot. PF-01 asked for the same on the other module record pages: any custom
LWC panel whose only job is to list child rows should become a Dynamic Related List, and its
Apex should go.

An audit of every `RecordPage` FlexiPage in `packages/*/main/default/flexipages` on
2026-11-22 found no custom panel that only lists rows. Each one has a behavior a Dynamic
Related List cannot give:

- `personEnrollments` (Programs on a person): reads a contact or a person account through two
  lookups, hides on a household or organization, shows the last service line and Enroll.
- `householdOfPerson`: reads households through the membership junction, with member counts
  and the formal greeting.
- `grantDocuments`: each requirement's latest file and version, with upload.
- `grantRenewals`: the renewal chain across years, with Start Renewal.
- `eventTickets`, `eventBudget`, `grantBudget`, `grantReport`, `rollupExplain`,
  `volunteerReadiness`: computed totals, warnings or row actions.
- Every other placed panel (rosters, sign-ups, schedules, sponsors, speakers, soft credits,
  allocations) adds, edits or removes rows.

The Grant page did have three plain lists, but as the older **Related List - Single**
(`force:relatedListSingleContainer`), whose columns come from whatever Grant layout a profile
has and cannot be sorted on the page.

## Decision

- **A plain list of a record's child rows on a module record page is a Dynamic Related List**
  (`lst:dynamicRelatedList`) with set columns, sort, ten rows and the action bar, never a custom
  panel and never the layout-driven Related List - Single.
- **The Grant page's Grant Payments, Restricted Fund Entries and Grant Requirements lists move
  to Dynamic Related Lists** with the columns of the Grant layout's related lists. Payments and
  requirements sort soonest due first; fund entries newest first.
- **Every audited custom panel stays**, for the reason listed in Context. No LWC or Apex method
  is removed by this decision.
- **The related list container stays** on each page for the org's own lists, as ADR-0097 says.

## Alternatives considered

- **Replace panels that are mostly lists anyway** (for example `personEnrollments`, dropping
  the last service line). Rejected: removes functionality, and a person account reads through a
  second lookup that one Dynamic Related List cannot follow.
- **Leave the Grant lists as Related List - Single.** Rejected: the page then shows whichever
  columns a profile's layout has, the dependency ADR-0043 and ADR-0097 removed elsewhere.

## Consequences

- Columns respect field-level security: a column the user cannot read is not shown.
- A column an admin adds to the Grant layout's related list no longer reaches the packaged
  page; the admin guide says to edit the list in Lightning App Builder.
- A new module panel that only lists rows is refused in review in favor of a Dynamic Related
  List (plan Section 9.4).
