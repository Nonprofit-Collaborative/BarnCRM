# Apps and Navigation

Scripts for the four BarnCRM apps and the **App Navigation Style** setting. Setup detail:
[The BarnCRM Apps and Navigation](../admin-guide/barncrm-app.md).

Before you start: an org from [Before you test](before-you-test.md), with the staff user from
[Test users](before-you-test.md#test-users). After a role or setting change, BarnCRM gives and
takes the apps in a queued job: wait a minute and reload before checking the App Launcher.

## T-APP-01: Each App Shows the Right Tabs to the Right People

**Purpose:** confirm the everyday apps go to every BarnCRM role, the admin apps to admins only, and each app holds its own tabs.
**Prerequisites:** admin user and staff user. **App Navigation Style** is **Both (each person chooses)**.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `BarnCRM`. | **BarnCRM**, **BarnCRM Console**, **BarnCRM Admin** and **BarnCRM Admin Console** are listed, each with the blue barn logo; the two admin apps' barn carries a navy gear badge. With the modules deployed, **Fundraising** shows the barn with a red heart badge and **BarnCRM Volunteers** with a green person badge. |
| 2 | Open **BarnCRM**. | Standard navigation (tabs across the top, no workspace tabs). Tabs: **Home**, **Contacts**, **Households**, **Organizations**, **Find**. |
| 3 | Open a household. | It replaces the page and shows the BarnCRM household page. |
| 4 | Open **BarnCRM Console** and its navigation menu (the arrow next to the app name). | **Home**, **Contacts**, **Households**, **Organizations**, **Find**, **Addresses**, **Relationships**, **Affiliations**, **Household Members**. |
| 5 | Open a household, then one of its addresses. | The household opens in its own tab; the address opens as a subtab under it. |
| 6 | Open **BarnCRM Admin**. | Standard navigation, with a navy header. Tabs: **BarnCRM Settings**, **Data Manager**, **Import**, **Bulk Update**, **Org Optimizer**, **Duplicate Matching**, **Error Log**. It opens on **BarnCRM Settings**. |
| 7 | Open **BarnCRM Admin Console** and its navigation menu. | The same seven tabs, opening as workspace tabs. |
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
| 2 | As admin, open **BarnCRM Admin**. | After **Error Log**: **Rollup Builder**, **Accounting Periods**, **Giving Nightly Jobs**, **Donor Level Ladder**, **Stewardship Plan Setup**, then **Campaign Sync**, **Opportunity Mirror** and **Accounting Export**. Volunteers adds no admin page (its settings are the **Volunteers** section of **BarnCRM Settings**). **BarnCRM Admin Console** has the same. |
| 3 | Open **BarnCRM**. | After **Find**: **Quick Gift Entry**, **Gifts**, **Commitments**, **Gift Batches** (and **Volunteer Shifts**, **Volunteer Hours** with Volunteers). |
| 4 | In **BarnCRM**, open a gift from **Gifts**. | The gift opens on the same record page as in **Fundraising**. |
| 5 | Open **BarnCRM Console**, then a gift from **Gifts**. | The gift opens in a console tab. |
| 6 | From the App Launcher, search for "BarnCRM Rollup Builder". | No such app is listed; the **Rollup Builder** tab is. |
| 7 | Open **BarnCRM**, **Home**, **Setup Checklist**, **Modules**. | Under **BarnCRM Giving**: "Add to BarnCRM and BarnCRM Console: Quick Gift Entry, Gifts, Commitments, Gift Batches" and "Add to BarnCRM Admin and BarnCRM Admin Console: Accounting Periods, Giving Nightly Jobs, Donor Level Ladder, Stewardship Plan Setup", then the App Manager steps. A module not installed lists no pages. |
| 8 | On the **BarnCRM Console** home page, look at **Modules**. | **BarnCRM Giving** has an **Open the app** link that opens **Fundraising**; **BarnCRM Rollup Builder** has none. |
| 9 | As staff, open **BarnCRM**. | The Giving pages show only if the staff user's access allows them; no admin page is listed. |

**Cleanup:** none.
