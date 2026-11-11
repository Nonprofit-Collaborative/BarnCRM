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
| 2 | Read the buttons and counts. | **Scan for Duplicates** and **Refresh** are enabled. **Dismissed suggestions** shows a number. |
| 3 | Click **Scan for Duplicates**. | A green notice **Scan started. The bell tells you when it finishes.** **Scan for Duplicates** is disabled and **A scan is running. The bell tells you when it finishes.** shows. Nothing asks you to refresh the page. |
| 4 | When the bell shows **Duplicate scan finished**, click **Refresh**. | **Last scan finished** with a date and time, and a line **Duplicate scan of ... finished: N new possible duplicates recorded.** in normal (not red) text. **Scan for Duplicates** is enabled again. |
| 5 | Check the bell. | One notification titled **Duplicate scan finished**. |

**Cleanup:** None.

## T-DUP-02: A Duplicate Person Is Found and Merged

**Purpose:** Confirm a person pair is listed with its reason, and Salesforce's merge keeps the person in the household.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact: First Name `Harper`, Last Name `Garcia`, Email `harper.garcia1@example.org`. | Salesforce warns that a similar record exists. Save anyway. |
| 2 | On **Duplicate Matching**, **Review**, click **Scan for Duplicates**, wait, click **Refresh**. | Under **Possible Duplicates** a pair of two **Harper Garcia** records, each with **Person:** and its detail. A grey line under them names the duplicate rule that found the pair. |
| 3 | Read the pair's buttons. | The pair has **Compare and Merge** (the main button) and **Not a Duplicate** on the right, and no **Merge Households** button. There is no note above the list telling you to open a record. |
| 4 | Click **Compare and Merge**. On the first **Harper Garcia**'s record page, which opens (a subtab in a console app), on the **Potential Duplicates** card choose **View Duplicates**, then **Compare and merge**, keep the sample record as the master, and confirm. | Salesforce merges the two. |
| 5 | Open the kept **Harper Garcia** and the **The Garcia Family** household. | Harper is still a member of **The Garcia Family**. The household made for the new contact still exists, now empty. |
| 6 | Back on **Duplicates**, click **Refresh**. | The pair is gone. |

**Cleanup:** Delete the empty household left by the merge (or keep it for T-HC-05).

## T-DUP-03: Not a Duplicate, and Taking the Dismissal Back

**Purpose:** Confirm a dismissed pair is not suggested again until its dismissal is deleted.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact `Luis Garcia` with Email `luis.garcia2@example.org`, save past the warning, scan, and refresh. | A **Luis Garcia** pair is listed. Note the **Dismissed suggestions** count. |
| 2 | Click **Not a Duplicate** on the pair. | A box **Not a Duplicate** opens: **The records stay as they are and this suggestion does not come back. Say why, for the next person who wonders.**, with **Reason**, **Not a Duplicate** and **Cancel**. |
| 3 | Click **Cancel**. | The box closes; the pair is still listed. |
| 4 | Click **Not a Duplicate** again, type `Test: father and son`, and click **Not a Duplicate** in the box. | **Noted. This suggestion will not come back.** The pair is gone and **Dismissed suggestions** is one higher. |
| 5 | Scan again and refresh. | The pair does not come back. |
| 6 | Click **View** next to **Dismissed suggestions**. Open **All Duplicate Dismissals**, find `Test: father and son`, and delete it. | The dismissal is deleted. |
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
| 5 | Click **Not a Duplicate**, give the reason `Test: match source`, confirm. | **Noted. This suggestion will not come back.** |
| 6 | Scan again and refresh. | The pair does not come back. |

**Cleanup:** Delete `Sunset Test Household` and its address. Delete the `Test: match source` dismissal (see T-DUP-03, step 6).

## T-DUP-06: A Deactivated Match Source Finds Nothing

