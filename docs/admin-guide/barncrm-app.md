# The BarnCRM Apps and Navigation

## What It Does

BarnCRM Core comes as four apps: two for everyday work and two for administrators, each in
standard navigation and console navigation.

| App | For | Navigation | Tabs |
|---|---|---|---|
| **BarnCRM** | Everyone with a BarnCRM role | Standard: each record opens in place of the page | Home, Contacts, Households, Organizations, Data Manager |
| **BarnCRM Console** | Everyone with a BarnCRM role | Console: records stay open side by side in tabs | Home, Contacts, Households, Organizations, Addresses, Relationships, Affiliations, Household Members, Data Manager |
| **BarnCRM Admin** | The BarnCRM Admin role only | Standard | BarnCRM Settings, Data Manager, Org Optimizer, Duplicate Matching, Error Log |
| **BarnCRM Admin Console** | The BarnCRM Admin role only | Console | The same as BarnCRM Admin |

The everyday apps give you one home page that tells you what to do next, a setup checklist
that remembers how far you got, and the places you go most: your households, your people and
your organizations. The admin apps hold every BarnCRM tool and setting in one place. Each
tab shows only to the people whose access allows it, so a menu can be shorter than the list.
**Import**, **Find** and **Bulk Update** are not in any app's navigation: open them from the
tiles on the **Data Manager** tab. **Error Log** is always the last tab of an app that has it,
after any pages a module adds. In the everyday apps, **Data Manager** is the last Core tab and
a module's pages follow it.

Each page's icon matches what it does, and the page header and its console tab show the same
one: a gear for **BarnCRM Settings**, building blocks for **Data Manager**, a stethoscope for
**Org Optimizer**, scales for **Duplicate Matching**, a bell for **Error Log**, a telescope for
**Find** and a form for **Import**. **Households** show people, **Organizations** a building,
**Addresses** a map. On Data Manager, Org Optimizer, Duplicate Matching, Find and Import the
page name appears once, in the page header, and the tool below it starts with what it is for.

If you have ever installed something in Salesforce and then wondered where to start, this
is the answer to that question. You start in **BarnCRM** (or **BarnCRM Console**).

### Where Everything Is

| What you are looking for | Where it is |
|---|---|
| People, households, organizations | **BarnCRM** or **BarnCRM Console** |
| Find, Import and Bulk Update | The **Data Manager** tab, in any BarnCRM app |
| Setup checklist, Health Check, What's new | The **Home** tab of **BarnCRM** or **BarnCRM Console** |
| BarnCRM Settings, Access, Module Manager, Features | **BarnCRM Settings** tab in **BarnCRM Admin** or **BarnCRM Admin Console** |
| Org Optimizer, Duplicate Matching, Error Log | **BarnCRM Admin** or **BarnCRM Admin Console** |
| Rollup Builder (Rollup Builder module) | **BarnCRM Admin** or **BarnCRM Admin Console** |
| Gifts and everything around them (Giving module) | The **Fundraising** app, and the BarnCRM apps once added (below) |
| Volunteer shifts and hours (Volunteers module) | The **BarnCRM Volunteers** app, and the BarnCRM apps once added (below) |

The home page's **Modules** list names each installed module, with an **Open the App** link
for a module that has an app of its own. The Rollup Builder module has no app of its own: its
**Rollup Builder** tab is in the admin apps.

### A Module's Pages in the BarnCRM Apps

Giving and Volunteers keep their own apps, and their pages can also sit in the BarnCRM apps
so you need not switch apps:

| Module | Added to **BarnCRM** and **BarnCRM Console** | Added to **BarnCRM Admin** and **BarnCRM Admin Console** |
|---|---|---|
| Rollup Builder | | Rollup Builder |
| Giving | Quick Gift Entry, Gifts, Commitments, Gift Batches | Accounting Periods, Giving Nightly Jobs, Donor Level Ladder, Stewardship Plan Setup |
| Volunteers | Volunteer Shifts, Volunteer Hours | |
| Mirror | | Campaign Sync, Opportunity Mirror, Accounting Export |

- **Deployed from source** with `scripts/org/deploy-packages.sh`: the script adds the pages
  of every module it deployed itself, as its last step. Nothing to do.
