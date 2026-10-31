# Org Optimizer

**Package:** Core
**Decision:** ADR-0103 `0103-org-optimizer-and-data-manager-pages.md`

## 1. What It Does

**Org Optimizer** is one page that answers "what in my org needs attention?" It brings
together the checks that used to live in several places: the record checks (**Data
Quality**), field utilization, and Health Check. (Duplicate review has its own tab,
**Duplicate Matching**; see [Duplicates](duplicates.md).) Each one
is a section of the page, and nothing in a section runs until you open it, so the page itself
opens quickly however large your database is.

| Section | What it answers | Who sees it |
|---|---|---|
| **Overview** | A tile for each section, grouped under **Check Your Data** and **Check Your Setup**. A tile's badge gives its state at a glance (see below). Select a tile to open its section. | Everyone who can open the page |
| **Data Quality** | Which records need tidying up: people with no household, empty households, orphaned memberships and addresses, incomplete or failed primary addresses, people nobody can reach, deceased people who can still be emailed, and people not changed for years. Each check shows its count, a **Needs Attention** or **All Clear** badge, and **Open in Find**. See [Data Quality](data-hygiene.md). | Anyone with **Find and Export Records** |
| **Field Utilization** | How often each field of a kind of record is filled in, by record type, with saved counts for trends. See [Field utilization](field-utilization.md). | Administrators |
| **Data Dictionary** | Every field you can see on the kinds of record you choose, with type, length, required, unique, picklist values, help text and formula, and optionally a fill rate, as a table and a CSV download. See [Data Dictionary](data-dictionary.md). | Administrators |
| **AI-Readiness Export** | One zip for an AI tool you choose: a plain-language README, a schema.json of your kinds of record, fields and relationships, the data dictionary, data quality notes and, if you want, record files with sensitive fields left out or masked. BarnCRM calls no AI service. See [AI-Readiness Export](ai-readiness-export.md). | Administrators |
| **Health Check** | Whether BarnCRM is set up the way it should be, with a fix for some findings. Runs only when you press **Run Health Check**. See [Health Check](health-check.md). | Administrators |
| **Errors** | How many Error Log entries nobody has read, the most recent ones, **Mark Acknowledged**, and a link to the full Error Log. See [Error Log](error-log.md). | Administrators |
| **Storage and Limits** | How much of your org's data and file storage, daily API requests, background jobs and single emails are used, each as a bar with a **Near Limit** badge at 80% or more, and how many records BarnCRM keeps for imports, undo, errors and saved field counts, at about 2 KB a record. Read only. | Administrators |
| **Unused Setup** | Setup nobody seems to use: active users who have not logged in for 90 days, permission sets nobody is assigned, reports not run for 365 days, email templates never used, flows left inactive, scheduled jobs owned by inactive users, objects near their custom field limit, and record types no record uses. Each line gives a count, up to five names and **Open in Setup**. Read only: you decide what to remove, in Setup. See section 5. | Administrators |

"Administrators" means anyone with the **Manage BarnCRM Settings** permission, which the
**BarnCRM Admin** role carries. A section you cannot use is not shown.

Org Optimizer never changes a record by itself. Every change is a button you press in a
section, and each section's own page in this guide says what that button does.

**Tile badges on Overview.** Opening the page runs no check, so a badge shows only what is
already known:

| Tile | Badge |
|---|---|
| **Errors** | **{n} New** when Error Log entries are unread, **All Clear** when none are. Read as the page opens (one small count). |
| **Health Check** | The last full run: **{n} Errors**, **{n} Warnings**, **Passed**, or **Not Run Yet**. Updated when you come back to **Overview** after a run. |
| **Data Quality** | **{n} Need Attention** (checks that found records) or **All Clear**, once you have opened the section. |
| **Storage and Limits** | **Data Storage {n}%** once you have opened the section, in warning colors from 80%. |

**About This Tool**, under the page header, explains the page. It is open on your first visit
and closed after that; open it again whenever you like. Your choice is kept in your browser
only.

## 2. How to Turn It On

On a new install the **Org Optimizer and Health Check** feature is off until you turn it on:
choose **Turn On** in that row in **BarnCRM Settings**, **General** (or leave it ticked in
first-run setup); see [BarnCRM Settings](barncrm-settings.md). While it is off its tab is
hidden for everyone.

1. Open the **BarnCRM Admin** app and choose the **Org Optimizer** tab. **Data Manager** also opens it
   from its **Org Optimizer** card.
2. The **BarnCRM Admin** role and the **BarnCRM Find and Export** permission set each give
   the tab. Staff with Find and Export see **Overview** and **Data Quality**; administrators
   see every section.

