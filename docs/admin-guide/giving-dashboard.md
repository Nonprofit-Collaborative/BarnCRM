# Giving Dashboard

## What it does

The Giving dashboard answers the four questions a board asks, without anybody building a
report: how much came in this month, which funds it went to, which appeals produced it,
and who the largest donors are this year. It arrives with the Giving package as a set of
reports and one dashboard, already filtered to the current month and the current year, so
Tom can open it the day after installation and read real numbers.

The reports underneath it are ordinary Salesforce reports in a shared folder. Anyone can
open one, change a filter, and save a copy of their own without affecting what everyone
else sees.

## How to turn it on

1. Open the **Fundraising** app from the app launcher. Tap **Dashboards**, open the
   **Open Impact Giving** folder, and open **Giving Overview**.
2. Check who the dashboard reads as. It ships set to **The dashboard viewer**, so every
   person sees the gifts they are allowed to see and nothing needs changing. If your
   edition does not offer the dashboard viewer, or your org has used up its allowance of
   dashboards that read that way, open the dashboard, choose **Edit**, and in **View
   dashboard as** choose a person who can see all gifts, usually the person who installed
   the package.
3. Give people access. In Open Impact Settings, open **Access** and assign the
   **Fundraising Staff** role, and then, in Salesforce Setup, the Giving module's
   **Giving Staff** or **Giving Read Only** permission set. The role does not carry the
   Giving permission sets yet, and without one of them a person cannot read gifts, so the
   dashboard has nothing to show them. The report and dashboard folders themselves ship as
   public read only, so nothing has to be shared by hand.
4. Optional, and worth the ten seconds: with the dashboard open, choose **Subscribe** and
   have it emailed to yourself on the first of the month.

Nothing here requires Salesforce Setup.

## A five-minute walkthrough

Do this as Tom, from the sample data, after at least a few gifts exist.

1. Open the app launcher and choose **Fundraising**. Choose **Dashboards**, then the
   **Open Impact Giving** folder, then **Giving Overview**.
2. Read the top left number: **Gifts this month**. It is the total of every gift received
   since the first of this month. Under it, the daily chart shows which days produced it,
   which is how you tell one large gift from a steady week.
3. Read **Giving by month**. Twelve bars, this month at the right, the same twelve months
   again next month with no editing. This is the chart to take to a board meeting.
4. Read **Giving by fund, this year**. Each bar is one fund. A restricted fund with a
   large balance is money you may not spend on operations, so this chart is the one to
   check before a cash flow conversation.
5. Read **Giving by appeal, this year**. Each bar is one appeal, so you can see whether
   the spring mailing outperformed the gala.
6. Read **Top donors, this year**. Households, largest first, with the amount each has
   given since January. Click any row to open the report and see the gifts behind the
   number.
7. Choose **Refresh** in the top right corner. The date and time under the dashboard name
   tell you how current the numbers are; everything on this dashboard is calculated from
   the gifts themselves, so a refresh is all it ever needs.
8. Open **Recent gifts** from the Reports tab, in the same folder, when someone asks
   "did that gift arrive?". It lists every gift from the last thirty days, newest first,
   with no status filter at all: pending gifts, refunds, and the gifts they reverse are
   all on it, because the answer to "did that gift arrive?" sometimes is "it arrived and
   then it went back". The status column tells you which is which.

## Common mistakes

**The dashboard shows an error instead of numbers.** The message is "The running user for
this dashboard doesn't have permission to run reports." The dashboard reads as whoever is
looking at it, so this is a permission problem, not a dashboard problem: that person cannot
run reports or cannot read gifts. Assign them the Fundraising Staff or Read Only role in
Open Impact Settings under Access, and the Giving module's permission set in Setup. See
step 3 above.

**The numbers look too small.** The money charts count gifts with the status **Received**,
**Refunded**, or **Written off**. A gift left at Pending, for example a pledge payment that
has not arrived, or Cancelled because it never will, is deliberately excluded so that the totals match the bank. Open Recent
gifts and look at the status column if a gift you expected is missing.

The two reversed statuses are in that list on purpose. A refund is recorded as a second
gift for a negative amount, and the original keeps its own row with the status Refunded or
Written off, so the charts have to see both rows for them to cancel: a gift of $250 with
all of it returned adds $250 and subtracts $250 and nets to nothing. If the charts counted
only Received, they would keep the refund and drop the gift it reverses, and that donor
would show as minus $250. See the refunds page for how a refund is recorded.

**A donor or a fund shows a negative number.** The charts are filtered by date, and a
refund carries the date the money went back, not the date it arrived. A gift received in
December and refunded in January is a positive row in last year's window and a negative
row in this year's, so a year to date chart shows the refund on its own. That is correct
for a chart that answers "what came in this year", and it is why a negative bar is worth
reading rather than reporting as a defect. Open Recent gifts, or the report behind the
chart, and look for a gift with the status Refunded dated before the window.

**A fund total looks short.** A gift counts toward a fund only through its allocation, and
a gift split across several funds appears once per fund. Check the split on the gift itself
before concluding a fund is short. Every gift has an allocation, because a gift saved
without one is refused until a default fund exists, so a gift can never be missing from the
fund chart while appearing in the monthly total.

**A gift of goods is nowhere on the dashboard.** Every chart here is money, and an in-kind
gift carries no amount, so it appears in none of them and in no fund or appeal total. That
is deliberate: goods are reported separately from cash. Use the **In-kind Gifts This Year**
report in the same folder, or the In-kind value figure on the donor, and see
[In-kind gifts](in-kind-gifts.md).

**Someone changes the shared report.** The reports live in a shared folder and a person
with edit access can save over them. Ask staff to use **Save As** and keep their copies in
their own folder. If a packaged report is changed by mistake, an upgrade of the Giving
package does not restore it, so keep the edits in copies from the start.

**Top donors looks like it is missing your largest supporter.** Top donors groups by
household, which is how individual donors are counted whether people are contacts or
person accounts in your org. A gift from a company or a foundation belongs to no
household, so it is not on this chart. Use Giving by fund and Giving by appeal, or open
the report and group by donor account, for organization giving.