- **Installed as packages**: Salesforce does not let one package add its pages to another
  package's app, so you add them once by hand. **Home**, **Setup Checklist**, **Modules**
  lists the pages for each installed module. For each BarnCRM app you use:
  1. In Setup, open **App Manager** and click **Edit** next to the app.
  2. Open **Navigation Items**, move the listed pages to **Selected Items**, and click
     **Save**. Skip any page that is already there.

A page shows only to people whose access allows it, so adding a page to an everyday app does
not show it to anyone who cannot use it.

## How to Turn It On

There is nothing to turn on. The apps are installed with BarnCRM Core, and BarnCRM gives each
one to the right people itself: the everyday apps to everyone with a BarnCRM role, the admin
apps to the **BarnCRM Admin** role only. It does this through four permission sets named
**BarnCRM App: ...**, which it gives and takes as roles change on the Access page and again
every night; do not assign them by hand.

1. Click the app launcher (the grid of dots at the top left of Salesforce).
2. Type `BarnCRM` and choose **BarnCRM** or **BarnCRM Console** (an administrator also sees
   **BarnCRM Admin** and **BarnCRM Admin Console**).
3. Click the star next to the app name if you want it to open by default. Each person picks
   their own default app this way.

### Hide One Navigation Style for Everyone

By default everyone sees both styles and picks the one they like. To show only one:

1. Open **BarnCRM Settings** (in **BarnCRM Admin**) and click **General**.
2. Set **App navigation style** to **Standard navigation only** or **Console navigation only**.
   **Both (each person chooses)** is the default.
3. Click **Save**. Within a minute or two the other style's apps leave everyone's App Launcher.
   Set it back to **Both (each person chooses)** to show them again.

The setting hides the everyday app and the admin app of the other style together. Each
person can still choose their own default app in the App Launcher among the apps they see.

Everyone who has been given a BarnCRM role can open the everyday apps. The home page shows each
person what they can act on:

| Part of the home page | Who sees it |
|---|---|
| **What's New in BarnCRM**: what changed in the latest release, until you click **Dismiss** | Everyone, each person once per release |
| **Welcome to BarnCRM** and the paused automation banner | Everyone |
| **New Household** button | People who can create and edit accounts (BarnCRM makes the household for them; nobody needs the Household record type) |
| **Setup Checklist** (or the **Setup Complete** tile once it is finished) | Administrators |
| **Health Check** (a summary of its last run; the full list of findings after **Run Now**) | Administrators |
| **Errors to Review** | Administrators |
| **Rollups Last Completed** | Administrators |
| **Seasonal Addresses Last Swapped** | Administrators |
| **Modules** | Administrators |
| **Files That Arrive Regularly** | Anyone who can read import templates, and only when a file is marked as arriving regularly |
| **Quick Links** | Everyone |

"Administrators" means anyone with the **Manage BarnCRM Settings** permission, which the
**BarnCRM Admin** role carries. Staff without it see a shorter page: the welcome, the
**New Household** button, and the quick links. They are not shown a checklist they cannot
finish or an error count for a log they cannot open. The page does not work those numbers
out for staff at all, so it loads faster for them; if you edit the page to show an
administrator tile to staff, it shows nothing to count.

## How Records Open: Tabs in a Console

Every BarnCRM app shows a blue barn logo in the app launcher. The admin apps add a navy gear
badge to it and have a navy header, so you can tell at a glance which app you are in; a module's
app adds its own badge (a red heart for **Fundraising**, a green person for **BarnCRM
Volunteers**).
**BarnCRM Console** and
**BarnCRM Admin Console** are console apps: instead of replacing the page each time you click,
they keep the records you are working on open side by side in tabs across the top. In
**BarnCRM** and **BarnCRM Admin** each record replaces the page, as in most Salesforce apps.

- **Households, organizations, people and Error Log entries open in their own tab** (a
  workspace tab). Open three households and you have three tabs; click one to go back to it.
- **The records that belong to one of them open inside its tab** (a subtab):
  - an address opens under its household,
  - a relationship or an affiliation opens under the person it belongs to,
  - a household member row opens under its household.

  If that link is blank (for example an address that belongs to a person, not a household),
  the record opens in its own tab instead.
