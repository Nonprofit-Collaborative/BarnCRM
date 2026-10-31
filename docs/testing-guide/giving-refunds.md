# Giving: Refunds and Write-Offs

Scripts for recording money that went back as a linked negative gift, and for what that does to totals. Setup detail: [Refunds and write-offs](../admin-guide/refunds.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, BarnCRM Rollup Builder and Giving deployed and sample data loaded unless a script says otherwise.

For every script on this page:

- Open gifts from the **BarnCRM Fundraising** app, so they open on the packaged **Gift Record Page**, which carries the **Refund or Write Off** action and the **Refunds and Write-Offs** list.
- In **BarnCRM Settings**, **Giving**, set **Default fund** to **General Fund** and save.
- "Enter a gift" means: in **Quick Gift Entry**, choose **Person**, pick the **Donor**, type the **Amount**, set **Payment Method** to **Check** and **Fund** to **General Fund**, then select **Save**.
- Totals are recalculated a few seconds after a save. Refresh the record page before reading a total.
- **Rosa Hall** has no gifts in the sample data, so her totals start empty. If an earlier page's scripts gave her gifts, note her totals first and read each expected total as a change from that.

## T-REF-01: Refund Part of a Gift, Then the Rest

**Purpose:** Confirm a partial and then a full refund create linked negative gifts and set the original's status only at the end.
**Prerequisites:** staff (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Enter a gift from **Rosa Hall** for 250. Open it. | **Status** Received, **Amount** 250.00. |
| 2 | Select **Refund or Write Off**. | The **Record Money Going Back** dialog. **Refund part or all of this gift** is chosen, **Left on this gift** reads 250.00, **How much is going back** starts at 250. |
| 3 | Change the amount to 100, type `Donor asked for part back` in **Why is it going back**, select **Record It**. | Toast "Recorded. The gift it reverses now shows what happened." The dialog closes. |
| 4 | Read the original gift. | **Amount** still 250.00, **Status** still Received. **Refunds and Write-Offs** lists one gift for -100.00 with the reason. |
| 5 | Open that refund gift. | **Amount** -100.00, **Original Gift** is the 250 gift, **Donor Contact** Rosa Hall, **Gift Date** today, **Status** Received, **Refund Reason** "Donor asked for part back". Its **Gift Allocations** show -100.00 to General Fund. |
| 6 | Back on the original, select **Refund or Write Off** again. | **Left on this gift** reads 150.00 and the amount starts at 150. |
| 7 | Type a reason and select **Record It**. | The original's **Status** changes to Refunded. The **Refund or Write Off** button is no longer on the page. The list shows two refunds. |

**Cleanup:** None. T-REF-04 reads these totals.

## T-REF-02: Write Off a Gift

**Purpose:** Confirm a write-off takes what is left, with no amount to type, and sets Written off.
**Prerequisites:** staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | Enter a gift from **Rosa Hall** for 500. Open it and select **Refund or Write Off**. | The dialog opens with **Left on this gift** 500.00. |
| 2 | Choose **Write off what is left of this gift**. | The **How much is going back** box disappears. |
| 3 | Type `Check returned unpaid by the bank` and select **Record It**. | The recorded toast. The original's **Status** is Written off and **Refunds and Write-Offs** lists one gift for -500.00. |

**Cleanup:** None.

## T-REF-03: Bad Refunds Are Refused

**Purpose:** Confirm a refund needs a reason and an amount within what is left, and negative gifts cannot be typed by hand.
**Prerequisites:** staff, then admin for step 7.

| Step | Action | Expected result |
|---|---|---|
| 1 | Enter a gift from **Rosa Hall** for 80. Open it and select **Refund or Write Off**. | The dialog opens. |
| 2 | Leave **Why is it going back** empty and select **Record It**. | Error toast: "Say why the money is going back, so the next person reading this gift knows what happened." No gift is created. |
| 3 | Type a reason, set the amount to 200, select **Record It**. | Error toast: "This refund is larger than the amount left on the gift. Check the gift's refunds: part of it may have gone back already." |
| 4 | Set the amount to 0, select **Record It**. | Error toast: "Enter how much is going back to the donor. A refund amount is always more than zero: BarnCRM records it as a negative gift for you." |
| 5 | Select **Cancel**. On the **Gifts** tab, select **New**, enter Rosa Hall as donor and **Amount** -50, select **Save**. | Refused: "A negative gift is a refund or a write-off, so it must name the original gift it reverses. Use the Refund or Write Off action on the original gift instead of entering this by hand." |
| 6 | Cancel. Open any sample gift with **Status** Pending (filter **All Gifts** by Status). | No **Refund or Write Off** button: only a received gift can go back. |
| 7 | As admin, open the original 250 gift from T-REF-01 and select **Delete**, then confirm. | Refused: "This gift has a refund or write-off linked to it, so it cannot be deleted. Delete the refund first if it was recorded in error." |

**Cleanup:** None.

## T-REF-04: Refunds Keep the Count and Leave the Total

**Purpose:** Confirm donor totals net refunds out, keep the gift count, and show zero rather than blank.
**Prerequisites:** admin. T-REF-01 and T-REF-02 done; T-REF-03 step 1 done.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Rosa Hall**. Read the Giving section. | **Total Giving** 80.00 (250 and 500 fully reversed, 80 kept). **Gift Count** 3. **Largest Gift** 500.00. **Last Gift Date** today. |
| 2 | Open Rosa Hall's household. | The same **Total Giving** and **Gift Count**. **Rollups Last Calculated** is a moment ago. |
| 3 | Open **Charlotte Williams** (sample data: one gift of 1,450, fully refunded). | **Total Giving** 0.00, not blank. **Gift Count** 1. |
| 4 | Open **General Fund**. Note **Total Raised**. Enter a gift from Rosa Hall for 40, then refund all 40 of it. Refresh the fund. | **Total Raised** is the same as before the 40 gift. **Gift Count** is one higher. |

**Cleanup:** None.

## T-REF-05: Who May Record a Refund

**Purpose:** Confirm read-only users cannot record a refund.
**Prerequisites:** read-only. A received gift with something left (the 80 gift from T-REF-03).

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, open **Rosa Hall**'s 80 gift. | The gift opens. **Refunds and Write-Offs** and the refund fields are readable. |
| 2 | Select **Refund or Write Off**. | The dialog says "You can see this gift but not record money going back. Ask your BarnCRM admin for the Fundraising Staff role, together with the Giving Staff permission set." It offers no reason box and no **Record It**, only **Cancel**. Select **Cancel**; no negative gift is added to **Refunds and Write-Offs**. |
| 3 | Open the **Refunds and Write-Offs** list view on the **Gifts** tab. | The refunds from T-REF-01 and T-REF-02 are listed. |

**Cleanup:** None.

## T-REF-06: Refund a Receipted Gift

**Purpose:** Confirm a refund is the way to correct a receipted gift and leaves the receipt untouched.
**Prerequisites:** staff. Receipt numbering set up ([Receipts and acknowledgments](giving-receipts-and-acknowledgments.md), T-RCPT-01).

| Step | Action | Expected result |
|---|---|---|
| 1 | Enter a gift from **Rosa Hall** for 60. Open it and select **Issue Receipt** on the **Receipts** panel. | A receipt row with **Status** Issued. |
| 2 | Select **Edit**, change **Amount** to 30, **Save**. | Refused with the receipt lock message, which ends "Void the receipt and reissue it, or record a refund." Cancel. |
| 3 | Select **Refund or Write Off**, refund 30 with reason `Half returned`. | The recorded toast. The receipt row is unchanged (**Status** Issued). |
| 4 | Read the original gift. | **Amount** 60.00, **Status** Received, one refund of -30.00 listed. |

**Cleanup:** None.

## T-REF-07: Cancel a Pending Gift Instead of Writing It Off

**Purpose:** Confirm a Pending gift is cancelled, not refunded, and only moves back to Pending.
**Prerequisites:** staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Gifts** tab, open a sample gift with **Status** Pending. Note its donor's **Total Giving**. | No **Refund or Write Off** button. |
| 2 | Select **Edit**, set **Status** to Cancelled, **Save**. | It saves. No negative gift appears in **Refunds and Write-Offs**. |
| 3 | Refresh the donor. | **Total Giving** is unchanged: a Pending gift was never in it. |
| 4 | Edit the gift, set **Status** to Received, **Save**. | Refused on **Status**: "A Cancelled gift can only be set back to Pending. Set it to Pending first, then to Received when the money arrives." |
| 5 | Set **Status** to Pending, **Save**. | It saves. |

**Cleanup:** Step 5 restores the gift.
