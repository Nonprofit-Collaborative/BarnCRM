# Settings and Module Manager

Scripts for the BarnCRM Settings console, Access, the Module Manager, Automation, Features, the edition, Custom metadata, the Error Log tile and the BarnCRM home page. Setup detail: [BarnCRM Settings](../admin-guide/barncrm-settings.md).

Before you start: an org from [Before you test](before-you-test.md), with every module deployed, the Nonprofit Edition chosen, every feature turned on in first-run setup, and sample data loaded unless a script says otherwise. Create the staff and read-only users from [Test users](before-you-test.md#test-users) first. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data and no module: skip the scripts that need a module, a staff user or the Nonprofit Edition, and put back any setting you change.

The BarnCRM Admin role card on the Access page is headed **BarnCRM Admin**, the role's label in Salesforce (its API name stays `BarnCRM_Admin_Group`).

## T-SET-01: Open the Settings Console

**Purpose:** confirm the console opens with its sections, descriptions, Learn More links and Recent Changes.
**Prerequisites:** admin user (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | From the App Launcher, open the **BarnCRM Admin** app and click the **BarnCRM Settings** tab. | The page name **BarnCRM Settings** shows once, in the page header, with the line "Choose how BarnCRM works for your whole organization." under it. A **Search settings** box and the section list are on the left; the first section shows on the right. No read-only notice is shown. |
| 2 | Read the section list. | Sections sit under group headings, each with an icon: **Organization** (**General**, **Organization**), **People** (**People and Households**, **Addresses**), **Data** (**Import**, **Duplicate Matching**, **Rollups** with Rollup Builder installed, **Org Optimizer**), **Fundraising** (**Giving** and **Receipts** with Giving installed), **Programs** (**Volunteers** with Volunteers installed) and **System** (**Modules**, **Access**, **Automation**, **Integrations**, **Health**, **Error Log**). **Error Log** is the last item. A Core-only org has no Fundraising or Programs group. |
| 3 | Click **General**. | **Edition**, **Features**, **Sample Data**, **Custom Metadata** and the setting rows show. No description is printed under a row: each row has an info icon, and clicking it shows the plain description. Unless a Custom Metadata save has already worked here, a **Needs a Change in Setup** note at the top shows one line, an **Open in Setup** button and **Show Steps** (T-SET-20). No note asks you to match a fiscal year: **Fiscal year start month** is a read-only row (T-SET-15). In **Features**, no description says "tab" or "Data Hygiene". |
| 4 | Click **Learn More** beside the info icon of any setting. | **Learn More** stands apart from any text, with a new-window icon. A new browser tab opens the matching admin-guide page on GitHub. The console tab is unchanged. |
| 5 | Scroll to the bottom of the page. | A **Recent Changes** heading with a table (columns **Setting**, **Old Value**, **New Value**, **Changed By**, **Changed At**), or "No settings have been changed yet. Every change you make is listed here." |
| 6 | In a console app, look at the workspace tab label. | The tab reads **BarnCRM Settings: General** (the open section). |
| 7 | Click **People and Households**, then scroll to the bottom of the page. | There is no **Recent Changes** heading or table on **People and Households**. Click **Automation**, **Access** and **Organization** in turn: none shows **Recent Changes**. |
| 8 | Type `greeting` in **Search settings** and click **Formal greeting pattern**. | The console switches to **People and Households**, and **Recent Changes** is still not shown. Click **General**: **Recent Changes** shows again. |

**Cleanup:** None.

## T-SET-02: Search for a Setting

**Purpose:** confirm search finds a setting by word and jumps to it, and says so when nothing matches.
**Prerequisites:** admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**. Type `greeting` in **Search settings**. | A **Search Results** list appears as you type. It includes **Formal greeting pattern (People and Households)** and **Informal greeting pattern (People and Households)**. |
| 2 | Click **Formal greeting pattern**. | The console switches to **People and Households** and scrolls to the **Preview and Recompute** panel. |
| 3 | Clear the box and type `pause`. | The **Automation** section's entry is listed. |
| 4 | Clear the box and type `zzqx`. | "No settings match that search. Try a shorter word, for example greeting." |

**Cleanup:** None.

## T-SET-03: Save a Setting, See It in Recent Changes, Discard and Refuse a Bad Value

**Purpose:** confirm saves are recorded, unsaved edits can be discarded, and out-of-range numbers are refused.
**Prerequisites:** admin user. Note the current value of **Days to keep Error Log entries** (180 by default).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Error Log**. Change **Days to keep Error Log entries** to `90`. | A bar docks to the bottom of the screen: "1 unsaved change", **Discard** and **Save**. Change **Digest frequency** too: the bar says "2 unsaved changes". |
| 2 | Click **Discard**. | Both values return to what they were and the bar goes away. Nothing is added to **Recent Changes** (shown on **General** only). |
| 3 | Change the value to `5000` and click **Save**. | The box is marked as out of range and the page says "A number is outside the range its setting takes, so nothing was saved. Correct the marked value and save again." |
| 4 | Change the value to `90` and click **Save**. | "Your settings are saved." Open **General**: the top row of **Recent Changes** shows **Days to keep Error Log entries**, old value 180, new value 90, your name and the time. |
| 5 | Open **Error Log** without changing anything, then open **General**. | No save bar shows while nothing is unsaved, and no new row appears in **Recent Changes**. |
| 6 | Reload the page and open **Error Log**. | The box shows 90. |

**Cleanup:** set **Days to keep Error Log entries** back to 180 and save.

## T-SET-04: Give and Remove a Role on the Access Page

**Purpose:** confirm a role can be given and taken away from the app, with a confirmation each time.
**Prerequisites:** admin user (a System Administrator, so it can assign permission sets). The staff user exists; if it already holds **Read Only**, remove it first.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Access**. | A card titled **Access** shows one card per role: **BarnCRM Admin**, **Team Member**, **Read Only**, and **Fundraising Staff** with Giving. No **Coordinator** card. Each heading ends with a count in brackets. |
| 2 | In **Find a person**, type `Staff`. | **Staff Tester** is listed with an email address. |
| 3 | Choose **Staff Tester**. In **Role**, choose **Read Only**. Click **Give Access**. | A dialog titled **Give Access** asks "Give Staff Tester the Read Only role?" with **Give Access** and **Cancel**. |
| 4 | Click **Cancel**. | The dialog closes and nothing changes. |
| 5 | Click **Give Access** again and confirm with **Give Access**. | A **Done** toast: "Staff Tester now has the Read Only role." **Staff Tester** appears on the **Read Only** card and its count goes up by one. |
| 6 | Click **Remove** beside **Staff Tester** on the **Read Only** card. | A dialog titled **Remove Access**: "Remove the Read Only role from Staff Tester? Any other role they hold stays in place." |
| 7 | Click **Remove**. | "Staff Tester no longer has the Read Only role." The name leaves the card. **Staff Tester** is still on the **Team Member** card. |
| 8 | Click **Create a User in Setup**. | Setup, Users opens in a new tab. |
| 9 | Back on **Access**, read the **Needs a Change in Setup** note. | It says "Core's extra permissions and every permission set a module lists here are given on this page; any other is assigned in Setup.", numbers three steps starting "Click the module's permission set.", and has **Open in Setup**. |

**Cleanup:** None.

## T-SET-05: Extra Permissions, and the Last Admin Is Protected

**Purpose:** confirm an extra permission is given with its warning and removed, and the last BarnCRM Admin cannot be removed.
**Prerequisites:** admin user, the only person on the **BarnCRM Admin** card (if the card is empty, give yourself the role first, as in T-SET-04). The staff user does not hold **BarnCRM Bulk Delete**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Access**. Scroll to **Extra Permissions**. | One card each for **BarnCRM Find and Export**, **BarnCRM Bulk Update**, **BarnCRM Bulk Delete**, **BarnCRM Erase People**, **BarnCRM Duplicate Review** and **BarnCRM Metadata Admin**, then the Giving and Mirror sets. Bulk Delete and Erase People carry the warning "This permission lets the person remove data. Give it only to someone you trust to do that." |
| 2 | Choose **Staff Tester** in **Find a person**. In **Extra permission**, choose **BarnCRM Bulk Delete**. | Under the picker: "Delete many records at once from a Find query, with undo from the Recycle Bin. Includes Find and Export, so nothing else is needed." and the remove-data warning. |
| 3 | Click **Give Permission**. | The dialog asks "Give Staff Tester the BarnCRM Bulk Delete permission?" and repeats the warning. |
| 4 | Confirm with **Give Permission**. | "Staff Tester now has the BarnCRM Bulk Delete permission." The name appears on the **BarnCRM Bulk Delete** card. |
| 5 | Click **Remove** beside the name on that card and confirm. | "Staff Tester no longer has the BarnCRM Bulk Delete permission." The card reads "No one has been given this permission here." Staff Tester's role is unchanged. |
| 6 | On the **BarnCRM Admin** card, click **Remove** beside your own name. | The dialog adds "You are about to remove your own BarnCRM Admin role. You will lose access to BarnCRM Settings." |
| 7 | Click **Remove**. | A **That Did Not Work** toast: "You cannot remove the last person from the BarnCRM Admin role. Give the role to someone else first." Your name stays on the card. |

**Cleanup:** None.

## T-SET-06: Module Manager

**Purpose:** confirm the module list, Turn off and Turn on, the uninstall report and Check again.
**Prerequisites:** admin user. Nonprofit Edition.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Modules**. | Rows for **Core** and **BarnCRM Rollup Builder** first, then a **Nonprofit Modules** section at the bottom with rows for **BarnCRM Giving**, **BarnCRM Volunteers**, **BarnCRM Programs**, **BarnCRM Funders** and **BarnCRM Mirror**. Deployed modules say **Installed**; Programs and Funders say **Not installed**. Every row has **What this module does**. |
| 2 | Look at a **Not installed** row. | "No install link is published for this module yet." (no module has a published install version on main). |
| 3 | Look at the **Core** row. | **Installed**, with no **Turn Off** button. |
| 4 | On the **BarnCRM Volunteers** row, click **Turn Off**. | The row says **Installed and off**. **Turn On** replaces **Turn Off**. |
| 5 | Open the **Home** tab and find the **Modules** card. | **BarnCRM Volunteers** shows **Off**. |
| 6 | Back in **Modules**, click **Turn On** on the Volunteers row. | The row says **Installed** again. No error shows. |
| 7 | Click **What an Uninstall Deletes** on the Volunteers row. | A box starts "Uninstalling this module deletes these records, and the fields it added to people, households and organizations. Export what you need first." and lists each object with a count (a `+` means at least that many), then **Open Installed Packages**. |
| 8 | Click **Check again**. | The report box closes and the list reloads with the same statuses. |
| 9 | Read the line under the list. | "Turning a module off stops its automation and keeps its records. It does not hide its tabs: to hide a module from someone, change their role on the Access page." |
| 10 | In the **Nonprofit Modules** section, look at **Show Nonprofit Modules**. | It is ticked (it is ticked on every org until someone clears it, including an org that saved its settings earlier) and the five nonprofit modules are listed under it. No "Installed nonprofit modules hidden" line shows. |
| 11 | Clear **Show Nonprofit Modules**. | The five nonprofit rows disappear; **Core** and **BarnCRM Rollup Builder** stay, and the checkbox stays, now clear. A line under it reads "Installed nonprofit modules hidden: 3" (Giving, Volunteers and Mirror are the installed ones in a test org; the number is however many nonprofit modules are installed). No error shows. |
| 12 | Reload the page. | The checkbox is still clear and the nonprofit rows are still hidden: the choice is saved for the whole org. |
| 13 | Tick **Show Nonprofit Modules**. | The nonprofit rows are back in the **Nonprofit Modules** section and the "hidden" line is gone. **Recent changes** in General lists both changes. |

**Cleanup:** make sure Volunteers is **Installed** (on) and **Show Nonprofit Modules** is ticked.

## T-SET-07: Pause Automation and Switch One Off

**Purpose:** confirm the timed pause, its banners, Resume, and a single automation switch.
**Prerequisites:** admin user. Automation not paused.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Automation**. | A card titled **Automation** lists each automation with a description, "Runs on" and its object, and a switch. **How long** shows **2 hours**. |
| 2 | Open **How long**. | Options **1 hour**, **2 hours**, **4 hours**, **8 hours**, **24 hours**. |
| 3 | Choose **1 hour** and click **Pause All Automation**. | A yellow box: "Automation is paused until" a date and time one hour from now, then "Paused by" your name and "It turns itself back on then.", with a **Resume Automation** button inside it. **How long** and **Pause All Automation** are gone, and there is no other **Resume Automation** button. Every switch stays where it was. |
| 4 | Open the **Home** tab. | Under **Welcome to BarnCRM**: "BarnCRM automation is paused. Households and greetings are not being updated until it resumes." in a yellow warning box with a **Resume Automation** link. Click the link: **BarnCRM Settings** opens on **Automation**. |
| 5 | Back in **Automation**, click **Resume Automation** in the yellow box. | The yellow box disappears, and **How long** with **Pause All Automation** is back; no **Resume Automation** button shows. On **Home** the banner is gone after a reload. |
| 6 | Switch off **Keep both sides of relationships in step**. | Next to the switch, for a few seconds: "Keep both sides of relationships in step is off. Turn it back on here." A screen reader announces it. Reload the page: the switch is still off. |
| 7 | Switch it back on, open **General** and scroll to **Recent Changes**. | Rows for **Automation Paused Until** record the pause and the resume, and rows record both switch changes, each with your name. |

**Cleanup:** leave every switch on and automation not paused.

## T-SET-07A: One Failing Row Does Not Stop the Rest

**Purpose:** confirm that when BarnCRM automation fails on one record of a bulk save, only that record is refused.
**Prerequisites:** admin user, Households on, **Create Households Automatically** on. In Setup, an Account validation rule `Test_No_Refuse` with the formula `CONTAINS(Name, "Refuseme")` and the message "Test rule". A CSV of five people, last names `Avery`, `Blake`, `Refuseme`, `Drew`, `Emery`, first name `Test`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Import the CSV with the **Generic contact list** template into People (see [Imports](imports.md)). | The run finishes. Four people are imported, each in a new household. One row is rejected: the `Refuseme` row, with a message saying the record was not saved. |
| 2 | Open **BarnCRM Settings**, **Error Log**. | An entry from the household automation names the failure. If the failure reached the trigger dispatcher, a Warning entry also says "Row 3 of this save was not saved" (the row in that save). |
| 3 | Search for `Avery` and `Emery`. | Both exist, each with a household. |

**Cleanup:** delete the validation rule and the four test people and their households.

## T-SET-07B: Bypass Automation for One User

**Purpose:** confirm the BarnCRM Automation Control setting skips automation for one user only.
**Prerequisites:** admin user, Households on, **Create Households Automatically** on. A second user, Sam, with the BarnCRM Staff role.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Automation**. Under **Pause or Bypass for Some People**, choose **User**, pick Sam, and select **Add**. | Below **Whole Organization** (both boxes off), a row for Sam, type User, with **Bypass** ticked and **Pause All** off. |
| 2 | As Sam, create a person `Test Bypassed`. | The person saves with no household (the household automation was skipped for Sam). |
| 3 | As the admin, create a person `Test Normal`. | The person gets a household as usual. |
| 4 | Select **Remove** on Sam's row, then **Catch Up Now**. Wait a minute and open `Test Bypassed`. | Sam's row is gone and the page says the catch-up has started. Selecting **Catch Up Now** again at once says "A catch-up is already running." `Test Bypassed` now has a household. |
| 5 | Tick **Pause All** on **Whole Organization**. | A yellow bar at the top says automation is paused for everyone, with **Turn Off**. Create a person: no household. |
| 6 | Add your own profile, untick its **Bypass**, and create a person. | The person gets a household: your profile's row (both off) replaces the organization's for you. |
| 7 | Select **Remove** on your profile's row, choose **Cancel** in the **Remove Automation Settings** window (the row stays), then **Remove** again and confirm. Select **Turn Off** in the yellow bar. | The bar is gone and **Pause All** is off on **Whole Organization**. |
| 8 | As a user without **Manage BarnCRM Settings**, open the page. | The rows show, but the boxes, **Add**, **Remove** and **Catch Up Now** are disabled. |

**Cleanup:** delete the test people and their households.

## T-SET-07C: List Your Own Flow on the Automation Page

**Purpose:** confirm an org's own flow can be listed with a switch that Check BarnCRM Automation reads.
**Prerequisites:** admin user; an active record-triggered flow of your own, `My_Test_Flow`, that starts with the **Check BarnCRM Automation** action (Automation Name `Flow:My_Test_Flow`) and ends when **Run** is false, and otherwise sets a field you can see.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Automation**. Under **Your Own Flows**, pick `My_Test_Flow` and select **Add**. | The flow joins the automation list, switched on, with a description naming `Flow:My_Test_Flow`, and a **Remove** button. It is no longer offered in the picker. |
| 2 | Save a record the flow runs on. | The flow sets its field. |
| 3 | Switch the flow's row **Off** and save another record. | The flow does not set its field. |
| 4 | Select **Remove** on the row. In the **Remove Flow** window choose **Cancel** (the row stays), then **Remove** again and confirm. | The row is gone and the flow is offered again. The flow itself is unchanged and still active. |

**Cleanup:** deactivate or delete `My_Test_Flow`.

## T-SET-07D: The Automation Tab

**Purpose:** confirm Automation has its own tab in the admin apps (D-184) and the Settings section still works.
**Prerequisites:** admin user; a staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM Admin** app. | The tabs read **BarnCRM Settings**, **Data Manager**, **Data Hygiene**, **Duplicate Matching**, **Automation**, then any module admin tabs, and **Error Log** last. **Automation** has a factory icon. |
| 2 | Click **Automation**. | The **Automation** card (factory icon) shows the pause controls, the switches, **Pause or Bypass for Some People** and **Your Own Flows**, as on **BarnCRM Settings**, **Automation**. |
| 3 | Open **BarnCRM Admin Console** and click **Automation**. | It opens as a workspace tab with the same card. |
| 4 | Open **BarnCRM Settings**, **Automation**. | The same card shows there; a switch changed on one page shows changed on the other after a reload. |
| 5 | As the staff user, open the App Launcher and search `Automation`. | No **Automation** tab is offered. |

**Cleanup:** None.

## T-SET-07E: Automation Inventory

**Purpose:** confirm the Automation tab lists every automation with owner and Pause All coverage, filters, a CSV and the snippets (C-60).
**Prerequisites:** admin user; `My_Test_Flow` from T-SET-07C (active, record-triggered on Contact); an active Apex trigger of your own on Account that does not check the setting, `MyAccountTrigger`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Automation** tab and scroll to **Automation Inventory**. | A table with **Name**, **Type**, **Object**, **Status**, **Owner**, **Runs** and **Covered by Pause All**. `Household naming` (or another BarnCRM automation) reads **BarnCRM Automation**, **On**, **BarnCRM**, **Yes**. `ContactTrigger` reads **Apex Trigger**, **BarnCRM**, **Yes**. `ErrorLogEventTrigger` reads **No**. |
| 2 | Find `My_Test_Flow` and `MyAccountTrigger`. | The flow: **Flow**, **Contact**, **Active**, **This Org**, **Not Checked**, with a note under the intro explaining Not Checked. The trigger: **This Org**, **No**. |
| 3 | Open the row menu of `MyAccountTrigger` and choose **How to Make This Respect Pause All**. | A section headed with that title and the trigger's name shows a sentence and four lines of Apex calling `CheckAutomationAction.check`, with **Copy** and **Close**. **Copy** puts the code on the clipboard. |
| 4 | Do the same for `My_Test_Flow`. | The steps name the Check BarnCRM Automation action and a Decision on Run; the code reads `Flow:My_Test_Flow`. |
| 5 | Open the row menu of a BarnCRM row. | No **How to Make This Respect Pause All** is offered. |
| 6 | Set **Object** to **Account**, then **Owner** to **This Org**. | Only Account rows, then only your own Account automation. Set **Owner** to a value with nothing on Account: "No automation matches these filters." |
| 7 | Clear the filters and click **Download CSV**. | A file `Automation-Inventory-<date>.csv` with every row shown, including API names and the object API name. |

**Cleanup:** delete `MyAccountTrigger` if you made it for this script.

## T-SET-07F: Scan Org Automation Through the Org Connection

**Purpose:** confirm the scan lists validation and workflow rules and checks the org's own flows (C-60, ADR-0174 "Deactivate org flows and validation rules with a snapshot and restore").
**Prerequisites:** an admin with BarnCRM Admin and BarnCRM Metadata Admin, Customize Application and Modify Metadata; the org connection set up with Enabled for Callouts on ([T-IMP-18](imports.md#t-imp-18-create-a-new-field-from-a-column)); `My_Test_Flow` from T-SET-07C (calls Check BarnCRM Automation); a second active flow of your own, `My_Plain_Flow`, that does not; an active validation rule on Contact, `Test_Paused_Rule`, whose formula reads `$Setup.BarnCRM_Automation_Control__c.Pause_All__c`; an active validation rule on Account, `Test_Plain_Rule`, that does not.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Automation** tab as an admin with BarnCRM Admin only. | No **Scan Org Automation** button; your flows read **Not Checked**. |
| 2 | Open it as the admin from the prerequisites, before the connection is set up (or with Enabled for Callouts off). | "Set up the org connection to list validation and workflow rules..." with the connection's status and **Set Up Connection** (or the Setup steps and **Check Again**). |
| 3 | With the connection ready, click **Scan Org Automation**. | "Scanning through the org connection..." and the button is greyed out. Within a minute the line reads "Last scanned" and a date and time. |
| 4 | Find `My_Test_Flow` and `My_Plain_Flow`. | **Yes** and **No** under **Covered by Pause All**. |
| 5 | Find `Test_Paused_Rule` and `Test_Plain_Rule`. | Both listed as **Validation Rule**, **Active**, **This Org**, on **Contact** and **Account**; **Yes** and **No**. A workflow rule, if the org has one, is listed with no status. |
| 6 | Click **Scan Org Automation** again and wait. | The date and time update; the rows are the same. |
| 7 | With Enabled for Callouts turned off in Setup, scan again. | The line names why the scan did not finish; an Error Log entry has the detail. Turn callouts back on. |

**Cleanup:** keep the flows and rules for T-SET-07G.

## T-SET-07G: Deactivate Org Flows and Validation Rules, Then Restore

**Purpose:** confirm a snapshot is saved before the org's own flows and rules are turned off, each result is shown, and Restore puts back exactly the snapshot (C-60, D-184, ADR-0174 "Deactivate org flows and validation rules with a snapshot and restore").
**Prerequisites:** the admin, connection, flows and rules from T-SET-07F, scanned; a sandbox, then (for step 8 only) a production org or Developer Edition org, where the same steps apply.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Automation** tab, find **Deactivate Org Flows and Validation Rules** under the table. | A list of your own active flows and validation rules only; no BarnCRM switch or flow, no trigger, no workflow rule, nothing from a managed package. **Deactivate Selected** is greyed out. |
| 2 | Set the owner filter to **BarnCRM**. | "No flow or validation rule of your own that is active matches these filters..." Set it back to all. |
| 3 | Tick `My_Plain_Flow` and `Test_Plain_Rule`, click **Deactivate Selected**. | In a sandbox, a plain confirm naming both items; no phrase to type. |
| 4 | Confirm. | Under **Deactivation Snapshots**, a new run (ASN- number) **In Progress** with both items **Waiting**, then within a minute **Completed** with both **Deactivated**. In Setup, `My_Plain_Flow` has no active version and `Test_Plain_Rule` is inactive. |
| 5 | Save an Account that `Test_Plain_Rule` would have refused. | It saves. |
| 6 | Click **Restore** on the run and confirm. | **Restoring**, then **Restored**; both items read **Restored**. In Setup the flow's same version is active again and the rule is active. No **Restore** button remains on that run. |
| 7 | Turn `Test_Plain_Rule` off in Setup. Without refreshing the Automation tab, deactivate it with `My_Plain_Flow`. | The rule reads **Left As It Is**, "It was already inactive, so it was left as it is."; the flow reads **Deactivated**. Restore turns the flow back on and leaves the rule off. Turn the rule back on in Setup. |
| 8 | In a production org, choose one item and click **Deactivate Selected**. | The dialog warns "This is a production org..." and **Deactivate Selected** stays greyed out until you type **DEACTIVATE**. Cancel. |
| 9 | While a run shows **In Progress**, look at **Deactivate Selected** and **Restore**. | Both are unavailable; the run says "Working through the org connection...". |

**Cleanup:** restore every run, so all flows and rules are active again.

## T-SET-08: Turn on a Feature Left Off

**Purpose:** confirm a feature that is off can be turned on once, behind a confirmation, and its tabs appear.
**Prerequisites:** admin user, in the org from [T-SA-02](setup-assistant.md#t-sa-02-first-run-setup-choosing-features) (Data Manager and Duplicate Matching left off).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**, **Features**. | A warning: "A feature can't be turned off once it is turned on. Turn on only what your organization will use." Eight rows. **Data Manager** and **Duplicate Matching** have **Turn On**; the rest say **On**. |
| 2 | Open the app's navigation menu. | **Data Manager** is not listed (nor **Find**, which opens from Data Manager). **Import** is not in the **Sections** list. |
| 3 | Click **Turn On** on **Data Manager**. | A dialog "Turn on Data Manager?": "Data Manager will be turned on for everyone, with its tabs, settings and automations. It can't be turned off again." |
| 4 | Click **Cancel**. | The row still shows **Turn On**. |
| 5 | Click **Turn On** again and confirm with **Turn On**. | "Data Manager is on. Its tabs appear for the right people within a few minutes." The row says **On** with no button. |
| 6 | Wait a few minutes, reload, and open the navigation menu. | **Data Manager** is listed, and its **Find and Export Records** tile opens Find. The **Import** section is now in the **Sections** list. |

**Cleanup:** None (a feature cannot be turned off).

## T-SET-09: Change the Edition

**Purpose:** confirm the edition can be changed from General with a confirmation, and module lists follow it.
**Prerequisites:** admin user. Nonprofit Edition.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**. Find **Edition**. | It reads **Nonprofit Edition**, with a **Change Edition** link under it. |
| 2 | Click **Change Edition**. | It opens: "The edition decides which modules BarnCRM shows and offers to everyone. Changing it installs, removes and turns off nothing, and changes no records." and a **Switch to the Standard Edition** button. |
| 3 | Click **Switch to the Standard Edition**. | A dialog "Change the Edition?" says modules already installed stay listed and keep working, with **Change Edition** and **Cancel**. |
| 4 | Click **Change Edition**. | "Edition changed. Reload open BarnCRM pages to see the new module lists." **Edition** reads **Standard Edition**. |
| 5 | Reload and open **Modules**. | **BarnCRM Programs** and **BarnCRM Funders** (not installed) are gone. Installed modules are still listed. |
| 6 | Switch back to the Nonprofit Edition the same way. | **Edition** reads **Nonprofit Edition**; after a reload Programs and Funders are listed again. **Recent Changes** lists both edition changes as **Edition**, with old and new values that read **Nonprofit Edition** and **Standard Edition** (never the stored codes "Standard" or "Nonprofit" alone, nor the old codes "Community" or "Impact"). |

**Cleanup:** leave the Nonprofit Edition.

## T-SET-10: Custom Metadata: Relationship Types

**Purpose:** confirm a person who can save Custom Metadata (BarnCRM Admin or Metadata Admin) can add, archive and restore a relationship type, that a missing picklist value is refused, and that match sources are no longer on this page (they are tested in [T-DUP-06 and T-DUP-07](duplicates.md#t-dup-06-a-deactivated-match-source-finds-nothing)).
**Prerequisites:** admin user holding **BarnCRM Admin**, which includes the permission to save Custom Metadata. Scratch orgs need no Apex Settings change; in an org where BarnCRM is installed as a package, turn on **Deploy Metadata from Non-Certified Package Versions via Apex** first. In Setup, Object Manager, Relationship, Fields & Relationships, **Type**: add `Mentor` and `Mentee`. Do not add `Godparent`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**, **Custom Metadata**. | One list, **Relationship types**, with **Added by Your Organization** ("Nothing added yet.") and **Shipped with BarnCRM**, which lists eleven rows (Spouse, Parent, Child and so on). There is no **Match sources** list. |
| 2 | Under **Relationship types**, click **Add**. Enter **Name** `Godparent`, **Type** `Godparent`, **Reciprocal Type** `Mentee`. Click **Save**. | Refused: "Godparent is not a choice in the Type list on Relationship. Add it in Setup (Object Manager, Relationship, Fields, Type), then save again." |
| 3 | Change **Name** and **Type** to `Mentor`, keep **Reciprocal Type** `Mentee`, and **Save**. | "Saving. Salesforce applies the change in the background, usually within a minute." then "Saved. Mentor is in the list." The row is under **Added by Your Organization** with **Status** **In use**. |
| 4 | Add `Mentee` with **Reciprocal Type** `Mentor` the same way. | "Saved. Mentee is in the list." |
| 5 | Open the row menu on **Mentee** and choose **Archive**. Wait for "Saved". | **Status** reads **Archived**. |
| 6 | Choose **Restore** from the same menu. Wait for "Saved". | **Status** reads **In use**. Shipped relationship types have no Archive action. |

**Cleanup:** archive Mentor and Mentee.

## T-SET-11: BarnCRM Home Page and What's New

**Purpose:** confirm the home page cards for an admin and for staff, and that What's new is dismissed per person.
**Prerequisites:** admin user and staff user. Neither has dismissed What's new since the last deploy.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the **BarnCRM** app, **Home** tab. | **What's New in BarnCRM** at the top ("Here is what changed since you last dismissed this card.", a **Version** heading showing **0.11**, the bold headline "A simpler way to work with your data, plus faster saves" and nine lines under it covering Data Manager, Import, Org Optimizer, Duplicate Matching, Settings, Setup Checklist and Home, record panels, faster saves and polish; no 0.6 note), then **Welcome to BarnCRM**, **Setup Checklist** or **Setup Complete**, **Health Check**, **Errors to Review**, the rollups and seasonal address tiles, **Modules** and **Quick Links**. |
| 2 | In **Quick Links**, click the **Households** tile, go back, then the **BarnCRM Settings** tile. | Three icon tiles, each with a one-line description; each opens its tab. **Organizations** is also listed. |
| 3 | In **Modules**, click **Open the Module Manager**. | **BarnCRM Settings** opens on **Modules**. |
| 4 | Look at the status tiles. | Each card has an icon. **Health Check** shows a badge (**Not Run Yet**, **Passed**, **Warnings: n** or **Errors: n**) and its findings as rows, as in BarnCRM Settings, **Health**. **Errors to Review** shows **All Clear** at zero. In an org where rollups never ran, the rollups tile shows **Not Run Yet** with no warning; once they ran and are more than 36 hours old it shows an **Overdue** badge. |
| 5 | On **Home**, click **Dismiss** on What's new. Reload. | The card is gone and stays gone. |
| 6 | As staff, open the **Home** tab. | What's new is still shown (dismissing is per person). Staff sees **Welcome to BarnCRM**, **New Household** and **Quick Links** only: no setup checklist, Health Check, Errors to Review or Modules card. |
| 7 | As staff, click **New Household**. | A household named **New Household** is created and its page opens, with no record type prompt. As admin, delete it. |

**Cleanup:** None.

## T-SET-12: Error Log Tile and Errors to Review

**Purpose:** confirm a new error is counted on Home and can be acknowledged from the tile, and staff cannot change its status.
**Prerequisites:** admin and staff users. Create one entry from the CLI: `sf apex run --target-org <alias>` with `insert new Error_Log__c(Message__c='Testing guide entry', Context__c='Testing guide', Severity__c='Error', Status__c='New', Timestamp__c=System.now());`.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open **Home**. | **Errors to Review** shows a count of at least 1, with **Open the Error Log**. |
| 2 | Open the **Org Optimizer** tab and its **Errors** tab. | An **Error Log** card with a badge "{n} new" lists **Testing guide entry** with **Testing guide** and the time, **Open This Entry** and **Mark Acknowledged**. |
| 3 | Click **Open This Entry**. | The Error Log record opens (as a subtab in the console). **Status** is **New**. |
| 4 | Back on the tile, click **Mark Acknowledged**. | The badge count drops by one (the entry stays in the recent list). The record's **Status** reads **Acknowledged**. On **Home**, **Errors to Review** drops by one after a reload. |
| 5 | As staff, open the **Error Log** tab and the entry. | The entry is readable. **Status** cannot be edited and **Technical Detail** is not shown. |

**Cleanup:** set the entry's **Status** to **Resolved** as admin.

## T-SET-13: Read-Only Users Across Settings

**Purpose:** confirm users without Manage BarnCRM Settings see every page read-only, with the reason.
**Prerequisites:** read-only user, then staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, open **BarnCRM Settings**, **General**. | A notice: "You can read these settings but not change them. Ask your BarnCRM admin for the Manage BarnCRM Settings permission." Every control is greyed out and no save bar appears. **Edition** shows with no **Change Edition** link. **Features** shows **On** and no **Turn On** buttons. |
| 2 | Open **Access**. | "You can see this page but you cannot change roles. Ask someone with the BarnCRM Admin role to make the change, or to give you that role." No **Find a person**, **Role**, **Give Access** or **Remove**. Role cards list holders, or say "You can see this page but you cannot see who holds each role." |
| 3 | Open **Modules**. | "You can see the modules but not change them. Ask your BarnCRM admin for the Manage BarnCRM Settings permission." No **Turn Off**, **Turn On** or **What an Uninstall Deletes**. **Show Nonprofit Modules** is greyed out. |
| 4 | Open **Automation**. | "You can read this page but not change it. Ask your BarnCRM admin for the Manage BarnCRM Settings permission." **Pause All Automation**, **How long** and every switch are disabled (with automation running, **Resume Automation** is not shown). |
| 5 | Open **General** and look for **Custom Metadata**. | It is not shown (it needs BarnCRM Admin or BarnCRM Metadata Admin). |
| 6 | Repeat step 1 as staff. | The same read-only notice and greyed-out controls. |

**Cleanup:** None.

## T-SET-14: Organization Address

**Purpose:** confirm the address is one grouped block laid out like a Salesforce address, that it may be blank, that four parts are required once any is filled, and that receipts and letters print it.
**Prerequisites:** admin user; the Organization address is blank (or note what it holds).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Organization**. | After **Organization legal name**, an **Organization Address** block shows **Street**, **Street 2**, then **City**, **State** and **Zip Code** on one row, then **Country**. No box is marked required while the whole address is blank. There is no separate row for each part. |
| 2 | Type `Springfield` in **City**. | **Street**, **City**, **State** and **Zip Code** are now marked required. **Street 2** and **Country** are not. |
| 3 | Click **Save Address**. | The page shows "Fill in the address parts marked required, or clear the whole address." and nothing is saved. |
| 4 | Fill **Street** `14 Bridge Street`, **State** `IL`, **Zip Code** `62701`. Leave **Street 2** and **Country** blank. Click **Save Address**, then open **General**. | "Organization address saved." On **General**, **Recent Changes** lists the four parts. |
| 5 | Reload and open **Organization**. | The four parts you saved are in their boxes. |
| 6 | Clear **Zip Code** and click **Save Address**. | A required-part message appears and the saved address is unchanged after a reload. |
| 7 | Search the console for `zip`, and click the **Organization zip code** result. | The console opens **Organization** and focuses the **Organization Address** block, not a separate row. |
| 8 | As read-only (T-SET-13), open **Organization**. | The address boxes are greyed out and there is no **Save Address** button. |
| 9 | Open **BarnCRM Settings**, **Organization** and clear all six boxes. Click **Save Address**. | "Organization address saved." A blank address is allowed. |
| 10 | Enter a Street 2 `Suite 3` and the four required parts again and save. Issue a receipt (see [Giving receipts and acknowledgments](giving-receipts-and-acknowledgments.md)) or make a volunteer hours letter, and open the document. | The receipt letterhead shows the address as `14 Bridge Street`, `Suite 3`, `Springfield, IL 62701` on separate lines. A letter using `{OrganizationAddress}` shows `14 Bridge Street, Suite 3, Springfield, IL 62701` on one line. |

**Cleanup:** restore the address you noted in the prerequisites (or clear it) and save.

## T-SET-15: Values That Come From Setup

**Purpose:** confirm the organization name and the fiscal year start month are shown read only from Setup, never edited in BarnCRM, and follow a change made in Setup.
**Prerequisites:** admin user. Note the org's name and fiscal year start month in **Setup, Company Settings, Company Information** before you start.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings** and click **Organization**. | The first row is **Organization name**, showing the org's name exactly as Company Information shows it. It cannot be typed in. Its description says to click **Open in Setup**, and **Open in Setup** under the row opens **Company Information** in a new tab. **Organization legal name** is the next row, directly below it, and can be edited. |
| 2 | Hover over the help icon next to **Organization name**. | "Read only. This comes from Salesforce Setup and is changed there; BarnCRM shows it and keeps no copy." |
| 3 | Click **General**. | A **Fiscal year start month** row shows the month the fiscal year starts in Setup, by name (for example **January**). It cannot be changed here, and its description says to click **Open in Setup**, then recalculate rollups. **Open in Setup** under the row opens **Fiscal Year** in a new tab. There is no month list to choose from. |
| 4 | Change **Organization legal name** and click **Save**, then click **General**. | Saved. **Recent Changes** lists the legal name only; **Organization name** never appears there. |
| 5 | In Setup, open **Company Information**, click **Edit**, add ` Test` to the end of **Organization Name** and save. Reload **BarnCRM Settings**, **Organization**. | **Organization name** shows the new name. |
| 6 | Sign in as the staff user and open **BarnCRM Settings**, **Organization**. | **Organization name** shows the same value, read only. |

**Cleanup:** In Setup, **Company Information**, set **Organization Name** back to what it was. Set **Organization legal name** back if you changed it in step 4.

## T-SET-16: Integrations Page

**Purpose:** confirm the Integrations roadmap page, that alternatives to a BarnCRM module appear only when installed, and the request links.
**Prerequisites:** admin user. No Volunteers for Salesforce, Program Management Module or Outbound Funds Module installed in the test org, and not a Nonprofit Cloud org with Program Management (the usual case). In a Nonprofit Cloud org with the standard **Program** object, **Alternatives to BarnCRM Modules** shows **Nonprofit Cloud Program Management**, **Installed in this org**, in step 2: that is expected.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Integrations**. | The introduction reads "Other free apps that work alongside BarnCRM, and alternatives to BarnCRM modules already in your org. None is integrated with BarnCRM yet, and BarnCRM depends on none of them." Each product's status and installed state are badges with icons (In Progress amber with a clock, Installed in this org green, Not installed grey). |
| 2 | Read the headings. | **Complementary Apps** and **In Development**. There is no **Alternatives to BarnCRM Modules** heading, and no empty group. |
| 3 | Read one product's row. | Its name, **In Progress**, **Not installed**, a description, who maintains it, **Cost and license**, **Compatibility with BarnCRM** with a note, and **Learn More**. No row has an **Install** link. The Summit Events App note says it is not yet tested and mentions the Salesforce Site and guest user. |
| 4 | Click **Learn More** on any row. | The product's page opens in a new tab. A screen reader reads "(Opens in a New Tab)" after the link name. |
| 5 | Read the last section, **Request an Integration**. | "Tell us what you need; requests shape the roadmap," says nothing is promised, and has **Request an Integration**, **Propose an Integration for Your Product** and **How an Integration Is Built**. |
| 6 | Click **Request an Integration**. | The GitHub form **Integration request** opens in a new tab with product name, link, what it does and how you use it. Close it without submitting. |
| 7 | Click **Propose an Integration for Your Product**. | The GitHub form **Integration proposal from a solution provider** opens in a new tab and asks for a role only, not a name or email. Close it without submitting. |
| 8 | In Setup, open **Custom Metadata Types**, **Integration App**, **Manage Integration App**, and edit **Volunteers for Salesforce (V4S)**: set **Show Only When Installed** off. Save, then click **Check again** on the page. | **Alternatives to BarnCRM Modules** appears with **Volunteers for Salesforce (V4S)**, **Not installed**, and its note says to use one or the other, not both, and that BarnCRM may offer a migration path in a future release. |
| 9 | Set **Show Only When Installed** back on, save and click **Check again**. | The **Alternatives to BarnCRM Modules** heading is gone again. |
| 10 | As an admin, look below the **Request an Integration** section. | Change a setting in another section, then come back: no save bar shows on this page (other sections show it to an admin while anything is unsaved). |
| 11 | As a read-only user, open **Integrations**. | The same page, with no setting to change. |

**Cleanup:** make sure **Show Only When Installed** is on for the four alternatives.

## T-SET-17: People and Households, and Boxes on Every Page

**Purpose:** confirm Households and Relationships are one **People and Households** section, every section groups its settings into headed boxes, and links to the old sections land in the right box.
**Prerequisites:** admin user. The **Households** and **Relationships** features on, and **Send long job notifications** ticked on **General**. A job notification for a household name recompute is easiest to get by clicking **Update All Household Names** in step 4.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings** and read the **Sections** list. | **People and Households** is the first item under **People**, right after **Organization**, then **Addresses**. There is no **Households** and no **Relationships** section. |
| 2 | Click **People and Households**. | Four bordered boxes, in order, each with a Title Case heading: **People** (**How people belong to a household**, **Create households automatically**), **Households** (**Delete empty households**, **Keep households of deleted people**), **Household Names and Greetings** (the **Preview and Recompute** panel, **Include people who have died in names**) and **Relationships** (**Keep both sides of relationships in step**). Every setting shows its value; none is blank. There is no duplicates row and no note about duplicate rules: those are on **Duplicate Matching**. |
| 3 | Tick **Keep households of deleted people**, click **Save**, then untick it and save again. | Both saves say the settings were saved. **General**, **Recent Changes** lists both changes. |
| 4 | Back on **People and Households**, click **Update All Household Names** and confirm. Wait for the bell, then open its **Household name recompute finished** notification. | The console opens on **People and Households**, scrolled to the **Household Names and Greetings** box, with focus on its heading. |
| 5 | Open each other section in turn: **General**, **Organization**, **Duplicate Matching**, **Addresses**, **Giving**, **Receipts**, **Rollups**, **Volunteers**, **Error Log**, **Import**, **Modules**, **Automation**, **Access**, **Org Optimizer**, **Integrations**, **Health**. | Every setting is inside a bordered box with a Title Case heading, as listed in the admin guide's "Sections and their boxes". A section with no list, such as **Access**, shows one box headed with its own name. No setting that showed before is missing. |
| 6 | In the browser address bar, change the end of the console's address to `?c__section=Relationships` and press Enter. | **People and Households** opens, scrolled to the **Relationships** box. |
| 7 | Do the same with `?c__section=Households`. | **People and Households** opens, scrolled to the **Households** box. |
| 8 | Open **Setup Assistant** on the Home page, go to **Confirm how households are named** and click **Where This Lives in Settings**. | **People and Households** opens at the **Household Names and Greetings** box. |

**Cleanup:** leave **Keep households of deleted people** unticked (the default).

## T-SET-18: Keep a Shown Default as a Saved Choice

**Purpose:** confirm a setting that shows a default nobody saved can be kept as a saved choice in one click, through the normal save.
**Prerequisites:** admin user, then read-only user. **Digest frequency** (Error Log), **Years before a person is not changed** and **Days before a user is unused** (Org Optimizer) never saved in this org.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Error Log**. | A banner at the top of the section reads **These Are Defaults** with **Keep All Defaults**. **Digest frequency** shows **Daily**, with a **Default** badge under it and a **Keep This Setting** button beside the badge, inside the **Error Digest** box. A setting already saved shows no badge. |
| 2 | Click **Keep This Setting** under **Digest frequency**. | "Your settings are saved." The badge and the button are gone, and **Digest frequency** still shows **Daily**. |
| 3 | Open **General** and read **Recent Changes**. | The top row is **Digest frequency**, old value empty, new value **Daily**, with your name. |
| 4 | Open **Org Optimizer**. Change **Days before a user is unused** to `120` without saving. | Its badge and button are gone; **Years before a person is not changed** still shows **5** with its badge and button. |
| 5 | Click **Keep This Setting** under **Years before a person is not changed**. | "Your settings are saved." Its badge is gone, **Days before a user is unused** still shows `120` and the save bar still says "1 unsaved change". Click **Discard**: it shows **90** again, with its badge. |
| 6 | Sign in as the read-only user and open **Org Optimizer**. | The **These Are Defaults** banner shows with no **Keep All Defaults**, and **Days before a user is unused** has its **Default** badge with no **Keep This Setting** button. |
| 7 | As an admin in an org with Person Accounts where **How people belong to a household** was never saved, open **People and Households**. | In the **People** box it shows **One household per person (simple)** with a **Default** badge under it and no **Keep This Setting** button, because BarnCRM would choose the flexible way for this org. In an org without Person Accounts or Nonprofit Cloud the same row has the button. |
| 8 | Still on **People and Households**, change one setting that has a **Default** badge without saving, then click **Keep All Defaults** in the banner. | "Your settings are saved." Every other badge with a **Keep This Setting** button is gone, and each kept setting has its own **Recent Changes** row. The changed setting is still unsaved in the save bar, and **How people belong to a household** (in the Person Accounts org) keeps its badge. |

**Cleanup:** none. The values kept are the defaults BarnCRM was already using, so nothing behaves differently.

## T-SET-18B: Blank Settings Say What They Mean

**Purpose:** confirm no setting on Organization or Error Log is a blank box with nothing said, and that Company Information is offered but never used until saved.
**Prerequisites:** admin user; an org where **Organization legal name**, the organization address and **Digest recipients** were never saved (note and clear them if they were), and Company Information (Setup, Company Settings) has a name and a full address.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Error Log**. | **Digest recipients** is empty, reads **Everyone with the Manage BarnCRM Settings permission** in grey inside the box, and has a **Default** badge with no **Keep This Setting** button. |
| 2 | Open **Organization**. | **Organization legal name** reads **Not set** in grey, with a **Default** badge and, under the box, "Company Information in Salesforce Setup has (your company name)." with **Use This Value**. Every empty address box reads **Not set**. Above the address, "No address is saved yet. Company Information in Salesforce Setup has (the address)." with **Use This Address**. With Giving, the tax identification number and receipt rows read **Not set** too. |
| 3 | Click **Use This Value**. | The legal name box holds the company name; the offer is gone; the save bar says "1 unsaved change". Nothing is saved yet. Click **Discard**: the box reads **Not set** again. |
| 4 | Click **Use This Address**, then **Save Address**. | The address boxes hold the company address (a second street line in **Street 2**), "Organization address saved.", and the offer does not come back after a reload. |
| 5 | Sign in as the read-only user and open **Organization**. | The **Not set** text and badges show; there is no **Use This Value** or **Use This Address**. |

**Cleanup:** clear the organization address (or set back what you noted) and save.

## T-SET-19: Finish Setup for a Module Whose Setup Never Ran

**Purpose:** confirm Health Check and the Modules page flag a module whose setup steps never ran (source copied in by hand), Finish Setup runs them, and the flag clears.
**Prerequisites:** admin user and the read-only user (T-SET-13). An org deployed with `scripts/org/deploy-packages.sh <alias>` (default settings), which runs every module's setup steps, or installed as packages.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Modules**. | No row says "Its setup steps never ran". |
| 2 | Imitate a module copied in by hand: in Setup, open **Custom Settings**, **BarnCRM Settings**, **Manage**, **Edit** the org default, remove `Giving` from **Modules Setup Run** (leave the rest, comma separated) and save. | Saved. |
| 3 | Back in **Modules**, click **Check again**. | Only the **BarnCRM Giving** row says "Its setup steps never ran, which happens when source is copied in by hand. Finish Setup runs the steps a package install runs." and has a **Finish Setup** button. |
| 4 | As the read-only user, open **Modules**. | The same sentence on **BarnCRM Giving**, with no **Finish Setup** button. |
| 5 | As admin, open **BarnCRM Settings**, **Health** and run Health Check. | A warning **Setup Never Ran for BarnCRM Giving** names the module and has **Finish Setup**. |
| 6 | Click **Finish Setup**, then **Confirm**. | **Done. Setup steps ran for: BarnCRM Giving.**, and the report re-runs without the warning. |
| 7 | Open **Modules**. | No row says "Its setup steps never ran". |
| 8 | Repeat step 2, then in **Modules** click **Finish Setup** on the **BarnCRM Giving** row. | The sentence and the button go away. No error shows, although Giving's steps had already run once: they only add what is missing, so the org has one General Fund and one of each receipt letter, not two. |
| 9 | Open **General** and scroll to **Recent Changes**. | **Finish Setup** and **Health Check: Finish Setup** each list **BarnCRM Giving**, with your name. |
| 10 | In a scratch org where nobody holds **Manage BarnCRM Settings** (remove BarnCRM Admin from every user), repeat step 2, then open **Modules** as a System Administrator. | **Finish Setup** shows on the **BarnCRM Giving** row (no other button does). Click it: the steps run and the notice goes away. Give BarnCRM Admin back to one user: a System Administrator without it no longer sees the button. |

**Cleanup:** None: **Modules Setup Run** lists Giving again.

## T-SET-20: Needs a Change in Setup Opens the Right Setup Page

**Purpose:** confirm every **Needs a Change in Setup** note gives one sentence on why, numbered steps, and an **Open in Setup** button that opens the right Setup page in a new tab, and that **Check Again** re-reads a check.
**Prerequisites:** an admin user with **BarnCRM Admin**, and a second user with settings access (Manage BarnCRM Settings) but neither BarnCRM Admin nor **BarnCRM Metadata Admin** (for step 1). Deliverability **Access level** is **All email**. Giving and Mirror installed for steps 7 to 10 (skip them on a Core-only org). A note whose change is already made is not shown at all.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the user with settings access but neither BarnCRM Admin nor Metadata Admin, open **BarnCRM Settings**, **General**, and click **Open in Setup** on the **Custom Metadata** note. | The note shows **Not done yet** with a warning icon and **Check Again**. A new browser tab opens **Permission Sets**. The BarnCRM tab is unchanged. Every note in this test shows one line under **Needs a Change in Setup**, the button, and **Show Steps**, closed; opening **Show Steps** shows one sentence on why and 2 to 4 numbered steps (here: click BarnCRM Admin, or BarnCRM Metadata Admin; click Manage Assignments, then Add Assignment; tick the person, then click Next and Assign). |
| 1a | As the admin with BarnCRM Admin, open **General**. | No **Custom Metadata** note is shown: BarnCRM Admin already holds the permission. The note does not mention the Apex Settings switch. |
| 1b | Assign the first user **BarnCRM Metadata Admin** in Setup, then back on **General** click **Check Again**. | The note is gone, and stays gone after a reload. |
| 2 | Click **Duplicate Matching**, then **Open in Setup**. | A new tab opens **Duplicate Rules**. |
| 3 | Click **Rollups** (Rollup Builder installed), then **Open in Setup**. | A new tab opens **Object Manager**; the first step says to click the object the rollup totals onto. |
| 4 | Click **Error Log**. | No email note: the org already sends all email. |
| 5 | In Setup, **Deliverability**, set **Access level** to **System email only** and save. Back in BarnCRM, reload and click **Error Log**, then **Open in Setup** on the note. | The note shows **Not done yet** and **Check Again**; a new tab opens **Deliverability**. Set **Access level** back to **All email**, save, click **Check Again**: the note goes without reloading. |
| 6 | Click **Access**, then **Open in Setup** on the note. | A new tab opens **Permission Sets**. |
| 7 | Open **Giving**, **Acknowledgments**. Click **Open in Setup** on each note in turn. | The From address note opens **Organization-Wide Addresses** and the template note opens **Classic Email Templates**. There is no email note while the org sends all email; with **System email only** it shows, opens **Deliverability** and has **Check Again**. |
| 8 | Open **Receipts**, then **Open in Setup** on the note. | A new tab opens **Lightning App Builder** (the Lightning Pages list). There is no note about Giving permission sets. |
| 9 | Open **Giving**, **Campaign Sync**. Click **Open in Setup** on each of the two notes. | The Campaign access note opens **Permission Sets**; the Marketing User note opens **Users**. |
| 10 | Open **Giving**, **Opportunity Mirror**, then **Open in Setup**; then open **Accounting Export**. | **Permission Sets** opens. **Accounting Export** shows no **Needs a Change in Setup** note. |

**Cleanup:** None, if Deliverability is back to **All email**.

## T-SET-21: An Upgrade Turns On New Settings Once

**Purpose:** confirm that an upgrade turns on a setting that ships on (Send Weekly Admin Summary, Ask Reminders) in an org that saved its settings before the setting existed, once, and never overrides the admin's choice after.
**Prerequisites:** an org upgraded or deployed from a version before 0.15 whose BarnCRM Settings and Giving settings had been saved.

| Step | Action | Expected result |
|---|---|---|
| 1 | After the upgrade, open **BarnCRM Settings** and find **Send weekly admin summary**. | It is on, and its description starts "On by default." |
| 2 | Choose the **Giving** section and find **Ask Reminders**. | It is on. |
| 3 | Switch both off and save. Run the upgrade or the source deploy again. | Both stay off. |

**Cleanup:** set both back to what they were.

## T-SET-22: Nightly Job Names, Template Names and Descriptions

**Purpose:** confirm nightly jobs are named in one style and a job scheduled under its earlier name is still recognized, and that shipped names read in title casing.
**Prerequisites:** the admin user; Giving and Programs installed; ideally an org whose Giving nightly jobs were scheduled before 0.15.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**, panel **Nightly Jobs**. | Each job scheduled before the upgrade (such as "BarnCRM Giving: ask reminders") shows as scheduled; none is offered for scheduling again or shown twice. |
| 2 | In an org where they were never scheduled, choose **Schedule Nightly Jobs**, then open Setup, **Scheduled Jobs**. | The names read "BarnCRM Giving Installment Top Up", "BarnCRM Giving Installments Overdue", "BarnCRM Giving Donor Levels" and "BarnCRM Giving Ask Reminders". When scheduled, the other two read "BarnCRM Giving Acknowledgments" and "BarnCRM Giving Pledge Reminders". |
| 3 | Open **Data Manager**, select **Import a File**, and open the **Template** picker. | Template names are in title casing, for example "Generic Gift List" and "NPSP: Opportunities and Payments". A template you renamed keeps your name. |
| 4 | Open the **Programs Admin** permission set in Setup. | Its description names case notes and service deliveries. |

**Cleanup:** leave the jobs scheduled as they were.

## T-SET-23: Settings Save Cues, Setting Names, Health and Error Log Links, Narrow Screens

**Purpose:** confirm a panel says it saves on its own, the save bar says what it covers, setting names read as form labels, Health and Error Log open Org Optimizer, and a narrow screen gets a Section box.
**Prerequisites:** admin user; the Org Optimizer and Households features on.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **People and Households**. | Setting names are in sentence case (**Create households automatically**, **Delete empty households**); box titles stay in Title Case. The household naming panel shows **Saves on its own** by its heading and its **Save** button at the top of the panel. |
| 2 | Tick **Delete empty households** (do not save). | The save bar reads "1 unsaved change in this section". |
| 3 | Open **General** without saving. | The save bar reads "0 unsaved changes in this section and 1 in other sections". Click **Discard**. |
| 4 | Open **Import**. | **Records per batch in imports** (Importing) and **Records per batch in background jobs** (Find, Super Transformer and Bulk Delete) each read 200; each description says to lower it only after a limit error. The first row's button reads **Open Super Importer**. |
| 5 | Open **Health** and click **Open Health Check**. | The Org Optimizer tab opens on its **Health Check** section, showing the last run (it does not start a new one). |
| 6 | Open **BarnCRM Settings**, **Error Log**. | The first box has **Open the Error Log**; below it the digest and retention settings only. Click it: Org Optimizer opens on **Errors**. |
| 7 | Narrow the browser window to phone width (or open on a phone) and reopen **BarnCRM Settings**. | The section list is replaced by a **Section** box under the search. Choose **Addresses**: the Addresses section shows and focus moves to its first box heading. |
| 8 | Log in as a user who can open BarnCRM Settings but has neither Find and Export nor Manage BarnCRM Settings, and open **Health**, then **Error Log**. | Health shows the Health Check report itself, with no **Open Health Check** button; Error Log has no **Open the Error Log** button. |

**Cleanup:** none.

## T-SET-24: Module Turn Off Confirmation, First-Run Feature List and Household Name Parts

**Purpose:** confirm Turn Off asks first, the first-run window names the default features, and the name pattern parts insert by click and by drag.
**Prerequisites:** admin user; an installed module that is on (Giving); for step 3, a fresh org where first-run setup has not run (or read the window in a scratch org).

| Step | Action | Expected result |
|---|---|---|
| 1 | **BarnCRM Settings**, **Modules**, on **BarnCRM Giving** click **Turn Off**, then **Cancel**. | A window titled "Turn Off BarnCRM Giving?" says its automation stops, its records stay, and its tabs stay visible (change a role on the Access page to hide them). After **Cancel** Giving is still on. |
| 2 | Click **Turn Off** again and confirm with **Turn Off**. Then **Turn On**. | The row reads **Installed and off**, then back on. |
| 3 | In the first-run window, leave **Turn on all the default core features** chosen. | Each default feature is listed by name with one plain line, and a warning reads "You can turn more features on later in BarnCRM Settings, General. A feature you turn on stays on, so if you are unsure, leave it off for now." |
| 4 | **People and Households**, household naming panel: click in **Household name pattern** before `Family`, then click the `{FirstName}` part under it. | `{FirstName}` is added at the cursor with spaces around it, the preview updates, and a screen reader hears "Added {FirstName} to Household name pattern." |
| 5 | Drag the `and` part (on a touch screen, press and hold, then drag) onto the formal greeting box and let go between two words. | `and` is added where you let go and the preview updates. Do not save. |
| 6 | Reload the page. | The patterns are back to their saved values. |

**Cleanup:** turn Giving back on if step 2 left it off.

## T-SET-25: One Nightly Run

**Purpose:** confirm every nightly job runs from the one schedule, in order, and the panel shows each job's result.
**Prerequisites:** the admin user. For step 1, an org upgraded from a version whose nightly jobs were scheduled one by one.

| Step | Action | Expected result |
|---|---|---|
| 1 | After the upgrade, open Setup, **Scheduled Jobs**. | One **BarnCRM Nightly Jobs** job at midnight, plus **BarnCRM Tab Access Check**; none of the old BarnCRM nightly jobs remain. |
| 2 | Open **BarnCRM Settings**, **General**, **Nightly Jobs**. | Says the run is scheduled; lists each job in time order with its time and On or Off. A job that was scheduled before the upgrade reads On. |
| 3 | Delete **BarnCRM Nightly Jobs** in Setup, then reload the panel. | Says it is not scheduled and shows **Schedule Nightly Jobs**. Health Check lists **Nightly Jobs Are Not Scheduled**. |
| 4 | Press **Schedule Nightly Jobs**. | The panel says it is scheduled. |
| 5 | On the **Error Log** section, press **Stop Daily Run**; back on **Nightly Jobs**. | The Error Log digest reads Off; the run stays scheduled. |
| 6 | The next morning, read the panel. | Each job shows a last run and a result (Done, Done With Errors, Skipped for jobs that are off). |
| 7 | Sign in as a user without Manage BarnCRM Settings and open the panel. | The list shows; there is no Schedule button. |
| 8 | As the admin, open **General**, then **Duplicate Matching**, **Import** and **Org Optimizer**. | Each shows its "Days to keep" setting with its default (730, 365, 365, 730); the panel lists **Record Cleanup** at 1:20, On. |
| 9 | Set **Days to keep merge history** to 5 and save. | A value below 30 is not accepted (the range is 30 to 3650). Set it back to 365. |

**Cleanup:** press **Schedule Daily Run** on the Error Log section again.

## T-SET-26: A Setting That Picks From Another Field's Values

**Purpose:** confirm a Picklist From Field setting offers only active values, keeps a retired saved value, and falls back to a text box when the field is absent.
**Prerequisites:** the admin user; BarnCRM Mirror installed. For steps 1 to 3, an org with Nonprofit Cloud (Gift Transaction Status); for step 4, an org without it.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Giving**, **BarnCRM Mirror**. | **Gift Transaction mirror paid status** is a dropdown showing `Paid` (the default, with the Default badge); it lists only the active Gift Transaction Status values. |
| 2 | Choose another value and save. | The save succeeds and the page keeps the choice. Recent changes lists it. |
| 3 | In Setup, make that Status value inactive; reload the setting. | The dropdown still shows the saved value, and saving the section keeps it. |
| 4 | In an org without Nonprofit Cloud, open the same setting. | A text box showing `Paid`; any text saves. |

## T-SET-28: Forms and Logic Models Are Found by Their Settings Rows

**Purpose:** confirm Forms and Logic Models show as installed through the settings row each ships, not an object name, and the row opens the module's tab (C-72).
**Prerequisites:** the admin user; Forms and Logic Models installed, Nonprofit Edition chosen.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Modules**. | **BarnCRM Forms** and **BarnCRM Logic Models** read **Installed**. |
| 2 | Open the **Forms** section (under People), then select **Open Forms**. | The Forms tab opens on its list view. |
| 3 | Open the **Logic Models** section (under Programs), then select **Open Logic Models**. | The Logic Models tab opens on its list view. |
| 4 | In an org with Core only, open **BarnCRM Settings**. | No Forms or Logic Models section; **Modules** lists both as not installed. |
