# Rollup Builder

Scripts for building, calculating, changing and switching off your own rollups, and for who may do it. Setup detail: [Rollups](../admin-guide/rollups.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and BarnCRM Rollup Builder deployed and sample data loaded unless a script says otherwise. Giving is not needed: these scripts use a rollup you build yourself, so the shipped giving totals are left alone.

Every script after T-RB-02 uses the rollup T-RB-02 builds, **Test children per household**: a count of the people in a household whose **Household Role** is **Child**. In the sample data, **The Garcia Family** has three people: Harper (Head), Luis (Spouse or Partner) and Diego (Child), so the expected total is 1.

The **Records to count** option in step 2 is named from your org's object and field labels, in the form "Contact, by Account ID". If your org renamed either label, pick the option that counts people by their household account.

## T-RB-01: Open the Rollup Builder and Schedule the Nightly Run

**Purpose:** confirm the app, tab and list open and the nightly run can be scheduled and stopped.
**Prerequisites:** admin user (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | From the App Launcher, open the **BarnCRM Admin** app and click **Rollup Builder**. | The **Rollup Builder** tab opens. |
| 2 | Look at the page. | A **Rollup Builder** card holds a **Rollups** card that starts "Every total BarnCRM keeps up to date for you, and when each one was last calculated." Under it is a **Needs Attention** section. No read only notice is shown. |
| 3 | Look at the buttons above the list. | **Schedule nightly recalculation** (or **Stop the nightly recalculation**), **Recalculate All**, **Restore Shipped Rollups** and **New Rollup** are all enabled. |
| 4 | If the button reads **Stop the nightly recalculation**, click it. | The text above the buttons reads "Nightly recalculation is not scheduled yet." **Needs Attention** shows "The nightly run is not scheduled, so totals a bulk change missed are not put right overnight." |
| 5 | Click **Schedule nightly recalculation**. | The text reads "Nightly recalculation is scheduled for 2:00 AM." The button now reads **Stop the nightly recalculation**, and the not scheduled warning under **Needs Attention** is gone. |
| 6 | Open the **BarnCRM Admin** app, then **BarnCRM Settings**, then the **Rollups** section. | The section opens the same Rollup Builder list, with the same schedule message. |

**Cleanup:** leave the nightly run scheduled.

## T-RB-02: Build a Rollup in Five Steps

**Purpose:** build a rollup with a condition, preview it on a real record and save it with its first calculation.
**Prerequisites:** admin user; sample data loaded. In Setup, on **Account**, create a Number field labelled **Test Children Count** (API name `Test_Children_Count__c`, 18 digits, 0 decimals), visible to your profile and added to the household page layout.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, click **New Rollup**. | The Builder opens above the list with a five step path: **Where should the number appear?**, **What should be counted?**, **How should it be calculated?**, **Which records count?**, **Check and save**. The heading reads **Where should the number appear?** |
| 2 | In **Record that shows the total**, choose **Account**. In **Field that shows the total**, choose **Test Children Count**. Click **Next**. | The heading reads **What should be counted?** |
| 3 | In **Records to count**, choose **Contact, by Account ID**. Click **Next**. | The heading reads **How should it be calculated?** |
| 4 | In **Calculation**, choose **Count**. Leave **Time window** on **All time**. | No **Field to calculate** box appears (Count reads no field). No **Date that decides the year** box appears. |
| 5 | Click **Next**. | The heading reads **Which records count?** It shows a **Conditions** builder and an **Only for some records** builder. |
| 6 | Under **Conditions**, click **Add Condition**. Choose **Field** = **Household Role**, **Comparison** = **is**, **Value** = **Child**. | The conditions read back as a sentence about contacts whose Household Role is Child. |
| 7 | Click **Next**. | The heading reads **Check and save**. A sentence of the form "Count of Contact, by Account ID, shown in ..., Test Children Count." is shown, and "This rollup will maintain about N records." where N is the number of accounts in the org. |
| 8 | In **See it on a record**, pick **The Garcia Family**. | "Calculated: 1. On the record now: (empty)." |
| 9 | In **Name**, type `Test children per household`. In **What this number means**, type `Children in the household`. Leave **Mode** on its default and **Active** on. | The fields hold what you typed. **Mode** shows the org's default rollup mode (**Both (recommended)** unless it was changed). |
| 10 | Click **Save and Calculate Now**. | The Builder closes. A green notice reads "Rollup saved, and its recalculation has started." |
| 11 | Find **Test children per household** in the list. | The row is under the **Account** heading and shows **Children in the household** under the name, a **What It Counts** sentence of the form "Number of Contacts by Account, shown in Test Children Count on each Account. Only records that meet its conditions count.", the mode you saved, and **Active** on. |
| 12 | Wait a minute and refresh the page. | The row's **Last Calculated** shows a time from a moment ago, not **Not calculated yet**. |
| 13 | Open **The Garcia Family** household. | **Test Children Count** shows 1. |
| 14 | Open any household with no person whose role is Child (for example a single-person household). | **Test Children Count** shows 0, not blank. |

**Cleanup:** keep the rollup and field; later scripts use them.

## T-RB-03: A Change to a Counted Record Updates the Total

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

## T-RB-04: Recalculate One Rollup and Recalculate All

**Purpose:** confirm single and full recalculation start, show their messages and offer the estimate and Run tonight.
**Prerequisites:** admin user; T-RB-02 done; nightly run scheduled (T-RB-01).

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, note the **Last Calculated** time of **Test children per household**. Click **Recalculate** on its row. | A green notice reads "Recalculation started. This page updates as it finishes." |
| 2 | Wait a minute and refresh. | The row's **Last Calculated** time has moved on. |
| 3 | Click **Recalculate All**. | Nothing starts yet. A box shows "About N records, roughly M minutes." with **Cancel**, **Start Now** and **Run Tonight**. Between 8 AM and 6 PM on a weekday it also says "People are working now. A long run competes with them saving records, so consider running it tonight." |
| 4 | Click **Cancel**. | The box closes and no notice appears. |
| 5 | Click **Recalculate All**, then **Run Tonight**. | The notice reads "The nightly run already recalculates every Every night and Both total at 2:00 AM. Instantly totals are kept by each save; to rebuild them too, choose Start now." |
| 6 | Click **Recalculate All**, then **Start Now**. | The notice reads "Recalculation started. This page updates as it finishes." **Needs Attention** shows a line starting "A full run is going:" or, once done, "Last full run:". |
| 7 | Straight away, click **Recalculate** on any row. | If the full run is still going, the red message reads "A full recalculation is already running. Its totals will be on the records when it finishes, so try again after that." |
| 8 | When the full run has finished, refresh. | Every active row's **Last Calculated** time is recent. **The Garcia Family** still shows **Test Children Count** 1. |

**Cleanup:** None.

## T-RB-05: Edit a Rollup, Change Its Mode and Copy It

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

## T-RB-06: Bad Input Is Refused

**Purpose:** confirm each step and the save refuse incomplete or impossible rollups with the message from code.
**Prerequisites:** admin user; T-RB-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **New Rollup**. Click **Next** without choosing anything. | The Builder stays on step 1. A red message reads "Choose the kind of record and the field that show the total, in step 1." |
| 2 | Choose **Account** and a writable number field you created (for example a second test field, or **Test Children Count**). Click **Next**, then click **Next** again with no **Records to count**. | Stays on step 2: "Choose the records to count and how they link to the record that shows the total, in step 2." |
| 3 | Choose **Contact, by Account ID**, click **Next**, then **Next** again with no **Calculation**. | Stays on step 3: "This calculation reads a field on each record. Fill in Source Field with the field to read." |
| 4 | Choose **Calculation** = **Last**, and a **Field to calculate**. Leave **Which record comes first, by** empty. Click **Next**. | "First and Last need the field that decides which record comes first, usually a date. Choose one in step 3." |
| 5 | Choose **Calculation** = **Count**. Choose **Time window** = **This fiscal year** and leave **Date that decides the year** empty. Click **Next**. | "A fiscal year window needs the date that decides which year a record falls in. Choose a date field in step 3, not a date and time field." |
| 6 | Set **Time window** back to **All time**. Click **Next**. Click **Add Condition** and choose only a **Field**. Click **Next**. | Stays on step 4: "Condition 1 needs a field, a comparison and a value. Fill it in or remove it." |
| 7 | Complete condition 1. In **Combine conditions**, type `1 AND 3`. Click **Next**. | "Combine conditions can use only the numbers 1 to 1, AND, OR, NOT and brackets." |
| 8 | Clear **Combine conditions**. Click **Next**. Clear **Name** and click **Save**. | "Give the rollup a name, so you can find it in the list." Nothing is saved. |
| 9 | Click **Cancel**. Click **Edit** on **Test children per household**. On step 3 set **Time window** to **This fiscal year** and **Date that decides the year** to **Birthdate**. Go to **Check and save**, choose **Mode** = **Instantly**, click **Save**. | "This total changes as the date moves on, with no record saved, so only the nightly run keeps it right. Choose Both (recommended) or Every night." Nothing is saved. |
| 10 | Click **Cancel**. Click **Edit** again and go to step 3. | **Time window** is still **All time** (the refused edit was not saved). Click **Cancel**. |

**Cleanup:** None.

## T-RB-07: Switch a Rollup Off and Back On

**Purpose:** confirm a switched off rollup keeps the values it already wrote and stops updating them, and that switching it on and recalculating catches up.
**Prerequisites:** admin user; T-RB-02 done; **The Garcia Family** shows **Test Children Count** 1.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, turn off the **Active** toggle on **Test children per household**. | No error; after the refresh the toggle stays off. |
| 2 | Open **The Garcia Family**. | **Test Children Count** still shows 1. Switching off never clears values already calculated. |
| 3 | Open Diego Garcia, change **Household Role** to **Other** and save. Wait a minute, then refresh **The Garcia Family**. | **Test Children Count** still shows 1: the inactive rollup did not recalculate. |
| 4 | Back on the **Rollup Builder** tab, click **New Rollup**, choose **Account**, and open **Field that shows the total**. | **Test Children Count** is listed with no "(filled by ...)" note, because no active rollup fills it. Click **Cancel**. |
| 5 | Turn the **Active** toggle on **Test children per household** back on. | The toggle stays on after the refresh. |
| 6 | Click **Recalculate** on its row and wait a minute. Refresh **The Garcia Family**. | **Test Children Count** shows 0, matching Diego's new role. |
| 7 | Open Diego Garcia, set **Household Role** back to **Child** and save. Wait a minute and refresh **The Garcia Family**. | **Test Children Count** shows 1. |

**Cleanup:** None. To remove the test rollup for good, use **Delete** (T-RB-24) once the other scripts are done.

## T-RB-08: Staff and Read-Only Users See the Builder Read Only

**Purpose:** confirm only a user with the Manage BarnCRM Settings permission can change rollups, and what everyone else sees.
**Prerequisites:** staff and read-only users (see [Test users](before-you-test.md#test-users)); each holds **Rollup Builder User** (BarnCRM gives it to holders of **BarnCRM Staff** and **BarnCRM Read Only** at install, at each Turn on and with each nightly run; assign it in Setup if it is missing); T-RB-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Log in as the staff user. In the App Launcher, search for "Rollup" and open the **Rollup Builder** tab. | The **Rollup Builder** tab opens. |
| 2 | Look at the top of the list. | A grey notice reads "You can see these totals but not change them. Ask your BarnCRM admin for the Manage BarnCRM Settings permission." |
| 3 | Look at the buttons and rows. | **Schedule nightly recalculation** (or **Stop the nightly recalculation**), **Recalculate All**, **Restore Shipped Rollups** and **New Rollup** are disabled. On every row the **Mode** list, **Active** toggle, **Recalculate**, **Edit** and **Copy** are disabled. |
| 4 | Find **Test children per household**. | The row shows its name, description, what it counts, where it shows and its **Last Calculated** time. |
| 5 | Look below the list. | No **Needs Attention** section is shown. |
| 6 | Log in as the read-only user and repeat steps 1 to 5. | Same results as the staff user. |
| 7 | As admin, in Setup remove **Rollup Builder User** from the read-only user. Log in as the read-only user and search the App Launcher for "Rollup". | The **Rollup Builder** tab is not offered. |
| 8 | As admin, in Setup open the **Rollup Builder Admin** and **Rollup Builder User** permission sets. | **Rollup Builder Admin** gives create, edit and delete on rollup definitions; **Rollup Builder User** gives read only. Both open the **Rollup Builder** tab; neither names an app. |

**Cleanup:** assign **Rollup Builder User** to the read-only user again.

## T-RB-09: Default Rollup Mode Decides How a New Rollup Starts

**Purpose:** confirm the Rollups section of BarnCRM Settings shows the shipped defaults on a fresh org and changes the mode a new rollup starts with.
**Prerequisites:** admin user. For step 1, a fresh org or a source-deployed one where nobody has saved these two settings yet.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings** and choose the **Rollups** section. | **Default rollup mode**, **When instant totals are calculated** and a **Rollups** row with an **Open Rollup Builder** button are shown. **Fiscal year start month** is not here (it is the org's, shown read only in **General**). The **BarnCRM Rollup Builder** app has no Settings tab. On a fresh org **Default rollup mode** shows **Both (recommended)** and **When instant totals are calculated** shows **After the save (recommended)** (neither is empty). |
| 2 | Change **Default rollup mode** to **Every night** and save. | The setting saves and shows **Every night**. |
| 3 | Reload the page and open the **Rollups** section again. | **Default rollup mode** still shows **Every night**. |
| 4 | On the **Rollup Builder** tab, click **New Rollup**, complete steps 1 to 4 (any valid choices) and go to **Check and save**. | **Mode** is preselected as **Every night**. |
| 5 | Click **Cancel**. | Nothing is saved. |

**Cleanup:** set **Default rollup mode** back to **Both (recommended)**.

## T-RB-10: Standard Objects Are Offered, Common Ones First

**Purpose:** confirm the Builder offers Salesforce standard objects, lists the common ones first and finds any other by search (ADR-0136).
**Prerequisites:** admin user; a writable Number field on Account for the test, for example **Test Task Count** (`Test_Task_Count__c`, created in Setup); **The Garcia Family** has two open tasks (create them in Setup or on the record, **Related To** = **The Garcia Family**).

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, click **New Rollup** and open **Record that shows the total**. | The list starts with Account, Contact, BarnCRM's objects and the common standard objects this org has, for example Task, Event and Asset, and in an org with Sales Cloud also Opportunity, Case and Campaign. No sharing or history objects (such as Account Share) are listed. |
| 2 | In **Find another object**, type `work`. Open **Record that shows the total** again. | Only objects whose name contains "work" are listed (for example Work Order, if the org has it). Clearing the box shows the common list again. |
| 3 | Clear **Find another object**. Choose **Account** and **Test Task Count**. Click **Next**. | Step 2 lists, among the others, **Task, by Related To ID** (and in an org with Sales Cloud, **Opportunity, by Account ID**). |
| 4 | Choose **Task, by Related To ID**. Click **Next**. Choose **Calculation** = **Count**. Click **Next**. Add the condition **Status** **is not** **Completed**. Click **Next**. | Step 5 shows the sentence, and the notice "Instant totals are not available yet for Tasks. This total is updated by the nightly run and when you click Recalculate. To make it instant, turn on instant totals for it below, or use the Recalculate rollups Flow template and choose Both (recommended)." Below the mode, the Task line reads **Not set up: these totals update every night and when you click Recalculate.** with **Turn On Instant Totals**. |
| 5 | In **See it on a record**, choose **The Garcia Family**. | The preview shows 2 as the calculated total. |
| 6 | Name it **Test open tasks**, leave the mode, click **Save and Calculate Now**. | Saved. After the recalculation finishes, **The Garcia Family** shows **Test Task Count** 2. |

**Cleanup:** delete **Test open tasks** (or set it inactive) and the two test tasks.

## T-RB-11: Instantly Alone Is Refused for Records with No Instant Updates

**Purpose:** confirm a rollup that counts records with no rollup trigger cannot be Instantly only, in the Builder or from the list (ADR-0136).
**Prerequisites:** admin user; T-RB-10 done up to step 6 (**Test open tasks** saved).

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **Edit** on **Test open tasks** and go to **Check and save**. | **Mode** offers **Every night** and **Both (recommended)** only; **Instantly** is not offered. The "Instant totals are not available yet for Tasks" notice is shown. |
| 2 | Click **Cancel**. In the rollup list, change the mode of **Test open tasks** to **Instantly**. | An error message reads "Instant totals are not available yet for Tasks, so this total cannot be Instantly only. Choose Both (recommended) or Every night." The mode stays as it was. |
| 3 | Click **Edit** on **Test children per household** and go to **Check and save**. | **Instantly** is offered and no notice is shown: people (Contact) have instant updates. Click **Cancel**. |

**Cleanup:** delete **Test open tasks** (or set it inactive) if T-RB-10's cleanup has not.

## T-RB-12: Only the First N Records, in Descending Order

**Purpose:** confirm a text list keeps only its first values in the order chosen (ADR-0136).
**Prerequisites:** admin user; sample data loaded. In Setup, on **Account**, create a Text field labelled **Test Names** (API name `Test_Names__c`, length 255), visible to your profile.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, click **New Rollup**. Choose **Account** and **Test Names**, click **Next**, choose **Contact, by Account ID** and click **Next**. | The heading reads **How should it be calculated?** |
| 2 | In **Calculation**, choose **Text list**. In **Field to calculate**, choose **First Name**. | **Only the first N records**, **Which record comes first, by**, **Order** (showing **Ascending**) and **Separate the values with** appear. |
| 3 | In **Only the first N records**, enter `2`. Leave **Which record comes first, by** empty and click **Next**. | The step does not move on and says "Only the first N records needs a field to order by, so BarnCRM knows which records come first. Choose one, or clear the limit." |
| 4 | In **Which record comes first, by**, choose **First Name**. In **Order**, choose **Descending**. Click **Next** twice. | The heading reads **Check and save**. |
| 5 | In **See it on a record**, pick **The Garcia Family**. | "Calculated: Luis, Harper. On the record now: (empty)." The two names last in the alphabet, Diego left out. |
| 6 | Click **Back** twice, clear **Only the first N records**, click **Next** twice and pick **The Garcia Family** again. | "Calculated: Luis, Harper, Diego. On the record now: (empty)." |
| 7 | Click **Cancel**. | Nothing is saved. |

## T-RB-13: First and Last Take No Limit or Order, Count Takes No Limit

**Purpose:** confirm the Builder offers a row limit and a direction only where they mean something.
**Prerequisites:** admin user; the **Test Names** field from T-RB-12.

| Step | Action | Expected result |
|---|---|---|
| 1 | Start a new rollup on **Account**, **Test Names**, **Contact, by Account ID**, and go to step 3. | The heading reads **How should it be calculated?** |
| 2 | In **Calculation**, choose **First**. | **Which record comes first, by** appears; **Only the first N records** and **Order** do not. |
| 3 | Click **Cancel**. Start a new rollup on **Account** and **Test Children Count** (from T-RB-02), **Contact, by Account ID**, and go to step 3. Choose **Count**. | **Only the first N records** and **Order** do not appear. |
| 4 | Click **Cancel**. | Nothing is saved. |

## T-RB-14: Pipe and Custom Separators

**Purpose:** confirm a text list can be separated by a pipe or by characters you type (ADR-0136).
**Prerequisites:** admin user; sample data loaded; the **Test Names** field from T-RB-12.

| Step | Action | Expected result |
|---|---|---|
| 1 | Start a new rollup on **Account**, **Test Names**, **Contact, by Account ID**, and go to step 3. Choose **Text list** and, in **Field to calculate**, **First Name**. | **Separate the values with** appears. |
| 2 | In **Separate the values with**, choose **Pipe**. Click **Next** twice and, in **See it on a record**, pick **The Garcia Family**. | "Calculated: Diego \| Harper \| Luis. On the record now: (empty)." |
| 3 | Click **Back** twice. In **Separate the values with**, choose **Custom**. | A **Custom delimiter** box appears. |
| 4 | Leave **Custom delimiter** empty and click **Next**. | The step does not move on and says "Type the characters that go between the values in Custom delimiter, or choose another delimiter." |
| 5 | In **Custom delimiter**, type `/`. Click **Next** twice and pick **The Garcia Family**. | "Calculated: Diego/Harper/Luis. On the record now: (empty)." |
| 6 | Click **Back** twice. In **Custom delimiter**, replace the text with a space, a hyphen and a space (` - `). Click **Next** twice and pick **The Garcia Family**. | "Calculated: Diego - Harper - Luis. On the record now: (empty)." The spaces are kept. |
| 7 | Click **Cancel**. | Nothing is saved. |

## T-RB-15: Include Deleted and Archived Records

**Purpose:** confirm a rollup counts a deleted record only when it includes deleted records (ADR-0136).
**Prerequisites:** admin user; sample data loaded; the **Test Names** field from T-RB-12. Create a contact, First Name **Zed**, Last Name **Garcia**, Account **The Garcia Family**, then delete it.

| Step | Action | Expected result |
|---|---|---|
| 1 | Start a new rollup on **Account**, **Test Names**, **Contact, by Account ID**, go to step 3, choose **Text list** and **First Name**, and click **Next**. | The heading reads **Which records count?** An unticked **Include deleted and archived records** box sits under the conditions. |
| 2 | Click **Next** and pick **The Garcia Family** in **See it on a record**. | "Calculated: Diego, Harper, Luis. On the record now: (empty)." Zed is not counted. |
| 3 | Click **Back**, tick **Include deleted and archived records**, click **Next** and pick **The Garcia Family** again. | "Calculated: Diego, Harper, Luis, Zed. On the record now: (empty)." |
| 4 | Click **Cancel**. | Nothing is saved. |

**Cleanup:** delete Zed Garcia from the Recycle Bin.

## T-RB-16: A Condition on a Field One Lookup Away

**Purpose:** confirm a condition can read a field of the record the counted records point to, one lookup away, and that the Builder says when such a total may not update at once.
**Prerequisites:** admin user; T-RB-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **New Rollup**. Choose **Account** and **Test Children Count**, then **Contact, by Account ID**, then **Calculation** = **Count**, and click **Next** until **Which records count?** | Step 4 shows the **Conditions** builder. No note about another record is shown. |
| 2 | Under **Conditions**, click **Add Condition** and open **Field**. | After the contact's own fields, the list offers fields of the records a contact points to, written as the lookup and the field, for example **Account > Account Name** and **Reports To > Last Name**. No **Created By > ...** or **Last Modified By > ...** fields are offered, and nothing two lookups away (such as **Account > Parent Account > ...**). |
| 3 | Choose **Account > Account Name**, **Comparison** = **is**, **Value** = `The Garcia Family`. | The sentence reads about contacts whose Account > Account Name is The Garcia Family. Below the conditions a grey note reads "This filter reads a field of another record. When that record changes, totals update at once only if its object has rollup triggers. Otherwise the nightly run, or Recalculate on the Rollups page, puts them right." |
| 4 | Click **Next**. In **See it on a record**, pick **The Garcia Family**. | The preview starts "Calculated: 3." (Harper, Luis and Diego). No error. |
| 5 | Pick any other household. | The preview starts "Calculated: 0." |
| 6 | Click **Back**, remove the condition. | The note about another record disappears. Click **Cancel**; nothing is saved. |

**Cleanup:** None.

## T-RB-17: A Picklist Filled by Last, and a Value It Does Not Have

**Purpose:** confirm First and Last can fill a picklist, the save refuses a source picklist with values the target lacks, and a text value the picklist lacks is left out and logged.
**Prerequisites:** admin user; T-RB-02 done. In Setup, on **Account**, create a Picklist field labelled **Test Last Role** (API name `Test_Last_Role__c`) with the values **Head**, **Child** and **Other** only (no **Spouse or Partner**), visible to your profile and on the household page layout.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **New Rollup**. Choose **Account** and, in **Field that shows the total**, **Test Last Role**. Choose **Contact, by Account ID** and click **Next**. | **Test Last Role** was offered in step 1. **Calculation** offers only **First** and **Last**. |
| 2 | Choose **Last**. Open **Field to calculate**. | Only picklist and text fields are offered (for example **Household Role**, **Last Name**), no number or date fields. |
| 3 | Choose **Household Role** and **Which record comes first, by** = **Created Date**. Click **Next** twice, name it `Test last role`, and click **Save**. | Nothing is saved. A red message reads "The picklist you fill does not have these values of the field you copy: Spouse or Partner. Add them to that picklist, or choose another field." |
| 4 | Keep the Builder open. In Setup, add the value **Spouse or Partner** to **Test Last Role**. Back in the Builder, click **Save and Calculate Now**. | "Rollup saved, and its recalculation has started." |
| 5 | Wait a minute and open **The Garcia Family**. | **Test Last Role** shows the Household Role of the Garcia person created last (Head, Spouse or Partner, or Child). |
| 6 | Click **Edit** on **Test last role**. On step 3 change **Field to calculate** to **Last Name**. Save and calculate now, wait a minute, and refresh **The Garcia Family**. | **Test Last Role** still shows the role from step 5: a last name is not a value of the picklist. |
| 7 | Open the **Error Log**. | A Warning from `RollupWriter` reads "A rollup could not put "Garcia" in Test Last Role, because it is not a value of that picklist. The record keeps the value it had. Add the value to the picklist, or change the rollup." (with that person's last name). |

**Cleanup:** switch **Test last role** off and delete the **Test Last Role** field in Setup.

## T-RB-19: Skip a Rollup for People with a Custom Permission

**Purpose:** confirm saves by a holder of the rollup's bypass custom permission leave its total alone, Recalculate still corrects it, and an unknown name is refused.
**Prerequisites:** admin user; T-RB-02 done; **Test children per household** in **Both (recommended)** and active; **The Garcia Family** shows **Test Children Count** 1.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Setup, **Custom Permissions**, click **New**. Label **Test Data Migration**, name `Test_Data_Migration`. Save. Create a permission set **Test Data Migration**, add that custom permission under **Custom Permissions**, and assign the permission set to yourself. | The permission set is assigned to you. |
| 2 | On the **Rollup Builder** tab, edit **Test children per household**, go to **Check and save** and enter `No_Such_Permission` in **Skip for people with this custom permission (optional)**. Click **Save**. | The save is refused: "No custom permission named No_Such_Permission exists in this org. ..." |
| 3 | Replace it with `Test_Data_Migration` and click **Save**. | The rollup saves. |
| 4 | Open Diego Garcia. Edit **Household Role** from **Child** to **Other** and save. Wait a minute, then open **The Garcia Family** and refresh. | **Test Children Count** still shows 1: your save skipped this rollup. |
| 5 | On the **Rollup Builder** tab, click **Recalculate** on **Test children per household**. When it finishes, refresh **The Garcia Family**. | **Test Children Count** shows 0. |

**Cleanup:** edit the rollup and clear **Skip for people with this custom permission (optional)**; set Diego's **Household Role** back to **Child** and check the total returns to 1; remove the **Test Data Migration** permission set assignment.

## T-RB-20: Recalculate Totals on This Record From a Flow

**Purpose:** confirm the Flow action recalculates a record's totals, every rollup or the one named, and logs a name that matches nothing.
**Prerequisites:** admin user; T-RB-02 done; **The Garcia Family** shows **Test Children Count** 1.

| Step | Action | Expected result |
|---|---|---|
| 1 | Edit **Test children per household** and set its mode to **Every night**. Save. Open Diego Garcia, change **Household Role** to **Other** and save. Refresh **The Garcia Family** after a minute. | **Test Children Count** still shows 1 (nightly only). |
| 2 | In Setup, **Flows**, click **New Flow**, choose **Autolaunched Flow (No Trigger)**. Create a Text variable `recordId`, **Available for input**. Add an **Action**, search **Recalculate totals on this record** (category **BarnCRM**), set **Record ID** to `{!recordId}`. Save as **Test recalculate totals**. | The action is listed and the flow saves. |
| 3 | Click **Debug**, enter the Id of **The Garcia Family** in `recordId` and run. Refresh **The Garcia Family**. | The debug run succeeds. **Test Children Count** shows 0. |
| 4 | Set Diego's **Household Role** back to **Child**. In the flow, set the action's **Rollup (optional)** to `No such rollup`, save, and debug again with the same Id. | The run succeeds. **Test Children Count** still shows 0. The Error Log has a Warning beginning "Recalculate totals on this record: no active rollup ..." naming `No such rollup`. |
| 5 | Set **Rollup (optional)** to `Test children per household`, save, and debug again. | **Test Children Count** shows 1. |

**Cleanup:** set the rollup's mode back to **Both (recommended)**; delete the **Test recalculate totals** flow.

## T-RB-21: Recalculate a Record's Totals From Apex

**Purpose:** confirm the global Apex entry point recalculates a record's totals.
**Prerequisites:** admin user with permission to run anonymous Apex; T-RB-02 done; **The Garcia Family** shows **Test Children Count** 1.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set **Test children per household** to **Every night**. Change Diego's **Household Role** to **Other** and save. | After a minute **Test Children Count** still shows 1. |
| 2 | Open the Developer Console, **Debug**, **Open Execute Anonymous Window**, and run `RollupApi.recalculate(new Set<Id>{ 'GARCIA_ID' });` with the household's Id (in an org where BarnCRM is installed from a package, put the package prefix and a dot before `RollupApi`). | The run succeeds. Refreshing **The Garcia Family** shows **Test Children Count** 0. |

**Cleanup:** set Diego's **Household Role** back to **Child**, set the rollup back to **Both (recommended)**, and click **Recalculate** on it; the total returns to 1.

## T-RB-22: Change the Time of the Nightly Run

**Purpose:** confirm the nightly run's hour is a setting with a default, and saving a new hour moves the scheduled run.
**Prerequisites:** admin user; nightly run scheduled (T-RB-01).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Rollups** section. | **Time of the nightly run** shows **2:00 AM**, never blank. Its list offers every hour from **12:00 AM (midnight)** to **11:00 PM**. |
| 2 | Choose **11:00 PM** and save. | The setting saves and shows **11:00 PM**. |
| 3 | Open the **Rollup Builder** tab. | The text above the buttons reads "Nightly recalculation is scheduled for 11:00 PM." |
| 4 | In Setup, open **Scheduled Jobs**. | One job named **BarnCRM Rollups**, next run today or tomorrow at 11:00 PM. |
| 5 | On the **Rollup Builder** tab, click **Stop the nightly recalculation**, then **Recalculate All**, then **Run Tonight**. | The notice reads "One recalculation of every total is set for the next 11:00 PM." |
| 6 | Click **Schedule nightly recalculation**. | The text reads "Nightly recalculation is scheduled for 11:00 PM." |

**Cleanup:** set **Time of the nightly run** back to **2:00 AM** and check the Rollup Builder tab says 2:00 AM; in Setup, **Scheduled Jobs**, delete the one-off **BarnCRM Rollups** job with a date in its name.

## T-RB-24: Delete a Rollup You Made, and Not a Shipped One

**Purpose:** confirm Delete says what happens, removes an admin-made rollup and leaves its values, and refuses a shipped rollup with the reason.
**Prerequisites:** admin user; T-RB-02 done. Step 6 needs Giving deployed (it ships rollups); skip it otherwise.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, click **Copy** on **Test children per household**, click **Next** until **Check and save**, turn off **Active** and click **Save**. | A row **Copy of Test children per household** appears, switched off. |
| 2 | Click **Delete** on **Copy of Test children per household**. | A **Delete This Rollup** panel opens above the list: "Delete Copy of Test children per household? This cannot be undone.", with **What happens to the values it wrote** set to **Keep them on the records (nothing updates them again)**. |
| 3 | Click **Cancel**. | The row is still listed. |
| 4 | Click **Delete** on the same row again, leave **Keep them on the records** chosen, and click **Delete** in the panel. | The notice reads "Rollup deleted. The values it wrote stay on the records." The row is gone; **Test children per household** is still listed. |
| 5 | Open **The Garcia Family**. | **Test Children Count** still shows 1. |
| 6 | Back on the **Rollup Builder** tab, click **Delete** on **Account gift count**. | No confirmation opens. A red message reads "This rollup came with BarnCRM, so it cannot be deleted: Restore shipped rollups would bring it back. Switch it off instead." The row is still listed. |
| 7 | Log in as the staff user and open the **Rollup Builder** tab. | **Delete** is disabled on every row, as **Edit** and **Copy** are. |

**Cleanup:** None.

## T-RB-25: Export Rollups to a File and Import Them Again

**Purpose:** confirm Export writes only the rollups you made, keyed by Definition Key, and Import says what it will do, matches by key and reports each rollup.
**Prerequisites:** admin user; T-RB-02 done. Step 7 needs a second org with Core and BarnCRM Rollup Builder but without the **Test Children Count** field; skip it if you have none.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, tick **Include in the export** on **Test children per household** and click **Export to a File**. | The browser saves `barncrm-rollups.json`. Rows of rollups that came with BarnCRM have no tick box. |
| 2 | Open the file in a text editor. | It starts with `"format" : "BarnCRM rollups"` and `"version" : 1`, and holds one rollup with `"name" : "Test children per household"` and a `"definitionKey"` starting `Custom_`. It has no `recordId` and no last calculated date. |
| 3 | Back on the tab, under **Import from a file**, choose the file. | A table lists **Test children per household** with "Will replace the rollup here with the same Definition Key". Nothing is saved yet. |
| 4 | Click **Cancel**. | The table closes. |
| 5 | Choose the file again and click **Import These Rollups**. | The table reads **Updated** for the rollup, and the notice reads "Import finished: see each rollup below. Imported rollups are calculated in their next run, or click Recalculate." The list still has one **Test children per household**, still active. |
| 6 | Untick the box and click **Export to a File** again. | The file holds every rollup you made and none that came with BarnCRM. |
| 7 | In the second org, on the **Rollup Builder** tab, import the file from step 1 and click **Import These Rollups**. | The table reads "Not saved: BarnCRM cannot write to the field this rollup fills. Choose a field that exists and is not a formula or read only." Nothing is saved. |

**Cleanup:** None.

## T-RB-26: A File That Is Not an Export Is Refused, and Staff Cannot Export or Import

**Purpose:** confirm Import refuses a file it cannot read and that Export and Import are admin only.
**Prerequisites:** admin and staff users; T-RB-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Save a text file named `not-rollups.json` holding `{}`. On the **Rollup Builder** tab, choose it under **Import from a file**. | A red message reads "This is not a BarnCRM rollups file. Choose a file made by Export to a file." No table opens. |
| 2 | Log in as the staff user and open the **Rollup Builder** tab. | **Export to a File**, **Import from a file** and the tick boxes are disabled or not shown. |

**Cleanup:** delete `not-rollups.json`.

## T-RB-30: Turn on Instant Totals for an Object BarnCRM Does Not Own

**Purpose:** confirm the Builder generates a trigger and test for another object, that the steps deploy them, and that its state is read from the org.
**Prerequisites:** admin user with Manage BarnCRM Settings, in a sandbox, scratch or Developer Edition org (the steps create Apex there). In Setup, create a custom object **Shift** (`Shift__c`) with a lookup **Volunteer** to Contact and a number field **Hours**, and a number field **Test shift hours** on Contact.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, build a rollup on **Contact**, field **Test shift hours**, counting **Shift, by Volunteer**, **Sum** of **Hours**, mode **Both (recommended)**. Stay on **Check and save**. | The notice "Instant totals are not available yet for Shifts..." is shown and **Mode** offers **Every night** and **Both (recommended)** only. Under **Mode**: **Not set up: these totals update every night and when you click Recalculate.** with **Turn On Instant Totals**. |
| 2 | Save. Scroll to **Instant Totals** below the rollups. | **Shift** is listed: **Not set up**, **1 instant rollup counts this object.**, and **Turn On Instant Totals**. |
| 3 | Click **Turn On Instant Totals**. | **Turn On Instant Totals for Shift** opens with five steps, the **Trigger** (`trigger BarnRollup_Shift_c on Shift__c (...)` with one line, `RollupInstantTrigger.run();`), the **Test Class** (`BarnRollup_Shift_c_Test`), a CLI command naming `--tests BarnRollup_Shift_c_Test`, and **Download deploy package**. |
| 4 | Click **Download deploy package**. | `BarnRollup_Shift_c.zip` downloads, holding `package.xml`, `triggers/BarnRollup_Shift_c.trigger` and `classes/BarnRollup_Shift_c_Test.cls` with their `-meta.xml` files. |
| 5 | Follow steps 1 and 2 of the panel in this org's Developer Console (use **Copy** for each piece of code), and run the test. | The test passes. |
| 6 | Reload the **Rollup Builder** tab. | **Shift** shows **On: the trigger BarnRollup_Shift_c updates these totals at once.** with **Turn Off Instant Totals** and **Remove the Trigger**. |
| 7 | Open a contact, add a **Shift** with **Hours** 3, wait a few seconds and reload the contact. | **Test shift hours** is 3 without clicking **Recalculate**. |
| 8 | On the **Rollup Builder** tab, click **Edit** on the rollup and go to **Check and save**. | No "Instant totals are not available yet" notice. **Mode** offers **Instantly** too, and the Shift line reads **On**. Click **Cancel**. |

**Cleanup:** keep the rollup and trigger for T-RB-31.

## T-RB-31: Turn Instant Totals Off and Back on, and Remove the Trigger

**Purpose:** confirm instant totals turn off with no deploy, turn back on, and that removal gives the right package and steps.
**Prerequisites:** T-RB-30 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Instant Totals**, click **Turn Off Instant Totals** for **Shift**. | **Instant totals on Shift are turned off.** The line reads **Turned off: these totals update every night and when you click Recalculate.** |
| 2 | Add another **Shift** with **Hours** 2 to the same contact, wait a few seconds and reload. | **Test shift hours** is still 3. |
| 3 | In BarnCRM Settings, open the **Automation** page. | **Instant rollups on Shift** is listed and off. |
| 4 | Back on **Instant Totals**, click **Turn On Instant Totals**, then click **Recalculate** on the rollup. | **Instant totals on Shift are turned back on.**, and after the recalculation **Test shift hours** is 5. |
| 5 | Click **Remove the Trigger**. | **Remove the Trigger for Shift** opens with three steps, a CLI command with `--test-level RunLocalTests`, and **Download removal package** (`BarnRollup_Shift_c_Removal.zip`, holding `package.xml` and `destructiveChanges.xml`). |
| 6 | Sign in as a user with BarnCRM Staff and Rollup Builder User only and open the **Rollup Builder** tab. | **Shift** is listed with **Remove the Trigger** but no **Turn Off Instant Totals** button. |

**Cleanup:** delete `BarnRollup_Shift_c` and `BarnRollup_Shift_c_Test` in Setup (sandbox), then the rollup.

## T-RB-32: BarnCRM Names DLRS and Rollup Helper Where It Matters

**Purpose:** confirm BarnCRM says when another rollup tool is installed, says nothing when none is, and changes nothing in the other tool.
**Prerequisites:** admin user with Manage BarnCRM Settings; two sandboxes or Developer Edition orgs with BarnCRM Rollup Builder: one without DLRS or Rollup Helper, one with DLRS installed (free, from the AppExchange listing "Declarative Lookup Rollup Summaries Tool").

| Step | Action | Expected result |
|---|---|---|
| 1 | In the org without DLRS, open the **Rollup Builder** tab, the Setup Assistant step that says what BarnCRM found, and the **Modules** section of BarnCRM Settings. | None shows **Other Rollup Tools**. |
| 2 | In the org with DLRS, open the **Rollup Builder** tab. | **Other Rollup Tools** is at the top: "This org also runs DLRS (Declarative Lookup Rollup Summaries). It is a separate rollup tool; BarnCRM does not manage its rollups." |
| 3 | Open the Setup Assistant at the step that says what BarnCRM found in your org. | The same **Other Rollup Tools** line is under what BarnCRM found. |
| 4 | Open the **Modules** section of BarnCRM Settings. | The same line is at the top of the list (Rollup Builder is installed). |
| 5 | In DLRS (the **Lookup Rollup Summaries** tab), open any DLRS rollup. | It is exactly as before: BarnCRM changed nothing. |
| 6 | If you can, repeat step 2 in an org with Rollup Helper installed. | The line reads "This org also runs Rollup Helper. It is a separate rollup tool; BarnCRM does not manage its rollups." |

**Cleanup:** None.

## T-RB-33: Turning on a Rollup That DLRS Also Fills Asks First, and the Answer Is Recorded

**Purpose:** confirm the same-field guard in the Builder, in the list and in Import from a file, and that BarnCRM never changes DLRS.
**Prerequisites:** the org with DLRS from T-RB-32; admin user with Manage BarnCRM Settings. In Setup, create a number field **Test child count** on Account. In DLRS, create and activate a rollup **Test child count** on Account: child object Account, relationship field `ParentId`, Count, aggregate result field **Test child count**, calculation mode Realtime (deploy its trigger as DLRS asks).

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, click **New Rollup** and build a rollup on **Account**, field **Test child count**, counting **Account, by Parent Account**, **Count**, **Active** ticked. Click **Save**. | **Switch Off the DLRS Rollup** opens: "The DLRS rollup Test child count also fills Account.Test_child_count__c. Two tools filling one field overwrite each other..." |
| 2 | Click **Cancel**. | The dialog closes, you are still on **Check and save**, and nothing is saved (the list has no new rollup). |
| 3 | Click **Save** again, then **OK**. | The rollup is saved and switched on. |
| 4 | In BarnCRM Settings, open **Recent Changes**. | A row **Rollup Builder:** and the rollup's name, old value "DLRS rollup Test child count fills Account.Test_child_count__c", new value "Turned on; the admin confirmed the DLRS rollup will be switched off". |
| 5 | In DLRS, open **Test child count**. | It is still active: BarnCRM changed nothing. |
| 6 | Back in the list, switch **Active** off for the rollup, then on again. Click **Cancel** in the dialog. | Switching off asks nothing. Switching on opens **Switch Off the DLRS Rollup**; after **Cancel** the switch is back off. |
| 7 | Switch **Active** on again and click **OK**. | The rollup is on, and a second **Recent Changes** row is written. |
| 8 | Tick the rollup, click **Export to a File**, delete the rollup, and import the file under **Import from a file**. | The table reads **Not saved** with the DLRS sentence; nothing is saved. |

**Cleanup:** delete the BarnCRM rollup; keep the DLRS rollup and field for T-RB-34.

## T-RB-34: Health Check Names a Field BarnCRM and DLRS Both Fill

**Purpose:** confirm Health Check reports a field both tools fill and stops once one is switched off.
**Prerequisites:** T-RB-33 setup (DLRS rollup **Test child count** active).

| Step | Action | Expected result |
|---|---|---|
| 1 | Build the BarnCRM rollup of T-RB-33 step 1 again and click **OK** to turn it on. | Saved and on. |
| 2 | Open Health Check and run it. | A warning **BarnCRM and DLRS Fill the Same Field** names `Account.Test_child_count__c`, the BarnCRM rollup and **Test child count** (DLRS), with **Open the Rollup Builder**. |
| 3 | Click **Open the Rollup Builder**. | The **Rollup Builder** tab opens. |
| 4 | In DLRS, deactivate **Test child count**. Run Health Check again. | The warning is gone. |

**Cleanup:** delete the BarnCRM rollup, the DLRS rollup (and its trigger, as DLRS describes) and the **Test child count** field.

## T-RB-35: Import From DLRS Copies Switched Off, Compares, and Finishes Only When Every Copy Is On

**Purpose:** confirm the Import from DLRS wizard copies what BarnCRM can hold, says why for the rest, compares values, asks before turning each copy on, and never changes DLRS.
**Prerequisites:** the org with DLRS from T-RB-32; admin user with Manage BarnCRM Settings. In Setup, create a number field **Test child count** and a text field **Test child names** (255) on Account. In DLRS, create and activate three rollups on Account, child object Account, relationship field `ParentId`, calculation mode Realtime: **Test child count** (Count into **Test child count**); **Test child names** (Concatenate of Name into **Test child names**, delimiter `; `); **Test unreadable** (Count into **Test child count** with Relationship Criteria `CALENDAR_YEAR(CreatedDate) = 2024`, kept inactive until step 1, then active). Run DLRS's Calculate once so the fields hold DLRS's values. Create a parent account with two child accounts.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Rollup Builder** tab. | **Other Rollup Tools** has an **Import From DLRS** button. |
| 2 | Click **Import From DLRS**. | The list is hidden. **Choose** lists **Test child count** and **Test child names** under **Can Be Copied**, both ticked, each with "Fills Account.... DLRS operation: ...". **Test unreadable** is under **Stays in DLRS** with "BarnCRM cannot read this part of the Relationship Criteria: CALENDAR_YEAR ( CreatedDate ) = 2024...". |
| 3 | Untick both. Tick them again. Click **Next**. | **Next** is unavailable with nothing ticked. **Review** says "Becomes a BarnCRM Count, filling Account.Test_child_count__c, switched off." and "Becomes a BarnCRM Text list, filling Account.Test_child_names__c, switched off." |
| 4 | Click **Copy Switched Off**. | **Compare** shows **Copied, switched off.** for both. In another tab, the rollup list shows both copies switched off, each described "Imported from the DLRS rollup ...". |
| 5 | Click **Compare** on **Test child count**. | Up to five accounts: the parent shows 2 under **Value Now (DLRS)** and **BarnCRM Value**, **Result** **Same**. Nothing on the accounts changes. |
| 6 | Click **Next**. | **Turn On** lists both copies with **Turn On** buttons; **Finish** is unavailable. |
| 7 | Click **Turn On** on **Test child count**, then **Cancel**. | **Switch Off the DLRS Rollup** opened naming the DLRS rollup and the field; after **Cancel** the copy is still off and **Finish** is still unavailable. |
| 8 | Click **Turn On** on each copy and **OK** each time. | Each reads **Turned on.** **Finish** becomes available. **Recent Changes** has one row per copy. |
| 9 | Click **Finish**. | The list is back with the notice "Import from DLRS finished: 2 copies turned on. Switch their DLRS rollups off in DLRS." |
| 10 | In DLRS, open the three rollups. | Each is exactly as before: BarnCRM changed nothing. |
| 11 | Click **Import From DLRS** again. | Both copies are under **Stays in DLRS** with "Already copied and turned on in BarnCRM." |

**Cleanup:** delete both BarnCRM copies; deactivate and delete the three DLRS rollups (and their triggers, as DLRS describes); delete the two fields and the test accounts.

## T-RB-40: Read, Search and Group the Rollup List

**Purpose:** confirm each rollup reads as a sentence and the list groups and searches.
**Prerequisites:** T-RB-02 done (**Test children per household** exists and is active).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Rollup Builder** tab. | The list has a heading row per object, such as **Account (1)**, in alphabetical order. **Test children per household** is under **Account**, and its **What It Counts** column reads "Number of Contacts by Account, shown in Test Children Count on each Account. Only records that meet its conditions count.", with `Count on Contact: Account.Test_Children_Count__c` in small grey text below. |
| 2 | In **Search rollups**, type `children`. | Only **Test children per household** is listed. |
| 3 | Type `Test_Children_Count__c`. | The same rollup is listed. Type `zzz`: "No rollup matches your search." Clear the box: every rollup is back. |

**Cleanup:** none.

## T-RB-41: Recalculation Status and Conflicts in the Rollup List

**Purpose:** confirm each row says how its recalculation stands, and that conflicts between rollups are shown and the Active switch refuses one.
**Prerequisites:** T-RB-02 done (**Test children per household** exists and is active).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Rollup Builder** tab and look at the **Status** column of **Test children per household**. | **Nothing waiting** (or "N records waiting" for a moment after a save). |
| 2 | Click **Copy** on **Test children per household**, change only the name to `Test children copy`, switch **Active** off and save. | The copy shows **Switched off** in **Status** and, in red under its name, "Cannot be switched on while Test children per household fills the same field for the same records." |
| 3 | Switch the copy's **Active** toggle on. | It is refused with that reason, and the toggle goes back off. |
| 4 | In Setup, on **Account**, create a Number field **Test Children Count 2** (`Test_Children_Count_2__c`). Edit the copy, choose **Test Children Count 2** in step 1, switch **Active** on and save. | Both rollups show, in red, "Calculates the same total as ..., into another field." |
| 5 | Sign in as a user with BarnCRM Staff and Rollup Builder User only and open the tab. | The **Status** column is empty. |

**Cleanup:** delete **Test children copy** and the field **Test Children Count 2**.

## T-RB-42: The Builder Sentence, Type Guidance and What Each Mode Means

**Purpose:** confirm the sentence above the steps fills in and opens steps, the Builder only offers what it can save and says why, and step 5 explains each mode by its consequence.
**Prerequisites:** T-RB-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **New Rollup**. | Above the steps, a sentence starting "Show (not chosen yet) from (not chosen yet)". Only the part for step 1 can be clicked. |
| 2 | Choose **Account** and **Test Children Count**, click **Next**, choose **Contact, by Account ID** and click **Next**. | The sentence now names **Contact, by Account ID** and **Account: Test Children Count**. Under **Calculation**: "Not available for Test Children Count: Any, None, Text list, Text list, each value once. To use one of them, choose another field in step 1." |
| 3 | Choose **Sum**. | **Field to calculate** lists only number, currency and percent fields of Contact, and the line under it reads "Only number, currency and percent fields are listed, because Sum works on numbers." |
| 4 | Choose **Count**, click **Next** twice. On step 5 read **What Each Choice Means**. | Three lines: "Instantly, after the save: Test Children Count changes within about a minute after one of the Contacts is saved.", "Every night: Test Children Count is recalculated at 2:00 AM each night, so a change made today shows tomorrow." (or the time you set), and "Both (recommended): instantly, and the nightly run at 2:00 AM puts right anything a save missed." |
| 5 | Click the **Contact, by Account ID** part of the sentence. | Step 2 opens. Click **Cancel**. |
| 6 | Click **Edit** on **Test children per household**. | Every part of the sentence can be clicked; the conditions part reads "only those that meet its conditions (1)". Click **Cancel**. |

**Cleanup:** none.

## T-RB-43: Preview with Sample Records and the Records Read

**Purpose:** confirm step 5 picks sample records, calculates each without saving, and lists the records read for one record as counted or left out with the reason.
**Prerequisites:** T-RB-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **Edit** on **Test children per household** and click **Next** until step 5. | **Pick Sample Records** shows, with "Calculates this rollup on up to five records it would fill, chosen for you. Nothing is saved." under it. No **Records Read for This Record** yet. |
| 2 | In **See it on a record**, pick **The Garcia Family**. | The total line shows 1 next to what the record holds. **Records Read for This Record** reads "Showing 3 of the 3 records read for this record." and lists Harper, Luis and Diego, each linked: Diego **Counted**, Harper and Luis "Left out: does not meet condition 1". |
| 3 | Click a name in the list. | The contact opens in a new tab. |
| 4 | Click **Pick Sample Records**. | **Sample Records** lists up to five households, each with its calculated total next to what it holds now. |
| 5 | Click **Show Records Read** on one sample. | **See it on a record** shows that household, and **Records Read for This Record** lists its people. The samples stay listed. |
| 6 | Click **Cancel**, then open the Rollup Builder tab again. | **Test children per household** is unchanged: no field on any household changed. |

**Cleanup:** none.

## T-RB-44: Delete a Rollup and Clear Its Values

**Purpose:** confirm Delete can clear the values a rollup wrote, only on the records it fills, and refuses to clear a field another active rollup fills.
**Prerequisites:** T-RB-02 done; **Test Children Count** on **The Garcia Family** shows 1.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Rollup Builder** tab, click **Copy** on **Test children per household**, click **Next** until **Check and save**, turn off **Active** and click **Save**. | **Copy of Test children per household** is listed, switched off. |
| 2 | Click **Delete** on the copy, choose **Clear them from every record it fills, in the background** and click **Delete** in the panel. | A red message: "Test children per household also fills this field for the same records, so its values cannot be cleared. Keep the values, or switch Test children per household off first." The copy is still listed. |
| 3 | Click **Delete** on the copy again, leave **Keep them on the records** chosen and click **Delete**. | "Rollup deleted. The values it wrote stay on the records." |
| 4 | Switch **Test children per household** off. Click **Delete** on it, choose **Clear them from every record it fills, in the background** and click **Delete**. | "Rollup deleted. Its values are being cleared from the records in the background." |
| 5 | After a minute, open **The Garcia Family**. | **Test Children Count** is blank. |
| 6 | In the Error Log, find the entry from **RollupClearBatch**. | "Values of the deleted rollup Test children per household cleared on N records; 0 records could not be saved." |

**Cleanup:** rebuild **Test children per household** with T-RB-02 if later scripts need it.

## T-RB-45: Create a Field From the Builder

**Purpose:** confirm step 1 writes a field to create (Setup steps, source and package), creates nothing itself, and chooses the field once it exists.
**Prerequisites:** admin user. A sandbox if you deploy with the CLI (step 6).

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **New Rollup**, choose **Account**, then click **Create a Field**. | A **Create a Field** panel opens, saying BarnCRM cannot add a field itself because that takes a Metadata API deploy. **Field type** shows **Number**; **Write the Field** is disabled. |
| 2 | Type `Test Gift Count` in **Field label** and click **Write the Field**. | Four numbered steps: open Object Manager, then Account, then Fields & Relationships, and click New; choose Number, enter the label Test Gift Count and the field name Test_Gift_Count; make it visible and save; come back and click Refresh Fields. Below, `objects/Account/fields/Test_Gift_Count__c.field-meta.xml` and its XML, **Copy**, **Download Field Package**, and the CLI command. |
| 3 | Click **Copy**. | "Copied." The clipboard holds the XML. |
| 4 | Click **Download Field Package**. | `BarnRollupField_Account_Test_Gift_Count__c.zip` downloads, holding `package.xml` and `objects/Account.object`. |
| 5 | Click **Refresh Fields** without creating the field. | The panel stays open; **Field that shows the total** does not list Test Gift Count. No field was created in the org. |
| 6 | Create the field by following the four steps in Setup (or, in a sandbox, deploy the zip with the command shown and give your profile access to the field). Back in the Builder, click **Refresh Fields**. | **Field that shows the total** now shows **Test Gift Count** and the panel closes. |
| 7 | Type `Member Count` in **Field label** after opening **Create a Field** again, and click **Write the Field**. | A red message: "This object already has a field named Member_Count__c. Choose it in the list, or give the new field another label." |

**Cleanup:** click **Cancel**; delete **Test Gift Count** in Setup if you created it.

## T-RB-46: Explain These Totals on a Record Page

**Purpose:** confirm the record-page component explains each total, counts what was read, links the records, and shows the recalculation to admins only.
**Prerequisites:** T-RB-02 done; **Test children per household** active; a staff user with **Rollup Builder User**.

| Step | Action | Expected result |
|---|---|---|
| 1 | With Giving deployed, open **The Garcia Family** as admin. (Without Giving: click the gear, **Edit Page**, drag **Explain These Totals** onto the page and save.) | The **Explain These Totals** card shows in the sidebar. |
| 2 | Read the entry for **Test Children Count**. | "Test Children Count: 1", the sentence "Number of Contacts ... shown in Test Children Count on each Account." (with its condition note), "1 of the 3 records read count; 2 are left out.", and "Last calculated ..." or "Not calculated yet." |
| 3 | Read **Records Read for This Record**. | Harper, Luis and Diego linked: Diego **Counted**, Harper and Luis "Left out: does not meet condition 1". |
| 4 | Read the admin line. | "For admins, recalculated now without saving: Calculated: 1. On the record now: 1." |
| 5 | Change Luis's **Household Role** to **Child** and save, then click **Refresh** on the card. | The counts read 2 of 3 (after the instant update), and Luis is **Counted**. Change him back. |
| 6 | Log in as the staff user and open **The Garcia Family**. | No card: it shows only to people with Manage BarnCRM Settings until you change its visibility. As admin, edit the page, remove the card's visibility filter and save; as the staff user, reload. | 
| 6a | Read the card as the staff user. | The same entry without the admin line. |
| 7 | Open an account no rollup fills (or switch the test rollup off and click **Refresh**). | "No BarnCRM rollup you can see fills a field on this record." |

**Cleanup:** switch the test rollup back on if you switched it off; put the card's visibility filter back (Manage BarnCRM Settings is true), or remove the component if you added it only for this script.

## T-RB-47: Starter Templates Add Only What You Tick, Switched Off

**Purpose:** confirm Starter Templates adds nothing by default, adds only ticked rollups and adds them switched off, and opens a rollup prefilled with Create a Field ready.
**Prerequisites:** admin user; Giving deployed; a staff user without Manage BarnCRM Settings.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Rollup Builder** tab and note how many rollups are listed. | **Starter Templates** shows above the list. |
| 2 | Click **Starter Templates**. | The **Nonprofit Starter** with seven rollups, none ticked, each with its sentence. Each says "Needs a field labelled ... on Contact" (or "on Appeal"), so its tick box is disabled. **Add the Chosen Rollups** is disabled. The rollup list has not changed. |
| 3 | Next to **Average Gift**, click **Open in Builder**. | The Builder opens on step 1 named **Average Gift**, showing on **Contact**, with **Create a Field** open: label **Average Gift**, type **Currency**. |
| 4 | Click **Write the Field**, create the field from the steps in Setup, then click **Refresh Fields**. Click **Cancel**. | **Field that shows the total** shows **Average Gift**. Cancel saves nothing. |
| 5 | Click **Starter Templates** (twice if the panel is still open, to close and reopen it). | **Average Gift** says "Ready to add, switched off." and can be ticked; the others still need their fields. |
| 6 | Tick **Average Gift** and click **Add the Chosen Rollups**. | "Average Gift: Added, switched off." The rollup list shows **Average Gift**, switched off, mode Both. |
| 7 | Close **Starter Templates** and open it again. | **Average Gift** says "Already filled by Average Gift." and cannot be ticked. |
| 8 | Log in as the staff user and open the **Rollup Builder** tab. | No **Starter Templates** button. |

**Cleanup:** delete the **Average Gift** rollup (keep values) and the **Average Gift** field in Setup.

## T-RB-48: A Rollup Saved Outside the Builder Passes the Same Checks

**Purpose:** confirm a rollup cannot be created or retargeted outside the Builder without Manage BarnCRM Settings, and never fills a field on users or setup records.
**Prerequisites:** admin user; T-RB-02 done; a test user holding **Rollup Builder Admin** but not **Manage BarnCRM Settings** (no BarnCRM Admin set).

| Step | Action | Expected result |
|---|---|---|
| 1 | As the admin, open the **Rollup Builder** tab, click **New Rollup** and search step 1's object list for **User** and **Permission Set**. | Neither is offered. |
| 2 | Log in as the test user. Open **Test children per household** by its record URL (`/lightning/r/Rollup_Definition__c/<Id>/view`), click **Edit**, change **Target Field** to `AnnualRevenue` and save. | Refused: "You do not have permission to change rollups." The field is unchanged. |
| 3 | As the test user, in the Developer Console run `insert new Rollup_Definition__c(Name='Test guard', Definition_Key__c='Test_Guard', Source_Object__c='Contact', Relationship_Path__c='AccountId', Aggregate__c='COUNT', Target_Object__c='Account', Target_Field__c='NumberOfEmployees', Mode__c='Both');` | Fails with the same message. Nothing is saved. |
| 4 | As the admin, run the same statement with `Target_Object__c='User'`, `Target_Field__c='Title'`, `Relationship_Path__c='OwnerId'`, `Aggregate__c='LAST'`, `Source_Field__c='Title'`, `Order_By_Field__c='CreatedDate'`. | Fails: "A rollup cannot fill fields on this kind of record. Choose another object for the total." |
| 5 | As the admin, click **Recalculate All** on the **Rollup Builder** tab. | The run finishes as before; shipped rollups and their last calculated times are unaffected. |

**Cleanup:** None.
