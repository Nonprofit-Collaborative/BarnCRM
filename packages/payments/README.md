# BarnCRM Payments

## Purpose

Takes payments through the organization's own Stripe or PayPal account on the processor's hosted
checkout page, records each as a `Payment__c` with one status flow, and receives the processors'
webhooks on the org's Salesforce Site (PAY-01, D-190, ADR-NEXT `NEXT-payments-module.md`).
BarnCRM holds no money and stores no card data. Setup and use:
[Admin Guide, Payments](../../docs/admin-guide/payments.md).

## First ships in

Release **1.4** (PAY-01). Its consumers come later: Events paid registration (EV-20, 1.5),
membership dues (PAY-02, 1.8), online donations and donor portal payments (G-34, PAY-03, 1.15)
and recurring donor health (G-27).

## Depends on

- BarnCRM Core

No consumer is a dependency, and no consumer depends on this package (the seam below).

## Contents

- Objects: `Payment__c` (29PAY1), `Payment_Event__c` (29PAY2); settings `Payments_Settings__c`
  (29PAY3) and the keys `Payment_Keys__c` (29PAY4, granted to no one).
- `PaymentsApi`: the seam (`System.Callable`).
- `PaymentService`: starting a checkout, the status moves (R-PAY1, R-PAY2) and telling listeners.
- `PaymentStripe`, `PaymentPayPal`: each processor's checkout call, event reading and
  verification.
- `PaymentWebhookRest`: the receiver, `/services/apexrest/barncrm/payments/v1/stripe` and
  `/paypal`, for the Site guest (`Payments_Webhook_Guest`).
- `PaymentEventProcessor`: four jobs every 15 minutes, scheduled from Health Check.
- `PaymentsHealthCheckExtension`, `PaymentsSetupController` and the `paymentsSetup` page.
- Permission sets `Payments_Admin`, `Payments_Staff`, `Payments_Read_Only` (given by
  `PaymentsAccessSync`) and `Payments_Webhook_Guest`.
- Remote Site Settings for `api.stripe.com`, `api-m.paypal.com` and `api-m.sandbox.paypal.com`.

## The Payment Seam

A module that charges never names a Payments class or object at compile time, and Payments never
names it. Both directions are `System.Callable` classes found by name, passing plain maps.

### Starting a checkout

```apex
Callable payments = (Callable) NamespaceUtil.build('PaymentsApi', Callable.class, 'MyModule');
if (payments == null) {
	// Payments is not installed: hide the paid option.
}
Map<String, Object> started = (Map<String, Object>) payments.call('startCheckout', new Map<String, Object>{
	'amount' => 40.00,                         // required, over zero
	'description' => 'Spring Gala: 2 tickets', // required, shown on the checkout page
	'successUrl' => 'https://example.org/paid',     // required, https
	'cancelUrl' => 'https://example.org/cancelled', // required, https
	'currency' => 'USD',              // optional, default the setting
	'processor' => 'Stripe',          // optional, Stripe or PayPal, default the setting
	'payerName' => 'Ana Rivera',      // optional
	'payerEmail' => 'ana@example.org',// optional, prefilled on Stripe
	'personId' => contactId,          // optional, a Contact id
	'sourceRecordId' => registration.Id, // optional, your record
	'listener' => 'EventPaymentListener', // optional, your Callable class
	'detail' => installmentId          // optional, kept as the payment's detail until the processor's
});
// started: { paymentId, checkoutUrl, status ('Pending'), reference }
```

- It makes the processor callout before it writes the payment, so call it **before your own
  writes** in the transaction (for example from its own controller call), then store
  `paymentId` on your record and send the payer to `checkoutUrl`.
- A bad argument, missing keys or a processor refusal throws `PaymentsApi.PaymentException`
  with a message fit to show the person; the cause is in the Error Log.
- It works for a Site guest (a public page): the payment is written in system mode. It is Apex
  only; never expose it to a page directly.

Other calls: `call('getPayment', new Map<String, Object>{ 'paymentId' => id })` returns the
payment map below (null when not found); `call('isReady', new Map<String, Object>{ 'processor' =>
'PayPal' })` returns true when that processor's keys are set; `call('countRecent', new
Map<String, Object>{ 'sourceRecordId' => id, 'minutes' => 10, 'status' => 'Pending' })` returns
how many payments for your record were started in the last minutes (default 60), of that status
if given (a count only, so a public page may ask it, for example to refuse card testing).

### Being told of a change

Give `listener` the name of a class of yours that implements `System.Callable`, with a public
no-argument constructor (and `@NamespaceAccessible` once packaged). When a payment's status or
refunded amount changes, the processing job first calls your class once for the whole run,
`call('paymentsChanged', new Map<String, Object>{ 'payments' => [payment, ...] })`, with every
changed payment of yours. Answer `true` when you handled them, which keeps a run of many
payments inside the limits (one query for all, not one per payment). Answer anything else (a
listener written before this form answers null) and it calls `call('paymentChanged', payment)`
once per payment instead. Each payment map holds:

| Key | Value |
|---|---|
| `paymentId` | The payment's id |
| `sourceRecordId` | Your record, as you passed it |
| `personId` | The Contact id, if given |
| `status` | `Pending`, `Paid`, `Failed`, `Refunded` or `Cancelled` |
| `previousStatus` | The status before |
| `amount`, `amountRefunded` | Decimals |
| `currency` | Three letters |
| `processor`, `mode` | `Stripe` or `PayPal`; `Test` or `Live` |
| `paidAt` | Datetime or null |
| `detail` | The processor's failure, refund or cancellation reason, or null |

- It runs as the administrator who scheduled processing, in user mode, inside a savepoint: if
  your listener throws, your writes are undone and the failure logged, and the payment keeps its
  new status. A failed `paymentsChanged` is followed by `paymentChanged` for each payment, each
  in its own savepoint. Make both safe to call twice with the same status.
- Do no callout in it; enqueue a job if you need one.
- Test mode payments arrive the same way with `mode` `Test`; decide whether to act on them.

### Stability

The action names and keys above are permanent once released: new optional keys may be added,
none removed or renamed. Ignore keys you do not know.

### Testing a consumer

In your tests, Payments may be absent. Inject your own `Callable` where you build `PaymentsApi`,
and call your listener directly with a map shaped like the table above.
