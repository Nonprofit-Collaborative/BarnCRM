# Entering gifts

A gift is one thing that arrived: money, stock or goods, from one donor, on one date. This page covers entering a gift, reading the gift page, and recording who else deserves credit for it. To change a gift after it is entered, see [Refunds and write-offs](refunds.md); a gift is never edited away.

Before you start: open the **Fundraising** app. You need the **Fundraising Staff** role (it carries the **Giving Staff** permission set). If the **Quick Gift Entry** tab is missing, ask your admin ([Access](../admin-guide/access.md)).

## To enter a gift with Quick Gift Entry

Quick Gift Entry is the first tab of the Fundraising app. On a computer it is also in the utility bar at the bottom of the screen, so you can open it over whatever page you are on.

1. Open the **Quick Gift Entry** tab, or click **Quick Gift Entry** in the utility bar.
2. Under **Who gave this gift**, choose **Person** or **Organization**.
3. Search for the donor in **Donor** (or **Organization**). If the person is not there, click **Not in the list? Add a new person**, create them, then come back and search again.
4. Type the **Amount**.
5. Check the **Gift date**. It starts at today.
6. Choose the **Payment method** (for example **Check**, **Card** or **Cash**).
7. Type the **Check or reference number** if there is one.
8. Check **Appeal** and **Fund**. They start at your organization's defaults; change them if the donor said otherwise.
9. Click **Save**, or **Save and new** to start the next gift straight away.

You should see: a green box saying "Gift G-000123 saved" with an **Open this gift** link. **Save and new** keeps the date, the appeal and the fund, and clears the rest.

