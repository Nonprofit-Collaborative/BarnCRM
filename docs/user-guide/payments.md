# Payments

When your organization takes money online (a paid event registration, an online gift, dues),
the payer pays on Stripe's or PayPal's own page, and BarnCRM keeps a **payment** record of it.
You look payments up; you never enter or change one. Your BarnCRM admin sets payments up (see
[Payments](../admin-guide/payments.md) in the Admin Guide).

## To Find a Payment

1. Open the **BarnCRM** (or **BarnCRM Console**) app and the **Payments** tab.
2. Choose a list view, or search by the payment number (PAY-000123), the payer's name or email.
3. Open the payment. It shows the amount, what it was for, who paid, its **Status**, when it was
   paid, any amount refunded and, if it failed or was cancelled, why.

## What the Status Means

| Status | Means |
|---|---|
| Pending | The payer was sent to the checkout page and has not paid yet. |
| Paid | The money was received. |
| Failed | The card or payment was declined. The payer may try again. |
| Refunded | The whole amount was given back. A partial refund stays Paid with **Amount Refunded** filled in. |
| Cancelled | The payer left the checkout page, or it expired. |

A payment can take up to 15 minutes to change from Pending to Paid after the payer pays.
**Mode Test** marks a practice payment that took no real money.

## To Refund a Payment

Refunds are made in Stripe or PayPal, not in BarnCRM. Ask whoever manages your Stripe or
PayPal account. BarnCRM records the refund on the payment by itself.
