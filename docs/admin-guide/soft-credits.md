# Soft credits

## What it does

A soft credit is recognition for a gift someone influenced but did not legally give: a
spouse who shares the household's giving, the board member who asked, the honoree a
memorial gift remembers. Open Impact keeps soft credits separate from the money, so your
receipts and your bank reconciliation stay exactly right while your donor lists still show
everyone who deserves the thank you.

Open Impact can also do the most common one for you. When a gift arrives from one member
of a household, every other current member of that household is soft credited
automatically, so a phone call to Luis Garcia about "your family's giving" is never a
surprise to him.

## How to turn it on

1. Open **Open Impact Settings** and choose **Giving**.
2. Find **Automatic household soft credits**. It is on when you install Open Impact.
3. Leave it on if your organization thanks and reports on households. Turn it off if you
   want soft credits only where a person entered one by hand.

That is the whole setting. Nothing here needs Salesforce Setup.

One piece of first-time setup does: the **Soft credits** panel lives on a gift's record
page, and Open Impact ships a page called **Gift Record Page** with the panel already on
it. Assign it once, as your org default for Gift, and every gift shows the panel from then
on. If your organization has built a gift record page of its own, add the **Gift Soft
Credits** component to that page instead.

Two things to know about how the automatic credits behave:

- **A household soft credit is for the full amount of the gift.** If Ana gives 500, Luis
  is credited with 500, not 250. This is the convention nonprofits and NPSP have always
  used: recognition is not divided, because both people are being recognized for the same
  gift. Soft credit totals across a household will therefore be larger than the household
  gave, which is correct and is why they are reported separately from giving totals.
- **The package looks after the credits it created and never touches the ones you
  entered.** Change the donor or the amount on a gift and the automatic credits are
  recalculated. Delete the gift and they go with it. A soft credit David entered by hand
  stays exactly as he left it.
- **A refund reverses a credit, it does not erase it.** A refund is recorded as a second
  gift for a negative amount, and that gift earns its own automatic credits, which are
  negative. The gift being refunded keeps the credit it earned. So Luis, credited 500 for
  Ana's gift, keeps that 500 and gains a credit of minus 500 on the refund, and his Total
  Soft Credits is nothing. Both rows carry the Automatic badge, and a negative credit is
  the package working rather than a fault. This is the same shape as the gifts themselves,
  where the refunded gift also keeps its row. A **matched donor** credit reverses the same
  way: refund a company's matching gift and the employee gets a negative credit for what
  went back, so a match of 500 with 200 returned leaves them recognized for 300. See
  `matching-gifts.md`.

## A five-minute walkthrough

You are David, the development director. Start from the sample data, which includes the
Garcia household: Harper Garcia, her spouse Luis Garcia, and their son Diego.

1. Click the **Gifts** tab and press **New**.
2. Enter a gift from **Harper Garcia** for **500**, dated today, type **Check**, status
   **Received**. Save.
3. On the gift you just saved, look at **Soft credits**. Luis Garcia and Diego Garcia are
   already there, each with the role **Household member**, the amount **500**, and an
   **Automatic** badge. Every other current member of the household is credited, not just
   the spouse, and you did nothing to make that happen.
4. Now add the solicitor. In the **Soft credits** panel press **Add credit**, pick the
   person who asked for the gift, choose the role **Solicitor**, leave the amount at 500,
   and press **Save**. The new credit appears with no Automatic badge, because you entered
   it.
5. Open **Luis Garcia** and look at **Total soft credits**. It shows 500. His **Total
   giving** is unchanged, because he did not give this gift. That separation is the point
   of the feature.
6. Go back to the gift and change the amount from 500 to **750**. Save, then look at the
   soft credits again: Luis and Diego are now credited with 750, and the solicitor credit you entered
   is still 500, because it is yours to change.
7. Remove the solicitor credit with the **Remove** button beside it. The automatic credits
   for Luis and Diego have no Remove button: it belongs to the gift, and it goes when the gift goes.

## Common mistakes

- **Expecting soft credits to add up to the gift.** They do not, and they are not meant
  to. Two people can each be recognized for the whole of a gift. If a total looks too
  large, check that you are reading Total soft credits and not Total giving.
- **Trying to fix a household credit by editing it.** An automatic credit is recalculated
  from the gift, so an edit is overwritten the next time the gift is saved or the household
  changes. Fix the gift, or fix who is in the household, and the credit follows. If you need different wording or
  a different amount for one person, add a credit of your own instead.
- **Expecting a household move to show up instantly.** Adding someone to a household, or
  moving them out of one, does recredit the household's gifts, including the ones already
  entered: a new spouse is credited on last year's gifts and a person who moves out stops
  being credited on gifts they no longer share. That work is queued rather than done while
  you wait, so give it a moment and refresh. A household that has given more than 500
  gifts has its most recent 500 recredited, and the rest follow the next time each of those
  gifts is saved.
- **Turning the setting off and expecting old credits to vanish that minute.** Turning off
  automatic household soft credits stops new ones at once. A credit already on a gift goes
  the next time that gift is saved, so your reporting history does not change under you
  the moment somebody flips a checkbox.

## Fields, for report builders

| What you see | Field |
|---|---|
| The gift being credited | Gift |
| The person or organization credited | Contact, Account |
| Why they are credited | Role, Custom role |
| How much they are recognized for | Amount, Percent |
| Created and maintained by Open Impact | Is automatic |
