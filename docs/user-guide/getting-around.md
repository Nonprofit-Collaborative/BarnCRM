# Getting around BarnCRM

BarnCRM lives inside Salesforce as a few apps. This page shows you how to open them, how
records open in tabs, what the home page shows you, and where to look when BarnCRM tells you
something (a tip, a "Learn more" link, or a notification under the bell).

Before you start: you need a BarnCRM role (Team Member, Coordinator, Fundraising Staff, Read
Only or Admin). If you cannot find the apps, ask your admin. See
[Access](../admin-guide/access.md).

## The apps

| App | What it is for | How it looks |
|---|---|---|
| **BarnCRM** | People, households, organizations, addresses, relationships and affiliations | A console: records open in tabs across the top |
| **Fundraising** | Gifts and everything around them (with the Giving module) | A standard app: each record replaces the page |
| **BarnCRM Volunteers** | Jobs, shifts and volunteer hours (with the Volunteers module) | A console, like BarnCRM |

The **BarnCRM** app's navigation menu holds **Home**, **Households**, **Contacts**,
**Organizations**, **Data Manager**, **Find**, **Org Optimizer**, **BarnCRM Settings**,
**Error Log**, **Addresses**, **Relationships**, **Affiliations** and **Household Members**.
You see only the tabs your access allows, so your menu may be shorter.

The **Fundraising** app has **Quick Gift Entry**, **Contacts**, **Households**,
**Organizations**, **Gifts**, **Commitments**, **Gift Batches**, **Funds**, **Appeals**,
**Tributes**, **Receipts**, **Stewardship Plans**, **Acknowledgment Queue**, **Receipt
Letters**, **Dashboards** and **Reports** (an admin also sees **Donor Level Ladder** and
**Stewardship Plan Setup**), plus **Quick Gift Entry** in the utility
bar at the bottom of the screen.

The **BarnCRM Volunteers** app has **Volunteer Jobs**, **Volunteer Shifts**, **Volunteer
Hours**, **Approve Hours**, **Volunteer Letter Templates**, **Skills**, **Volunteer
Requirements**, **Volunteer Settings**, **Dashboards** and **Reports**.

## To open an app

1. Click the App Launcher (the grid of dots at the top left).
2. Type `BarnCRM` (or `Fundraising`) and choose the app.
3. Optional: click the star next to the app name to open it by default.

You should see: the app's first tab. In **BarnCRM** that is **Home**.

## To work with records in console tabs

In the **BarnCRM** and **BarnCRM Volunteers** apps, records stay open side by side.

1. Open a household, organization or person. It opens in its own tab across the top.
2. Open something that belongs to it, such as an address on the household or a relationship
   on a person. It opens as a subtab inside that record's tab.
3. Click a tab to go back to it. Close a tab with its **x**, or right-click the tabs to close
   several at once.
4. To open a record in a new browser tab instead, hold Ctrl (Cmd on a Mac) while you click.

You should see: your open tabs still there when you come back later. Pages such as **Find**
and **BarnCRM Settings** name their tab for what is on screen, for example "Find: Contact".

On a phone, the Salesforce mobile app shows BarnCRM as an ordinary app without tabs.

## To use the home page

Open the **BarnCRM** app and choose **Home**. As a staff member you see:

- **What's new in BarnCRM**: what changed in the latest upgrade, with a headline and a few
  lines for each change. Read it, then click **Dismiss**. It comes back only when a later
  upgrade brings something new. Dismissing hides it for you, not for your colleagues.
- **Welcome to BarnCRM**: a short line saying "Your households, people and organizations are
  in the tabs above."
- **New household**: opens a new household with a placeholder name. The name is replaced
  automatically once you add a member. You see this button only if you can create households.
- **Quick links**: **Households**, **Organizations** and **BarnCRM Settings**, opened without
  going back to the App Launcher.
