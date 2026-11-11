# Commitments: Pledges and Recurring Gifts

**Feature:** G-07 and G-11 | **Package:** Giving | **Iteration:** v0.3

## What It Does

A commitment is a promise to give. It covers a pledge, where a donor promises a fixed
total paid over time, and a recurring gift, where a donor gives the same amount on a
schedule with no end in sight. BarnCRM keeps both in one place, works out the
payments that are expected and when, and shows what has been paid and what is still
outstanding.

Because the expected payments are real records, David can see what is coming up in the
next thirty days and Jen can see what is overdue, without building a report or exporting
to a spreadsheet.

## How to Turn It On

Commitments come with the Giving module. When Giving is on, the Commitments and
Scheduled Payments tabs are in the app and no further step is required. Scheduled Payments
is the tab for the payment (Installment) records; only its label changed, and its API name
is still `Installment__c`.

**One set of words (G-36).** Staff see **Commitment** for the record of either kind,
**Pledge** and **Recurring Gift** for its two kinds, and **Scheduled Payment** for each
payment it expects (the Gift, Gift Batch Line and Pledge Reminder lookups to it carry that
label too). The pledge reminders keep their name although they also remind recurring
donors. Every one of these is a label, so an org that prefers other words renames the
object or field in Setup (**Rename Tabs and Labels** or **Object Manager**); nothing in
BarnCRM reads a label.

**New** on Commitment opens the **New Commitment** screen, not the standard form. A pledge
is entered as its **Pledge Total**, **How Often**, **First Payment Date** and **Number of
Payments** (or **Last Payment Date**); a recurring gift as its **Amount Each Time**, **How
Often** and **Start Date**. A one-line preview of the payments shows before anything is
saved. The screen saves through the same code as the Ask Pipeline's **Record a Pledge**,
so a pledge from either place is the same record: the total, the number of payments, and
an amount each time that is the total divided evenly, rounded down, with the last payment
taking up the cents (rule R-CM5). The override is set on the Commitment object for desktop
and phone, through a small Aura wrapper (`commitmentNewOverride`), because Salesforce
overrides a standard button only with an Aura component. **Edit** still opens the standard
form, which is where **Day of Month** is set. To put the standard New form back, open
**Setup**, **Object Manager**, **Commitment**, **Buttons, Links, and Actions**, edit **New**
and choose **No override**.

Three settings control how the schedules behave. Open **BarnCRM Settings** and choose
**Giving**; they sit in that section alongside the default fund and appeal:

| Setting | What it does | Default |
|---|---|---|
| Installment generation horizon (months) | How far ahead payments are created for a recurring gift, so an open-ended schedule does not fill the org with rows | 12 |
| Overdue grace days | How many days an unpaid payment waits after its due date before it is marked Overdue | 5 |
| Auto-apply gifts to installments | When a gift names a commitment but not a particular payment, whether BarnCRM links it to the oldest unpaid payment | On |

Change a value and choose **Save**. The new value applies to the next commitment you
create or change; existing schedules are left alone until you edit them.

## Switching the Nightly Jobs On

Commitments need jobs to run overnight, and until you switch them on none of them
runs. This is the step that makes a payment turn Overdue on its own.

Open **BarnCRM Settings**, choose **Giving**, and choose **Open** on **Nightly Jobs**.
The page opens with a line for each job, then one button.

Choose **Schedule Nightly Run**. Five jobs are switched on at once, as steps of
[BarnCRM Nightly Jobs](nightly-jobs.md), the one nightly run (the button also schedules that
run when it is not scheduled yet):

| Job | Runs at | What it does |
|---|---|---|
| Payment schedule top up | 01:15 | Extends every active recurring commitment up to the generation horizon, so an open ended schedule always has the next year of payments in front of it |
| Overdue pass | 01:45 | Marks every unpaid payment Overdue once it is further past its due date than the grace period |
| Donor levels | 03:00 | Places every donor on the rung their giving now reaches |
| Pledge reminders | 03:15 | Sends the [pledge reminder](pledge-reminders.md) steps that are due. Sends nothing while **Send Pledge Reminders** is off, which is how it ships (D-162) |
| Ask reminders | 03:30 | Creates a task when a donor's Next Ask Date arrives ([Ask Cadence](ask-cadence.md)); nothing while Ask Reminders is off |

The pledge reminders line is on this page since 1.5 (G-37), with its last run, what it
sent and a warning when a scheduled run recorded nothing. The Pledge Reminders page keeps
its own **Run every night** switch for that one step; stopping it there leaves the other
four running, and this page still reads as scheduled.

