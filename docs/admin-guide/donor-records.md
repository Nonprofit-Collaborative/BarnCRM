# A Donor's Giving on Their Record

## What It Does

When David opens a person, a household or an organization in the **Fundraising** app, the
record shows what they gave: a **Giving** section with their totals, their donor level and
when those numbers were last calculated, and lists of their gifts, commitments, soft
credits, receipts and stewardship plans. A person also shows their **Employer**, which
[matching gifts](matching-gifts.md) check against. A **New Gift** button records a gift with
the donor already filled in.

Nothing here is calculated on the page. The totals are the rollups BarnCRM keeps (see
[Rollups](rollups.md)), and **Rollups Last Calculated** says how fresh they are.

## How to Turn It On

Nothing to do: it arrives with the Giving module. BarnCRM Giving ships two record pages,
**Giving Contact Record Page** and **Giving Account Record Page**, and the Fundraising app
opens people, households and organizations on them.

Two things to know:

- **In the BarnCRM app, records open on Core's pages, which show no giving.** BarnCRM Core
  is also used by organizations that do not fundraise, so it cannot show giving. If your
  staff work in the BarnCRM app and should see giving there too, open Setup, then
  **Lightning App Builder**, edit **Giving Contact Record Page**, choose **Activation**,
  then **App, Record Type, and Profile**, and assign it to the BarnCRM app on desktop and
  phone. Do the same for **Giving Account Record Page**. This is the one step that needs
  Setup, because a page can only be assigned to another package's app there.
- **If your organization has its own Contact or Account record page,** it keeps showing
  wherever you assigned it. To add giving to it instead, open it in the Lightning App Builder
  and add the giving fields from the field list, and the **Dynamic Related List - Single**
  component for Gifts, Commitments, Soft Credits, Receipts and Stewardship Plans.

## A Five-Minute Walkthrough

Start with the sample data loaded (BarnCRM Settings, then Sample Data).

1. Open the **Fundraising** app and its **Contacts** tab, and open a person who has given.
2. Find the **Giving** section. **Total Giving**, **Last Gift Date** and the rest are filled,
   and **Rollups Last Calculated** shows a date and time.
3. Scroll to **Gifts**. Each gift the person gave is listed, newest first.
4. Click **New Gift** at the top of the page. The donor is already this person. Enter an
   **Amount** of 50, choose a **Payment Method**, and save. The gift appears in the list.
5. Refresh the page. **Total Giving** has gone up by 50 and **Rollups Last Calculated** has
   moved to now.
6. Open the person's household from the **Household** card. The household's **Giving**
   section counts the gift too, and its **Gifts** list shows every gift credited to the
   household, from any member.
7. Open an organization that gave. Its **Gifts** list shows the gifts it gave in its own name.

## Common Mistakes

- **"I see no Giving section."** The record was opened outside the Fundraising app, or your
  organization assigned its own record page. Switch to the Fundraising app, or follow the
  first item under "How to turn it on".
- **Totals that look out of date.** Look at **Rollups Last Calculated**. If it is days old,
  the nightly rollup is not scheduled: see [Rollups](rollups.md).
- **A gift entered from a household that should have been from a person.** New Gift on a
  household records the household as the donor. When one person gave, open that person and
  use New Gift there, so the gift is credited to them and still counts for the household.
