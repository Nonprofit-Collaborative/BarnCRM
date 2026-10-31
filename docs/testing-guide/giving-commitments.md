# Giving: Commitments

Scripts for pledges and recurring gifts: payment schedules, paying a payment with a gift, pausing, cancelling, refunds and the overdue pass. Setup detail: [Commitments: pledges and recurring gifts](../admin-guide/commitments.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Giving deployed and sample data loaded unless a script says otherwise. Work in the **Fundraising** app. A default fund must be set (script T-GIFT-01 in [Giving: gifts, funds and batches](giving-gifts-funds-batches.md)). The **Installments** tab is not in the app's navigation: open it from the app launcher. Leave the **Import** settings **Days either side of a payment's due date** (7) and **Amount difference allowed** (0) at their defaults.

## T-COM-01: Create a Pledge and See Its Schedule

**Purpose:** confirm a pledge saves with a generated payment schedule, paid to date and balance.
**Prerequisites:** staff (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Commitments** tab and click **New**. | The form shows **Type**, **Donor**, **Donor Account**, **Status**, **Fund**, **Appeal**, **Amount**, **Frequency**, **Day of Month**, **Start Date**, **End Date**, **Installments Planned** and **Expected Total**. |
| 2 | **Type** `Pledge`, **Donor** `Luis Garcia`, **Amount** `100`, **Frequency** `Monthly`, **Start Date** today, **Installments Planned** `12`. Leave **Expected Total** and **Day of Month** empty. Save. | The commitment opens on its record page. |
| 3 | Read the fields. | **Status** Active, **Expected Total** 1,200.00 (filled in as amount times installments), **Household** The Garcia Family. |
| 4 | Look at the **Payment Schedule** card. | 12 rows, **Number** 1 to 12, first **Due Date** today, monthly after that, each **Expected** 100.00 and **Status** Scheduled. The card shows **Pause**, **Mark complete** and **Cancel commitment**. |
| 5 | Read **Paid To Date** and **Balance** (refresh after a few seconds if empty). | **Paid To Date** 0.00 (or empty), **Balance** 1,200.00. |
| 6 | Open the **Commitments** tab, list view **Active Pledges**. | The new pledge is listed with the sample pledges. |

**Cleanup:** keep the pledge for T-COM-03 to T-COM-05.

## T-COM-02: Commitment Rules That Refuse a Save

**Purpose:** confirm the one-donor, recurring-total, pledge-size and day-of-month rules.
**Prerequisites:** staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | **New** commitment: **Type** `Pledge`, **Donor** `Harper Garcia`, **Donor Account** any organization, **Amount** `50`, **Frequency** `Monthly`, **Start Date** today, **Installments Planned** `4`. Save. | Refused: "Choose one donor for this commitment, either a person or an account, not both." |
| 2 | Clear both donor fields, save. | Refused: "Choose a donor for this commitment, either a person or an account." |
| 3 | Pick **Harper Garcia** again, clear **Installments Planned**, save. | Refused: "A pledge needs an expected total or a number of installments, so the schedule can be worked out." |
| 4 | Set **Type** `Recurring`, **Expected Total** `600`, save. | Refused: "A recurring commitment has no expected total. Choose Pledge if the donor promised a fixed amount." |
| 5 | Clear **Expected Total**, set **Day of Month** `40`, save. | Refused: "Day of month is a day between 1 and 31, or empty to use the day of the start date." |
| 6 | Clear **Day of Month**, save. | Saved: a monthly recurring gift with 12 or 13 months of payments ahead (the generation horizon), no **Expected Total**. |

**Cleanup:** keep the recurring gift for T-COM-06.

## T-COM-03: Pay a Payment From Quick Gift Entry

**Purpose:** confirm the form suggests the payment a gift pays, and saving links them and updates the balance.
**Prerequisites:** staff; the pledge from T-COM-01 (payment 1 due today, 100.00).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Quick Gift Entry**. Pick **Luis Garcia**, **Amount** `100`, leave **Gift Date** today. | **Pays a scheduled payment** appears under **Gift Date** with payment 1 chosen and marked "(suggested)". Under the list: "Chosen because it is due near the gift date and expects this amount. Choose None if the gift is not for it." |
| 2 | Change **Amount** to `90`. | The list refreshes; **None: a new gift on its own** is chosen (90 is outside the allowed difference). |
| 3 | Set **Amount** back to `100`. | Payment 1 is suggested and chosen again. |
| 4 | **Payment Method** `Check`, click **Save**. | "Gift G-... saved". |
| 5 | Open the pledge from T-COM-01. | **Payment Schedule**: payment 1 **Status** Paid, **Paid** 100.00. **Paid To Date** 100.00, **Balance** 1,100.00. The gift is first in the **Gifts** list. |
| 6 | Open Luis Garcia. | **Pledge Balance** in the **Giving** section is 1,100.00 (after a refresh). |
| 7 | Back on **Quick Gift Entry**, pick Luis Garcia again, **Amount** `100`. | Payment 1 is no longer in the list; payment 2 is listed but not suggested (not due within 7 days), so **None** stays chosen. |

**Cleanup:** none; T-COM-05 refunds the gift.

## T-COM-04: Pay a Payment From a Gift Batch

**Purpose:** confirm the batch **Pays** column links a line to a payment when posted.
**Prerequisites:** staff; any sample pledge or the T-COM-01 pledge. Open the pledge and note its donor and the due date and amount of its next Scheduled payment.

| Step | Action | Expected result |
|---|---|---|
| 1 | **Gift Batches**, **New**: **Description** `Pledge checks`, **Control Total** the payment's amount, **Default Gift Date** the payment's due date. Save. | The **Lines** card opens. |
| 2 | **Add line**, pick the pledge's donor, **Amount** the payment's amount. | The **Pays** cell chooses that payment, marked "(suggested)". |
| 3 | Set **Pays** to **None: a new gift on its own**, then choose the payment again. | Your choice stays as you set it. |
| 4 | Click **Save**, then **Post batch**. | "Batch posted: 1 gifts created." |
| 5 | Open the pledge. | That payment is Paid; **Paid To Date** rose and **Balance** fell by the amount. |
| 6 | Open the gift the batch made. | **Commitment** names the pledge and **Installment** the payment. |
| 7 | Note the pledge's next Scheduled payment. On the **Gifts** tab click **New**: the pledge's donor, **Amount** that payment's amount, **Payment Method** `Check`, **Commitment** the pledge, **Installment** that payment. Save, then open the pledge. | That payment is Paid and **Balance** fell by its amount. |

**Cleanup:** none.

## T-COM-05: Refund a Gift That Paid a Payment

**Purpose:** confirm a refund reopens the payment and restores the balance (the undo for a payment).
**Prerequisites:** staff; the gift from T-COM-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the T-COM-03 gift, click **Refund or Write Off**. Choose **Refund part or all of this gift**, **How much is going back** `40`, a reason, **Record it**. | "Recorded. The gift it reverses now shows what happened." |
| 2 | Open the pledge. | Payment 1 **Status** Partially paid, **Paid** 60.00. **Paid To Date** 60.00, **Balance** 1,140.00. |
| 3 | Refund the remaining `60` from the same gift. | Recorded. |
| 4 | Open the pledge again. | Payment 1 is no longer Paid or Partially paid (Scheduled, or Overdue once past its grace days). **Balance** 1,200.00. |

**Cleanup:** none.

## T-COM-06: Pause, Resume, Complete and Cancel

**Purpose:** confirm the status actions on the payment schedule card and that nothing received is changed.
**Prerequisites:** staff; the recurring gift from T-COM-02, and the pledge from T-COM-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the recurring gift. On **Payment Schedule** click **Pause**. | "The commitment was updated." **Status** Paused. Scheduled payments stay. **Resume** replaces **Pause**. |
| 2 | Click **Resume** (undo). | **Status** Active; the schedule keeps its dates and numbering. |
| 3 | Click **Cancel commitment**. | **Status** Cancelled. Every unpaid payment shows **Skipped**. No action buttons remain. |
| 4 | Open the **Commitments** tab, list view **Active Recurring Gifts**. | The cancelled gift is not listed. |
| 5 | Open the T-COM-01 pledge, click **Mark complete**. | **Status** Completed. The pledge leaves **Active Pledges**. |
| 6 | Open **Quick Gift Entry**, pick Luis Garcia, **Amount** `100`. | No **Pays a scheduled payment** list: a completed pledge has no open payments. |

**Cleanup:** none.

## T-COM-07: Nightly Jobs and Overdue Payments

**Purpose:** confirm the nightly jobs schedule, run on demand, and fill the Overdue list view.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Giving**, **Nightly Jobs**, **Open**. | Card **Nightly Jobs** with "The nightly jobs are not scheduled, so no schedule is being extended and no payment will turn Overdue on its own." and **Schedule Nightly Run**. |
| 2 | Click **Schedule Nightly Run**. | "The nightly jobs are scheduled." Each job shows a **Next Run**. **Stop Nightly Run** and **Run the jobs now** show. |
| 3 | Click **Run the jobs now**. | "The top up and the overdue pass have started. Refresh this page in a minute to see what they did." |
| 4 | Refresh after a minute. | **Last Run** for the top up and the overdue pass shows a time and a result line (for example a count of payments marked overdue, or that none were). |
| 5 | Open the **Installments** tab, list view **Overdue**. | Lists payments with **Status** Overdue, including the sample monthly donor's three overdue payments. Each is more than the grace days (5) past due. |
| 6 | Switch to **Upcoming 30 Days**. | Payments due in the next 30 days. |
| 7 | Back on **Nightly Jobs**, click **Stop Nightly Run** (undo). | The not-scheduled message returns. Payments already Overdue stay Overdue. |

**Cleanup:** schedule the jobs again if later scripts need them.

## T-COM-08: Delete Protection

**Purpose:** confirm a paid commitment, a paid payment and the donor of an open commitment cannot be deleted.
**Prerequisites:** admin; a sample Active pledge with at least one Paid payment (for example Carmen Torres's pledge on **Active Pledges**).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the pledge, choose **Delete**, confirm. | Refused: "This commitment cannot be deleted because a gift has been received against one of its payments. Cancel it instead." |
| 2 | Open one of its Paid payments from the **Installments** tab, choose **Delete**. | Refused: "This payment cannot be deleted because a gift has been received against it. Mark it Skipped instead." |
| 3 | Open the pledge's donor (Carmen Torres), choose **Delete**. | Refused: "This record is the donor of an active or paused pledge or recurring gift, so it cannot be deleted. Cancel the commitment, or change its donor, first. Merging a duplicate still works." |

**Cleanup:** none.

## T-COM-09: Commitment Access by Permission Set

**Purpose:** confirm staff cannot delete commitments, read-only users cannot create or change them, and Giving Admin gives no View All on commitments.
**Prerequisites:** staff, then read-only. For step 5, a user on the **Standard User** profile (not System Administrator) with **BarnCRM Admin** and **Giving Admin**, and no role above the sample data's owner.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open any sample pledge. | **Edit** shows; **Delete** does not. |
| 2 | As read-only, open the **Commitments** tab. | No **New** button. The list views **Active Pledges** and **Active Recurring Gifts** show. |
| 3 | As read-only, open an Active recurring gift. | No **Edit** or **Delete**. The **Payment Schedule** card lists the payments. |
| 4 | Look at the card's buttons. | No **Pause**, **Resume**, **Mark complete** or **Cancel commitment**. On a commitment with no payments yet, the card has no **Generate now**. |
| 5 | As the step 5 user, open **Commitments**, **All Commitments**, then **Gifts**, **All Gifts**. Create a pledge, then reopen **All Commitments**. | Neither list shows the sample commitments or gifts owned by someone else, the same for both. The new pledge shows, with its **Payment Schedule**. Sharing a sample pledge with this user (**Sharing** on the record) makes it show. |
**Cleanup:** none.

## T-COM-10: List Views for Commitments and Installments

**Purpose:** commitments and installments open with an All view, a My view and the status views.
**Prerequisites:** staff user, sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Commitments** tab and the list view menu. | **All Commitments**, **My Commitments**, **Active Pledges**, **Active Recurring Gifts** and **Paused Commitments** are listed. |
| 2 | Choose **All Commitments**. | Every commitment shows, with Type, Amount, Frequency and Status columns. |
| 3 | Pause a sample recurring gift (see T-COM-06) and choose **Paused Commitments**. | It shows there and has left **Active Recurring Gifts**. Resume it afterwards. |
| 4 | Open the **Installments** tab and the list view menu. | **All Installments**, **Overdue** and **Upcoming 30 Days** are listed. **All Installments** shows every payment. |

**Cleanup:** resume the paused commitment.

## T-COM-11: Pledge Reminders Stay Off Until Turned On, Then Remind Once

**Purpose:** confirm reminders send nothing while the setting is off, then email an overdue payment once, log it, and queue a letter for an opted-out donor.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)); a Pledge for a donor with an email address, **Start Date** seven days ago (so payment 1 is 7 days overdue); a second pledge for a donor with **Email Opt Out** ticked, **Start Date** seven days ago. Setup detail: [Pledge reminders](../admin-guide/pledge-reminders.md).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Giving**, **Commitments and Installments**. | **Send pledge reminders** is off, and **Pledge Reminders** is listed below it. |
| 2 | Open **Pledge Reminders**. | A notice says reminders are off. **Send Reminders Now** is disabled. No steps are listed. |
| 3 | Choose **New Step**. Name `Week late`, **Days From Due Date** `7`, **Channel** `Email`, choose **BarnCRM: pledge installment overdue**. Save. | The step is listed with timing `7 days after the due date` and its template name. |
| 4 | Choose **New Step** again. Name `Final letter`, **Days From Due Date** `30`, **Channel** `Letter`. Save. | Listed with timing `30 days after the due date`; the template column is empty. |
| 5 | Choose **New Step** a third time, **Channel** `Email`, and save without choosing a template. | The form asks for an email template and does not save. Cancel. |
| 6 | In **BarnCRM Settings**, turn on **Send pledge reminders**. Return to **Pledge Reminders**. | The off notice is gone. **Emails** reads 1 and **Letters** reads 1. |
| 7 | Press **Send Reminders Now**. Wait a minute, then refresh. | Under **Recent Reminders**: `Week late` by Email for the first donor, status **Sent**; `Week late` by Letter for the opted-out donor, status **Queued**. |
| 8 | Press **Send Reminders Now** again. | No new rows: the same step never reminds the same payment twice. |
| 9 | Press **Produce Letter File**. | A **Download letters** link appears. The CSV has one row with the opted-out donor, amount, 7 days overdue and the step name. The row is still **Queued**. |
| 10 | Press **Mark Letters Sent**. | The row's status is **Sent**. |
| 11 | Open the **Pledge Reminders Log** tab, list view **All Pledge Reminders**. | Both rows are listed with their pledge, payment, step, channel and status. |
| 12 | In **BarnCRM Settings**, turn **Send pledge reminders** off. Return to the page and press **Send Reminders Now**. | The button is disabled; if the page was open before the change, the error says reminders are turned off. |

**Cleanup:** turn **Send pledge reminders** off, and clear **Active** on both steps.
