# ADR-NEXT: Acknowledgments Honor the Donor's Email Opt-Out

**Status:** Accepted (owner decision, 2026-10-29)
**Date:** 2026-10-29
**Source:** module security review of 2026-10-28, finding G-L4; owner decision (Brandon,
2026-10-29: honor the opt-out, skip the email, show the reason in the queue so staff can send a
letter instead); ADR-0032; canonical model R-AK9 and R-AK13

## Context

The acknowledgment email run (ADR-0032) addresses each message to a contact with
`setTargetObjectId`. Salesforce applies a contact's **Email Opt Out** (`HasOptedOutOfEmail`) to
list and mass email, not to a single message sent from Apex, so the run emailed donors who had
asked not to be emailed. The review asked for one of two things: skip them, or record that a
thank you is transactional email and exempt.

Questions to settle: which opt-out applies, whose opt-out it is when the donor is an organization
or a household, and what happens to the gift so the donor is still thanked.

## Decision

1. **The opt-out read is `Contact.HasOptedOutOfEmail` on the recipient contact, and only that.**
   No other BarnCRM path sends email to donors (the Error Log digest goes to staff), so there is
   no existing rule to follow. Contact Point consent (`ContactPointTypeConsent`, `Individual`) is
   not read: it exists only where an org turns on data protection, BarnCRM writes nothing to it,
   and a module may not depend on it on a Platform-only org (ADR-0013).
2. **The opt-out is the recipient's.** The recipient is the one `recipientContactIdFor` already
   picks: the donor contact for a person's gift, and the account's primary contact for an
   organization or household gift. The opt-out of the person who would receive the message
   decides; other household members' opt-outs do not, because they are not emailed.
3. **An opted-out email gift is not emailed and gets no acknowledgment row.** As for a gift with
   nobody to email (R-AK9), nothing was attempted, so nothing is recorded on the donor; the gift
   stays **To acknowledge**. It is not counted as an error, since nothing went wrong.
4. **It goes in the letter queue instead.** The letter run (`runLetterMerge`) takes an email gift
   whose recipient opted out as a letter, recording the email rule on the row. The Acknowledgment
   Queue shows the count on its own line, **Opted out of email, sent by letter**, so staff see why
   these gifts are letters. The nightly run and **Send emails now** use the same check, so no
   send path emails an opted-out donor.
5. **The flag is read in system mode** (`AcknowledgmentSelector.optedOutOfEmail`), returning only
   contact Ids. Whether a donor is emailed must not depend on whether the person pressing Send
   has field access to Email Opt Out: without it, a user-mode read would either fail the run or
   treat every donor as opted in.

## Alternatives Considered

- **Treat acknowledgments as transactional email and ignore the opt-out.** Rejected by the owner:
  a thank you is not something the donor asked for in that moment, and an opted-out donor emailed
  anyway reads as the org ignoring them.
- **Write a Failed row, or a new Skipped status, per opted-out gift.** Rejected: a row every night
  for a gift that will never be emailed is noise on the donor's record (the R-AK9 reasoning), and
  a new picklist value and its filters would be added for a reason the queue count already gives.
- **Leave opted-out gifts waiting for staff to handle by hand.** Rejected: with no way to thank
  them in the product, staff would have to change each gift's status, and the gift would be
  skipped again every night.

## Consequences

- An opted-out donor whose rule says email gets a letter in the next letter file. An org that
  sends no letters sees them wait in the queue under their own line until it does.
- No object or field is added (canonical model R-AK13).
- An email already sent is unaffected; the check runs at send time, so a donor who opts out after
  a gift is queued is not emailed.
