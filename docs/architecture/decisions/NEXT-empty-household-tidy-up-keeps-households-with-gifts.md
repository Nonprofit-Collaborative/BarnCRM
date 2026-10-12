# ADR-NEXT: The empty household tidy-up keeps a household that still has gifts

**Status:** Accepted
**Date:** 2026-10-12
**Source:** product owner decision (Brandon, 2026-10-12, plan Section 12 decision D-20);
resolves the open follow-up of `NEXT-a-gift-keeps-the-household-it-was-given-to.md`; extends
ADR-0036 and canonical model R-H12, under the cross-package mechanism of ADR-0017

## Context

A gift keeps the household it was credited to when it was given: a donor moving households
does not move past gifts (`NEXT-a-gift-keeps-the-household-it-was-given-to.md`, R-G2). The
empty household tidy-up (R-H12, ADR-0036, `Delete_Empty_Households__c`) deletes the household
a person was the last to leave. `Gift__c.Household__c` and `Commitment__c.Household__c` are
`SetNull` lookups, so that delete clears the household on every gift and pledge credited to
it, and no gift trigger runs when it does. With the tidy-up on, a donor living alone who moves
leaves their whole giving history with no household at all.

ADR-0036 already keeps a household that something outside BarnCRM depends on. Gifts are not
outside BarnCRM, and Core may never reference Giving (plan Section 4.1), so Core cannot ask
about gifts itself.

## Decision

**An emptied household is kept when an installed module still credits records to it.**

- Core defines the extension point `HouseholdDependentsExtension`: one method that takes
  household identifiers and returns those the module still credits records to.
  `HouseholdDependentsExtensions` finds implementations by class name with `Type.forName`,
  the pattern `HealthCheckExtensions` uses (ADR-0017). Where none is installed, nothing is
  asked and nothing changes.
- Giving implements it in `GivingHouseholdDependentsExtension`: a household that a Gift's or
  a Commitment's Household field names. It reads in system mode (ADR-0021): a gift the moving
  user cannot see would otherwise read as absent and the household would be deleted anyway.
- `HouseholdService.deleteEmptyHouseholds` asks once per batch, after the ADR-0036 probe, and
  deletes only what neither probe reports.
- An extension that throws reports every household it was asked about as dependent, and the
  failure is logged: not being able to answer is not answering no (the ADR-0036 rule).
- A household kept this way is not written to the Error Log. Keeping a donor's past household
  is the ordinary result of a move, not something an administrator must act on.

## Alternatives considered

- **Change the lookups to Restrict.** Rejected: a delete would then fail the whole move with a
  platform error the person moving a contact cannot act on.
- **Move the gifts to the donor's new household before the delete.** Rejected: contradicts
  R-G2 as amended; the household that received the gifts is the one they belong to.
- **Turn the tidy-up off when Giving is installed.** Rejected: households with no gifts are
  still worth tidying, and an installed package is the wrong signal (the ADR-0036 reasoning).

## Consequences

- With Giving, the tidy-up removes only households with no gifts and no pledges. The admin
  guide's Households page and the setting's description say so.
- One more system-mode read per batch of emptied households, two semi-join queries at most.
- Another module (for example Connect, for mirrored opportunities) can join by adding its class
  name to `HouseholdDependentsExtensions.EXTENSION_CLASSES`; no new decision is needed.
- Receipts also carry a Household lookup. A receipt takes its household from its gifts, so a
  household with receipts has gifts and the gift check covers it.
