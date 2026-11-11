# Pledges and Recurring Gifts

A commitment is a promise to give. A **Pledge** is a fixed total paid over time; a **Recurring** gift is the same amount on a schedule with no end. BarnCRM lays out the expected payments (scheduled payments), so you can see what is due, what is overdue and what is left to pay.

The words BarnCRM uses: **commitment** for the record, whichever kind it is; **pledge** and **recurring gift** for its two kinds; **scheduled payment** for each payment it expects.

Before you start: open the **BarnCRM Fundraising** app, **Commitments** tab. You need the **Fundraising Staff** role (the **Giving Staff** permission set).

## To Record a Pledge

1. Open **Commitments** and click **New** (or click **New** in the **Commitments** list on a person or organization, which fills in the donor).
2. Under **Donor**, choose **Person** or **Organization**, then pick the donor. Each name shows an email or city, so two people with one name can be told apart.
3. Under **Type**, choose **Pledge**.
4. Type the **Pledge Total**: the whole amount promised, for example 1,200.
5. Choose **How Often**: **Weekly**, **Every two weeks**, **Monthly**, **Quarterly**, **Twice a year** or **Yearly**.
6. Set the **First Payment Date**.
7. Fill in **Number of Payments**, or the **Last Payment Date** instead. Filling in one clears the other.
8. Choose a **Fund** and **Appeal** if they apply.
9. Check the **Payment Schedule** line, for example "12 payments of $100.00, the last one $100.00 on Dec 15, 2027.", and click **Save**.

You should see: the commitment page with a **Payment Schedule** card: a **Total Expected** tile and every payment (**Number**, **Due Date**, **Expected**, **Paid**, **Status**). **Balance** equals the total, because nothing is paid yet. The amount each time is the total divided evenly; the last payment takes up any cents left over. The Ask Pipeline's **Record a Pledge** makes the same pledge.

## To Record a Recurring Gift

1. Open **Commitments** and click **New**.
2. Choose the donor, then under **Type** choose **Recurring Gift**.
3. Type the **Amount Each Time**, choose **How Often** and set the **Start Date**.
4. Choose a **Fund** and **Appeal** if they apply, and click **Save**.

You should see: about a year of payments on the **Payment Schedule** card. More are added as time goes on. A recurring gift has no total.

If the card says **No Payments Yet**, click **Generate Now**.

## To See What Is Overdue or Coming Up

The payments are on the **Scheduled Payments** tab of the BarnCRM Fundraising app. The overdue
count is also on **Fundraising Home**; click it to open the **Overdue** list.

1. In **BarnCRM Fundraising**, open the **Scheduled Payments** tab.
2. Choose the list view **Overdue**, or **Upcoming 30 Days**. Salesforce opens the list you chose last time from then on.

You should see: each payment with its commitment and what was expected. A payment turns **Overdue** a few days after its due date, overnight.

To see whole commitments, open **Commitments** and choose **Active Pledges** or **Active Recurring Gifts**.

## To Pay an Installment

When a payment arrives, enter it as a gift and link it to the payment.

