# Refunds and write-offs

## What it does

Sometimes money goes back: a card is charged twice, a donor asks for a gift to be returned,
or a check recorded as received bounces and finance writes it off. BarnCRM never
edits or deletes the original gift, because it really happened and Jen reconciles against
it. Instead it records a second gift for a negative amount, linked to the original, with
the reason on it.

That keeps three things true at once: the bank reconciles, fund and donor totals correct
themselves automatically, and anyone looking at the original gift can see what became of it.

Refunds and write-offs are for money you received. A **Pending** gift that will never be paid,
such as a pledge payment that never came, is not written off: you set its **Status** to
**Cancelled** (see [Cancelling a Pending gift](#cancelling-a-pending-gift) below).

## What a refund does to the donor's totals

The negative gift and the gift it reverses cancel each other, so nothing has to be adjusted
by hand. Ana gave 250 and asked for 100 back:

| After | Total giving | Gift count |
|---|---|---|
| The 250 gift | 250 | 1 |
| 100 refunded | 150 | 1 |
| The other 150 refunded as well | 0 | 1 |

**A fully refunded gift leaves the donor's total at zero and still counts as one gift.**
That is deliberate. Ana did give, once, and it is part of her history with you; the
organization is simply holding none of it. A write-off behaves the same way. The same
arithmetic runs on the fund's and the appeal's total raised, on a pledge's paid to date,
and on Ana's giving for the fiscal year the gifts fall in.

Two things follow from it that surprise people. Total giving divided by gift count is not a
useful average gift for a donor with refunds, because the two numbers deliberately answer
different questions. And Ana's **Last gift date** stays on the day of the original gift
rather than moving to the day of the refund, because the date totals ignore negative gifts.

Recognition follows the same arithmetic. If Ana's household member Luis was soft credited
for her gift, the refund gives him a negative soft credit of the same size and leaves the
original credit where it is, so his **Total soft credits** ends at nothing. Both rows stay
on the record, which is why a negative soft credit is a normal thing to see next to a
refund.

The same is true of a matching gift. Refunding a company's match gives the employee who
earned it a negative soft credit for the amount that went back, so a match of 500 with 200
returned leaves them recognized for 300, and the link between the two gifts stays as it was.
You do not have to unlink the pair first. Refunding the employee's own gift does not change
the match, because the company's money is still money you are holding.

## How to turn it on

Refunds and write-offs arrive with the Giving module. There is nothing to configure.

The **Refund or Write Off** action appears on the gift page for anyone with the **Giving
Staff** or **Giving Admin** permission set. It asks which of the two you are recording, so
there is one button rather than two that look unrelated. **Giving Read Only** users can see
the result but cannot record one.

## A five-minute walkthrough

You are David. The 250 check from the Gifts page walkthrough was partly a mistake: 100 of it
was meant for another organization, and the donor has asked for it back.

1. Open the gift `G-000001`. Its **Status** is `Received` and its **Amount** is 250.
2. Click **Refund or Write Off**.
3. Leave the choice at the top on **Refund part or all of this gift**. The amount starts at
   what is left of the gift, which is 250. Change it to 100, type "Donor asked for the
   misdirected portion back" as the reason, and click **Record it**.
4. BarnCRM creates a second gift for minus 100. Open it. Its **Original Gift** points at
   `G-000001`, its **Donor** and **Appeal** are the same as the original, its **Gift Date**
   is today, its **Status** is `Received` (because the refund itself is a transaction that
   happened), and its **Refund Reason** carries what you typed.
5. Look at that refund gift's allocations: one allocation for minus 100 against `General`,
   mirroring the original's designation, so the fund's total corrects itself.
6. Go back to `G-000001`. It still shows 250 and its **Status** is still `Received`, because
   only part of it came back. The refund is visible in its **Refunds** related list.
7. Now refund the rest: click **Refund or Write Off** on `G-000001` again. The amount starts
   at 150, which is what is left. Give a reason and click **Record it**. This time the
   original's **Status** changes to `Refunded`, because the whole gift has now gone back.
8. To see a write-off instead, enter a new gift for 500, open it, click **Refund or Write
   Off**, and choose **Write off what is left of this gift** with the reason "Check returned
   unpaid by the bank". There is no amount to type: a write-off is always what is left. BarnCRM creates a linked gift for minus 500 and sets the original's **Status** to
   `Written off`.
9. To see a cancellation, enter a gift for 75 with **Status** `Pending`, dated last month, then
   edit it and set **Status** to `Cancelled`. It saves, and no negative gift is created. Your
   donor's totals and the accounting export never counted it, and still do not.

## Cancelling a Pending gift

A Pending gift is money you expect. If it will never arrive, edit the gift and set **Status**
to **Cancelled**. Nothing else changes: no negative gift is created, and a Cancelled gift is in
no total, no export, no receipt and no acknowledgment, exactly as it was while Pending. It works
even when the gift is dated in a month whose books are closed, because a Pending gift was never
in the books. If the gift was expected to pay a pledge installment, cancelling it frees the
installment for the next gift. If the money turns up after all, set the gift back to
**Pending**, then to **Received** when it arrives. Only Pending moves to Cancelled, and a
Cancelled gift moves only back to Pending. Each change is written to the Error Log, with who
made it.

## Common mistakes

- **Editing the gift amount instead of refunding.** If a receipt has been issued the save is
  refused outright, and if it has not, you have quietly restated a period Tom already
  reported to the board. Record a refund: it is one click and it leaves a trail. The refusal
  on a receipted gift is not something you can switch off: the receipt lock is one of the
  automations that always run, and pausing automation does not suspend it. In the rare case
  where a receipted gift really has to change, an administrator grants the Override Receipt
  Lock permission in Setup for the length of the correction, and every change made that way
  is written to the Error Log. The procedure is on the [Gifts page](gifts.md), under
  "Lifting the receipt lock".
- **Refunding a gift that is posted to accounting or in a closed period.** That works: the
  refund is a new gift dated today, so it lands in an open period and in Jen's next export.
  See [Posting and Closed Periods](posting-and-closed-periods.md).
- **Writing off or refunding a Pending gift.** The action is refused with "Only a received gift
  can be refunded or written off": nothing was received. Set its **Status** to **Cancelled**
  instead.
- **Refunding more than is left.** The action is refused with "This refund is larger than
  the amount left on the gift." Check the gift's **Refunds** related list: part of it may
  have gone back already.
- **Typing a negative gift by hand instead of using the action.** You cannot: **Original
  Gift** and **Refund Reason** are filled in by the action and are read only on the page. The
  action is what mirrors the original's designation and updates its status, and a hand-typed
  negative gift would do neither.
- **Deleting the original to make a refund go away.** BarnCRM refuses, with "This gift has
  a refund or a write-off linked to it, so it cannot be deleted". If the refund itself was
  recorded in error, delete the refund first.
- **Expecting totals to move immediately.** Donor, fund and appeal totals are calculated by
  the rollup engine. Each record's **Rollups Last Calculated** tells you when its numbers
  were worked out.
