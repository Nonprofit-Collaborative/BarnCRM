# Apps and navigation

Scripts for the four BarnCRM apps and the **App Navigation Style** setting. Setup detail:
[The BarnCRM apps and navigation](../admin-guide/barncrm-app.md).

Before you start: an org from [Before you test](before-you-test.md), with the staff user from
[Test users](before-you-test.md#test-users). After a role or setting change, BarnCRM gives and
takes the apps in a queued job: wait a minute and reload before checking the App Launcher.

## T-APP-01: Each app shows the right tabs to the right people

**Purpose:** confirm the everyday apps go to every BarnCRM role, the admin apps to admins only, and each app holds its own tabs.
**Prerequisites:** admin user and staff user. **App Navigation Style** is **Both (each person chooses)**.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the App Launcher and type `BarnCRM`. | **BarnCRM**, **BarnCRM Console**, **BarnCRM Admin** and **BarnCRM Admin Console** are listed, each with the blue barn logo; the two admin apps' barn carries a navy gear badge. With the modules deployed, **Fundraising** shows the barn with a red heart badge and **BarnCRM Volunteers** with a green person badge. |
| 2 | Open **BarnCRM**. | Standard navigation (tabs across the top, no workspace tabs). Tabs: **Home**, **Contacts**, **Households**, **Organizations**, **Find**. |
| 3 | Open a household. | It replaces the page and shows the BarnCRM household page. |
| 4 | Open **BarnCRM Console** and its navigation menu (the arrow next to the app name). | **Home**, **Contacts**, **Households**, **Organizations**, **Find**, **Addresses**, **Relationships**, **Affiliations**, **Household Members**. |
| 5 | Open a household, then one of its addresses. | The household opens in its own tab; the address opens as a subtab under it. |
| 6 | Open **BarnCRM Admin**. | Standard navigation, with a navy header. Tabs: **BarnCRM Settings**, **Data Manager**, **Import**, **Bulk Update**, **Org Optimizer**, **Error Log**. It opens on **BarnCRM Settings**. |
| 7 | Open **BarnCRM Admin Console** and its navigation menu. | The same six tabs, opening as workspace tabs. |
| 8 | As staff, open the App Launcher and type `BarnCRM`. | **BarnCRM** and **BarnCRM Console** are listed. **BarnCRM Admin** and **BarnCRM Admin Console** are not. |
| 9 | As admin, on **BarnCRM Settings**, **Access**, remove the staff user's role. Wait a minute; as staff, reload and open the App Launcher. | No BarnCRM app is listed. |

**Cleanup:** give the staff user its role back on the Access page.

## T-APP-02: App Navigation Style hides the other style for everyone

**Purpose:** confirm the setting shows only one style's apps, defaults to Both, and records the change.
**Prerequisites:** admin user and staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open **BarnCRM Admin**, **BarnCRM Settings**, **General**. | An **App Navigation Style** row shows **Both (each person chooses)**, never blank, with a description and a **Learn more** link. |
| 2 | Choose **Console navigation only** and click **Save**. | "Your settings are saved." **Recent changes** shows **App Navigation Style**, old value Both, new value Console. |
| 3 | Wait a minute, reload, and open the App Launcher. | **BarnCRM Console** and **BarnCRM Admin Console** are listed; **BarnCRM** and **BarnCRM Admin** are not. |
| 4 | As staff, reload and open the App Launcher. | Only **BarnCRM Console** is listed. |
| 5 | As admin, in **BarnCRM Admin Console**, set **App Navigation Style** to **Standard navigation only** and save. Wait a minute and reload. | Only **BarnCRM** and **BarnCRM Admin** are listed for the admin, only **BarnCRM** for staff. |
| 6 | Set it to **Both (each person chooses)** and save. Wait a minute and reload. | All four apps are back for the admin, both everyday apps for staff. |

**Cleanup:** leave **App Navigation Style** on **Both (each person chooses)**.
