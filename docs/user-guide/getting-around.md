# Getting Around BarnCRM

BarnCRM lives inside Salesforce as a few apps. This page shows you how to open them, how
records open in tabs, what the home page shows you, and where to look when BarnCRM tells you
something (a tip, a "Learn More" link, or a notification under the bell).

Before you start: you need a BarnCRM role (Team Member, Coordinator, Fundraising Staff, Read
Only or Admin). If you cannot find the apps, ask your admin. See
[Access](../admin-guide/access.md).

## The Apps

| App | What it is for | How it looks |
|---|---|---|
| **BarnCRM** | People, households and organizations, every day | Standard navigation: each record replaces the page |
| **BarnCRM Console** | The same work as **BarnCRM** | Console navigation: records open in tabs across the top |
| **BarnCRM Admin** | BarnCRM Settings and the data tools (admins only) | Standard navigation |
| **BarnCRM Admin Console** | The same as **BarnCRM Admin** (admins only) | Console navigation |
| **BarnCRM Fundraising** | Gifts and everything around them (with the Giving module) | A standard app: each record replaces the page |
| **BarnCRM Volunteers** | Jobs, shifts and volunteer hours (with the Volunteers module) | A console, like BarnCRM Console |

**Which one should I open?** For everyday work, open **BarnCRM** or **BarnCRM Console**: they
hold the same things and differ only in how records open, so pick the one you like and star it.
Your admin may have hidden one of them for everyone. Open **BarnCRM Fundraising** for gifts and **BarnCRM
Volunteers** for volunteers. **BarnCRM Admin** and **BarnCRM Admin Console** are for
administrators only.

**BarnCRM** has **Home**, **Contacts**, **Households**, **Organizations** and **Data
Manager**. **BarnCRM Console** has the same, plus **Addresses**, **Relationships**,
**Affiliations** and **Household Members** just before **Data Manager**. The admin apps
have **BarnCRM Settings**, **Data Manager**, **Org Optimizer**, **Duplicate Matching** and
**Error Log**. You see only the tabs your access allows, so your menu may be shorter. **Find**,
**Import** and **Super Transformer** are not in the navigation: open them from their cards on
the **Data Manager** tab. Every tab, including those Giving, Volunteers and Programs add,
has its own icon, so a tab is easy to spot in the menu. Administrators also find a **Data
Dictionary** section inside **Org Optimizer**, which lists every field (and, when asked, the
flows and Apex triggers that run on each kind of record) and downloads it as a CSV, an
**AI-Readiness Export** section, which downloads a zip that explains your data to an AI tool of
their choice, a **Setup Changes** section that shows who changed what in Setup, and when, and
an **Access Explorer** section that shows who can see or change what, and why, compares two
people side by side and lists who holds Modify All Data. Its **Field Use** section also
shows, for any picklist, how many records hold each value and when they were last changed, and
its **Unused Setup** section lists Apex and flows on old API versions in a closed part titled
**For Developers: Old Code and Flows**. Org Optimizer lists its sections on the left, like
BarnCRM Settings; on a phone, choose a section in the **Show** box at the top.
Each field row in the Data Dictionary, Field Use and the Record Inspector has a **Where
Used** action, which lists the BarnCRM setup (saved queries, import mappings, rollups and more)
that uses the field and walks an administrator through retiring it safely. If you import files, the
**Check Columns** step shows a few example values beside each column, so you can see each
column lands in the right field before anything loads; a column matched from a near spelling
(`Frist Name`) shows a **Best Guess, Check It** badge, and you accept it or choose another
field before you go on. An Excel workbook can load several of its sheets at once, each into
its own kind of record if the template loads several. The
Admin Guide's Importing page has the detail.

The **BarnCRM Fundraising** app opens on **Fundraising Home**, then has **Quick Gift Entry**,
**Contacts**, **Households**, **Organizations**, **Gifts**, **Commitments**, **Installments**
(each pledge payment), **Ask Pipeline**, **Asks**, **Gift Batches**, **Funds**, **Appeals**,
**Tributes**, **Receipts**, **Stewardship Plans**, **Acknowledgment Queue**, **Donor
Segments**, **Dashboards** and **Reports**, plus **Quick Gift Entry** in the utility bar at the
bottom of the screen.

