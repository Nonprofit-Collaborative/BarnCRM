# The BarnCRM Apps and Navigation

## What It Does

BarnCRM comes as nine apps, all in console navigation: records stay open side by side in tabs.
Five serve every organization, nonprofit or for-profit; four are for nonprofits.

| App | Group | For | Pages |
|---|---|---|---|
| **BarnCRM Console** | Universal | Everyone with a BarnCRM role | Home, Contacts, Households, Organizations, Accounts, Addresses, Relationships, Affiliations, Household Members, Data Manager, then the everyday pages of modules with no app of their own (Forms, Form Submissions, Logic Models, Payments, Component Builder, Advanced Reporting) and of Scholarships and Outbound Grants |
| **BarnCRM Admin Console** | Universal | The BarnCRM Admin role only | BarnCRM Settings, Data Manager, Duplicate Matching, Automation, every installed module's admin pages (among them Forms Home and Forms, Portal Builder Home, Portals and Portal Accesses, and Super Connector), Error Log |
| **BarnCRM Members and Partners** | Universal | Memberships and Corporate Hub role holders | Memberships Home, Memberships, Member Certifications, Membership Levels, Certifications, Corporate Hub Home, Library Documents, Compliance Obligations, Agreements, Boards and Committees, Board Meetings, Processing Activities, Data Subject Requests, Data Breaches, Reports, Dashboards, Error Log |
| **BarnCRM Events** | Universal | Event Management role holders | Events Home, Event Calendar, Events, Event Speakers, Venues, Reports, Error Log |
| **BarnCRM Projects** | Universal | Project Management role holders | Projects Home, Timesheet, Approvals, Requests, Projects, Time Entries, Project Expenses, Project Resources, Staffing, Project Rates, Project Invoices, Request Connections, Reports, Error Log |
| **BarnCRM Fundraising** | Nonprofit | Fundraising role holders | Fundraising Home, Quick Gift Entry, Contacts, Households, Organizations, Gifts, Commitments, Ask Pipeline, Gift Batches, Receipts, Stewardship Plans, Thank-Yous, Reports, with its utility bar |
| **BarnCRM Grants** | Nonprofit | Grants role holders | Grants Home, Grant Pipeline, Grant Calendar, Grant Finder, Grants, Grant Requirements, Grant Answers, Funder Report Templates, Grant Checklist Items, then Scholarships Home, Award Programs, Award Applications and Awards (with Scholarships and Outbound Grants), Reports, Dashboards, Error Log |
| **BarnCRM Programs** | Nonprofit | Programs role holders | Programs Home, Programs, Cohorts, Sessions, Enrollments, Service Deliveries, Case Notes, Referrals, Service Counts, Goals, Reports |
| **BarnCRM Volunteers** | Nonprofit | Volunteers role holders | Volunteers Home, Volunteer Jobs, Shifts, Sign-Ups, Hours, Approve Hours, Letter Templates, Skills, Requirements, Reports, Dashboards |

Memberships, Corporate Hub, Forms, Event Management and Project Management serve every
organization, so their pages never sit in a nonprofit app. An app shows only the pages of the
modules installed, and each page shows only to the people whose access allows it, so a menu can
be shorter than the list.

**BarnCRM Console** gives you one home page that tells you what to do next, a setup checklist
that remembers how far you got, and the places you go most: your households, your people and
your organizations. **BarnCRM Admin Console** holds every BarnCRM tool and setting in one
place. **Super Importer**, **Find** and **Super Transformer** are not in any app's navigation:
open them from the tiles on the **Data Manager** tab, which also has tiles for **Org Optimizer**
and **Duplicate Matching**. The raw **Import Rows** tab is in no app's navigation either: open
it from an import's results in Super Importer, or from the App Launcher. **Error Log** is always
the last tab of an app that has it, after any pages a module adds. In BarnCRM Console, **Data
Manager** is the last Core tab and a module's pages follow it.

Each page's icon matches what it does, and the page header and its console tab show the same
one: a gear for **BarnCRM Settings**, building blocks for **Data Manager**, a stethoscope for
**Org Optimizer**, scales for **Duplicate Matching**, a factory for **Automation**, a bell
for **Error Log**, a telescope for
**Find** and a form for **Import**. **Households** show people, **Organizations** a building,
**Addresses** a map. Every BarnCRM page opens with the same page header: on Data Manager, Org
Optimizer, Duplicate Matching, Find, Import, Super Transformer, Automation and Record Inspector
the page name appears once, followed by a line saying what the page is for. On the home page the
header is the welcome. Sections further down a page are cards. Module pages open with the same
header, among them **Rollup Builder**, **Accounting Periods**, **Opportunity Mirror**, **Gift
Transaction Mirror** and **Component Builder**.