- **Pages such as Data Manager and BarnCRM Settings open as tabs too.** Choose them from the
  navigation menu (the arrow next to the app name). In **BarnCRM Console**, Addresses,
  Relationships, Affiliations and Household Members follow Organizations, and Data Manager
  ends the Core part of that menu. In **BarnCRM
  Admin Console** the menu holds BarnCRM Settings, Data Manager, Org Optimizer, Duplicate
  Matching and Error Log. Find and Import open as tabs from their Data Manager tiles.
- **Close a tab** with its **x**, or right-click tabs to close several. Your open tabs are
  still there when you come back.
- **On a phone**, the Salesforce mobile app shows each BarnCRM app as an ordinary app without
  tabs.

## A Five-Minute Walkthrough

Maria has just installed BarnCRM and has the sample data loaded. She has the BarnCRM
Admin role.

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM** (or **BarnCRM Console**). The home page
   opens with the heading **Welcome to BarnCRM** and the sentence "Start with the setup
   checklist below."
2. Read the **Setup Checklist**. It lists every step with a progress ring and a **Done**,
   **Skipped** or **To Do** badge, opens the first step you have not finished, and counts how
   far you have got, for example "3 of 9 steps done" (eight steps with Core alone, nine with
   Giving). The steps are guided: each one is done here, on the home page.
3. The first step, **Choose Your Edition**, is already **Done**: you chose the edition in the
   first-run setup window, and the step only shows that answer.
4. The next step, **Confirm How BarnCRM Fits Your Org**, says what it found in
   your org and recommends a fit. On a fresh org it says "This looks like a fresh org, with
   no other household model and no Person Accounts. BarnCRM can run on its own." and
   recommends **Standalone**. If your org uses Person Accounts, it says so plainly, and
   household membership uses one record per person so that what you already have keeps
   working. Click **Confirm and Continue**.
5. Use **Next** and **Skip for Now**, or click any step's name, to move around. Skipping
   does not mark a step done: it moves the step out of the way and offers it to you again
   next time. The full walkthrough of every step is in [setup-assistant.md](setup-assistant.md).
6. Below the checklist, **Health Check** shows a summary of its last run: a badge (**Not
   Run Yet**, **Passed**, or how many errors or warnings it found) and when it ran. Click
   **Run Now** to check the org again and see every finding as a row, with a button to fix it
   where it can. These are the same rows as the Health Check tab of Org Optimizer. The full
   guide is [health-check.md](health-check.md).
7. Look at the status tiles, each with an icon and a badge. **Errors to Review** shows the
   count of new errors, with **All Clear** when there are none. If it ever shows a number,
   click **Open the Error Log** and read the plain-language message on each row. The tile
   counts up to 999; past that it says `999+`, so a flooded Error Log never slows the home
   page down.
8. Look at **Rollups Last Completed** and **Seasonal Addresses Last Swapped**. Each says
   when that nightly job last finished. Before a job has ever run, the tile says so with a
   **Not Run Yet** badge and no warning. If a job that has run before is more than 36 hours
   late, the tile shows an **Overdue** badge and says so in words, and its link opens the
   settings page where you can run it.
9. If someone has paused automation (for example during a large import), a warning under
   the welcome says BarnCRM automation is paused; administrators also get a **Resume
   Automation** link to the Automation section of BarnCRM Settings. The warning disappears by
   itself when the pause expires.
10. Look at **Modules**. It lists BarnCRM Core and each module installed in your org (with
    Giving, that is Giving), and says for each whether it is on or installed and off. Click
    **Open the Module Manager** to turn a module on or off.
11. Use **Quick Links**, three icon tiles, to open Households, Organizations, or BarnCRM
    Settings without going back to the app launcher.

That is the whole home page. Five minutes, and you know what is done, what is next, and
whether anything went wrong.

When every step is done, the checklist collapses to a small **Setup Complete** tile, and
the welcome sentence points at the tabs instead of the checklist.

## Working in Console Tabs

When the app you are in is a console app (tabs across the top, each holding its own
subtabs), BarnCRM pages use those tabs instead of replacing the page you are on:

- A record you open from a BarnCRM panel opens as a subtab of the tab you are in. That
  covers the household link on a person, a record a Health Check finding names, a record
  in a duplicate suggestion, and an entry in the Error Log tile. Hold Ctrl (Cmd on a Mac)
  while clicking to open the record in a new browser tab instead.
