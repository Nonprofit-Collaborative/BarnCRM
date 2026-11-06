# A Donor's Giving on Their Record

## What It Does

When David opens a person, a household or an organization in the **BarnCRM Fundraising** app, the
record shows what they gave. On the **Details** tab, a **Giving** section holds the everyday
figures (total, this year, last year, largest and last gift, pledge balance, donor level and
giving pattern), and **Giving Details** below it the scores, counts, first gift, soft credits
and when the numbers were last updated. The **Related** tab lists their gifts, commitments,
soft credits, receipts, stewardship plans and asks. A person also shows their **Employer**, which
[matching gifts](matching-gifts.md) check against. An **Enter a Gift** button opens
[Quick Gift Entry](quick-gift-entry.md) with the donor already filled in.

Nothing here is calculated on the page. The totals are the rollups BarnCRM keeps (see
[Rollups](rollups.md)), and **Totals Last Updated** says how fresh they are.

## How to Turn It On

Nothing to do: it arrives with the Giving module. BarnCRM Giving ships two record pages,
**Giving Contact Record Page** and **Giving Account Record Page**, and the BarnCRM Fundraising app
opens people, households and organizations on them.

Two things to know:

- **In the BarnCRM app, records open on Core's pages, with a Giving at a Glance card.** With
  Giving installed, the top of the sidebar on a person, household or organization shows
  **Giving at a Glance**: **Total Giving**, **Last Gift Date**, **Donor Level** and an
  **Enter a Gift** button that opens Quick Gift Entry with the donor filled in. Nothing to
  turn on. The card shows only to people with a Giving permission set, and the button only
  to people who can create gifts. Without Giving the card is not there. If your staff should
  see the whole Giving page in the BarnCRM app instead, open Setup, then
  **Lightning App Builder**, edit **Giving Contact Record Page**, choose **Activation**,
  then **App, Record Type, and Profile**, and assign it to the BarnCRM app on desktop and
  phone. Do the same for **Giving Account Record Page**. This is the one step that needs
  Setup, because a page can only be assigned to another package's app there.
- **If your organization has its own Contact or Account record page,** it keeps showing
  wherever you assigned it. To add giving to it instead, open it in the Lightning App Builder
  and add the giving fields from the field list, and the **Dynamic Related List - Single**
  component for Gifts, Commitments, Soft Credits, Receipts and Stewardship Plans. For the
  glance card, add the **Record Glance** component.

## A Five-Minute Walkthrough

Start with the sample data loaded (BarnCRM Settings, then Sample Data).

1. Open the **BarnCRM Fundraising** app and its **Contacts** tab, and open a person who has given.
2. On the **Details** tab, find the **Giving** section. **Total Giving**, **Last Gift Date**
   and the rest are filled, and in **Giving Details** **Totals Last Updated** shows a date
   and time.
3. Click the **Related** tab. **Gifts** lists each gift the person gave, newest first.
4. Click **Enter a Gift** at the top of the page. Quick Gift Entry opens in a window with
   this person already the donor. Enter an **Amount** of 50, choose a **Payment Method**, and
   click **Save**. The window closes and the gift appears in the list.
5. Refresh the page. **Total Giving** has gone up by 50 and **Totals Last Updated** has
   moved to now.
6. Open the person's household from the **Household** card on the **Connections** tab. The household's **Giving**
   section counts the gift too, and its **Gifts** list shows every gift credited to the
   household, from any member.
7. Open an organization that gave. Its **Gifts** list shows the gifts it gave in its own name.

## Common Mistakes

- **"I see no Giving section."** The record was opened outside the BarnCRM Fundraising app, or your
  organization assigned its own record page. Switch to the BarnCRM Fundraising app, or follow the
  first item under "How to turn it on".
- **Totals that look out of date.** Look at **Totals Last Updated**. If it is days old,
  the nightly rollup is not scheduled: see [Rollups](rollups.md).
- **A gift entered from a household that should have been from a person.** Enter a Gift on a
  household records the household as the donor. When one person gave, open that person and
  use Enter a Gift there, so the gift is credited to them and still counts for the household.
