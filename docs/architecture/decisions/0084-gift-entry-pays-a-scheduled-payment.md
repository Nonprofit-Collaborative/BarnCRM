# ADR-0084: Gift entry screens suggest the scheduled payment a gift pays, and a person decides

**Status:** Accepted
**Date:** 2026-10-12
**Source:** owner approved gap from the NPSP Gift Entry comparison ("Review Donations"); extends
G-03 (Quick Gift Entry) and G-17 (Gift Batches) with the G-24 donation matching rules
(canonical model R-DM2, R-DM3, new R-DM8)

## Context

A check that pays a pledge installment, typed on Quick Gift Entry or a gift batch line, was
saved as a gift on its own. The installment stayed unpaid, turned Overdue, and the pledge
balance was wrong until someone linked the gift by hand. Gift imports already solve this with
donation matching (G-24): candidates are the donor's open installments, a candidate matches
within a date window and an amount tolerance, the closest date wins, and a tie is refused.

An entry screen differs from an import in one way that matters: a person is looking at the
gift as it is typed. An import has to decide alone, so it needs R-DM4's tie rule and R-DM5's
behaviours. A screen does not, and deciding silently on a screen is worse than an import
doing so, because the person believes they typed a gift on its own.

## Decision

1. **The same candidates and the same match test as imports.** Candidates are R-DM2's (open
   installments of active or paused commitments of the donor or the donor's household), with
   no date bound, because a person may want an early or late payment the window would hide.
   The window and tolerance are the org's donation matching settings, through
   `DonationMatcher.matching`, so there is one definition of "this gift looks like that
   payment".
2. **Suggest, never apply unseen.** Matching candidates are marked suggested. One is chosen in
   advance only when it is the only one suggested, and the screen then says why it is chosen.
   Two or more suggested, or none, leave None chosen. None is always offered.
3. **The server checks the choice again.** At save (Quick Gift Entry) and at posting (batch
   lines), the chosen installment must still be a candidate of the gift's donor, read in the
   saving user's mode; otherwise the save is refused beside the choice and nothing is written.
   No new validation rule on `Gift__c`: the check belongs to these entry points, and the gift
   triggers (`GiftCommitmentHandler`) already apply a gift that carries Installment and
   Commitment.
4. **Standard base components.** The choice is a `lightning-combobox` on the form and in each
   batch line, labelled and described in custom labels.

## Alternatives considered

- **Apply the closest match automatically, as an import does.** Rejected: a wrong silent link
  marks a pledge paid that was not, and the person entering the gift never saw it happen.
- **A separate "Review Donations" dialog, as NPSP has.** Rejected for now: one more step for
  every gift, where an inline list costs nothing when the donor owes nothing.
- **Reuse an import template's matching values.** Rejected: an entry screen has no template;
  the org settings are what an import without its own values uses, so the two agree.

## Consequences

- Staff can pay a pledge installment from either screen; the pledge balance follows at once.
- The candidate query has no date bound, so a donor with very many open installments shows
  the first 50 by due date. Org testing should confirm that is enough in practice.
- A batch line gains an Installment lookup, so the choice survives saving the grid before
  posting (canonical model Section 25M).
