# Rollup Builder

Scripts for building, calculating, changing and switching off your own rollups, and for who may do it. Setup detail: [Rollups](../admin-guide/rollups.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and BarnCRM Rollup Builder deployed and sample data loaded unless a script says otherwise. Giving is not needed: these scripts use a rollup you build yourself, so the shipped giving totals are left alone.

Every script after T-RB-02 uses the rollup T-RB-02 builds, **Test children per household**: a count of the people in a household whose **Household Role** is **Child**. In the sample data, **The Garcia Family** has three people: Harper (Head), Luis (Spouse or Partner) and Diego (Child), so the expected total is 1.

The **Records to count** option in step 2 is named from your org's object and field labels, in the form "Contact, by Account ID". If your org renamed either label, pick the option that counts people by their household account.

## T-RB-01: Open the Rollup Builder and schedule the nightly run

**Purpose:** confirm the app, tab and list open and the nightly run can be scheduled and stopped.
**Prerequisites:** admin user (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | From the App Launcher, open the **BarnCRM Rollup Builder** app. | The app opens on the **Rollup Builder** tab. The **Rollup Settings** tab is next to it. |
| 2 | Look at the page. | A **Rollup Builder** card holds a **Rollups** card that starts "Every total BarnCRM keeps up to date for you, and when each one was last calculated." Under it is a **Needs attention** section. No read only notice is shown. |
| 3 | Look at the buttons above the list. | **Schedule nightly recalculation** (or **Stop the nightly recalculation**), **Recalculate all**, **Restore shipped rollups** and **New rollup** are all enabled. |
| 4 | If the button reads **Stop the nightly recalculation**, click it. | The text above the buttons reads "Nightly recalculation is not scheduled yet." **Needs attention** shows "The nightly run is not scheduled, so totals a bulk change missed are not put right overnight." |
| 5 | Click **Schedule nightly recalculation**. | The text reads "Nightly recalculation is scheduled for 2:00 AM." The button now reads **Stop the nightly recalculation**, and the not scheduled warning under **Needs attention** is gone. |
| 6 | Open the **BarnCRM** app, then **BarnCRM Settings**, then the **Rollups** section. | The section opens the same Rollup Builder list, with the same schedule message. |

**Cleanup:** leave the nightly run scheduled.

## T-RB-02: Build a rollup in five steps

**Purpose:** build a rollup with a condition, preview it on a real record and save it with its first calculation.
**Prerequisites:** admin user; sample data loaded. In Setup, on **Account**, create a Number field labelled **Test Children Count** (API name `Test_Children_Count__c`, 18 digits, 0 decimals), visible to your profile and added to the household page layout.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, click **New rollup**. | The Builder opens above the list with a five step path: **Where should the number appear?**, **What should be counted?**, **How should it be calculated?**, **Which records count?**, **Check and save**. The heading reads **Where should the number appear?** |
| 2 | In **Record that shows the total**, choose **Account**. In **Field that shows the total**, choose **Test Children Count**. Click **Next**. | The heading reads **What should be counted?** |
| 3 | In **Records to count**, choose **Contact, by Account ID**. Click **Next**. | The heading reads **How should it be calculated?** |
| 4 | In **Calculation**, choose **Count**. Leave **Time window** on **All time**. | No **Field to calculate** box appears (Count reads no field). No **Date that decides the year** box appears. |
| 5 | Click **Next**. | The heading reads **Which records count?** It shows a **Conditions** builder and an **Only for some records** builder. |
| 6 | Under **Conditions**, click **Add condition**. Choose **Field** = **Household Role**, **Comparison** = **is**, **Value** = **Child**. | The conditions read back as a sentence about contacts whose Household Role is Child. |
| 7 | Click **Next**. | The heading reads **Check and save**. A sentence of the form "Count of Contact, by Account ID, shown in ..., Test Children Count." is shown, and "This rollup will maintain about N records." where N is the number of accounts in the org. |
| 8 | In **See it on a record**, pick **The Garcia Family**. | "Calculated: 1. On the record now: (empty)." |
| 9 | In **Name**, type `Test children per household`. In **What this number means**, type `Children in the household`. Leave **Mode** on its default and **Active** on. | The fields hold what you typed. **Mode** shows the org's default rollup mode (**Both (recommended)** unless it was changed). |
| 10 | Click **Save and calculate now**. | The Builder closes. A green notice reads "Rollup saved, and its recalculation has started." |
| 11 | Find **Test children per household** in the list. | The row shows **Children in the household** under the name, a **What it counts** value, **Where it shows** names the Test Children Count field, the mode you saved, and **Active** on. |
| 12 | Wait a minute and refresh the page. | The row's **Last calculated** shows a time from a moment ago, not **Not calculated yet**. |
| 13 | Open **The Garcia Family** household. | **Test Children Count** shows 1. |
| 14 | Open any household with no person whose role is Child (for example a single-person household). | **Test Children Count** shows 0, not blank. |

**Cleanup:** keep the rollup and field; later scripts use them.

## T-RB-03: A change to a counted record updates the total

**Purpose:** confirm a saved change on a source record moves the total on the target record without any manual recalculation.
**Prerequisites:** admin user; T-RB-02 done; **Test children per household** in **Both (recommended)** or **Instantly** mode and active; **When instant totals are calculated** at its default.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **The Garcia Family** household. | **Test Children Count** shows 1. |
| 2 | Open Diego Garcia. Edit **Household Role** from **Child** to **Other** and save. | The save succeeds with no error. |
| 3 | Wait up to a minute, then open **The Garcia Family** and refresh. | **Test Children Count** shows 0. |
| 4 | Open Diego Garcia. Edit **Household Role** back to **Child** and save. | The save succeeds. |
| 5 | Wait up to a minute, then open **The Garcia Family** and refresh. | **Test Children Count** shows 1 again. |

**Cleanup:** None (Diego is back to **Child**).

## T-RB-04: Recalculate one rollup and recalculate all

**Purpose:** confirm single and full recalculation start, show their messages and offer the estimate and Run tonight.
**Prerequisites:** admin user; T-RB-02 done; nightly run scheduled (T-RB-01).

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, note the **Last calculated** time of **Test children per household**. Click **Recalculate** on its row. | A green notice reads "Recalculation started. This page updates as it finishes." |
| 2 | Wait a minute and refresh. | The row's **Last calculated** time has moved on. |
| 3 | Click **Recalculate all**. | Nothing starts yet. A box shows "About N records, roughly M minutes." with **Cancel**, **Start now** and **Run tonight**. Between 8 AM and 6 PM on a weekday it also says "People are working now. A long run competes with them saving records, so consider running it tonight." |
| 4 | Click **Cancel**. | The box closes and no notice appears. |
| 5 | Click **Recalculate all**, then **Run tonight**. | The notice reads "The nightly run already recalculates every Every night and Both total at 2:00 AM. Instantly totals are kept by each save; to rebuild them too, choose Start now." |
| 6 | Click **Recalculate all**, then **Start now**. | The notice reads "Recalculation started. This page updates as it finishes." **Needs attention** shows a line starting "A full run is going:" or, once done, "Last full run:". |
| 7 | Straight away, click **Recalculate** on any row. | If the full run is still going, the red message reads "A full recalculation is already running. Its totals will be on the records when it finishes, so try again after that." |
| 8 | When the full run has finished, refresh. | Every active row's **Last calculated** time is recent. **The Garcia Family** still shows **Test Children Count** 1. |

**Cleanup:** None.

## T-RB-05: Edit a rollup, change its mode and copy it

**Purpose:** confirm Edit reopens a saved rollup with its values, the list's Mode control saves, and Copy cannot write a field the original already fills.
**Prerequisites:** admin user; T-RB-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **Edit** on **Test children per household**. | The Builder opens on **Where should the number appear?** with **Account** and **Test Children Count** filled in. |
| 2 | Click **Next** three times. | Each step shows what you saved: **Contact, by Account ID**, **Count**, **All time**, and condition 1 on **Household Role** **is** **Child**. |
| 3 | Click **Next**. On **Check and save**, change **What this number means** to `Children in this household` and click **Save**. | The Builder closes. The notice reads "Rollup saved. It is calculated in its next run." The row shows the new description. |
| 4 | In the row's **Mode** list, choose **Every night**. | No error; the row shows **Every night** after the page refreshes. |
| 5 | Set **Mode** back to **Both (recommended)**. | The row shows **Both (recommended)**. |
| 6 | Click **Copy** on the row. | The Builder opens with every step filled in from the original. **Field that shows the total** lists the field as "Test Children Count (filled by Test children per household)". |
| 7 | Click **Next** until **Check and save**. | **Name** reads "Copy of Test children per household". |
| 8 | Click **Save**. | Nothing is saved. A red message reads "Test children per household already fills this field for some of the same records, so the two would overwrite each other. Choose another field, or add conditions under Only for some records so they never pick the same record." |
| 9 | Click **Cancel**. | The Builder closes. The list has no "Copy of" row. |

**Cleanup:** None.

## T-RB-06: Bad input is refused

**Purpose:** confirm each step and the save refuse incomplete or impossible rollups with the message from code.
**Prerequisites:** admin user; T-RB-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **New rollup**. Click **Next** without choosing anything. | The Builder stays on step 1. A red message reads "Choose the kind of record and the field that show the total, in step 1." |
| 2 | Choose **Account** and a writable number field you created (for example a second test field, or **Test Children Count**). Click **Next**, then click **Next** again with no **Records to count**. | Stays on step 2: "Choose the records to count and how they link to the record that shows the total, in step 2." |
| 3 | Choose **Contact, by Account ID**, click **Next**, then **Next** again with no **Calculation**. | Stays on step 3: "This calculation reads a field on each record. Fill in Source Field with the field to read." |
| 4 | Choose **Calculation** = **Last**, and a **Field to calculate**. Leave **Which record comes first, by** empty. Click **Next**. | "First and Last need the field that decides which record comes first, usually a date. Choose one in step 3." |
| 5 | Choose **Calculation** = **Count**. Choose **Time window** = **This fiscal year** and leave **Date that decides the year** empty. Click **Next**. | "A fiscal year window needs the date that decides which year a record falls in. Choose a date field in step 3, not a date and time field." |
| 6 | Set **Time window** back to **All time**. Click **Next**. Click **Add condition** and choose only a **Field**. Click **Next**. | Stays on step 4: "Condition 1 needs a field, a comparison and a value. Fill it in or remove it." |
| 7 | Complete condition 1. In **Combine conditions**, type `1 AND 3`. Click **Next**. | "Combine conditions can use only the numbers 1 to 1, AND, OR, NOT and brackets." |
| 8 | Clear **Combine conditions**. Click **Next**. Clear **Name** and click **Save**. | "Give the rollup a name, so you can find it in the list." Nothing is saved. |
| 9 | Click **Cancel**. Click **Edit** on **Test children per household**. On step 3 set **Time window** to **This fiscal year** and **Date that decides the year** to **Birthdate**. Go to **Check and save**, choose **Mode** = **Instantly**, click **Save**. | "This total changes as the date moves on, with no record saved, so only the nightly run keeps it right. Choose Both (recommended) or Every night." Nothing is saved. |
| 10 | Click **Cancel**. Click **Edit** again and go to step 3. | **Time window** is still **All time** (the refused edit was not saved). Click **Cancel**. |

**Cleanup:** None.

## T-RB-07: Switch a rollup off and back on

**Purpose:** confirm a switched off rollup keeps the values it already wrote and stops updating them, and that switching it on and recalculating catches up.
**Prerequisites:** admin user; T-RB-02 done; **The Garcia Family** shows **Test Children Count** 1.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, turn off the **Active** toggle on **Test children per household**. | No error; after the refresh the toggle stays off. |
| 2 | Open **The Garcia Family**. | **Test Children Count** still shows 1. Switching off never clears values already calculated. |
| 3 | Open Diego Garcia, change **Household Role** to **Other** and save. Wait a minute, then refresh **The Garcia Family**. | **Test Children Count** still shows 1: the inactive rollup did not recalculate. |
| 4 | Back on the **Rollup Builder** tab, click **New rollup**, choose **Account**, and open **Field that shows the total**. | **Test Children Count** is listed with no "(filled by ...)" note, because no active rollup fills it. Click **Cancel**. |
| 5 | Turn the **Active** toggle on **Test children per household** back on. | The toggle stays on after the refresh. |
| 6 | Click **Recalculate** on its row and wait a minute. Refresh **The Garcia Family**. | **Test Children Count** shows 0, matching Diego's new role. |
| 7 | Open Diego Garcia, set **Household Role** back to **Child** and save. Wait a minute and refresh **The Garcia Family**. | **Test Children Count** shows 1. |

**Cleanup:** None. To remove the test rollup for good, use **Delete** (T-RB-24) once the other scripts are done.

## T-RB-08: Staff and read-only users see the Builder read only

**Purpose:** confirm only a user with the Manage BarnCRM Settings permission can change rollups, and what everyone else sees.
**Prerequisites:** staff and read-only users (see [Test users](before-you-test.md#test-users)); each holds **Rollup Builder User** (BarnCRM gives it to holders of **BarnCRM Staff** and **BarnCRM Read Only** at install, at each Turn on and with each nightly run; assign it in Setup if it is missing); T-RB-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Log in as the staff user. From the App Launcher, open **BarnCRM Rollup Builder**. | The app opens on the **Rollup Builder** tab. |
| 2 | Look at the top of the list. | A grey notice reads "You can see these totals but not change them. Ask an administrator for the Manage BarnCRM Settings permission." |
| 3 | Look at the buttons and rows. | **Schedule nightly recalculation** (or **Stop the nightly recalculation**), **Recalculate all**, **Restore shipped rollups** and **New rollup** are disabled. On every row the **Mode** list, **Active** toggle, **Recalculate**, **Edit** and **Copy** are disabled. |
| 4 | Find **Test children per household**. | The row shows its name, description, what it counts, where it shows and its **Last calculated** time. |
| 5 | Look below the list. | No **Needs attention** section is shown. |
| 6 | Log in as the read-only user and repeat steps 1 to 5. | Same results as the staff user. |
| 7 | As admin, in Setup remove **Rollup Builder User** from the read-only user. Log in as the read-only user and search the App Launcher for "Rollup". | **BarnCRM Rollup Builder** and the **Rollup Builder** tab are not offered. |
| 8 | As admin, in Setup open the **Rollup Builder Admin** and **Rollup Builder User** permission sets. | **Rollup Builder Admin** gives create, edit and delete on rollup definitions; **Rollup Builder User** gives read only. Both open the app and both tabs. |

**Cleanup:** assign **Rollup Builder User** to the read-only user again.

## T-RB-09: Default rollup mode decides how a new rollup starts

**Purpose:** confirm the Rollup Settings tab changes the mode a new rollup starts with.
**Prerequisites:** admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Rollup Builder**, open the **Rollup Settings** tab. | The settings console shows only the module's settings: **Default rollup mode** and **When instant totals are calculated**. **Fiscal year start month** is not here. |
| 2 | Change **Default rollup mode** to **Every night** and save. | The setting saves and shows **Every night**. |
| 3 | Open **BarnCRM Settings**, **Rollups** section. | **Default rollup mode** shows **Every night** there too. |
| 4 | On the **Rollup Builder** tab, click **New rollup**, complete steps 1 to 4 (any valid choices) and go to **Check and save**. | **Mode** is preselected as **Every night**. |
| 5 | Click **Cancel**. | Nothing is saved. |

**Cleanup:** set **Default rollup mode** back to **Both (recommended)**.

## T-RB-24: Delete a Rollup You Made, and Not a Shipped One

**Purpose:** confirm Delete says what happens, removes an admin-made rollup and leaves its values, and refuses a shipped rollup with the reason.
**Prerequisites:** admin user; T-RB-02 done. Step 6 needs Giving deployed (it ships rollups); skip it otherwise.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, click **Copy** on **Test children per household**, click **Next** until **Check and save**, turn off **Active** and click **Save**. | A row **Copy of Test children per household** appears, switched off. |
| 2 | Click **Delete** on **Copy of Test children per household**. | A **Delete Rollup** box reads "Delete Copy of Test children per household? The values it already wrote stay on the records, but nothing updates them again. This cannot be undone." |
| 3 | Click **Cancel**. | The row is still listed. |
| 4 | Click **Delete** on the same row again, then **OK**. | The notice reads "Rollup deleted. The values it wrote stay on the records." The row is gone; **Test children per household** is still listed. |
| 5 | Open **The Garcia Family**. | **Test Children Count** still shows 1. |
| 6 | Back on the **Rollup Builder** tab, click **Delete** on **Account gift count**. | No confirmation opens. A red message reads "This rollup came with BarnCRM, so it cannot be deleted: Restore shipped rollups would bring it back. Switch it off instead." The row is still listed. |
| 7 | Log in as the staff user and open the **Rollup Builder** tab. | **Delete** is disabled on every row, as **Edit** and **Copy** are. |

**Cleanup:** None.
