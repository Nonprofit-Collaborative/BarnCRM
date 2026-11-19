# Advanced Reporting

## What It Does

BarnCRM Advanced Reporting is an optional module, in either edition, for reports and dashboards
built inside BarnCRM (O-02, D-202, D-207). It is in beta.

- **Report builder**: pick an object, then columns (including fields of related records through
  up to two lookups, such as a gift's fund name), filters, a date range, conditions on related
  records (contacts that have, or have no, gifts this year), up to two groupings with up to four
  totals (count, sum, average, smallest, largest, count unique), up to three related totals per
  row (each household's gifts this year), sort and a row or top-group limit.
- **Views**: table, bar, column, line and donut charts, and a metric tile. A chart has Show Table
  beside it, which lists every value.
- **Dashboards**: up to 12 report widgets in a grid (third, half or full width) under up to four
  dashboard-wide filters. A date filter replaces each bound widget's date range; a record filter
  (a fund, a board, a job) narrows each bound widget, through related records where needed (a
  gift's fund through its allocations).
- **Save and share**: a saved report or dashboard is the owner's. Share it with people or public
  groups, each Can View or Can Edit.
- **Export CSV** of a list report (every row) or of a totals report (the groups shown).
- **Dashboard templates** for the modules installed: Board Governance (Corporate Hub), Giving
  Overview (Fundraising), Scholarships and Grants (Scholarships and Outbound Grants) and
  Volunteers. A template shows only when its module is installed and the person can read its
  records.

Everything runs as the person viewing it. Two people opening the same dashboard each see totals
of only the records their own access lets them read, and a field they cannot read is never
offered.

## Install and Turn On

Advanced Reporting depends on BarnCRM Core only. It reads module objects by name, so it works
with any mix of modules installed, and offers each module's objects once that module is in.
Install it like any module, then turn it on in BarnCRM Settings, **Modules** (it installs off).
The install, and Finish Setup on the Modules page, gives you and every BarnCRM Admin holder
Advanced Reporting Admin, and gives the module's Staff and Read Only sets to BarnCRM's other
roles (see Access below).

The **Advanced Reporting** tab joins the BarnCRM and BarnCRM Console apps before Error Log.
BarnCRM Settings has an **Advanced Reporting** row that opens it. There is nothing to set up.

## Access

| Permission set | Who gets it automatically | What it allows |
|---|---|---|
| Advanced Reporting Admin | BarnCRM Admin holders | Everything Staff has |
| Advanced Reporting Staff | Team Member and Fundraising Staff holders | The tab; build and run reports and dashboards; save, share and delete their own |
| Advanced Reporting Read Only | Read Only holders | The tab; run templates and anything shared with them; build and run reports without saving |

Saving is the **Save Advanced Reporting Reports** custom permission, in Staff and Admin. Export
CSV follows Salesforce's own **Export Reports** user permission: a person without it does not
see Export CSV. Reading records always follows the person's object, field and sharing access;
the permission sets grant no record access of their own.

## Where Reports and Dashboards Are Kept

A saved report or dashboard is a Salesforce File owned by the person who saved it: a file with
the extension `.barnreport` or `.barndash` holding the definition as JSON (canonical model
section 29AR). No custom object is added. This means:

- People need access to Salesforce Files (on in every org by default).
- Sharing is a file share: Can View is a Viewer share, Can Edit a Collaborator share. Only the
  owner shares or deletes. A Can Edit person's save keeps the owner's sharing as it was.
- A public group is shared with its active members as they are when the owner saves or shares;
  someone who joins the group later sees it after the owner saves or shares again. Up to 500
  people per report or dashboard.
- Each save is a new file version, so Files keeps the history.
- They count toward file storage like any other file, at a few kilobytes each.

Deleting a saved report or dashboard deletes the file for everyone it is shared with.

## Large Data Volumes

- A list report reads up to 2,000 rows on screen; Export CSV reads every row in pages of 5,000.
- A totals report is counted first. When the matching records fit Salesforce's aggregate query
  limits (about 20,000, or half the rows left in the request), one aggregate query totals them.
  Otherwise the browser reads the records in pages of 5,000 in Id order and totals them itself,
  showing progress and a Stop button, up to 1,000,000 records; a note says when totals are
  partial. Add a filter or a date range to keep large reports fast.
- Grouping by a date uses the person's time zone for date and time fields.
- Up to 2,000 groups are read; a note says when there are more.

## Dashboard Templates

Templates are shipped as JSON (static resource `BarnReporting_Templates`). Opening one runs it;
Edit changes it and Save keeps your own copy. Template contents:

| Template | Shown when | Filters | Widgets |
|---|---|---|---|
| Board Governance | Corporate Hub is installed | Board | Current members by board; attendance this year by member (stacked by attendance); terms ending in the next 90 days; open disclosures |
| Giving Overview | Fundraising is installed | Gift date, Fund, Appeal | Given this month; giving by day this month; giving by month for 12 months; allocations by fund; giving by appeal (donut); top donors this year |
| Scholarships and Grants | Scholarships and Outbound Grants is installed | Cycle, Program | Applications by cycle and status; awards by program (awarded and paid); ranked applications; payments due in 30 days; requirements due |
| Volunteers | Volunteers is installed | Date worked, Job | Approved hours by job this year; lapsing volunteers (last served 182 to 365 days ago); hours awaiting approval with days waiting; unfilled shifts in the next 14 days |

Giving totals count gifts with status Received, Refunded or Written off, as the Fundraising
dashboard does.

## How It Relates to Other Tools

- **Salesforce reports and dashboards** stay available; BarnCRM's shipped reports and dashboards
  are unchanged. Advanced Reporting adds what they do poorly: fields across lookups and related
  records in one report, totals of related records per row, and dashboard filters that reach
  every widget, with each person seeing only their own records.
- **Grid** (item 14) is for working with records in a spreadsheet view and editing them;
  Advanced Reporting reads only.
- **Analytics** (item 10) is a separate, later module for trends and forecasting; it can reuse
  these definitions.
- **Find** keeps its saved queries; Advanced Reporting uses the same filter builder and query
  checks.

## Troubleshooting

| What you see | Why | What to do |
|---|---|---|
| No Advanced Reporting tab | The module is off, or the person has none of its permission sets | Turn it on in Modules; run Finish Setup |
| An object is missing from Report On | The person cannot read it, or it is a setting or system object | Give object access through the module's permission sets |
| A template is missing | Its module is not installed, or the person cannot read its records | Install the module or give access |
| Save is missing | The person has Read Only | Give Advanced Reporting Staff |
| Export CSV is missing | The person lacks Salesforce's Export Reports permission | Add it in their profile or a permission set |
| "Totals cover the first 1,000,000 records only" | The report matches more records than the browser totals | Add a filter or a date range |
| A shared report is missing for a group member | They joined the group after it was shared | The owner opens it and selects Share, then Save |

Errors are written to the Error Log with the request that failed.