Module tabs follow the same rule: every Fundraising, Volunteers, Programs, Logic Models, Rollup
Builder and Mirror tab has its own icon, never one shared with another BarnCRM tab (for
example a stack of cash for **Gifts**, a trophy for **Donor Levels**, a chalkboard for **Logic
Models**, a sailboat for **Programs**). The full list is in the contributor guide's
[Tab Icons](../contributor-guide/tab-icons.md).

If you have ever installed something in Salesforce and then wondered where to start, this
is the answer to that question. You start in **BarnCRM Console**.

### Where Everything Is

| What you are looking for | Where it is |
|---|---|
| People, households, organizations | **BarnCRM Console** |
| Find, Import and Super Transformer | The **Data Manager** tab, in BarnCRM Console or BarnCRM Admin Console |
| Setup checklist, What's new | The **Home** tab of **BarnCRM Console** |
| Health Check | The **Org Optimizer** tab, with the optional BarnCRM Org Optimizer package |
| BarnCRM Settings, Access, Module Manager, Features | **BarnCRM Settings** tab in **BarnCRM Admin Console** |
| Org Optimizer, Duplicate Matching, Automation, Error Log | **BarnCRM Admin Console** |
| Record Inspector | The **Inspect This Record** button at the top of the right column on Contact and Account pages (it has no tab in the apps, D-183) |
| Rollup Builder (Rollup Builder module) | **BarnCRM Admin Console** |
| Gifts and everything around them (Fundraising module) | **BarnCRM Fundraising**; its admin pages also in **BarnCRM Admin Console** |
| Grants (Grants module) | **BarnCRM Grants** |
| Award programs, applications and awards (Scholarships and Outbound Grants module) | **BarnCRM Grants**, after the grant pages, and **BarnCRM Console** |
| Programs, enrollments and services (Programs module) | **BarnCRM Programs** |
| Volunteer shifts and hours (Volunteers module) | **BarnCRM Volunteers** |
| Memberships and certifications (Memberships module) | **BarnCRM Members and Partners**; Membership Levels and Certifications also in **BarnCRM Admin Console** |
| Library, compliance, agreements and boards (Corporate Hub module) | **BarnCRM Members and Partners** |
| Events, speakers and venues (Event Management module) | **BarnCRM Events** |
| Projects, time and expenses (Project Management module) | **BarnCRM Projects**; Project Rates, Project Invoices and Request Connections also in **BarnCRM Admin Console** |
| Form submissions (Forms module) | **BarnCRM Console** |
| Building forms: Forms Home and Forms (Forms module) | **BarnCRM Admin Console** |
| Portals (Portal Builder module) | **BarnCRM Admin Console** |
| Super Connector (BarnCRM Connector module) | **BarnCRM Admin Console** |

The home page's **Modules** list names each installed module, marked **On** or **Off** (turned
off in BarnCRM Settings, Modules), with an **Open the App** link to the app its pages are in:
**BarnCRM Members and Partners** for Memberships and Corporate Hub, **BarnCRM Grants** for
Scholarships and Outbound Grants. Forms, Portal Builder, Connector, Rollup Builder, Mirror and
the smaller modules have no app of their own: their pages are in BarnCRM Console and BarnCRM
Admin Console.

### The Module Apps

Each module app is a console app with its own logo, every page of its modules, **Reports**, and
**Error Log** last where the module ships it. The module's permission sets show the app, so
whoever has the module's Staff, Admin or Read Only set sees it in the App Launcher. **BarnCRM
Members and Partners** is shown by the Memberships and Corporate Hub sets; nobody sees it until
one of the two is installed.

### Module Homes

Every module app opens on its home, the first tab, named for the module: Events Home,
Fundraising Home, Grants Home, Programs Home, Projects Home and Volunteers Home. **BarnCRM Members
and Partners** opens on **Memberships Home**, or on **Corporate Hub Home** when Memberships is not
installed; **BarnCRM Grants** keeps **Grants Home** first, with **Scholarships Home** after the
grant pages. Forms Home and Portal Builder Home are in **BarnCRM Admin Console**. Each home has
the same layout, so people know where to look in any module:

- The page title, its About This Tool help, and the module's quick actions (such as **New
  Event**) at the top right. A quick action shows only to someone who may create that record.
- A row of figures, each a link to the list behind it.
- The lists or charts that module's daily work needs, each with a heading. An empty list says
  what to do next.