1. Open [Quick Gift Entry](gifts.md#to-pay-a-scheduled-payment) and choose the donor.
2. Type the **Amount** and **Gift Date**.
3. In **Pays a scheduled payment**, check the chosen payment, or pick the right one. Choose **None: a new gift on its own** if the gift is not for the pledge.
4. Click **Save**.

You should see: on the commitment, the payment's **Status** turns **Paid** (or **Partially paid** if less came in), **Paid To Date** goes up and **Balance** goes down. The gift appears in the commitment's **Gifts** list, on its **Related** tab. For a stack of checks, use the **Pays** column in a [gift batch](gift-batches.md#to-mark-a-check-as-a-scheduled-payment-pays).

On the **Gifts** tab's **New** form, set **Commitment** to the pledge and **Scheduled Payment** to the payment instead. Leave **Scheduled Payment** empty and BarnCRM links the gift to the oldest unpaid payment, if your admin left that setting on.

## To Pause or Resume a Recurring Gift

1. Open the commitment.
2. On the **Payment Schedule** card, click **Pause**.

You should see: "The commitment was updated." **Status** is **Paused**, no new payments are added, and the card now offers **Resume**. Click **Resume** when the donor starts again; the missing payments are filled back in.

## To End a Commitment

1. Open the commitment.
2. On the **Payment Schedule** card, click **Mark Complete** for one that is finished, or **Cancel Commitment** for one the donor has stopped.

**Cancel Commitment** asks first: "Cancel This Commitment?", with how many unpaid payments will be marked **Skipped**. Click **Cancel Commitment** to go ahead, or **Keep It** to leave the commitment as it is.

You should see: **Status** is **Completed** or **Cancelled**. Cancelling marks the unpaid payments **Skipped** and deletes nothing. Gifts already received are not touched.

## To Change the Amount or Schedule

1. Open the commitment and click **Edit**.
2. Change **Amount**, **Frequency**, **Day of Month** or **End Date**, and click **Save**.

You should see: the unpaid payments rebuilt; paid and partly paid ones are left alone. Log an activity on the commitment saying why, so the next person knows why the numbers moved.

## Pledge Reminders

If your organization has turned on pledge reminders, donors with a payment coming due or overdue are emailed (or, if they opted out of email, have no email address, their address bounced, or the step is a letter, sent a letter) on the schedule your admin set up. You do not send them yourself unless you have the **Send Acknowledgments** permission.

- Open the **Pledge Reminders Log** tab, list view **All Pledge Reminders**, to see what was sent for a payment, to whom, on what date, and whether it failed. A reminder shows its step name, for example `Week late`.
- If a donor says they never got one, check the log row's **Recipient Email** and **Status** first. **Failed** rows say why.
- To stop reminders for one pledge, **Pause** it. Reminders only go to **Active** pledges, so a paused, completed or cancelled pledge is left alone.
- Once a donor pays, the payment is no longer open and nothing more is sent for it.
- With the **Send Acknowledgments** permission you can press **Send Reminders Now**, **Produce Letter File** and **Mark Letters Sent** on the **Pledge Reminders** page. Reminders are written and switched on by your admin ([Pledge reminders](../admin-guide/pledge-reminders.md)).

## Common Problems

- Twelve payments of 1,200 on a 1,200 pledge. This came from a pledge entered on the old standard form, or edited later, with the total in **Amount**. Edit it: change **Amount** to what is expected each time and save. The New screen asks for the **Pledge Total** instead, so new pledges avoid this.
- "Choose the donor: a person or an organization." Pick the donor at the top of the New screen.
- "Enter the pledge total, above zero." or "Enter how often the donor pays, how many payments, and the date of the first one." Fill in **Pledge Total**, **How Often**, **First Payment Date**, and **Number of Payments** or **Last Payment Date**.
- "The last payment date is before the first payment date. Change one of them." Check both dates.
- "Choose one donor for this commitment, either a person or an account, not both." (when editing) Clear **Donor** or **Donor Account**.
- "A pledge needs an expected total or a number of installments, so the schedule can be worked out." (when editing) Fill in **Expected Total** or **Payments Planned**.
- "A recurring commitment has no expected total. Choose Pledge if the donor promised a fixed amount." (when editing) Clear **Expected Total**, or change **Type** to **Pledge**.
- "Day of month is a day between 1 and 31, or empty to use the day of the start date." A 31 falls on the last day of a shorter month.
- "This commitment cannot be deleted because a gift has been received against one of its payments. Cancel it instead." Use **Cancel Commitment**.
- "This record is the donor of an active or paused pledge or recurring gift, so it cannot be deleted." Cancel the commitment, or change its donor, first. Merging a duplicate still works.
- "That payment is no longer open, or is not this donor's. Nothing was saved." Choose again in **Pays a scheduled payment**, or None.
- "A gift of goods cannot pay a scheduled payment. Choose None." In-kind gifts never pay a pledge.
- The **Overdue** list is empty. Payments turn Overdue in a nightly job your admin switches on ([Commitments](../admin-guide/commitments.md)).
- You cannot find a pledge a colleague entered. Commitments are private, like gifts: you see your own and those your role or sharing gives you. Ask your admin ([Access](../admin-guide/access.md)).
- A suggested payment was wrong and the gift is saved. Open the gift, click **Edit**, and clear **Scheduled Payment** and **Commitment**; the payment is owed again.

## Related

- [Entering gifts](gifts.md), [Gift batches](gift-batches.md), [Refunds and write-offs](refunds.md)
- Admin Guide: [Commitments](../admin-guide/commitments.md), [Pledge reminders](../admin-guide/pledge-reminders.md), [Quick Gift Entry](../admin-guide/quick-gift-entry.md)