**Fundraising Home** shows five figures, each a link to its list: gifts waiting for a thank
you, overdue pledge payments, your asks due this month, open gift batches and running
stewardship plans. **Enter a Gift** opens Quick Gift Entry. Under **Fundraising Setup** are the
setup pages that are no longer in the menu (**Donor Level Ladder**, **Stewardship Plan Setup**,
**Pledge Reminders**, **Receipt Letters**), each shown only to people who may use it; they are
also in the App Launcher. Below are two charts, **Giving by Month** and **Open Asks by Stage**;
click a chart to open its report.

The **BarnCRM Volunteers** app has **Volunteer Jobs**, **Volunteer Shifts**, **Volunteer
Hours**, **Approve Hours**, **Volunteer Letter Templates**, **Skills**, **Volunteer
Requirements**, **Dashboards** and **Reports**. The module's settings are the **Volunteers**
section of **BarnCRM Settings**.

Your admin may also have added the module pages you use most to the BarnCRM apps: **Quick Gift
Entry**, **Gifts**, **Commitments** and **Gift Batches**, or **Volunteer Shifts** and
**Volunteer Hours**, at the end of the navigation menu. The **Rollup Builder** is in the admin
apps; anyone else who may view it opens it by typing its name in the App Launcher.

## To Open an App

1. Click the App Launcher (the grid of dots at the top left).
2. Type `BarnCRM` (or `BarnCRM Fundraising`) and choose the app.
3. Optional: click the star next to the app name to open it by default.

You should see: the app's first tab. In **BarnCRM** and **BarnCRM Console** that is **Home**.

## To Work with Records in Console Tabs

In the **BarnCRM Console** and **BarnCRM Volunteers** apps, records stay open side by side.

1. Open a household, organization or person. It opens in its own tab across the top.
2. Open something that belongs to it, such as an address on the household or a relationship
   on a person. It opens as a subtab inside that record's tab.
3. Click a tab to go back to it. Close a tab with its **x**, or right-click the tabs to close
   several at once.
4. To open a record in a new browser tab instead, hold Ctrl (Cmd on a Mac) while you click.

You should see: your open tabs still there when you come back later. Pages such as **Find**
and **BarnCRM Settings** name their tab for what is on screen, for example "Find: Contact".

On a phone, the Salesforce mobile app shows BarnCRM Console as an ordinary app without tabs.

## To Use the Home Page

Open the **BarnCRM** app and choose **Home**. As a staff member you see:

- **What's New in BarnCRM**: what changed in the latest upgrade, with a headline and a few
  lines for each change. Read it, then click **Dismiss**. It comes back only when a later
  upgrade brings something new. Dismissing hides it for you, not for your colleagues.
- **Welcome to BarnCRM**: a short line saying "Find someone, add someone new, or pick up
  where you left off."
- **New Person**: opens the new person form. Fill in the name and address and save; BarnCRM
  makes the household for you. You see this button only if you can create contacts.
- **New Household**: creates a household with a placeholder name and opens it. The name is
  replaced automatically once you add a member. You see this button only if you can create
  and edit accounts.
- **Quick Links**: icon tiles for **People**, **Households**, **Organizations** and **Find**,
  plus **Quick Gift Entry** when Giving is installed and turned on, and **BarnCRM Settings**
  for administrators. Each has a one-line description and the same icon as its tab, and opens
  without going back to the App Launcher.
  **Households** opens the households list even on your first day, before the **Households**
  tab has been added for you.
- **Files That Arrive Regularly**: shown only if you can read import templates and a file is
  marked as arriving regularly, with the date it was last imported.

If someone has paused automation (for example during a large import), a warning under the
welcome says "BarnCRM automation is paused. Households and greetings are not being updated
until it resumes." It goes away by itself. Admins also see **Resume Automation** in the warning.

Admins also see the setup checklist, a Health Check summary and status tiles with a badge
each (for example **All Clear**, **Not Run Yet** or **Overdue**). See
[The BarnCRM Apps and Navigation](../admin-guide/barncrm-app.md) and [Health Check](../admin-guide/health-check.md).

## To Read In-App Tips

The first time you open some BarnCRM pages, Salesforce shows a short tip:

| Tab | Tip title |
|---|---|
| **BarnCRM Settings** | Getting around BarnCRM Settings (a panel headed "BarnCRM tips") |
| **Find** | Find exactly the records you need |

