# Memberships

A **membership** is one term (a year, say) of one member at one **level**. A member is a person,
a household or an organization. When a member renews, BarnCRM adds the next term and marks the
old one Renewed, so each year's dates and payment stay as they were. Your BarnCRM admin sets up
the levels (see [Memberships](../admin-guide/memberships.md) in the Admin Guide).

## To Add a Member

1. Open the **BarnCRM** (or **BarnCRM Console**) app and the **Memberships** tab, then click **New**.
2. Choose the **Level**, and the **Contact** (a person's own membership), the **Household or
   Organization**, or both (an organization member and the person you deal with).
3. Leave **Status** Current, or choose **Pending** for a member who will pay online.
4. Save. BarnCRM fills the dues from the level, a start date of today, the end date from the
   level's term, and **Member Since**.

## What the Status Means

| Status | Meaning |
|---|---|
| Pending | Not paid yet |
| Current | In its term |
| Grace | Ended, but still in the level's grace days |
| Lapsed | Ended and past the grace days |
| Renewed | A newer term follows it |
| Cancelled | Ended early, or its online payment was refunded |

BarnCRM moves ended memberships to Grace and then Lapsed each morning. A membership with no end
date never lapses.

## To Renew a Membership

1. Open the membership and click **Renew** in the membership panel.
2. Choose the level (the same one is chosen for you) and confirm.

The new term starts the day after the old one ends when it is Current or in Grace, or today when
it has lapsed. Gifts to your membership fund and online payments can renew memberships by
themselves; you do not need to renew those by hand.

## To Send a Payment Link

When your organization takes dues online, click **Email Payment Link** on the membership. The
member gets an email with a link to pay on Stripe's or PayPal's own page. The link works for about
a day; send a new one if it has stopped working. When the payment arrives (up to 15 minutes
later), BarnCRM dates the membership on it: a Pending membership becomes Current, and any other is
renewed.

## The Directory Listing

A member chooses whether they appear in your online member directory, from your member portal.
On the membership, **Listed in Directory**, **Directory Location** and **Directory Bio** show
what they chose. Change them only when the member asks you to.
