# Receipts and Acknowledgments

A receipt is the numbered tax document for a gift; an acknowledgment is the thank-you. They are separate on purpose: the thank-you is yours to word, the receipt is not. This page also covers year-end statements, stewardship plans and the gift's **Posting** panel.

Before you start: you need the **Fundraising Staff** role. Its **Giving Staff** permission set carries the **Issue Receipts** and **Send Acknowledgments** permissions. With **Giving Read Only** you can read receipts and open their PDFs, but not issue or send. The letters, the thank-you rules and receipt numbering are set up by your admin ([Receipts](../admin-guide/receipts.md), [Acknowledgments](../admin-guide/acknowledgments.md)).

## To Issue a Receipt for a Gift

1. Open a received gift.
2. In the **Receipts** panel, click **Issue Receipt**.

You should see: "Receipt ... has been issued. Click View PDF beside it to open the file." The panel lists the receipt with its **Number**, **Status**, **Amount** and **Issued** date, and the gift's **Receipt Number** is filled in. Click **View PDF** to open the document.

From then on the gift's amount, date, donor and in-kind description are locked, because the donor holds a document that states them.

## To Void and Reissue a Receipt

Use this when the receipt is wrong, for example the amount was entered wrongly.

1. Open the gift.
2. In the **Receipts** panel, type **Why is this receipt being voided?**
3. Click **Void and Reissue**.

You should see: "Receipt ... has been voided and reissued as .... The original file is unchanged." The old receipt shows status Void with your reason, and a new receipt with the next number sits beside it. Nobody can delete a receipt or its file.

To change the gift's amount itself, void and reissue is not enough: record a refund ([Refunds and write-offs](refunds.md)).

## To Find a Donor's Receipts

Receipt PDFs are attached to the **Receipt** record and, for a single gift receipt, to the gift. They are not in the donor's or household's Files list.

1. Open the donor and use their **Receipts** list, or open the gift and use its **Receipts** panel, or
2. Open the **Receipts** tab and use the list views **All Receipts**, **Year End Statements** or **Voided Receipts**.

## To Run Year-End Statements

A year-end statement lists a donor's gifts for the year in one document. With the **Issue Receipts** permission you can start a run.

1. Open the **Receipt Letters** tab.
2. Click the **Year End Statements** tab.
3. Check the **Statement year**.
4. Click **Generate**.
5. Click **Refresh** to follow the run.

You should see: "Year end statements are being generated." A row for the run with **Year**, **Status**, **Donors**, **Issued** and **Errors**. Each statement is filed as a receipt on the donor.

Enter all the year's gifts first. A donor who already has a statement for the year is skipped on a second run; to correct one, void that donor's statement and run again. Editing the letter wording on the other tab needs your admin.

## To Send Thank-Yous

The thank-you page shows what is waiting, sorted into queues by your organization's rules.

1. Open the **Acknowledgment Queue** tab.
2. Read **Waiting to Go**: **Emails ready to send**, **Letters ready to merge**, **Waiting, matched by no rule** and **Could not be sent, nobody to email**.
3. Click **Send emails now** to send the email queue.
4. Click **Download letters to merge** to get the letter queue as a spreadsheet. Under **Recent Runs**, click **Download the file**, merge it with your letter, and print.
5. When the letters are posted, click **Mark as sent** on that run.

You should see: each run under **Recent Runs** with **Status**, **Sent** and **Errors**. A thanked gift's **Acknowledgment Status** is **Acknowledged**, with an **Acknowledgment Date**. Letters stay in the queue until you click **Mark as sent**.

Only your admin can add or change rules, or turn on **Send emails nightly**. The **Gifts to Acknowledge** list view on **Gifts** shows every gift still waiting.

## To Thank a Donor Again, or Not at All

1. Open the gift and click **Edit**.
2. Set **Acknowledgment Status** to **To acknowledge** to queue it again, or **Do not acknowledge** to leave it out.
3. Click **Save**.

