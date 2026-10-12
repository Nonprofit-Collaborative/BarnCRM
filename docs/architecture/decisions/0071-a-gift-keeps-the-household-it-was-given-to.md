# ADR-0071: A gift keeps the household it was given to

**Status:** Accepted
**Date:** 2026-10-12
**Source:** product owner decision (Brandon, 2026-10-12: "proceed as recommended; I can amend
later"), plan Section 12 decision D-20; amends canonical model rule R-G2

## Context

Rule R-G2 says a gift's Household is written by the package from its donor, and, as first
written, that it is recomputed both when the donor changes and when the donor's household
membership changes. Read literally, the second half means that when Luis Garcia moves out of
the Garcia household, every gift he gave while he lived there moves to his new household: the
Garcia household's giving history and totals shrink, and his new household gains gifts it never
received.

The Giving code never did that. `GiftTriggerHandler` derives the household when a gift is
inserted and when its donor changes, and nothing re-derives it when a membership changes. The
admin guide already describes the code's behavior ("Moving a person moves the person, not the
history of the household they left", Households page). The rule and the code disagreed, and the
owner was asked which one is right.

## Decision

**A gift stays credited to the household it was credited to when it was given.**

- A donor moving households (a reparent, a split, an end date on a membership, a new membership
  in junction mode) does not move their past gifts. Their gifts given after the move are
  credited to the new household.
- The household is still derived, never typed: on insert, and again when the gift's donor is
  changed, because then the gift itself was wrong.
- A household merge is not a move. The platform account merge carries every lookup to the
  surviving household (R-H13), so the merged household's gifts are credited to the survivor.
- Household rollups reached through the gift's Household field (total giving, gift counts and
  dates, giving by year) follow the gift and so stay with the household it was given to.
  Household rollups reached through current membership, such as automatic household soft
  credits, follow current membership, as they do today.

## Alternatives considered

- **Move past gifts with the donor (R-G2 as first written).** Rejected: a household's giving
  history, LYBUNT and SYBUNT reporting, receipts already issued and the accounting export would
  all change after the fact because somebody moved house. Totals for a year that is closed would
  change.
- **Ask the user which gifts to move at each move.** Rejected: an extra step on every move for a
  case that is rare, and a correction is already possible by changing the gift's donor.

## Consequences

- No code change is needed for the rule itself: the trigger already behaves this way. The
  canonical model (R-G2) and the Gifts admin guide page are amended to match.
- A test that pins it is worth adding with the next Giving change: move a donor with 200 gifts
  to another household and assert that every gift keeps its Household.
- Resolved: the empty household tidy-up keeps a household with gifts or commitments credited to it (`0070-empty-household-tidy-up-keeps-households-with-gifts.md`).
- Commitments derive their household exactly as gifts do (R-G2), so a pledge also stays with the
  household it was made to.
