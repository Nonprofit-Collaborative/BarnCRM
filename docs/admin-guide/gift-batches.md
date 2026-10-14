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
2. Check that a default fund is set: **BarnCRM Settings**, then **Giving**, **Default
   fund**. A line with no fund of its own, in a batch with no fund, goes to that fund, and
   without one the batch cannot post.
3. The people who type batches need the **Giving Staff** permission set, the same one Quick
   Gift Entry needs. The **Fundraising Staff** role includes it. Deleting a batch is kept to
   **Giving Admin**.

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

## Checks that pay a pledge

A check is often a pledge payment. Each line has a **Pays** column for that. Once a line has
a donor, **Pays** lists that donor's payments still owed: scheduled, overdue or partly paid,
on pledges and recurring gifts that are active or paused, including the ones made in the name
of the donor's household. **None: a new gift on its own** is always there, and is what a line
does unless you or a suggestion says otherwise.

A payment is marked **suggested** when its due date is within the date window of the line's
date (its own, or the batch's) and its expected amount is within the allowed difference of
the line's amount. These are the settings gift imports use: **BarnCRM Settings**, **Import**,
**Days either side of a payment's due date** and **Amount difference allowed**. When exactly
one payment is suggested, the line chooses it and the cell says so; when two or more are,
nothing is chosen and you pick. A payment you picked yourself stays picked. Change the amount
or the date, and the list is looked up again; change the donor, and the line goes back to
None until the new donor's list arrives.

Posting links each such gift to its payment and pledge, and the payment's status and the
pledge's paid to date and balance update on their own. Posting checks every chosen payment
again first: one paid or closed since you chose it, or one that is not the line's donor's,
stops the post and names the line, and nothing is created.

Two lines can pay the same payment, for example two checks that each pay half of it. The
payment counts both, and shows Partially paid until they add up to what it expects.

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
to be designated. Set the default fund in BarnCRM Settings and post again; nothing was
created by the failed attempt.

**A line says "This line pays a payment that is no longer open".** The payment was paid, or
its pledge completed or cancelled, after you chose it. Its **Pays** cell reads **A payment
that is no longer open: choose again**. Choose another payment, or None, and post again;
nothing was created by the failed attempt.

**A saved line keeps its choice.** A line you saved keeps the payment it was saved with, or
None, when you open the batch again: nothing is chosen for it in advance a second time. A new
line, or a saved line whose donor you change, gets a suggestion as described above.

**A suggestion chosen for the wrong pledge.** A suggestion is only a suggestion: check the
**Pays** cell of every line that shows one before you post, and choose **None** where the
check is not a pledge payment. If it was posted anyway, open the gift and clear its
**Installment** and **Commitment**; the payment is owed again.

**Typing a batch on a phone.** The grid has ten columns, so on a phone it scrolls sideways
and the screen says **Batches are easier on a computer.** It still works. For one gift on a
phone, Quick Gift Entry is quicker.

**Two people typing the same batch.** Each save sends the whole grid. Type a batch on one
screen at a time, or split the stack into two batches.

**No Add line, Save or Post batch buttons.** The grid says **You can see this batch but not
change or post it.** You have read access only: the Giving Read Only permission set, or
someone else's batch shared with you to read. Ask for the Giving Staff permission set, or
ask the batch's owner (or an administrator, who can change its owner) for edit access.
