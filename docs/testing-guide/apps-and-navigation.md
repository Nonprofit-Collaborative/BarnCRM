# Apps and Navigation

Scripts for the four BarnCRM apps, the module apps and the **App Navigation Style** setting. Setup detail:
[The BarnCRM Apps and Navigation](../admin-guide/barncrm-app.md).

Before you start: an org from [Before you test](before-you-test.md), with the staff user from
[Test users](before-you-test.md#test-users). After a role or setting change, BarnCRM gives and
takes the apps in a queued job: wait a minute and reload before checking the App Launcher.

## T-APP-01: Each App Shows the Right Tabs to the Right People

**Purpose:** confirm the everyday apps go to every BarnCRM role, the admin apps to admins only, and each app holds its own tabs.
**Prerequisites:** admin user and staff user. **App Navigation Style** is **Both (each person chooses)**.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `BarnCRM`. | **BarnCRM**, **BarnCRM Console**, **BarnCRM Admin** and **BarnCRM Admin Console** are listed, each with the blue barn logo; the two admin apps' barn carries a navy gear badge. With the modules deployed, **BarnCRM Fundraising** shows the barn with a berry heart badge, **BarnCRM Volunteers** a green person badge, **BarnCRM Programs** a purple sprout badge and **BarnCRM Funders** a bronze award ribbon badge. There is no **BarnCRM Logic Models** app (retired in release 1.24). No app shows a generic initials tile. |
| 2 | Open **BarnCRM**. | Standard navigation (tabs across the top, no workspace tabs). Tabs: **Home**, **Contacts**, **Households**, **Organizations**, **Data Manager**. **Find** is not in the navigation. |
| 3 | Open a household. | It replaces the page and shows the BarnCRM household page. |
| 4 | Open **BarnCRM Console** and its navigation menu (the arrow next to the app name). | **Home**, **Contacts**, **Households**, **Organizations**, **Addresses**, **Relationships**, **Affiliations**, **Household Members**, **Data Manager**. |
| 5 | Open a household, then one of its addresses. | The household opens in its own tab; the address opens as a subtab under it. |
| 6 | Open **BarnCRM Admin**. | Standard navigation, with a navy header. Tabs: **BarnCRM Settings**, **Data Manager**, **Org Optimizer**, **Duplicate Matching**, **Automation**, **Error Log** (last). **Super Importer**, **Super Transformer** and **Import Rows** are not in the navigation. It opens on **BarnCRM Settings**. |
| 7 | Open **BarnCRM Admin Console** and its navigation menu. | The same five tabs, opening as workspace tabs, with **Error Log** last. With a module deployed (for example the Rollup Builder), its admin tabs come before **Error Log**. |
| 8 | As staff, open the App Launcher and type `BarnCRM`. | **BarnCRM** and **BarnCRM Console** are listed. **BarnCRM Admin** and **BarnCRM Admin Console** are not. |
| 9 | As admin, on **BarnCRM Settings**, **Access**, remove the staff user's role. Wait a minute; as staff, reload and open the App Launcher. | No BarnCRM app is listed. |

**Cleanup:** give the staff user its role back on the Access page.

## T-APP-02: App Navigation Style Hides the Other Style for Everyone

**Purpose:** confirm the setting shows only one style's apps, defaults to Both, and records the change.
**Prerequisites:** admin user and staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open **BarnCRM Admin**, **BarnCRM Settings**, **General**. | An **App Navigation Style** row shows **Both (each person chooses)**, never blank, with a description and a **Learn More** link. |
| 2 | Choose **Console navigation only** and click **Save**. | "Your settings are saved." **Recent changes** shows **App Navigation Style**, old value Both, new value Console. |
| 3 | Wait a minute, reload, and open the App Launcher. | **BarnCRM Console** and **BarnCRM Admin Console** are listed; **BarnCRM** and **BarnCRM Admin** are not. |
| 4 | As staff, reload and open the App Launcher. | Only **BarnCRM Console** is listed. |
| 5 | As admin, in **BarnCRM Admin Console**, set **App Navigation Style** to **Standard navigation only** and save. Wait a minute and reload. | Only **BarnCRM** and **BarnCRM Admin** are listed for the admin, only **BarnCRM** for staff. |
| 6 | Set it to **Both (each person chooses)** and save. Wait a minute and reload. | All four apps are back for the admin, both everyday apps for staff. |

**Cleanup:** leave **App Navigation Style** on **Both (each person chooses)**.

## T-APP-03: Module Pages Reach the BarnCRM Apps

**Purpose:** confirm a source deploy adds each deployed module's pages to the Core apps, the Setup Assistant lists them for a package install, and the home page links each module app.
**Prerequisites:** an org deployed with `scripts/org/deploy-packages.sh` (Core, Rollup Builder, Giving, Mirror, and Volunteers when it ships metadata); admin user and staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Read the deploy output. | A stage "Module tabs in the BarnCRM apps" ran and succeeded. |
| 2 | As admin, open **BarnCRM Admin**. | Before **Error Log**, which stays the last tab: **Rollup Builder**, **Accounting Periods**, **Donor Level Ladder**, **Stewardship Plan Setup**, **Pledge Reminders**, **Receipt Letters**, then **Campaign Sync**, **Opportunity Mirror** and **Accounting Export**. Volunteers adds no admin page (its settings are the **Volunteers** section of **BarnCRM Settings**). **BarnCRM Admin Console** has the same. |
| 3 | Open **BarnCRM**. | After **Find**: **Quick Gift Entry**, **Gifts**, **Commitments**, **Gift Batches** (and **Volunteer Shifts**, **Volunteer Hours** with Volunteers). |
| 4 | In **BarnCRM**, open a gift from **Gifts**. | The gift opens on the same record page as in **BarnCRM Fundraising**. |
| 5 | Open **BarnCRM Console**, then a gift from **Gifts**. | The gift opens in a console tab. |
| 6 | From the App Launcher, search for "BarnCRM Rollup Builder". | No such app is listed; the **Rollup Builder** tab is. |
| 7 | Open **BarnCRM**, **Home**, **Setup Checklist**, **Modules**. | Under **BarnCRM Giving**: "Add to BarnCRM and BarnCRM Console: Quick Gift Entry, Gifts, Commitments, Gift Batches" and "Add to BarnCRM Admin and BarnCRM Admin Console: Accounting Periods, Donor Level Ladder, Stewardship Plan Setup, Pledge Reminders, Receipt Letters", then the App Manager steps. A module not installed lists no pages. |
| 8 | On the **BarnCRM Console** home page, look at **Modules**. | **BarnCRM Giving** has an **Open the App** link that opens **BarnCRM Fundraising**; **BarnCRM Rollup Builder** has none. |
| 9 | As staff, open **BarnCRM**. | The Giving pages show only if the staff user's access allows them; no admin page is listed. |

**Cleanup:** none.

## T-APP-04: Tab Icons Match Their Pages, and Each Page Name Shows Once

**Purpose:** confirm each Core page shows an icon that fits it, the same in the navigation, the page header and the console tab, and prints its name once.
**Prerequisites:** admin user. Open **BarnCRM Admin Console**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**. | The page header shows a gear, as do the console tab and the settings card. No airplane. |
| 2 | Open **Data Manager**. | Building blocks in the page header. The name **Data Manager** shows once, in the page header; below it the first line is "Start a data task, or see and undo what changed." with no second **Data Manager** title. |
| 3 | On **Data Manager**, click the **Super Importer** tile. | The **Super Importer** page header shows a form (a document), not an alarm clock. The page name shows once; the wizard starts straight under the header. |
| 4 | Back on **Data Manager**, click the **Find** tile, then go back and click the **Super Transformer** tile. | The first opens **Find**, with a telescope in the page header and the name **Find** once, followed by its purpose line. The second opens **Super Transformer**, its name once, followed by "Change many records at once, without a file, and undo it if needed." |
| 5 | Open **Org Optimizer**, then **Duplicate Matching**. | A stethoscope, then scales, in the page header. Each name shows once, followed by its purpose line and then the tabs. |
| 6 | Open **Error Log**. | A bell in the page header, not a trophy. **Error Log** is the last tab in the navigation menu. |
| 7 | Open **BarnCRM Console**, then **Households**, **Organizations** and an address. | People for households, a building for organizations, a map for the address. |

**Cleanup:** none.

## T-APP-05: Home Works From the First Day, on Any Screen

**Purpose:** confirm the Households quick link, the setup checklist on a phone, the first-run
window's close button and the Storage and Limits icon.
**Prerequisites:** admin; a staff user who has never opened **Households** (a new user is
best); for step 5, an org where first-run setup is not finished.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the new staff user, open the **BarnCRM** home page and click the **Households** quick link. | The households list opens, even though the user has no **Households** tab yet. |
| 1a | Still as staff, look at the welcome and **Quick Links**, then click **New Person**. | The welcome reads "Find someone, add someone new, or pick up where you left off." Quick links are **People**, **Households**, **Organizations** and **Find** (plus **Import a File** for someone who can import, **Enter a Gift** with Giving, **Log Hours** with Volunteers and **Enroll** with Programs, each only while its module is installed and on), with no **BarnCRM Settings**. **Enroll** opens a new enrollment; turn Programs off in the Module Manager and reload: **Enroll** is gone. **New Person** opens the new contact form; save a person and a household is made for them. As admin, **BarnCRM Settings** is also listed. |
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
| 2 | As staff, open **BarnCRM**. | **Households** and **Organizations** show; **Accounts** does not. |
| 3 | As admin, choose **Accounts Tab (Standard)** and **Save**. Wait a minute. | "Your settings are saved." **Recent changes** shows the change. |
| 4 | As staff, reload **BarnCRM** and **BarnCRM Console**. | **Accounts** shows after **Contacts**; **Households** and **Organizations** are gone from both apps and the App Launcher. In **Accounts**, the list view menu holds **Households**, **My Households**, **Organizations** and **My Organizations**. |
| 5 | As admin, choose **Both** and save; wait a minute; as staff, reload. | **Households**, **Organizations** and **Accounts** all show. |
| 6 | As admin, choose **Organization and Household Tabs** and save; wait; as staff, reload. | Back to step 2: no **Accounts** tab. |

**Cleanup:** leave **Account Tabs** on **Organization and Household Tabs**.

## The Module Apps (T-APP-08 to T-APP-13)

Event Management, Forms, Portal Builder, Corporate Hub and Project Management each have an app
of their own, and their tabs stay in the BarnCRM apps too. Run T-APP-08 to T-APP-12 on a
production org or sandbox (`mwdbdevsb`): a scratch or Developer Edition org does not get these
five apps (T-APP-13). In each, the module is installed and on, and its access sync has run
(**Finish Setup**, or wait an hour).

## T-APP-08: BarnCRM Events

**Purpose:** confirm the Event Management app, its tabs and who sees it.
**Prerequisites:** admin user; staff user with the Team Member role (so Events Staff).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Events`. | **BarnCRM Events** is listed with the barn and a teal calendar badge. |
| 2 | Open it and its navigation menu. | Console navigation with the blue header. Tabs: **Events Home**, **Event Calendar**, **Events**, **Event Speakers**, **Venues**, **Reports**, **Error Log** (last). |
| 3 | Open an event from **Events**. | It opens as a workspace tab on the event record page (with its tabs), the same page as in **BarnCRM**. |
| 4 | Open **BarnCRM**. | **Events Home**, **Event Calendar**, **Events**, **Event Speakers** and **Venues** are still there, after **Data Manager**. |
| 5 | As staff, open the App Launcher and type `Events`. | **BarnCRM Events** is listed. A user with no Events permission set does not see it. |

## T-APP-09: BarnCRM Forms

**Purpose:** confirm the Forms app, its tabs and who sees it.
**Prerequisites:** admin user; staff user with the Team Member role (so Forms Staff).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Forms`. | **BarnCRM Forms** is listed with the barn and a blue form page badge. |
| 2 | Open it and its navigation menu. | Console navigation with the blue header. Tabs: **Forms**, **Form Submissions**, **Reports**, **Error Log** (last). |
| 3 | Open a form. | It opens on the form record page with its builder, the same page as in **BarnCRM**. |
| 4 | Open **BarnCRM**. | **Forms** and **Form Submissions** are still there, after **Data Manager**. |
| 5 | As staff, open the App Launcher and type `Forms`. | **BarnCRM Forms** is listed. |

## T-APP-10: BarnCRM Portal Builder

**Purpose:** confirm the Portal Builder app is an admin app with its tabs.
**Prerequisites:** admin user; staff user without the BarnCRM Admin role.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Portal`. | **BarnCRM Portal Builder** is listed with the barn and a purple door badge. |
| 2 | Open it and its navigation menu. | Console navigation with the navy admin header. Tabs: **Portals**, **Portal Accesses**, **Reports**, **Error Log** (last). |
| 3 | Open **BarnCRM Admin**. | **Portals** and **Portal Accesses** are still there, before **Error Log**. |
| 4 | As staff, open the App Launcher and type `Portal`. | **BarnCRM Portal Builder** is not listed (only Portal Builder Admin shows it). |

## T-APP-11: BarnCRM Corporate Hub

**Purpose:** confirm the Corporate Hub app holds every Corporate Hub page.
**Prerequisites:** admin user; staff user with the Team Member role (so Corporate Hub Staff).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Corporate`. | **BarnCRM Corporate Hub** is listed with the barn and a slate office building badge. |
| 2 | Open it and its navigation menu. | Console navigation with the blue header. Tabs: **Corporate Hub**, **Library Documents**, **Compliance Obligations**, **Agreements**, **Boards and Committees**, **Board Meetings**, **Processing Activities**, **Data Subject Requests**, **Data Breaches**, **Reports**, **Dashboards**, **Error Log** (last). |
| 3 | Open **Board Meetings** and a meeting. | It opens on the Board Meeting record page with its panel. |
| 4 | Open **BarnCRM**. | The first six tabs are still there after **Data Manager**; the three data protection tabs are not. |
| 5 | As staff, open the App Launcher and type `Corporate`. | **BarnCRM Corporate Hub** is listed. |

## T-APP-12: BarnCRM Projects

**Purpose:** confirm the Project Management app holds every Project Management page.
**Prerequisites:** admin user; staff user with the Team Member role (so Projects Staff).

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `Projects`. | **BarnCRM Projects** is listed with the barn and a blue task board badge. |
| 2 | Open it and its navigation menu. | Console navigation with the blue header. Tabs: **Projects Home**, **Timesheet**, **Approvals**, **Requests**, **Projects**, **Time Entries**, **Project Expenses**, **Project Resources**, **Staffing**, **Project Rates**, **Project Invoices**, **Request Connections**, **Reports**, **Error Log** (last). |
| 3 | Open a project. | It opens on the project record page with its board. |
| 4 | Open **BarnCRM**. | The Project Management tabs are still there, after **Data Manager**. |
| 5 | As staff, open the App Launcher and type `Projects`. | **BarnCRM Projects** is listed. |

## T-APP-13: A Scratch or Developer Edition Org Gets No Module Apps

**Purpose:** confirm a capped org deploys without the five module apps and keeps their tabs.
**Prerequisites:** a scratch org deployed with `scripts/org/deploy-packages.sh` (for example
`barn-sales`).

| Step | Action | Expected result |
|---|---|---|
| 1 | Read the deploy output. | It says "Capped org (scratch or Developer Edition): leaving out the apps of events forms portal corporatehub projects", and a "Permission sets without the left-out module apps" stage succeeds. |
| 2 | As admin, open the App Launcher and type `BarnCRM`. | No **BarnCRM Events**, **BarnCRM Forms**, **BarnCRM Portal Builder**, **BarnCRM Corporate Hub** or **BarnCRM Projects**. The other BarnCRM apps are listed. |
| 3 | Open **BarnCRM**, then **BarnCRM Admin**. | The Event Management, Forms, Corporate Hub and Project Management tabs are in **BarnCRM**; **Portals** and **Portal Accesses** are in **BarnCRM Admin**. |
| 4 | As staff, open **Events Home**. | It opens: the Events permission sets deployed without the app. |
