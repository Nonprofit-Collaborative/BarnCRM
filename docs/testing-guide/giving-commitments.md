# Giving: commitments

Scripts for pledges and recurring gifts: payment schedules, paying a payment with a gift, pausing, cancelling, refunds and the overdue pass. Setup detail: [Commitments: pledges and recurring gifts](../admin-guide/commitments.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Giving deployed and sample data loaded unless a script says otherwise. Work in the **Fundraising** app. A default fund must be set (script T-GIFT-01 in [Giving: gifts, funds and batches](giving-gifts-funds-batches.md)). The **Installments** tab is not in the app's navigation: open it from the app launcher. Leave the **Import** settings **Days either side of a payment's due date** (7) and **Amount difference allowed** (0) at their defaults.

## T-COM-01: Create a pledge and see its schedule

**Purpose:** confirm a pledge saves with a generated payment schedule, paid to date and balance.
**Prerequisites:** staff (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Commitments** tab and click **New**. | The form shows **Type**, **Donor**, **Donor Account**, **Status**, **Fund**, **Appeal**, **Amount**, **Frequency**, **Day of Month**, **Start Date**, **End Date**, **Installments Planned** and **Expected Total**. |
| 2 | **Type** `Pledge`, **Donor** `Luis Garcia`, **Amount** `100`, **Frequency** `Monthly`, **Start Date** today, **Installments Planned** `12`. Leave **Expected Total** and **Day of Month** empty. Save. | The commitment opens on its record page. |
| 3 | Read the fields. | **Status** Active, **Expected Total** 1,200.00 (filled in as amount times installments), **Household** The Garcia Family. |
| 4 | Look at the **Payment schedule** card. | 12 rows, **Number** 1 to 12, first **Due date** today, monthly after that, each **Expected** 100.00 and **Status** Scheduled. The card shows **Pause**, **Mark complete** and **Cancel commitment**. |
| 5 | Read **Paid To Date** and **Balance** (refresh after a few seconds if empty). | **Paid To Date** 0.00 (or empty), **Balance** 1,200.00. |
| 6 | Open the **Commitments** tab, list view **Active Pledges**. | The new pledge is listed with the sample pledges. |

**Cleanup:** keep the pledge for T-COM-03 to T-COM-05.

## T-COM-02: Commitment rules that refuse a save

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

## T-COM-03: Pay a payment from Quick Gift Entry

**Purpose:** confirm the form suggests the payment a gift pays, and saving links them and updates the balance.
**Prerequisites:** staff; the pledge from T-COM-01 (payment 1 due today, 100.00).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Quick Gift Entry**. Pick **Luis Garcia**, **Amount** `100`, leave **Gift date** today. | **Pays a scheduled payment** appears under **Gift date** with payment 1 chosen and marked "(suggested)". Under the list: "Chosen because it is due near the gift date and expects this amount. Choose None if the gift is not for it." |
| 2 | Change **Amount** to `90`. | The list refreshes; **None: a new gift on its own** is chosen (90 is outside the allowed difference). |
| 3 | Set **Amount** back to `100`. | Payment 1 is suggested and chosen again. |
| 4 | **Payment method** `Check`, click **Save**. | "Gift G-... saved". |
| 5 | Open the pledge from T-COM-01. | **Payment schedule**: payment 1 **Status** Paid, **Paid** 100.00. **Paid To Date** 100.00, **Balance** 1,100.00. The gift is first in the **Gifts** list. |
| 6 | Open Luis Garcia. | **Pledge Balance** in the **Giving** section is 1,100.00 (after a refresh). |
| 7 | Back on **Quick Gift Entry**, pick Luis Garcia again, **Amount** `100`. | Payment 1 is no longer in the list; payment 2 is listed but not suggested (not due within 7 days), so **None** stays chosen. |

**Cleanup:** none; T-COM-05 refunds the gift.

## T-COM-04: Pay a payment from a gift batch

**Purpose:** confirm the batch **Pays** column links a line to a payment when posted.
**Prerequisites:** staff; any sample pledge or the T-COM-01 pledge. Open the pledge and note its donor and the due date and amount of its next Scheduled payment.

| Step | Action | Expected result |
|---|---|---|
| 1 | **Gift Batches**, **New**: **Description** `Pledge checks`, **Control Total** the payment's amount, **Default Gift Date** the payment's due date. Save. | The **Lines** card opens. |
| 2 | **Add line**, pick the pledge's donor, **Amount** the payment's amount. | The **Pays** cell chooses that payment, marked "(suggested)". |
| 3 | Set **Pays** to **None: a new gift on its own**, then choose the payment again. | Your choice stays as you set it. |
| 4 | Click **Save**, then **Post batch**. | "Batch posted: 1 gifts created." |
| 5 | Open the pledge. | That payment is Paid; **Paid To Date** rose and **Balance** fell by the amount. |

**Cleanup:** none.

## T-COM-05: Refund a gift that paid a payment

**Purpose:** confirm a refund reopens the payment and restores the balance (the undo for a payment).
**Prerequisites:** staff; the gift from T-COM-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the T-COM-03 gift, click **Refund or Write Off**. Choose **Refund part or all of this gift**, **How much is going back** `40`, a reason, **Record it**. | "Recorded. The gift it reverses now shows what happened." |
| 2 | Open the pledge. | Payment 1 **Status** Partially paid, **Paid** 60.00. **Paid To Date** 60.00, **Balance** 1,140.00. |
| 3 | Refund the remaining `60` from the same gift. | Recorded. |
| 4 | Open the pledge again. | Payment 1 is no longer Paid or Partially paid (Scheduled, or Overdue once past its grace days). **Balance** 1,200.00. |

**Cleanup:** none.

## T-COM-06: Pause, resume, complete and cancel

**Purpose:** confirm the status actions on the payment schedule card and that nothing received is changed.
**Prerequisites:** staff; the recurring gift from T-COM-02, and the pledge from T-COM-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the recurring gift. On **Payment schedule** click **Pause**. | "The commitment was updated." **Status** Paused. Scheduled payments stay. **Resume** replaces **Pause**. |
| 2 | Click **Resume** (undo). | **Status** Active; the schedule keeps its dates and numbering. |
| 3 | Click **Cancel commitment**. | **Status** Cancelled. Every unpaid payment shows **Skipped**. No action buttons remain. |
| 4 | Open the **Commitments** tab, list view **Active Recurring Gifts**. | The cancelled gift is not listed. |
| 5 | Open the T-COM-01 pledge, click **Mark complete**. | **Status** Completed. The pledge leaves **Active Pledges**. |
| 6 | Open **Quick Gift Entry**, pick Luis Garcia, **Amount** `100`. | No **Pays a scheduled payment** list: a completed pledge has no open payments. |

**Cleanup:** none.

## T-COM-07: Nightly jobs and overdue payments

**Purpose:** confirm the nightly jobs schedule, run on demand, and fill the Overdue list view.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Giving**, **Nightly jobs**, **Open**. | Card **Nightly jobs** with "The nightly jobs are not scheduled, so no schedule is being extended and no payment will turn Overdue on its own." and **Schedule nightly run**. |
| 2 | Click **Schedule nightly run**. | "The nightly jobs are scheduled." Each job shows a **Next run**. **Stop nightly run** and **Run the jobs now** show. |
| 3 | Click **Run the jobs now**. | "The top up and the overdue pass have started. Refresh this page in a minute to see what they did." |
| 4 | Refresh after a minute. | **Last run** for the top up and the overdue pass shows a time and a result line (for example a count of payments marked overdue, or that none were). |
| 5 | Open the **Installments** tab, list view **Overdue**. | Lists payments with **Status** Overdue, including the sample monthly donor's three overdue payments. Each is more than the grace days (5) past due. |
| 6 | Switch to **Upcoming 30 Days**. | Payments due in the next 30 days. |
| 7 | Back on **Nightly jobs**, click **Stop nightly run** (undo). | The not-scheduled message returns. Payments already Overdue stay Overdue. |

**Cleanup:** schedule the jobs again if later scripts need them.

## T-COM-08: Delete protection

**Purpose:** confirm a paid commitment, a paid payment and the donor of an open commitment cannot be deleted.
**Prerequisites:** admin; a sample Active pledge with at least one Paid payment (for example Carmen Torres's pledge on **Active Pledges**).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the pledge, choose **Delete**, confirm. | Refused: "This commitment cannot be deleted because a gift has been received against one of its payments. Cancel it instead." |
| 2 | Open one of its Paid payments from the **Installments** tab, choose **Delete**. | Refused: "This payment cannot be deleted because a gift has been received against it. Mark it Skipped instead." |
| 3 | Open the pledge's donor (Carmen Torres), choose **Delete**. | Refused: "This record is the donor of an active or paused pledge or recurring gift, so it cannot be deleted. Cancel the commitment, or change its donor, first. Merging a duplicate still works." |

**Cleanup:** none.

## T-COM-09: Commitment access by permission set

**Purpose:** confirm staff cannot delete commitments and read-only users cannot create or change them.
**Prerequisites:** staff, then read-only.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open any sample pledge. | **Edit** shows; **Delete** does not. |
| 2 | As read-only, open the **Commitments** tab. | No **New** button. The list views **Active Pledges** and **Active Recurring Gifts** show. |
| 3 | As read-only, open an Active recurring gift. | No **Edit** or **Delete**. The **Payment schedule** card lists the payments. |
| 4 | Click **Pause** on the card. | Refused with a message ("That change is not allowed from the commitment's current status..."); **Status** stays Active. Refresh to confirm. |

**Cleanup:** none.
