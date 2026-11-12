# Payments

Scripts for the optional BarnCRM Payments module: settings and keys, Health Check, a Stripe and a PayPal test payment end to end, refunds, each processor event used once, abandoned checkouts and access. Setup detail: [Payments](../admin-guide/payments.md). Online giving through Zapier (MIG-06) is guidance only and has no script.

Before you start: an org from [Before you test](before-you-test.md), with Core and Payments deployed, an active Salesforce Site, a Stripe account in test mode and a PayPal developer account with a sandbox app and a sandbox buyer. No module charges through Payments yet, so the scripts start a checkout from **Developer Console**, **Debug**, **Open Execute Anonymous Window**, with:

```apex
Callable api = (Callable) Type.forName('PaymentsApi').newInstance();
System.debug(api.call('startCheckout', new Map<String, Object>{
  'amount' => 25, 'description' => 'Test payment', 'payerEmail' => 'tester@example.org',
  'successUrl' => 'https://example.org/thanks', 'cancelUrl' => 'https://example.org/cancelled'
}));
```

Open the debug log and copy the `checkoutUrl` value into a browser.

## T-PAY-01: Settings and Health Check

**Purpose:** confirm the settings show their defaults and Health Check lists what is missing.
**Prerequisites:** admin (BarnCRM Admin, which gives Payments Admin).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Payments**. | **Processor** Stripe, **Mode** Test, **Default currency** USD, and a **Payments Setup** link. |
| 2 | Open **Health Check**. | `Payment Keys Are Missing` for Stripe, `Payment Processing Is Not Scheduled` with **Schedule Payment Processing**, and, if the Site guest lacks it, `A Site Guest User Can't Receive Payment News` with **Give Payments Webhook Guest**. |
| 3 | Select both fixes. | Both findings are gone after the page refreshes. **Setup > Scheduled Jobs** lists four `BarnCRM Payments Processing` jobs. |
| 4 | Open **Payments Setup**. | "Processing is scheduled" and no **Schedule Processing** button. |
| 5 | In **Setup > Scheduled Jobs**, delete the four `BarnCRM Payments Processing` jobs. Reload **Payments Setup**. | A warning that processing is not scheduled and a **Schedule Processing** button. |
| 6 | Select **Schedule Processing**. | "Processing is scheduled"; the four jobs are back in **Scheduled Jobs**. |

**Cleanup:** None.

## T-PAY-02: Keys Are Never Shown Again

**Purpose:** confirm keys are write-only and the mode check works.
**Prerequisites:** admin, after T-PAY-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Payments Setup**. | A Stripe address and a PayPal address on your Site, ending `/payments/v1/stripe` and `/payments/v1/paypal`. Every key reads **Not set**. |
| 2 | Enter your Stripe test secret key and a made-up signing secret `whsec_test1234`, and select **Save Keys**. | Both read **Set**, ending `...` and their last four characters. The boxes are empty again. |
| 3 | Reload the page and view its source or the network response. | No key appears anywhere, only the last four characters. |
| 4 | In **BarnCRM Settings**, set **Mode** to Live. Open **Health Check**. | `Stripe Key Does Not Match the Mode`. Set **Mode** back to Test: the finding is gone. |

**Cleanup:** None.

## T-PAY-03: A Stripe Test Payment

**Purpose:** confirm checkout on Stripe's page and Paid from the verified event.
**Prerequisites:** admin; in Stripe test mode, a webhook endpoint at the Stripe address with the six events the Admin Guide lists; its real signing secret saved in **Payments Setup** (replacing T-PAY-02's).

| Step | Action | Expected result |
|---|---|---|
| 1 | Run the snippet above. | The debug log shows a `paymentId`, a `checkoutUrl` on `checkout.stripe.com` and status `Pending`. |
| 2 | Open the **Payments** tab and the new payment. | Status **Pending**, Amount 25.00, Currency USD, Processor Stripe, Mode Test. |
| 3 | Open the `checkoutUrl`, pay with card `4242 4242 4242 4242`, any future date, any CVC. | Stripe shows its success page, then goes to `https://example.org/thanks`. |
| 4 | Wait for the next quarter hour (or run `System.enqueueJob(new PaymentEventProcessor.Run());` in Execute Anonymous). | The payment is **Paid** with **Paid At** filled in. **Payment Events** shows `checkout.session.completed` **Applied**. |

**Cleanup:** None (T-PAY-04 uses this payment).

## T-PAY-04: Refunds

**Purpose:** confirm partial and full refunds from Stripe.
**Prerequisites:** admin, after T-PAY-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Stripe, refund 10.00 of the payment. Process as in T-PAY-03 step 4. | The payment stays **Paid** with **Amount Refunded** 10.00. |
| 2 | Refund the remaining 15.00. Process again. | **Refunded**, Amount Refunded 25.00. |

**Cleanup:** None.

## T-PAY-05: Each Event Used Once, Forged Events Refused

**Purpose:** confirm idempotency and signature checks.
**Prerequisites:** admin, after T-PAY-04.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Stripe, **Developers > Events**, open the `charge.refunded` event and select **Resend**. | Stripe reports a 200 answer. **Payment Events** gains no new row and the payment is unchanged. |
| 2 | From a terminal, `curl -X POST <Stripe address> -H 'Stripe-Signature: t=1,v1=00' -d '{}'`. | The answer is 400. No Payment Event is added. |

**Cleanup:** None.

## T-PAY-06: A PayPal Sandbox Payment

**Purpose:** confirm the approve link, capture and Paid.
**Prerequisites:** admin; the PayPal sandbox app's client id, secret and webhook id (webhook at the PayPal address with the five events the Admin Guide lists) saved in **Payments Setup**; processing scheduled.

| Step | Action | Expected result |
|---|---|---|
| 1 | Run the snippet with `'processor' => 'PayPal'` added. | A `checkoutUrl` on `sandbox.paypal.com`. |
| 2 | Open it, sign in as the sandbox buyer and approve. | PayPal goes to `https://example.org/thanks`. The payment is still **Pending**. |
| 3 | Process twice (approval, then the capture event). | The payment is **Paid**. Payment Events shows `CHECKOUT.ORDER.APPROVED` and `PAYMENT.CAPTURE.COMPLETED` **Applied**. |
| 4 | In the sandbox merchant account refund the payment and process. | **Refunded**. |

**Cleanup:** None.

## T-PAY-07: Abandoned and Expired Checkouts

**Purpose:** confirm a checkout left unpaid ends Cancelled.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Run the snippet, open the Stripe page and close it without paying. In Stripe, open the session under **Payments > Checkout sessions** and expire it (or wait 24 hours). Process. | The payment is **Cancelled**, Detail `The checkout expired or was left.` |
| 2 | Run the snippet with `'processor' => 'PayPal'` and never open the link. Two days later, process. | **Cancelled** with the same detail. |

**Cleanup:** None.

## T-PAY-08: Who Can Do What

**Purpose:** confirm staff and read only users see payments and cannot change them.
**Prerequisites:** a Team Member user and a Read Only user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the Team Member, open the **Payments** tab and a payment. | The payment shows; there is no **Edit** and no **Delete**. **Payments Setup** and **Payment Events** are not in the app. |
| 2 | As the Read Only user, the same. | The same. |

**Cleanup:** None.