The times are fixed and are chosen to keep out of the way of the two other nightly jobs
BarnCRM ships: the seasonal address swap at 00:30 and the rollups at 02:00. The top up
runs before the overdue pass so that the overdue pass sees every payment, and the donor
levels run an hour after the rollups start so that the totals the ladder reads have
settled.

Nothing else has to be done. If you have just switched the jobs on and do not want to wait
for tonight, choose **Run the Jobs Now**: the top up, the overdue pass and both reminder
passes (each only while its setting is on) start immediately, and the page shows what they did once they finish. (Donor levels have their
own **Recalculate Now** button on the Donor Levels page.)

### Checking They Are Running

The same page is where you check on them afterwards. Each job shows when it last finished
and what it did, for example "Marked 4 payments overdue." A job that ran and had nothing to
do says so ("No payments were overdue.") rather than staying blank. A job that has not run
at all reads **Never run**.

Three things the page can tell you:

- **Not scheduled.** Nobody has switched the jobs on in this org. Nothing is late, because
  nothing was ever going to run. The button under the line says **Schedule Nightly Run**.
- **Scheduled, with a last run and a next run.** This is the normal state.
- **Scheduled but has not run in more than 36 hours.** A yellow warning sits under the job.
  Something stopped the job. Open the
  **Error Log** in BarnCRM Settings: a job that fails writes there and carries on with
  the rest of its work rather than stopping, so the log tells you which commitment or which
  payment is the problem.

**Stop Nightly Run** unschedules all three. Nothing already generated or already
marked Overdue is changed; the schedules simply stop being extended and payments stop
turning Overdue.

Scheduling and stopping need the **Manage BarnCRM Settings** permission, which comes with
the BarnCRM Admin permission set. The jobs run as the person who scheduled them and reach
only the commitments that person can see and edit, so schedule them as a system
administrator. Commitments are private, like gifts, and Giving Admin does not give View All
on them (see [Access](access.md)). Somebody who has the Giving Admin permission set without
it can open the page and see whether the jobs are running; the buttons are disabled.

The **payment schedule** card lives on a commitment's record page, and BarnCRM ships a
page called **Commitment Record Page** with the card already on it. The BarnCRM Fundraising app
opens every commitment on it, with nothing to assign. The same page lists the **Gifts**
received against the commitment, newest first, and its action bar carries **Edit**,
**Change Owner**, **Sharing** and **Delete**. If your organization has built a commitment record page of
its own, add the **Commitment Payment Schedule** component to that page, and a **Dynamic
Related List - Single** for Gifts.

## A Five-Minute Walkthrough

Start from the sample data. The first part is David's work, the last step is Jen's.

### David Records a Pledge

1. Open the **Commitments** tab and choose **New**. The **New Commitment** screen opens.
2. Under **Donor**, keep **Person** and choose a person from a household in the sample
   data, for example Ana Nguyen.
3. Under **Type**, keep **Pledge**.
4. Set **Pledge Total** to 1,200 and **How Often** to Monthly.
5. Set **First Payment Date** to the first day of next month.
6. Set **Number of Payments** to 12 (or set **Last Payment Date** eleven months after the
   first; the screen counts the payments).
7. Read the **Payment Schedule** line: "12 payments of $100.00, the last one $100.00 on"
   the date eleven months on.
8. Choose **Save**. You will see the commitment with twelve scheduled payments, the first
   one due next month and the last one eleven months later, each for 100. The balance
   reads 1,200 because nothing has been paid yet.

### David Enters the First Payment

9. Open the first payment in the list and note its due date.
10. Open the **Gifts** tab, choose **New**, and enter a gift for Ana for 100 with the
    same date. In **Commitment** choose the pledge you just made, and in **Scheduled Payment**
    choose the first payment.
11. Choose **Save**, then go back to the commitment. The first payment now reads **Paid**,
    paid to date reads 100, and the balance reads 1,100. The gift is at the top of the
    commitment's **Gifts** list on the **Related** tab.

If David had left **Scheduled Payment** empty, BarnCRM would have linked the gift to the
oldest unpaid payment by itself, because the automatic setting is on.

If a pledge is later edited on the standard form with **Expected Total** cleared, BarnCRM
fills it in on save as the amount times the installments planned, so the balance stays
right. A total you type is always kept.

If Ana later asks for that payment back, David records it with **Refund or Write Off** on
the gift (see [Refunds and write-offs](refunds.md)). The negative gift names the same pledge
and payment, so paid to date drops by what went back and the balance, Ana's pledge balance
and her household's all rise by the same amount. A part refund leaves the payment
**Partially paid**; a full one leaves it unpaid. A pledge the payment had completed is
Active again.

### David Pauses a Recurring Gift