- **BarnCRM Settings**, **Import**, **Find** and **Rollup Builder** name their tab for what
  is on screen, for example "BarnCRM Settings: People and Households", "Import: donors.csv",
  "Find: Contact" or "Rollup Builder: Household total giving", with the page's own icon.
- After **Merge** or **Split** in Household Merge and Split, the household's tab refreshes
  in place, and a split opens the other household as a subtab beside it.

In a standard (non-console) app, and in an org that uses another app, these pages work
exactly as before: records open as pages and nothing is renamed. There is nothing to turn
on.

## Rearranging the Home Page

The home page is a standard Lightning page, and each tile on it is its own component, so
you can move, remove, or add tiles in the Lightning App Builder without any code.

1. Open the home page, click the gear icon, then **Edit Page**.
2. Drag a tile to another region, or select it and click the delete icon to remove it.
   The BarnCRM tiles are listed under **Custom** with names that start with
   **BarnCRM Home**, plus **Health Check**.
3. To add something of your own, drag in a standard component: **List View** (for example
   your households), **Report Chart**, or **Rich Text** for a note to your team.
4. To show a tile only to some people, select it and use **Set Component Visibility**. The
   administrator tiles use the filter **Permissions, Custom Permission, Manage BarnCRM
   Settings, equals true**. Use the same filter to hide your own tiles from staff.
5. Click **Save**. If the App Builder says the page cannot be edited because it came with
   the package, click **Save As** to make your own copy, then **Activation** to make the
   copy the home page of the **BarnCRM** and **BarnCRM Console** apps.

A copy you made does not receive changes from later BarnCRM versions. After an upgrade,
compare it with the page that came with the package.

## Common Mistakes

- **Looking for the app in Setup.** BarnCRM is an app, not a Setup page. Use the app
  launcher, not the gear icon. If `BarnCRM` does not appear in the app launcher, you
  have not been assigned a BarnCRM role: ask whoever installed the package to add you
  on the Access page. If the role was given a moment ago, wait a minute: BarnCRM gives the
  apps in a queued job.
- **Looking for BarnCRM Settings in the BarnCRM app.** The settings and the admin tools are in
  **BarnCRM Admin** and **BarnCRM Admin Console**, which only the BarnCRM Admin role sees.
  **Data Manager** is in the BarnCRM apps too, for anyone with the Find and Export, Bulk Update
  or Bulk Delete permission. Someone without the admin role who has the Duplicate Review
  permission opens Org Optimizer or Duplicate Matching by typing its name in the app launcher.
- **Looking for Find, Import or Bulk Update in the navigation.** None is in any app's
  navigation: open **Data Manager** and choose the **Find and Export Records**, **Import a
  File** or **Update Many Records** card. Recent bulk updates and their undo are under **Data
  Jobs** on the same page.
- **Hiding a style and wondering why a person still has it as their default.** **App
  Navigation Style** takes the other style's apps away; the next time that person opens
  Salesforce they land in an app they can still see. Nothing else about their access changes.
- **Wondering where the checklist went for a staff member.** The checklist, the Health
  Check and the status tiles show only to people with the Manage BarnCRM Settings
  permission. A staff member sees the welcome and the quick links, on purpose.
- **Treating Skip for now as done.** Skipping moves you on without finishing the step, on
  purpose, so that a step waiting for a module you have not installed does not block you. A
  skipped step is still waiting for you next time.
- **Reading the checklist as a one-time task.** When every step is done the checklist
  collapses to a small **Setup Complete** tile with a **Reopen Setup** button. Re-run it
  whenever your organization changes: a new fiscal year, a new staff member, a new address.
- **Expecting a record to replace the page.** In the console, a record opens in a tab and
  the page you were on stays open in its own tab. If the screen feels crowded, close the tabs
  you have finished with.
- **Updating an org that already had the BarnCRM app without tabs.** Salesforce will not
  switch an existing app to console tabs during a deployment, and the console app keeps the
  old app's API name (`BarnCRM`), now labelled **BarnCRM Console**. Before deploying, open
  Setup, **App Manager**, click the arrow next to that app, choose **Edit**, then under **App
  Options** set **Navigation Style** to **Console Navigation** and save. A new installation
  needs nothing.
- **Assuming an empty Errors tile means nothing failed.** The tile counts errors with the
  status **New**. If someone has already marked an error Acknowledged or Resolved, it
  stops counting. Open the Error Log tab to see everything.
