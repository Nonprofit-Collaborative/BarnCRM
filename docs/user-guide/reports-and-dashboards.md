# Reports and Dashboards

BarnCRM ships ready-made reports and dashboards for giving and for volunteering, so you can
answer common questions without building anything. This page lists what each one shows and how
to open, filter and save your own copy. It also explains the totals you see on a donor's or a
volunteer's record.

**Before you start:** giving reports are in the **BarnCRM Fundraising** app and need a Giving permission
set (it comes with the Fundraising Staff role, or with Read Only plus **Giving Read Only**).
Volunteer reports are in the **BarnCRM Volunteers** app and need a Volunteers permission set,
which comes with your BarnCRM role. If a report or dashboard is empty or refuses to open, ask
your admin (see [Giving dashboard](../admin-guide/giving-dashboard.md) and
[Volunteers](../admin-guide/volunteers.md#the-volunteers-dashboard-and-reports)).

**You see what you are allowed to see.** Both dashboards run as the person viewing them. Two
people can open the same dashboard and see different numbers if their access differs. For
example, volunteer hours are private: a Team Member's charts count only the hours they can open,
while a coordinator's count everyone's.

## What Ships

**Giving** (folder **BarnCRM Giving**, dashboard **Giving Overview**):

| Report | What it shows |
|---|---|
| Gifts This Month by Day | Every gift received since the first of this month, totalled by day. |
| Giving by Month | Total received in each of the last twelve months. |
| Giving by Fund This Year | What each fund has received this year, from the gift allocations. |
| Giving by Appeal This Year | What each appeal has raised this year. |
| Top Donors This Year | Households by what they have given this year. |
| Recent Gifts | Every gift from the last thirty days, any status, for "did that gift arrive?". |
| In-kind Gifts This Year | Goods and services received this year, with their fair market value. |
| LYBUNT Donors | Gave last fiscal year, not this one. |
| SYBUNT Donors | Gave in some earlier fiscal year, not this one. |
| New Versus Retained Donors | This fiscal year's donors, split into new, retained and reactivated. |
| First to Second Gift Conversion | Donors whose first gift fell in one of the last two completed fiscal years, and whether they gave again. |

The money reports count gifts with the status Received, Refunded or Written off. Pending and
Cancelled gifts are left out. The last four are retention reports, which count donors, not
gifts. Their exact definitions are on [Retention reports](../admin-guide/retention-reports.md).

The **Giving Overview** dashboard shows **Gifts this month**, **This month, day by day**,
**Giving by month**, **Giving by fund, this year**, **Giving by appeal, this year** and **Top
donors, this year**. The retention reports are not on it: open them from the folder.

**Volunteers** (folder **BarnCRM Volunteers**, dashboard **Volunteers**):

| Report | What it shows |
|---|---|
| Approved Hours This Year by Job | Approved hours this year, by job. Hours with no job are grouped as blank. |
| Hours Awaiting Approval | Hours entered and not yet approved or rejected, oldest first, with the days each has waited. |
| Unfilled Shifts Next 14 Days | Open shifts starting in the next 14 days that still need volunteers, soonest first. |
| Lapsing Volunteers | Volunteers whose last approved hours were between six and twelve months ago, longest gap first. |

The **Volunteers** dashboard shows one chart for each: **Approved hours this year, by job**,
**Hours awaiting approval**, **Unfilled shifts, next 14 days** and **Lapsing volunteers**.

## To Open a Dashboard

1. Open the **BarnCRM Fundraising** app (giving) or the **BarnCRM Volunteers** app (volunteering).
2. Click the **Dashboards** tab.
3. Open the **BarnCRM Giving** or **BarnCRM Volunteers** folder.
4. Click **Giving Overview** or **Volunteers**.
5. Click **Refresh** at the top right to bring the numbers up to date.

You should see: the charts, with the date and time they were last refreshed under the dashboard
name. Click a chart to open the report behind it.

To have the dashboard emailed to you on a schedule, click **Subscribe** on the open dashboard.

## To Open a Report

1. In the same app, click the **Reports** tab.
2. Open the **BarnCRM Giving** or **BarnCRM Volunteers** folder (under **All Folders**).
3. Click the report name.

You should see: the report, already filtered. Click a record name in a row to open it.

## To Change a Filter and Save Your Own Copy

The shipped reports and dashboards belong to BarnCRM. Never edit them: everyone shares them, and
an upgrade can replace them. Save a copy instead.

1. Open the report and click **Edit**.
2. In the **Filters** pane, change what you need (for example the date range, or add a filter on
   a fund or job).
3. Open the menu next to **Save** and choose **Save As**.
4. Give it a new **Report Name**, choose a folder of your own (for example **Private Reports**),
   and click **Save**.

You should see: your copy open, with your filters. The shipped report is unchanged for everyone
else.

To try a filter without saving, change it from the **Filters** pane while viewing the report
and do not save.

## To Read the Totals on a Record

**Giving totals.** In the **BarnCRM Fundraising** app, a person, household or organization has a
**Giving** section: **Total Giving**, **Gift Count**, **First Gift Date**, **Last Gift Date**,
**Largest Gift**, **Giving This Year**, **Giving Last Year**, **Giving Two Years Ago**,
**Pledge Balance**, **Total Soft Credits**, **In-kind Value** and others, plus **Donor Level**.
**Rollups Last Calculated** shows when these were last worked out. See [Gifts](gifts.md).

**Volunteer totals.** In the **BarnCRM Volunteers** app, a person's **Volunteer Profile**
section shows **Volunteer Hours Total**, **Volunteer Hours This Year**, **Volunteer Hours Last
Year**, **First Volunteer Date** and **Last Volunteer Date**. They count approved hours only. A
volunteer job and a shift show **Total Hours** and **Totals Last Updated**. See
[Volunteer hours](volunteer-hours.md#to-see-a-persons-volunteering).

These totals are read only for everyone. They update when a gift or hours entry is saved, and
again every night. "This year" and "last year" on a record follow your organization's fiscal
year.

## To See How a Total Is Worked Out

If your admin shows you **Explain These Totals** on the record page (it starts out shown to
admins only):

1. Open the person, household or organization and find the **Explain These Totals** card.
2. Each total is listed with its value, for example "Total Giving: 4,250", and one sentence
   saying what it counts.
3. Read the line under it, for example "12 of the 15 records read count; 3 are left out.", and
   when it was last calculated.
4. Under **Records Read for This Record**, up to ten of those records are linked, each marked
   **Counted** or with why it is left out, for example "Left out: does not meet condition 1"
   (a gift whose status is not one that counts). Click one to open it.
5. Click **Refresh** after a change to read the totals again.

The counts and the list include only the records you can open; the total includes them all.
You need the **Rollup Builder User** permission set to see the card; ask your admin. If a
total still looks wrong, tell your admin: they also see what it would be if recalculated now.

## Common Problems

- Problem: the dashboard shows "The running user for this dashboard doesn't have permission to
  run reports." Why and what to do: you lack report or gift access. Ask your admin (see
  [Giving dashboard](../admin-guide/giving-dashboard.md)).
- Problem: a giving total looks too small. Why and what to do: Pending and Cancelled gifts are
  left out on purpose. Open **Recent Gifts** and check the status column.
- Problem: a report's "this year" number differs from **Giving This Year** or **Volunteer Hours
  This Year** on a record. Why and what to do: the shipped "This Year" reports use the calendar
  year, while the record totals use your fiscal year. If your fiscal year does not start in
  January, the two differ. Save a copy with a fiscal year filter if you need them to match.
- Problem: the volunteer charts show fewer hours than you expected. Why and what to do: only
  **Approved** hours count, and you see only the hours your access allows. Approve waiting hours
  first (see [Volunteer hours](volunteer-hours.md#to-approve-hours)).
- Problem: a donor or volunteer total looks out of date. Why and what to do: check **Rollups
  Last Calculated** (or **Totals Last Updated** on a job or shift). If it is days old, tell your
  admin (see [Rollups](../admin-guide/rollups.md)).
- Problem: an organization is missing from **Top donors, this year**. Why and what to do:
  organizations give without a household, so they are not on that list.
- Problem: **Lapsing Volunteers** is empty although you have people who stopped coming. Why and
  what to do: it reads **Last Volunteer Date** on contacts. If your people are person accounts,
  ask your admin for an account-based version.
- Problem: you cannot save changes to a shipped report. Why and what to do: the shipped folders
  are read only. Use **Save As** to make your own copy.

## Related

- [Gifts](gifts.md)
- [Commitments](commitments.md)
- [Volunteer hours](volunteer-hours.md)
- [Volunteer jobs, shifts and sign-ups](volunteer-shifts.md)
- [Find](find.md): lists and exports of people
- Admin Guide: [Giving dashboard](../admin-guide/giving-dashboard.md),
  [Retention reports](../admin-guide/retention-reports.md),
  [A donor's giving on their record](../admin-guide/donor-records.md),
  [Rollups](../admin-guide/rollups.md),
  [Volunteers](../admin-guide/volunteers.md#the-volunteers-dashboard-and-reports)