- Before the module has its first record, a setup panel with the first step in place of the
  figures and lists.

A home only reads what the module already stores, as the person viewing it, so each person sees
figures and rows for the records they may read. Nothing on a home is a setting.

Test and developer orgs (scratch and Developer Edition orgs) allow only about 10 custom apps; the
nine apps fit, so every org gets every app (`scripts/org/capped-org-apps.py` leaves none out).

### A Module's Pages in the BarnCRM Apps

Salesforce does not let an app name a page its own package does not ship, so a module's pages
reach BarnCRM Console, BarnCRM Admin Console, BarnCRM Members and Partners and BarnCRM Grants
from the module catalog, not from the app's own file:

| Module | Everyday pages go to | Admin pages go to |
|---|---|---|
| Rollup Builder | | **BarnCRM Admin Console**: Rollup Builder |
| Fundraising | (its own app) | **BarnCRM Admin Console**: Accounting Periods, Donor Levels and Scores, Stewardship Plan Setup, Pledge Reminders, Receipt Letters, Campaign Sync, Opportunity Mirror, Gift Transaction Mirror, Accounting Export |
| Programs | (its own app) | **BarnCRM Admin Console**: Programs Settings |
| Mirror | | **BarnCRM Admin Console**: Provider Requests |
| Forms | **BarnCRM Console**: Forms, Form Submissions | **BarnCRM Admin Console**: Forms Home, Forms |
| Portal Builder | | **BarnCRM Admin Console**: Portal Builder Home, Portals, Portal Accesses |
| BarnCRM Connector | | **BarnCRM Admin Console**: Super Connector |
| Memberships | **BarnCRM Members and Partners**: Memberships Home, Memberships, Member Certifications | **BarnCRM Members and Partners** and **BarnCRM Admin Console**: Membership Levels, Certifications |
| Corporate Hub | **BarnCRM Members and Partners**: Corporate Hub Home, Library Documents, Compliance Obligations, Agreements, Boards and Committees, Board Meetings, Processing Activities, Data Subject Requests, Data Breaches | |
| Project Management | (its own app) | **BarnCRM Admin Console**: Project Rates, Project Invoices, Request Connections |
| Scholarships and Outbound Grants | **BarnCRM Grants** and **BarnCRM Console**: Scholarships Home, Award Programs, Award Applications, Awards | |
| Logic Models, Payments, Component Builder, Advanced Reporting | **BarnCRM Console** | **BarnCRM Admin Console**: their setup pages |

A module's pages go before an app's **Reports**, **Dashboards** and **Error Log** tabs, or at
the end of BarnCRM Console, so Error Log stays last. A form, form submission or event opens on
its own record page from any app, since its module makes that page the org default.

- **Deployed from source** with `scripts/org/deploy-packages.sh`: the script adds the pages
  of every module it deployed itself, as its last step. Nothing to do. Each run sets each app
  to exactly its own pages plus those of the modules it deployed.
- **Removing a module from a source install**: before deleting the module's components, set the
  apps back without its pages, naming only the module folders you keep (here Fundraising and
  Rollups):

  ```
  python3 scripts/org/module-app-tabs.py --all apps-out rollups giving
  sf project deploy start --metadata-dir apps-out --target-org myorg
  ```

  With no module left, leave the folder names out.
- **Installed as packages**: Salesforce does not let one package add its pages to another
  package's app, so you add them once by hand. **Home**, **Setup Checklist**, **Modules**
  lists the pages for each installed module. For each app it names:
  1. In Setup, open **App Manager** and click **Edit** next to the app.
  2. Open **Navigation Items**, move the listed pages to **Selected Items**, and click
     **Save**. Skip any page that is already there.

A page shows only to people whose access allows it, so adding a page to an app does not show it
to anyone who cannot use it.

## How to Turn It On

There is nothing to turn on. The apps are installed with their packages, and BarnCRM gives each
one to the right people itself: **BarnCRM Console** to everyone with a BarnCRM role, **BarnCRM
Admin Console** to the **BarnCRM Admin** role only. It does this through two permission sets
named **BarnCRM Auto: ... App**, which it gives and takes as roles change on the Access page and
again every hour; do not assign them by hand. A module app comes with its module's role sets.
The sets of modules with no app show a Core app instead, so everyone who works in a module
has an app: the Forms and Scholarships and Outbound Grants sets show **BarnCRM Console**,
**Forms Admin** also shows **BarnCRM Admin Console**, and **Portal Builder Admin** and both
BarnCRM Connector sets show **BarnCRM Admin Console**.