You should see: the gift back in the queue, or out of it. BarnCRM never re-queues an acknowledged gift on its own.

## To Work a Stewardship Plan

A stewardship plan lays out follow-up tasks (a thank-you call, a welcome packet, a check-in) when a gift or pledge arrives. Your admin writes the plans and switches them on; the tasks land in your ordinary task list.

1. Open the **Stewardship Plans** tab and choose **Running Plans**, or open the donor and use their **Stewardship Plans** list.
2. Open a plan to see its **Plan Template**, the person (**Contact**) or organization (**Account**), and the **Gift** or **Commitment** that started it.
3. Work the tasks in your task list as usual.
4. When the work is done, click **Edit**, set **Status** to **Complete** (or **Cancelled**), and click **Save**. **Completed Date** fills in as today; type another date first if the work finished earlier.

You should see: the plan leave **Running Plans**. BarnCRM does not close a plan when its last task closes, and cancelling a plan leaves its tasks alone.

## To Start a Stewardship Plan by Hand

Use this for a donor who should get a plan that no gift started, for example after a meeting. Any plan your admin has turned on can be started by hand ([Stewardship plans](../admin-guide/stewardship-plans.md)).

1. In the Fundraising app, open the person, household or organization.
2. Click **Start Stewardship Plan** and choose the plan in **Plan**. Its description shows under the list.
3. Click **Start Plan**.

You should see: the plan in the donor's **Stewardship Plans** list with **Status** Running, and its tasks in the task lists of the people they are assigned to. The same plan does not start twice on a donor while it is running.

## To Read the Posting Panel

The **Posting** panel on a gift says whether the bookkeeper has exported it:

- "Not posted to accounting." The gift is in the books but not yet exported.
- "Posted to accounting by ..." with a date. Its date, amount, donor, payment method, reference and funds are locked.
- "Not in the books: Pending and in-kind gifts are in no accounting export, so this gift stays editable."
- "Dated in a closed period ..." The books for that month are closed.

Marking gifts posted, and unposting, need the **Post Gifts** permission, which only **Giving Admin** carries. See [Posting and closed periods](../admin-guide/posting-and-closed-periods.md).

## Common Problems

- **Issue Receipt** is missing. The gift already has a receipt (use **Void and Reissue**), or you lack **Issue Receipts**.
- "You do not have permission to issue receipts. Ask your administrator for the Fundraising Staff role."
- "This gift has already been receipted. To correct the receipt, void it and reissue it."
- "A pending or cancelled gift cannot be receipted, because no money has arrived. Mark the gift Received first."
- "Say why this receipt is being voided. A void needs a reason and a date." Fill in the reason first.
- "This receipt has already been voided. Look for the receipt that replaced it."
- "A year end statement is reissued by voiding it and running statements again for that donor, not from this button."
- "This gift has a receipt number, so its amount, date, donor and in-kind description cannot change." Void and reissue, or record a refund.
- "Sending thank yous needs the Send Acknowledgments permission." Ask your admin for the Fundraising Staff role.
- **Send emails now** is greyed out. The email queue is empty, or you lack **Send Acknowledgments**.
- "Acknowledging gifts is switched off, so nothing is joining the queue." Your admin turns it on.
- Gifts sit under **Waiting, matched by no rule**. No rule covers them; tell your admin.
- **Template not found** beside a rule. Its email template is gone; your admin picks another. The **Failed Acknowledgments** list view on Acknowledgments shows what did not send.
- "You need the Post Gifts permission to mark gifts posted to accounting or to unpost them."

## Related

- [Entering gifts](gifts.md), [Refunds and write-offs](refunds.md), [Reports and dashboards](reports-and-dashboards.md)
- Admin Guide: [Receipts](../admin-guide/receipts.md), [Acknowledgments](../admin-guide/acknowledgments.md), [Stewardship plans](../admin-guide/stewardship-plans.md), [Posting and closed periods](../admin-guide/posting-and-closed-periods.md), [Access](../admin-guide/access.md)