1. Read the tip.
2. Close it (or choose **Got it**).

You should see: the tip close for good. Each tip shows once per person, and Salesforce waits
a day between tips in the same app, so you may see the next one on a later visit.

## To Open a "Learn More" Link

On the **BarnCRM Settings** tab, many settings have a **Learn More** link beside them.

1. Click **Learn More** next to the setting.

You should see: the matching Admin Guide page open in a new browser tab. Everyone can read
the settings; only admins can change them. Links that open a new tab show a small new-window
icon and tell screen readers "(opens in a new tab)".

## To Check a Job Notification

When you start a long job yourself (an export to Files from **Find**, a Super Transformer run, an
undo), BarnCRM tells you when it is done.

1. Look at the bell at the top of any Salesforce page. A number shows on it when something
   is new.
2. Click the bell, then the notification.

You should see: the job's own record or page, with what finished and how it went. Only the
person who started the job is told. Nightly jobs send nothing.

## To Use the Data Manager Tab

You see **Data Manager** if you have the **BarnCRM Find and Export**, **BarnCRM Bulk Update**
or **BarnCRM Bulk Delete** add-on. It shows a tile (an icon, a name and one line) for each
tool you may use, in short groups:

| Group | Tile | Opens |
|---|---|---|
| **Find and Change** | **Find** | The **Find** tab: find records, then save or export them |
| **Find and Change** | **Super Transformer** | Change fields on many records at once, no file needed: choose the records and the changes, preview, then run (see [Changing many records at once](super-transform.md)) |
| **Check and Tidy** | **Org Optimizer** | The **Org Optimizer** tab |
| **Careful** (last) | **Delete Many Records** | **Find**, with a note: run a query, then choose **Change Records**, **Bulk Delete** (no file needed) |

Deleted records go to the Recycle Bin, not away for good: choosing **Delete Many Records**
first shows a box that says so. Choose **Continue** to go on to Find, or **Cancel** to stay on
Data Manager. You can undo a bulk delete from **Data Jobs** for up to 15 days.

1. Choose the tile you want: anywhere on it works. Not sure which? Type the task in **What Do
   You Want to Do?** above the tiles (for example "find people without email") and choose a
   result to open its tool.
2. Under **Data Jobs**, use **Show** to filter to **All**, **Super Transformer runs** or **Bulk
   deletes**, and press **Refresh** to see the latest.

You should see: your recent jobs, newest first, each with its counts and an **Undo** while
it can still be undone. **Bring Data In** (**Super Importer**), **Duplicate Matching**, **Import Templates** and
**Salesforce's Own Tools** are for admins. See
[Data Manager](../admin-guide/data-manager.md).

## Common Problems

- Problem: you cannot find the **BarnCRM** app. You have no BarnCRM role yet. Ask your admin.
- Problem: a tab such as **Find** or **Data Manager** is missing. Those tabs appear only once
  the feature is turned on and you have the matching add-on. Ask your admin.
- Problem: a record replaced the page instead of opening in a tab. You are in the
  **BarnCRM Fundraising** app, which is a standard app, or another app. Switch to **BarnCRM**.
- Problem: "What's new could not be updated. Refresh the page and try again. The problem is
  recorded in the Error Log." Refresh the page. If it keeps happening, tell your admin.
- Problem: "The home page could not load everything. The error is recorded in the Error
  Log." Refresh. If it keeps happening, tell your admin.
- Problem: "Something went wrong while BarnCRM was updating this record, so it was not saved."
  Only that record was refused; anything else you saved at the same time went ahead. Try
  again; if it repeats, tell your admin, who will find the reason in the Error Log.
- Problem: no notification arrived. Check that you have not muted notifications in your own
  Salesforce settings. The job still finished; open its record to check.
- Problem: "An administrator needs to finish setting up BarnCRM." BarnCRM has not been set up
  yet. Ask your admin.

## Related

- [Finding people and records](find.md)
- [People and households](people-and-households.md)
- [Read-only access](read-only-access.md)
- Admin Guide: [The BarnCRM Apps and Navigation](../admin-guide/barncrm-app.md),
  [What's new](../admin-guide/whats-new.md), [In-app tips](../admin-guide/in-app-guidance.md),
  [Job notifications](../admin-guide/job-notifications.md),
  [Data Manager](../admin-guide/data-manager.md)
