# ADR-0201: BarnCRM Payments: the org's own Stripe and PayPal through hosted checkout, one payment record, a verified webhook receiver and a Callable seam for the modules that charge

**Status:** Accepted (builder decision)
**Date:** 2026-11-11
**Source:** plan Section 6.0a release 1.4 (PAY-01, MIG-06), D-190 (payments through Stripe and
PayPal for events, donations and whatever else applies; payment processing stays out of Core),
D-125 and Section 6.1.4 item 6 (online giving landing; the first-party Stripe receiver X-08 is
part of PAY-01), Section 4.13 (security), Section 9.9 (portability). Builds on ADR-0013 (Core
runs alone), ADR-0017 (cross-package mechanisms by name), ADR-0057 (Health Check extensions),
ADR-0131 (module access by role), ADR-0184 (a guest only stores, a staff job processes) and
ADR-0185 (portal API).

## Context

Events (EV-20, paid registration), Giving (G-34 online donations, G-27 recurring donor health),
Memberships (PAY-02, dues) and Portal Builder (PAY-03, donor portal payments) all need to take
money online. D-190 settles that the organization uses its own Stripe or PayPal account, that
BarnCRM never holds money or card data, and that payment processing stays out of Core. Each of
those modules is built later, by other people, so the way they ask for a payment and learn its
outcome must be small, stable and documented before any of them exists. The module must also
run without any of them installed, and none of them may fail to deploy when Payments is absent.

A processor reports the outcome of a payment by calling a public address (a webhook). On
Salesforce without Experience Cloud (ADR-0009) that address is a Salesforce Site, whose guest
user Salesforce restricts on purpose: ADR-0184 settled that a guest only stores and a staff
user processes.

## Decision

