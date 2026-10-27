# Duplicates

Scripts for the duplicate scan, the review list, merges, dismissals, match sources and the permissions behind them. Setup detail: [Duplicates](../admin-guide/duplicates.md); match sources: [Matching Logic](../admin-guide/duplicates.md#matching-logic).

Before you start: an org from [Before you test](before-you-test.md) on the Person Accounts shape (duplicate review needs a Sales Cloud or Service Cloud license), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest. A scan reads every contact and household in the org and writes duplicate suggestion records for pairs among real people (it does not change the people); never merge or dismiss a pair that is not a fixture pair. In **BarnCRM Settings**, **General**, the **Duplicate Matching**, **Addresses** and **Org Optimizer and Health Check** features are **On** (Addresses before the sample data loads, so each household has its address record). In Setup, **Duplicate Rules**, the **Standard Contact Duplicate Rule** and **Standard Account Duplicate Rule** are active.

## T-DUP-01: The Duplicates section and a scan

**Purpose:** Confirm the section lists the rules and a scan runs in the background and reports what it did.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)), holding **BarnCRM Duplicate Review** (the create script gives it; in a real-org sandbox give it on the **Access** page) and **Manage BarnCRM Settings** (the BarnCRM Admin role has it). Both are needed: the **Scan for duplicates** button works only with Manage BarnCRM Settings, and the suggestion list needs Duplicate Review. A holder of Duplicate Review without Manage BarnCRM Settings can read the section but not scan. At least the **Standard Contact Duplicate Rule** must be active in Setup, **Duplicate Rules**; a real org may have its own rules instead, so read the rule list in step 1 as it is.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Duplicate Matching** tab. | The **Review** area opens on the **Duplicates** panel. Under **Duplicate rules** each rule for people and accounts is listed with **On** or **Off**; at least two read **On**. A link **Open Duplicate Rules in Setup** is under them. |
| 2 | Read the buttons and counts. | **Scan for duplicates** and **Refresh** are enabled. **Dismissed pairs** shows a number. |
| 3 | Click **Scan for duplicates**. | **Scan started. It runs in the background, and suggestions appear here as they are found.** **Scan for duplicates** is disabled and **A scan is running. Refresh the page in a minute to see what it found.** shows. |
| 4 | Wait a minute and click **Refresh**. | **Last scan finished** with a date and time, and a line **Duplicate scan of ... finished: N new possible duplicates recorded.** in normal (not red) text. **Scan for duplicates** is enabled again. |
| 5 | Check the bell. | One notification titled **Duplicate scan finished**. |

**Cleanup:** None.

## T-DUP-02: A duplicate person is found and merged

**Purpose:** Confirm a person pair is listed with its reason, and Salesforce's merge keeps the person in the household.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact: First Name `Harper`, Last Name `Garcia`, Email `harper.garcia1@example.org`. | Salesforce warns that a similar record exists. Save anyway. |
| 2 | On **Duplicate Matching**, **Review**, click **Scan for duplicates**, wait, click **Refresh**. | Under **Possible duplicates** a pair of two **Harper Garcia** records, each with **Person:** and its detail. A grey line under them names the duplicate rule that found the pair. |
| 3 | Read the pair's buttons. | No **Merge households** button. The line **To merge two people, open either one and use Compare and merge on the Potential Duplicates card.** and a **Not a duplicate** button. |
| 4 | Click the new **Harper Garcia**'s name. On the **Potential Duplicates** card choose **View Duplicates**, then **Compare and merge**, keep the sample record as the master, and confirm. | Salesforce merges the two. |
| 5 | Open the kept **Harper Garcia** and the **The Garcia Family** household. | Harper is still a member of **The Garcia Family**. The household made for the new contact still exists, now empty. |
| 6 | Back on **Duplicates**, click **Refresh**. | The pair is gone. |

**Cleanup:** Delete the empty household left by the merge (or keep it for T-HC-05).

## T-DUP-03: Not a duplicate, and taking the dismissal back

**Purpose:** Confirm a dismissed pair is not suggested again until its dismissal is deleted.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact `Luis Garcia` with Email `luis.garcia2@example.org`, save past the warning, scan, and refresh. | A **Luis Garcia** pair is listed. Note the **Dismissed pairs** count. |
| 2 | Click **Not a duplicate** on the pair. | A box **Not a duplicate** opens: **The records stay as they are and this pair is not suggested again. Say why, for the next person who wonders.**, with **Reason**, **Not a duplicate** and **Cancel**. |
| 3 | Click **Cancel**. | The box closes; the pair is still listed. |
| 4 | Click **Not a duplicate** again, type `Test: father and son`, and click **Not a duplicate** in the box. | **Noted. This pair will not be suggested again.** The pair is gone and **Dismissed pairs** is one higher. |
| 5 | Scan again and refresh. | The pair does not come back. |
| 6 | Click **View** next to **Dismissed pairs**. Open **All Duplicate Dismissals**, find `Test: father and son`, and delete it. | The dismissal is deleted. |
| 7 | Scan again and refresh. | The **Luis Garcia** pair is listed again. |

