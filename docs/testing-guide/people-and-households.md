# People and Households

Scripts for people, households, the Members and Household panels, names and greetings, merge and split, preferred phone, interaction notes and the record pages. Setup detail: [Households](../admin-guide/households.md), [Household members](../admin-guide/household-members.md), [Household names and greetings](../admin-guide/household-naming.md), [Merging and splitting households](../admin-guide/household-merge-split.md), [Preferred phone](../admin-guide/preferred-phone.md), [Interaction notes](../admin-guide/interaction-notes.md), [Record pages](../admin-guide/record-pages.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest. T-HH-14 needs a person account, so skip it there. The **Household Upkeep** and **Preferred Email and Phone** features must be on (BarnCRM Settings, **General**). Open every record from the **BarnCRM** app. Check which way of belonging the org uses (BarnCRM Settings, **People and Households**, **How people belong to a household**): **One household per person (simple)** or **A person can belong to more than one household (flexible)**. Steps that differ between the two say so. The sample people are contacts in both org shapes.

## T-HH-01: A New Person Gets a Household

**Purpose:** saving a person with no household creates and names one, and both panels show it.
**Prerequisites:** admin. **Create a household automatically** is on (ships on).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Contacts** tab, select **New**, enter Salutation `Ms.`, First Name `Ada`, Last Name `Testwell`, leave the account blank, and save. | The person saves. In the simple way the account field names **The Testwell Family**; in the flexible way it stays blank. |
| 2 | Look at the **Household** panel on Ada's page. | It links to **The Testwell Family**, reads **1 member**, and shows **Formal greeting: Ms. Ada Testwell**. |
| 3 | Select the household name in the panel. | The household page opens. The **Members** panel lists Ada Testwell with a **Primary** badge. **Name and Greetings** shows Formal Greeting **Ms. Ada Testwell**, Informal Greeting **Ada**, Member Count **1**, Primary Contact **Ada Testwell**. |
| 4 | Open **Home**, then select **New Household**. | A household named **New Household** is created and its page opens, with no record type prompt. Delete it. |

**Cleanup:** keep Ada and The Testwell Family for T-HH-02 to T-HH-07.

## T-HH-02: Add Member and Automatic Naming (Simple Way)

**Purpose:** Add Member creates a person in the household and the name and greetings follow the members.
**Prerequisites:** admin, simple way, T-HH-01 done. Use T-HH-03 instead in the flexible way.

| Step | Action | Expected result |
|---|---|---|
| 1 | On The Testwell Family, select **Add Member** in the **Members** panel. | The **Add Member** dialog opens with Salutation, First Name and Last Name, a **Save** and a **Cancel** button. |
| 2 | Enter `Mr.`, `Ben`, `Testwell` and select **Save**. | The dialog closes. A toast reads **Added. The household name and greetings have been brought up to date.** Ben appears as a tile with his initials **BT**. |
| 3 | Refresh the page. | Member Count **2**. Formal Greeting **Ms. Ada Testwell and Mr. Ben Testwell**. Informal Greeting **Ada and Ben**. The name stays **The Testwell Family**. |
| 4 | Add a third member `Wei` `Lee` (no salutation) and refresh. | Member Count **3**. The name reads **Testwell and Lee Household** because the surnames differ. |
| 5 | Open the menu on Wei's tile and select **Move to Another Household**, pick **The Garcia Family** in the picker and select **Save**. | A toast reads **Moved. Both households have been brought up to date.** Wei leaves the list; the name returns to **The Testwell Family**, Member Count **2**. |
| 6 | Reverse it: open The Garcia Family, use **Move to Another Household** on Wei, and choose The Testwell Family. | Wei is back in The Testwell Family; The Garcia Family is back to its three members and its own name. |

**Cleanup:** delete Wei Lee.

## T-HH-03: Add Member (Flexible Way)

**Purpose:** in the flexible way Add Member offers search and create.
**Prerequisites:** admin, flexible way, T-HH-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On The Testwell Family, select **Add Member**. | The **Add Member** dialog shows **Add Someone Already in Salesforce** with a search box (placeholder **Search by name**) and **Or Add Someone New** with Salutation, First name and Last name. |
| 2 | Type `zzqq` in the search box. | **No matches. Keep typing, or add them as a new person below.** |
| 3 | Leave Last name empty and select **Save**. | **Enter at least a last name before saving.** Nothing is created. |
| 4 | Enter `Mr.`, `Ben`, `Testwell` and select **Save**. | A toast confirms the add; Ben is listed; after refresh Member Count is **2** and Informal Greeting **Ada and Ben**. |
| 5 | Open **Add Member** again, search `Diego`, and select **Diego Garcia**. | Diego joins The Testwell Family and stays in The Garcia Family. His **Household** panel lists both households. |
| 6 | Open the **Household Members** tab, open Diego's new membership, set **End Date** to yesterday, and save. | Diego disappears from The Testwell Family's panel and its Member Count drops by one. The Garcia Family is unchanged. |
| 7 | Create a second current membership for Ben in The Testwell Family from the **Household Members** tab. | Refused: **This person is already a current member of this household. Edit their existing membership instead of adding another.** |

**Cleanup:** delete Diego's ended membership record.

## T-HH-04: Make Primary

**Purpose:** Make Primary moves the primary contact and the Primary Contact field follows.
**Prerequisites:** admin, The Testwell Family with Ada and Ben.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the menu on Ben's tile and select **Make Primary**. | A toast reads **Ben Testwell is now the primary contact.** The **Primary** badge moves to Ben; **Make Primary** now shows in Ada's menu and not in Ben's. |
| 2 | Refresh. | Primary Contact reads **Ben Testwell**. |
| 3 | Simple way: edit the household and set Primary Contact to **Harper Garcia**. | Refused: **The Primary Contact has to be somebody in this household. Choose one of its members, or move the person into the household first.** |
| 4 | Flexible way: edit the household and change Primary Contact to Ada. | Refused with a message starting **In this org a household's Primary Contact follows the member marked primary.** |
| 5 | Select **Make Primary** on Ada to put it back. | Badge and Primary Contact return to Ada. |

**Cleanup:** None.

## T-HH-05: Greetings: Deceased, Preferred Name, Exclusions, Custom Name

**Purpose:** person-level boxes change the greetings, and Custom Name locks the name and every greeting that has a value.
**Prerequisites:** admin, The Testwell Family with Ada and Ben, **Include people who have died in names** off (ships off).

| Step | Action | Expected result |
|---|---|---|
| 1 | On Ben, set **Preferred Name** to `Benji` and save. Refresh the household. | Informal Greeting **Ada and Benji**. Formal Greeting still **Ms. Ada Testwell and Mr. Ben Testwell**. |
| 2 | On Ben, tick **Exclude From Greetings** and save. Refresh the household. | Informal Greeting **Ada**, Formal Greeting **Ms. Ada Testwell**. Member Count still **2**. |
| 3 | Untick it, tick **Deceased** on Ben, and save. Refresh the household. | Greetings leave Ben out. His row in **Members** carries a **Deceased** badge. |
| 4 | Untick **Deceased**. On the household tick **Custom Name**, set the name to `The Testwell Household (custom)`, and save. | The name saves as typed. |
| 5 | Add a member `Cy` `Testwell` and refresh. | Name and greetings are unchanged; Member Count goes up. |
| 6 | On the household clear **Informal Greeting** and save. On Cy, set **Preferred Name** to `Cyrus` and save. Refresh the household. | Informal Greeting is filled from the members and includes Cyrus. Name and Formal Greeting are unchanged. |
| 7 | Untick **Custom Name** and save. | The name is recalculated at once to **The Testwell Family** and the greetings include Cy. |

**Cleanup:** delete Cy Testwell; clear Ben's Preferred Name.

## T-HH-06: Naming Patterns, Preview and Recompute

**Purpose:** the naming panel previews, saves and recomputes, and is read only without the permission.
**Prerequisites:** admin; read-only user for step 6.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **People and Households**. | In the **Household Names and Greetings** box, the **Household Names and Greetings** panel shows **Household name pattern**, **Formal greeting pattern**, **Informal greeting pattern**, and **How Five Sample Households Would Read**. |
| 2 | Change **Household name pattern** to `{LastName} Household`. | The preview updates as you type. |
| 3 | Select **Save**. | **Saved. New households use these patterns straight away.** |
| 4 | Select **Update All Household Names**, then **Yes, Recompute** in the dialog. | **Updating household names in the background.** After a few minutes The Garcia Family reads **Garcia Household**; the **Staff Household** (Custom Name) is unchanged. |
| 5 | Put the pattern back to `The {LastName} Family`, save, and recompute again. | Names return to **The Garcia Family** form. |
| 6 | As read-only, open the same panel. | **You can see these settings but not change them. Changing them needs the Manage BarnCRM Settings permission.** The patterns cannot be saved. |
| 7 | As admin, look at the table under **How Five Sample Households Would Read** at normal desktop width. | The whole table fits inside the settings panel: long names and greetings wrap onto more lines, and there is no horizontal scroll bar on the table or the page. |

**Cleanup:** pattern back to `The {LastName} Family`.

## T-HH-07: Merge Two Households (with Cancel)

**Purpose:** merge combines two households after a warning, and cancel leaves both untouched.
**Prerequisites:** admin (staff also passes), The Testwell Family with Ada and Ben (Ben is added in T-HH-02 steps 1 to 3; the smoke list runs those first). Step 7 needs an organization with Bayview in its name: sample data has **Bayview Hardware**; with no sample data, first create an organization `Zztest Bayview Hardware` (an organization: the record type in **Record type for organizations**).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact `Cara` `Testwell` with no account. | A second household named **The Testwell Family** is created for her. |
| 2 | Open the first Testwell household (Ada's) and select **Merge or Split** in the action bar. | A window titled **Merge or Split Households** opens on the **Merge** tab with **Pick a household to see the two side by side.** |
| 3 | Type `Testwell` in **Find the other household** and pick Cara's household. | The comparison shows **Field**, **This Household**, **The Other Household**; differing values offer **Keep this one** or **Keep the other one**. **Members After the Merge** lists Ada and Ben (**From this household**) and Cara (**From the other household**). |
| 4 | Select **Merge**. | A dialog headed **This Cannot Be Undone** says Cara's household will be combined into this one. |
| 5 | Select **Cancel**. | Nothing changes: both households still exist with their members. |
| 6 | Select **Merge**, then **Merge Households**. | Toast **Merged. The household you kept now holds everyone from both.** The window closes and the page refreshes: Member Count **3**, Cara in **Members**. Cara's old household no longer exists. |
| 7 | Type `Bayview` in **Find the other household**. | **No households match what you typed.** Organizations are never offered. |

**Cleanup:** keep the merged household for T-HH-08.

## T-HH-08: Split and Reverse a Split

**Purpose:** split moves people to a new household, and a second split to an existing household reverses it.
**Prerequisites:** admin, The Testwell Family with Ada, Ben and Cara.

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **Merge or Split**, then the **Split** tab. | **Choose Who Moves Out** lists the three members; **Split** is disabled until someone is ticked. |
| 2 | Tick Cara, leave **A new household**, and select **Split**. | A dialog headed **Split this household?** opens. |
| 3 | Select **Split** in the dialog. | Toast **Moved. Both household names and member counts are up to date.** Cara's new household **The Testwell Family** has Member Count **1**; the original has **2**. |
| 4 | Undo: on Cara's new household, **Merge or Split**, **Split**, tick Cara, choose **An existing household**, search `Testwell`, pick the original, and split. | Cara is back in the original (Member Count **3**). Her emptied household remains with Member Count **0** and keeps its name, because **Delete a household once it is empty** ships off. |

**Cleanup:** delete the empty household.

## T-HH-09: Household Settings

**Purpose:** delete-empty and the way-of-belonging guard work from the console.
**Prerequisites:** admin, sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | In an org without Person Accounts that has not changed it, open **BarnCRM Settings**, **People and Households**, and read **How people belong to a household** without touching it. | **One household per person (simple)** is selected, never an empty choice. (An org with Person Accounts, or one set up alongside Nonprofit Cloud, shows **A person can belong to more than one household (flexible)** instead.) |
| 2 | Switch **How people belong to a household** to the other way and save. | Refused with a message starting **You cannot switch to the flexible way of belonging yet.** (or **...to the simple way...**) naming how many people it affects. The setting is unchanged. |
| 3 | Tick **Delete a household once it is empty** and save. | Saved. |
| 4 | Create contact `Dee` `Testempty`, then move Dee into The Testwell Family with **Move to Another Household**. | Dee's own household is deleted (it is gone from the **Households** tab). |
| 5 | Untick **Delete a household once it is empty** and save. | Saved. |

**Cleanup:** delete Dee Testempty.

## T-HH-10: Read-Only User on People and Households

**Purpose:** a read-only user sees households but cannot change BarnCRM membership or settings.
**Prerequisites:** read-only user, with the Salesforce **Read Only** profile as [Before you test](before-you-test.md#test-users) says (a profile that can edit accounts and contacts would show the buttons below).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Households** tab and The Garcia Family. | The **Members** panel and **Name and Greetings** show. |
| 2 | Look at the **Members** panel, in either way of belonging. | The members and their badges show. There is no **Add Member** button and no menu on the member tiles. |
| 3 | Open the **Household Members** tab (from the navigation menu if it is not shown). | It opens and lists membership records (none in the simple way of belonging); no **New** button. |
| 4 | Open **BarnCRM Settings**, **People and Households**. | The settings show and cannot be saved; the naming panel shows the read-only notice from T-HH-06. |

**Cleanup:** None.

## T-HH-11: Preferred Phone

**Purpose:** Preferred Phone copies the chosen number into Phone and refuses an empty choice.
**Prerequisites:** admin; **Copy preferred phone on a person** on (Automation page, ships on). Home Phone, Mobile, Other Phone, Work Phone and Preferred Phone are in the person page's **Reaching This Person** section.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Ada Testwell enter Home Phone `555-0101`, Mobile `555-0102`, leave Preferred Phone empty, and save. | Phone is unchanged. |
| 2 | Set **Preferred Phone** to **Mobile** and save. | Phone reads **555-0102**. |
| 3 | Set **Preferred Phone** to **Work** and **Work Phone** to `555-0103`, and save. | Phone reads **555-0103**. |
| 4 | Set **Preferred Phone** to **Other** with Other Phone empty, and save. | Refused: **The Other phone number is empty, so there is nothing to put in the ordinary Phone box. Type that number in, or choose a different preferred phone.** |
| 5 | Undo: clear Preferred Phone, type `555-0199` in Phone, and save. | Phone keeps **555-0199**. |

**Cleanup:** None.

## T-HH-12: Log an Interaction

**Purpose:** Log an interaction saves a completed activity on the person and the household.
**Prerequisites:** staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Harper Garcia and select **Log an Interaction**. | A window opens with Subject, the date (defaults to today), Type (**Meeting**), Name, Assigned To and Comments. |
| 2 | Enter Subject `Coffee test`, change the date to last Friday, and save. | The note appears under past activity on Harper, dated last Friday, completed. |
| 3 | Clear Subject and try to save a second note. | The window refuses the save until Subject is filled. |
| 4 | Open The Garcia Family and select **Log an Interaction**, choose **Luis Garcia** in Name, and save. | The note shows on the household and on Luis. |

**Cleanup:** delete both notes.

## T-HH-13: Record Pages by Record Type

**Purpose:** the shipped pages show the right sections and actions per record.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open The Garcia Family. | Sections **Details** and **Name and Greetings**; panels **Members** and **Addresses**; actions **Edit**, **Log an Interaction**, **Merge or Split**, **Delete**. |
| 2 | Open **Bayview Hardware** from **Organizations**. | **Details** with Website; **Affiliations** and **Addresses** panels; no **Name and Greetings**, no **Members**, no **Merge or Split**. |
| 3 | Open Harper Garcia. | Sections **Person**, **Household**, **Reaching This Person**; panels **Household**, **Relationships**, **Affiliations**, **Addresses**; no **Merge or Split**. |

**Cleanup:** None.

## T-HH-14: Person Account Gets a Household

**Purpose:** a person stored as an account gets a household in the flexible way.
**Prerequisites:** admin, Person Accounts org shape, flexible way, **Household of Person** added to the person account page ([Household members](../admin-guide/household-members.md)).

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a person account `Pat` `Testaccount`. | Saved. Its **Household** panel links to **The Testaccount Family**, **1 member**. |
| 2 | Open that household. | **Members** lists Pat Testaccount with **Primary**; Primary Contact names Pat. |
| 3 | In **BarnCRM Settings**, **People and Households**, try to switch to **One household per person (simple)** and save. | Refused with a message starting **You cannot switch to the simple way of belonging yet.** The setting is unchanged. |

**Cleanup:** delete Pat Testaccount and the household.

## T-HH-15: Staff Merge Households Without Delete on Account

**Purpose:** a Team Member who cannot delete accounts can still merge two households they can edit, and cannot merge one they cannot edit.
**Prerequisites:** admin; a second user `Merge Tester` on the **Minimum Access - Salesforce** profile (the Standard User profile gives Delete on Account, which would hide the problem), given the **Team Member** role on **BarnCRM Settings**, **Access**. Two households `The Mergetest Family`, each created by admin by adding one contact (Maria Mergetest and Wei Mergetest, each in their own household) and then given to Merge Tester with **Change Owner**, and a third household `The Otherowner Family` owned by admin that Merge Tester can read but not edit (only in an org whose account sharing is Private or Public Read Only).

| Step | Action | Expected result |
|---|---|---|
| 1 | Log in as Merge Tester. Open the first Mergetest household and select **Merge or Split**. | The **Merge** tab opens. There is no notice that changes are switched off. |
| 2 | Pick the second Mergetest household, select **Merge**, then **Merge Households**. | Toast **Merged. The household you kept now holds everyone from both.** The other household no longer exists, and both Maria and Wei are members of the kept one. |
| 3 | On the kept household, select **Merge or Split** and pick The Otherowner Family, then **Merge**, **Merge Households**. | Refused with **You need edit access to both households to merge them.** Both households are unchanged. |

**Cleanup:** as admin, delete the Mergetest household and The Otherowner Family.

## T-HH-17: A Person in a Household Is Not Pointed at an Organization

**Purpose:** in the simple way of belonging, changing a household member's Account Name to an organization is refused, while a person already at an organization can still be moved between organizations.
**Prerequisites:** admin, the simple way of belonging. Two organizations (of the record type chosen in **Record type for organizations**) `Zztest Library` and `Zztest Trust`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact `Hana` `Hhsixteen` with **Account Name** blank. | Saved, in **The Hhsixteen Family**. |
| 2 | Edit Hana, set **Account Name** to Zztest Library, and save. | Refused with **This person is in a household, so Account Name must stay a household, not an organization. To connect them to an organization, add an affiliation. To move them, use Move to another household.** Hana is still in The Hhsixteen Family. |
| 3 | Create a contact `Omar` `Hhsixteen` with **Account Name** Zztest Library. | Saved at Zztest Library, with no household. |
| 4 | Edit Omar, set **Account Name** to Zztest Trust, and save. | Saved: Omar was not in a household. |

**Cleanup:** delete Hana, Omar, The Hhsixteen Family and both organizations.

## T-HH-16: A Blocking Account Duplicate Rule Does Not Stop a New Person

**Purpose:** households BarnCRM creates are saved past the org's Account duplicate rules, so adding a person never fails over a look-alike household.
**Prerequisites:** admin; in Setup, an active Account duplicate rule on the standard account matching rule with **Action On Create** set to **Block**. Contact `Ana Duptest` already saved, with her household **The Duptest Family**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact `Luis` `Duptest`, leaving the account empty. | Saved. Luis has a household of his own, also named **The Duptest Family**. |
| 2 | In Setup, try to create an account named **The Duptest Family** by hand. | Your duplicate rule blocks it, as before. |

**Cleanup:** delete both contacts and their households, then deactivate the duplicate rule.

## T-HH-18: Households Tab Only While Household Upkeep Is On, Household Record Type Never Offered

**Purpose:** no install adds a record type anyone can pick; turning Household Upkeep on shows the Households tab to BarnCRM role holders, and households are still made only by BarnCRM.
**Prerequisites:** a fresh scratch org of the Platform-only shape (no Account record types) with Core deployed and first-run setup not finished; a staff user with the Staff role.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user, open the **BarnCRM** app. | No **Households** tab. |
| 2 | As the staff user, open Accounts and click **New**. | No record type choice; the new account form opens straight away. |
| 3 | As admin, in Setup, open Object Manager, Account, Record Types. | **Household** is listed and active. No **Organization** record type. |
| 4 | As admin, finish first-run setup with **Household Upkeep** ticked (or choose **Turn On** in its row on **General**). | The confirmation says Household Upkeep adds the Households tab and that households are created with **New Household** on BarnCRM Home, not the standard **New** button. |
| 5 | Wait a few minutes. As the staff user, reload the **BarnCRM** app. | The **Households** tab is there. |
| 6 | As the staff user, open Accounts and click **New**. | Still no record type choice and no **Household**; the account saves with no record type and appears on **Organizations**, not **Households**. |
| 7 | As the staff user, click **New Household** on BarnCRM Home, save, then edit the household's phone and save. | The household is created and appears on the **Households** tab; the edit saves. |
| 8 | As the staff user, edit the account from step 6 and try to change its record type. | **Household** is not offered (Change Record Type shows no choice, or is not offered). |
| 9 | As the staff user, open the household from step 7. On **Members** select **Add Member**, add `Zztest` `Rt`, then open the household's **Addresses** card. | Before the add the panel shows **No Members Yet**; the **Add Member** dialog opens and the new person shows as a tile. **Addresses** shows **No Addresses Yet** with **Add Address**. Nothing asks for a record type. |
| 10 | As admin, in Setup, open the staff user's permission set assignments, then the **BarnCRM Households** permission set's record type settings. | **BarnCRM Households** is assigned; it grants no record type. |
| 11 | In an org that already ran BarnCRM before this change, deploy it, then as admin open **BarnCRM Staff** and its record type settings. | **Household** is no longer listed; staff can still open and edit existing households. |

**Cleanup:** none (Household Upkeep cannot be turned off).

## T-HH-19: Record Type for Organizations Is Detected and Can Be Changed

**Purpose:** BarnCRM picks the org's own record type for organizations and never adds one.
**Prerequisites:** admin. Run once in a Person Accounts org (it has **Business Account**) and once in a Platform-only org.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **General**. | **Record type for organizations** shows **Business Account** in the Person Accounts org and **No record type** in the Platform-only org; never blank. |
| 2 | Open the dropdown. | In the Person Accounts org it lists the org's active Account record types and no **No record type**; in the Platform-only org it lists only **No record type**. Never **Household** or a person account record type. |
| 3 | Open the **Organizations** tab. | Accounts of the chosen record type are listed; households and person accounts are not. |
| 4 | Open one of those organizations. | The **Affiliations** panel and the website show; no **Name and Greetings**, no **Members**, no **Erase Person**. |
| 5 | Import a file with one person and the organization `Zztest Rt Org`. | `Zztest Rt Org` is created with the chosen record type (or none, for **No record type**) and appears on the **Organizations** tab. |
| 6 | In an org with a second business record type, choose it in the setting and save. | Saved, and listed in **Recent Changes**. The **Organizations** tab now lists accounts of that record type instead. Open one: **Is Organization** is checked, and the **Affiliations** panel and website show, with Giving and Volunteers the organization sections too; an account of the first record type now shows **Is Organization** unchecked. |
| 7 | With that record type still chosen, import a file with one person and the organization `Zztest Rt Org 2`, give an organization an address in its billing fields, and load sample data in a sandbox without it. | `Zztest Rt Org 2` is created with that record type; the organization with the billing address gets a first address of type **Work**; sample data's organizations get that record type and the sample data count lists them. |
| 8 | As a user whose profile and permission sets do not give that record type, import a file with two people: one at `Zztest Rt Org 2` (now in Salesforce) and one at the new organization `Zztest Rt Org 3`. | The first row loads, linked to `Zztest Rt Org 2`. The second is rejected with **This row's organization is not in Salesforce yet, and you cannot use the ... record type**, naming it by its label; the run log says no new organization was created for the same reason. `Zztest Rt Org 3` is not created. |

**Cleanup:** set the setting back to its first value; delete `Zztest Rt Org` and the imported person.

## T-HH-20: An Org Already Running BarnCRM Keeps Its Organizations

**Purpose:** after BarnCRM stops shipping its Organization record type, an org that ran an earlier version keeps its organizations once **Record type for organizations** is set.
**Prerequisites:** admin; an org deployed before this change, with organizations and households (for example a test org with sample data).

| Step | Action | Expected result |
|---|---|---|
| 1 | Before the deploy, open the **Organizations** tab and note how many records it lists. | A count to compare. |
| 2 | Deploy this version. Open **BarnCRM Settings**, **General**. | **Record type for organizations** shows a record type, never blank. **No record type** is offered only when the org has no Account record type besides Household and person account ones. |
| 3 | Set **Record type for organizations** to the record type your organizations use and save. | Saved, and listed in **Recent Changes**. |
| 4 | Open the **Organizations** tab and the **Households** tab. | The Organizations tab lists the same records as in step 1; the Households tab lists the same records as before. |
| 5 | As a staff user, open a household and an organization. | The same sections and panels as before (T-HH-13): the organization shows **Is Organization** checked, with the **Affiliations** panel. |
| 6 | If step 3 kept **Organization**: before giving it to your profile, run **Health Check**, then load sample data. Then give **Organization** to your profile (Setup, Profiles, Record Type Settings) and run Health Check again. | Before: Health Check warns **You cannot use the record type for organizations**, naming Organization, and **Load Sample Data** refuses with a message naming it. After: no such warning. |
| 7 | If step 3 chose another record type: move any accounts still on **Organization** to it, then in Setup, Object Manager, Account, Record Types, deactivate **Organization**. Reopen **BarnCRM Settings**, **General**. | **Record type for organizations** still shows your choice, and Organization is no longer among its choices. The Organizations tab lists the same records as in step 1. |

**Cleanup:** none.
