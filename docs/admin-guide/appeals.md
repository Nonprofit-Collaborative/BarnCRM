# Appeals

## What it does

An appeal is a fundraising effort you can name: a spring appeal, a year-end mailing, a
gala, a giving day. Recording the appeal a gift responded to is what lets David say which
efforts paid for themselves and lets Tom see how a campaign is tracking against its goal.

An appeal carries a goal, what it cost to run, its dates, and an optional parent appeal so
a gala can sit inside a larger capital campaign. Total raised and gift count are calculated
from the gifts themselves, so nobody keeps a running total by hand.

## How to turn it on

Appeals arrive with the Giving module. There is nothing to install separately.

1. Open the **Appeals** tab.
2. Create one appeal per effort you want to measure. Do not create one per mailing list or
   per segment: an appeal you cannot report on is an appeal nobody fills in.
3. If you want a particular appeal proposed on new gifts, open **Open Impact Settings**,
   choose **Giving**, and set **Default Appeal**.

No Salesforce Setup step is needed.

## A five-minute walkthrough

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

## Common mistakes

- **Making an appeal its own parent, or a loop.** Open Impact refuses the save with "An
  appeal cannot be its own parent appeal." Choose the larger effort instead, or leave
  **Parent Appeal** empty.
- **Expecting a parent's Total Raised to include its children.** It does not: a parent's
  totals count only gifts given to the parent directly. Group by parent in a report to see
  the whole hierarchy.
- **Creating an appeal per letter variant.** You end up with forty appeals and no
  comparable numbers. One appeal per effort, and use gift type or fund for the detail.
- **Leaving Cost empty and wondering why Net Raised equals Total Raised.** Cost is what you
  spent. Fill it in when the invoice arrives, and net return becomes real.
