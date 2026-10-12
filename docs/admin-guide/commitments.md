# Commitments: pledges and recurring gifts

**Feature:** G-07 and G-11 | **Package:** Giving | **Iteration:** v0.3

## What it does

A commitment is a promise to give. It covers a pledge, where a donor promises a fixed
total paid over time, and a recurring gift, where a donor gives the same amount on a
schedule with no end in sight. Open Impact keeps both in one place, works out the
payments that are expected and when, and shows what has been paid and what is still
outstanding.

Because the expected payments are real records, David can see what is coming up in the
next thirty days and Jen can see what is overdue, without building a report or exporting
to a spreadsheet.

## How to turn it on

Commitments come with the Giving module. When Giving is on, the Commitments and
Installments tabs are in the app and no further step is required.

Three settings control how the schedules behave. Open **Open Impact Settings** and choose
**Giving**; they sit in that section alongside the default fund and appeal:

| Setting | What it does | Default |
|---|---|---|
| Installment generation horizon (months) | How far ahead payments are created for a recurring gift, so an open-ended schedule does not fill the org with rows | 12 |
| Overdue grace days | How many days an unpaid payment waits after its due date before it is marked Overdue | 5 |
| Auto-apply gifts to installments | When a gift names a commitment but not a particular payment, whether Open Impact links it to the oldest unpaid payment | On |

Change a value and choose **Save**. The new value applies to the next commitment you
create or change; existing schedules are left alone until you edit them.

## Switching the nightly jobs on

Commitments need three jobs to run overnight, and until you switch them on none of them
runs. This is the step that makes a payment turn Overdue on its own.

Open **Open Impact Settings**, choose **Giving**, and choose **Open** on **Nightly jobs**.
The page opens with a line for each job, then one button.

Choose **Schedule the nightly jobs**. Three jobs are scheduled at once:

| Job | Runs at | What it does |
|---|---|---|
| Installment top up | 01:15 | Extends every active recurring commitment up to the generation horizon, so an open ended schedule always has the next year of payments in front of it |
| Overdue pass | 01:45 | Marks every unpaid payment Overdue once it is further past its due date than the grace period |
| Donor levels | 03:00 | Places every donor on the rung their giving now reaches |

The times are fixed and are chosen to keep out of the way of the two other nightly jobs
Open Impact ships: the seasonal address swap at 00:30 and the rollups at 02:00. The top up
runs before the overdue pass so that the overdue pass sees every payment, and the donor
levels run an hour after the rollups start so that the totals the ladder reads have
settled.

Nothing else has to be done. If you have just switched the jobs on and do not want to wait
for tonight, choose **Run the jobs now**: the top up and the overdue pass start
immediately, and the page shows what they did once they finish. (Donor levels have their
own **Recalculate now** button on the Donor Levels page.)

### Checking they are running

The same page is where you check on them afterwards. Each job shows when it last finished
and what it did, for example "Marked 4 payments overdue." A job that ran and had nothing to
do says so ("No payments were overdue.") rather than staying blank, so a blank line means
the job has not run at all.

Three things the page can tell you:

- **Not scheduled.** Nobody has switched the jobs on in this org. Nothing is late, because
  nothing was ever going to run. The button under the line says **Schedule the nightly
  jobs**.
- **Scheduled, with a last run and a next run.** This is the normal state.
- **Scheduled but has not run in more than 36 hours.** Something stopped the job. Open the
  **Error Log** in Open Impact Settings: a job that fails writes there and carries on with
  the rest of its work rather than stopping, so the log tells you which commitment or which
  payment is the problem.

**Stop the nightly jobs** unschedules all three. Nothing already generated or already
marked Overdue is changed; the schedules simply stop being extended and payments stop
turning Overdue.

Scheduling and stopping need the **Manage Open Impact Settings** permission, which comes with
the Open Impact Admin permission set. Somebody who has the Giving Admin permission set without
it can open the page and see whether the jobs are running; the buttons are disabled.

