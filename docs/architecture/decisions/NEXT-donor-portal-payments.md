# ADR-NEXT: Donor portal payments: a Pay Online action on a pledge or recurring gift that emails the donor the org's own hosted checkout, with the gift written from the payment's outcome

**Status:** Accepted (builder decision)
**Date:** 2026-11-11
**Source:** plan Section 6.0a release 1.15 (PAY-03, extends PB-08), D-190 (payments through the
org's own Stripe and PayPal). Amends ADR-0191 decision 4 (the donor template took no payment).
Builds on ADR-0017 (cross-package mechanisms by name), ADR-0185 decision 9 (portal module
actions through `PortalActionExtension`), ADR-NEXT `NEXT-payments-module.md` (the Payments
seam), ADR-NEXT `NEXT-memberships-module.md` decisions 6 and 7 (dues paid from the portal by an
emailed link) and ADR-NEXT `NEXT-online-donation-pages.md` (the Giving listener).

## Context

PAY-03 asks for pledge payments and recurring gift card updates in the donor portal through the
Payments hosted checkout. A portal action cannot make the Payments callout itself: Portal Builder
may write the session's Last Used time before the action and sets a savepoint around it, and
Salesforce refuses a callout after either. Memberships met the same limit for dues (PB-09) by
queuing a job that starts the checkout and emails the link. Payments has no subscriptions, so a
stored card cannot be updated.

## Decision

1. **The donor template offers `Giving.PayOnline` on Pledges and Recurring Gifts** (label Pay
   Online). This amends ADR-0191 decision 4: the donor portal still changes only contact details
   and starts a payment on the processor's page; it takes no card itself.
2. **The action queues the checkout and emails it,** as Memberships' Pay Dues does.
   `GivingPortalPayments` (Giving, registered in Core's `PortalActionExtensions`) checks, in
   system mode and only for the verified person's own record, that the commitment is Active, the
   person has an email address, an amount is due and Payments is ready, then queues itself. The
   job asks `PaymentsApi` by name for a hosted checkout and emails the donor its address from the
   help catalog's words. The portal answers "We've emailed you a secure link". No Core or Portal
   Builder change is needed.
3. **The amount is the next payment due.** The earliest Scheduled, Partially paid or Overdue
   payment's expected amount less what was paid; with none, a pledge's balance, or a recurring
   gift's amount. The payment's source record is the commitment and its listener is
   `GivingDonations`.
4. **The gift is written when Payments reports Paid.** `GivingDonations.paymentChanged` writes,
   for a payment whose source is a commitment and that has no gift yet, a Received gift: the
   person as donor, the commitment and its appeal, the amount, Gift Date the paid date, Payment
   Reference the payment's identifier. Giving's existing commitment rule links it to the earliest
   unpaid payment (`CommitmentService.applyGift`).
   Refunded and Cancelled move an existing gift, as for donation pages; Pending and Failed write
   nothing.
5. **No card update.** Payments takes one-off payments only. A donor with a recurring gift pays
   each payment through the same action; changing a stored card waits for a Payments
   subscription extension.
6. **Nothing new to switch on.** The action shows only where a portal's template lists it, and
   an org's existing portals keep their saved template until it is updated.

## Alternatives considered

- **Sending the browser straight to checkout** through a new portal route that resolves the
  session without writing it and calls a new Core `PortalCheckoutExtension` before any write.
  Better for the donor, but a Core seam, a Portal Builder route and a client change for one
  action, and different from Memberships' Pay Dues. Can be added later without changing the
  listener.
- **A gift written as Pending when the checkout starts.** Rejected: an abandoned checkout would
  count against the pledge's balance until Payments cancelled it.

## Consequences

- A donor chooses Pay Online, gets an email with the processor's checkout link and pays there;
  the gift and the payment's status follow once Payments processes the processor's report.
- Card updates for recurring gifts are not offered (decision 5).
- Each choice of Pay Online starts one checkout and one email; an unused checkout is cancelled by
  Payments as abandoned.
