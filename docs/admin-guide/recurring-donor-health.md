# Recurring Donor Health

## What It Does

Recurring donors (sustainers) are usually lost quietly: a card fails or expires and nobody
notices until the gifts have stopped. **Recurring Donor Health** (feature G-27) brings those
signs together for every open-ended recurring gift (a Commitment of Type **Recurring**):

- **Monthly Recurring Revenue**: what your active recurring gifts bring in a month, with each
  gift's amount turned into a monthly value (a yearly gift of 120 counts as 10 a month).
- **Recurring Gifts Received, Last 12 Months**: received gifts on recurring commitments, by
  month.
- **Save the Sustainer**: the active recurring gifts that need attention, largest first, with
  the reasons and a **Create Follow-Up Task** button.

A gift is on the Save the Sustainer list when any of these is true:

| Reason | Where it comes from |
|---|---|
| Failed charges | The processor reported a failed charge and no successful one since. |
| Card expires soon | The card's expiry month is within **Card expiry warning days** (default 60). |
| Cancelled at the processor | The processor reported the recurring gift cancelled. |
| Payment overdue | A scheduled payment is Overdue (see [Commitments](commitments.md)). |

The commitment's Status never changes by itself: when a sustainer has really stopped, you set
the commitment to Cancelled.

## Where the Processor News Comes From

BarnCRM calls no payment processor and stores no card data; a card is known only by its expiry
month. The news arrives as **Recurring Gift Event** records, written by a Zapier recipe from your
own Stripe, PayPal or giving tool account (the same approach as
[Online giving through Zapier](online-giving-zapier.md)), or entered by hand.

Each event has an **Event Type** (Charge Failed, Charge Succeeded, Card Expiring, Card Updated or
Cancelled), an **Event Date**, and a way to find the gift: a **Subscription Id** that matches the
commitment's **Processor Subscription Id**, or the donor's **Donor Email**. Use the processor's
event id as **External Id** with Zapier's upsert action, so a recipe that runs twice records the
event once.

When the event is saved, BarnCRM finds the recurring gift:

1. The commitment whose **Processor Subscription Id** equals the event's **Subscription Id**
   (case is ignored).
2. Otherwise, the one Active or Paused recurring gift whose donor's email equals **Donor
   Email**. If the donor has two or more, none is chosen.

A found event is **Matched** and updates the gift: **Failed Charges**, **Last Failed Charge**,
**Card Expires** and **Cancelled at Processor** on the commitment. A successful charge sets
Failed Charges back to 0 and clears Cancelled at Processor. An event that matched nothing is
**Unmatched**; the page counts them. Open **Recurring Gift Events**, list view **Unmatched
Events**, choose the **Commitment** on each, and it is applied then.

### A Zapier Recipe

1. Trigger: your processor's event in Zapier (for example Stripe **Failed Payment** or
   **Canceled Subscription**).
2. Action: Salesforce **Create Record** (or **Create or Update Record** on External Id),
   object **Recurring Gift Event**. Map the event type as one of the five values, the date,
   the subscription id, the customer email, the card expiry (last day of the month), the
   amount, the decline reason and the event id.
3. Run it as a Salesforce user with **Giving Staff**; that user does not need to see the
   commitments.

Store each gift's subscription id in **Processor Subscription Id** on its commitment when you
can: matching by id is exact, matching by email is a fallback.

## Settings

**BarnCRM Settings**, Giving section:

| Setting | Default | What it does |
|---|---|---|
| Card expiry warning days (`Recurring_Card_Expiry_Days__c`) | 60 | How many days before a card's expiry month ends the gift joins the list. 0 to 365. |

The matching and updating can be switched off on the **Automation** page (registry row
**Recurring gift event: match and apply**).

## Who Can Use It

| Permission set | Recurring Donor Health page | Recurring Gift Events | Health fields on Commitment |
|---|---|---|---|
| Giving Admin | Yes | Create, edit, delete; sees all | Edit |
| Giving Staff | Yes | Create and edit their own | Read; edit Processor Subscription Id |
| Giving Read Only | Yes | Read their own | Read |

The page shows each person only the commitments they may see (commitments are private), so its
figures are that person's share. Giving Admin sees all.

## Good to Know

- At most 200 gifts are listed; the largest monthly values come first.
- Monthly values: Weekly x 52 / 12, Every two weeks x 26 / 12, Monthly x 1, Quarterly / 3,
  Twice a year / 6, Yearly / 12.
- **Create Follow-Up Task** makes a task for you, due today, on the commitment and its donor.
- Nothing here is paid or sends anything; the recipe runs in your own Zapier account.
