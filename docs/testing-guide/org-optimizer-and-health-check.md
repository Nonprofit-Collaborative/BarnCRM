# Org Optimizer and Health Check

Scripts for the Org Optimizer page (its sections, Storage and Limits, Unused Setup) and Health Check (findings, fix buttons, read-only view, the Home tile). Setup detail: [Org Optimizer](../admin-guide/org-optimizer.md), [Health Check](../admin-guide/health-check.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data, and the read-only reports (Health Check, storage, limits, field utilization) read the real org. Do not select a fix button that changes an org-wide setting. In **BarnCRM Settings**, **General**, the **Org Optimizer and Health Check** feature is **On**. Data Quality, Duplicates and Field Utilization have their own scripts in [Data Manager and job history](data-manager-and-job-history.md) and [Duplicates](duplicates.md).

## T-HC-01: Org Optimizer Sections for an Admin

**Purpose:** Confirm an admin sees every section and nothing runs until a section is opened.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | In the BarnCRM app, open the **Org Optimizer** tab. | The page name **Org Optimizer** once (no second title card), then **What in your org needs attention, one section at a time.** On your first visit **About This Tool** is open with a **Learn More** link that opens the admin guide in a new tab. **Overview** is selected. |
| 2 | Read **Overview**. | Tiles with an icon and one line each, under **Check Your Data** (**Data Quality**, **Field Utilization**, **Data Dictionary**) and **Check Your Setup** (**Health Check**, **Errors**, **Storage and Limits**, **Unused Setup**, **Access Explorer**). **Errors** has a badge (**{n} New** or **All Clear**); **Health Check** has **Not Run Yet** on a new org, otherwise the last run's result. No **Duplicates** (they are on the **Duplicate Matching** tab). |
| 3 | Look at the vertical tabs. | **Overview**, **Data Quality**, **Field Utilization**, **Data Dictionary**, **Health Check**, **Errors**, **Storage and Limits**, **Unused Setup**, **Access Explorer**. Each section has one heading and no card inside the page's card. |
| 4 | Select the **Errors** tile. | The **Errors** section opens with the **Error Log** card: a count of new entries (or **Nothing has gone wrong. There is nothing to read here.**) and **Open the Error Log**. |
| 5 | Choose **Health Check**. | An illustration, **Health Check Runs When You Ask**, **Health Check reads your org's setup, which can take a few seconds, so it runs only when you ask.** and **Run Health Check**. No findings yet. |
| 6 | Click **Run Health Check**. | **Reading your org**, then the Health Check report with **What We Found in Your Org** and grouped findings. |
| 7 | Choose **Overview**, then **Health Check** again. | On **Overview** the **Health Check** tile shows the run's result (**Errors: {n}**, **Warnings: {n}** or **Passed**). Back on **Health Check**, the same report shows without running again. |
| 8 | Choose **Data Quality**, then **Storage and Limits**, then **Overview**. | **Data Quality** has **{n} Need Attention** or **All Clear**; **Storage and Limits** has **Data Storage {n}%**. Reload the page: **About This Tool** is now closed. |

**Cleanup:** None.

## T-HC-02: Who Sees Org Optimizer

**Purpose:** Confirm the tab and sections follow each person's permissions.
**Prerequisites:** staff; admin to give and take permissions.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the BarnCRM app. | No **Org Optimizer** tab. |
| 2 | As admin, give the staff user **BarnCRM Find and Export** in **BarnCRM Settings**, **Access**, **Extra Permissions**. | A message says the staff user now has it. |
| 3 | As staff, wait a minute, reload, and open **Org Optimizer**. | Only **Overview** and **Data Quality**. **Overview** has one tile, **Data Quality**, under **Check Your Data**. |
| 4 | Choose **Data Quality**. | The checks count with the staff user's own access. |

**Cleanup:** Remove **BarnCRM Find and Export** from the staff user.

## T-HC-03: Health Check Report and Re-Run

**Purpose:** Confirm the full report reads the org, groups findings and re-runs.
**Prerequisites:** admin. Setup Assistant steps you skipped (for example the module and access steps) add findings beyond the ones named here: read them, they are expected, and they do not fail this script.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings** and choose **Health**. | **Health Check**, **What BarnCRM found in your org, and what to do about it.** The card **What We Found in Your Org** shows what was detected (for example **Person Accounts enabled**), **Coexistence mode** and **Recommended**. |
| 2 | Read the findings. | Grouped under **Your Org**, **Licenses**, **Access** and **Settings**. Each has a severity (**Needs fixing**, **Worth knowing** or **Information**), a title, a sentence on what to do and, for most, a button. |
| 3 | Find **Your Org at a Glance**. | An **Information** finding that ends by saying Shield Platform Encryption cannot be detected from inside the app. |
| 4 | Find the automation finding. | **Automation is running normally**, **Information**. |
| 5 | Look for a fiscal year finding. | With a standard fiscal year in Setup (the default), there is none. An org that uses a custom fiscal year shows **Your org uses a custom fiscal year**, **Information**, naming the start month, with no button. |
| 6 | Click **Re-Run**. | **Reading your org**, then the report again. |

**Cleanup:** None.

## T-HC-04: A Fix Button Asks First

**Purpose:** Confirm a fix shows what it will do, Cancel changes nothing, and Confirm does exactly that and is recorded.
**Prerequisites:** admin. A fresh org: no BarnCRM nightly job scheduled yet.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **BarnCRM Settings**, **Health**, find **Nightly jobs are not scheduled**. | It names the jobs, for example **Error digest email**, **Empty household tidy-up**, and has **Schedule All Nightly Jobs**. |
| 2 | Click **Schedule All Nightly Jobs**. | A dialog **Before This Fix Runs**: **This is what the fix will do. Nothing changes until you confirm.**, the same list, **Confirm** and **Cancel**. |
| 3 | Press Escape. | The dialog closes and focus returns to the button. Nothing is scheduled. |
| 4 | Click **Schedule All Nightly Jobs**, then **Confirm**. | **Done. Scheduled: ...** naming each job, and the report re-runs. **Nightly jobs are not scheduled** is gone. |
| 5 | In **BarnCRM Settings**, open **General** and scroll to **Recent Changes**. | The top entry starts **Health Check:** with the button's name, your name and the time. |
| 6 | Open **BarnCRM Settings**, **Error Log**. | The **Error Digest** panel shows as scheduled, so the job can be stopped on its own page. The seasonal address swap is not on the list unless **Seasonal Addresses** is ticked on the **Addresses** page, and then it is scheduled already. |

**Cleanup:** None. Leave the jobs scheduled.

## T-HC-05: An Empty Household Finding Links the Record

**Purpose:** Confirm a data finding counts and links an empty household and changes nothing.
**Prerequisites:** admin. A Household account with no members, for example `Empty Test Household` from T-DM-08.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **BarnCRM Settings**, **Health**, click **Re-Run**. | **1 household has nobody in it** (or **N households have nobody in them**), **Information**, with **The first is linked below.** or **The first N are linked below.** |
| 2 | Look for a fix button on it. | None: what to do with an empty household is your decision. |
| 3 | Click the `Empty Test Household` link. | The household opens, unchanged. |
| 4 | Delete `Empty Test Household`, return and **Re-Run**. | The count drops by one (the finding is gone if it was the only one). |

**Cleanup:** None.

## T-HC-06: Health Check as the Read-Only User

**Purpose:** Confirm someone without Manage BarnCRM Settings can read the report but not fix anything, and access checks are skipped.
**Prerequisites:** read-only; admin to make a finding with a button (stop one nightly job on its page, for example the error digest on **BarnCRM Settings**, **Error Log**).

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, open **BarnCRM Settings** and choose **Health**. | The report shows with **You can read this report but not change anything. Ask an administrator for the Manage BarnCRM Settings permission.** |
| 2 | Look under **Access**. | **Only a BarnCRM Admin can see the access checks**, instead of the admin and user counts. |
| 3 | Find **Nightly jobs are not scheduled**. | It is not shown (only administrators see it), and no finding has a fix button. |
| 4 | Check the app's navigation. | No **Org Optimizer** tab. |

**Cleanup:** As admin, run **Schedule All Nightly Jobs** again.

## T-HC-07: Health Check's Last Result on Home

**Purpose:** Confirm Home shows the last full run instead of running each time, and Run Now refreshes it.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the BarnCRM home page. | The Health Check tile shows **Last Run** with a date and time and **N to fix, N to be aware of, N for your information.**, or **Health Check has not run yet. Click Run Now to check this org.** |
| 2 | Click **Run Now**. | **Reading your org**, then the whole report in the tile. |
| 3 | Reload the home page. | **Last Run** shows the time of step 2, with its counts. |

**Cleanup:** None.

## T-HC-08: Storage and Limits

**Purpose:** Confirm the read-only storage section shows the org's limits and BarnCRM's own records.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Org Optimizer**, choose **Storage and Limits**. | **Your Org's Limits** lists **Data Storage (MB)**, **File Storage (MB)**, **API Requests in the Last 24 Hours**, **Background Jobs (Asynchronous Apex) in the Last 24 Hours**, **Single Emails Sent Today**, each as **N of N (N%)** with a bar, and a **Near Limit** badge on any at 80% or more. |
| 2 | Read **What BarnCRM Stores**. | **Records BarnCRM keeps for imports, undo and errors. Salesforce counts most records as 2 KB.** and a table with **Kind of Record**, **Records** and **About (MB)**. |
| 3 | Look for anything that changes data. | Only **Refresh**. Click it: the numbers reload. |

**Cleanup:** None.

## T-HC-09: Unused Setup and Its Thresholds

**Purpose:** Confirm the read-only checks list counts and Setup links, and the thresholds are bounded settings.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Org Optimizer**, choose **Unused Setup**. | **Nothing here is changed for you. Open each item in Setup and decide whether to remove it.** Then eight checks, including **Active Users Who Have Not Logged In for 90 Days**, **Permission Sets Nobody Is Assigned**, **Reports Not Run for 365 Days**, **Email Templates Never Used**, **Inactive Flows**, **Scheduled Jobs Owned by Inactive Users**, **Objects Near Their Custom Field Limit**, **Record Types No Record Uses, or Inactive**. |
| 2 | Read a check with a count above 0. | The count in a warning-colored badge, up to five names, and **Open in Setup** with a new-window icon. A check the org does not allow reads **Could not check: your access or this org does not allow it.** |
| 3 | Click **Open in Setup** on one check. | The matching Setup page opens. Nothing was removed. |
| 4 | In **BarnCRM Settings**, **Org Optimizer**, set **Days before a user is unused** to `10` and click **Save**. | Nothing is saved; the value is marked as outside its range (30 to 365). |
| 5 | Set it to `60`, **Save**, then **Refresh** on **Unused Setup**. | **Your settings are saved.** The first check reads **Active Users Who Have Not Logged In for 60 Days**. |

**Cleanup:** Set **Days before a user is unused** back to `90`.

## T-HC-10: Data Dictionary Lists Fields, Fill Rates and a CSV

**Purpose:** Confirm an admin can document fields, add fill rates and download the table, and that nobody else sees it.
**Prerequisites:** admin and staff (see [Test users](before-you-test.md#test-users)); sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the admin, open **Org Optimizer** and choose **Data Dictionary**. | **Data Dictionary**, a **Kinds of Record** picker with **Account**, **Contact** and Core's data objects (such as **Address** and **Relationship**) already under **Selected**, **Include Fill Rates** unticked, **Build Dictionary** enabled and **Download CSV** disabled. **Choose kinds of record and press Build Dictionary.** shows. |
| 2 | Move everything except **Account** out of **Selected**, then click **Build Dictionary**. | A progress bar, then **Described 1 of 1 kinds of record.** and a table of Account's fields sorted by **Field**, with **Object**, **API Name**, **Type**, **Length**, **Precision**, **Required**, **Unique**, **External ID**, **Custom**, **Picklist Values**, **Help Text**, **Formula** and **Related To**. No **Fill Rate** column. |
| 3 | Find **Name**, **Website** and **Is Organization**. | **Name** is **Required**: Yes. **Website** has type url and **Custom**: No. **Is Organization** has **Custom**: Yes and its formula in **Formula**. **Parent Account** has **Related To**: Account. |
| 4 | Tick **Include Fill Rates** and click **Build Dictionary**. | The progress line reads **Counting fill rates for Account.** while it counts, then a **Fill Rate** column appears. **Phone** shows a percentage; **Is Organization** (a formula) and checkboxes are blank. |
| 5 | Click **Download CSV**. | A file named **Data_Dictionary-** and today's date ending .csv downloads, and **Downloaded {n} fields.** shows. Open it in a spreadsheet: a header row starting **Object**, **Object API Name**, **Field**, then one row per field with the same values, and **Fill Rate** as a percentage such as 33.3%. |
| 6 | In Setup, give a field help text containing a comma and a quotation mark, such as `Used for "Gifts", mostly`. Build again. | The help text shows whole in the table, and in the CSV it sits in one cell. |
| 7 | Choose all objects, tick **Include Fill Rates** and build, with an object of more than 1,000,000 records if the org has one. | Each object is described. An object over the limit has blank fill rates and **Fill rates not counted for: {object}.** appears under the table. |
| 8 | As staff (no Manage BarnCRM Settings), open **Org Optimizer**. | There is no **Data Dictionary** tile or tab. |

**Cleanup:** Remove the help text added in step 6.

## T-HC-11: Access Explorer Shows Who Can See What, and Why

**Purpose:** Confirm an admin can see a person's access and its sources, a permission set's access, who has access to a kind of record or field, and BarnCRM's permission sets, that each table downloads, and that nobody else sees it.
**Prerequisites:** admin and staff (see [Test users](before-you-test.md#test-users)); staff holds the **Team Member** role.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the admin, open **Org Optimizer** and choose the **Access Explorer** tile. | **Access Explorer**, **Who can see or change what, and why. Access Explorer only reads: it never gives or takes access.**, a **Show** choice with **By Person or Permission Set** selected, **Look Up** set to **Person**, and **Choose a person or permission set to see their access.** |
| 2 | Type the first two letters of the staff user's name in **Person** and choose them. | **Access Comes From** lists their profile (**Profile**), then **Team Member** (**Permission Set Group**, **Includes** BarnCRM Staff and the other sets in the role). A **Kinds of Record** table follows, sorted by name, with **Read**, **Create**, **Edit**, **Delete**, **View All**, **Modify All** and **Granted By**. **Relationship** has **Read**, **Create**, **Edit** and **Delete** as **Yes**, and **Granted By** reads **Team Member (through BarnCRM Staff)**. |
| 3 | Choose **Relationship** in **Field Access For**. | A **Fields** table with **Field**, **API Name**, **Read**, **Edit** and **Granted By**. **Description** shows **Yes** for **Read** and **Edit**; **Relationship Number** (Name) shows **Always**. |
| 4 | Type one letter in **Person**. | No search runs and nothing is listed until a second letter is typed. |
| 5 | Choose **By Kind of Record**, then **Relationship** in **Kind of Record**. | **Who Gives Access** lists profiles, then permission set groups, then permission sets, with **Kind**, the six permissions and **Active People**. **Team Member** is there with at least 1 active person, and **System Administrator** shows **View All** and **Modify All** (it gives Modify All Data). **People With Access** lists active people by name with **Granted By**. |
| 6 | Choose **Description** in **Field**. | **Who Gives Access** now shows **Read** and **Edit** only, and **People With Access** reloads. Choose **Relationship Number**: **Anyone who can read this kind of record can see this field. Salesforce does not let it be restricted.** and no tables. |
| 7 | In an org with more than 50 active people with access, click **Show More**. | The next 50 people are added below, in name order, with no one listed twice. **Show More** disappears after the last page. |
| 8 | Choose **By Person or Permission Set**, set **Look Up** to **Permission Set**, type `Staff` and choose **BarnCRM Staff** (**Permission Set**). | **Access Comes From** lists only **BarnCRM Staff**, and the table shows only what it gives: **Relationship** with **Granted By** **BarnCRM Staff**. |
| 9 | Search `Team` and choose **Team Member** (**Permission Set Group**). | **Access Comes From** shows **Team Member** with **Includes** naming its sets, and **Relationship**'s **Granted By** reads **Team Member (through BarnCRM Staff)**. |
| 10 | Choose **BarnCRM Permission Sets**. | The BarnCRM roles first (such as **BarnCRM Admin Group** and **Team Member**), then the BarnCRM permission sets, each with **Active People**. Below: **The Tab Access Check is scheduled hourly. Next run:** and a time, or, if it is not scheduled, a message pointing to Health Check. |
| 11 | Click **Download CSV** under any table. | A file named **Access_Explorer-** and today's date ending .csv downloads with the table's columns and rows, and **Downloaded {n} rows.** shows. |
| 12 | As staff (no Manage BarnCRM Settings), open **Org Optimizer**. | There is no **Access Explorer** tile or tab. |
| 13 | As the admin, open **BarnCRM Settings**, then the **Access** page, and click **Open Access Explorer**. | **Org Optimizer** opens on the **Access Explorer** section. |
| 14 | As an admin without View All Users (no BarnCRM Access Manager permission set), repeat step 5. | Above **People With Access**: **You may not see everyone: without View All Users, this list shows only the people Salesforce lets you see.** With View All Users the line is not shown. |

**Cleanup:** None. Access Explorer changes nothing.
