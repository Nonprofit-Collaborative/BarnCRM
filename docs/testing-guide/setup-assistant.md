# Setup Assistant

Scripts for first-run setup, the Setup Assistant's steps, sample data load and removal, and the in-app tips. Setup detail: [Setup Assistant](../admin-guide/setup-assistant.md).

Before you start: an org from [Before you test](before-you-test.md), with every module deployed and sample data loaded unless a script says otherwise. T-SA-01 and T-SA-02 need fresh orgs of their own, because first-run setup shows only once.

With Giving installed the assistant has nine steps; with Core alone it has eight and every step after **Confirm how households are named** moves up by one. Step numbers below are the nine-step ones.

## T-SA-01: First-run setup, every feature on

**Purpose:** confirm the setup window blocks the app until an admin finishes it, and that non-admins are told to wait.
**Prerequisites:** a new Person Accounts org (`scripts/org/create-scratch-org.sh person-accounts <alias>-fr1 --days 7 --no-sample-data`) whose BarnCRM home page has never been opened. A staff user in it with the **BarnCRM_Staff** permission set assigned from the CLI ([Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the **BarnCRM** app. | A window over the home page reads "An administrator needs to finish setting up BarnCRM." and nothing else. There is no **Finish setup** button. |
| 2 | As staff, open the **BarnCRM Settings** tab. | The same window, with the same sentence. |
| 3 | As admin, open the **BarnCRM** app. | A window titled **Set up BarnCRM**: "Two questions before BarnCRM is ready. You are asked them once." It asks **Which edition?** and **What should BarnCRM turn on?** **Turn on all the default core features** is selected. Under them: "No module is installed now. Install modules later from BarnCRM Settings, Modules." |
| 4 | Look at **Finish setup** before choosing an edition. | It is disabled. |
| 5 | Press Escape, then press Tab several times. | The window stays open and focus stays inside it. |
| 6 | Choose **Nonprofit Edition: the core suite plus the nonprofit tools, starting with the Giving module**. | **Finish setup** is enabled. |
| 7 | Click **Finish setup**. | The window closes and **BarnCRM Settings** opens on **General**. Without reloading the browser page, **Edition** reads **Nonprofit Edition** (never "Not chosen yet"). Every row under **Features** says **On**. |
| 8 | Open **Home**, then reload. | The window does not come back. The **Setup checklist** shows. |
| 9 | As staff, reload the home page. | No window. Staff sees **Welcome to BarnCRM** and **Quick links**. |

**Cleanup:** None. Delete the org when done (`sf org delete scratch --target-org <alias>-fr1`).

## T-SA-02: First-run setup, choosing features

**Purpose:** confirm unticked features stay off with their tabs hidden, ready for [T-SET-08](settings-and-module-manager.md#t-set-08-turn-on-a-feature-left-off).
**Prerequisites:** admin user in another new org, as in T-SA-01 (`<alias>-fr2`), never opened.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM** app. Choose **Standard Edition: the full core suite of BarnCRM tools**. | The **Set up BarnCRM** window shows both questions. |
| 2 | Choose **Let me choose features**. | "Untick what you do not want yet. You can turn it on later in BarnCRM Settings, General. Turning a feature on cannot be undone." Eight ticked boxes: **Data Manager**, **Duplicate Review**, **Org Optimizer and Health Check**, **Household upkeep**, **Addresses**, **Relationships**, **Affiliations**, **Preferred email and phone**, each with a help icon describing it. |
| 3 | Untick **Data Manager** and **Duplicate Review**. Click **Finish setup**. | **BarnCRM Settings** opens on **General**. Without reloading the browser page, **Edition** reads **Standard Edition** (never "Not chosen yet"). **Data Manager** and **Duplicate Review** show **Turn on**; the other six say **On**. |
| 4 | Wait a few minutes (the tab sync runs in the background), reload, and open the app's navigation menu. | **Data Manager** and **Find** are not listed. **Data Hygiene** is listed. |
| 5 | Look at the **Sections** list. | **Import** is not listed. |
| 6 | Open **Modules**. | **Core** and **BarnCRM Rollup Builder** only (no nonprofit module is offered in the Standard Edition). |

**Cleanup:** keep this org for T-SET-08, then delete it.

## T-SA-03: Walk the first steps: edition, fit and naming

**Purpose:** confirm the edition shows read-only, the fit is detected, and Back, Next and Skip for now move between steps.
**Prerequisites:** admin user, Person Accounts org, first-run setup finished with the Nonprofit Edition. If the home page shows **Setup complete**, click **Start setup again** under **Reopen setup** first (see T-SA-06).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM** app, **Home**. | A **Setup checklist** card with progress "{n} of 9". The assistant opens on the first step not done (usually step 2, because the edition is already saved). The counter reads "{step} / 9". |
| 2 | Click **Back** until step 1, **Choose your edition**. | "Edition: **Nonprofit Edition**", "The edition is chosen once." and a **How to change it later** link. No edition choice and no **Confirm and continue**. "Giving is installed. Its steps are part of this setup." **Back** is disabled. |
| 3 | Click **Next**. | Step 2, **Confirm how BarnCRM fits your existing org**: "Your org uses Person Accounts. Household membership is tracked with one record per person, so a person can be in more than one household and everything you already have keeps working." **Recommended for your org**, and **How BarnCRM fits this org** set to **Standalone**. (On the platform-only shape: "This looks like a fresh org, with no other household model and no Person Accounts. BarnCRM can run on its own.") |
| 4 | Open **How BarnCRM fits this org**. | Only **Standalone** (no NPSP or Nonprofit Cloud is in this org). |
| 5 | Click **Confirm and continue**. | Step 3, **Confirm how households are named**, opens with the household naming panel and its preview, and "This step finishes by itself once the setting it fills in has a value." **BarnCRM Settings**, **General**, **Coexistence mode** now reads **Standalone**. |
| 6 | Click **Next**. | Step 4 (with Giving, the default fund and appeal step; with Core alone, the access step). |
| 7 | Click **Skip for now**. | The next step opens. |
| 8 | Reload the page. | The assistant opens on the skipped step again (a skipped step is not finished). |

Note: in an org that stores people as accounts, confirming step 2 also switches household membership to one record per person, unless an administrator already chose a way of belonging.

**Cleanup:** None.

## T-SA-04: Access and organization identity steps

**Purpose:** confirm a role is given from the assistant and the identity answers land in BarnCRM Settings.
**Prerequisites:** admin user, as T-SA-03. The read-only user exists.

| Step | Action | Expected result |
|---|---|---|
| 1 | Go to step 5, **Give your colleagues access**. | **Person** and **Role** pickers, **Give access**, a **Create a user in Setup** link and a **Set up automatic access** link. |
| 2 | Choose **Read Only Tester** in **Person** and **Read Only** in **Role**. Click **Give access**. | "Access given. Add another person, or continue." |
| 3 | Open **BarnCRM Settings**, **Access** in another tab. | **Read Only Tester** is on the **Read Only** card. |
| 4 | Back in the assistant, click **Next**, to step 6, **Set your organization's identity**. | **Legal name, as registered** and **Address, as you want it printed**; with Giving, the receipt fields and upload buttons too, with the note "Uploaded files belong to the person who uploads them and stay attached to that person's user record, because Salesforce attaches every uploaded file to a record. Upload from an account that will stay active." |
| 5 | Enter `Riverside Test Trust` and `1 Main St, Springfield, IL 62701`. Click **Save**. | The step finishes and the assistant moves on. |
| 6 | Open **BarnCRM Settings**, **Organization**. | **Organization legal name** reads Riverside Test Trust; **Organization address** reads the address. Open **General**: **Recent Changes** lists both. |

**Cleanup:** None.

## T-SA-05: Modules and data steps

**Purpose:** confirm the module list follows the edition and the data step offers sample data and import.
**Prerequisites:** admin user, as T-SA-03. Sample data already loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Go to step 7, **Choose which modules to turn on**. | Core, BarnCRM Rollup Builder, BarnCRM Giving, BarnCRM Volunteers, BarnCRM Programs, BarnCRM Funders and BarnCRM Mirror, each **Present** or **Not installed** with **What this module does**. Then "To turn an installed module off or on, or to see what uninstalling one would delete, open the Modules section of BarnCRM Settings." |
| 2 | Click **Next**. | Step 8, **Bring in your data**, with **Load the sample data** and **Import a spreadsheet**. Step 7 shows as done. |
| 3 | Click **Load the sample data**. | The **Sample Data** card opens inside the step with status **Loaded** and **Load sample data** disabled. |
| 4 | Click **Import a spreadsheet**. | The **Import** tab opens. Go back to **Home**. |
| 5 | Click **Next** on step 8. | Step 8 shows as done. Step 9, **Check that everything works**, opens. With Giving, an **Enter your first gift** control is offered. The forward button reads **Finish**. |

**Cleanup:** None.

## T-SA-06: Finish, reopen and start again

**Purpose:** confirm the completion screen, the Setup complete tile, Reopen setup and Start setup again.
**Prerequisites:** admin user, after T-SA-05, with every step before 9 done: go back to any step marked **To do** or **Skipped** and finish it (for the Giving step, pick a fund and an appeal and click **Save**).

| Step | Action | Expected result |
|---|---|---|
| 1 | On step 9, click **Finish**. | "You are ready", each step with a **Done** badge, "Time taken: {n} minutes", **Reopen setup** and **Start setup again**. |
| 2 | Reload **Home**. | A **Setup complete** tile shows "9 of 9" and **Reopen setup**. The welcome reads "Your households, people and organizations are in the tabs above." |
| 3 | Click **Reopen setup**. | The assistant opens on step 1 with your answers intact. |
| 4 | Finish again to the completion screen. Click **Start setup again**. | The checklist starts from step 1. Steps whose setting already has a value (for example the identity step) still show as done. No setting is emptied: **BarnCRM Settings**, **Organization** still shows Riverside Test Trust. |

**Cleanup:** None.

## T-SA-07: Remove sample data (the undo)

**Purpose:** confirm removal deletes every sample record and leaves records you entered.
**Prerequisites:** admin user. Sample data loaded. Create one contact of your own: **First Name** `Rita`, **Last Name** `Real`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**, **Sample Data**. | Status **Loaded**, a warning "Sample data is for scratch orgs, sandboxes, and demos. Never load it into a production org.", tiles for **Households**, **Contacts**, **Organizations**, **Relationships** and **Affiliations**. **Load sample data** is disabled; **Remove sample data** is enabled. |
| 2 | Click **Remove sample data**. | A dialog "Remove sample data?": "This permanently deletes every household, contact, and organization created by the sample data loader. Records you entered yourself are not affected." with **Confirm** and **Cancel**. |
| 3 | Click **Cancel**. | Nothing changes. |
| 4 | Click **Remove sample data** and **Confirm**. | Status **Removing**; both buttons are disabled. The card refreshes by itself. |
| 5 | Wait until it changes (a few minutes with Giving). | Status **Not loaded**, a "Sample data removed." toast, **Load sample data** enabled, **Remove sample data** disabled. |
| 6 | Open **Households** and search for `Garcia`, then `Staff Household`. | Neither is found. |
| 7 | Search **Contacts** for `Rita Real`. | Rita Real is still there. |
| 8 | With Giving, open the **Gifts** tab, **All** list view. | No sample gifts remain. |

**Cleanup:** run T-SA-08 to load the sample data again.

## T-SA-08: Load sample data from the app

**Purpose:** confirm the load runs in the background, reports its counts and sends one notification.
**Prerequisites:** admin user. Sample data not loaded (after T-SA-07). **Tell people when their long jobs finish** ticked in **BarnCRM Settings**, **General**.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Sample Data**, click **Load sample data**. | A dialog "Load sample data?": "This adds 200 households, 440 contacts, 25 organizations, and the relationships and affiliations between them to this org, plus sample records for each installed module..." with **Confirm**. |
| 2 | Click **Confirm**. | Status **Loading**; both buttons disabled. |
| 3 | Wait for it to finish. | Status **Loaded** and a "Sample data loaded." toast. **Households** 200, **Contacts** 440, **Organizations** 25; **Relationships** and **Affiliations** above zero. |
| 4 | Open the bell. | One notification, **Sample data load finished**: "200 households, 440 people and 25 organizations are ready to explore." |
| 5 | Click the notification. | **BarnCRM Settings** opens on **General**. |
| 6 | Open **Households**, find **The Garcia Family**. | It exists, with its members. |
| 7 | With Giving, open **BarnCRM Settings**, **Rollups**, and select **Recalculate**. | Giving totals fill in (see [Load sample data](before-you-test.md#load-sample-data)). |

**Cleanup:** None (leave sample data loaded).

## T-SA-09: Sample data and the assistant without permission

**Purpose:** confirm a user without Manage BarnCRM Settings cannot load or remove sample data or see the checklist.
**Prerequisites:** read-only user, then staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, open **BarnCRM Settings**, **General**, **Sample Data**. | The card shows its status and counts, and "You need the Manage BarnCRM Settings permission to load or remove sample data." There is no **Load sample data** or **Remove sample data**. |
| 2 | Open **Home**. | No **Setup checklist** and no **Setup complete** tile. |
| 3 | Repeat steps 1 and 2 as staff. | The same. |

**Cleanup:** None.

## T-SA-10: In-app tips

**Purpose:** confirm the BarnCRM tips show once per person.
**Prerequisites:** staff user who has never opened BarnCRM Settings or Find, with **BarnCRM Find and Export** given on the Access page. Tips are not shown in the Salesforce mobile app.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the **BarnCRM** app, **BarnCRM Settings** tab. | A docked panel at the bottom right headed **BarnCRM tips**, titled **Getting around BarnCRM Settings**. |
| 2 | Minimize the panel and reload. | It does not come back. |
| 3 | At least 24 hours later, open the **Find** tab. | A floating tip, **Find exactly the records you need**, with **Got it**. |
| 4 | Click **Got it** and reload. | The tip does not come back. |
| 5 | In Setup, **In-App Guidance**, find the prompts. | Four start with "BarnCRM tips": BarnCRM Settings, Import, Find and Bulk Update. |

**Cleanup:** remove **BarnCRM Find and Export** from the staff user.

## T-SA-11: An org deployed from source

**Purpose:** confirm a source deploy runs Core's install steps on a fresh org, changes nothing on an org already set up, and that finishing first-run setup gives the tool tabs.
**Prerequisites:** a new org with nothing of BarnCRM in it (`<alias>-src`), and the CLI logged in to it as an admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Run `scripts/org/deploy-packages.sh <alias>-src --core-only`. | The output includes **== Running Core's post-install steps ==** with no error, and ends **== Every stage deployed ==**. |
| 2 | Open the **BarnCRM** app as the admin who deployed. | The **Set up BarnCRM** window shows, as in T-SA-01. |
| 3 | Choose **Standard Edition: the full core suite of BarnCRM tools**, keep **Turn on all the default core features**, and click **Finish setup**. | **BarnCRM Settings** opens on **General**. Every row under **Features** says **On**. |
| 4 | Wait a few minutes, reload, and open the app's navigation menu. | **Data Manager** and **Find** are listed. In Setup, **Scheduled Jobs** lists **BarnCRM Tab Access Check**. |
| 5 | Open **BarnCRM Settings**, **Automation**. | The automation switches are listed. |
| 6 | Run the deploy script from step 1 again. | It ends **== Every stage deployed ==**. In BarnCRM Settings, **Edition** still reads **Standard Edition**, every feature is still **On**, the setup window does not come back, and **Scheduled Jobs** still lists one **BarnCRM Tab Access Check**. |

**Cleanup:** None. Delete the org when done.
