# Duplicates

Scripts for the duplicate scan, the review list, merges, dismissals, match sources and the permissions behind them. Setup detail: [Duplicates](../admin-guide/duplicates.md); match sources: [Matching Logic](../admin-guide/duplicates.md#matching-logic).

Before you start: an org from [Before you test](before-you-test.md) on the Person Accounts shape (duplicate review needs a Sales Cloud or Service Cloud license), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest. A scan reads every contact and household in the org and writes duplicate suggestion records for pairs among real people (it does not change the people); never merge or dismiss a pair that is not a fixture pair. In **BarnCRM Settings**, **General**, the **Duplicate Matching**, **Addresses** and **Org Optimizer and Health Check** features are **On** (Addresses before the sample data loads, so each household has its address record). In Setup, **Duplicate Rules**, the **Standard Contact Duplicate Rule** and **Standard Account Duplicate Rule** are active.

## T-DUP-01: The Duplicates Section and a Scan

**Purpose:** Confirm the section lists the rules and a scan runs in the background and reports what it did.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)), holding **BarnCRM Duplicate Review** (the create script gives it; in a real-org sandbox give it on the **Access** page) and **Manage BarnCRM Settings** (the BarnCRM Admin role has it). Both are needed: the **Scan for Duplicates** button works only with Manage BarnCRM Settings, and the suggestion list needs Duplicate Review. A holder of Duplicate Review without Manage BarnCRM Settings can read the section but not scan. At least the **Standard Contact Duplicate Rule** must be active in Setup, **Duplicate Rules**; a real org may have its own rules instead, so read the rule list in step 1 as it is.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Duplicate Matching** tab. | The page header shows the merge icon and **Review possible duplicate people and households, and choose what pairs them.**, with no second **Duplicate Matching** title under the page name. The **Review** tab opens. Under **Duplicate Rules** each rule for people and accounts is listed with **On** or **Off**; at least two read **On**. A link **Open Duplicate Rules in Setup** is under them. |
| 2 | Read the buttons and counts. | **Scan for Duplicates** and **Refresh** are enabled. **Dismissed pairs** shows a number. |
| 3 | Click **Scan for Duplicates**. | **Scan started. It runs in the background, and suggestions appear here as they are found.** **Scan for Duplicates** is disabled and **A scan is running. Refresh the page in a minute to see what it found.** shows. |
| 4 | Wait a minute and click **Refresh**. | **Last scan finished** with a date and time, and a line **Duplicate scan of ... finished: N new possible duplicates recorded.** in normal (not red) text. **Scan for Duplicates** is enabled again. |
| 5 | Check the bell. | One notification titled **Duplicate scan finished**. |

**Cleanup:** None.

## T-DUP-02: A Duplicate Person Is Found and Merged

**Purpose:** Confirm a person pair is listed with its reason, and Salesforce's merge keeps the person in the household.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact: First Name `Harper`, Last Name `Garcia`, Email `harper.garcia1@example.org`. | Salesforce warns that a similar record exists. Save anyway. |
| 2 | On **Duplicate Matching**, **Review**, click **Scan for Duplicates**, wait, click **Refresh**. | Under **Possible Duplicates** a pair of two **Harper Garcia** records, each with **Person:** and its detail. A grey line under them names the duplicate rule that found the pair. |
| 3 | Read the pair's buttons, and the line above the list. | The pair has a **Not a Duplicate** button on the right and no **Merge Households** button. The line **To merge two people, open either one and use Compare and merge on the Potential Duplicates card.** is shown once, above the list, not on the pair. |
| 4 | Click the new **Harper Garcia**'s name. On the **Potential Duplicates** card choose **View Duplicates**, then **Compare and merge**, keep the sample record as the master, and confirm. | Salesforce merges the two. |
| 5 | Open the kept **Harper Garcia** and the **The Garcia Family** household. | Harper is still a member of **The Garcia Family**. The household made for the new contact still exists, now empty. |
| 6 | Back on **Duplicates**, click **Refresh**. | The pair is gone. |

**Cleanup:** Delete the empty household left by the merge (or keep it for T-HC-05).

## T-DUP-03: Not a Duplicate, and Taking the Dismissal Back

