# Advanced Reporting

Advanced Reporting lets you build reports and dashboards across your BarnCRM records without
leaving BarnCRM: lists, totals, charts and metric tiles, dashboards with filters that apply to
every widget, and templates for the modules your organization uses.

**Before you start:** open the **Advanced Reporting** tab in the BarnCRM app. If it is missing,
ask your admin (see [Advanced Reporting](../admin-guide/advanced-reporting.md)).

**You see what you are allowed to see.** Every report and dashboard runs with your own access.
Two people opening the same dashboard each see totals of only the records they may read.

## Open a Dashboard Template

1. On the **Dashboards** tab, under **Dashboard Templates**, select a template (for example
   Giving Overview).
2. Use the filters at the top: a date range, or a record such as a fund. Type part of a name in
   **Find** to narrow a long list. Every widget the filter applies to updates; a widget the filter
   does not apply to says so under its title.
3. Select **Refresh** to run every widget again.

To keep your own version, select **Edit**, change what you like, enter a **Dashboard Name** and
select **Save**.

## Build a Report

1. Select **New Report**.
2. **Report On**: the kind of record, such as Contact or Gift.
3. **Columns**: pick the fields to list. A lookup followed by **>** (for example **Fund >**)
   opens the related record's fields, so you can list a gift's fund name. Date columns can show
   **Days Since** instead of the date.
4. **Filters**: the same filter builder as Find.
5. **Date Range**: pick a date field and a range, such as This Year, Last 12 Months or Between
   Days Ago (for example between 365 and 182 days ago).
6. **Related Records**: keep only records that **Have** or **Have None** of a kind of related
   record, optionally matching conditions. Example: contacts with no gift this year.
7. **Related Totals**: add a column that counts or totals each record's related records, such as
   each household's gifts.
8. Select **Run**. The result shows beside the builder (below it on a phone).

### Totals and Charts

Under **Groups and Totals**, select **Add Total** to count or sum instead of listing. Add up to
two groupings (**Group By**, **Then By**) to split the totals, such as by month and fund. Dates
group by day, week, month, quarter or year.

Under **Display**, **Show As** picks Table, Bar Chart, Column Chart, Line Chart, Donut Chart or
Metric (one total, no grouping). With two groupings a bar or column chart can be **Stacked**.
**Top Groups** keeps the largest groups; **Sort By** changes the order.

On a chart, **Show Table** lists every value; the chart is one image to a screen reader, and the
table carries the numbers.

### Large Reports

A report that totals a very large number of records reads them in pages and shows how many it
has read; select **Stop** to see totals so far (marked partial). A filter or a date range makes it
faster.

## Save, Share and Export

- **Save** keeps the report or dashboard as yours. **Save As** keeps a copy under a new name.
- **Share** (owner only): find people or public groups and choose **Can View** or **Can Edit**.
  People you share with see the records their own access allows, not yours. A public group is
  shared with its members as they are now; share again to include people who join later.
- **Delete** (owner only) deletes it for everyone it is shared with.
- **Export CSV** downloads a list report's rows (every row, not only those on screen) or a totals
  report's groups. It needs Salesforce's Export Reports permission.

Reports and dashboards shared with you show in the lists with their owner and your access. If
you can only view one, use **Save As** to make your own copy.

## Build a Dashboard

1. Select **New Dashboard**. Enter a **Dashboard Name**.
2. Under **Add Widget**, pick a **Saved Report** and select **Add Report**, or select **New
   Report Widget** to build one here and select **Done**.
3. Under **Add Filter**, add a **Date Range** or a **Record** filter (choose **Records From**, for
   example Fund), with a label.
4. On each widget, under **Dashboard Filters on This Widget**, pick the field each filter
   applies to (for example Gift Date for the date filter, Fund for the fund filter). Set the
   widget's **Width** and order with the arrows.
5. Select **Done Editing**, then **Save**.

Up to 12 widgets and four filters per dashboard.

## Why Something Is Missing

| What you see | Why |
|---|---|
| An object or field is not offered | Your access does not include it |
| A template is missing | Its module is not installed, or you cannot read its records |
| No Save button | Your role can run reports and open shared ones, but not save them |
| No Export CSV | You do not have Salesforce's Export Reports permission |
| "There are more groups than shown" | More than 2,000 groups matched; add a filter |
