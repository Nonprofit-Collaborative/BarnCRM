# Giving: Rollups and Dashboards

Scripts for the giving totals on donors, funds and appeals, the Giving Overview dashboard and the retention reports. Setup detail: [Rollups](../admin-guide/rollups.md), [Giving dashboard](../admin-guide/giving-dashboard.md), [Retention reports](../admin-guide/retention-reports.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, BarnCRM Rollup Builder and Giving deployed and sample data loaded unless a script says otherwise. Building, editing and switching off your own rollups is covered in [Rollup Builder](rollup-builder.md); this page tests the giving totals Giving ships.

For every script on this page:

- In **BarnCRM Settings**, **Giving**, set **Default fund** to **General Fund** and save.
- "Enter a gift" means: in the **BarnCRM Fundraising** app, open **Quick Gift Entry**, choose **Person**, pick the **Donor**, type the **Amount**, set **Payment Method** to **Check** and **Fund** to **General Fund**, then select **Save**.
- Totals are recalculated a few seconds after a save. Refresh the record page before reading a total.
- Sample data: **The Garcia Family** holds three gifts from Harper Garcia (250, 55 and 80, all Received). **Sofia Ali** and her household have no gifts. **Charlotte Williams** gave once (1,450) and all of it was refunded.

## T-GRD-01: Recalculate Every Giving Total

**Purpose:** Confirm the shipped giving totals are listed and Recalculate all fills them in.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Rollups**. On the **Rollups** row select **Open Rollup Builder**. | The Rollup Builder opens with one row per total, including **Household total giving**, **Account total giving**, **Contact total giving**, **Fund total raised** and **Appeal total raised**. Each shipped giving row shows mode **Both (recommended)** and is active. |
| 2 | Select **Recalculate All**. | A box reads "About N records, roughly M minutes." with **Cancel**, **Start Now** and **Run Tonight**. |
| 3 | Select **Start Now**. | "Recalculation started. This page updates as it finishes." When it finishes, **Rollups Last Completed** shows a time a moment ago. |
| 4 | Open **The Garcia Family**. Read the Giving section. | **Total Giving** 385.00, **Gift Count** 3, **Largest Gift** 250.00. **First Gift Date** and **Last Gift Date** are filled in. **Rollups Last Calculated** is recent. |
| 5 | Open **Harper Garcia**. | The same **Total Giving** 385.00 and **Gift Count** 3. |

**Cleanup:** None.

## T-GRD-02: A Gift Moves the Donor's Totals on Save

**Purpose:** Confirm donor totals update shortly after a gift is saved, with no recalculation.
**Prerequisites:** staff. T-GRD-01 done.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Sofia Ali** and her household. | **Total Giving** and **Gift Count** are empty or 0. |
| 2 | Enter a gift from **Sofia Ali** for 500. | **Gift Saved**. |
| 3 | Wait a few seconds and refresh Sofia Ali. | **Total Giving** 500.00, **Gift Count** 1, **Largest Gift** 500.00, **Giving This Year** 500.00, **First Gift Date** and **Last Gift Date** today. |
| 4 | Refresh her household. | The same values. **Rollups Last Calculated** is a moment ago. |
| 5 | Enter a second gift from Sofia Ali for 200. Refresh her household. | **Total Giving** 700.00, **Gift Count** 2, **Largest Gift** still 500.00. |

**Cleanup:** None. T-GRD-03 uses these gifts.

## T-GRD-03: Refunds, Pending Gifts and Soft Credits in the Totals

**Purpose:** Confirm a refund leaves the total but keeps the count, and pending gifts and soft credits stay out of total giving.
**Prerequisites:** staff. T-GRD-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the 200 gift from T-GRD-02, select **Refund or Write Off**, refund all 200 with reason `Rollup test`. | The recorded toast. |
| 2 | Refresh **Sofia Ali**. | **Total Giving** 500.00, **Gift Count** 2. **Last Gift Date** unchanged. |
| 3 | Open **Charlotte Williams**. | **Total Giving** 0.00, not blank. **Gift Count** 1. |
| 4 | Open **Kwame Ali**, a member of Sofia Ali's household. | With household soft credits on (they ship on), **Total Soft Credits** 500.00 (700 credited, 200 reversed by the refund). His **Total Giving** stays empty or 0: a soft credit is never added to giving. |
| 5 | On the **Gifts** tab select **New**: donor Sofia Ali, **Amount** 300, **Status** Pending, **Gift Date** today. **Save**. Refresh Sofia Ali. | **Total Giving** still 500.00 and **Gift Count** still 2: a pending gift is in no total. |

**Cleanup:** Edit the Pending gift and set **Status** to Cancelled.

## T-GRD-04: Fund and Appeal Totals

**Purpose:** Confirm a gift and its refund move a fund's and an appeal's totals.
**Prerequisites:** staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **General Fund** (Funds tab). Note **Total Raised**, **Total Raised This Year** and **Gift Count**. Open the **Annual Fund** appeal and note **Total Raised** and **Gift Count**. | Values noted. |
| 2 | Enter a gift from **Sofia Ali** for 1000 with **Appeal** Annual Fund and **Fund** General Fund. | **Gift Saved**. |
| 3 | Refresh General Fund. | **Total Raised** and **Total Raised This Year** are 1000 higher; **Gift Count** is 1 higher; **Last Gift Date** today. |
| 4 | Refresh Annual Fund. | **Total Raised** 1000 higher, **Gift Count** 1 higher. |
| 5 | Refund all 1000 of the gift. Refresh both records. | **Total Raised** is back to the value from step 1; **Gift Count** stays 1 higher. |

**Cleanup:** None.

## T-GRD-05: Giving Overview Dashboard

**Purpose:** Confirm the packaged dashboard opens with its six components and counts a new gift.
**Prerequisites:** admin.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | In the **BarnCRM Fundraising** app, open **Dashboards**, folder **BarnCRM Giving**, **Giving Overview**. | The dashboard shows **Gifts this month**, **This month, day by day**, **Giving by month**, **Giving by fund, this year**, **Giving by appeal, this year** and **Top donors, this year**, with numbers from the sample data. |
| 2 | Note **Gifts this month**. Enter a gift from **Sofia Ali** for 7777. Back on the dashboard select **Refresh**. | **Gifts this month** is 7777 higher. Today's bar in **This month, day by day** includes it. |
| 3 | Refund all 7777 of that gift. Refresh the dashboard. | **Gifts this month** is back to the step 2 starting value: the original and its refund cancel. |
| 4 | Open **Reports**, folder **BarnCRM Giving**, **Recent Gifts**. | The 7777 gift (Status Refunded) and its -7777 refund are both listed, newest first. |
| 5 | Open **Top Donors This Year** from the same folder. | Rows are households, largest first. |
| 6 | Open **In-kind Gifts This Year**. | Lists in-kind gifts from the sample data; none appear in the money charts. |

**Cleanup:** None.

## T-GRD-06: Dashboard and Reports as Staff and Read-Only

**Purpose:** Confirm the dashboard runs as the viewer and the shared folder is read only.
**Prerequisites:** staff, read-only, then admin and staff for steps 5 to 6.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Giving Overview**. | The six components show numbers. |
| 2 | As read-only, open **Giving Overview**. | The six components show numbers. |
| 3 | As read-only, open **Reports**, folder **BarnCRM Giving**, **Giving by Month**. | The report runs. The folder is shared read only, so the report cannot be saved over. |
| 4 | As staff, open the same report. | The report runs: Giving Staff, like Giving Read Only, carries Salesforce's **Run Reports**. |
| 5 | As admin, in Setup, remove **Giving Staff** from the staff user. | Saved. |
| 6 | As staff, open **Giving Overview**. | The components show an error or no data: without a Giving permission set the user cannot read gifts. |

**Cleanup:** Give the staff user **Giving Staff** again.

## T-GRD-07: Retention Reports

**Purpose:** Confirm the four retention reports run, count donors, and treat a refund correctly.
**Prerequisites:** admin. T-GRD-01 done. The reports and the donor totals both follow the org's fiscal year in Setup, shown read only as **Fiscal year start month** in **BarnCRM Settings**, **General**.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Reports**, folder **BarnCRM Giving**, open **LYBUNT Donors**. | Rows are donors (households, organizations), sorted by giving last year, largest first. |
| 2 | Open the first row's donor. | **Giving Last Year** above 0, **Giving This Year** 0 or empty, **Last Gift Date** in last fiscal year. |
| 3 | Open **SYBUNT Donors**. | Grouped by the fiscal year of the donor's last gift, newest group first. The first group holds the same donors as LYBUNT. |
| 4 | Open **New Versus Retained Donors**. | Outer groups by fiscal year of first gift. Earlier years split into **Gave last fiscal year** and **Did not give last fiscal year**. Sofia Ali's household (first gift today, T-GRD-02) is in the current year's group. |
| 5 | Open **First to Second Gift Conversion**. | Groups for the two completed fiscal years, each split into **Gave again** and **First gift only**. |
| 6 | Open **Margaret Young**'s household (sample: 65 about two years ago, then 1,475 refunded in full about three months before load). | If the 1,475 gift is dated in this fiscal year: **Giving This Year** 0, and the household is on neither LYBUNT nor SYBUNT, because the refunded gift still counts as a gift this year. |

**Cleanup:** None.

## T-GRD-08: Donor Segments

**Purpose:** Confirm a starter template saves a segment that counts, lists and exports for Mailchimp, Constant Contact and All Columns, leaving out who cannot be emailed. Setup detail: [Donor segments](../admin-guide/donor-segments.md).
**Prerequisites:** admin (holds BarnCRM Find and Export through BarnCRM Admin). T-GRD-01 done. Sample data loaded. A spreadsheet app to open CSV files.

| Step | Action | Expected result |
|---|---|---|
| 1 | In the **BarnCRM Fundraising** app, open **Donor Segments**. | The page shows **Start From a Template** with five templates and **Your Segments**. |
| 2 | Choose **Lapsed Donors**, **People**, keep the name **Lapsed Donors (People)**, select **Save as Segment**. | "Segment saved" shows; the segment is chosen and its count shows (sample data gives at least one). |
| 3 | Select **Show List**. | A table of people with Email, Last Gift Date and giving columns; each has **Giving Last Year** above 0 and **Giving This Year** 0 or empty. |
| 4 | Open one listed person, tick **Email Opt Out**, save, and return to **Donor Segments**. Choose the segment again. | The count is unchanged: opting out does not leave the segment. |
| 5 | With **Export Layout** **Mailchimp**, select **Export**. Open the file. | Header row: Email Address, First Name, Last Name, Tags. The opted-out person is not in it, nobody without an email is, and every row's Tags is **Lapsed Donors (People)**. |
| 6 | Choose **Constant Contact** and export. | Header row starts Email address, First name, Last name, Street address line 1, City. |
| 7 | Choose **All Columns** and export. | The segment's own columns; the opted-out person is in it. |
| 8 | Save **Major Gift Prospects** for **Organizations**. Open the **Export Layout** choice. | Only **All Columns** is offered, with a note that the email layouts are for people. |
| 9 | Choose **Lapsed Donors (People)** and select **Edit in Find**. | Find opens with the segment's query loaded. |
| 10 | As staff without **BarnCRM Find and Export**, open **Donor Segments**. | The page says the BarnCRM Find and Export permission set is needed and shows no segments. |

**Cleanup:** Untick **Email Opt Out** on the person from step 4. In Find, delete the two saved queries.