**Purpose:** Confirm a dismissed pair is not suggested again until its dismissal is deleted.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact `Luis Garcia` with Email `luis.garcia2@example.org`, save past the warning, scan, and refresh. | A **Luis Garcia** pair is listed. Note the **Dismissed pairs** count. |
| 2 | Click **Not a Duplicate** on the pair. | A box **Not a Duplicate** opens: **The records stay as they are and this pair is not suggested again. Say why, for the next person who wonders.**, with **Reason**, **Not a Duplicate** and **Cancel**. |
| 3 | Click **Cancel**. | The box closes; the pair is still listed. |
| 4 | Click **Not a Duplicate** again, type `Test: father and son`, and click **Not a Duplicate** in the box. | **Noted. This pair will not be suggested again.** The pair is gone and **Dismissed pairs** is one higher. |
| 5 | Scan again and refresh. | The pair does not come back. |
| 6 | Click **View** next to **Dismissed pairs**. Open **All Duplicate Dismissals**, find `Test: father and son`, and delete it. | The dismissal is deleted. |
| 7 | Scan again and refresh. | The **Luis Garcia** pair is listed again. |

**Cleanup:** Delete the contact you created and its household.

## T-DUP-04: Merge Two Households From a Pair

**Purpose:** Confirm the household merge from the list keeps the chosen household and moves the members.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Home**, click **New Household**, then edit it: the same **Account Name** as **The Garcia Family** and Billing Street `6830 Sunset Ln`, City `Springfield`, Zip `62756`. Save past the warning. | The household saves. |
| 2 | Scan and refresh **Duplicates**. | A pair of two households side by side, each marked **Household** with its billing street, city, postal code and phone; a value that differs between the two has a **Different** badge (the streets match, so they have none). **Merge Households** (blue) and **Not a Duplicate** are at the top of the card. |
| 3 | Click **Merge Households**. | A box **Merge Two Households**: **Members, related records, files and activities of the other household move to the one you keep, totals are recalculated, and the other household is deleted. This cannot be undone.**, a **Household to keep** list, the fields where they differ, and **To choose field by field, use Merge or split on the household record instead.** |
| 4 | In **Household to keep**, choose the sample household (the one with members). | The list of differing fields marks which values are kept and which dropped. |
| 5 | Click **Merge These Two**. | **The two households are now one.** The pair is gone. |
| 6 | Open **The Garcia Family**. | Harper, Luis and Diego are still members; the household you created no longer exists. |

**Cleanup:** None.

## T-DUP-05: A Match Source Finds a Pair the Rules Cannot

**Purpose:** Confirm the scan pairs households that share an address held on BarnCRM addresses, and says why.
**Prerequisites:** admin. **Address (household)** is **Active** on the **Duplicate Matching** tab, **Matching Logic**.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Home**, click **New Household** and rename it `Sunset Test Household` (a name no rule would match). | The household saves. |
| 2 | Open the **Addresses** tab and create an address: **Household or Organization** `Sunset Test Household`, **Street** `6830 SUNSET LN.`, **City** `Springfield`, **Postal Code** `62756`, **Primary** ticked. | The address saves. |
| 3 | On **Duplicate Matching**, **Matching Logic**, choose **Try a Value** on **Address (household)**. Enter **Value** `6830 Sunset Ln`, **Postal code** `62756`, and choose **Try**. | **Compared as: 6830 sunset ln\|62756**, then **These records would match:** with **Household: The Garcia Family** and **Household: Sunset Test Household**. |
| 4 | On **Review**, scan and refresh. | A pair of `Sunset Test Household` and **The Garcia Family**, both **Household:**, with the grey line **Same address on Address (household)**. Capitals and the full stop did not stop the match. |
| 5 | Click **Not a Duplicate**, give the reason `Test: match source`, confirm. | **Noted. This pair will not be suggested again.** |
| 6 | Scan again and refresh. | The pair does not come back. |

**Cleanup:** Delete `Sunset Test Household` and its address. Delete the `Test: match source` dismissal (see T-DUP-03, step 6).

## T-DUP-06: A Deactivated Match Source Finds Nothing

