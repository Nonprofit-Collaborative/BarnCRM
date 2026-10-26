# Giving: gifts, funds and batches

Scripts for entering gifts (Gifts tab, Quick Gift Entry, gift batches, import), funds, appeals, in-kind gifts and closed accounting periods. Setup detail: [Gifts](../admin-guide/gifts.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Giving deployed and sample data loaded unless a script says otherwise. Work in the **Fundraising** app (app launcher). Sample data makes no fund the default, so run T-GIFT-01 first. Related admin-guide pages: [Quick Gift Entry](../admin-guide/quick-gift-entry.md), [Funds](../admin-guide/funds.md), [Appeals](../admin-guide/appeals.md), [Gift batches](../admin-guide/gift-batches.md), [In-kind gifts](../admin-guide/in-kind-gifts.md), [Posting and closed periods](../admin-guide/posting-and-closed-periods.md), [Importing gifts](../admin-guide/gift-import.md), [A donor's giving on their record](../admin-guide/donor-records.md). Refunds, receipts and the receipt lock have their own pages.

## T-GIFT-01: Funds and the default fund

**Purpose:** confirm one fund is the default, the flag moves when a second fund takes it, and a fund with gifts cannot be deleted.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Funds** tab, list view **All Funds**. | The 8 sample funds show, from **General Fund** to **Memorial Fund**. |
| 2 | Open **General Fund**, click **Edit**, tick **Is Default**, and save. | Saved. **Total Raised**, **Gift Count**, **Last Gift Date** and **Rollups Last Calculated** are read only. |
| 3 | Open **BarnCRM Settings**, **Giving**. | **Default fund** shows General Fund. |
| 4 | On the **Funds** tab click **New**. Name `Test Fund`, tick **Active** and **Is Default**, and save. | Saved. |
| 5 | Reopen **General Fund**. | **Is Default** is now unticked: only one default exists. |
| 6 | Edit **General Fund**, tick **Is Default** again, and save. Reopen `Test Fund`. | `Test Fund` is no longer the default. |
| 7 | On **General Fund**, choose **Delete** and confirm. | Refused: "Gifts have been designated to this fund, so it cannot be deleted: deleting it would leave those gifts pointing at nothing. Untick Active instead..." |
| 8 | Delete `Test Fund` (it has no gifts). | Deleted. |

**Cleanup:** keep **General Fund** as the default; every later script needs it.

## T-GIFT-02: Enter a gift on the Gifts tab

**Purpose:** confirm a gift gets its household and a default allocation, and allocations must total the gift.
**Prerequisites:** staff; General Fund is the default (T-GIFT-01).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Gifts** tab and click **New**. | The new gift form shows **Donor Contact**, **Donor Account**, **Amount**, **Gift Date**, **Payment Method**, **Status** (Received) and **Appeal**. |
| 2 | Choose **Harper Garcia** in **Donor Contact**, **Amount** `250`, **Gift Date** today, **Payment Method** `Check`, **Appeal** `Spring Appeal`. Save. | The gift opens on the gift page, named `G-` and a number. |
| 3 | Read the **Household** field. | It names Harper's household (The Garcia Family), filled in by BarnCRM. |
| 4 | Look at the **Gift Allocations** list. | One allocation: **General Fund**, 250.00. |
| 5 | Open the allocation, click **Edit**, set **Amount** to `100`, save. | Refused: "The allocations of this gift total 100.00, but the gift is 250.00. The difference is 150.00." |
| 6 | Cancel the edit. | The allocation stays 250.00. |
| 7 | Check the gift's action bar. | **Edit** and **Refund or Write Off** show. **Delete** does not (Giving Staff cannot delete). |
| 8 | Open Harper Garcia from the **Donor Contact** link and refresh after a few seconds. | The **Giving** section shows **Total Giving** including the 250 and **Rollups Last Calculated** close to now. The **Gifts** list shows the new gift first. |

**Cleanup:** none; T-GIFT-03 and other pages reuse the gift.

## T-GIFT-03: Gift rules that refuse a save, and cancelling a Pending gift

**Purpose:** confirm the donor, amount and status rules, and that a cancel can be reversed only back to Pending.
**Prerequisites:** admin; the gift from T-GIFT-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **New** on the **Gifts** tab. Fill both **Donor Contact** (Harper Garcia) and **Donor Account** (any organization), **Amount** `10`, today, `Cash`. Save. | Refused: "Enter a donor contact or a donor account, not both. A gift has exactly one donor." |
| 2 | Clear **Donor Account**, set **Amount** `0`, save. | Refused: "A gift amount cannot be zero. Enter what was received, or enter a negative amount to record a refund..." |
| 3 | Set **Amount** `-10`, save. | Refused: "A negative gift is a refund or a write-off, so it must name the original gift it reverses. Use the Refund or Write Off action on the original gift..." Cancel the form. |
| 4 | On the **All Gifts** list view, filter **Status** equals Pending, and open one sample gift (for example from Charlotte Osei, 450). | **Status** is Pending. |
| 5 | Edit it, set **Status** to `Cancelled`, save. | Saved. |
| 6 | Edit it again, set **Status** to `Received`, save. | Refused: "A Cancelled gift can only be set back to Pending. Set it to Pending first, then to Received when the money arrives." |
| 7 | Set **Status** to `Pending` and save (undo). | Saved; the gift is Pending again. |
| 8 | Open the T-GIFT-02 gift and edit **Status** to `Cancelled`. | Refused: "Only a Pending gift can be cancelled. A gift that was received is refunded or written off instead." |

**Cleanup:** none.

## T-GIFT-04: Quick Gift Entry

**Purpose:** confirm the one-screen form saves gifts with defaults, Save and new keeps the shared values, and a double save is blocked.
**Prerequisites:** staff; General Fund is the default. In **BarnCRM Settings**, **Giving**, set **Default appeal** to `Annual Fund` (as admin).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Quick Gift Entry** tab. | Card **Quick gift entry**. **Who gave this gift** is on **Person**; **Gift date** is today; **Appeal** shows Annual Fund; **Fund** shows General Fund. |
| 2 | In **Donor** type `Garc` and pick **Luis Garcia**. Enter **Amount** `50`, **Payment method** `Check`, **Check or reference number** `1042`. | Values stay as typed. No **Pays a scheduled payment** list appears (Luis owes no pledge payment). |
| 3 | Click **Save and new**. | "Gift G-... saved" with an **Open this gift** link. The donor, amount, payment method and check number clear; the date, appeal and fund stay. |
| 4 | Switch to **Organization**, pick **Founders Consulting Group**, **Amount** `25`, **Payment method** `Cash`. Click **Save**. | Saved message with link. **Save** and **Save and new** are now greyed out. |
| 5 | Change the amount to `30`. | **Save** and **Save and new** are enabled again. Do not save. |
| 6 | Click **Open this gift**. | The gift shows **Donor Account** Founders Consulting Group, 25.00, Cash, appeal Annual Fund, one allocation to General Fund. |
| 7 | Open the utility bar at the bottom of any Fundraising page. | **Quick Gift Entry** opens there over the page. |

**Cleanup:** set **Default appeal** back to empty if later scripts expect none.

## T-GIFT-05: Quick Gift Entry refusals and in-kind fields

**Purpose:** confirm messages sit on the field they concern, and In-kind swaps the amount for description and value.
**Prerequisites:** staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Quick Gift Entry**, leave **Donor** empty, click **Save**. | Under **Donor**: "Choose the person or organization who gave this gift." Nothing is saved. |
| 2 | Pick **Harper Garcia**, enter **Amount** `-20`, **Payment method** `Cash`, click **Save**. | Under **Amount**: "Enter an amount greater than zero. A refund is entered from the original gift, not here." |
| 3 | Clear **Payment method** (choose **Choose one**) and amount `20`, click **Save**. | Under **Payment method**: "Choose a payment method." |
| 4 | Choose **Payment method** `In-kind`. | **Amount** and **Pays a scheduled payment** disappear. **What was given** and **Fair market value** appear, with "For your reporting only. It is never printed on the receipt..." under the value. |
| 5 | Leave **What was given** empty, click **Save**. | Under **What was given**: "Describe what was given. This text is the donor's receipt, so a gift of goods cannot be saved without it." |
| 6 | Type `Sixteen folding tables, used`, **Fair market value** `-5`, click **Save**. | "Fair market value cannot be negative. Leave it empty if you do not have a figure yet." |
| 7 | Set **Fair market value** `800`, click **Save**, then **Open this gift**. | **Amount** 0.00, **In-kind Description** and **Fair Market Value** 800.00 show in the in-kind section. |

**Cleanup:** none; T-GIFT-06 uses the in-kind gift.

## T-GIFT-06: In-kind rules on the gift record

**Purpose:** confirm the in-kind validation rules and that in-kind value stays out of total giving.
**Prerequisites:** admin; the in-kind gift from T-GIFT-05.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the in-kind gift, click **Edit**, set **Amount** `800`, save. | Refused: "An in-kind gift has no amount, because goods are not money the organization holds. Leave Amount at zero..." Cancel. |
| 2 | Edit, clear **In-kind Description**, save. | Refused: "Describe what was given. This text is printed on the donor's receipt..." Cancel. |
| 3 | Open the T-GIFT-02 gift (Check, 250), edit, type `Chairs` in **In-kind Description**, save. | Refused: "In-kind Description and Fair Market Value belong to a gift of goods or services. Either set Type to In-kind, or clear both fields." Cancel. |
| 4 | Open Harper Garcia, wait a few seconds and refresh. | **Total Giving** did not rise by 800. If your page shows **In-kind Value** (it is not placed by default; add it or use a report), it includes 800. |

**Cleanup:** none.

## T-GIFT-07: Appeals

**Purpose:** confirm calculated appeal totals and the parent appeal rule.
**Prerequisites:** staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Appeals** tab, click **New**. **Appeal Name** `Test Appeal`, **Start Date** today, **Goal** `25000`, **Cost** `1200`. Save. | Saved. **Net Raised** shows -1,200.00 and **Percent To Goal** 0%. |
| 2 | Enter a gift of `500` on Quick Gift Entry with **Appeal** `Test Appeal`. | Saved. |
| 3 | Reopen `Test Appeal` after a few seconds and refresh. | **Total Raised** 500.00, **Gift Count** 1, **Net Raised** -700.00, **Percent To Goal** 2%. |
| 4 | Edit `Test Appeal`, set **Parent Appeal** to `Test Appeal`, save. | Refused: "An appeal cannot be its own parent appeal." |
| 5 | Set **Parent Appeal** to `Annual Fund`, save. Then open **Annual Fund**, set its **Parent Appeal** to `Test Appeal`, save. | The first save works. The second is refused: "That parent appeal would create a loop, because this appeal is already above it..." |

**Cleanup:** none.

## T-GIFT-08: Gift batch: enter, balance and post

**Purpose:** confirm a batch tracks the control total, saves lines, posts all lines as gifts once balanced, and locks after posting.
**Prerequisites:** staff; General Fund is the default.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Gift Batches** tab, click **New**. **Description** `Tuesday mail`, **Control Total** `350`, **Default Appeal** `Annual Fund`; leave **Default Fund** empty. Save. | **Default Gift Date** is today and **Default Payment Method** is Check. The batch opens with the **Lines** card: **Control total** $350.00, **Entered** $0.00, "No lines yet. Click Add line and type the first check." |
| 2 | Click **Add line**. Pick **Harper Garcia**, **Amount** `100`, **Check number** `1042`. | Status line: "This batch does not balance: the lines add up to 250.00 less than the control total..." **Post batch** is disabled. |
| 3 | **Add line**, switch it to **Organization**, pick **The Summit Foundation**, **Amount** `200`, **Fund** `Building Fund`. | Other cells show **As the batch**. Status: 50.00 less. |
| 4 | **Add line**, a person (Luis Garcia), **Amount** `75`. | Status: "...25.00 more than the control total..." |
| 5 | Change that amount to `50`. | Status: "Balanced: the lines add up to the control total." |
| 6 | Click **Save**, then reload the page. | "Lines saved." The three lines are still there. The **Open Batches** list view lists `Tuesday mail`. |
| 7 | Click **Post batch**. | "Batch posted: 3 gifts created." The note "This batch is posted. Each line links to the gift it became..." shows; no **Add line**, **Save** or **Post batch**. |
| 8 | Click the first line's gift link. | Gift dated today, Check, appeal Annual Fund, **Payment Reference** 1042, one allocation to General Fund. The Summit Foundation gift is allocated to Building Fund. |
| 9 | Back on the batch, click **Edit**, change **Control Total**, save. | Refused: "This batch has been posted and can no longer be changed. To correct one of its gifts, refund or write off that gift." |

**Cleanup:** none.

## T-GIFT-09: Gift batch refusals and read-only access

**Purpose:** confirm unfinished lines stop a post, nothing is created on failure, and a read-only user cannot change a batch.
**Prerequisites:** staff, then read-only.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, create a batch `Bad lines`, **Control Total** `60`. **Add line** with **Amount** `60` and no donor. Save. | "Lines saved." Status: Balanced. |
| 2 | Click **Post batch**. | "Some lines are not finished. Fix the lines marked below, then post again." Line 1 shows "This line has no donor. Find the person or organization that gave." No gift is created. |
| 3 | Pick **Harper Garcia** on line 1 and set its **Amount** to `100`. **Add line** for **Luis Garcia** with **Amount** `-40`. | Status: Balanced (100 less 40 is 60). |
| 4 | Click **Post batch**. | "Some lines are not finished..." Line 2 shows "This line needs an amount greater than zero. Money that went back is recorded as a refund on the gift, not here." No gift is created. |
| 5 | Set line 2's **Amount** to `40` and line 1's to `20`, then click **Save**. Do not post. | "Lines saved." Status: Balanced. |
| 6 | As read-only, open **Gift Batches**, list view **Open Batches**, open `Bad lines`. | "You can see this batch but not change or post it. Ask your administrator for the Giving Staff permission set, or for edit access to this batch." No **Add line**, **Save** or **Post batch**. |
| 7 | As read-only, look at the **Gift Batches** tab header. | No **New** button. |

**Cleanup:** as admin, delete batch `Bad lines` (staff cannot delete a batch).

## T-GIFT-10: Closed accounting periods

**Purpose:** confirm a closed period refuses gifts dated in it, still allows refunds and non-money edits, and cannot be reopened from the app.
**Prerequisites:** admin. Run this near the end of a test cycle: a closed period cannot be reopened without the **Override Posting Lock** permission, and sample gifts in a closed period cannot be removed. Posting gifts to accounting is tested in [Mirror](mirror.md) (T-MIR-09).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Giving**, **Accounting periods**, **Open**. | Card **Accounting Periods** with **Books closed through** and "No period is closed." |
| 2 | Set **Books closed through** to today, click **Save**. | Refused: "The books can be closed through the day before yesterday at the latest..." |
| 3 | Set it to the last day of last month (on the 1st or 2nd, the month before), click **Save**. | "Saved. The books are closed through the date shown." |
| 4 | On **Quick Gift Entry**, enter a gift for Harper Garcia, 20, Cash, **Gift date** in last month. Save. | Not saved; the message starts "The books are closed through", naming the date. |
| 5 | Change **Gift date** to today and save. | Saved. |
| 6 | Open a Received sample gift dated last month. Its **Posting** card says it is dated in a closed period. Edit **Amount**, save. | Refused: "This gift is dated in a closed accounting period (the books are closed through ...), so its date, amount, donor, payment method, reference and funds cannot change..." |
| 7 | Cancel, edit **Acknowledgment Status** instead, save. | Saved. |
| 8 | Click **Refund or Write Off**, refund `10` with a reason. | Recorded; the refund gift is dated today. |
| 9 | Back on **Accounting Periods**, set an earlier date and click **Save**. | Refused: "A closed period cannot be reopened here. Moving the date back or clearing it needs the Override Posting Lock permission..." |

**Cleanup:** to reopen, follow "Reopening a period" in [Posting and closed periods](../admin-guide/posting-and-closed-periods.md) (a temporary permission set with **Override Posting Lock**), clear the date, then remove the assignment.

## T-GIFT-11: Import gifts with the generic gift list

**Purpose:** confirm a gift file previews, imports into existing and new donors, rejects a bad fund, does not duplicate on reload, and undoes.
**Prerequisites:** admin; Data Manager on (see [Imports](imports.md)). Save `gift-import-test.csv`, using a date in the current month:

```
Donor First Name,Donor Last Name,Donor Email,Gift Amount,Gift Date,Payment Method,Payment Reference,Fund,Transaction ID
Harper,Garcia,harper.garcia1@example.org,75,2026-10-05,cheque,5001,General Fund,TX-T-1
Gia,Testgift,gia.testgift@example.org,40,2026-10-05,credit card,,Building Fund,TX-T-2
Hal,Badfund,hal.badfund@example.org,30,2026-10-05,Cash,,Genral Fund,TX-T-3
```

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Import tab from **Data Manager**, choose **Generic gift list**, **Next**, upload the file. | **Check the columns** maps the first eight columns to person and gift targets (for example **Gift: amount**, **Gift: fund**). |
| 2 | Map **Transaction ID** to **Gift: external ID**. **Next**. | The matching step shows **Email exact** and **Matching gifts to scheduled payments** on **Match or create**. |
| 3 | Under **Control totals (optional)** enter **Rows in the file** `3`, **Total of the gift amounts** `145`. Select **Preview**. | 2 rows would create a gift, 1 would be rejected: "No fund is named Genral Fund, or has it as its accounting code." Run log: "Control total: the file has 3 rows, as expected." |
| 4 | Select **Import these rows**. | Results: 2 gifts created, 1 rejected. |
| 5 | Open Harper Garcia's newest gift. | 75.00, **Payment Method** Check ("cheque" understood), General Fund, **Created By Import Batch** links to the import. Gia Testgift exists with a Card gift to Building Fund. |
| 6 | Load the same file again and preview. | The two loaded rows match the gifts you already have; nothing would be created. Cancel. |
| 7 | Undo the first import (**Undo this import**, confirm). | The two gifts and the contact Gia Testgift are removed. Harper Garcia stays. |

**Cleanup:** none after undo.

## T-GIFT-12: Giving access by permission set

**Purpose:** confirm what staff and read-only users can and cannot do with gifts and funds.
**Prerequisites:** staff, then read-only; any sample gift.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the **Fundraising** app. | Tabs include **Quick Gift Entry**, **Gifts**, **Commitments**, **Gift Batches**, **Funds** and **Appeals**. |
| 2 | As staff, open a gift. | **Edit** and **Refund or Write Off** show; **Delete** does not. |
| 3 | As read-only, open the **Fundraising** app. | No **Quick Gift Entry** tab. **Gifts**, **Funds** and **Appeals** show no **New** button. |
| 4 | As read-only, open a gift. | No **Edit** or **Delete**. The **Soft credits** panel's **Add credit** is disabled. |
| 5 | As read-only, open a person with gifts in the Fundraising app. | The **Giving** section and **Gifts** list show; there is no **New Gift** button. |

**Cleanup:** none.