1. **A new optional module, BarnCRM Payments** (`packages/payments`, module key `Payments`),
   depending on Core only, offered in both editions, not installed by default. It ships its
   catalog row with no probe object and Setting Definition rows naming it (#1053). Nothing in
   Core names a payment; Core only lists the module's class names where it already lists every
   module's (Health Check extensions, Module Manager, the help catalog).
2. **Processor-hosted checkout only.** Payments asks the processor for a hosted checkout page
   and returns its address; the payer types their card or signs in to PayPal on the processor's
   page, never on a BarnCRM or Salesforce page.
   - **Stripe:** a Checkout Session (`POST /v1/checkout/sessions`, mode `payment`, one line item
     priced in the smallest currency unit), with the payment's reference in `client_reference_id`
     and in the metadata of both the session and its payment intent, and the reference as the
     idempotency key.
   - **PayPal:** an Order (`POST /v2/checkout/orders`, intent `CAPTURE`) whose purchase unit
     carries the reference as `custom_id`, and the order's approve link. PayPal needs the
     merchant to capture an approved order, so the processing job captures it when the
     `CHECKOUT.ORDER.APPROVED` event arrives.
   BarnCRM stores the amount, currency, description, payer name and email, and the processor's
   identifiers. It never sees or stores a card number, an account number or a PayPal password.
3. **One payment record and status flow.** `Payment__c` (canonical model 29PAY1) with Status
   Pending, Paid, Failed, Refunded or Cancelled:
   - Pending at checkout; Paid when the processor reports the money captured; Failed when it
     reports the charge declined or failed; Cancelled when the checkout expires or is abandoned
     (Stripe `checkout.session.expired`, or a payment still Pending with no processor payment
     after 2 days, swept by the processing job); Refunded when the whole amount is refunded.
   - A partial refund keeps the payment Paid and raises Amount Refunded; refunds add up to the
     amount at most.
   - Allowed moves: Pending to any; Failed to Paid (a retried card); Paid to Refunded; Cancelled
     to Paid (a late capture is still money received). Every other move is ignored and the event
     is kept as Ignored with the reason, so an out-of-order or replayed event never takes a
     payment backwards.
4. **The webhook receiver.** `PaymentWebhookRest` at
   `<site URL>/services/apexrest/barncrm/payments/v1/stripe` and `.../v1/paypal`, open to the
   Site's guest user through the permission set `Payments_Webhook_Guest`, which grants that one
   class and nothing else: no object, no field.
   - **Stripe events are verified on arrival:** the `Stripe-Signature` header's `t` and `v1`
     values, an HMAC-SHA256 of `t.body` with the endpoint's signing secret compared in constant
     time, and `t` within 5 minutes of now. A request that fails is answered 400 and nothing is
     stored.
   - **PayPal events are verified by PayPal:** the receiver stores the event with its five
     `PAYPAL-*` transmission headers, and the processing job calls PayPal's
     `/v1/notifications/verify-webhook-signature` with the org's webhook id before using it. An
     event PayPal does not confirm is kept as Rejected and never applied. The guest therefore
     makes no callout and never reads a PayPal secret.
   - The receiver does one thing: inserts a `Payment_Event__c` (29PAY2) with Status Received, in
     system mode (the guest has no object access), and answers 200. It reads no record, returns
     no identifier and answers every outcome with the same empty body. A body over 64 KB, or
     more than the hourly limit of events (500) stored in the last hour, is refused.
5. **Each processor event is used once.** `Payment_Event__c.Event_Key__c` is unique
   (`stripe:evt_...`, `paypal:WH-...`). Stripe events get the key on arrival, so a resent event
   is a duplicate insert, answered 200 and dropped. PayPal events get it only once verified, so
   a forged event can never take a real event's key; a verified duplicate is marked Ignored.
6. **Processing runs as a staff user** (ADR-0184 decision 2): `PaymentEventProcessor`, four
   scheduled jobs every 15 minutes, scheduled from Health Check by an administrator and running
   as them, in user mode. Each run does every callout first (PayPal verification and capture),
   then every write, since Salesforce allows no callout after a write in one transaction. It
   applies the status move, writes the payment, marks the event Applied, Ignored, Rejected or
   Failed with a reason, and tells the payment's listener (decision 8). Up to 15 minutes can
   pass between the payment and its record: a consumer's return page says the payment is being
   confirmed.
7. **Keys are the org's own, entered in the app, never shown again.** `Payment_Keys__c` (29PAY4),
   a protected hierarchy custom setting granted to no permission set: Stripe secret key and
   webhook signing secret, PayPal client id, client secret and webhook id. The Payments Setup
   page writes them and shows only whether each is set and its last four characters. The
   processor choice, test or live mode and default currency are ordinary settings in the
   Payments section of BarnCRM Settings (`Payments_Settings__c`, 29PAY3). Callouts go to the
   three processor addresses shipped as Remote Site Settings. Health Check reports a missing
   key, a Stripe key whose mode (`sk_test_` or `sk_live_`) disagrees with the setting, no active
   Site, a Site guest without the receiver's permission set (fix: give it), processing not
   scheduled (fix: schedule it) and events waiting over an hour.
8. **The seam is `System.Callable`, found by name**, so no consumer depends on Payments and
   Payments depends on no consumer (ADR-0017). Both directions pass plain maps of strings,
   numbers and identifiers, so the shape is the same in JSON and portable (Section 9.9).
   - **Starting a checkout.** A consumer builds `PaymentsApi` by name
     (`NamespaceUtil.build('PaymentsApi', Callable.class, context)`; null means Payments is not
     installed) and calls `call('startCheckout', args)` with: `amount` (Decimal, required, over
     zero), `description` (required), `successUrl` and `cancelUrl` (https, required), and
     optionally `currency` (three letters, default the setting), `processor` (`Stripe` or
     `PayPal`, default the setting), `payerName`, `payerEmail`, `personId` (a Contact id),
     `sourceRecordId` (the consumer's record) and `listener` (the consumer's class name). It
     returns `{ paymentId, checkoutUrl, status, reference }`, or throws
     `PaymentsApi.PaymentException` with a message fit to show. The callout happens before the
     payment is written, so a consumer calls it before its own writes in the transaction (or
     from its own controller call). The payment is written in system mode: the API is Apex
     only, never exposed to a page, and a public page's guest must be able to start a checkout.
   - **Other calls.** `call('getPayment', { paymentId })` returns the payment as a map (the
     fields below), `call('isReady', { processor })` returns whether the keys and mode for that
     processor are set.
   - **Being told.** When a payment's status or refunded amount changes, the processing job
     builds the payment's `listener` by name and calls `call('paymentChanged', payment)` with
     `{ paymentId, sourceRecordId, personId, status, previousStatus, amount, amountRefunded,
     currency, processor, mode, paidAt, detail }`. It runs as the processing administrator in
     the same transaction as the payment write, inside a savepoint: a listener that throws has
     its own writes undone and the failure logged with the payment's id, while the payment keeps
     its new status. A listener does no callout (enqueue a job instead) and must be safe to call
     twice with the same status.
   - **Stability.** Action names and map keys are permanent once released; new optional keys
     may be added, none removed or renamed. A consumer must ignore keys it does not know.
9. **Access.** `Payments_Admin` (BarnCRM Admin holders): every payment and event, the settings,
   the Payments Setup page; `Payments_Staff` (Team Member, Fundraising Staff): read payments;
   `Payments_Read_Only` (Read Only): read payments. Nobody edits a payment's status by hand: it
   comes only from the processor. `Payments_Webhook_Guest` is the guest's.
10. **Test and live.** The mode is stored on each payment, so test payments can be told apart
    and left out of reports. PayPal's test mode uses `api-m.sandbox.paypal.com`; Stripe's is
    chosen by the key.
11. **MIG-06, other giving tools.** Tools such as Givebutter, Donorbox, Zeffy or Classy are not
    integrated: the Admin Guide's Zapier recipes write their gifts through Mirror's Inbound Gift
    API (X-03), which already makes a resend safe, or with Zapier's Salesforce action on the
    Giving gift. Stripe itself is received first-party by this module (the former X-08). This
    is guidance only: no code, no BarnCRM-held account.

## Alternatives considered

- **Payments in Core, or a Core interface for the seam.** Rejected: D-190 keeps processing out
  of Core, and `System.Callable` gives a compile-free seam without a Core type.
- **A Payments interface consumers implement.** Rejected: every consumer would depend on the
  Payments package and fail to deploy without it.
- **Keys in Named Credentials.** Rejected for now: the Stripe signing secret must be read by
  Apex to compute the HMAC, which a Named Credential does not allow, and Named Credentials are
  edited in Setup, not in the app. One protected setting holds all five; moving the API keys to
  an External Credential later changes only the two client classes.
- **Applying events in the guest's transaction.** Rejected: listeners would write consumer
  records as the guest, in system mode (ADR-0184 rejected the same for forms).
- **Embedded card fields (Stripe Elements, PayPal buttons) on BarnCRM pages.** Rejected: more
  PCI scope, Lightning Locker and Site content security work, and no gain for the consumers.
- **A first-party receiver for each giving tool.** Rejected: D-125 keeps those as recipes;
  community receivers stay X-08's community scope.

## Consequences

- An administrator does three things outside the app, which no app can do: create the Site
  (shared with public forms), paste the receiver address into the Stripe or PayPal dashboard,
  and copy the keys from there into Payments Setup.
- A payment reaches Paid up to 15 minutes after the payer pays; consumers show "being
  confirmed" on their return page and act when told.
- The keys sit in a custom setting that, until the packages have a namespace, an administrator
  with View All Custom Settings can read in Setup; with the namespace it is protected.
- Consumers built later (EV-20, G-34, G-27, PAY-02, PAY-03) need no Payments change: each passes
  its own `listener` and `sourceRecordId`.
- Multi-currency orgs are out of scope (plan Section 6.1): Amount is in the payment's own
  currency code, shown as entered.
