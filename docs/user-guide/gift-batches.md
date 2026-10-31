# Gift Batches

A gift batch is how you type a stack of checks in one sitting. You start with the total from the deposit slip (the control total), type one line per check, and post the batch when the lines add up. Posting turns every line into an ordinary gift in one go.

Before you start: open the **BarnCRM Fundraising** app, **Gift Batches** tab. You need the **Fundraising Staff** role (the **Giving Staff** permission set). For a single gift, [Quick Gift Entry](gifts.md) is quicker.

## To Start a Batch

1. Open **Gift Batches** and click **New**.
2. Type a **Description**, for example `Tuesday mail`.
3. Type the **Control Total** from the deposit slip.
4. Check the defaults every line will share unless it says otherwise: **Default Gift Date** (starts at today), **Default Payment Method**, **Default Fund**, **Default Appeal**. Leave **Default Fund** empty to use your organization's default fund.
5. Click **Save**.

You should see: the batch page with its **Batch** details and, below them, the **Lines** card showing **Control total**, **Entered** and a line saying how far apart they are.

## To Type the Lines

1. Click **Add line**.
2. In **Donor**, choose **Person** or **Organization**, then search by name.
3. Type the **Amount** and the **Check Number**.
4. Leave **Date**, **Payment Method**, **Fund** and **Appeal** empty to use the batch's (the method shows **As the batch**). Fill one in only when this check is different.
5. Repeat for every check.
6. Click **Save** whenever you pause. Saved lines are kept if you close the browser.

You should see: **Entered** go up with each line, and the balance line change. When the lines match the control total it says "Balanced: the lines add up to the control total."

To remove a line before posting, click the delete icon at the end of its row.

## To Mark a Check as a Pledge Payment (Pays)

Once a line has a donor who owes a pledge or recurring payment, the **Pays** column shows a list.

1. Read the note under the list. If one payment matches the line's date and amount, it is already chosen; if several could, none is chosen.
2. Choose the right payment, or **None: a new gift on its own**.

You should see: after posting, the payment is **Paid** (or **Partially paid**) and the commitment's **Paid To Date** goes up. Check every line that shows a suggestion before you post.

## To Post a Batch

1. Make sure the balance line says **Balanced**.
2. Click **Post batch**.

You should see: "Batch posted: 3 gifts created." The grid becomes read only, the batch **Status** is **Posted**, and each line's **Gift** column links to the gift it became. A posted batch cannot be changed, posted again or added to. To correct one of its gifts, refund or write off that gift ([Refunds and write-offs](refunds.md)).

A batch's **Posted** status is not the same as a gift posted to accounting.

## To Find an Unfinished Batch

1. Open **Gift Batches**.
2. Choose the **Open Batches** list view.

You should see: every batch not yet posted. Open one and carry on typing.

## Common Problems

- "This batch does not balance: the lines add up to ... less than the control total." A check is missing or an amount is typed low. Find it, or correct the **Control Total** with **Edit** if the slip itself is wrong.
- "This batch does not balance: the lines add up to ... more than the control total." Look for a line entered twice or an amount typed high.
- "Enter the control total from the deposit slip before posting, so there is something to check against." Edit the batch and fill in **Control Total**.
- "Some lines are not finished. Fix the lines marked below, then post again." Each marked line says what is wrong, for example "This line has no donor. Find the person or organization that gave." or "This line has no payment method. Give it one, or set the batch's default payment method."
- "This line needs an amount greater than zero." Money that went back is a refund on the original gift, not a batch line.
- In-kind is not offered as a payment method. A gift of goods has no amount: enter it on its own with [Quick Gift Entry](gifts.md#to-enter-a-gift-of-goods-in-kind).
- "This line pays a payment that is no longer open, or is not this donor's." Its **Pays** cell reads "A payment that is no longer open: choose again". Choose another payment or None, and post again.
- "The books are closed through ..." on a line. That line is dated in a closed accounting period. Date it later and post again; the failed post created nothing.
- "The batch did not post, and no gifts were created." Nothing was lost. Try again; if it repeats, ask your admin to check the Error Log.
- "You can see this batch but not change or post it." You have read access only. Ask your admin for the Giving Staff permission set, or ask the batch's owner for edit access.
- "Batches are easier on a computer." On a phone the grid scrolls sideways. It still works.
- Two people typing the same batch overwrite each other, because each save sends the whole grid. Type a batch on one screen at a time, or split the stack into two batches.

## Related

- [Entering gifts](gifts.md), [Pledges and recurring gifts](commitments.md), [Refunds and write-offs](refunds.md)
- Admin Guide: [Gift batches](../admin-guide/gift-batches.md), [Posting and closed periods](../admin-guide/posting-and-closed-periods.md)
