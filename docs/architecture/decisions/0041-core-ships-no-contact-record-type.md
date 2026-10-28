# ADR-0041: Core ships no Contact record type

**Status:** Accepted
**Date:** 2026-09-23
**Source:** product owner decision (Brandon), plan Section 4 "Record types"
**Amended by:** ADR-NEXT (D-134): Account keeps one packaged record type, Household; the
  Organization record type is no longer shipped.

## Context

Core shipped one Contact record type, `Household_Contact`, with its own compact layout, a
list view that filtered on it, and visibility in the three Nonprofit permission sets. Its
description said it existed "so that an org can add its own without colliding with ours".
That reason does not hold: record types never collide, and an org can add Contact record
types whether or not a package ships one.

Nothing depended on it. No trigger, service, rule or page branched on a person's record
type. The sample data loader was the only code that set it, and the only effect of the
record type on a live org was an extra step (a record type picker) when a user created a
person, plus one more thing an administrator had to make visible in every profile.

## Decision

- Core ships no Contact record type. The Household Contact record type, its compact layout
  `Household_Contact_Compact`, and the list view `All_Household_Contacts` are removed.
- Package code never sets or reads a Contact's record type. A person gets the creating
  user's default, which is whatever the org has chosen.
- Account keeps its two record types, Household and Organization, because household naming,
  greetings, merge and the sample data all branch on them.
- The Contact record page, renamed from `Household_Contact_Record_Page` to
  `Contact_Record_Page`, is assigned to Contact without a record type.

## Alternatives considered

- **Keep it, unused.** Rejected: it gave no function, cost every installing administrator a
  visibility decision, and a packaged record type is hard to remove once a version ships.
- **Keep it and make code use it**, for example to tell people from other contacts. Rejected:
  no rule needs that distinction, and an org that wants it can add its own record type.

## Consequences

- Removal before the first package version costs nothing in subscriber orgs. The test org
  needs a destructive deploy of the record type, compact layout and list view.
- A person's highlights panel shows the org's own Contact compact layout.
  `Primary_Affiliation__c` stays on the Contact page layout.
- The `Household_Role__c` values the record type listed are all active on the master record
  type, so no picklist value is lost.