1. Click the app launcher (the grid of dots at the top left of Salesforce).
2. Type `BarnCRM` and choose **BarnCRM Console** (an administrator also sees **BarnCRM Admin
   Console**).
3. Click the star next to the app name if you want it to open by default. Each person picks
   their own default app this way.

Everyone who has been given a BarnCRM role can open BarnCRM Console. The home page shows each
person what they can act on:

| Part of the home page | Who sees it |
|---|---|
| **What's New in BarnCRM**: what changed in the latest release, until you click **Dismiss** | Everyone, each person once per release |
| **Welcome to BarnCRM** and the paused automation warning | Everyone |
| **New Person** button (opens the standard new contact form; the household is made automatically) | People who can create contacts |
| **New Household** button | People who can create and edit accounts (BarnCRM makes the household for them; nobody needs the Household record type) |
| **Setup Checklist** (or the **Setup Complete** tile once it is finished) | Administrators |
| **Health Check** (a summary of its last run, with **Open Health Check**) | Administrators, while BarnCRM Org Optimizer is installed |
| **Errors to Review** | Administrators |
| **Rollups Last Completed** | Administrators |
| **Seasonal Addresses Last Swapped** | Administrators |
| **Modules** | Administrators |
| **Files That Arrive Regularly** | Anyone who can read import templates, and only when a file is marked as arriving regularly |
| **Quick Links**: People, Households, Organizations and Find | Everyone |
| **Import a File** quick link | Anyone who can run an import (create Import Batches) |
| Module quick links: **Enter a Gift** (Fundraising), **Log Hours** (Volunteers), **Enroll** (Programs, for someone who can create enrollments) | Everyone, while that module is installed and turned on in the Module Manager. Each module's links come from its row in the module catalog (`Quick_Links__c` on BarnCRM Module), never from module code; the one-line description under each comes from Core's in-app help text (BarnHelp), like the other quick links' |
| **BarnCRM Settings** quick link | Administrators |

"Administrators" means anyone with the **Manage BarnCRM Settings** permission, which the
**BarnCRM Admin** role carries. Staff without it see a shorter page: the welcome, the
**New Person** and **New Household** buttons, and the quick links. They are not shown a checklist they cannot
finish or an error count for a log they cannot open. The page does not work those numbers
out for staff at all, so it loads faster for them; if you edit the page to show an
administrator tile to staff, it shows nothing to count.

## How Records Open: Tabs in a Console