**Cleanup:** Delete the contact you created and its household.

## T-DUP-04: Merge two households from a pair

**Purpose:** Confirm the household merge from the list keeps the chosen household and moves the members.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create an Account, record type **Household**, with the same **Account Name** as **The Garcia Family** and Billing Street `6830 Sunset Ln`, City `Springfield`, Zip `62756`. Save past the warning. | The household saves. |
| 2 | Scan and refresh **Duplicates**. | A pair of two households, each with **Household:** and its detail, with **Merge households** and **Not a duplicate**. |
| 3 | Click **Merge households**. | A box **Merge two households**: **Members, related records, files and activities of the other household move to the one you keep, totals are recalculated, and the other household is deleted. This cannot be undone.**, a **Household to keep** list, the fields where they differ, and **To choose field by field, use Merge or split on the household record instead.** |
| 4 | In **Household to keep**, choose the sample household (the one with members). | The list of differing fields marks which values are kept and which dropped. |
| 5 | Click **Merge these two**. | **The two households are now one.** The pair is gone. |
| 6 | Open **The Garcia Family**. | Harper, Luis and Diego are still members; the household you created no longer exists. |

**Cleanup:** None.

## T-DUP-05: A match source finds a pair the rules cannot

**Purpose:** Confirm the scan pairs households that share an address held on BarnCRM addresses, and says why.
**Prerequisites:** admin. **Address (household)** is **Active** on the **Duplicate Matching** tab, **Matching Logic**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create an Account, record type **Household**, named `Sunset Test Household` (a name no rule would match). | The household saves. |
| 2 | Open the **Addresses** tab and create an address: **Household or Organization** `Sunset Test Household`, **Street** `6830 SUNSET LN.`, **City** `Springfield`, **Postal Code** `62756`, **Primary** ticked. | The address saves. |
| 3 | On **Duplicate Matching**, **Matching Logic**, choose **Try a value** on **Address (household)**. Enter **Value** `6830 Sunset Ln`, **Postal code** `62756`, and choose **Try**. | **Compared as: 6830 sunset ln\|62756**, then **These records would match:** with **Household: The Garcia Family** and **Household: Sunset Test Household**. |
| 4 | On **Review**, scan and refresh. | A pair of `Sunset Test Household` and **The Garcia Family**, both **Household:**, with the grey line **Same address on Address (household)**. Capitals and the full stop did not stop the match. |
| 5 | Click **Not a duplicate**, give the reason `Test: match source`, confirm. | **Noted. This pair will not be suggested again.** |
| 6 | Scan again and refresh. | The pair does not come back. |

**Cleanup:** Delete `Sunset Test Household` and its address. Delete the `Test: match source` dismissal (see T-DUP-03, step 6).

## T-DUP-06: A deactivated match source finds nothing

