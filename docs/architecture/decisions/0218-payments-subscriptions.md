# ADR-0218: Payments subscriptions: a recurring gift charged by the processor's own subscription, renewals and failures told to Giving, and Update Card on the processor's own page

**Status:** Accepted (builder decision)
**Date:** 2026-11-12
**Source:** plan Section 6.0a release 1.20, D-196 (2) (PAY-04: the recurring gift stores the
processor's customer and subscription ids, the portal opens the processor's own update-card
page, listener events for failed and renewed charges; completes PAY-03's card updates). Amends
ADR-0201 `0201-payments-module.md` decisions 2, 3 and 8 and ADR-0210
`0210-donor-portal-payments.md` decision 5, and through it ADR-0191 decision 4 (the donor
template takes no card). Builds on ADR-0017 (cross-package mechanisms by name), ADR-0185
decision 9 (portal module actions) and G-27 recurring donor health (canonical model Section 25V).

## Context

PAY-03 lets a donor pay each payment of a recurring gift through an emailed one-off checkout.
Payments stores no processor customer, saved card or subscription, so nothing is charged
without the donor acting, and a donor whose card fails or expires cannot fix it. G-27 already
keeps a recurring gift's health (Failed Charges, Last Failed Charge, Card Expires, Cancelled at
Processor) from Recurring Gift Event records matched by Processor Subscription Id, written today
by a Zapier recipe. The smallest design that lets later payments charge a saved card and lets a
donor fix one uses the processor's own subscription and its own pages: BarnCRM never sees a card
number and runs no charging job of its own.

## Decision

1. **Automatic Recurring Payments, off by default.** A Payments setting
   (`Payments_Settings__c.Recurring_Payments__c`, default false). When on, `startCheckout` with
   `interval` (`week`, `month` or `year`) and `intervalCount` (1 to 12) starts a subscription on
   the processor's hosted page instead of a one-off checkout; when off, the two keys are ignored
   and nothing changes. `isReady { recurring: true }` answers whether keys are set and the
   setting is on.
   - **Stripe:** a Checkout Session in mode `subscription` with an inline recurring price and
     the payment's reference in `subscription_data[metadata]`. Stripe creates the customer and
     saves the card; Stripe charges each period and retries a failed charge on its own schedule.
   - **PayPal:** a product, a plan with one fixed-price regular cycle, then a subscription whose
     `custom_id` is the reference; the payer approves on PayPal's page. PayPal charges each
     period from the payer's PayPal account. (Amended 2026-11-12, D-198: the product and plans
     are shared and reused; see the amendment below.)
2. **The first payment is the subscription's record.** The Pending payment the checkout wrote
   becomes Paid as today and gains the processor's subscription id
   (`Payment__c.Subscription_Id__c`, 29PAY1). Each later charge the processor reports as paid
   (Stripe `invoice.paid`, PayPal `PAYMENT.SALE.COMPLETED`) whose processor payment id no payment
   has yet becomes a new Paid payment copied from the first (person, source record, listener,
   description, currency, mode), with its own reference and the charged amount (R-PAY6). It is
   written in system mode: the processing administrator edits payments but creates none, and the
   event creating it is verified (R-PEV2). Its listener is told `paymentsChanged` as for any
   payment, so Giving writes the gift. A renewal never carries the first payment's detail.