- **Files that arrive regularly**: shown only if you can read import mappings and a file is
  marked as arriving regularly, with the date it was last imported.

If someone has paused automation (for example during a large import), a banner under the
welcome says "BarnCRM automation is paused. Households and greetings are not being updated
until it resumes." It goes away by itself.

Admins also see the setup checklist, Health Check and a few status tiles. See
[The BarnCRM app](../admin-guide/barncrm-app.md) and [Health Check](../admin-guide/health-check.md).

## To read in-app tips

The first time you open some BarnCRM pages, Salesforce shows a short tip:

| Tab | Tip title |
|---|---|
| **BarnCRM Settings** | Getting around BarnCRM Settings (a panel headed "BarnCRM tips") |
| **Find** | Find exactly the records you need |

1. Read the tip.
2. Close it (or choose **Got it**).

You should see: the tip close for good. Each tip shows once per person, and Salesforce waits
a day between tips in the same app, so you may see the next one on a later visit.

## To open a "Learn more" link

On the **BarnCRM Settings** tab, many settings have a **Learn more** link beside them.

1. Click **Learn more** next to the setting.

You should see: the matching Admin Guide page open in a new browser tab. Everyone can read
the settings; only admins can change them.

## To check a job notification

When you start a long job yourself (an export to Files from **Find**, a bulk update, an
undo), BarnCRM tells you when it is done.

1. Look at the bell at the top of any Salesforce page. A number shows on it when something
   is new.
2. Click the bell, then the notification.

You should see: the job's own record or page, with what finished and how it went. Only the
person who started the job is told. Nightly jobs send nothing.

## To use the Data Manager tab

You see **Data Manager** if you have the **BarnCRM Find and Export**, **BarnCRM Bulk Update**
or **BarnCRM Bulk Delete** add-on. It shows a card for each tool you may use:

| Card | Opens |
|---|---|
| **Find and export records** | The **Find** tab |
| **Change many records** | **Find**: run a query, then press **Bulk update** |
| **Delete many records** | **Find**: run a query, then press **Bulk delete** |
| **Tidy and check your data** | The **Org Optimizer** tab |

1. Choose **Open** on the card you want.
2. Under **Data jobs**, use **Show** to filter to **All**, **Bulk updates** or **Bulk
   deletes**, and press **Refresh** to see the latest.

You should see: your recent jobs, newest first, each with its counts and an **Undo** while
it can still be undone. Import cards and Salesforce's own tools are for admins. See
[Data Manager](../admin-guide/data-manager.md).

## Common problems

- Problem: you cannot find the **BarnCRM** app. You have no BarnCRM role yet. Ask your admin.
- Problem: a tab such as **Find** or **Data Manager** is missing. Those tabs appear only once
  the feature is turned on and you have the matching add-on. Ask your admin.
- Problem: a record replaced the page instead of opening in a tab. You are in the
  **Fundraising** app, which is a standard app, or another app. Switch to **BarnCRM**.
- Problem: "What's new could not be updated. Refresh the page and try again. The problem is
  recorded in the Error Log." Refresh the page. If it keeps happening, tell your admin.
- Problem: "The home page could not load everything. The error is recorded in the Error
  Log." Refresh. If it keeps happening, tell your admin.
- Problem: no notification arrived. Check that you have not muted notifications in your own
  Salesforce settings. The job still finished; open its record to check.
- Problem: "An administrator needs to finish setting up BarnCRM." BarnCRM has not been set up
  yet. Ask your admin.

## Related

- [Finding people and records](find.md)
- [People and households](people-and-households.md)
- [Read-only access](read-only-access.md)
- Admin Guide: [The BarnCRM app](../admin-guide/barncrm-app.md),
  [What's new](../admin-guide/whats-new.md), [In-app tips](../admin-guide/in-app-guidance.md),
  [Job notifications](../admin-guide/job-notifications.md),
  [Data Manager](../admin-guide/data-manager.md)
