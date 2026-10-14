# ADR-0097: Every packaged record page places its own actions, and Giving's own pages their own related lists

**Status:** Accepted (builder decision, Core quality pass Q-08); amends the related-lists
rule of ADR-0043 for record pages of objects the shipping package owns
**Date:** 2026-10-13
**Source:** Core quality pass item Q-08 (owner decision, 2026-10-13, to adopt the
recommended platform features), plan Section 4 and ADR-0043

## Context

ADR-0043 moved the packaged record pages to Dynamic Forms and put Dynamic Actions on the
Account page. An inventory for Q-08 found every record page already on Dynamic Forms, but:

- `Gift_Record_Page`, `Commitment_Record_Page` and `Gift_Batch_Record_Page` still took
  their actions from the page layout. Commitment's layout has no action list at all, so
  that page showed whatever the org's defaults were.
- The Giving copies of the Account and Contact pages had drifted from Core's: no **Log an
  interaction** (ADR-0064 says each copy is Core's page plus giving).
- `Commitment_Record_Page` showed no gifts: its layout has no related lists, so the related
  list container rendered nothing.
- **Refund or Write Off** showed on every gift and was refused by Apex on all but received
  ones.

## Decision

- **Every packaged record page uses Dynamic Actions** on its highlights panel, with Chatter
  actions hidden (ADR-0042). Gift: Edit, Refund or Write Off, Delete. Commitment: Edit,
  Change Owner, Sharing, Delete. Gift Batch: Edit, Delete. The Giving donor pages carry Core's
  actions plus New Gift.
- **An action that applies to some records carries a visibility rule**, as Merge or split
  already does: Refund or Write Off shows only while the gift's Status is Received. The
  Apex refusal stays for every other place the action can be reached.
- **On a record page for an object its own package owns** (Gift, Commitment), related lists
  are Dynamic Related Lists with set columns and sort, and the related list container is
  removed. Gift: Gift Allocations, Refunds and Write-offs. Commitment: Gifts.
- **Account and Contact pages keep the related list container**, as ADR-0043 and ADR-0064
  say: there it renders the org's own layout lists, which a package must not replace.
- **Custom panels stay.** Household members, household of a person, addresses,
  affiliations, relationships, soft credits and the payment schedule each do something a
  Dynamic Related List cannot: make primary, set default, move, remove, add with defaults,
  search, or read either a contact or a person account.
- **Every layout stays.** The layout is still what New and Edit windows, a record opened
  outside the packaged apps, and the activity panel's composer read. The Gift layout gains
  Log a Call, New Task and New Event so the Gift activity panel can create activities, as
  the Account layout already does.

## Alternatives considered

- **Keep the container on Gift and Commitment and add the lists to the layout.** Rejected:
  the page then shows whatever layout a profile has, which is the dependency ADR-0043 removed
  for fields, and a layout related list cannot be sorted newest first.
- **Dynamic Related Lists on Account and Contact too.** Rejected: an org's own lists
  (opportunities, cases, its own objects) would vanish from the packaged pages.
- **Replace the custom panels with Dynamic Related Lists.** Rejected: each would lose a
  behavior listed above.

## Consequences

- A list an admin adds to the Gift or Commitment layout appears on the fallback page, not on
  the packaged page; the admin guide says to add a Dynamic Related List in the Lightning App
  Builder instead.
- The Commitment page no longer shows Clone or Printable View, which came only from
  org defaults. An admin adds them in the Lightning App Builder; Clone is left off because a
  cloned commitment copies paid to date, and so a wrong balance, until rollups recalculate.
- A change to Core's Account or Contact page actions is mirrored in Giving's copy in the
  same pull request (ADR-0064); review checks both.