**Purpose:** Confirm Matching Logic lists the shipped sources in words, deactivating one stops its pairs, and activating brings them back.
**Prerequisites:** admin, holding **BarnCRM Metadata Admin** (the create script gives it).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Duplicate Matching** tab and choose **Matching Logic**. | Under one intro line with a help icon, six cards, each with a **Shipped with BarnCRM** badge and its **Active** switch on: **Contact Point Email**, **Contact Point Phone**, **Contact Point Address**, **Address (person)**, **Address (household)**, **Address (person account)**. Each has one line such as **Email Address on Contact Point Email, compared as Email**. In an org without contact point objects, those three say **Not used in this org**. Shipped cards have **Show Details** and **Try a Value**, and no **Edit**. |
| 2 | Choose **Show Details** on the **Address (household)** card. | **Object** Address, **Field compared** Street, **Postal code field** Postal Code, **Belongs to** a household or a person account, **Through the lookup** the household lookup, **How values are compared** starting **Address:**. The button now reads **Hide Details**. |
| 3 | Turn off the **Active** switch on **Address (household)**. | The switch stays on while **Saving. Salesforce applies the change in the background, usually within a minute.** shows, then **Saved.** and the switch reads **Inactive**. |
| 4 | Create a household `Pine Test Household` with a primary address **Street** `5616 Pine Dr`, **Postal Code** `78728` (the **Staff Household**'s address). | Both save. |
| 5 | On **Review**, scan and refresh. | No pair with `Pine Test Household`. |
| 6 | Back on **Matching Logic**, turn on the **Active** switch on **Address (household)**. | **Saved.** The switch reads **Active**. |
| 7 | Scan and refresh. | A pair of `Pine Test Household` and **Staff Household**, reason **Same address on Address (household)**. |

**Cleanup:** Delete `Pine Test Household` and its address; the pair goes with it.

## T-DUP-07: Adding a Match Source, and a Bad One Refused

**Purpose:** Confirm Matching Logic offers only fields that can work, checks a new source against the org before saving, and saves a good one.
**Prerequisites:** admin with **BarnCRM Metadata Admin**. In an org where BarnCRM is installed as a package, **Deploy Metadata from Non-Certified Package Versions via Apex** is on in Setup, **Apex Settings**.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Matching Logic**, click **Add**. | A window **New Match Source** over the page, with focus inside it: **Name**, **Object**, **Find Fields**, **Field compared**, **Through the lookup**, **How values are compared**, and **Cancel** and **Save** at the bottom. Press Escape: the window closes and nothing is saved. |
| 2 | Click **Add** again. Enter **Object** `Not_An_Object__c` and choose **Find Fields**. | In the window: **Not_An_Object__c is not an object in this org. Check its API name.** |
| 3 | Change **Object** to `Contact` and choose **Find Fields**. | **Field compared** offers text, email and phone fields such as **Email** and **Assistant Phone**, and no date or number field. **Through the lookup** offers lookups such as **Account ID** and **Reports To ID**, and not **Last Name**. |
| 4 | Choose **How values are compared** **Address**. | A **Postal code field** list appears. |
| 5 | Choose **Field compared** **Mailing Street**, **Through the lookup** **Account ID**, leave **Postal code field** empty, and **Save**. | Refused: **An address source needs a postal code field: the street is compared together with it.** in the window, which stays open. |
| 6 | Enter **Name** `Test: assistant phone`, choose **How values are compared** **Phone**, **Field compared** **Assistant Phone**, **Through the lookup** **Reports To ID**, and **Save**. | The window closes. **Saving.**, then **Saved. Test: assistant phone is in the list.** Its card has **Edit**, the **Active** switch and **Try a Value**, no **Shipped with BarnCRM** badge, and **Show Details** says **Belongs to** a person. |
| 7 | Choose **Edit** on it. In the window, change **Name** to `Test: assistant phone 2`, and **Save**. | The window opens with the source's values and its object's fields filled in. **Saved.** The card has the new name. |

**Cleanup:** Turn off the **Active** switch on `Test: assistant phone 2` (Salesforce does not let an app delete custom metadata; delete it in Setup, **Custom Metadata Types**, **Match Source**, **Manage Records**, if you want it gone).

## T-DUP-08: Without BarnCRM Duplicate Review

**Purpose:** Confirm an admin without the permission set sees why, and cannot scan, merge or dismiss.
**Prerequisites:** admin; a second admin session or the CLI to restore the set.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Access**, **Extra Permissions**, remove **BarnCRM Duplicate Review** from yourself and confirm. | A message says you no longer have it. |
| 2 | Reload **Duplicate Matching**, **Review**. | Under **Possible Duplicates**: **Suggestions need access to duplicate record sets, which Salesforce gives only to Sales Cloud and Service Cloud licenses. ...** No pairs are listed. |
| 3 | Look at **Scan for Duplicates**. | Disabled. |

**Cleanup:** Give yourself **BarnCRM Duplicate Review** again on the **Access** page.

## T-DUP-09: Who Sees the Duplicate Matching Tab

**Purpose:** Confirm the tab is for administrators and BarnCRM Duplicate Review holders, a holder who is not an admin can read the review list but not act, Org Optimizer no longer lists duplicates, and BarnCRM Settings links to the tab.
**Prerequisites:** admin; staff given **BarnCRM Find and Export** on the **Access** page; T-DUP-01 done (at least one pair waiting).

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Org Optimizer**. | Only **Overview** and **Data Quality**. No **Duplicates**. There is no **Duplicate Matching** tab. |
| 2 | As admin, in **BarnCRM Settings**, **Access**, **Extra Permissions**, remove **BarnCRM Find and Export** from the staff user and give them **BarnCRM Duplicate Review**. | A message says the staff user now has it. |
| 3 | As staff, wait a minute, reload, and open the **Duplicate Matching** tab (from the app launcher if it is not in the navigation bar). | Only the **Review** area. |
| 4 | Read the **Review** area. | The waiting pairs are listed, with **You can see this list. Scanning, dismissing and merging here need the Manage BarnCRM Settings permission.** **Scan for Duplicates** and the pair actions are disabled. |
| 5 | As admin, open **BarnCRM Settings**. Under **People and Households**, look for a duplicates row; then choose the **Duplicate Matching** section. | **People and Households** has no duplicates row and no duplicates note. **Duplicate Matching** shows the note about duplicate rules and Duplicate Review, and the **Duplicate Matching** row with **Open This Page**. |
| 6 | Click **Open This Page**. | The **Duplicate Matching** tab opens on **Review**. |

**Cleanup:** Remove **BarnCRM Duplicate Review** from the staff user.

## T-DUP-10: Matching Logic Without BarnCRM Metadata Admin

**Purpose:** Confirm an administrator without Metadata Admin can read the match sources and try a value, but not change them.
**Prerequisites:** admin; a second admin session or the CLI to restore the set.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Access**, **Extra Permissions**, remove **BarnCRM Metadata Admin** from yourself and confirm. | A message says you no longer have it. |
| 2 | Reload **Duplicate Matching** and choose **Matching Logic**. | **You can see the match sources. Adding or changing one needs the BarnCRM Metadata Admin permission set.** No **Add**, no **Edit** and no **Active** switch; each card shows an **Active** or **Inactive** badge instead. |
| 3 | Choose **Try a Value** on **Contact Point Email** (or **Address (person)** where there are no contact point objects), enter `Someone@Example.org` (for the address source, `1 Main St` and postal code `12345`), and choose **Try**. | A **Compared as:** line with the value as compared, then the matching records or a line saying nobody holds it. Nothing is saved. |

**Cleanup:** Give yourself **BarnCRM Metadata Admin** again on the **Access** page.

## T-DUP-11: A Long Review List

**Purpose:** Confirm a long list shows a count and 10 pairs at a time, with one shared note, and an empty list shows the empty state.
**Prerequisites:** admin; T-DUP-01 done with more than 10 pairs waiting (sample data on oi-test gives about 40). For step 5, an org with no pairs waiting (a fresh org before any scan).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Duplicate Matching**, **Review**. | The tab reads **Review (40)** (or **Review (50+)**), and **Possible Duplicates** has a badge with the same number. 10 pair cards, each with the reason and buttons at the top and the two records side by side under them. Under the cards **Showing 10 of 40 suggestions, newest first.** and **Show More**. |
| 2 | Count the line **To merge two people, open either one and use Compare and merge on the Potential Duplicates card.** | Once, above the list (only when a shown pair is two people). |
| 3 | With the keyboard, tab to **Show More** and press Enter. | 10 more pairs; focus is on the first new pair's first name; the line says **Showing 20 of 40**. Repeat until all show: **Show More** and the line go away (unless the badge reads **50+**). |
| 4 | Click **Not a Duplicate** on the third pair, then **Cancel**. | The **Not a Duplicate** box opens inside the third pair's card, with focus on its heading; **Cancel** closes it. |
| 5 | In the org with no pairs, open **Review**. | The tab reads **Review**, with no number, and there is no badge. An illustration with **No Possible Duplicates** and **No possible duplicates are waiting. Scan again after a large import.** |

## T-DUP-12: Comparing a Pair Side by Side

**Purpose:** Confirm a pair shows its two records side by side with differing values marked, and stacks on a phone.
**Prerequisites:** admin; T-DUP-01 done with at least one pair of two people waiting.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Review**, find a pair of two people with different emails (on oi-test the sample data gives several). | Two columns, each starting with the person's name as a link and **Person**, then **Email**, **Phone**, **Mailing Street**, **Mailing City**, **Mailing Zip/Postal Code** and **Household**. An empty value reads **Blank**. |
| 2 | Compare the two **Email** values. | Each differing value has a **Different** badge on both sides; values that match have none. A screen reader reads the badge with the value. |
| 3 | Click the first name. | The person opens (as a subtab in the console app). |
| 4 | Narrow the window to phone width (or open the page on a phone). | The two records stack, one above the other; nothing scrolls sideways. |

**Cleanup:** None.