12. Open the **Commitments** tab and open one of the sample recurring gifts, or create one:
    **New**, **Type** Recurring Gift, **Amount Each Time** 25, **How Often** Monthly and a
    **Start Date**. A recurring gift has payments generated a year ahead, not forever.
13. On the payment schedule card, choose **Pause**. The status changes to Paused, no
    further payments are generated, and the payments already scheduled stay where they
    are. The card then offers **Resume** instead of Pause: choose it when the donor starts
    giving again and the missing payments are filled back in, keeping their original dates
    and their original numbering.

The same card offers **Mark Complete** for a commitment that is finished and **Cancel
Commitment** for one the donor has stopped. Cancel Commitment is a red-text button, last
in the row, and asks first ("Cancel This Commitment?", with the number of unpaid payments
that will be marked Skipped; **Keep It** backs out). Cancelling marks the unpaid payments
Skipped and deletes nothing.

### Jen Checks What Is Overdue

14. Open the **Scheduled Payments** tab and choose the **Overdue** list view. Every payment
    already marked Overdue is here, with its commitment, its donor, and what was expected.
    A payment is marked Overdue by the overdue pass, so this list fills up the first night
    after you schedule the nightly jobs (see "Switching the nightly jobs on"). If the list
    is empty and you have just switched the jobs on, choose **Run the Jobs Now** on the
    Nightly jobs page rather than waiting.
15. Switch to **Upcoming 30 Days** to see what should arrive next, which is the list Jen
    uses when she reconciles the bank statement.

## List Views

**Commitments** has **All Commitments**, **My Commitments**, **Active Pledges**, **Active
Recurring Gifts** and **Paused Commitments**. **Scheduled Payments** has **All Scheduled Payments**,
**Overdue** and **Upcoming 30 Days**. Salesforce opens a tab on the list view each person
used last (the first visit shows Recently Viewed); there is no setting that makes
**Overdue** every person's default, so the User Guide tells staff to choose it once.

## Common Mistakes

**Entering the total in the amount field.** On the standard Edit form, Amount is what is
expected each time. A 1,200 pledge paid monthly has an amount of 100 and an expected total
of 1,200. If the schedule comes out with twelve payments of 1,200, this is what happened:
correct the amount and save, and the unpaid payments are rebuilt. The New Commitment
screen asks for the total instead, so a new pledge cannot be entered this way.

**Naming two donors.** A commitment is from one donor: a person or an account, never
both. Saving with both filled in stops with "Choose one donor for this commitment, either
a person or an account, not both."

**Giving a recurring gift an expected total.** A recurring gift is open ended, so it has
no total and no fixed number of payments. If the donor has promised a fixed total, it is
a pledge. Saving a recurring commitment with a total stops with "A recurring commitment
has no expected total. Choose Pledge if the donor promised a fixed amount."

**Deleting a commitment that has been paid.** Once a gift has been received against a
payment, the commitment and that payment are part of the giving history and cannot be
deleted. Cancel the commitment instead: the unpaid future payments are marked Skipped and
nothing already received is touched.

**Deleting the donor of an open commitment.** A person or organization who is the donor of
an Active or Paused pledge or recurring gift cannot be deleted, and neither can the
household of a person who is, because the commitment would be left with no donor and could
not be saved again. The delete stops with "This record is the donor of an active or paused
pledge or recurring gift, so it cannot be deleted. Cancel the commitment, or change its
donor, first." Merging duplicates still works: the commitment moves to the record you keep.
Erasing a person is not a delete either, so it works with an open pledge: the pledge stays,
credited to the anonymized record.

**A commitment somebody cannot find.** Commitments are private: a person sees the ones they
own and the ones your role hierarchy or sharing settings give them, and Giving Admin adds
nothing to that, exactly as for gifts. If a fundraiser cannot find a pledge a colleague
entered, give them a role above the owner, add a sharing rule, or use **Sharing** on the
commitment.

**Editing the amount partway through.** Changing the amount, the frequency, the day of
month, or the end date rebuilds the payments that are still unpaid and leaves every paid
or partly paid one alone. The balance changes as a result, which is what you want, but it
does mean the schedule after the change no longer matches the pledge letter the donor
signed. Log an activity on the commitment (the **Activity** panel on its record page) that
says why, so the next person to look at it knows why the numbers moved.

## Field Reference for Report Builders

Everything above is on two objects: Commitment and Installment. The list views named here
are shipped and can be copied.

| What Maria calls it | Where it lives |
|---|---|
| Paid to date | Commitment, Paid To Date |
| Balance | Commitment, Balance |
| Expected payment | Installment, Expected Amount |
| Paid so far on this payment | Installment, Paid Amount |
| Pledge balance for a donor | Account or Contact, Pledge Balance |
