# Gift Batches

## What it does

A gift batch is how a stack of checks gets typed in one sitting. You start a batch with the
total from the deposit slip (the **control total**) and the things every gift in the stack
shares: the date they arrived, how they arrived, the fund and the appeal. Then you type one
line per check: who gave, how much, and the check number. The screen keeps a running total
beside the deposit slip total and tells you, in words, how far apart they are.

When the two totals agree, **Post batch** turns every line into a gift, in one go. A batch
that does not balance does not post, and neither does one with an unfinished line. Once
posted, a batch cannot be posted again, changed or added to: it is the record of what went
to the bank, and each line links to the gift it became. One gap to know about: someone with
the Giving Staff or Giving Admin permission set can still delete a line of a posted batch
from outside this screen (a report, a data tool or the API). Its gift is untouched; only the
batch's record of the deposit loses that line.

Gifts from a batch are ordinary gifts. They count in the giving totals, get their household
and their fund, can be receipted and acknowledged, and appear on the dashboard, exactly as a
gift entered on Quick Gift Entry does.

## How to turn it on

Nothing to install and no Setup step. Gift batches arrive with the Giving package.

1. Open the **Fundraising** app from the app launcher. **Gift Batches** is one of its tabs.
2. Check that a default fund is set: **Open Impact Settings**, then **Giving**, **Default
   fund**. A line with no fund of its own, in a batch with no fund, goes to that fund, and
   without one the batch cannot post.
3. The people who type batches need the **Giving Staff** permission set, the same one Quick
   Gift Entry needs. Deleting a batch is kept to **Giving Admin**.

There are no settings for batches themselves.

## A five-minute walkthrough

Do this as David, with the Tuesday mail: three checks and a deposit slip that says 350.00.

1. Open **Fundraising**, then **Gift Batches**, and click **New**.
2. In **Description**, type `Tuesday mail`. In **Control Total**, type `350`. **Default
   Gift Date** is already today and **Default Payment Method** is already Check. Pick
   **Spring Appeal** as the **Default Appeal**. Leave **Default Fund** empty. Click **Save**.
3. The batch opens. Under the batch details is the **Lines** card, with **Control total
   350.00**, **Entered 0.00**, and a line saying the lines add up to 350.00 less than the
   control total.
4. Click **Add line**. Leave the donor type on **Person**, search for `Garcia` and pick Ana
   Garcia. Type `100` in **Amount** and `1042` in **Check number**.
5. Click **Add line** again. Choose **Organization**, pick Riverside Foundation, type
   `200`, and in **Fund** pick Building Fund, because their letter says so. This one line
   now goes to the Building Fund; the others still follow the batch.
6. Add a third line: a person, `25`. The status line now says they add up to 25.00 less.
   Look at the check again: it is for 50. Change the amount to `50`. The status line says
   **Balanced**.
7. Click **Save**. The lines are stored, so closing the browser now loses nothing. You can
   find the batch again under **Gift Batches**, list view **Open Batches**.
8. Click **Post batch**. A message says three gifts were posted. The grid becomes read only
   and every line shows the gift it became, as a link.
9. Click the first gift link. It is dated today, type Check, appeal Spring Appeal, check
   number 1042, with one allocation to your default fund.

## Common mistakes

**The batch does not balance.** The message says how far out it is and in which direction:
**the lines add up to 25.00 less than the control total** means a check is missing or an
amount is typed low; **more** means a line is entered twice or an amount is typed high.
Nothing posts until it balances. If the deposit slip itself is wrong, correct **Control
Total** with **Edit** at the top of the batch.

**A line has no donor.** A line can be saved before its donor is found, so you can type the
amount from the check and look the person up afterwards. Posting refuses it and marks the
line: **This line has no donor.** Find the donor or remove the line.

**Typing a refund as a negative line.** Refused: a batch is money that came in. A refund is
recorded from the original gift, with its refund action.

**Entering goods.** In-kind is not a payment method in a batch, because a gift of goods has
no amount. Enter it on its own with Quick Gift Entry, choosing In-kind.

**Changing a default after typing lines.** That is fine and is what you want: every line
that left the date, method, fund or appeal empty follows the batch, so correcting the
default corrects them all. A line where you chose something else keeps its own choice.

**Posting the wrong batch, or a wrong amount slipping through.** A posted batch cannot be
reopened. Correct the gift itself, by refund or write-off, as with any gift.

**A line dated in a closed period.** Posting fails and names the line: `The books are closed
through...`. Date it after the close date and post again; nothing was created by the failed
attempt. A batch's **Posted** status is not the same as a gift posted to accounting (see
[Posting and Closed Periods](posting-and-closed-periods.md)).

**No default fund anywhere.** Posting fails and names every line: the gifts have nowhere
to be designated. Set the default fund in Open Impact Settings and post again; nothing was
created by the failed attempt.

**Two people typing the same batch.** Each save sends the whole grid. Type a batch on one
screen at a time, or split the stack into two batches.

**No Add line, Save or Post batch buttons.** The grid says **You can see this batch but not
change or post it.** You have read access only: the Giving Read Only permission set, or
someone else's batch shared with you to read. Ask for the Giving Staff permission set, or
ask the batch's owner (or an administrator, who can change its owner) for edit access.
