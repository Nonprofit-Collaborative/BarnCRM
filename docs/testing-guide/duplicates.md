# Duplicates

Scripts for the duplicate scan, the review list, merges, dismissals, match sources and the permissions behind them. Setup detail: [Duplicates](../admin-guide/duplicates.md); match sources: [Custom metadata](../admin-guide/custom-metadata.md#match-sources).

Before you start: an org from [Before you test](before-you-test.md) on the Person Accounts shape (duplicate review needs a Sales Cloud or Service Cloud license), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest. A scan reads every contact and household in the org and writes duplicate suggestion records for pairs among real people (it does not change the people); never merge or dismiss a pair that is not a fixture pair. In **BarnCRM Settings**, **General**, the **Duplicate Review**, **Addresses** and **Org Optimizer and Health Check** features are **On** (Addresses before the sample data loads, so each household has its address record). In Setup, **Duplicate Rules**, the **Standard Contact Duplicate Rule** and **Standard Account Duplicate Rule** are active.

## T-DUP-01: The Duplicates section and a scan

**Purpose:** Confirm the section lists the rules and a scan runs in the background and reports what it did.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)), holding **BarnCRM Duplicate Review** (the create script gives it; in a real-org sandbox give it on the **Access** page) and **Manage BarnCRM Settings** (the BarnCRM Admin role has it). Both are needed: the **Scan for duplicates** button works only with Manage BarnCRM Settings, and the suggestion list needs Duplicate Review. A holder of Duplicate Review without Manage BarnCRM Settings can read the section but not scan. At least the **Standard Contact Duplicate Rule** must be active in Setup, **Duplicate Rules**; a real org may have its own rules instead, so read the rule list in step 1 as it is.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Org Optimizer** and choose **Duplicates**. | The **Duplicates** panel. Under **Duplicate rules** each rule for people and accounts is listed with **On** or **Off**; at least two read **On**. A link **Open Duplicate Rules in Setup** is under them. |
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
| 2 | On **Org Optimizer**, **Duplicates**, click **Scan for duplicates**, wait, click **Refresh**. | Under **Possible duplicates** a pair of two **Harper Garcia** records, each with **Person:** and its detail. A grey line under them names the duplicate rule that found the pair. |
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
**Prerequisites:** admin. **Address (household)** is **In use** on the **Custom Metadata** page.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create an Account, record type **Household**, named `Sunset Test Household` (a name no rule would match). | The household saves. |
| 2 | Open the **Addresses** tab and create an address: **Household or Organization** `Sunset Test Household`, **Street** `6830 SUNSET LN.`, **City** `Springfield`, **Postal Code** `62756`, **Default** ticked. | The address saves. |
| 3 | On **Duplicates**, scan and refresh. | A pair of `Sunset Test Household` and **The Garcia Family**, both **Household:**, with the grey line **Same address on Address (household)**. Capitals and the full stop did not stop the match. |
| 4 | Click **Not a duplicate**, give the reason `Test: match source`, confirm. | **Noted. This pair will not be suggested again.** |
| 5 | Scan again and refresh. | The pair does not come back. |

**Cleanup:** Delete `Sunset Test Household` and its address. Delete the `Test: match source` dismissal (see T-DUP-03, step 6).

## T-DUP-06: An archived match source finds nothing

