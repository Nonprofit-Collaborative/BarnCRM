# Giving: Gifts, Funds and Batches

Scripts for entering gifts (Gifts tab, Quick Gift Entry, gift batches, import), funds, appeals, in-kind gifts and closed accounting periods. Setup detail: [Gifts](../admin-guide/gifts.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Giving deployed and sample data loaded unless a script says otherwise. Work in the **BarnCRM Fundraising** app (app launcher). Sample data makes no fund the default, so run T-GIFT-01 first (a new org's own starting **General Fund** is already the default: see T-GIFT-14). Related admin-guide pages: [Quick Gift Entry](../admin-guide/quick-gift-entry.md), [Funds](../admin-guide/funds.md), [Appeals](../admin-guide/appeals.md), [Gift batches](../admin-guide/gift-batches.md), [In-kind gifts](../admin-guide/in-kind-gifts.md), [Posting and closed periods](../admin-guide/posting-and-closed-periods.md), [Importing gifts](../admin-guide/gift-import.md), [A donor's giving on their record](../admin-guide/donor-records.md). Refunds, receipts and the receipt lock have their own pages.

## T-GIFT-01: Funds and the Default Fund

**Purpose:** confirm one fund is the default, the flag moves when a second fund takes it, and a fund with gifts cannot be deleted.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Funds** tab, list view **All Funds**. | **General Fund** to **Memorial Fund** show, 8 funds in all. On an org that started with a default fund (a new org's own starting **General Fund**, T-GIFT-14), that fund is the only **General Fund** and the other 7 are sample funds. |
| 2 | Open **General Fund**. If **Is Default** is not ticked, click **Edit**, tick it, and save. | **Is Default** is ticked. **Total Raised**, **Gift Count**, **Last Gift Date** and **Totals Last Updated** are read only. |
| 3 | Open **BarnCRM Settings**, **Giving**. | **Default fund** shows General Fund. |
| 4 | On the **Funds** tab click **New**. Name `Test Fund`, tick **Active** and **Is Default**, and save. | Saved. |
| 5 | Reopen **General Fund**. | **Is Default** is now unticked: only one default exists. |
| 6 | Edit **General Fund**, tick **Is Default** again, and save. Reopen `Test Fund`. | `Test Fund` is no longer the default. |
| 7 | On **General Fund**, choose **Delete** and confirm. | Refused: "Gifts have been designated to this fund, so it cannot be deleted: deleting it would leave those gifts pointing at nothing. Untick Active instead..." |
| 8 | Delete `Test Fund` (it has no gifts). | Deleted. |

**Cleanup:** keep **General Fund** as the default; every later script needs it.

## T-GIFT-02: Enter a Gift on the Gifts Tab

**Purpose:** confirm a gift gets its household and a default allocation, and allocations must total the gift.
**Prerequisites:** staff; General Fund is the default (T-GIFT-01).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Gifts** tab and click **New**. | The new gift form shows **Donor Contact**, **Donor Account**, **Amount**, **Gift Date** (already today), **Payment Method**, **Status** (Received), **Appeal**, **Commitment** and **Installment**. |
| 2 | Choose **Harper Garcia** in **Donor Contact**, **Amount** `250`, **Gift Date** today, **Payment Method** `Check`, **Appeal** `Spring Appeal`. Save. | The gift opens on the gift page, named `G-` and a number. |
| 3 | Read the **Household** field. | It names Harper's household (The Garcia Family), filled in by BarnCRM. |
| 4 | Click the **Related** tab and look at the **Gift Allocations** list. | One allocation: **General Fund**, 250.00. |
| 5 | Open the allocation, click **Edit**, set **Amount** to `100`, save. | Refused: "The allocations of this gift total 100.00, but the gift is 250.00. The difference is 150.00." |
| 6 | Cancel the edit. | The allocation stays 250.00. |
| 7 | Check the gift's action bar. | **Edit** and **Refund or Write Off** show. **Delete** does not (Giving Staff cannot delete). |
| 8 | Open Harper Garcia from the **Donor Contact** link and refresh after a few seconds. | The **Giving** section shows **Total Giving** including the 250 and **Totals Last Updated** close to now (in **Giving Details**). On the **Related** tab, the **Gifts** list shows the new gift first. |

**Cleanup:** none; T-GIFT-03 and other pages reuse the gift.

## T-GIFT-03: Gift Rules That Refuse a Save, and Cancelling a Pending Gift

**Purpose:** confirm the donor, amount and status rules, and that a cancel can be reversed only back to Pending.
**Prerequisites:** admin; the gift from T-GIFT-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **New** on the **Gifts** tab. Fill both **Donor Contact** (Harper Garcia) and **Donor Account** (any organization), **Amount** `10`, today, `Cash`. Save. | Refused: "Choose one donor: a person or an organization, not both." |
| 2 | Clear **Donor Account**, set **Amount** `0`, save. | Refused: "A gift amount cannot be zero. Enter what was received; money going back is recorded with Refund or Write Off on the original gift..." |
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
| 1 | Open the **Quick Gift Entry** tab. | Card **Quick Gift Entry**. **Who gave this gift** is on **Person**; **Gift Date** is today; **Appeal** shows Annual Fund; **Fund** shows General Fund. |
| 2 | In **Donor** type `Garc` and pick **Luis Garcia**. Enter **Amount** `50`, **Payment Method** `Check`, **Check or reference number** `1042`. | Values stay as typed. No **Pays a scheduled payment** list appears (Luis owes no pledge payment). |
| 3 | Click **Save and New**. | "Gift G-... saved" with an **Open This Gift** link. The donor, amount, payment method and check number clear; the date, appeal and fund stay. |
| 4 | Switch to **Organization**, pick **Founders Consulting Group**, **Amount** `25`, **Payment Method** `Cash`. Click **Save**. | Saved message with link. **Save** and **Save and New** are now greyed out. |
| 5 | Change the amount to `30`. | **Save** and **Save and New** are enabled again. Do not save. |
| 6 | Click **Open This Gift**. | The gift shows **Donor Account** Founders Consulting Group, 25.00, Cash, appeal Annual Fund, one allocation to General Fund. |
| 7 | Open the utility bar at the bottom of any BarnCRM Fundraising page. | **Quick Gift Entry** opens there over the page. |
| 8 | Save another gift and look at the saved message. | A green success notice with a check icon: "Gift G-... saved" and an underlined **Open This Gift** link in the notice's own text color, easy to read; the link opens the gift. |
| 9 | Click **Save and New**, then type `Garc` in **Donor**. | Each name in the list shows the person's email and mailing city under it. Switch to **Organization** and type `Found`: each organization shows its billing city. |
| 10 | Open **Luis Garcia**'s page in the BarnCRM Fundraising app and click **Enter a Gift** in the action bar. | A window titled **Enter a Gift** opens with Quick Gift Entry inside (no second Quick Gift Entry title), **Person** chosen and **Luis Garcia** in **Donor**. |
| 11 | Enter **Amount** `15`, **Payment Method** `Cash`, click **Save**. | The window closes, a "Gift Saved" toast shows, and the gift is in the page's **Gifts** list. |
| 12 | Open **Founders Consulting Group** and click **Enter a Gift**. | **Organization** is chosen with Founders Consulting Group as donor. Close the window. |
| 13 | On the **Quick Gift Entry** tab type **Amount** `40`, then click **Not in the list? Add a new person**. | A **Not in the list? Add a new person** window over the form asks for Salutation, First Name, Last Name, Email, Street, City and Postal Code. |
| 14 | Type `Test` `Newdonor`, an email, and click **Save**. | The window closes; **Donor** shows Test Newdonor and **Amount** still reads 40. Do not save the gift yet. |
| 15 | Open **Split Across Funds**, set the first row to General Fund 30.00, click **Add a Fund**, choose **Building Fund** (T-GIFT-16) for the rest. | **Fund** above is greyed out; "Left to assign: $0.00". |
| 16 | Change the second row to 5.00 and click **Save**. | Not saved: the section opens with "A split is for a gift of money: choose a different fund on every row, give each an amount, and make the rows add up to the gift's amount." |
| 17 | Set the second row back to 10.00 and click **Save**. Open the gift. | **Gift Allocations** shows General Fund 30.00 and Building Fund 10.00, no third row. |
| 18 | Open a draft gift batch, click **Not in the list? Add a new person** under a line's donor, create `Test Batchdonor`. | The window closes and the line's donor is Test Batchdonor; the batch shows unsaved changes. |

**Cleanup:** set **Default appeal** back to empty if later scripts expect none.

## T-GIFT-04b: Tribute and Matching Gift in Quick Gift Entry

**Purpose:** confirm the collapsed honors section saves a tribute with the gift, and an organization's gift can match an employee's gift chosen from a list.
**Prerequisites:** staff; General Fund is the default. As admin, set **Employer** on **Harper Garcia** to **Founders Consulting Group**, and enter one gift of `100` from Harper Garcia.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Quick Gift Entry**. | Under **Fund**, two collapsed sections: **This Gift Honors Someone** (and, once an organization donor is chosen, **Matches an Employee's Gift**). |
| 2 | Pick **Luis Garcia**, **Amount** `40`, **Payment Method** `Check`. Open **This Gift Honors Someone** and type `Rosa Garcia` in **Honoree Name** only. Click **Save**. | Under **Type**: "Choose whether this gift is in honor of someone or in memory of them." Nothing is saved. |
| 3 | Choose **Type** `In memory of` and click **Save**, then **Open This Gift**. | Saved. The gift's **Tribute** card reads In memory of Rosa Garcia. |
| 4 | Back on Quick Gift Entry, switch to **Organization**, pick **Founders Consulting Group**, **Amount** `100`, **Payment Method** `Check`. Open **Matches an Employee's Gift**. | **Matched Gift** lists Harper Garcia's 100.00 gift with its date and gift number, after **None**. |
| 5 | Choose that gift and click **Save**, then **Open This Gift**. | **Matched Gift** names Harper's gift, and **Soft Credits** shows Harper Garcia as **Matched Donor**. Harper's gift shows the link in its own **Matched Gift**. |
| 6 | Pick an organization no one names as Employer and open **Matches an Employee's Gift**. | "No gift to match yet: nobody whose Employer is this organization has a gift that is not already matched." |

**Cleanup:** none.

## T-GIFT-05: Quick Gift Entry Refusals and In-Kind Fields

**Purpose:** confirm messages sit on the field they concern, and In-kind swaps the amount for description and value.
**Prerequisites:** staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Quick Gift Entry**, leave **Donor** empty, click **Save**. | Under **Donor**: "Choose the person or organization who gave this gift." Nothing is saved. |
| 2 | Pick **Harper Garcia**, enter **Amount** `-20`, **Payment Method** `Cash`, click **Save**. | Under **Amount**: "Enter an amount greater than zero. A refund is entered from the original gift, not here." |
| 3 | Clear **Payment Method** (choose **Choose one**) and amount `20`, click **Save**. | Under **Payment Method**: "Choose a payment method." |
| 4 | Choose **Payment Method** `In-kind`. | **Amount** and **Pays a scheduled payment** disappear. **What was given** and **Fair market value** appear, with "For your reporting only. It is never printed on the receipt..." under the value. |
| 5 | Leave **What was given** empty, click **Save**. | Under **What was given**: "Describe what was given. This text is the donor's receipt, so a gift of goods cannot be saved without it." |
| 6 | Type `Sixteen folding tables, used`, **Fair market value** `-5`, click **Save**. | "Fair market value cannot be negative. Leave it empty if you do not have a figure yet." |
| 7 | Set **Fair market value** `800`, click **Save**, then **Open This Gift**. | **Amount** 0.00, **In-kind Description** and **Fair Market Value** 800.00 show in the in-kind section. |

**Cleanup:** none; T-GIFT-06 uses the in-kind gift.

## T-GIFT-06: In-Kind Rules on the Gift Record

**Purpose:** confirm the in-kind validation rules and that in-kind value stays out of total giving.
**Prerequisites:** admin; the in-kind gift from T-GIFT-05.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the in-kind gift, click **Edit**, set **Amount** `800`, save. | Refused: "An in-kind gift has no amount, because goods are not money the organization holds. Leave Amount at zero..." Cancel. |
| 2 | Edit, clear **In-kind Description**, save. | Refused: "Describe what was given. This text is printed on the donor's receipt..." Cancel. |
| 3 | Open the T-GIFT-02 gift (Check, 250), edit, type `Chairs` in **In-kind Description**, save. | Refused: "In-kind Description and Fair Market Value belong to a gift of goods or services. Either set Payment Method to In-kind, or clear both fields." Cancel. |
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

## T-GIFT-08: Gift Batch: Enter, Balance and Post

**Purpose:** confirm a batch tracks the control total, saves lines, posts all lines as gifts once balanced, and locks after posting.
**Prerequisites:** staff; General Fund is the default.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Gift Batches** tab, click **New**. **Description** `Tuesday mail`, **Control Total** `350`, **Default Appeal** `Annual Fund`; leave **Default Fund** empty. Save. | **Default Gift Date** is today and **Default Payment Method** is Check. The batch opens with the **Lines** card: two figure tiles, **Control total** $350.00 and **Entered** $0.00, and an empty state **No Lines Yet**, "Choose Add Line and type the first check.", with an **Add Line** button. |
| 2 | Click **Add Line**. Pick **Harper Garcia** (the list shows email and city under each name), **Amount** `100`, **Check Number** `1042`. | Amber notice: "This batch does not balance: the lines add up to 250.00 less than the control total..." **Create Gifts** is disabled. |
| 3 | **Add Line**, switch it to **Organization**, pick **The Summit Foundation**, **Amount** `200`, **Fund** `Building Fund`. | Other cells show **As the batch**. Status: 50.00 less. |
| 4 | **Add Line**, a person (Luis Garcia), **Amount** `75`. | Status: "...25.00 more than the control total..." |
| 5 | Change that amount to `50`. | Green notice: "Balanced: the lines add up to the control total." |
| 6 | Click **Save**, then reload the page. | "Lines saved." The three lines are still there. The **Open Batches** list view lists `Tuesday mail`. |
| 7 | Click **Create Gifts**. | "Gifts created: 3 from this batch." The green note "These gifts have been created. Each line links to its gift..." shows; no **Add Line**, **Save** or **Create Gifts**. |
| 8 | Click the first line's gift link. | Gift dated today, Check, appeal Annual Fund, **Payment Reference** 1042, one allocation to General Fund. The Summit Foundation gift is allocated to Building Fund. |
| 9 | Back on the batch, click **Edit**, change **Control Total**, save. | Refused: "The gifts for this batch have been created, so it can no longer be changed. To correct one of its gifts, refund or write off that gift." |

**Cleanup:** none.

## T-GIFT-09: Gift Batch Refusals and Read-Only Access

**Purpose:** confirm unfinished lines stop a post, nothing is created on failure, and a read-only user cannot change a batch.
**Prerequisites:** staff, then read-only.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, create a batch `Bad lines`, **Control Total** `60`. **Add Line** with **Amount** `60` and no donor. Save. | "Lines saved." Status: Balanced. |
| 2 | Click **Create Gifts**. | Red notice: "Some lines are not finished. Fix the lines marked below, then choose Create Gifts again." Line 1 shows a red notice "This line has no donor. Find the person or organization that gave." No gift is created. |
| 3 | Pick **Harper Garcia** on line 1 and set its **Amount** to `100`. **Add Line** for **Luis Garcia** with **Amount** `-40`. | Status: Balanced (100 less 40 is 60). |
| 4 | Click **Create Gifts**. | "Some lines are not finished..." Line 2 shows "This line needs an amount greater than zero. Money that went back is recorded as a refund on the gift, not here." No gift is created. |
| 5 | Set line 2's **Amount** to `40` and line 1's to `20`, then click **Save**. Do not create the gifts. | "Lines saved." Status: Balanced. |
| 6 | As read-only, open **Gift Batches**, list view **Open Batches**, open `Bad lines`. | "You can see this batch but not change it or create its gifts. Ask your BarnCRM admin for the Giving Staff permission set, or for edit access to this batch." No **Add Line**, **Save** or **Create Gifts**. |
| 7 | As read-only, look at the **Gift Batches** tab header. | No **New** button. |

**Cleanup:** as admin, delete batch `Bad lines` (staff cannot delete a batch).

## T-GIFT-10: Closed Accounting Periods

**Purpose:** confirm a closed period refuses gifts dated in it, still allows refunds and non-money edits, and cannot be reopened from the app.
**Prerequisites:** admin. Run this near the end of a test cycle: a closed period cannot be reopened without the **Override Posting Lock** permission, and sample gifts in a closed period cannot be removed. Posting gifts to accounting is tested in [Mirror](mirror.md) (T-MIR-09).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Giving**, **Accounting Periods**, **Open**. | Card **Accounting Periods** with **Books Closed Through** and "No period is closed." |
| 2 | Set **Books Closed Through** to today, click **Save**. | Refused: "The books can be closed through the day before yesterday at the latest..." |
| 3 | Set it to the last day of last month (on the 1st or 2nd, the month before), click **Save**. | "Saved. The books are closed through the date shown." |
| 4 | On **Quick Gift Entry**, enter a gift for Harper Garcia, 20, Cash, **Gift Date** in last month. Save. | Not saved; the message starts "The books are closed through", naming the date. |
| 5 | Change **Gift Date** to today and save. | Saved. |
| 6 | Open a Received sample gift dated last month. Its **Posting** card says it is dated in a closed period. Edit **Amount**, save. | Refused: "This gift is dated in a closed accounting period (the books are closed through ...), so its date, amount, donor, payment method, reference and funds cannot change..." |
| 7 | Cancel, edit **Acknowledgment Status** instead, save. | Saved. |
| 8 | Click **Refund or Write Off**, refund `10` with a reason. | Recorded; the refund gift is dated today. |
| 9 | Back on **Accounting Periods**, set an earlier date and click **Save**. | Refused: "A closed period cannot be reopened here. Moving the date back or clearing it needs the Override Posting Lock permission..." |

**Cleanup:** to reopen, follow "Reopening a period" in [Posting and closed periods](../admin-guide/posting-and-closed-periods.md) (a temporary permission set with **Override Posting Lock**), clear the date, then remove the assignment.

## T-GIFT-11: Import Gifts with the Generic Gift List

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
| 1 | Open the Import tab from **Data Manager**, under **What Are You Importing?** choose **Gifts**, then **Generic Gift List**, **Next**, upload the file. | **Check Columns** maps the first eight columns to person and gift targets (for example **Gift: amount**, **Gift: fund**). |
| 2 | Map **Transaction ID** to **Gift: external ID**. **Next**. | The matching step shows **Email exact** and **Matching gifts to scheduled payments** on **Match or create**. |
| 3 | Under **Control Totals (Optional)** enter **Rows in the file** `3`, **Total of the gift amounts** `145`. Select **Preview**. | 2 rows would create a gift, 1 would be rejected: "No fund is named Genral Fund, or has it as its accounting code." Run log: "Control total: the file has 3 rows, as expected." |
| 4 | Select **Import These Rows**. | Results: 2 gifts created, 1 rejected. |
| 5 | Open Harper Garcia's newest gift. | 75.00, **Payment Method** Check ("cheque" understood), General Fund, **Created By Import Batch** links to the import. Gia Testgift exists with a Card gift to Building Fund. |
| 6 | Load the same file again and preview. | The two loaded rows match the gifts you already have; nothing would be created. Cancel. |
| 7 | Undo the first import (**Undo This Import**, confirm). | The two gifts and the contact Gia Testgift are removed. Harper Garcia stays. |

**Cleanup:** none after undo.

## T-GIFT-12: Giving Access by Permission Set

**Purpose:** confirm what staff and read-only users can and cannot do with gifts and funds.
**Prerequisites:** staff, then read-only, then admin; any sample gift; for step 6, a user with no BarnCRM role.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the **BarnCRM Fundraising** app. | Tabs include **Quick Gift Entry**, **Gifts**, **Commitments**, **Gift Batches**, **Funds** and **Appeals**. |
| 2 | As staff, open a gift. | **Edit** and **Refund or Write Off** show; **Delete** does not. |
| 3 | As read-only, open the **BarnCRM Fundraising** app. | No **Quick Gift Entry** tab. **Gifts**, **Funds** and **Appeals** show no **New** button. |
| 4 | As read-only, open a gift. | No **Edit** or **Delete**. The **Soft Credits** panel's **Add Credit** is disabled. |
| 5 | As read-only, open a person with gifts in the BarnCRM Fundraising app. | The **Giving** section and **Gifts** list show; there is no **Enter a Gift** button. |
| 6 | As admin, on BarnCRM Settings, **Access**, give the user with no role the **BarnCRM Admin** role. Wait up to an hour, or run `new GivingAccessSync().requestSync();` in Anonymous Apex. In Setup, open the user's **Permission Set Assignments**. | **Giving Admin** is assigned, without anyone giving it. Cleanup: remove the role and Giving Admin. |

**Cleanup:** none.

## T-GIFT-14: A New Org Starts with a Default Fund

**Purpose:** a freshly deployed Giving org already has one default fund, so the first gift works without any setup.
**Prerequisites:** a new org deployed with `scripts/org/deploy-packages.sh` (default settings) or installed as packages, with no fund created by hand and no sample data loaded. Admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Funds** tab, list view **All Funds**. | Exactly one fund: **General Fund**, **Active** ticked, **Restricted** and **Accounting Code** empty, **Is Default** ticked. |
| 2 | Open **BarnCRM Settings**, **Giving**. | **Default fund** shows **General Fund**, not blank. |
| 3 | Open the **Home** tab and the Setup Assistant step **Pick your default fund and appeal**. | The fund picker shows **General Fund** already chosen. |
| 4 | Enter a gift for any person without choosing a fund. | It saves, with one allocation for the whole amount to **General Fund**. |
| 5 | Rename the fund to `Annual Giving` and untick **Is Default**. Run the deploy script (or reinstall the package) again. | No second **General Fund** appears. **All Funds** still shows one fund, named `Annual Giving`, and the Default Fund setting is blank. |
| 6 | On a different org that already has a fund of your own, run the deploy script (or reinstall the package). | No fund is added and the Default Fund setting is not changed. |

**Cleanup:** none (or delete the gift from step 4 and the fund).

## T-GIFT-13: List Views for Gifts, Funds, Appeals, Donor Levels and Batches

**Purpose:** each giving object opens with an All view and the status views an admin expects.
**Prerequisites:** staff user, sample data loaded (the Inactive views are empty until you switch something off).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Gifts** tab and the list view menu. | **All Gifts**, **My Gifts**, **Pending Gifts**, **Gifts to Acknowledge** and **Refunds and Write-Offs** are listed. |
| 2 | Enter a gift as yourself, then choose **My Gifts**. | The new gift shows. Gifts the sample loader created do not, unless you own them. |
| 3 | Open the **Funds** tab. | **All Funds**, **Active Funds** and **Inactive Funds** are listed. Untick **Active** on a sample fund that has no gifts: it moves to **Inactive Funds** and leaves **Active Funds**. Tick it again. |
| 4 | Open **Appeals** and **Donor Levels** and open each list view menu. | **All Appeals**, **Active Appeals**, **Inactive Appeals**; **All Donor Levels**, **Active Donor Levels**, **Inactive Donor Levels**. |
| 5 | Open **Gift Batches**. | **All Gift Batches**, **Open Batches** and **My Gift Batches** are listed. A batch you create shows in **My Gift Batches**. |

**Cleanup:** none.

## T-GIFT-15: Sample Data Reuses the Org's Default Fund

**Purpose:** loading sample data on an org that already has a default fund does not add a second General Fund, and removing it leaves the org's fund.
**Prerequisites:** admin; a new Giving org with its starting **General Fund** as the default (T-GIFT-14), no sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Sample Data**, and load the sample data with Giving installed. | The load finishes. |
| 2 | Open the **Funds** tab, list view **All Funds**. | One **General Fund** (yours, still the default) and seven sample funds, 8 in all. |
| 3 | Open **General Fund** and its gifts. | Sample gifts are allocated to it. |
| 4 | Select **Remove Sample Data** and confirm. | The removal finishes. |
| 5 | Open **All Funds**. | **General Fund** is still there and still the default. The seven sample funds and the sample gifts are gone. |

**Cleanup:** none.

## T-GIFT-16: Split a Gift Across Funds with Edit Funds

**Purpose:** the gift page's **Edit Funds** splits a gift in one save, keeps the split adding up, and respects the posting lock.
**Prerequisites:** T-GIFT-01; an active fund **Building Fund**; the **Gift Allocations** card on the Gift record page; a test user with **Giving Staff** and one with **Giving Admin**.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the Giving Staff user, enter a 200.00 gift with no fund and open it. | **Gift Allocations** shows one row: General Fund, 200.00, 100%, and an **Edit Funds** button. |
| 2 | Click **Edit Funds**. | One row (General Fund, 200.00, 100%), **Add a Fund**, a green "Left to assign: $0.00" badge, **Save** and **Cancel**. |
| 3 | Set the row's **Percent** to `50`. | **Amount** becomes 100.00; the badge turns amber, "Left to assign: $100.00"; **Save** is off. |
| 4 | Click **Add a Fund**. | A second row with **Amount** 100.00 and no fund; a bar with one divider appears under the rows. |
| 5 | Choose **Building Fund** in the second row. | The badge reads "Left to assign: $0.00" and turns green; **Save** is on. |
| 6 | Select the divider on the bar and press the Right arrow three times. | General Fund 106.00 (53%), Building Fund 94.00 (47%); a screen reader announces "General Fund 53%, Building Fund 47%". |
| 7 | Drag the divider back to the middle with the mouse or a finger. | The split returns to about 50% each and the totals still leave 0.00 to assign. |
| 8 | Choose **General Fund** in the second row too. | A warning: "Each fund can be chosen once. Put all of its amount on one row." **Save** is off. Choose **Building Fund** again. |
| 9 | Click **Save**. | "Funds saved. The gift's allocations now match the split." Two rows, General Fund and Building Fund, adding up to 200.00. Building Fund's **Total Raised** includes its share after the next rollup. |
| 10 | Still as the Giving Staff user, click **Edit Funds**, delete the Building Fund row, set General Fund to 200.00, click **Save**. | Saved: one row, General Fund 200.00. Giving Staff may delete Gift Allocations (plan D-176). |
| 11 | Split the gift again (General Fund 100.00, Building Fund 100.00), then as the Giving Admin user repeat step 10. | Saved: one row, General Fund 200.00. |
| 12 | Mark the gift posted on the **Accounting Export** page and reopen it. | **Edit Funds** is gone; an info notice reads "This gift is in the books (posted to accounting, or dated in a closed period), so its funds and amounts to each cannot change. Record a refund instead." |

**Cleanup:** unpost the gift from its **Posting** card, then delete it.
## T-GIFT-17: Gift and Commitment Pages Use Tabs

**Purpose:** the gift and commitment pages group their parts in tabs, with the posting and receipt cards kept in the sidebar.
**Prerequisites:** staff; sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open any sample gift with a soft credit. | Tabs **Details**, **Credits and Tributes**, **Related**, with **Details** open: sections **Gift** and **Acknowledgment, Receipt and Recognition**. The sidebar shows **Posting**, **Gift Allocations** (with **Edit Funds**), **Receipt Actions** and the activity panel. |
| 2 | Click **Credits and Tributes**. | The **Soft Credits** and **Tribute** cards. |
| 3 | Click **Related**. | The **Gift Allocations**, **Refunds and Write-offs**, **Tributes** and **Acknowledgments** lists. |
| 4 | Open a sample pledge from the **Commitments** tab. | The payment schedule at the top, then tabs **Details** (sections **Commitment**, **Schedule**, **Totals**) and **Related** (the **Gifts** list). |

**Cleanup:** none.

## T-GIFT-18: Giving at a Glance in the BarnCRM App

**Purpose:** Core's person and organization pages show Giving's summary card, and Enter a Gift opens Quick Gift Entry for that donor.
**Prerequisites:** staff (Giving Staff); a read-only user with Giving Read Only; sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | In the **BarnCRM** app, open **Harper Garcia**. | The sidebar starts with **Giving at a Glance**: **Total Giving**, **Last Gift Date**, **Donor Level** (when she has one) and **Enter a Gift**. |
| 2 | Click **Enter a Gift**. | Quick Gift Entry opens with Harper Garcia as the donor. |
| 3 | Save a gift of 25, go back to Harper and refresh. | **Total Giving** has gone up by 25 and **Last Gift Date** is today. |
| 4 | Open **The Garcia Family** and an organization that gave. | Each shows the card with its own figures. |
| 5 | As the read-only user, open Harper Garcia. | The card shows without **Enter a Gift**. |
| 6 | As a user with no Giving permission set, open Harper Garcia. | No card; the sidebar starts with the next card. |

**Cleanup:** refund or delete the gift from step 3.

## T-GIFT-22: NPSP Funds, Levels and Recurring Donations Kit

**Purpose:** confirm the kit copies NPSP General Accounting Units, levels and recurring donations into Giving and never changes NPSP.
**Prerequisites:** admin; an org with NPSP installed (a test org, never production); in NPSP, a General Accounting Unit "Building Fund", a level "Friend" (100 to 499.99), an open monthly recurring donation of 25 for a contact with a next payment date next month, and a closed yearly one of 500 for an organization.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Integrations**, NPSP. | One **Start Migration** button per kit, including **Start Migration: NPSP Funds, Levels, Recurring Donations**. |
| 2 | Start it; preview and load **Funds**, then **Donor Levels**. | A fund Building Fund and a donor level Friend with the same amounts. **Check this step** matches each. |
| 3 | Load **Recurring Donations of People**. | A recurring commitment of 25, Monthly, Active, for the same contact, starting at the NPSP next payment date; no overdue payments. |
| 4 | Load **Recurring Donations of Organizations**. | A recurring commitment of 500, Yearly, Cancelled, for the organization. |
| 5 | Open the NPSP records. | Nothing in NPSP changed. |

**Cleanup:** undo the four steps in reverse order.