**Purpose:** Confirm Matching Logic lists the shipped sources in words, deactivating one stops its pairs, and activating brings them back.
**Prerequisites:** admin with **BarnCRM Admin**, which includes the permission to save match sources.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Duplicate Matching** tab and choose **Matching Logic**. | Under one intro line with a help icon, six cards, each with a **Shipped with BarnCRM** badge and its **Active** switch on: **Contact Point Email**, **Contact Point Phone**, **Contact Point Address**, **Address (person)**, **Address (household)**, **Address (person account)**. Each has one line such as **Email Address on Contact Point Email, compared as Email**. In an org without contact point objects, those three say **Not used in this org**. Shipped cards have **Show Details** and **Try a Value**, and no **Edit**. |
| 2 | Choose **Show Details** on the **Address (household)** card. | **Object** Address, **Value compared** Street, **Postal code field** Postal Code, **Belongs to** a household or a person account, **Linked through the field** the household lookup, **How values are compared** starting **Address:**. The button now reads **Hide Details**. |
| 3 | Turn off the **Active** switch on **Address (household)**. | At once, with no saving wait: **Address (household) is turned off. Duplicate Matching and import matching no longer use it.** and the switch is off. In Setup, **Custom Metadata Types**, **Match Source**, the **Address (household)** row still has **Active** ticked (the row is never changed, D-184). |
| 4 | Create a household `Pine Test Household` with a primary address **Street** `5616 Pine Dr`, **Postal Code** `78728` (the **Staff Household**'s address). | Both save. |
| 5 | On **Review**, scan and refresh. | No pair with `Pine Test Household`. |
| 6 | Back on **Matching Logic**, turn on the **Active** switch on **Address (household)**. | At once: **Address (household) is turned on and used for matching again.** The switch is on. |
| 7 | Scan and refresh. | A pair of `Pine Test Household` and **Staff Household**, reason **Same address on Address (household)**. |

**Cleanup:** Delete `Pine Test Household` and its address; the pair goes with it.

## T-DUP-07: Adding a Match Source, and a Bad One Refused

**Purpose:** Confirm Matching Logic offers only fields that can work, checks a new source against the org before saving, and saves a good one.
**Prerequisites:** admin with **BarnCRM Admin**. In an org where BarnCRM is installed as a package, **Deploy Metadata from Non-Certified Package Versions via Apex** is on in Setup, **Apex Settings** (if it is off, a save fails with a message naming it).

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Matching Logic**, click **Add**. | A window **New Match Source** over the page, with focus inside it: **Name**, **Object**, **Find Fields**, **Value compared**, **Linked through the field**, **How values are compared**, and **Cancel** and **Save** at the bottom. Press Escape: the window closes and nothing is saved. |
| 2 | Click **Add** again. Enter **Object** `Not_An_Object__c` and choose **Find Fields**. | In the window: **Not_An_Object__c is not an object in this org. Check its API name.** |
| 3 | Change **Object** to `Contact` and choose **Find Fields**. | **Value compared** offers text, email and phone fields such as **Email** and **Assistant Phone**, and no date or number field. **Linked through the field** offers lookups such as **Account ID** and **Reports To ID**, and not **Last Name**. |
| 4 | Choose **How values are compared** **Address**. | A **Postal code field** list appears. |
| 5 | Choose **Value compared** **Mailing Street**, **Linked through the field** **Account ID**, leave **Postal code field** empty, and **Save**. | Refused: **An address source needs a postal code field: the street is compared together with it.** in the window, which stays open. |
| 6 | Enter **Name** `Test: assistant phone`, choose **How values are compared** **Phone**, **Value compared** **Assistant Phone**, **Linked through the field** **Reports To ID**, and **Save**. | The window closes. **Saving.**, then **Saved. Test: assistant phone is in the list.** Its card has **Edit**, the **Active** switch and **Try a Value**, no **Shipped with BarnCRM** badge, and **Show Details** says **Belongs to** a person. |
| 7 | Choose **Edit** on it. In the window, change **Name** to `Test: assistant phone 2`, and **Save**. | The window opens with the source's values and its object's fields filled in. **Saved.** The card has the new name. |

**Cleanup:** Turn off the **Active** switch on `Test: assistant phone 2` (Salesforce does not let an app delete custom metadata; delete it in Setup, **Custom Metadata Types**, **Match Source**, **Manage Records**, if you want it gone).

## T-DUP-08: Without BarnCRM Duplicate Review

**Purpose:** Confirm an admin without the permission set sees why, and cannot scan, merge or dismiss.
**Prerequisites:** admin; a second admin session or the CLI to restore the set.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Access**, **Extra Permissions**, remove **BarnCRM Duplicate Review** from yourself and confirm. | A message says you no longer have it. |
| 2 | Reload **Duplicate Matching**, **Review**. | Under **Possible Duplicates**, an info notice: **Possible duplicates can be listed only for people with a Sales Cloud or Service Cloud license. Duplicate rules still check records as they are saved.** No pairs are listed. |
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

## T-DUP-10: Matching Logic Without Permission to Save

**Purpose:** Confirm a person without BarnCRM Admin or BarnCRM Metadata Admin can read the match sources and try a value, but not change them.
**Prerequisites:** a user who has the **Duplicate Matching** tab through **BarnCRM Duplicate Review** only: no BarnCRM Admin, no BarnCRM Metadata Admin. (An admin cannot do this by removing Metadata Admin, because BarnCRM Admin carries the permission.)

| Step | Action | Expected result |
|---|---|---|
| 1 | Sign in as that user and open **Duplicate Matching**. | The tab shows. |
| 2 | Choose **Matching Logic**. | **You can see the match sources. Adding or changing one needs the BarnCRM Metadata Admin permission set.** No **Add**, no **Edit** and no **Active** switch; each card shows an **Active** or **Inactive** badge instead. |
| 3 | Choose **Try a Value** on **Contact Point Email** (or **Address (person)** where there are no contact point objects), enter `Someone@Example.org` (for the address source, `1 Main St` and postal code `12345`), and choose **Try**. | A **Compared as:** line with the value as compared, then the matching records or a line saying nobody holds it. Nothing is saved. |

**Cleanup:** none.

## T-DUP-11: A Long Review List

**Purpose:** Confirm a long list shows a count and 10 pairs at a time, with one shared note, and an empty list shows the empty state.
**Prerequisites:** admin; T-DUP-01 done with more than 10 pairs waiting (sample data on oi-test gives about 40). For step 5, an org with no pairs waiting (a fresh org before any scan).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Duplicate Matching**, **Review**. | The tab reads **Review (40)** (or **Review (50+)**), and **Possible Duplicates** has a badge with the same number. 10 pair cards, each with the reason and buttons at the top and the two records side by side under them. Under the cards **Showing 10 of 40 suggestions, newest first.** and **Show More**. |
| 2 | Look at a pair of two people and a pair of two households. | The people pair has **Compare and Merge**; the household pair has **Merge Households**; both have **Not a Duplicate**. No note sits above the list. A value that differs carries an amber **Different** badge with a warning icon. |
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

## T-DUP-13: A Suggestion of Three or More Records

**Purpose:** Confirm a suggestion naming three or more records compares each with the first and says so.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact: First Name `Harper`, Last Name `Garcia`, Email `harper.garcia1@example.org`, and save past the warning. Then create a second one the same way with Email `harper.garcia3@example.org`, and save past the warning. | Both save. The second save's warning names two existing records. |
| 2 | On **Duplicate Matching**, **Review**, click **Refresh**. | A card with three **Harper Garcia** records and the line "Each record is compared with Harper Garcia, the first one." On a wide screen the records sit in up to three columns. |
| 3 | Read the **Email** values. | The first record has no **Different** badge. Each other record whose email differs from the first one's has one. A screen reader reads it as different from the first record's name. |
| 4 | Read the counts. | The tab and **Possible Duplicates** count suggestions, and the dismissed count reads **Dismissed suggestions**. |

**Cleanup:** None.

## T-DUP-14: Similar Names, Household Aware

**Purpose:** Confirm the scan pairs similar names only with something else in common, and treats one household as family.
**Prerequisites:** admin. In **BarnCRM Settings**, **Duplicate Matching**, **Fuzzy name match** reads **90**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact: First Name `Jonathan`, Last Name `Zzfuzz`, Email `jz.fuzz@example.org`. Create another: First Name `Jonathon`, Last Name `Zzfuzz`, Email `JZ.Fuzz@example.org`; save past any warning. | Both save, each in a household of its own. |
| 2 | Create a contact `Jonathen Zzfuzz` with Email `other.fuzz@example.org`. | It saves. |
| 3 | Create a household `Zzfuzz Family Household`, and in it four contacts with no email or phone: `Daniel Zzfuzz`, `Danielle Zzfuzz`, `Sam Zzfuzz` and `Sam Zzfuzz` (save past any warning). | All save in that household. |
| 4 | On **Duplicate Matching**, **Review**, scan and refresh. | A pair of **Jonathan Zzfuzz** and **Jonathon Zzfuzz**, with the line **Similar names (95%) and the same email** (the percentage varies a little with the last name), or the name of a duplicate rule when an active rule found the pair first. A pair of the two **Sam Zzfuzz**, with **Same name in the same household** (or a rule's name, if your rules found it first). No pair names **Jonathen Zzfuzz** (nothing else in common), and no pair of **Daniel** and **Danielle**. |

**Cleanup:** Delete the `Zzfuzz` contacts and `Zzfuzz Family Household`; their pairs go with them.

## T-DUP-15: Merge Rules and the Setting for Other Fields

**Purpose:** Confirm merge rules are listed on the Custom Metadata page, a bad one is refused, and the setting for other fields shows its default.
**Prerequisites:** admin with **BarnCRM Admin**. In an org where BarnCRM is installed as a package, **Deploy Metadata from Non-Certified Package Versions via Apex** is on in Setup, **Apex Settings** (if it is off, a save fails with a message naming it).

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, open **Duplicate Matching**. | **Fuzzy name match** reads **90** and **Merge rule for other fields** reads **Not blank**, each with a description. Change **Merge rule for other fields** to **Most recent** and save: **Saved.** Change it back to **Not blank** and save. |
| 2 | Open **Custom Metadata**. | Two lists: **Relationship types** and **Merge Rules**, the second empty with a line explaining it. |
| 3 | Under **Merge Rules**, add a row: **Field Name** `AccountId`, **Rule** **Most recent**, and save. | Refused: **AccountId is not a person field a merge can change.** and the rest of the sentence. |
| 4 | Change **Field Name** to `Email` and save. | **Saved** once Salesforce applies it. The row lists **Email**, **Most recent**. |
| 5 | Add another row: **Field Name** `Email`, **Rule** **Oldest record**, and save. | Refused: an active row already names **Email**. |

**Cleanup:** Archive the `Email` merge rule.

## T-DUP-16: Auto-Merge Previews, Confirms and Merges Exact Matches

**Purpose:** Confirm Auto-Merge previews only exact people matches from the review list, merges them in the background after a confirm, and lists the run.
**Prerequisites:** admin with **BarnCRM Admin** and **BarnCRM Duplicate Review**. Two Zztest pairs: **Zztest Ann Auto** twice with the same email `zztest.ann.auto@example.org` (different phones), and **Zztest Ben Auto** twice with different emails. A duplicate scan has run, so the Ann pair is in the review list; the Ben pair is not, because two people with different emails and no phone in common are no match.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, open **Duplicate Matching**. | **Exact match for auto-merge** reads **Name and email**, with a description. |
| 2 | Open the **Duplicate Matching** tab, then **Auto-Merge**. | The intro, **Exact match: Name and email.**, **Preview Exact Matches**, and **Recent Runs** reading **No auto-merge in the last 15 days.** |
| 3 | Click **Preview Exact Matches**. | **Pairs To Merge (1)**: the Ann pair only, with **Keep:**, **Merge away:** and the values that will change (for example **Phone: (blank) becomes ...**), or **No values change.** The Ben pair is not listed. |
| 4 | Click **Merge 1 Pairs**, then **Cancel**. | Nothing is merged; the preview stays. |
| 5 | Click **Merge 1 Pairs** and confirm. | **Auto-merge started.** The bell reports **Auto-Merge Finished** with 1 pair merged. |
| 6 | Click **Refresh**. | **Recent Runs** lists the run: **1 people merged, 0 undone, 0 not fully undone**, with **Undo**. One Ann record remains; the other is in the Recycle Bin. The Ben records are both still there, untouched. |

**Cleanup:** Keep the run for T-DUP-17.

## T-DUP-17: Undoing an Auto-Merge Run, and What It Cannot Restore

**Purpose:** Confirm Undo restores the merged-away person from the Recycle Bin, puts back changed values and moved related records, and lists what it cannot restore.
**Prerequisites:** T-DUP-16 done. Before undoing, on the kept Ann record change a value the merge changed (for example **Phone**).

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Auto-Merge**, under the run, click **Undo**. | **Undo This Run** asks to confirm, naming the Recycle Bin, values and related records. |
| 2 | Confirm. | **Undo started.** The bell reports **Auto-Merge Undo Finished**. |
| 3 | Click **Refresh**. | The run reads **1 people merged, 0 undone, 1 not fully undone**, with a note: **Phone was changed after the merge and was left as it is.** **Undo** is gone. |
| 4 | Open both Ann records. | The merged-away Ann is back (same record Id as before, not a copy), with her activities and relationships. The kept Ann keeps the phone you typed. |
| 5 | As a user without **BarnCRM Admin**, open the **Duplicate Matching** tab. | No **Auto-Merge** area. |

**Cleanup:** Delete the Zztest Auto records.

## T-DUP-18: Households Sharing Only a City Are Not Paired

**Purpose:** Confirm two households that share only a billing city and state are never listed, while two at one address are.
**Prerequisites:** admin. In Setup, **Duplicate Rules**, the **Standard Account Duplicate Rule** is active.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Home**, click **New Household** twice, then edit them: `The Zztest Hall Family`, Billing Street `8848 Highland Ln`, City `Toledo`, State `OH`, Zip `43622`; and `The Zztest Shah Family`, Billing Street `9719 Harbor Dr`, City `Toledo`, State `OH`, Zip `43621`. Save past any warning. | Both save. |
| 2 | On **Duplicate Matching**, **Review**, scan and refresh. | No suggestion pairs `The Zztest Hall Family` with `The Zztest Shah Family`, and neither appears on a card with only households that share its city. |
| 3 | Create a third household `The Zztest Hall Family`, Billing Street `8848 Highland Lane`, City `Toledo`, State `OH`, Zip `43622`. Save past the warning. Scan and refresh. | A pair of the two `The Zztest Hall Family` households, with **Merge Households**. `The Zztest Shah Family` is not on it. |

**Cleanup:** Dismiss the pair with **Not a Duplicate** (or merge it) and delete the Zztest households.

## T-DUP-19: Duplicate Rules Starter

**Purpose:** Confirm the starter shows the org's rules untouched, creates BarnCRM's people and household rules through the org connection, and explains a missing connection.
**Prerequisites:** admin with **BarnCRM Metadata Admin**, Customize Application and Modify Metadata. Not in `mwdbdevsb` without Brandon's approval (it writes org metadata). For step 1 the org connection is not set up; for steps 3 onward it is set up and connected (see [Creating a New Field From an Import](../admin-guide/import-new-fields.md)).

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Duplicate Matching**, **Review**, choose **Duplicate Rules Starter**. | A section **Duplicate Rules Starter** opens under the rules box with its intro, a notice that the org connection is needed and the connection panel. **Set Up Rules** is disabled. Under **People** and **Households**, the rule in words and your own rules, each "(active, left as it is)" or "(inactive, left as it is)". |
| 2 | Set up the connection from the panel, then choose **Refresh**. | The notice is gone. Both sets are ticked with **Set Up will:** two steps each (create the matching rule, create the duplicate rule). |
| 3 | Choose **Set Up Rules**. | A dialog lists the four steps. Confirm. A line says BarnCRM is writing the rules. |
| 4 | Wait a few minutes. | The line is replaced by a green notice **Duplicate Rules Starter finished. Set up and active: People, Households.** Both sets read **Set up and active.** |
| 5 | In Setup, open **Matching Rules** and **Duplicate Rules**. | **BarnCRM People Match** and **BarnCRM Household Match** are Active; **BarnCRM People Duplicates** and **BarnCRM Household Duplicates** are Active, action Allow with Alert and Report, and the household rule has the condition Account Record Type equals Household. The standard rules are unchanged. |
| 6 | Deactivate **BarnCRM People Duplicates** in Setup. Back on the starter choose **Refresh**. | **People** is ticked with one step: rewrite BarnCRM's duplicate rule and activate it. **Set Up Rules** repairs it; **Households** stays **Set up and active.** |

**Cleanup:** In Setup, deactivate and delete the four BarnCRM rules if the org should not keep them.

## T-DUP-20: Merge Records Merges Two Funds and Moves Their Gifts

**Purpose:** Confirm Merge Records compares two records of one BarnCRM object, starts each field from the merge rules, moves the related records, sends the other record to the Recycle Bin and lists the merge.
**Prerequisites:** admin. Giving installed. Two funds: `Zztest Fund A` with **Description** blank, and `Zztest Fund B` with Description `Merge test` and one gift on it. In a Core-only org use two import mappings instead (Data Manager, Import, save a mapping twice) with one import job on the second.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Duplicate Matching** tab, then **Merge Records**. | The area says Merge Records is off, with nothing to choose. |
| 2 | In **BarnCRM Settings**, **Duplicate Matching**, turn on **Turn On Merge Records** and save. Reopen the tab, then **Merge Records**. | The intro, **Object**, a disabled **Compare** and **Recent Merges** reading that nothing was merged in the last 15 days. |
| 3 | Choose **Object** Fund, pick `Zztest Fund A` as **First Record** and `Zztest Fund B` as **Second Record**, click **Compare**. | The two funds side by side, `Zztest Fund A` chosen as **Record to Keep**. **Description** shows the value `Merge test` selected (merge rule Not blank). No owner, record type or unique field rows. |
| 4 | Tick **Only Differences**. | Only rows whose values differ remain. |
| 5 | Click **Merge** and confirm. | A message: merged, 1 related record moved, 1 value changed. The comparison closes. **Recent Merges** lists `Fund: Zztest Fund B` with **Undo**. |
| 6 | Open `Zztest Fund A`. | Description reads `Merge test`; the gift that was on Fund B is on Fund A. `Zztest Fund B` is in the Recycle Bin. |
| 7 | On **Auto-Merge**, read **Recent Runs**. | The fund merge is not listed there. |

**Cleanup:** Keep the merge for T-DUP-21.

## T-DUP-21: Undoing a Merge, and a Merge That Is Refused

**Purpose:** Confirm Undo on a merge restores the other record, its values and its related records, and a merge that would lose records is refused with nothing changed.
**Prerequisites:** T-DUP-20 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Under **Recent Merges**, click **Undo** on `Zztest Fund B` and confirm. | The row reads **Undone** and **Undo** is gone. |
| 2 | Open both funds. | `Zztest Fund B` is back (same record Id), with its gift. Fund A's Description is blank again. |
| 3 | Compare two records where the person merging cannot read a related object (for example as an admin without access to one module's objects), and click **Merge**. | An error names the records that could not be read and says nothing was merged. Both records are unchanged. |
| 4 | As a user without **BarnCRM Admin**, open the **Duplicate Matching** tab. | No **Merge Records** area. |

**Cleanup:** Delete the Zztest funds and gift.