**Purpose:** Confirm Matching Logic lists the shipped sources in words, deactivating one stops its pairs, and activating brings them back.
**Prerequisites:** admin, holding **BarnCRM Metadata Admin** (the create script gives it).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Duplicate Matching** tab and choose **Matching Logic**. | Six cards, each marked **Shipped with BarnCRM** and **Active**: **Contact Point Email**, **Contact Point Phone**, **Contact Point Address**, **Address (person)**, **Address (household)**, **Address (person account)**. In an org without contact point objects, those three say **Not used in this org**. Shipped cards have **Deactivate** and **Try a value**, and no **Edit**. |
| 2 | Read the **Address (household)** card. | **Object** Address, **Field compared** Street, **Postal code field** Postal Code, **Belongs to** a household or a person account, **Through the lookup** the household lookup, **How values are compared** starting **Address:**. |
| 3 | Choose **Deactivate** on **Address (household)**. | **Saving. Salesforce applies the change in the background, usually within a minute.**, then **Saved.** The card reads **Inactive**, with **Activate**. |
| 4 | Create a household `Pine Test Household` with a primary address **Street** `5616 Pine Dr`, **Postal Code** `78728` (the **Staff Household**'s address). | Both save. |
| 5 | On **Review**, scan and refresh. | No pair with `Pine Test Household`. |
| 6 | Back on **Matching Logic**, choose **Activate** on **Address (household)**. | **Saved.** The card reads **Active**. |
| 7 | Scan and refresh. | A pair of `Pine Test Household` and **Staff Household**, reason **Same address on Address (household)**. |

**Cleanup:** Delete `Pine Test Household` and its address; the pair goes with it.

## T-DUP-07: Adding a match source, and a bad one refused

**Purpose:** Confirm Matching Logic offers only fields that can work, checks a new source against the org before saving, and saves a good one.
**Prerequisites:** admin with **BarnCRM Metadata Admin**. In an org where BarnCRM is installed as a package, **Deploy Metadata from Non-Certified Package Versions via Apex** is on in Setup, **Apex Settings**.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Matching Logic**, click **Add**. | A **New Row** form: **Name**, **Object**, **Find fields**, **Field compared**, **Through the lookup**, **How values are compared**. |
| 2 | Enter **Object** `Not_An_Object__c` and choose **Find fields**. | **Not_An_Object__c is not an object in this org. Check its API name.** |
| 3 | Change **Object** to `Contact` and choose **Find fields**. | **Field compared** offers text, email and phone fields such as **Email** and **Assistant Phone**, and no date or number field. **Through the lookup** offers lookups such as **Account ID** and **Reports To ID**, and not **Last Name**. |
| 4 | Choose **How values are compared** **Address**. | A **Postal code field** list appears. |
| 5 | Choose **Field compared** **Mailing Street**, **Through the lookup** **Account ID**, leave **Postal code field** empty, and **Save**. | Refused: **An address source needs a postal code field: the street is compared together with it.** The form stays open. |
| 6 | Enter **Name** `Test: assistant phone`, choose **How values are compared** **Phone**, **Field compared** **Assistant Phone**, **Through the lookup** **Reports To ID**, and **Save**. | **Saving.**, then **Saved. Test: assistant phone is in the list.** Its card says **Belongs to** a person, has **Edit**, **Deactivate** and **Try a value**, and is not marked **Shipped with BarnCRM**. |
| 7 | Choose **Edit** on it, change **Name** to `Test: assistant phone 2`, and **Save**. | **Saved.** The card has the new name. |

**Cleanup:** Choose **Deactivate** on `Test: assistant phone 2` (Salesforce does not let an app delete custom metadata; delete it in Setup, **Custom Metadata Types**, **Match Source**, **Manage Records**, if you want it gone).

## T-DUP-08: Without BarnCRM Duplicate Review

**Purpose:** Confirm an admin without the permission set sees why, and cannot scan, merge or dismiss.
**Prerequisites:** admin; a second admin session or the CLI to restore the set.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Access**, **Extra Permissions**, remove **BarnCRM Duplicate Review** from yourself and confirm. | A message says you no longer have it. |
| 2 | Reload **Duplicate Matching**, **Review**. | Under **Possible duplicates**: **Suggestions need access to duplicate record sets, which Salesforce gives only to Sales Cloud and Service Cloud licenses. ...** No pairs are listed. |
| 3 | Look at **Scan for duplicates**. | Disabled. |

**Cleanup:** Give yourself **BarnCRM Duplicate Review** again on the **Access** page.

## T-DUP-09: Who sees the Duplicate Matching tab

**Purpose:** Confirm the tab is for administrators and BarnCRM Duplicate Review holders, a holder who is not an admin can read the review list but not act, Org Optimizer no longer lists duplicates, and BarnCRM Settings links to the tab.
**Prerequisites:** admin; staff given **BarnCRM Find and Export** on the **Access** page; T-DUP-01 done (at least one pair waiting).

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Org Optimizer**. | Only **Overview** and **Data quality**. No **Duplicates**. There is no **Duplicate Matching** tab. |
| 2 | As admin, in **BarnCRM Settings**, **Access**, **Extra Permissions**, remove **BarnCRM Find and Export** from the staff user and give them **BarnCRM Duplicate Review**. | A message says the staff user now has it. |
| 3 | As staff, wait a minute, reload, and open the **Duplicate Matching** tab (from the app launcher if it is not in the navigation bar). | Only the **Review** area. |
| 4 | Read the **Review** area. | The waiting pairs are listed, with **You can see this list. Scanning, dismissing and merging here need the Manage BarnCRM Settings permission.** **Scan for duplicates** and the pair actions are disabled. |
| 5 | As admin, open **BarnCRM Settings**. Under **People and Households**, look for a duplicates row; then choose the **Duplicate Matching** section. | **People and Households** has no duplicates row and no duplicates note. **Duplicate Matching** shows the note about duplicate rules and Duplicate Review, and the **Duplicate Matching** row with **Open this page**. |
| 6 | Click **Open this page**. | The **Duplicate Matching** tab opens on **Review**. |

**Cleanup:** Remove **BarnCRM Duplicate Review** from the staff user.

## T-DUP-10: Matching Logic without BarnCRM Metadata Admin

**Purpose:** Confirm an administrator without Metadata Admin can read the match sources and try a value, but not change them.
**Prerequisites:** admin; a second admin session or the CLI to restore the set.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Access**, **Extra Permissions**, remove **BarnCRM Metadata Admin** from yourself and confirm. | A message says you no longer have it. |
| 2 | Reload **Duplicate Matching** and choose **Matching Logic**. | **You can see the match sources. Adding or changing one needs the BarnCRM Metadata Admin permission set.** No **Add**, **Edit**, **Deactivate** or **Activate**. |
| 3 | Choose **Try a value** on **Contact Point Email** (or **Address (person)** where there are no contact point objects), enter `Someone@Example.org` (for the address source, `1 Main St` and postal code `12345`), and choose **Try**. | A **Compared as:** line with the value as compared, then the matching records or a line saying nobody holds it. Nothing is saved. |

**Cleanup:** Give yourself **BarnCRM Metadata Admin** again on the **Access** page.
