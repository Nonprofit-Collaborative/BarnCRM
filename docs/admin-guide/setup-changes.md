# Setup Changes

**Package:** Core
**Feature:** C-56 (plan Section 6.0a release 0.12, decision D-156)

## What It Does

The **Setup Changes** section of **Org Optimizer** answers "who changed this, and when?" for
anything changed in Setup: a field label, a page layout, a user's profile, a permission set, a
flow. It reads the Salesforce **Setup Audit Trail**, the list Salesforce keeps of every Setup
change, and shows it in Salesforce's own words with filters and a CSV download.

Salesforce keeps that trail for only 180 days. BarnCRM copies it every night into its own
**Setup Change** records and keeps them for as long as you choose (two years unless you change
it), so a change made last year can still be found.

| Column | What it shows |
|---|---|
| **Changed At** | When the change was made, in your time zone |
| **Changed By** | The user who made it. Blank for some automatic Salesforce processes. |
| **Logged In As** | The username of the person who was logged in as that user, when someone was (for example a Salesforce support agent or another administrator) |
| **Section** | The Setup area, such as Customize Accounts or Manage Users |
| **What Changed** | Salesforce's own sentence for the change |

It is read only toward Setup: it never changes a setting, and nobody edits the copied rows.

## How to Turn It On

You need the BarnCRM Admin role (the BarnCRM Admin permission set, which carries the Manage
BarnCRM Settings permission). It shows you the **Setup Changes** section of the **Org
Optimizer** tab. Nobody else sees it.

The nightly copy is **BarnCRM Setup Changes Copy** at 1:30. Health Check lists it with the
other nightly jobs, and its **Schedule all nightly jobs** fix starts it. Pressing **Copy New
Changes Now** in the section also schedules it when it is not scheduled.

The copy runs as the user who scheduled it, and Salesforce shows the trail only to users with
the **View Setup and Configuration** permission (every System Administrator has it). If that
user cannot read the trail, the run copies nothing and writes one entry in the Error Log.

**Days to Keep Setup Changes** is in the **Org Optimizer** section of **BarnCRM Settings**: 730
(two years) unless you change it, from 180 to 3,650. Each night, after copying, the job deletes
kept changes older than that. Each kept change uses about 2 KB of data storage, which **Storage
and Limits** counts.

## A Five-Minute Walkthrough

1. Open the **Org Optimizer** tab and choose **Setup Changes**.
2. On a new install nothing is kept yet, and the section says so. Press **Copy New Changes
   Now**. The copy runs in the background and takes up to a few minutes. Press **Refresh**: the
   table fills with the last 180 days of changes, newest first, and the line above it reads,
   for example, "Kept: 1,240 changes, from 3 May 2026 to 31 October 2026."
3. In Setup, change a field's help text, then come back, press **Copy New Changes Now** and
   **Refresh**. Your change is at the top, with your name in **Changed By**.
4. Type the field's name in **Search** and press **Search**. Only changes that mention it are
   left.
5. Choose **Customize Accounts** (or wherever your field is) in **Section**, and set **From** to
   the first of this month. The list narrows again.
6. Press **Download CSV**. The file has the same columns, plus **Action** (Salesforce's code
   for the kind of change), for every match up to 5,000.

## Filters

- **From** and **To** are days in your time zone; both days are included. Leave either empty
  for no limit.
- **Section** offers the Setup areas among the kept changes.
- **Search** finds changes whose **What Changed**, **Section**, **Changed By**, **Logged In
  As** or **Action** contains the words you type, ignoring capitals. Search for a field's
  label or API name, an object, a user's name or a permission set.
- The table shows the newest 200 matches and says when there are more. Narrow the filters, or
  use **Download CSV**, which saves up to 5,000.
- One search looks at no more than 40,000 kept changes, newest first. When it stops there it
  says so: narrow the dates or the section.

## Download CSV

**Download CSV** saves every match up to 5,000, with the filters you set, as a UTF-8 file with
a byte-order mark, so Excel reads accents correctly. Text that starts with `=`, `+`, `-` or `@`
is saved with a leading apostrophe, so a spreadsheet never runs it as a formula. The file name
is `Setup_Changes-` and the date. For more, build a report on **Setup Changes** (reports are on
for the object).

## Common Mistakes

**Expecting changes from before BarnCRM was installed beyond 180 days.** The first copy takes
what Salesforce still holds, the last 180 days. Older changes were already gone.

**Expecting record changes.** The trail is about Setup, not data. A changed gift amount or
address is not here; use field history tracking for records.

**Expecting changes to appear at once.** A change shows after the next copy: the nightly run,
or **Copy New Changes Now**.

**Setting a very long retention in a busy org.** An org with many administrators or packages
can log thousands of changes a month. Check **Storage and Limits** before choosing ten years.

**Scheduling the copy as a user without View Setup and Configuration.** The run copies nothing
and logs an error. Schedule it as a System Administrator, through Health Check or **Copy New
Changes Now**.

## Field Reference

**Setup Change** (`Setup_Change__c`), one per copied trail row. Read only for the BarnCRM Admin
role; written and deleted only by the nightly copy.

| Field | API name | What it holds |
|---|---|---|
| Audit Trail ID | `Audit_Trail_Id__c` | The trail row's ID, so a change is never kept twice |
| Changed At | `Changed_At__c` | When the change was made |
| Changed By | `Changed_By__c` | The user's name |
| Logged In As | `Delegate_User__c` | The username of the person logged in as that user |
| Section | `Section__c` | The Setup area |
| Action | `Action__c` | Salesforce's code for the kind of change |
| What Changed | `Display__c` | Salesforce's sentence for the change |

## Related

- [Org Optimizer](org-optimizer.md)
- [Health Check](health-check.md)
- [Error Log](error-log.md)
