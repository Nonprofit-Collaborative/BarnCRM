# Appeals

## What It Does

An appeal is a fundraising effort you can name: a spring appeal, a year-end mailing, a
gala, a giving day. Recording the appeal a gift responded to is what lets David say which
efforts paid for themselves and lets Tom see how a campaign is tracking against its goal.

An appeal carries a goal, what it cost to run, its dates, and an optional parent appeal so
a gala can sit inside a larger capital campaign. Total raised and gift count are calculated
from the gifts themselves, so nobody keeps a running total by hand.

## How to Turn It On

Appeals arrive with the Giving module. There is nothing to install separately.

1. Open the **Appeals** tab.
2. Create one appeal per effort you want to measure. Do not create one per mailing list or
   per segment: an appeal you cannot report on is an appeal nobody fills in.
3. If you want a particular appeal proposed on new gifts, open **BarnCRM Settings**,
   choose **Giving**, and set **Default appeal**.

No Salesforce Setup step is needed.

## A Five-Minute Walkthrough

You are David, and the spring letter goes out on Monday.

1. Open the **Appeals** tab and click **New**.
2. Name it `Spring appeal`, set **Start Date** to the day the letter drops and leave **End
   Date** empty until the appeal closes.
3. Enter a **Goal** of 25,000 and a **Cost** of 1,200 (printing and postage), then save.
4. The appeal page shows **Net Raised** and **Percent To Goal**. Both are calculated as you
   look at them, so they are never stale. Right now **Net Raised** shows minus 1,200,
   because you have spent the money and raised nothing yet.
5. Enter a gift and choose `Spring appeal` on it (see the Gifts page).
6. Once the giving totals have been calculated, come back. **Total Raised** and **Gift
   Count** now include the gift, **Net Raised** is the total less the 1,200 cost, and
   **Percent To Goal** shows how far you have come.
7. Create a second appeal named `Spring appeal: major donor calls` and set its **Parent
   Appeal** to `Spring appeal`, so the phone effort is reported inside the campaign it
   belongs to.

## Online Donation Page

An appeal can have its own public donation page (G-34). Donors fill in a BarnCRM Forms form
on your Salesforce Site and pay on your own Stripe or PayPal checkout page; BarnCRM holds no
money and never sees card details. It needs the **Forms** and **Payments** modules, a public
Site for Forms, and your processor keys entered on Payments Setup (see
[Payments](payments.md) and [Forms](forms.md)).

1. Build a public form in the **Form Builder**. Give it a **Number** question with the key
   `amount` (the gift amount) and the person questions Forms needs to match the donor (first
   name, last name, email). Keys `email`, `firstName` and `lastName` also fill in the
   processor's page. Publish it and turn on **Public**.
2. On the appeal, paste the form's record ID into **Donation Form ID** and tick **Donation
   Page**. The appeal must be **Active**. Health Check lists any active appeal with Donation
   Page on whose form has no `amount` question.
3. Share `<your Site address>/FormsPublic?record=<the appeal's record ID>`. The page shows
   the appeal's name, description and goal, then the form under **Give Now**.

When a donor sends the form, they go straight to the processor's checkout. Their gift
appears on the appeal once Forms has processed the submission: **Pending** until the payment
is confirmed, then **Received** (dated the day it was paid), or **Cancelled** if they left the
checkout without paying. A refund made at the processor sets the gift to **Refunded**. The
payment's identifier is in the gift's **Payment Reference**.

If Payments is not installed or its keys are missing, the page shows the appeal and says online
giving is not open. Recurring online gifts are not offered yet.

Against card testing (stolen cards tried with tiny gifts), a page refuses a gift below
**Donation Page Minimum Amount** (Settings, Giving section; default 5) and refuses new checkouts
once the appeal has started 30 in the last hour. A refused gift starts no checkout, the form says
it could not be sent, and the Error Log says why.

If a payment that was Cancelled is paid late, or a Pending gift is refunded, the gift is moved
through the step the gift status rules need (Cancelled to Pending to Received; Pending to
Received to Refunded), so it always ends at the payment's status.

## List Views

**Appeals** has **All Appeals**, **Active Appeals** and **Inactive Appeals**.

## Common Mistakes

- **A donation form without an `amount` question.** The donor is told something went wrong
  and nothing is stored. Add a Number question with the key `amount`.
- **Payments still in Test mode.** Donors reach the processor's test checkout and no money
  moves. Switch Payments to Live when you are ready.
- **Making an appeal its own parent, or a loop.** BarnCRM refuses the save with "An
  appeal cannot be its own parent appeal." Choose the larger effort instead, or leave
  **Parent Appeal** empty.
- **Expecting a parent's Total Raised to include its children.** It does not: a parent's
  totals count only gifts given to the parent directly. Group by parent in a report to see
  the whole hierarchy.
- **Creating an appeal per letter variant.** You end up with forty appeals and no
  comparable numbers. One appeal per effort, and use gift type or fund for the detail.
- **Leaving Cost empty and wondering why Net Raised equals Total Raised.** Cost is what you
  spent. Fill it in when the invoice arrives, and net return becomes real.