Every BarnCRM app shows Patch, the BarnCRM highland cow, in the app launcher, and every app has
the same Barn Navy header (#1E2A3A), so you always know you are in BarnCRM. The logo tells the
apps apart: **BarnCRM Console** shows Patch's face on a sage circle, **BarnCRM Admin Console**
shows Patch standing in a round badge, and each module app shows Patch with its prop (a heart
for **BarnCRM Fundraising**, a safety vest for **BarnCRM Volunteers**, a cap and clipboard for
**BarnCRM Programs**, a monocle for **BarnCRM Grants**, a party hat for **BarnCRM Events**, a hard
hat for **BarnCRM Projects** and a Member sash for **BarnCRM Members and Partners**). Logic Models
and Forms have no app; Patch with building blocks or with a pencil and tool belt marks their
tiles under **Modules** on the BarnCRM home page. Every app is a console app: instead of
replacing the page each time you click, it keeps the records you are working on open side by
side in tabs across the top.

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
  ends the Core part of that menu. In **BarnCRM Admin Console** the menu holds BarnCRM Settings,
  Data Manager, Duplicate Matching, Automation, the module admin pages and Error Log. Find and
  Import open as tabs from their Data Manager tiles.
- **Close a tab** with its **x**, or right-click tabs to close several. Your open tabs are
  still there when you come back.
- **On a phone**, the Salesforce mobile app shows each BarnCRM app as an ordinary app without
  tabs.

## A Five-Minute Walkthrough

Maria has just installed BarnCRM and has the sample data loaded. She has the BarnCRM
Admin role.

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM Console**. The home page
   opens with the page header **Welcome to BarnCRM** and the sentence "Start with the setup
   checklist below.", with Patch waving hello beside it (on a wide screen) and **New Person**
   and **New Household** on the right.
2. Read the **Setup Checklist**. It lists every step with a progress ring and a **Done**,
   **Skipped** or **To Do** badge, opens the first step you have not finished, and counts how
   far you have got, for example "3 of 9 steps done" (eight steps with Core alone, nine with
   Fundraising). The steps are guided: each one is done here, on the home page.
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
6. With the optional BarnCRM Org Optimizer package installed, the **Health Check** tile
   shows a summary of its last full run: a badge (**Needs Fixing**, **Worth Knowing**, **All
   Clear** or **Not Run Yet**, the same badge as Org Optimizer's), when it ran, and how many
   findings it had to fix, to be aware of and for your information. Click **Open Health
   Check** to open the Health Check section of Org Optimizer, where you run it again and fix
   what it found. Opening Home never runs Health Check, so the tile costs the page nothing.
   Without the package there is no tile. The full guide is [health-check.md](health-check.md).
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
    Fundraising, that is Fundraising), each with its app's logo, and says for each whether it is on or
    installed and off. Click
    **Open the Module Manager** to turn a module on or off.
11. Use **Quick Links**, icon tiles, to open People, Households, Organizations, Find, Import a
    File, each installed module's links (Enter a Gift, Log Hours, Enroll) or BarnCRM Settings
    without going back to the app launcher. A module link to a tab shows only to someone who
    can see that tab.
12. Click **New Person** under the welcome to add someone; the household is made for them.
    Once setup is finished, the welcome reads "Find someone, add someone new, or pick up
    where you left off."

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

In an app of your own in standard navigation, these pages work as ordinary pages: records open
as pages and nothing is renamed. There is nothing to turn on.

## Rearranging the Home Page

The home page is a standard Lightning page, and each tile on it is its own component, so
you can move, remove, or add tiles in the Lightning App Builder without any code.

1. Open the home page, click the gear icon, then **Edit Page**.
2. Drag a tile to another region, or select it and click the delete icon to remove it.
   The BarnCRM tiles are listed under **Custom** with names that start with
   **BarnCRM Home**; **BarnCRM Home: Health Check** is the Health Check tile. With BarnCRM
   Org Optimizer installed, the full **Health Check** panel is listed too: add it and tick
   **Show the last result first** for the last run's summary with **Run Health Check** on
   the home page itself.
3. To add something of your own, drag in a standard component: **List View** (for example
   your households), **Report Chart**, or **Rich Text** for a note to your team.
4. To show a tile only to some people, select it and use **Set Component Visibility**. The
   administrator tiles use the filter **Permissions, Custom Permission, Manage BarnCRM
   Settings, equals true**. Use the same filter to hide your own tiles from staff.
5. Click **Save**. If the App Builder says the page cannot be edited because it came with
   the package, click **Save As** to make your own copy, then **Activation** to make the
   copy the home page of the **BarnCRM Console** app.

A copy you made does not receive changes from later BarnCRM versions. After an upgrade,
compare it with the page that came with the package.

## Common Mistakes

- **Looking for the app in Setup.** BarnCRM is an app, not a Setup page. Use the app
  launcher, not the gear icon. If `BarnCRM` does not appear in the app launcher, you
  have not been assigned a BarnCRM role: ask whoever installed the package to add you
  on the Access page. If the role was given a moment ago, wait a minute: BarnCRM gives the
  apps in a queued job.
- **Looking for BarnCRM Settings in BarnCRM Console.** The settings and the admin tools are in
  **BarnCRM Admin Console**, which the BarnCRM Admin role sees (and the Forms Admin, Portal
  Builder Admin and BarnCRM Connector sets, for their own pages). **Data Manager** is in
  BarnCRM Console too, for anyone with the Find and Export, Bulk Update or Bulk Delete
  permission. Someone without the admin role who has the Duplicate Review permission opens Org
  Optimizer or Duplicate Matching by typing its name in the app launcher.
- **Looking for a Forms, Portal Builder or Connector app.** These modules have no app: form
  submissions are in BarnCRM Console, and building forms, portals and Super Connector are in
  BarnCRM Admin Console. Someone without the admin role who works on forms or portals opens the
  page by typing its name in the app launcher.
- **Looking for Find, Import or Super Transformer in the navigation.** None is in any app's
  navigation: open **Data Manager** and choose the **Find and Export Records**, **Import a
  File** or **Super Transformer** card. Recent Super Transformer runs and their undo are under **Data
  Jobs** on the same page.
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
- **Deploying over an org with an app of the same name in standard navigation.** Salesforce
  will not switch an existing app to console tabs during a deployment. Before deploying, open
  Setup, **App Manager**, click the arrow next to that app, choose **Edit**, then under **App
  Options** set **Navigation Style** to **Console Navigation** and save. A new installation
  needs nothing.
- **Assuming an empty Errors tile means nothing failed.** The tile counts errors with the
  status **New**. If someone has already marked an error Acknowledged or Resolved, it
  stops counting. Open the Error Log tab to see everything.
