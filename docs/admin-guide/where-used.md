# Where Used and Retire a Field

**Package:** Core (the Rollup Builder and Giving modules add their own records when installed)
**Feature:** C-59 (plan Section 6.0a release 0.16, decision D-156; ADR-0159)

## What It Does

**Where Used** answers "what in BarnCRM uses this field?" before you change or delete it. Pick a
field, and BarnCRM lists every BarnCRM setup record that names it, grouped by kind:

| Group | What is checked |
|---|---|
| **Saved Find Queries** | Columns, filter, sort, related-records conditions, related record columns and summary of every saved query in Find. Donor segments (Giving) are saved queries, so they are listed here. |
| **Super Transform Step Lists** | The filter and every change (the field written, a field copied from, and the fields named inside steps) |
| **Import Mappings** | Every column and default value that loads the field, the matching fields (Email, External ID and the like), the object a one-object mapping loads, and the link field of related records |
| **Merge Rules** | The field a rule decides, including a whole address rule for any of its parts |
| **Matching Sources** | The value, parent and postal code fields of each duplicate matching source |
| **BarnCRM Settings** | Every setting whose value names a field: Address Card Fields, and the Household Name, Formal Greeting and Informal Greeting patterns (their {FirstName}, {LastName} and {Salutation} blanks; a blank pattern counts as its default) |
| **Rollups** (Rollup Builder module) | The counted field, sort field, fiscal date field, both filters, the relationship path and the result field |
| **BarnCRM Settings** (Giving module) | The Donor Level source total, on both people and organizations |
| **Import Mappings** (Giving module) | Columns and default values that load gifts, allocations, soft credits and tributes |

For each record it shows its name, where in it the field is named (for example "Filter" or
"Column "Donor Email""), what stops working if the field is deleted, and a link to the BarnCRM
page that edits it.

You can also ask about a whole kind of record (an object): BarnCRM then lists every setup record
that works on that object or reaches it through a lookup.

**What it does not check.** BarnCRM reads only its own setup. Salesforce's own uses of a field
(flows, Apex code, page layouts, reports, list views, validation rules, formula fields, email
templates) are not checked, because that needs the Salesforce Tooling API, which BarnCRM does not
use. The page says so every time and links the field's Setup page, where Salesforce's **Where is
this used?** button covers those.

A private saved query that someone else owns is counted and named by its owner only ("A private
saved query owned by Sam Lee"), never by its name. Ask the owner to change it, or to share it.

**Retire a Field** is the checklist at the end of the list. BarnCRM never deletes a field itself;
the checklist walks you to a safe deletion in Setup:

1. Edit or remove each BarnCRM record listed (each has a link).
2. Check Salesforce's own uses: open the field in Setup and click **Where is this used?**
3. Back up the values: open Find on the object, add the field as a column and export.
4. Hide the field first: take it off page layouts and remove field access for a few weeks, so you
   learn whether anyone misses it.
5. Delete the field in Setup (a link opens the field's page). Standard fields and fields a managed
   package installed cannot be deleted; the checklist tells you to hide them instead.

The ticks are only for you while the window is open; nothing is saved.

## How to Turn It On

You need the BarnCRM Admin role (the BarnCRM Admin permission set, which carries the Manage
BarnCRM Settings permission). Nothing to schedule, and no setting to change. It is on wherever
these field lists are:

- **Org Optimizer, Data Dictionary:** each field row's action menu has **Where Used**.
- **Org Optimizer, Field Utilization:** each field row's action menu has **Where Used**, handy for a
  field that is almost never filled in.
- **Record Inspector:** each field row has a **Where Used** button.

## How to Use It

1. Open one of the three places above and find the field.
2. Choose **Where Used** on its row. A window opens and lists the BarnCRM records that use it, or
   says that none do.
3. Click a record's name to open the page that edits it, in a new tab.
4. To see everything that uses the whole kind of record, click **Show Uses of the Whole Object**.
   Click **Show Uses of This Field** to go back.
5. To retire the field, work down the **Retire a Field** checklist, ticking each step as you go.
6. Click **Close** when you are done.

## What Can Go Wrong

- **The window says you need the Manage BarnCRM Settings permission.** Ask a BarnCRM Admin to
  assign you the BarnCRM Admin permission set.
- **The window says some module records could not be checked.** A module's check failed; the
  failure is in the Error Log. The list shows everything else; check that module's records by hand
  before deleting the field.
- **A field shows no uses, yet something broke after you deleted it.** Something outside BarnCRM
  used it: a flow, Apex, a report or a layout. Always do step 2 of the checklist. To undo a
  deletion, Salesforce keeps a deleted custom field for 15 days under **Deleted Fields** on the
  object's Fields and Relationships page in Setup.
- **The list is long for a large org.** BarnCRM reads up to 2,000 records of each kind per check.