The **payment schedule** card lives on a commitment's record page, and Open Impact ships a
page called **Commitment Record Page** with the card already on it. Assign it once, as your
org default for Commitment, and every commitment shows the schedule from then on. If your
organization has built a commitment record page of its own, add the **Commitment Payment
Schedule** component to that page instead.

## A five-minute walkthrough

Start from the sample data. The first part is David's work, the last step is Jen's.

### David records a pledge

1. Open the **Commitments** tab and choose **New**.
2. Set **Type** to Pledge.
3. In **Donor**, choose a person from a household in the sample data, for example Ana
   Nguyen. Leave the account donor field empty: a commitment has one donor, not two.
4. Set **Expected total** to 1,200 and **Amount** to 100. The amount is what is expected
   each time, not the total.
5. Set **Frequency** to Monthly and **Start date** to the first day of next month.
6. Leave **Day of month** empty. The day of the start date is used.
7. Set **Installments planned** to 12 and **End date** to the day before the first
   anniversary of the start date.
8. Choose **Save**. You will see twelve scheduled payments on the commitment, the first
   one due next month and the last one eleven months later, each for 100. The balance
   reads 1,200 because nothing has been paid yet.

### David enters the first payment

9. Open the first payment in the list and note its due date.
10. Open the **Gifts** tab, choose **New**, and enter a gift for Ana for 100 with the
    same date. In **Commitment** choose the pledge you just made, and in **Installment**
    choose the first payment.
11. Choose **Save**, then go back to the commitment. The first payment now reads **Paid**,
    paid to date reads 100, and the balance reads 1,100.

If David had left **Installment** empty, Open Impact would have linked the gift to the
oldest unpaid payment by itself, because the automatic setting is on.

### David pauses a recurring gift

12. Open the **Commitments** tab and open one of the sample recurring gifts, or create one:
    Type Recurring, Amount 25, Frequency Monthly, a start date, no expected total and no
    end date. A recurring gift has payments generated a year ahead, not forever.
13. On the payment schedule card, choose **Pause**. The status changes to Paused, no
    further payments are generated, and the payments already scheduled stay where they
    are. The card then offers **Resume** instead of Pause: choose it when the donor starts
    giving again and the missing payments are filled back in, keeping their original dates
    and their original numbering.

The same card offers **Mark complete** for a commitment that is finished and **Cancel
commitment** for one the donor has stopped. Cancelling marks the unpaid payments Skipped
and deletes nothing.

### Jen checks what is overdue

14. Open the **Installments** tab and choose the **Overdue** list view. Every payment
    already marked Overdue is here, with its commitment, its donor, and what was expected.
    A payment is marked Overdue by the overdue pass, so this list fills up the first night
    after you schedule the nightly jobs (see "Switching the nightly jobs on"). If the list
    is empty and you have just switched the jobs on, choose **Run the jobs now** on the
    Nightly jobs page rather than waiting.
15. Switch to **Upcoming 30 days** to see what should arrive next, which is the list Jen
    uses when she reconciles the bank statement.

## Common mistakes

**Entering the total in the amount field.** Amount is what is expected each time. A
1,200 pledge paid monthly has an amount of 100 and an expected total of 1,200. If the
schedule comes out with twelve payments of 1,200, this is what happened: correct the
amount and save, and the unpaid payments are rebuilt.

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

**Editing the amount partway through.** Changing the amount, the frequency, the day of
month, or the end date rebuilds the payments that are still unpaid and leaves every paid
or partly paid one alone. The balance changes as a result, which is what you want, but it
does mean the schedule after the change no longer matches the pledge letter the donor
signed. Log an activity on the commitment (the **Activity** panel on its record page) that
says why, so the next person to look at it knows why the numbers moved.

## Field reference for report builders

Everything above is on two objects: Commitment and Installment. The list views named here
are shipped and can be copied.

| What Maria calls it | Where it lives |
|---|---|
| Paid to date | Commitment, Paid To Date |
| Balance | Commitment, Balance |
| Expected payment | Installment, Expected Amount |
| Paid so far on this payment | Installment, Paid Amount |
| Pledge balance for a donor | Account or Contact, Pledge Balance |