Duplicates are no longer a section here: they are on the **Duplicate Matching** tab, which
the **Duplicate Matching** section of **BarnCRM Settings** opens.

## 3. A Five-Minute Walkthrough (as Maria)

Start from the sample data (see [Sample data](sample-data.md)).

1. Open the **Org Optimizer** tab. **Overview** shows a tile per section, each with one line.
   The **Health Check** tile says **Not Run Yet** on a new org.
2. Select the **Data Quality** tile. The ten checks count as the section opens. **People with
   No Household** says **0** on fresh sample data, with an **All Clear** badge.
3. Choose **Field Utilization**. In **Kind of Record** choose **Account**, and watch the table
   fill. Sort by **Filled** to see the fields nobody uses.
4. Choose **Health Check** and press **Run Health Check**. The findings appear, most serious
   first, each with what to do.
5. Choose **Storage and Limits**. **Data Storage (MB)** shows how much of your allowance is
   used, and **What BarnCRM Stores** lists the sample data's import and error records.
6. Choose **Unused Setup**. In a fresh org most lines say **0**; any with a count list the
   first five names, and **Open in Setup** takes you to the page where you can remove them.
7. Go back to **Data Quality** and press **Recount**: the counts are fresh each time you ask.
8. Choose **Overview**. The **Data Quality**, **Health Check** and **Storage and Limits** tiles
   now carry badges for what you just looked at.

## 4. Why Sections Load Only When Opened

Some checks read every person or every household, and Health Check reads your org's setup.
On a large database that takes seconds. Opening the page runs none of it: each section runs
the first time you open it, and Health Check runs only when you press its button. Switching
back to a section you already opened shows what it found, and each section has its own
**Recount**, **Count Again** or **Run** button for fresh numbers.

## 5. What Unused Setup Checks

Each check reads as you, so it sees what your own access lets you see in Setup. A check that
your access or your org does not allow says **Could not check** and the others still run.
Each count stops at 1,000 and then says **More than 1000**.

| Check | What counts | Left out |
|---|---|---|
| Active Users Who Have Not Logged In for 90 Days | Active, full Salesforce users whose last login is more than 90 days ago (or the days you set), or who never logged in. | Inactive users, and portal and integration user types. |
| Permission Sets Nobody Is Assigned | Your own permission sets with no user assigned. | Profile permission sets, permission sets from installed packages, and those inside a permission set group. |
| Reports Not Run for 365 Days | Reports nobody has run for a year (or the days you set), or ever. Only reports you can see are counted. | Reports from installed packages. |
| Email Templates Never Used | Templates that have never been sent and are more than 90 days old. | Templates from installed packages, and new ones. |
| Inactive Flows | Flows with no active version, last changed more than 90 days ago. | Flows from installed packages, and recent work. |
| Scheduled Jobs Owned by Inactive Users | Scheduled jobs still waiting to run whose owner is no longer active. These may stop working. | Finished and deleted jobs. |
| Objects Near Their Custom Field Limit | Account, Contact and BarnCRM's own objects with 80% or more of the custom fields your edition allows (100 on Professional, 500 on Enterprise and Developer, 800 on Unlimited and Performance, 500 when the edition is not known). Each example says how many of how many. | Fields from installed packages, which do not count against the limit, and every other object. |
| Record Types No Record Uses, or Inactive | Record types on Account, Contact and BarnCRM's own objects that are inactive, or that no record you can see uses. At most 50 active record types are looked at. | Record types on other objects. |

Two thresholds are settings, in the **Org Optimizer** section of **BarnCRM Settings**: **Days before a user
is unused** (90 unless you change it; 30 to 365) and **Days before a report is unused** (365;
90 to 1,095). The settings page refuses a value outside the range and saves nothing, and each
check's name shows the number in use. The 90 days that keep new email templates and flows out are fixed.
Nothing here is deleted or changed for you:
**Open in Setup** opens the Setup page where you can review and remove each item.

## 6. Common Mistakes

- **Looking for a separate data-quality tab.** The record checks are the **Data Quality**
  section of **Org Optimizer**.
- **Looking for duplicates here.** Duplicate review moved to its own tab, **Duplicate
  Matching**. The **Duplicate Matching** section of BarnCRM Settings opens it.
- **Seeing only two sections.** The others are for administrators. Ask whoever set up your
  org for the **BarnCRM Admin** role on the **Access** page.
- **Expecting Health Check to run as the page opens.** It runs when you press **Run Health
  Check**, here, or on **BarnCRM Settings > Health**.
- **Removing something Unused Setup lists without checking it.** A report nobody runs may be
  on a dashboard, and an inactive flow may be kept as a draft. Open it in Setup first.

## Field Reference

Org Optimizer adds no object and no field. Each section reads and writes what its own page in
this guide lists.
