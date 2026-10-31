# Pledges and Recurring Gifts

A commitment is a promise to give. A **Pledge** is a fixed total paid over time; a **Recurring** gift is the same amount on a schedule with no end. BarnCRM lays out the expected payments (installments), so you can see what is due, what is overdue and what is left to pay.

Before you start: open the **Fundraising** app, **Commitments** tab. You need the **Fundraising Staff** role (the **Giving Staff** permission set).

## To Record a Pledge

1. Open **Commitments** and click **New**.
2. Set **Type** to **Pledge**.
3. Choose the donor: **Donor** for a person, or **Donor Account** for an organization or household. Fill in one, never both.
4. Type the **Amount** expected each time, not the total. A 1,200 pledge paid monthly has an **Amount** of 100.
5. Fill in **Expected Total** or **Installments Planned** (or both). A pledge needs at least one so the schedule can be worked out.
6. Choose the **Frequency**: **Weekly**, **Every two weeks**, **Monthly**, **Quarterly**, **Twice a year** or **Yearly**.
7. Set the **Start Date**. Leave **Day of Month** empty to use the day of the start date.
8. Choose a **Fund** and **Appeal** if they apply, and click **Save**.

You should see: the commitment page with a **Payment Schedule** card listing every payment (**Number**, **Due Date**, **Expected**, **Paid**, **Status**) and a **Total expected** line. **Balance** equals the total, because nothing is paid yet.

## To Record a Recurring Gift

1. Open **Commitments** and click **New**.
2. Set **Type** to **Recurring**.
3. Choose the donor, the **Amount**, the **Frequency** and the **Start Date**.
4. Leave **Expected Total** empty. A recurring gift has no total.
5. Click **Save**.

You should see: about a year of payments on the **Payment Schedule** card. More are added as time goes on.

If the card says "No payments have been generated for this commitment yet.", click **Generate now**.

## To See What Is Overdue or Coming Up

The payments are Installment records. They are not a tab in the Fundraising app.

1. Open the App Launcher, search for **Installments**, and open it.
2. Choose the list view **Overdue**, or **Upcoming 30 Days**.

You should see: each payment with its commitment and what was expected. A payment turns **Overdue** a few days after its due date, overnight.

To see whole commitments, open **Commitments** and choose **Active Pledges** or **Active Recurring Gifts**.

## To Pay an Installment

When a payment arrives, enter it as a gift and link it to the payment.

1. Open [Quick Gift Entry](gifts.md#to-pay-a-scheduled-payment) and choose the donor.
2. Type the **Amount** and **Gift Date**.
3. In **Pays a scheduled payment**, check the chosen payment, or pick the right one. Choose **None: a new gift on its own** if the gift is not for the pledge.
4. Click **Save**.

You should see: on the commitment, the payment's **Status** turns **Paid** (or **Partially paid** if less came in), **Paid To Date** goes up and **Balance** goes down. The gift appears in the commitment's **Gifts** list. For a stack of checks, use the **Pays** column in a [gift batch](gift-batches.md#to-mark-a-check-as-a-pledge-payment-pays).

On the **Gifts** tab's **New** form, set **Commitment** to the pledge and **Installment** to the payment instead. Leave **Installment** empty and BarnCRM links the gift to the oldest unpaid payment, if your admin left that setting on.

## To Pause or Resume a Recurring Gift

1. Open the commitment.
2. On the **Payment Schedule** card, click **Pause**.

You should see: "The commitment was updated." **Status** is **Paused**, no new payments are added, and the card now offers **Resume**. Click **Resume** when the donor starts again; the missing payments are filled back in.

## To End a Commitment

1. Open the commitment.
2. On the **Payment Schedule** card, click **Mark complete** for one that is finished, or **Cancel commitment** for one the donor has stopped.

You should see: **Status** is **Completed** or **Cancelled**. Cancelling marks the unpaid payments **Skipped** and deletes nothing. Gifts already received are not touched.

## To Change the Amount or Schedule

1. Open the commitment and click **Edit**.
2. Change **Amount**, **Frequency**, **Day of Month** or **End Date**, and click **Save**.

You should see: the unpaid payments rebuilt; paid and partly paid ones are left alone. Log an activity on the commitment saying why, so the next person knows why the numbers moved.

## Pledge Reminders

If your organization has turned on pledge reminders, donors with a payment coming due or overdue are emailed (or, if they opted out of email or the step is a letter, sent a letter) on the schedule your admin set up. You do not send them yourself unless you have the **Send Acknowledgments** permission.

- Open the **Pledge Reminders Log** tab, list view **All Pledge Reminders**, to see what was sent for a payment, to whom, on what date, and whether it failed. A reminder shows its step name, for example `Week late`.
- If a donor says they never got one, check the log row's **Recipient Email** and **Status** first. **Failed** rows say why.
- To stop reminders for one pledge, **Pause** it. Reminders only go to **Active** pledges, so a paused, completed or cancelled pledge is left alone.
- Once a donor pays, the payment is no longer open and nothing more is sent for it.
- With the **Send Acknowledgments** permission you can press **Send Reminders Now**, **Produce Letter File** and **Mark Letters Sent** on the **Pledge Reminders** page. Reminders are written and switched on by your admin ([Pledge reminders](../admin-guide/pledge-reminders.md)).

## Common Problems

- Twelve payments of 1,200 on a 1,200 pledge. The total was typed in **Amount**. Change **Amount** to what is expected each time and save.
- "Choose one donor for this commitment, either a person or an account, not both." Clear **Donor** or **Donor Account**.
- "Choose a donor for this commitment, either a person or an account." Fill in one of the two.
- "A pledge needs an expected total or a number of installments, so the schedule can be worked out." Fill in **Expected Total** or **Installments Planned**.
- "A recurring commitment has no expected total. Choose Pledge if the donor promised a fixed amount." Clear **Expected Total**, or change **Type** to **Pledge**.
- "Day of month is a day between 1 and 31, or empty to use the day of the start date." A 31 falls on the last day of a shorter month.
- "This commitment cannot be deleted because a gift has been received against one of its payments. Cancel it instead." Use **Cancel commitment**.
- "This record is the donor of an active or paused pledge or recurring gift, so it cannot be deleted." Cancel the commitment, or change its donor, first. Merging a duplicate still works.
- "That payment is no longer open, or is not this donor's. Nothing was saved." Choose again in **Pays a scheduled payment**, or None.
- "A gift of goods cannot pay a scheduled payment. Choose None." In-kind gifts never pay a pledge.
- The **Overdue** list is empty. Payments turn Overdue in a nightly job your admin switches on ([Commitments](../admin-guide/commitments.md)).
- You cannot find a pledge a colleague entered. Commitments are private, like gifts: you see your own and those your role or sharing gives you. Ask your admin ([Access](../admin-guide/access.md)).
- A suggested payment was wrong and the gift is saved. Open the gift, click **Edit**, and clear **Installment** and **Commitment**; the payment is owed again.

## Related

- [Entering gifts](gifts.md), [Gift batches](gift-batches.md), [Refunds and write-offs](refunds.md)
- Admin Guide: [Commitments](../admin-guide/commitments.md), [Pledge reminders](../admin-guide/pledge-reminders.md), [Quick Gift Entry](../admin-guide/quick-gift-entry.md)
