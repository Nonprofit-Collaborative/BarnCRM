# Refunds and Write-Offs

Sometimes money goes back: a card is charged twice, a donor asks for a gift back, or a check bounces. BarnCRM never edits or deletes the original gift. It records a second gift for a negative amount, linked to the original, with your reason on it, so totals correct themselves and anyone can see what happened.

Before you start: you need the **Fundraising Staff** role (the **Giving Staff** permission set). With **Giving Read Only** you can see refunds but not record one.

## To Refund Part or All of a Gift

1. Open the gift. Its **Status** must be `Received`.
2. Click **Refund or Write Off**.
3. Leave **Refund part or all of this gift** selected.
4. Check **Left on this gift**. **How much is going back** starts at that figure; change it for a partial refund.
5. Type **Why is it going back**. A reason is required.
6. Click **Record it**.

You should see: "Recorded. The gift it reverses now shows what happened." The refund appears in the original's **Refunds and Write-Offs** list. Open it: a negative gift dated today, with **Original Gift** and **Refund Reason** filled in, the same donor and appeal, and allocations that mirror the original's funds.

The original keeps its amount. Its **Status** stays `Received` after a partial refund, and turns `Refunded` once everything has gone back, at which point **Refund or Write Off** leaves the page.

## To Write Off a Gift

Use a write-off when money recorded as received will not be kept, for example a check returned unpaid by the bank.

1. Open the gift and click **Refund or Write Off**.
2. Choose **Write off what is left of this gift**. There is no amount to type: a write-off is always what is left.
3. Type **Why is it going back** and click **Record it**.

You should see: a linked negative gift for the remaining amount, and the original's **Status** is `Written off`.

## To Cancel a Pending Gift

A Pending gift is money you expect. If it will never arrive, cancel it instead of writing it off: nothing was received.

1. Open the gift and click **Edit**.
2. Set **Status** to **Cancelled** and click **Save**.

You should see: the gift saved as `Cancelled`, with no negative gift. A Cancelled gift is in no total, export, receipt or thank-you. If it was paying a pledge installment, that payment is free for the next gift. If the money turns up after all, set the gift back to **Pending**, then to **Received**.

## What Happens to Totals

- **Donor totals**: the negative gift cancels the refunded part. A donor who gave 250 and got 100 back shows 150 in total giving. A fully refunded gift leaves the total at zero but still counts as one gift.
- **Last gift date** stays on the original gift's date.
- **Funds, appeals and pledges**: the same arithmetic runs on fund and appeal totals and on a pledge's **Paid To Date**. A refunded pledge payment goes back to **Partially paid** or unpaid.
- **Soft Credits**: the refund gets its own automatic credits for minus the amount. The original credit stays, so a household member's **Total soft credits** nets to what was kept. A negative credit next to a refund is normal.
- **Matching gifts**: refunding the company's gift gives the employee a negative **Matched Donor** credit for what went back. You do not unlink the pair first. Refunding the employee's own gift does not change the match.
- **Thank-yous** already sent stand. Refunds are never acknowledged.

Totals are recalculated by BarnCRM, sometimes a little later. **Rollups Last Calculated** on a record says when its numbers were worked out.

## Common Problems

- **Refund or Write Off** is missing. The gift is not `Received`. A `Pending` gift is cancelled instead; a `Refunded` or `Written off` gift has nothing left to reverse.
- "Only a received gift can be refunded or written off. This gift is ...: if it is Pending and will never be paid, set its Status to Cancelled." Same cause, on a page your organization built.
- "This refund is larger than the amount left on the gift. Check the gift's refunds: part of it may have gone back already." Look at **Refunds and Write-Offs** on the gift.
- "Say why the money is going back, so the next person reading this gift knows what happened." Fill in the reason.
- "This gift already records money going back, so it cannot itself be refunded or written off. Open the original gift instead." You opened the refund. Use **Original Gift** to go to the original.
- "This gift is already Refunded, so there is nothing left to refund or write off." Everything has already gone back.
- "Only a Pending gift can be cancelled. A gift that was received is refunded or written off instead." Use **Refund or Write Off**.
- "A Cancelled gift can only be set back to Pending. Set it to Pending first, then to Received when the money arrives."
- "A negative gift is a refund or a write-off, so it must name the original gift it reverses." You typed a negative amount by hand. Use **Refund or Write Off** on the original instead.
- "This gift has a refund or a write-off linked to it, so it cannot be deleted." Delete the refund first if it was recorded in error.
- The gift is receipted, posted to accounting, or in a closed period. That is fine: a refund is a new gift dated today, so it lands in an open period. Do not try to edit the original amount.

## Related

- [Entering gifts](gifts.md), [Pledges and recurring gifts](commitments.md), [Receipts and acknowledgments](receipts-and-acknowledgments.md)
- Admin Guide: [Refunds](../admin-guide/refunds.md), [Soft credits](../admin-guide/soft-credits.md), [Matching gifts](../admin-guide/matching-gifts.md), [Posting and closed periods](../admin-guide/posting-and-closed-periods.md)
