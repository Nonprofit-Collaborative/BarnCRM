# Settings and Module Manager

Scripts for the BarnCRM Settings console, Access, the Module Manager, Automation, Features, the edition, Custom metadata, the Error Log tile and the BarnCRM home page. Setup detail: [BarnCRM Settings](../admin-guide/barncrm-settings.md).

Before you start: an org from [Before you test](before-you-test.md), with every module deployed, the Nonprofit Edition chosen, every feature turned on in first-run setup, and sample data loaded unless a script says otherwise. Create the staff and read-only users from [Test users](before-you-test.md#test-users) first. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data and no module: skip the scripts that need a module, a staff user or the Nonprofit Edition, and put back any setting you change.

The BarnCRM Admin role card on the Access page is headed **BarnCRM Admin Group**, the role's label in Salesforce; the admin guide calls the role BarnCRM Admin and names the card the same way.

## T-SET-01: Open the settings console

**Purpose:** confirm the console opens with its sections, descriptions, Learn more links and Recent Changes.
**Prerequisites:** admin user (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | From the App Launcher, open the **BarnCRM** app and click the **BarnCRM Settings** tab. | A card titled **BarnCRM Settings** opens. A **Search settings** box and a **Sections** list are on the left; the first section shows on the right. No read-only notice is shown. |
| 2 | Read the **Sections** list. | It includes **General**, **Modules**, **Organization**, **Households**, **Relationships**, **Addresses**, **Automation**, **Error Log**, **Access**, **Import** and **Health**, plus **Giving** and **Receipts** with Giving installed, and **Rollups** with Rollup Builder installed (a Core-only org has no **Rollups** section). |
| 3 | Click **General**. | **Edition**, **Features**, **Sample Data**, **Custom Metadata** and the setting rows show, each with a plain description. A **Needs a Change in Setup** note at the top names **Setup, Company Settings, Fiscal Year** and shows **Done** or **Not done yet**. |
| 4 | Click **Learn more** under any setting. | A new browser tab opens the matching admin-guide page on GitHub. The console tab is unchanged. |
| 5 | Scroll to the bottom of the page. | A **Recent Changes** heading with a table (columns **Setting**, **Old value**, **New value**, **Changed by**, **Changed at**), or "No settings have been changed yet. Every change you make is listed here." |
| 6 | In a console app, look at the workspace tab label. | The tab reads **BarnCRM Settings: General** (the open section). |
| 7 | Click **Households**, then scroll to the bottom of the page. | There is no **Recent Changes** heading or table on **Households**. Click **Automation**, **Access** and **Organization** in turn: none shows **Recent Changes**. |
| 8 | Type `greeting` in **Search settings** and click **Formal greeting pattern**. | The console switches to **Households**, and **Recent Changes** is still not shown. Click **General**: **Recent Changes** shows again. |

**Cleanup:** None.

## T-SET-02: Search for a setting

**Purpose:** confirm search finds a setting by word and jumps to it, and says so when nothing matches.
**Prerequisites:** admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**. Type `greeting` in **Search settings**. | A **Search Results** list appears as you type. It includes **Formal greeting pattern (Households)** and **Informal greeting pattern (Households)**. |
| 2 | Click **Formal greeting pattern**. | The console switches to **Households** and scrolls to the **Preview and Recompute** panel. |
| 3 | Clear the box and type `pause`. | The **Automation** section's entry is listed. |
| 4 | Clear the box and type `zzqx`. | "No settings match that search. Try a shorter word, for example greeting." |

**Cleanup:** None.

## T-SET-03: Save a setting, see it in Recent Changes, discard and refuse a bad value

**Purpose:** confirm saves are recorded, unsaved edits can be discarded, and out-of-range numbers are refused.
**Prerequisites:** admin user. Note the current value of **Days to keep Error Log entries** (180 by default).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Error Log**. Change **Days to keep Error Log entries** to `90`. | **Save** and **Discard changes** become enabled. |
| 2 | Click **Discard changes**. | The value returns to what it was. **Save** is disabled again. Nothing is added to **Recent Changes** (shown on **General** only). |
| 3 | Change the value to `5000` and click **Save**. | The box is marked as out of range and the page says "A number is outside the range its setting takes, so nothing was saved. Correct the marked value and save again." |
| 4 | Change the value to `90` and click **Save**. | "Your settings are saved." Open **General**: the top row of **Recent Changes** shows **Days to keep Error Log entries**, old value 180, new value 90, your name and the time. |
| 5 | Open **Error Log** and click **Save** again without changing anything, then open **General**. | No new row appears in **Recent Changes**. |
| 6 | Reload the page and open **Error Log**. | The box shows 90. |

**Cleanup:** set **Days to keep Error Log entries** back to 180 and save.

## T-SET-04: Give and remove a role on the Access page

**Purpose:** confirm a role can be given and taken away from the app, with a confirmation each time.
**Prerequisites:** admin user (a System Administrator, so it can assign permission sets). The staff user exists; if it already holds **Coordinator**, remove it first.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Access**. | A card titled **Access** shows one card per role: **BarnCRM Admin Group**, **Team Member**, **Coordinator**, **Read Only**, and **Fundraising Staff** with Giving. Each heading ends with a count in brackets. |
| 2 | In **Find a person**, type `Staff`. | **Staff Tester** is listed with an email address. |
| 3 | Choose **Staff Tester**. In **Role**, choose **Coordinator**. Click **Give access**. | A dialog titled **Give access** asks "Give Staff Tester the Coordinator role?" with **Give access** and **Cancel**. |
| 4 | Click **Cancel**. | The dialog closes and nothing changes. |
| 5 | Click **Give access** again and confirm with **Give access**. | A **Done** toast: "Staff Tester now has the Coordinator role." **Staff Tester** appears on the **Coordinator** card and its count goes up by one. |
| 6 | Click **Remove** beside **Staff Tester** on the **Coordinator** card. | A dialog titled **Remove access**: "Remove the Coordinator role from Staff Tester? Any other role they hold stays in place." |
| 7 | Click **Remove**. | "Staff Tester no longer has the Coordinator role." The name leaves the card. **Staff Tester** is still on the **Team Member** card. |
| 8 | Click **Create a user in Setup**. | Setup, Users opens in a new tab. |
| 9 | Back on **Access**, read the **Needs a Change in Setup** note. | It names **Setup, Users, the person, Permission Set Assignments** and says "Core's extra permissions, and any permission set an installed module lists here, are given on this page. A module permission set not listed here is assigned in Setup." |

**Cleanup:** None.

## T-SET-05: Extra Permissions, and the last admin is protected

**Purpose:** confirm an extra permission is given with its warning and removed, and the last BarnCRM Admin cannot be removed.
**Prerequisites:** admin user, the only person on the **BarnCRM Admin Group** card (if the card is empty, give yourself the role first, as in T-SET-04). The staff user does not hold **BarnCRM Bulk Delete**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Access**. Scroll to **Extra Permissions**. | One card each for **BarnCRM Find and Export**, **BarnCRM Bulk Update**, **BarnCRM Bulk Delete**, **BarnCRM Erase People**, **BarnCRM Duplicate Review** and **BarnCRM Metadata Admin**, then the Giving and Mirror sets. Bulk Delete and Erase People carry the warning "This permission lets the person remove data. Give it only to someone you trust to do that." |
| 2 | Choose **Staff Tester** in **Find a person**. In **Extra permission**, choose **BarnCRM Bulk Delete**. | Under the picker: "Delete many records at once from a Find query, with undo from the Recycle Bin. Give it together with Find and Export." and the remove-data warning. |
| 3 | Click **Give permission**. | The dialog asks "Give Staff Tester the BarnCRM Bulk Delete permission?" and repeats the warning. |
| 4 | Confirm with **Give permission**. | "Staff Tester now has the BarnCRM Bulk Delete permission." The name appears on the **BarnCRM Bulk Delete** card. |
| 5 | Click **Remove** beside the name on that card and confirm. | "Staff Tester no longer has the BarnCRM Bulk Delete permission." The card reads "No one has been given this permission here." Staff Tester's role is unchanged. |
| 6 | On the **BarnCRM Admin Group** card, click **Remove** beside your own name. | The dialog adds "You are about to remove your own BarnCRM Admin role. You will lose access to BarnCRM Settings." |
| 7 | Click **Remove**. | A **That did not work** toast: "You cannot remove the last person from the BarnCRM Admin role. Give the role to someone else first." Your name stays on the card. |

**Cleanup:** None.

## T-SET-06: Module Manager

**Purpose:** confirm the module list, Turn off and Turn on, the uninstall report and Check again.
**Prerequisites:** admin user. Nonprofit Edition.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Modules**. | Rows for **Core**, **BarnCRM Rollup Builder**, **BarnCRM Giving**, **BarnCRM Volunteers**, **BarnCRM Programs**, **BarnCRM Funders** and **BarnCRM Mirror**. Deployed modules say **Installed**; Programs and Funders say **Not installed**. Every row has **What this module does**. |
| 2 | Look at a **Not installed** row. | "No install link is published for this module yet." (no module has a published install version on main). |
| 3 | Look at the **Core** row. | **Installed**, with no **Turn off** button. |
| 4 | On the **BarnCRM Volunteers** row, click **Turn off**. | The row says **Installed and off**. **Turn on** replaces **Turn off**. |
| 5 | Open the **Home** tab and find the **Modules** card. | **BarnCRM Volunteers** shows **Installed and off**. |
| 6 | Back in **Modules**, click **Turn on** on the Volunteers row. | The row says **Installed** again. No error shows. |
| 7 | Click **What an uninstall deletes** on the Volunteers row. | A box starts "Uninstalling this module deletes these records, and the fields it added to people, households and organizations. Export what you need first." and lists each object with a count (a `+` means at least that many), then **Open Installed Packages**. |
| 8 | Click **Check again**. | The report box closes and the list reloads with the same statuses. |
| 9 | Read the line under the list. | "Turning a module off stops its automation and keeps its records. It does not hide its tabs: to hide a module from someone, change their role on the Access page." |

**Cleanup:** make sure Volunteers is **Installed** (on).

## T-SET-07: Pause automation and switch one off

**Purpose:** confirm the timed pause, its banners, Resume, and a single automation switch.
**Prerequisites:** admin user. Automation not paused.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Automation**. | A card titled **Automation** lists each automation with a description, "Runs on" and its object, and a switch. **How long** shows **2 hours**. |
| 2 | Open **How long**. | Options **1 hour**, **2 hours**, **4 hours**, **8 hours**, **24 hours**. |
| 3 | Choose **1 hour** and click **Pause all automation**. | A yellow box: "Automation is paused until" a date and time one hour from now, then "Paused by" your name and "It turns itself back on then." Every switch stays where it was. |
| 4 | Open the **Home** tab. | Under **Welcome to BarnCRM**: "BarnCRM automation is paused. Households and greetings are not being updated until it resumes." |
| 5 | Back in **Automation**, click **Resume automation**. | The yellow box disappears. On **Home** the banner is gone after a reload. |
| 6 | Switch off **Keep both sides of relationships in step**. Reload the page. | The switch is still off. |
| 7 | Switch it back on, open **General** and scroll to **Recent Changes**. | Rows for **Automation Paused Until** record the pause and the resume, and rows record both switch changes, each with your name. |

**Cleanup:** leave every switch on and automation not paused.

## T-SET-08: Turn on a feature left off

**Purpose:** confirm a feature that is off can be turned on once, behind a confirmation, and its tabs appear.
**Prerequisites:** admin user, in the org from [T-SA-02](setup-assistant.md#t-sa-02-first-run-setup-choosing-features) (Data Manager and Duplicate Review left off).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**, **Features**. | A warning: "A feature can't be turned off once it is turned on. Turn on only what your organization will use." Eight rows. **Data Manager** and **Duplicate Review** have **Turn on**; the rest say **On**. |
| 2 | Open the app's navigation menu. | **Data Manager** and **Find** are not listed. **Import** is not in the **Sections** list. |
| 3 | Click **Turn on** on **Data Manager**. | A dialog "Turn on Data Manager?": "Data Manager will be turned on for everyone, with its tabs, settings and automations. It can't be turned off again." |
| 4 | Click **Cancel**. | The row still shows **Turn on**. |
| 5 | Click **Turn on** again and confirm with **Turn on**. | "Data Manager is on. Its tabs appear for the right people within a few minutes." The row says **On** with no button. |
| 6 | Wait a few minutes, reload, and open the navigation menu. | **Data Manager** and **Find** are listed. The **Import** section is now in the **Sections** list. |

**Cleanup:** None (a feature cannot be turned off).

## T-SET-09: Change the edition

**Purpose:** confirm the edition can be changed from General with a confirmation, and module lists follow it.
**Prerequisites:** admin user. Nonprofit Edition.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**. Find **Edition**. | It reads **Nonprofit Edition**, with a **Change edition** link under it. |
| 2 | Click **Change edition**. | It opens: "The edition decides which modules BarnCRM shows and offers to everyone. Changing it installs, removes and turns off nothing, and changes no records." and a **Switch to the Standard Edition** button. |
| 3 | Click **Switch to the Standard Edition**. | A dialog "Change the edition?" says modules already installed stay listed and keep working, with **Change edition** and **Cancel**. |
| 4 | Click **Change edition**. | "Edition changed. Reload open BarnCRM pages to see the new module lists." **Edition** reads **Standard Edition**. |
| 5 | Reload and open **Modules**. | **BarnCRM Programs** and **BarnCRM Funders** (not installed) are gone. Installed modules are still listed. |
| 6 | Switch back to the Nonprofit Edition the same way. | **Edition** reads **Nonprofit Edition**; after a reload Programs and Funders are listed again. **Recent Changes** lists both edition changes. |

**Cleanup:** leave the Nonprofit Edition.

## T-SET-10: Custom Metadata: relationship types and match sources

**Purpose:** confirm a Metadata Admin can add, archive and restore a relationship type, archive and restore a shipped match source, and that a missing picklist value is refused.
**Prerequisites:** admin user holding **BarnCRM Metadata Admin** (the create script gives it; otherwise give it on the Access page, Extra Permissions). Scratch orgs need no Apex Settings change; in an org where BarnCRM is installed as a package, turn on **Deploy Metadata from Non-Certified Package Versions via Apex** first. In Setup, Object Manager, Relationship, Fields & Relationships, **Type**: add `Mentor` and `Mentee`. Do not add `Godparent`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**, **Custom Metadata**. | Two lists: **Relationship types** and **Match sources**, each with **Added by Your Organization** ("Nothing added yet.") and **Shipped with BarnCRM**. Relationship types lists eleven shipped rows (Spouse, Parent, Child and so on); Match sources lists six. |
| 2 | Under **Relationship types**, click **Add**. Enter **Name** `Godparent`, **Type** `Godparent`, **Reciprocal Type** `Mentee`. Click **Save**. | Refused: "Godparent is not a choice in the Type list on Relationship. Add it in Setup (Object Manager, Relationship, Fields, Type), then save again." |
| 3 | Change **Name** and **Type** to `Mentor`, keep **Reciprocal Type** `Mentee`, and **Save**. | "Saving. Salesforce applies the change in the background, usually within a minute." then "Saved. Mentor is in the list." The row is under **Added by Your Organization** with **Status** **In use**. |
| 4 | Add `Mentee` with **Reciprocal Type** `Mentor` the same way. | "Saved. Mentee is in the list." |
| 5 | Open the row menu on **Mentee** and choose **Archive**. Wait for "Saved". | **Status** reads **Archived**. |
| 6 | Choose **Restore** from the same menu. Wait for "Saved". | **Status** reads **In use**. |
| 7 | Under **Match sources**, **Shipped with BarnCRM**, archive **Contact Point Phone**, then restore it. | Its status goes to **Archived**, then back to **In use**. Shipped relationship types have no Archive action. |
| 8 | Under **Match sources**, click **Add**. Enter **Name** `Bad source`, **Object Name** `Contact`, **Value Field** `Nope__c`, **Parent Field** `AccountId`, **Normalization** **Email**, and **Save**. | Refused: "Nope__c is not a field on Contact. Check its API name." Nothing is added. |
| 9 | Change **Value Field** to `Email` and **Parent Field** to `LastName`, and **Save**. | Refused: "LastName on Contact is not a lookup to a contact, account or Individual. The parent field has to link each value to its person, household or Individual." |
| 10 | Change **Normalization** to **Address**, **Parent Field** to `AccountId`, leave **Postal Code Field** empty, and **Save**. | Refused: "An address source needs a postal code field: the street is compared together with it." Click **Cancel**. |

**Cleanup:** archive Mentor and Mentee. Make sure **Contact Point Phone** is **In use**.

## T-SET-11: BarnCRM home page and What's new

**Purpose:** confirm the home page cards for an admin and for staff, and that What's new is dismissed per person.
**Prerequisites:** admin user and staff user. Neither has dismissed What's new since the last deploy.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the **BarnCRM** app, **Home** tab. | **What's new in BarnCRM** at the top ("Here is what changed since you last dismissed this card.", a **Version** heading, bold headlines), then **Welcome to BarnCRM**, **Setup checklist** or **Setup complete**, **Health Check**, **Errors to review**, the rollups and seasonal address tiles, **Modules** and **Quick links**. |
| 2 | In **Quick links**, click **Households**, go back, then **BarnCRM Settings**. | Each opens its tab. **Organizations** is also listed. |
| 3 | In **Modules**, click **Open the Module Manager**. | **BarnCRM Settings** opens on **Modules**. |
| 4 | On **Home**, click **Dismiss** on What's new. Reload. | The card is gone and stays gone. |
| 5 | As staff, open the **Home** tab. | What's new is still shown (dismissing is per person). Staff sees **Welcome to BarnCRM**, **New household** and **Quick links** only: no setup checklist, Health Check, Errors to review or Modules card. |
| 6 | As staff, click **New household**. | A new Household account form opens. Cancel it. |

**Cleanup:** None.

## T-SET-12: Error Log tile and Errors to review

**Purpose:** confirm a new error is counted on Home and can be acknowledged from the tile, and staff cannot change its status.
**Prerequisites:** admin and staff users. Create one entry from the CLI: `sf apex run --target-org <alias>` with `insert new Error_Log__c(Message__c='Testing guide entry', Context__c='Testing guide', Severity__c='Error', Status__c='New', Timestamp__c=System.now());`.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open **Home**. | **Errors to review** shows a count of at least 1, with **Open the Error Log**. |
| 2 | Open the **Data Hygiene** tab (titled **Org Optimizer**) and its **Errors** tab. | An **Error Log** card with a badge "{n} new" lists **Testing guide entry** with **Testing guide** and the time, **Open this entry** and **Mark acknowledged**. |
| 3 | Click **Open this entry**. | The Error Log record opens (as a subtab in the console). **Status** is **New**. |
| 4 | Back on the tile, click **Mark acknowledged**. | The badge count drops by one (the entry stays in the recent list). The record's **Status** reads **Acknowledged**. On **Home**, **Errors to review** drops by one after a reload. |
| 5 | As staff, open the **Error Log** tab and the entry. | The entry is readable. **Status** cannot be edited and **Technical Detail** is not shown. |

**Cleanup:** set the entry's **Status** to **Resolved** as admin.

## T-SET-13: Read-only users across Settings

**Purpose:** confirm users without Manage BarnCRM Settings see every page read-only, with the reason.
**Prerequisites:** read-only user, then staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, open **BarnCRM Settings**, **General**. | A notice: "You can read these settings but not change them. Ask your administrator for the Manage BarnCRM Settings permission." Every control is greyed out and there is no **Save** or **Discard changes**. **Edition** shows with no **Change edition** link. **Features** shows **On** and no **Turn on** buttons. |
| 2 | Open **Access**. | "You can see this page but you cannot change roles. Ask someone with the BarnCRM Admin role to make the change, or to give you that role." No **Find a person**, **Role**, **Give access** or **Remove**. Role cards list holders, or say "You can see this page but you cannot see who holds each role." |
| 3 | Open **Modules**. | "You can see the modules but not change them. Ask an administrator for the Manage BarnCRM Settings permission." No **Turn off**, **Turn on** or **What an uninstall deletes**. |
| 4 | Open **Automation**. | "You can read this page but not change it. Ask your administrator for the Manage BarnCRM Settings permission." **Pause all automation**, **Resume automation**, **How long** and every switch are disabled. |
| 5 | Open **General** and look for **Custom Metadata**. | It is not shown (it needs BarnCRM Metadata Admin). |
| 6 | Repeat step 1 as staff. | The same read-only notice and greyed-out controls. |

**Cleanup:** None.

## T-SET-14: Organization address

**Purpose:** confirm the address is one grouped block laid out like a Salesforce address, that it may be blank, that four parts are required once any is filled, and that receipts and letters print it.
**Prerequisites:** admin user; the Organization address is blank (or note what it holds).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Organization**. | After **Organization legal name**, an **Organization address** block shows **Street**, **Street 2**, then **City**, **State** and **Zip Code** on one row, then **Country**. No box is marked required while the whole address is blank. There is no separate row for each part. |
| 2 | Type `Springfield` in **City**. | **Street**, **City**, **State** and **Zip Code** are now marked required. **Street 2** and **Country** are not. |
| 3 | Click **Save address**. | The page shows "Fill in the address parts marked required, or clear the whole address." and nothing is saved. |
| 4 | Fill **Street** `14 Bridge Street`, **State** `IL`, **Zip Code** `62701`. Leave **Street 2** and **Country** blank. Click **Save address**. | "Organization address saved." **Recent changes** lists the four parts. |
| 5 | Reload and open **Organization**. | The four parts you saved are in their boxes. |
| 6 | Clear **Zip Code** and click **Save address**. | A required-part message appears and the saved address is unchanged after a reload. |
| 7 | Search the console for `zip`, and click the **Organization zip code** result. | The console opens **Organization** and focuses the **Organization address** block, not a separate row. |
| 8 | As read-only (T-SET-13), open **Organization**. | The address boxes are greyed out and there is no **Save address** button. |
| 9 | Open **BarnCRM Settings**, **Organization** and clear all six boxes. Click **Save address**. | "Organization address saved." A blank address is allowed. |
| 10 | Enter a Street 2 `Suite 3` and the four required parts again and save. Issue a receipt (see [Giving receipts and acknowledgments](giving-receipts-and-acknowledgments.md)) or make a volunteer hours letter, and open the document. | The receipt letterhead shows the address as `14 Bridge Street`, `Suite 3`, `Springfield, IL 62701` on separate lines. A letter using `{OrganizationAddress}` shows `14 Bridge Street, Suite 3, Springfield, IL 62701` on one line. |

**Cleanup:** restore the address you noted in the prerequisites (or clear it) and save.
