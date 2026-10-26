# Org Optimizer and Health Check

Scripts for the Org Optimizer page (its sections, Storage and limits, Unused setup) and Health Check (findings, fix buttons, read-only view, the Home tile). Setup detail: [Org Optimizer](../admin-guide/org-optimizer.md), [Health Check](../admin-guide/health-check.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In **BarnCRM Settings**, **General**, the **Org Optimizer and Health Check** feature is **On**. Data quality, Duplicates and Field utilization have their own scripts in [Data Manager and job history](data-manager-and-job-history.md) and [Duplicates](duplicates.md).

## T-HC-01: Org Optimizer sections for an admin

**Purpose:** Confirm an admin sees every section and nothing runs until a section is opened.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | In the BarnCRM app, open the **Org Optimizer** tab. | Title **Org Optimizer**, with **What in your org needs attention. Each section runs only when you open it.** **Overview** is selected. |
| 2 | Read **Overview**. | One line per section, each with **Open**: **Data quality**, **Duplicates**, **Field utilization**, **Health Check**, **Errors**, **Storage and limits**, **Unused setup**. |
| 3 | Look at the vertical tabs. | **Overview**, **Data quality**, **Duplicates**, **Field utilization**, **Health Check**, **Errors**, **Storage and limits**, **Unused setup**. |
| 4 | Click **Open** on **Errors**. | The **Errors** section opens with the **Error Log** card: a count of new entries (or **Nothing has gone wrong. There is nothing to read here.**) and **Open the Error Log**. |
| 5 | Choose **Health Check**. | **Health Check reads your org's setup, which can take a few seconds, so it runs only when you ask.** and **Run Health Check**. No findings yet. |
| 6 | Click **Run Health Check**. | **Reading your org**, then the Health Check report with **What we found in your org** and grouped findings. |
| 7 | Choose **Overview**, then **Health Check** again. | The same report shows without running again. |

**Cleanup:** None.

## T-HC-02: Who sees Org Optimizer

**Purpose:** Confirm the tab and sections follow each person's permissions.
**Prerequisites:** staff; admin to give and take permissions.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the BarnCRM app. | No **Org Optimizer** tab. |
| 2 | As admin, give the staff user **BarnCRM Find and Export** in **BarnCRM Settings**, **Access**, **Extra permissions**. | A message says the staff user now has it. |
| 3 | As staff, wait a minute, reload, and open **Org Optimizer**. | Only **Overview** and **Data quality**. **Overview** lists one section. |
| 4 | Choose **Data quality**. | The checks count with the staff user's own access. |

**Cleanup:** Remove **BarnCRM Find and Export** from the staff user.

## T-HC-03: Health Check report and Re-run

**Purpose:** Confirm the full report reads the org, groups findings and re-runs.
**Prerequisites:** admin.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings** and choose **Health**. | **Health Check**, **What BarnCRM found in your org, and what to do about it.** The card **What we found in your org** shows what was detected (for example **Person Accounts enabled**), **Coexistence mode** and **Recommended**. |
| 2 | Read the findings. | Grouped under **Your org**, **Licenses**, **Access** and **Settings**. Each has a severity (**Needs fixing**, **Worth knowing** or **Information**), a title, a sentence on what to do and, for most, a button. |
| 3 | Find **Your org at a glance**. | An **Information** finding that ends by saying Shield Platform Encryption cannot be detected from inside the app. |
| 4 | Find the automation finding. | **Automation is running normally**, **Information**. |
| 5 | Click **Re-run**. | **Reading your org**, then the report again. |

**Cleanup:** None.

## T-HC-04: A fix button asks first

**Purpose:** Confirm a fix shows what it will do, Cancel changes nothing, and Confirm does exactly that and is recorded.
**Prerequisites:** admin. A fresh org: no BarnCRM nightly job scheduled yet.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **BarnCRM Settings**, **Health**, find **Nightly jobs are not scheduled**. | It names the jobs, for example **Seasonal address swap**, **Error digest email**, **Empty household tidy-up**, and has **Schedule all nightly jobs**. |
| 2 | Click **Schedule all nightly jobs**. | A dialog **Before this fix runs**: **This is what the fix will do. Nothing changes until you confirm.**, the same list, **Confirm** and **Cancel**. |
| 3 | Press Escape. | The dialog closes and focus returns to the button. Nothing is scheduled. |
| 4 | Click **Schedule all nightly jobs**, then **Confirm**. | **Done. Scheduled: ...** naming each job, and the report re-runs. **Nightly jobs are not scheduled** is gone. |
| 5 | In **BarnCRM Settings**, scroll to **Recent changes**. | The top entry starts **Health Check:** with the button's name, your name and the time. |
| 6 | Open **BarnCRM Settings**, **Addresses**. | The seasonal address swap shows as scheduled, so the job can be stopped on its own page. |

**Cleanup:** None. Leave the jobs scheduled.

## T-HC-05: An empty household finding links the record

**Purpose:** Confirm a data finding counts and links an empty household and changes nothing.
**Prerequisites:** admin. A Household account with no members, for example `Empty Test Household` from T-DM-08.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **BarnCRM Settings**, **Health**, click **Re-run**. | **1 household has nobody in it** (or **N households have nobody in them**), **Information**, with **The first is linked below.** or **The first N are linked below.** |
| 2 | Look for a fix button on it. | None: what to do with an empty household is your decision. |
| 3 | Click the `Empty Test Household` link. | The household opens, unchanged. |
| 4 | Delete `Empty Test Household`, return and **Re-run**. | The count drops by one (the finding is gone if it was the only one). |

**Cleanup:** None.

## T-HC-06: Health Check as the read-only user

**Purpose:** Confirm someone without Manage BarnCRM Settings can read the report but not fix anything, and access checks are skipped.
**Prerequisites:** read-only; admin to make a finding with a button (stop one nightly job on its page, for example the seasonal address swap on **BarnCRM Settings**, **Addresses**).

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, open **BarnCRM Settings** and choose **Health**. | The report shows with **You can read this report but not change anything. Ask an administrator for the Manage BarnCRM Settings permission.** |
| 2 | Look under **Access**. | **Only a BarnCRM Admin can see the access checks**, instead of the admin and user counts. |
| 3 | Find **Nightly jobs are not scheduled**. | It is not shown (only administrators see it), and no finding has a fix button. |
| 4 | Check the app's navigation. | No **Org Optimizer** tab. |

**Cleanup:** As admin, run **Schedule all nightly jobs** again.

## T-HC-07: Health Check's last result on Home

**Purpose:** Confirm Home shows the last full run instead of running each time, and Run now refreshes it.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the BarnCRM home page. | The Health Check tile shows **Last run** with a date and time and **N to fix, N to be aware of, N for your information.**, or **Health Check has not run yet. Click Run now to check this org.** |
| 2 | Click **Run now**. | **Reading your org**, then the whole report in the tile. |
| 3 | Reload the home page. | **Last run** shows the time of step 2, with its counts. |

**Cleanup:** None.

## T-HC-08: Storage and limits

**Purpose:** Confirm the read-only storage section shows the org's limits and BarnCRM's own records.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Org Optimizer**, choose **Storage and limits**. | **Your org's limits** lists **Data storage (MB)**, **File storage (MB)**, **API requests in the last 24 hours**, **Background jobs (asynchronous Apex) in the last 24 hours**, **Single emails sent today**, each as **N of N (N%)**. |
| 2 | Read **What BarnCRM stores**. | **Records BarnCRM keeps for imports, undo and errors. Salesforce counts most records as 2 KB.** and a table with **Kind of record**, **Records** and **About (MB)**. |
| 3 | Look for anything that changes data. | Only **Refresh**. Click it: the numbers reload. |

**Cleanup:** None.

## T-HC-09: Unused setup and its thresholds

**Purpose:** Confirm the read-only checks list counts and Setup links, and the thresholds are bounded settings.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Org Optimizer**, choose **Unused setup**. | **Nothing here is changed for you. Open each item in Setup and decide whether to remove it.** Then eight checks, including **Active users who have not logged in for 90 days**, **Permission sets nobody is assigned**, **Reports not run for 365 days**, **Email templates never used**, **Inactive flows**, **Scheduled jobs owned by inactive users**, **Objects near their custom field limit**, **Record types no record uses, or inactive**. |
| 2 | Read a check with a count above 0. | Up to five names and **Open in Setup**. A check the org does not allow reads **Could not check: your access or this org does not allow it.** |
| 3 | Click **Open in Setup** on one check. | The matching Setup page opens. Nothing was removed. |
| 4 | In **BarnCRM Settings**, **General**, set **Days before a user is unused** to `10` and click **Save**. | Nothing is saved; the value is marked as outside its range (30 to 365). |
| 5 | Set it to `60`, **Save**, then **Refresh** on **Unused setup**. | **Your settings are saved.** The first check reads **Active users who have not logged in for 60 days**. |

**Cleanup:** Set **Days before a user is unused** back to `90`.