3. **Subscription news, told to the listener once per run.** Four processor events are read into
   subscription news, each used once through the existing Event Key (R-PEV1):

   | News | Stripe | PayPal |
   |---|---|---|
   | `chargeSucceeded` | `invoice.paid` | `PAYMENT.SALE.COMPLETED` |
   | `chargeFailed` | `invoice.payment_failed` | `BILLING.SUBSCRIPTION.PAYMENT.FAILED` |
   | `cardUpdated` | `checkout.session.completed` in mode `setup` (decision 5) | none: PayPal sends no event for a changed funding source |
   | `cancelled` | `customer.subscription.deleted` | `BILLING.SUBSCRIPTION.CANCELLED` |

   The payment is found by its reference (in the subscription's metadata or `custom_id`), else by
   Subscription Id. The listener is told `subscriptionsChanged { changes: [...] }`, each change
   `{ subscriptionId, customerId, sourceRecordId, personId, processor, mode, event, eventKey,
   eventDate, amount, cardExpires, detail }`, inside a savepoint like `paymentsChanged`. A failed
   charge writes no payment: the processor retries it, and a later success is a renewal.
4. **Giving keeps the ids and the health.** `GivingDonations` (Giving's existing listener) takes
   `subscriptionsChanged`: it fills the commitment's Processor Subscription Id and the new
   Processor Customer Id (`Commitment__c.Processor_Customer_Id__c`, Section 25V) when blank, and
   upserts one Recurring Gift Event per change by External Id (the event key), so G-27's rules
   R-RH1 and R-RH2 update Failed Charges, Card Expires and Cancelled at Processor as they do for
   Zapier's events. Payments stays dependent on Core only; Giving names no Payments class.
5. **Update Card opens the processor's own page.** `call('updateCard', { subscriptionId,
   customerId, returnUrl })` returns `{ url }`. The processor is told by the id (`sub_` is
   Stripe, any other is PayPal).
   - **Stripe:** a Checkout Session in mode `setup` for the customer, with the subscription in its
     metadata (valid 24 hours, so it can be emailed). When the session completes, the processing
     job reads the new card (`GET /v1/setup_intents/{id}`, its payment method expanded) and makes
     it the subscription's default (`POST /v1/subscriptions/{id}`), callouts before writes as for
     PayPal capture; Stripe's own retries then charge an unpaid invoice to the new card.
   - **PayPal:** PayPal's own automatic payments page (`www.paypal.com/myaccount/autopay/`, the
     sandbox address in Test mode), where the payer changes the funding source; no callout.
6. **The donor portal's Update Card.** The donor template adds `Giving.UpdateCard` (label Update
   Card) on Pledges and Recurring Gifts. `GivingPortalPayments` checks, as for Pay Online, that
   the commitment is the verified person's, Active, a recurring gift with a Processor
   Subscription Id, that the person has an email and Payments is ready, then queues itself and
   emails the processor's page (the portal cannot call out after its own write). Pay Online on
   such a gift is refused while it is charged automatically; on a recurring gift with no
   subscription, with the setting on, it starts the subscription for the gift's Amount and
   Frequency (Weekly, Every two weeks, Monthly, Quarterly, Twice a year, Yearly).
7. **Access.** Processor Customer Id: Giving Admin edits it (for a subscription made outside
   BarnCRM), Giving Staff and Read Only read it. Subscription Id on a payment: Payments Admin
   edits it (the processing job writes it), Staff and Read Only read it.

## Alternatives considered

- **A saved card charged by BarnCRM** (Stripe SetupIntent and an off-session PaymentIntent per
  scheduled payment). Rejected: a charging job of BarnCRM's own, strong customer authentication
  handling and retries, and no PayPal equivalent without vault approval; the processors already
  schedule, retry and email.
- **Stripe's Customer Portal** (`/v1/billing_portal/sessions`, flow `payment_method_update`).
  One callout and no follow-up, but its link is short-lived (unfit for an emailed link) and the
  organization must configure the portal in Stripe first. Can replace the setup session in
  `PaymentStripe` alone if the portal ever opens links directly.
- **PayPal `revise` with the same plan** for an approve link. Revise is for changing plans; the
  payer's funding source is changed in their PayPal account, which PayPal's own page does.
- **A Payment Subscription object.** Rejected: the first payment already holds the subscription's
  source, person and listener; one field finds it.
- **Failed charges as Failed payments.** Rejected: a retry of the same invoice would make two
  records for one charge; health lives on the commitment (G-27).

## Consequences

- An administrator adds the new event types to the processor's webhook (Stripe `invoice.paid`,
  `invoice.payment_failed`, `customer.subscription.deleted`; PayPal Payment sale completed,
  Billing subscription payment failed, Billing subscription cancelled) and turns the setting on.
- Subscriptions started outside BarnCRM (G-27's Zapier recipes) keep working as before; Update
  Card works for them once an administrator fills Processor Customer Id (Stripe), but their
  renewals are not written by Payments, since Payments has no first payment for them.
- Under Stripe API versions from 2025-03, an invoice carries no payment intent: a renewal's
  Processor Payment Id is then the invoice id, and a refund of it is not matched (refund it in
  Stripe and adjust the gift by hand).
- Cancelling a subscription is done in the processor's dashboard (or by the donor at PayPal);
  BarnCRM records it as Cancelled at Processor and never changes the commitment's Status.

## Amendment 2026-11-12: PayPal products and plans reused (D-198)

**Source:** plan decision D-198 (Brandon, 2026-11-12): "It definitely needs to reuse products,
plans, and whatever is applicable to be reused while allowing accurate tracking." Amends
decision 1 (PayPal). Canonical model R-PAY7, version 1.53.

Decision 1 made a PayPal catalog product and a billing plan for every recurring checkout (three
callouts and two catalog objects per payer). Instead:

1. **One product per PayPal account.** Its id is kept in `Payment_Keys__c.PayPal_Product_Id__c`,
   beside the account's keys (named "{organization} recurring payments"). It is made at the first
   PayPal subscription checkout with PayPal-Request-Id `product-{mode}`.
2. **One plan per Plan Key** (mode, currency, amount, interval unit and count, such as
   `Test:USD:25.00:MONTH:1`), named "25.00 USD every month". The subscription's first payment
   keeps the key and the plan (`Payment__c.Plan_Key__c`, external ID, and `Plan_Id__c`); a
   checkout reuses the Plan Id of the newest payment with the same key. That read runs past
   sharing (a private inner reader, one field by key), because a donor page's guest or a portal
   person starts checkouts and can see no other payment. A plan is made with PayPal-Request-Id
   `plan-{key}-{product}`, so checkouts at the same moment make one plan.
3. **Each payer keeps their own subscription**, its `custom_id` their payment's reference, so
   renewals, failures, cancellations and Update Card track exactly as before (decisions 2 to 5).
4. **Replaced when PayPal refuses it.** When PayPal refuses (4xx) a subscription on the
   remembered plan (missing, inactive, another account), a new plan is made and the
   subscription asked again (request ids gain the payment's reference); this payment carries the
   new plan, so it replaces the old from then on. A plan refused for its product (new keys, the
   other mode) makes a new product first, which replaces the stored one.
5. **Callouts first.** A reused plan costs one callout (the subscription). The payment and, when
   a product was made, the product id are written after the last callout.

**Stripe is unchanged:** its Checkout Session prices inline (`price_data` with `product_data`),
so BarnCRM makes and keeps no Stripe product or price to reuse.

**Alternatives considered:** a list custom setting of plans (sharing-free, but creating list
custom settings is off by default in new orgs and a source deploy may be refused); a Payment
Plan object (a second object, permissions and sharing for one id per key); finding the plan by
listing PayPal's plans (paged callouts on every checkout); checking the remembered plan with a
GET first (one more callout on every checkout, where a refusal is already the signal).

**Consequences:** the payer sees the shared plan's name on PayPal's page, not the payment's
description. A mode switch makes a new product the first time each way. A subscription refused
for another reason (for example a bad return address) makes one unused plan before it is
refused.