**Purpose:** Confirm archiving a shipped source stops its pairs, and restoring brings them back.
**Prerequisites:** admin, holding **BarnCRM Metadata Admin** (the create script gives it).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**, scroll to **Custom Metadata**, then **Match sources**. | **Shipped with BarnCRM** lists six rows: **Contact Point Email**, **Contact Point Phone**, **Contact Point Address**, **Address (person)**, **Address (household)**, **Address (person account)**, each **In use**. |
| 2 | Open the menu on **Address (household)** and choose **Archive**. | **Saving. Salesforce applies the change in the background, usually within a minute.**, then **Saved.** The row reads **Archived**. |
| 3 | Create a household `Pine Test Household` with a default address **Street** `5616 Pine Dr`, **Postal Code** `78728` (the **Staff Household**'s address). | Both save. |
| 4 | Scan and refresh **Duplicates**. | No pair with `Pine Test Household`. |
| 5 | Back on **Match sources**, choose **Restore** on **Address (household)**. | **Saved.** The row reads **In use**. |
| 6 | Scan and refresh. | A pair of `Pine Test Household` and **Staff Household**, reason **Same address on Address (household)**. |

**Cleanup:** Delete `Pine Test Household` and its address; the pair goes with it.

## T-DUP-07: A bad match source is refused

**Purpose:** Confirm the page checks a new source against the org before saving.
**Prerequisites:** admin with **BarnCRM Metadata Admin**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Under **Match sources**, click **Add**. | A **New Row** form. |
| 2 | Fill in **Object Name** `Not_An_Object__c`, any **Value Field** and **Parent Field**, **Normalization** **Email**, and click **Save**. | Refused: **Not_An_Object__c is not an object in this org. Check its API name.** Nothing is added. |
| 3 | Change **Object Name** to `Contact`, **Value Field** `Nope__c`, **Parent Field** `AccountId`. Save. | **Nope__c is not a field on Contact. Check its API name.** |
| 4 | Set **Value Field** `Email`, **Parent Field** `Email`. Save. | Refused with a message that **Email** on **Contact** is not a lookup to a contact, account or Individual. |
| 5 | Set **Normalization** **Address**, **Value Field** `MailingStreet`, **Parent Field** `AccountId`, leave **Postal Code Field** empty. Save. | **An address source needs a postal code field: the street is compared together with it.** |
| 6 | Click **Cancel**. | **Added by Your Organization** is unchanged. |

**Cleanup:** None.

## T-DUP-08: Without BarnCRM Duplicate Review

**Purpose:** Confirm an admin without the permission set sees why, and cannot scan, merge or dismiss.
**Prerequisites:** admin; a second admin session or the CLI to restore the set.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Access**, **Extra Permissions**, remove **BarnCRM Duplicate Review** from yourself and confirm. | A message says you no longer have it. |
| 2 | Reload **Org Optimizer**, **Duplicates**. | Under **Possible duplicates**: **Suggestions need access to duplicate record sets, which Salesforce gives only to Sales Cloud and Service Cloud licenses. ...** No pairs are listed. |
| 3 | Look at **Scan for duplicates**. | Disabled. |

**Cleanup:** Give yourself **BarnCRM Duplicate Review** again on the **Access** page.

## T-DUP-09: Who sees the Duplicates section

**Purpose:** Confirm the section is for administrators and BarnCRM Duplicate Review holders only, a holder who is not an admin can read it but not act, and BarnCRM Settings links to it.
**Prerequisites:** admin; staff given **BarnCRM Find and Export** on the **Access** page; T-DUP-01 done (at least one pair waiting).

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Org Optimizer**. | Only **Overview** and **Data quality**. No **Duplicates**. |
| 2 | As admin, in **BarnCRM Settings**, **Access**, **Extra Permissions**, remove **BarnCRM Find and Export** from the staff user and give them **BarnCRM Duplicate Review**. | A message says the staff user now has it. |
| 3 | As staff, wait a minute, reload, and open **Org Optimizer**. | Only **Overview** and **Duplicates**. **Overview** lists one section. |
| 4 | Choose **Duplicates**. | The waiting pairs are listed, with **You can see this list. Scanning, dismissing and merging here need the Manage BarnCRM Settings permission.** **Scan for duplicates** and the pair actions are disabled. |
| 5 | As admin, open **BarnCRM Settings**, **People and Households**, find the **Duplicates** row in the **People** box. | It describes duplicate review in Org Optimizer and has **Open Org Optimizer**. |
| 6 | Click **Open Org Optimizer**. | The **Org Optimizer** tab opens. |

**Cleanup:** Remove **BarnCRM Duplicate Review** from the staff user.
