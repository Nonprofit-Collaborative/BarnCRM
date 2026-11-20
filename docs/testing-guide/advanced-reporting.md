# Advanced Reporting

Scripts for the optional BarnCRM Advanced Reporting module: the report builder, charts and
metric tiles, dashboards and their filters, saving and sharing as Files, export, the dashboard
templates and large reports. Setup detail: [Advanced Reporting](../admin-guide/advanced-reporting.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Advanced
Reporting deployed and the module turned on in BarnCRM Settings, **Modules**. For the template
scripts, deploy Fundraising and Volunteers too (Corporate Hub and Scholarships when available).
You need an admin (BarnCRM Admin), two users with the Team Member role (staff user A and staff
user B), a user with the Read Only role, a public group holding staff user B, and BarnCRM sample
data (or a few contacts, households and gifts). Set the Gift object to Private sharing for
T-AR-03 if it is not already.

## T-AR-01: Install, Access and the Tab

**Purpose:** confirm setup gives access, the tab and the settings row.
**Prerequisites:** admin, staff user A, read only user.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the BarnCRM app. | An Advanced Reporting tab, at the end of the app (in a package install, add it in App Manager first). |
| 2 | Open Setup, staff user A's permission set assignments. | Advanced Reporting Staff is assigned (within the hour, or after Finish Setup). |
| 3 | Open Setup, the read only user's assignments. | Advanced Reporting Read Only is assigned. |
| 4 | As admin, open BarnCRM Settings. | An **Advanced Reporting** row that opens the tab. |
| 5 | Open BarnCRM Settings, **Modules**. | Advanced Reporting is listed, marked Beta, in both editions. |

**Cleanup:** None.

## T-AR-02: Build a List Report Across Lookups and Related Records

**Purpose:** confirm columns through lookups, filters, date range, related conditions and related totals.
**Prerequisites:** staff user A; contacts with and without gifts this year.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff user A, open Advanced Reporting, select **New Report**, Report On **Gift**. | The builder shows Columns, Filters, Date Range, Related Records (if any), Groups and Totals, Display. |
| 2 | Add Column **Amount**, then pick **Fund >**, then **Fund Name**. | Columns list Amount and Fund: Fund Name. |
| 3 | Date Range: field Gift Date, range This Year. Select **Run**. | A table of this year's gifts with fund names; the first column links to the gift. |
| 4 | Start a new report on **Contact**; add Name and Email. Under Related Records select **Add Related Records Condition**, keep **Have None**, pick Gifts (Donor), and in its filter set Gift Date this year. Run. | Only contacts with no gift this year. |
| 5 | Under Related Totals select **Add Related Total**, pick Gifts (Donor), Total **Sum**, Field Amount. Run. | A Sum of Amount column per contact (0 or blank where none). |
| 6 | Date column: add Created Date, tick **Days Since**. Run. | The column shows whole days, not dates. |

**Cleanup:** None.

## T-AR-03: Totals, Charts and Metric, as the Viewer

**Purpose:** confirm grouping, buckets, chart types, Show Table, metric and that totals follow sharing.
**Prerequisites:** staff users A and B; gifts owned by each; Gift sharing Private.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff user A, new report on Gift. Add Grouping Gift Date. | Groups By month; Show As Bar Chart; a Record Count total appears. |
| 2 | Change the total to **Sum**, Field Amount. Run. | Bars per month with dollar values; hovering a bar shows its value. |
| 3 | Select **Show Table**. | A table of month and amount; **Show Chart** returns. |
| 4 | Add a second grouping Fund; Show As Column Chart, tick **Stacked**. Run. | Stacked columns with a legend of funds. |
| 5 | Remove both groupings; Show As Metric. Run. | One tile with the total. |
| 6 | Name it "My Gifts Total" and select **Save** (a report that was never saved has no **Save As**). Sign in as staff user B and build the same metric. | Each user's total covers only the gifts they can see. |
| 7 | Show As Donut with grouping Appeal, Top Groups 3. Run. | At most 3 slices, the total in the middle; with more than 3 appeals, the note "Showing the top 3 groups." |

**Cleanup:** None.

## T-AR-04: Save, Share With a Person and a Group, Delete

**Purpose:** confirm Files storage, Can View, Can Edit, owner-only sharing and delete.
**Prerequisites:** staff users A and B; the public group holding B; the read only user.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff user A, save a report "Shared Test". | "Saved Shared Test." The Reports tab lists it with owner You. |
| 2 | As staff user B, open Advanced Reporting. | "Shared Test" is not listed. |
| 3 | As A, open it, select **Share**, find staff user B, Add, keep **Can View**, Save. | "Sharing saved." |
| 4 | As B, open it. | Listed with owner A, access Can View; opening shows "shared with you to view"; no Save, Share or Delete; Save As is there. |
| 5 | As A, Share: remove B, add the public group with **Can Edit**. Save. As B, change the title and Save. | The group shows as "(Public Group)". B's save works. As A, Share still lists the group (B's save kept A's sharing). |
| 6 | As the read only user, open a report shared with them. | It runs; no Save or Save As. |
| 7 | As B, try Delete. | No Delete button. |
| 8 | As B (Can Edit), open the Files tab, find "Shared Test" (shared with me), and try **Share** or a share link. | Sharing is not offered or is refused: the file prevents others from sharing and unlinking. |
| 9 | As A, open "Shared Test" in two browser tabs. In tab 1, Share it with the read only user too. In tab 2 (opened before), change the title and Save. | The save works; the read only user still sees it (a save never changes sharing). |
| 10 | As A, open Share. | The intro says a Public Group shares with its direct members. |
| 11 | As A, Delete, confirm. | Gone for A and B. In Files (Setup or the Files tab as A), the file is deleted. |

**Cleanup:** None.

## T-AR-05: Export CSV

**Purpose:** confirm export of every row, of groups, and the Export Reports gate.
**Prerequisites:** staff user A with Export Reports; staff user B without it.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | As A, run a list report with a row limit of 10 on an object with more than 10 records. Select **Export CSV**. | A CSV with every matching record (not only 10), the column labels as the header. |
| 2 | Run a grouped report; Export CSV. | One row per group shown, totals as numbers. |
| 3 | As B (no Export Reports), run a report. | No Export CSV button. |
| 4 | As B, in the Developer Console call `ReportingQueryService.page` with a list report request and `forExport` true. | Refused: "Exporting needs the Export Reports permission in Salesforce." |
| 5 | As A, export a list report on an object with more than 100,000 matching records (or skip if none). | The CSV holds 100,000 rows and the note "Exported the first 100,000 rows, the most one export holds." |

**Cleanup:** None.

## T-AR-06: Dashboards and Filters

**Purpose:** confirm widgets, sizes, order, date and record filters, bindings through related records.
**Prerequisites:** staff user A; Fundraising with funds, gifts and allocations.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As A, select **New Dashboard**, name it "Test Dash". | Edit mode with Add Filter and Add Widget. |
| 2 | Add a saved report as a widget; add a **New Report Widget** (gifts by month), select Done. | Two widgets. |
| 3 | Add Filter: Date Range, label "Gift Date". On the gifts widget, bind it to Gift Date. | The widget's binding shows Gift Date. |
| 4 | Add Filter: Record, Records From Fund, label "Fund". Bind the gifts widget to a field that is a Fund lookup, or leave it unbound. | An unbound widget says "Not filtered by: Fund." when a fund is chosen. |
| 5 | Set widget widths (Third, Half, Full) and move one up. Done Editing, Save. | Layout follows; saved. |
| 6 | Choose Gift Date Last Year, then a fund. | Bound widgets update; unbound ones keep their data and show the note. |
| 7 | Type part of a fund name in **Find Fund**. | The list narrows to matching funds. |
| 8 | At phone width (or the Salesforce mobile app), open the dashboard. | Filters and widgets stack in one column; tables stack per row. |

**Cleanup:** Delete "Test Dash".

## T-AR-07: Dashboard Templates

**Purpose:** confirm templates show only for installed modules and filter correctly.
**Prerequisites:** Fundraising and Volunteers installed; Corporate Hub or Scholarships not installed (or test both ways).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the Dashboards tab. | Templates for Giving Overview and Volunteers; none for a module not installed. |
| 2 | Open Giving Overview. | Given This Month (metric), by day, by month for 12 months, allocations by fund, by appeal (donut), top donors (table of 10). |
| 3 | Choose a Fund. | Gift widgets narrow to gifts with an allocation to that fund; allocations by fund shows that fund only. |
| 4 | Open Volunteers. | Approved hours by job, lapsing volunteers, hours awaiting approval with Days Waiting, unfilled shifts in 14 days. |
| 5 | As a user without access to Volunteer Hours, open the Dashboards tab. | No Volunteers template. |
| 6 | Open Giving Overview, Edit, Save as "My Giving". | Saved as the user's own dashboard. |

**Cleanup:** Delete "My Giving".

## T-AR-08: Large Reports

**Purpose:** confirm the paged totals path, progress, Stop and the partial note.
**Prerequisites:** an org with more than 25,000 records of one object (for example Volunteer Hours or Gift from a data load); staff user A.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | As A, group the object by a picklist, Record Count, with no filter. Run. | "Totalling a large report: N records read." rises in steps of 5,000, with Stop. |
| 2 | Let it finish. | Totals match a Salesforce summary report of the same object. |
| 3 | Run again and select **Stop** part way. | Totals shown with "Stopped after N records. These totals are partial." |
| 4 | Add a date range that matches under 20,000 records. Run. | Totals appear at once, with no progress. |
| 5 | Put two such large widgets (no date range) on one dashboard and open it. | One widget shows progress at a time; the second starts when the first finishes. |
| 6 | In a multi-currency org only: group the large object and Sum a currency field, no filter. | Refused with "This report is too large to total ... more than one currency"; with a narrower date range it totals. |

**Cleanup:** None.

## T-AR-09: Refused Requests

**Purpose:** confirm the server refuses what the screen would never send.
**Prerequisites:** admin; Developer Console or Workbench (Execute Anonymous runs as the admin).
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Call `ReportingQueryService.run` with an object the user cannot read, a field name holding a quote or a space, a grouping on a long text field, and an unknown total function. | Each is refused with a message; nothing runs. |
| 2 | Call `ReportingQueryService.page` with an after-Id that is not an Id. | Refused. |
| 3 | Call `ReportingLibrary.share` on another person's report. | "Only its owner can share or delete this." |
| 4 | As the read only user, call `ReportingLibrary.share` or `ReportingLibrary.remove` on any report. | Refused: saving, sharing and deleting need Advanced Reporting Staff or Admin. |
| 5 | Call `ReportingQueryService.run` with a grouping on a field that cannot be grouped. | The message names the field, for example "That field (Description) cannot be used to group records." |

**Cleanup:** None.

## T-AR-10: Dates in the Person's Time Zone and Week

**Purpose:** confirm date ranges and buckets use the person's Salesforce time zone and locale.
**Prerequisites:** staff user A; records with a Created Date today.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Set A's time zone (Settings, Personal Information) to one far from the browser's, for example Pacific/Auckland when the computer is in America. Report on any object, Date Range Created Date Today. Run. | Records created during A's today in Auckland, not the computer's day. |
| 2 | Set A's locale to English (United Kingdom). Date Range This Week. | The week runs Monday to Sunday; with English (United States), Sunday to Saturday. |
| 3 | Date Range This Year, then Last 7 Days. Run each. | Results match a Salesforce list view filtered THIS_YEAR and LAST_N_DAYS:7. |

**Cleanup:** Put A's time zone and locale back.
