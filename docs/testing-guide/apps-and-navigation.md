# Apps and Navigation

Scripts for the nine BarnCRM apps, all in console navigation, and the module pages they hold.
Setup detail: [The BarnCRM Apps and Navigation](../admin-guide/barncrm-app.md).

Before you start: an org from [Before you test](before-you-test.md), with the staff user from
[Test users](before-you-test.md#test-users). After a role or setting change, BarnCRM gives and
takes the apps in a queued job: wait a minute and reload before checking the App Launcher.

## T-APP-01: Each App Shows the Right Tabs to the Right People

**Purpose:** confirm BarnCRM Console goes to every BarnCRM role, BarnCRM Admin Console to admins only, and each holds its own tabs.
**Prerequisites:** admin user and staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `BarnCRM`. | **BarnCRM Console** and **BarnCRM Admin Console** are listed: the first with Patch's face on a sage circle, the admin app with Patch standing in a round badge. With the modules deployed, **BarnCRM Fundraising** shows Patch holding a heart, **BarnCRM Volunteers** Patch in a safety vest, **BarnCRM Programs** Patch with a cap and clipboard, **BarnCRM Grants** Patch with a monocle, **BarnCRM Events** Patch in a party hat, **BarnCRM Projects** Patch in a hard hat and **BarnCRM Members and Partners** Patch wearing a green Member sash. No app named **BarnCRM** or **BarnCRM Admin** alone is listed. No app shows a generic initials tile. |
| 2 | Open **BarnCRM Console** and its navigation menu (the arrow next to the app name). | Console navigation with a Barn Navy (#1E2A3A) header. **Home**, **Contacts**, **Households**, **Organizations**, **Addresses**, **Relationships**, **Affiliations**, **Household Members**, **Data Manager**, then the pages of installed modules with no app (for example **Forms** and **Form Submissions**) and the Scholarships and Outbound Grants pages. **Find** is not in the navigation. On a wide window, Patch waves beside **Welcome to BarnCRM** on **Home**; its alternative text (a screen reader reads it) is "Patch, the BarnCRM highland cow, waving hello". |
| 3 | Open a household, then one of its addresses. | The household opens in its own tab; the address opens as a subtab under it. |
| 4 | Open **BarnCRM Admin Console** and its navigation menu. | **BarnCRM Settings**, **Data Manager**, **Duplicate Matching**, **Automation**, the installed modules' admin pages, **Error Log** (last), each opening as a workspace tab. **Super Importer**, **Super Transformer** and **Import Rows** are not in the navigation. It opens on **BarnCRM Settings**. |
| 5 | As staff, open the App Launcher and type `BarnCRM`. | **BarnCRM Console** is listed. **BarnCRM Admin Console** is not. |
| 6 | As admin, on **BarnCRM Settings**, **Access**, remove the staff user's role. Wait a minute; as staff, reload and open the App Launcher. | No BarnCRM Core app is listed. |

**Cleanup:** give the staff user its role back on the Access page.

## T-APP-02: Only Console Apps Ship

**Purpose:** confirm the suite has nine apps, each in console navigation, and no navigation style setting (ADR-0237, nine console apps).
**Prerequisites:** an org deployed with every module by `scripts/org/deploy-packages.sh`; admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Setup, open **App Manager** and filter the list by `BarnCRM`. | Nine apps: BarnCRM Console, BarnCRM Admin Console, BarnCRM Members and Partners, BarnCRM Events, BarnCRM Projects, BarnCRM Fundraising, BarnCRM Grants, BarnCRM Programs, BarnCRM Volunteers. Each reads **Console** under its navigation type. |
| 2 | Open **BarnCRM Settings**, **General**. | No **App Navigation Style** row. |
| 3 | Open each app in turn and open a record from a list. | The record opens in a workspace tab in every app. |

**Cleanup:** none.

## T-APP-03: Module Pages Reach the Apps That Host Them

**Purpose:** confirm a source deploy adds each deployed module's pages to the app that hosts them, the Setup Assistant lists them for a package install, and the home page links each module's app.
**Prerequisites:** an org deployed with `scripts/org/deploy-packages.sh` (Core, Rollup Builder, Fundraising, Mirror, Forms, Memberships, Corporate Hub, Grants and Scholarships and Outbound Grants); admin user and staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Read the deploy output. | A stage "Module tabs in the BarnCRM apps" ran and succeeded. |
| 2 | As admin, open **BarnCRM Admin Console**. | Before **Error Log**, which stays the last tab: **Rollup Builder**, **Accounting Periods**, **Donor Levels and Scores**, **Stewardship Plan Templates**, **Pledge Reminders**, **Receipt Letters**, **Campaign Sync**, **Opportunity Mirror**, **Gift Transaction Mirror**, **Accounting Export**, then **Forms Home** and **Forms** and the other module admin pages. |
| 3 | Open **BarnCRM Console**. | After **Data Manager**: **Forms**, **Form Submissions**. No **Gifts**, **Memberships** or **Awards** tab: those are in their own apps. |
| 4 | Open **BarnCRM Console**, **Contacts**, a contact with gifts, then a gift from its related list. | The gift opens on the same record page as in **BarnCRM Fundraising**. |
| 5 | From the App Launcher, search for "BarnCRM Rollup Builder". | No such app is listed; the **Rollup Builder** tab is. |
| 6 | Open **BarnCRM Console**, **Home**, **Setup Checklist**, **Modules**. | Under **BarnCRM Memberships**: "Add to the module's app if they are not there, or to BarnCRM Console for a module with no app: Memberships Home, Memberships, Member Certifications" and "Add to BarnCRM Admin Console: Membership Levels, Certifications", then the App Manager steps. A module not installed lists no pages. |
| 7 | On the **BarnCRM Console** home page, look at **Modules**. | **BarnCRM Fundraising** has an **Open the App** link that opens **BarnCRM Fundraising**; Memberships and Corporate Hub open **BarnCRM Members and Partners**; Scholarships and Outbound Grants opens **BarnCRM Grants**; Forms, Portal Builder and **BarnCRM Rollup Builder** have none. |
| 8 | As staff, open **BarnCRM Console**. | A module page shows only if the staff user's access allows it; no admin page is listed. |

**Cleanup:** none.

## T-APP-04: Tab Icons Match Their Pages, and Each Page Name Shows Once

**Purpose:** confirm each Core page shows an icon that fits it, the same in the navigation, the page header and the console tab, and prints its name once.
**Prerequisites:** admin user. Open **BarnCRM Admin Console**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**. | The page header shows a gear, as do the console tab and the settings card. No airplane. |
| 2 | Open **Data Manager**. | Building blocks in the page header. The name **Data Manager** shows once, in the page header; below it the first line is "Start a data task, or see and undo what changed." with no second **Data Manager** title. |
| 3 | On **Data Manager**, click the **Super Importer** tile. | The **Super Importer** page header shows a form (a document), not an alarm clock. The page name shows once, followed by "Load records from a spreadsheet, preview them first, and undo an import if needed." and then the wizard. |
| 4 | Back on **Data Manager**, click the **Find** tile, then go back and click the **Super Transformer** tile. | The first opens **Find**, with a telescope in the page header and the name **Find** once, followed by its purpose line. The second opens **Super Transformer**, its name once, followed by "Change many records at once, without a file, and undo it if needed." |
| 5 | Open **Org Optimizer**, then **Duplicate Matching**. | A stethoscope, then scales, in the page header. Each name shows once, followed by its purpose line and then the tabs. |
| 6 | Open **Error Log**. | A bell in the page header, not a trophy. **Error Log** is the last tab in the navigation menu. |
| 7 | Open **BarnCRM Console**, then **Households**, **Organizations** and an address. | People for households, a building for organizations, a map for the address. |
| 8 | In **BarnCRM Admin Console**, open **Automation**. | The name **Automation** shows once, followed by its purpose line "Everything BarnCRM does for you in the background. ..." in the same page header style as Data Manager; the **Pause and Catch Up** card follows, without that line repeated in it. |
| 9 | Open a sample Contact and click **Inspect This Record**. | The **Record Inspector** page opens with the page header: the large title **Record Inspector**, the line "See every field you can read on any record, with its API name and value." and **Refresh** on the right. No small card title. |
| 10 | Open the **BarnCRM Console** app, **Home** tab. | The top of the page is the same page header style: Patch (on a wide screen), the large title **Welcome to BarnCRM**, the welcome line under it, and **New Person** and **New Household** on the right. The other Home tiles stay cards. |

**Cleanup:** none.

## T-APP-05: Home Works From the First Day, on Any Screen

**Purpose:** confirm the Households quick link, the setup checklist on a phone, the first-run
window's close button and the Storage and Limits icon.
**Prerequisites:** admin; a staff user who has never opened **Households** (a new user is
best); for step 5, an org where first-run setup is not finished.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the new staff user, open the **BarnCRM Console** home page and click the **Households** quick link. | The households list opens, even though the user has no **Households** tab yet. |
| 1a | Still as staff, look at the welcome and **Quick Links**, then click **New Person**. | The welcome reads "Find someone, add someone new, or pick up where you left off." Quick links are **People**, **Households**, **Organizations** and **Find** (plus **Import a File** for someone who can import, **Enter a Gift** with Fundraising, **Log Hours** with Volunteers and **Enroll** with Programs, each only while its module is installed and on), with no **BarnCRM Settings**. **Enroll** opens a new enrollment; turn Programs off in the Module Manager and reload: **Enroll** is gone. **New Person** opens the new contact form; save a person and a household is made for them. As admin, **BarnCRM Settings** is also listed. |
| 2 | As admin, in an org where a setup step is still **To Do**, open the home page in the Salesforce mobile app or a browser window about 400 pixels wide. | The **Setup Checklist** is the first card on the page, above the welcome. It shows once. |
| 3 | Widen the window past 768 pixels. | The checklist moves to the side column. It shows once. |
| 4 | In an org where setup is finished, repeat step 2. | The **Setup Complete** tile is at the bottom of the page, not the top. |
| 5 | In an org where first-run setup is not finished, open the home page as admin, then as staff. | Admin: the setup window's close button is greyed out and Escape does nothing. Staff: "An administrator needs to finish setting up BarnCRM." with a **Close** button; **Close**, the close button and Escape each close the window. |
| 6 | Open **Org Optimizer**, **Overview**. | The **Storage and Limits** tile shows an icon, not an empty square. |
| 7 | Open **BarnCRM Settings**, **Integrations**, in an org without DLRS. | DLRS is not listed. In an org with DLRS installed, it is listed under **Complementary Apps** as **Installed in this org**. |

**Cleanup:** none.

## T-APP-06: Households and Organizations Tabs Open Full List Views

**Purpose:** confirm the tabs open the standard Account list page with its list view menu, and
that My list views exist.
**Prerequisites:** staff user with the **BarnCRM Households** tab; more than 25 households; a
household and an organization owned by that user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Households** tab. | The standard Account list page opens on **Households** with every household (pages of rows, not a short card) and the list view menu. |
| 2 | Select the browser Back button. | You return to the page before the tab, not to a blank tab page. |
| 3 | In the list view menu, choose **My Households**. | Only households the user owns. |
| 4 | Open the **Organizations** tab, then choose **My Organizations**. | The **Organizations** list opens with the menu; **My Organizations** lists only the user's own. |
| 5 | Open the **Brands**, **Payments** and **Boards and Committees** tabs (where installed). | Each has **All** and **My** lists; **Brands** also has **Active Brands** and **Inactive Brands**. |

**Cleanup:** none.

## T-APP-07: Account Tabs Chooses Households and Organizations, Accounts, or Both

**Purpose:** confirm the Account Tabs setting shows the chosen tabs to every BarnCRM role and that the default changes nothing (C-73).
**Prerequisites:** admin user and staff user; the **Households** feature on; the staff user's profile does not show the Accounts tab (Setup, the profile's **Object Settings** or **Tab Settings**: Accounts **Default Off** or hidden).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open **BarnCRM Settings**, **General**. | An **Account Tabs** row shows **Organization and Household Tabs** with its help, and the choices **Organization and Household Tabs**, **Accounts Tab (Standard)** and **Both: Organization, Household and Accounts Tabs**. |
| 2 | As staff, open **BarnCRM Console**. | **Households** and **Organizations** show; **Accounts** does not. |
| 3 | As admin, choose **Accounts Tab (Standard)** and **Save**. Wait a minute. | "Your settings are saved." **Recent changes** shows the change. |
| 4 | As staff, reload **BarnCRM Console** and **BarnCRM Fundraising**. | In **BarnCRM Console**, **Accounts** shows after **Contacts**; **Households** and **Organizations** are gone from it and the App Launcher. In **Accounts**, the list view menu holds **Households**, **My Households**, **Organizations** and **My Organizations**. |
| 5 | As admin, choose **Both** and save; wait a minute; as staff, reload. | **Households**, **Organizations** and **Accounts** all show. |
| 6 | As admin, choose **Organization and Household Tabs** and save; wait; as staff, reload. | Back to step 2: no **Accounts** tab. |

**Cleanup:** leave **Account Tabs** on **Organization and Household Tabs**.

## The Module Apps and Hosted Pages (T-APP-08 to T-APP-15, T-APP-18)

Event Management, Project Management, Fundraising, Grants, Programs and Volunteers have an app of
their own. Memberships and Corporate Hub fill **BarnCRM Members and Partners**, a Core app;
Scholarships and Outbound Grants joins **BarnCRM Grants**; Forms, Portal Builder and BarnCRM
Connector have no app, and their permission sets show BarnCRM Console or BarnCRM Admin
Console instead. Every org, scratch and Developer Edition included, gets all nine apps
(T-APP-13). In each script, the module is installed and on, and its access sync has run
(**Finish Setup**, or wait an hour).

## T-APP-08: BarnCRM Events

**Purpose:** confirm the Event Management app, its tabs and who sees it.
**Prerequisites:** admin user; staff user with the Team Member role (so Events Staff).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Events`. | **BarnCRM Events** is listed with Patch in a party hat. |
| 2 | Open it and its navigation menu. | Console navigation with the Barn Navy header. Tabs: **Events Home**, **Event Calendar**, **Events**, **Event Speakers**, **Venues**, **Reports**, **Error Log** (last). |
| 3 | Open an event from **Events**. | It opens as a workspace tab on the event record page (with its tabs). |
| 4 | Open **BarnCRM Console** and **BarnCRM Fundraising**. | Neither lists an Event Management page. |
| 5 | As staff, open the App Launcher and type `Events`. | **BarnCRM Events** is listed. A user with no Events permission set does not see it. |

## T-APP-09: Forms Pages in BarnCRM Console and BarnCRM Admin Console

**Purpose:** confirm Forms has no app, its submissions are in BarnCRM Console and its form building pages in BarnCRM Admin Console.
**Prerequisites:** admin user; staff user with the Team Member role (so Forms Staff).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Forms`. | No **BarnCRM Forms** app; the **Forms Home**, **Forms** and **Form Submissions** items are listed. |
| 2 | Open **BarnCRM Admin Console** and its navigation menu. | **Forms Home** and **Forms** are there, before **Error Log**. |
| 3 | Open a form. | It opens on the form record page with its builder. |
| 4 | Open **BarnCRM Console**. | **Forms** and **Form Submissions** are there, after **Data Manager**; **Forms Home** is not. |
| 5 | As staff, open **BarnCRM Console**, **Forms**, then a published form. | It opens on the form record page with **Fill In**; **Form Submissions** opens its list too. |

## T-APP-10: Portal Builder Pages in BarnCRM Admin Console

**Purpose:** confirm Portal Builder has no app and its pages are admin pages.
**Prerequisites:** admin user; staff user without the BarnCRM Admin role.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Portal`. | No **BarnCRM Portal Builder** app; the **Portal Builder Home**, **Portals** and **Portal Accesses** items are listed. |
| 2 | Open **BarnCRM Admin Console**. | **Portal Builder Home**, **Portals** and **Portal Accesses** are there, before **Error Log**. |
| 3 | As staff, open the App Launcher and type `Portal`. | No portal page is listed (only Portal Builder Admin shows them). |

## T-APP-11: Corporate Hub in BarnCRM Members and Partners

**Purpose:** confirm Corporate Hub alone fills BarnCRM Members and Partners with every Corporate Hub page.
**Prerequisites:** an org with Corporate Hub and without Memberships; admin user; staff user with the Team Member role (so Corporate Hub Staff).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Members`. | **BarnCRM Members and Partners** is listed with Patch wearing a green Member sash. |
| 2 | Open it and its navigation menu. | Console navigation with the Barn Navy header. It opens on **Corporate Hub Home**. Tabs: **Corporate Hub Home**, **Library Documents**, **Compliance Obligations**, **Agreements**, **Boards and Committees**, **Board Meetings**, **Processing Activities**, **Data Subject Requests**, **Data Breaches**, **Reports**, **Dashboards**, **Error Log** (last). |
| 3 | Open **Board Meetings** and a meeting. | It opens on the Board Meeting record page with its panel. |
| 4 | Open **BarnCRM Console**. | No Corporate Hub page is listed. |
| 5 | As staff, open the App Launcher and type `Members`. | **BarnCRM Members and Partners** is listed. A user with neither a Corporate Hub nor a Memberships permission set does not see it. |

## T-APP-12: BarnCRM Projects

**Purpose:** confirm the Project Management app holds every Project Management page.
**Prerequisites:** admin user; staff user with the Team Member role (so Projects Staff).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Projects`. | **BarnCRM Projects** is listed with Patch in a hard hat, holding a clipboard. |
| 2 | Open it and its navigation menu. | Console navigation with the Barn Navy header. Tabs: **Projects Home**, **Timesheet**, **Approvals**, **Requests**, **Projects**, **Time Entries**, **Project Expenses**, **Project Resources**, **Staffing**, **Project Rates**, **Project Invoices**, **Request Connections**, **Reports**, **Error Log** (last). |
| 3 | Open a project. | It opens on the project record page with its board. |
| 4 | Open **BarnCRM Admin Console**. | **Project Rates**, **Project Invoices** and **Request Connections** are there too, before **Error Log**. |
| 5 | As staff, open the App Launcher and type `Projects`. | **BarnCRM Projects** is listed. |

## T-APP-13: A Scratch or Developer Edition Org Gets Every App

**Purpose:** confirm a capped org (about 10 custom apps) deploys all nine apps.
**Prerequisites:** a scratch org deployed with `scripts/org/deploy-packages.sh` (for example
`barn-sales`).

| Step | Action | Expected result |
|---|---|---|
| 1 | Read the deploy output. | No "leaving out the apps of" line and no "Permission sets without the left-out module apps" stage. |
| 2 | As admin, open the App Launcher and type `BarnCRM`. | The nine apps of T-APP-02 are listed. |

## T-APP-14: Memberships in BarnCRM Members and Partners

**Purpose:** confirm Memberships fills BarnCRM Members and Partners and comes first when Corporate Hub is installed too.
**Prerequisites:** an org with Memberships and Corporate Hub; admin user; staff user with the Team Member role (so Memberships Staff).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open **BarnCRM Members and Partners** and its navigation menu. | It opens on **Memberships Home**. Tabs: **Memberships Home**, **Memberships**, **Member Certifications**, **Membership Levels**, **Certifications**, then the Corporate Hub pages of T-APP-11, **Reports**, **Dashboards**, **Error Log** (last). |
| 2 | Open a membership. | It opens as a workspace tab on the membership record page. |
| 3 | Open **BarnCRM Admin Console**. | **Membership Levels** and **Certifications** are there too, before **Error Log**. |
| 4 | Open **BarnCRM Fundraising**, **BarnCRM Grants**, **BarnCRM Programs** and **BarnCRM Volunteers**. | None lists a Memberships or Corporate Hub page. |
| 5 | On BarnCRM Home, find Memberships under **Modules**. | Its **Open the App** link opens **BarnCRM Members and Partners**. |
| 6 | As staff, open the App Launcher and type `Members`. | **BarnCRM Members and Partners** is listed. |

## T-APP-15: Scholarships in BarnCRM Grants

**Purpose:** confirm Scholarships and Outbound Grants joins the Grants app after the grant pages and stays in BarnCRM Console, so Scholarships-only staff keep an app.
**Prerequisites:** admin user; staff user with Scholarships Staff and no Grants permission set; an org with Grants and Scholarships and Outbound Grants.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open **BarnCRM Grants** and its navigation menu. | It opens on **Grants Home**. After the grant pages: **Scholarships Home**, **Award Programs**, **Award Applications**, **Awards**, then **Reports**, **Dashboards**, **Error Log** (last). |
| 2 | Open an award application. | It opens as a workspace tab on the application record page. |
| 3 | Open **Dashboards**. | The Scholarships and Grants dashboard is listed. |
| 4 | On BarnCRM Home, find Scholarships and Outbound Grants under **Modules**. | Its **Open the App** link opens **BarnCRM Grants**. |
| 5 | Open **BarnCRM Console**. | **Scholarships Home**, **Award Programs**, **Award Applications** and **Awards** are there, after **Data Manager**. |
| 6 | As the staff user, open the App Launcher and type `BarnCRM`. | **BarnCRM Console** is listed and has the Scholarships pages; **BarnCRM Grants** is not listed. |

## T-APP-16: Module Quick Links Keep Their Words

**Purpose:** confirm the module quick links show the same one-line descriptions now that the words come from Core's help catalog (D-208).
**Prerequisites:** admin; Fundraising, Volunteers and Programs installed and turned on.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM Console** home page and look at **Quick Links**. | **Enter a Gift** reads "Record a gift in a few keystrokes.", **Log Hours** reads "Hours a volunteer worked, in one short form." and **Enroll** reads "Start someone in a program." No tile shows a key such as `Core_HubHome_QuickLinkEnterGiftLine`. |
| 2 | Turn Volunteers off in the Module Manager and reload the home page. | **Log Hours** is gone; the other two keep their words. Turn Volunteers back on. |


## T-APP-17: Every Module App Opens on Its Home

**Purpose:** confirm each module app's first tab is its home, named `<Module> Home`, with the same layout (ADR-0236, Module Home pattern).
**Prerequisites:** a production org or sandbox (`mwdbdevsb`) with the modules installed and on; admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open each module app from the App Launcher. | The first tab and the page title are: BarnCRM Events, **Events Home**; BarnCRM Fundraising, **Fundraising Home**; BarnCRM Grants, **Grants Home**; BarnCRM Members and Partners, **Memberships Home** (or **Corporate Hub Home** without Memberships); BarnCRM Programs, **Programs Home**; BarnCRM Projects, **Projects Home**; BarnCRM Volunteers, **Volunteers Home**. **Error Log** is still the last tab of each app that has it. |
| 2 | On each home, look at the page. | The title and About This Tool at the top, the module's quick actions at the top right, then figures, then the module's lists. |
| 3 | Open **BarnCRM Admin Console**. | It carries **Forms Home** and **Portal Builder Home**, and **Super Connector** with BarnCRM Connector installed. |

## T-APP-18: BarnCRM Fundraising Is a Console App

**Purpose:** confirm Fundraising opens records in tabs and keeps its utility bar.
**Prerequisites:** Fundraising installed; staff user with the Fundraising Staff role.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **BarnCRM Fundraising** and its navigation menu. | Console navigation with the Barn Navy header. Tabs: **Fundraising Home**, **Quick Gift Entry**, **Contacts**, **Households**, **Organizations**, **Gifts**, **Commitments**, **Ask Pipeline**, **Gift Batches**, **Receipts**, **Stewardship Plans**, **Acknowledgments**, **Reports**. **Quick Gift Entry** is in the utility bar at the bottom. |
| 2 | Open **Gifts** and a gift, then its donor. | The gift opens in a workspace tab on the gift page; the donor opens beside it. |
| 3 | Open the App Launcher and type `Fundraising`. | One **BarnCRM Fundraising** app. |