If the donor still owes a pledge or recurring payment, a **Pays a scheduled payment** list appears. See [To pay a scheduled payment](#to-pay-a-scheduled-payment) below.

## To pay a scheduled payment

When you choose a donor who has an active or paused pledge or recurring gift, Quick Gift Entry shows **Pays a scheduled payment**.

1. Enter the donor, **Amount** and **Gift date** as usual.
2. Read the note under **Pays a scheduled payment**:
   - "Chosen because it is due near the gift date and expects this amount" means one payment matched and is already picked.
   - "2 payments could be this gift, so none was chosen" means you pick.
3. Choose the right payment, or **None: a new gift on its own** if this gift is not for a pledge.
4. Click **Save**.

You should see: the payment on the commitment turn **Paid** (or **Partially paid**), and the commitment's **Paid To Date** go up. More in [Pledges and recurring gifts](commitments.md).

## To enter a gift of goods (in-kind)

1. In Quick Gift Entry, choose the donor and the **Gift date**.
2. Set **Payment method** to **In-kind**. The **Amount** box goes away: a gift of goods has no amount.
3. In **What was given**, describe the goods so a stranger would recognize them a year from now. This text is printed on the donor's receipt word for word.
4. Type a **Fair market value** if you have one. It is for your reporting only, never printed on the receipt and never added to giving totals. Leave it empty if you do not know.
5. Click **Save**.

You should see: the gift page shows an **In-kind Gift** section with **In-kind Description** and **Fair Market Value**. A gift that was part money and part goods is two gifts. Use Quick Gift Entry for goods, not the New Gift action, which has no description box.

## To add a gift from a person's or organization's page

1. Open the person, household or organization in the Fundraising app.
2. Click **New Gift** in the action bar. The donor is already filled in.
3. Fill in **Amount**, **Payment Method**, **Status** and **Acknowledgment Status**, and choose an **Appeal** if there is one. **Gift Date** defaults to today; change it if the gift arrived on another day.
4. Click **Save**.

You should see: the gift in the record's **Gifts** list. The gift goes to your default fund. Use **Status** `Pending` for money that is promised but has not arrived.

## To read a gift page

A gift opens on the gift record page. From top to bottom:

- The action bar: **Edit**, **Refund or Write Off** (only while **Status** is `Received`) and **Delete**.
- **Gift**: donor, **Household** (filled in from the donor, so you never set it), **Appeal**, **Commitment** and **Installment** (the pledge payment the gift pays, if any), **Amount**, **Gift Date**, **Payment Method**, **Status**, **Payment Reference**.
- **Acknowledgment, Receipt and Recognition**: **Acknowledgment Status**, **Acknowledgment Date**, **Receipt Number**, **Matched Gift**, **Tribute**, and on a refund, **Original Gift** and **Refund Reason**.
- **In-kind Gift**, only on an in-kind gift.
- Side panels: **Posting**, **Receipts**, **Soft credits**, **Tribute**, and **Activity**.
- Lists: **Gift Allocations** (which funds the gift went to), **Refunds and Write-offs**, **Tributes** and **Acknowledgments** (each thank-you sent for the gift).

Gift statuses:

- **Received**: the money arrived. It counts in giving totals.
- **Pending**: expected, not yet arrived. It counts in no total, export, receipt or thank-you.
- **Refunded** and **Written off**: set for you when the whole gift has gone back. See [Refunds and write-offs](refunds.md).
- **Cancelled**: a Pending gift that will never be paid. See [Refunds and write-offs](refunds.md#to-cancel-a-pending-gift).

A gift without a fund goes in full to your organization's default fund, as one line in **Gift Allocations**. Allocations always add up to the gift. Quick Gift Entry designates one fund; to split a gift across several funds, ask your admin, because changing one allocation row at a time is refused.

## To add a soft credit

A soft credit recognizes someone who influenced a gift but did not give it, such as the board member who asked. It never changes the money.

1. Open the gift.
2. In the **Soft credits** panel, click **Add credit**.
3. Choose the **Person to recognize**.
4. Choose **Why they are recognized**: **Solicitor**, **Honoree**, **Influencer**, **Household Member**, **Matched Donor** or **Other**. With **Other**, type **Your own wording**.
5. Check the **Amount** and click **Save**.

You should see: the person in the panel with no badge. To take it off, click **Remove** beside it.

Credits marked **Automatic** are made by BarnCRM. When a household member gives, every other current member of that household is credited for the full amount. They follow the gift and the household, so they have no **Remove** button. To change one, fix the gift or the household, or add a credit of your own.

## To record a tribute (in honor or in memory)

The **Tribute** panel on the gift shows the tribute and whether the family has been told. The tribute itself is a separate record.

1. Open the gift. In its **Tributes** list, click **New**. The gift is filled in for you.
2. Choose the **Type**: **In honor of** or **In memory of**.
3. Type the **Honoree Name**, or choose **Honoree Contact** if the person is already in BarnCRM.
4. Fill in who should be told: **Notification Recipient Contact**, or type **Notification Recipient Name** if they are not in BarnCRM.
5. Type any **Message** from the donor and click **Save**.
6. When the letter has gone out, open the gift and click **Mark notification sent** in the **Tribute** panel.

You should see: the panel reads "In memory of ..., Notify ..." and then **Notification sent** with the date. BarnCRM does not send the letter; the button records that you did. The **Notifications to Send** list view on Tributes shows the ones still waiting.

## To link a matching gift

When an employer matches an employee's gift, the employer is the donor of its own gift, and the employee gets a soft credit for causing it.

1. Open the employee's person page and check that **Employer** names the company. If it is blank, click **Edit**, fill it in and click **Save**.
2. Enter the employee's gift, and then the employer's gift (donor: the organization), as usual.
3. Open the employer's gift and click **Edit**.
4. In **Matched Gift**, choose the employee's gift. Click **Save**.

You should see: on the employer's gift, the employee in **Soft credits** as **Matched Donor**, marked **Automatic**. The employee's gift shows the link in its own **Matched Gift**. You enter the link once, from the employer's side. To undo it, clear **Matched Gift**.

## Common problems

- "This gift has a receipt number, so its amount, date, donor and in-kind description cannot change. Void the receipt and reissue it, or record a refund." The donor holds a receipt for this gift. Use **Void and reissue** ([Receipts and acknowledgments](receipts-and-acknowledgments.md)) or record a refund.
- "This gift has been posted to accounting, so its date, amount, donor, payment method, reference and funds cannot change and it cannot be deleted." The bookkeeper has exported it. Record a refund, or ask whoever posts gifts to unpost it.
- "This gift is dated in a closed accounting period (the books are closed through ...)" The books for that month are closed. Record a refund instead: it is dated today.
- "The books are closed through ..., so a gift dated on or before that day cannot be added to them." Date the gift after the close date, or ask your admin.
- "Enter a donor contact or a donor account, not both. A gift has exactly one donor." Clear one of the two donor fields.
- "A gift amount cannot be zero." Enter the amount received. For goods, set **Payment Method** to **In-kind**.
- "The gift was saved, but it is already split across more than one fund, so the fund you chose was not applied." Open the gift to check its **Gift Allocations**.
- "The donor's scheduled payments could not be loaded." You can still save the gift on its own and link it to the payment later.
- "The matching gift must come from an organization. Open the company's gift and link the employee's gift to it." You opened the employee's gift. Link from the company's gift.
- "That gift is from someone whose employer is a different organization." Check **Employer** on the person, or clear it if you are not sure.
- "A gift that has been refunded or written off cannot be part of a matching gift pair." Link the replacement gift instead.
- "This gift is in memory of the person you have chosen to notify." Choose a family member or friend as the notification recipient.
- "This gift already has a tribute." One tribute per gift: put a second name in the **Message**.
- "The gift could not be saved. Your administrator can find the details in the Error Log." Try again; if it repeats, tell your admin.

## Related

- [Gift batches](gift-batches.md), [Pledges and recurring gifts](commitments.md), [Refunds and write-offs](refunds.md), [Receipts and acknowledgments](receipts-and-acknowledgments.md)
- [People and households](people-and-households.md)
- Admin Guide: [Gifts](../admin-guide/gifts.md), [Quick Gift Entry](../admin-guide/quick-gift-entry.md), [Soft credits](../admin-guide/soft-credits.md), [Tributes](../admin-guide/tributes.md), [In-kind gifts](../admin-guide/in-kind-gifts.md), [Matching gifts](../admin-guide/matching-gifts.md), [Funds](../admin-guide/funds.md), [Posting and closed periods](../admin-guide/posting-and-closed-periods.md)
