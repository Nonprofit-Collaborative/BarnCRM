# ADR-0064: Giving ships the donor record pages, with Dynamic Related Lists for giving

**Status:** Accepted
**Date:** 2026-10-12
**Source:** product owner decision (Brandon), UI/UX review item 2, approved as recommended on
2026-10-12; amends the related-lists rule of ADR-0043 for the giving lists only

## Context

Giving adds about 19 fields to Account and Contact: Total Giving, Last Gift Date, Pledge
Balance, Donor Level, Rollups Last Calculated and the rest. None of them was on any page.
Core ships the Account and Contact record pages (ADR-0043), and Core may never reference
Giving (ADR-0003, ADR-0059), so neither Core's pages nor Core's fallback layouts can place a
Giving field, a Gifts related list or a Giving action. Giving ships no Account or Contact
layout, and none could be assigned anyway (ADR-0043: no profile layout assignments). The
result on a fresh install: David opens a donor and sees nothing they gave, and the record
breaks Principle 2, because the rollups are calculated but "when it was last calculated" is
shown nowhere.

ADR-0043 keeps related lists in the layout, read by the related list container, and
rejected Dynamic Related List components "for now", on cost alone. That reasoning assumes the
package that owns the list also owns the layout. For Gifts, Commitments and Soft Credits on
a donor it does not: the list belongs to Giving and the layout to Core or to the org.

## Decision

- **Giving ships its own Account and Contact record pages**, `Giving_Account_Record_Page` and
  `Giving_Contact_Record_Page`. Each is Core's page, unchanged, plus:
  - a **Giving** field section (Dynamic Forms) holding the giving totals, the donor level and
    **Rollups Last Calculated**, all read only, because the package maintains them;
  - **Dynamic Related List** components (`lst:dynamicRelatedList`) for Gifts, Commitments
    and Soft Credits. On a household the lists read the gifts and commitments credited to
    the household; on an organization, the ones it gave in its own name;
  - a **New gift** action (a standard Create quick action with the donor filled in) placed
    with Dynamic Actions.
- **They are activated in the BarnCRM Fundraising app** through its `actionOverrides` (Large and
  Small), the mechanism Core uses for its own pages in the BarnCRM app. No org default and
  no profile assignment is packaged.
- **Giving's related lists are Dynamic Related Lists; everything else stays as ADR-0043
  says.** The related list container stays on both pages for the lists the layout carries
  (Core's or the org's own). Within one package, a list that package owns still goes in its
  fallback layout.

## Alternatives considered

- **Document it and leave it to the administrator** (the review's interim). Rejected as the
  answer: every install would start with donors who show no giving, and Maria would rebuild
  the same page by hand in the Lightning App Builder.
- **A Giving layout for Account and Contact.** Rejected: nothing assigns it (no profiles
  ship), and it would compete with the org's own layout.
- **A custom "giving summary" component on Core's page.** Rejected: Core cannot place a
  Giving component, and a custom component would repeat what Dynamic Forms and the standard
  related list already render.

## Consequences

- **Two copies of each page.** A change to Core's `Account_Record_Page` or
  `Contact_Record_Page` is made in Giving's copy in the same pull request. Review checks both.
  If they drift in practice, a CI check that every Core component identifier appears in the
  Giving copy is the next step.
- In the BarnCRM app a donor still opens on Core's page, without giving. An organization
  that wants giving there activates the Giving page for that app in the Lightning App Builder
  (the admin guide says how). Core cannot do it, by ADR-0059.
- About 45 lines of metadata per Dynamic Related List, which is the cost ADR-0043 named.
- The lists, the section and the action work on a Platform-only org: they need only Giving's
  own objects and the Account and Contact objects every edition has (ADR-0013).
