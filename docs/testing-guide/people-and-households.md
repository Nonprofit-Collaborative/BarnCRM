# People and households

Scripts for people, households, the Members and Household panels, names and greetings, merge and split, preferred phone, interaction notes and the record pages. Setup detail: [Households](../admin-guide/households.md), [Household members](../admin-guide/household-members.md), [Household names and greetings](../admin-guide/household-naming.md), [Merging and splitting households](../admin-guide/household-merge-split.md), [Preferred phone](../admin-guide/preferred-phone.md), [Interaction notes](../admin-guide/interaction-notes.md), [Record pages](../admin-guide/record-pages.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. The **Household upkeep** and **Preferred email and phone** features must be on (BarnCRM Settings, **General**). Open every record from the **BarnCRM** app. Check which way of belonging the org uses (BarnCRM Settings, **Households**, **How people belong to a household**): **One household per person (simple)** or **A person can belong to more than one household (flexible)**. Steps that differ between the two say so. The sample people are contacts in both org shapes.

## T-HH-01: A new person gets a household

**Purpose:** saving a person with no household creates and names one, and both panels show it.
**Prerequisites:** admin. **Create a household automatically** is on (ships on).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Contacts** tab, select **New**, enter Salutation `Ms.`, First Name `Ada`, Last Name `Testwell`, leave the account blank, and save. | The person saves. In the simple way the account field names **The Testwell Family**; in the flexible way it stays blank. |
| 2 | Look at the **Household** panel on Ada's page. | It links to **The Testwell Family**, reads **1 member**, and shows **Formal greeting: Ms. Ada Testwell**. |
| 3 | Select the household name in the panel. | The household page opens. The **Members** panel lists Ada Testwell with a **Primary** badge. **Name and Greetings** shows Formal Greeting **Ms. Ada Testwell**, Informal Greeting **Ada**, Member Count **1**, Primary Contact **Ada Testwell**. |
| 4 | Open **Home**, then select **New household**. | A new Account form opens with no record type prompt and the name **New Household** filled in. Select **Cancel**. |

**Cleanup:** keep Ada and The Testwell Family for T-HH-02 to T-HH-07.

## T-HH-02: Add member and automatic naming (simple way)

**Purpose:** Add member creates a person in the household and the name and greetings follow the members.
**Prerequisites:** admin, simple way, T-HH-01 done. Use T-HH-03 instead in the flexible way.

| Step | Action | Expected result |
|---|---|---|
| 1 | On The Testwell Family, select **Add member** in the **Members** panel. | A form opens in the panel with Salutation, First Name and Last Name, a **Save** and a **Cancel** button. |
| 2 | Enter `Mr.`, `Ben`, `Testwell` and select **Save**. | A toast reads **Added. The household name and greetings have been brought up to date.** Ben appears in the list. |
| 3 | Refresh the page. | Member Count **2**. Formal Greeting **Ms. and Mr. Ada Testwell**. Informal Greeting **Ada and Ben**. The name stays **The Testwell Family**. |
| 4 | Add a third member `Wei` `Lee` (no salutation) and refresh. | Member Count **3**. The name reads **Testwell and Lee Household** because the surnames differ. |
| 5 | On Wei's row select **Move to another household**, pick **The Garcia Family** in the picker and select **Save**. | A toast reads **Moved. Both households have been brought up to date.** Wei leaves the list; the name returns to **The Testwell Family**, Member Count **2**. |
| 6 | Reverse it: open The Garcia Family, use **Move to another household** on Wei, and choose The Testwell Family. | Wei is back in The Testwell Family; The Garcia Family is back to its three members and its own name. |

**Cleanup:** delete Wei Lee.

## T-HH-03: Add member (flexible way)

**Purpose:** in the flexible way Add member offers search and create.
**Prerequisites:** admin, flexible way, T-HH-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On The Testwell Family, select **Add member**. | The panel shows **Add someone already in Salesforce** with a search box (placeholder **Search by name**) and **Or add someone new** with Salutation, First name and Last name. |
| 2 | Type `zzqq` in the search box. | **No matches. Keep typing, or add them as a new person below.** |
| 3 | Leave Last name empty and select **Save**. | **Enter at least a last name before saving.** Nothing is created. |
| 4 | Enter `Mr.`, `Ben`, `Testwell` and select **Save**. | A toast confirms the add; Ben is listed; after refresh Member Count is **2** and Informal Greeting **Ada and Ben**. |
| 5 | Open **Add member** again, search `Diego`, and select **Diego Garcia**. | Diego joins The Testwell Family and stays in The Garcia Family. His **Household** panel lists both households. |
| 6 | Open the **Household Members** tab, open Diego's new membership, set **End Date** to yesterday, and save. | Diego disappears from The Testwell Family's panel and its Member Count drops by one. The Garcia Family is unchanged. |
| 7 | Create a second current membership for Ben in The Testwell Family from the **Household Members** tab. | Refused: **This person is already a current member of this household. Edit their existing membership instead of adding another.** |

**Cleanup:** delete Diego's ended membership record.

## T-HH-04: Make primary

**Purpose:** Make primary moves the primary contact and the Primary Contact field follows.
**Prerequisites:** admin, The Testwell Family with Ada and Ben.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Ben's row select **Make primary**. | A toast reads **Ben Testwell is now the primary contact.** The **Primary** badge moves to Ben; **Make primary** now shows on Ada's row and not on Ben's. |
| 2 | Refresh. | Primary Contact reads **Ben Testwell**. |
| 3 | Simple way: edit the household and set Primary Contact to **Harper Garcia**. | Refused: **The Primary Contact has to be somebody in this household. Choose one of its members, or move the person into the household first.** |
| 4 | Flexible way: edit the household and change Primary Contact to Ada. | Refused with a message starting **In this org a household's Primary Contact follows the member marked primary.** |
| 5 | Select **Make primary** on Ada to put it back. | Badge and Primary Contact return to Ada. |

**Cleanup:** None.

## T-HH-05: Greetings: deceased, preferred name, exclusions, custom name

**Purpose:** person-level boxes change the greetings and Custom Name locks them.
**Prerequisites:** admin, The Testwell Family with Ada and Ben, **Include people who have died in names** off (ships off).

| Step | Action | Expected result |
|---|---|---|
| 1 | On Ben, set **Preferred Name** to `Benji` and save. Refresh the household. | Informal Greeting **Ada and Benji**. Formal Greeting still **Ms. and Mr. Ada Testwell**. |
| 2 | On Ben, tick **Exclude From Greetings** and save. Refresh the household. | Informal Greeting **Ada**, Formal Greeting **Ms. Ada Testwell**. Member Count still **2**. |
| 3 | Untick it, tick **Deceased** on Ben, and save. Refresh the household. | Greetings leave Ben out. His row in **Members** carries a **Deceased** badge. |
| 4 | Untick **Deceased**. On the household tick **Custom Name**, set the name to `The Testwell Household (custom)`, and save. | The name saves as typed. |
| 5 | Add a member `Cy` `Testwell` and refresh. | Name and greetings are unchanged; Member Count goes up. |
| 6 | Untick **Custom Name** and save. | The name is recalculated at once to **The Testwell Family** and the greetings include Cy. |

**Cleanup:** delete Cy Testwell; clear Ben's Preferred Name.

## T-HH-06: Naming patterns, preview and recompute

**Purpose:** the naming panel previews, saves and recomputes, and is read only without the permission.
**Prerequisites:** admin; read-only user for step 6.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Households**. | The **Household names and greetings** panel shows **Household name pattern**, **Formal greeting pattern**, **Informal greeting pattern**, and **How five sample households would read**. |
| 2 | Change **Household name pattern** to `{LastName} Household`. | The preview updates as you type. |
| 3 | Select **Save**. | **Saved. New households use these patterns straight away.** |
| 4 | Select **Update all household names**, then **Yes, recompute** in the dialog. | **Updating household names in the background.** After a few minutes The Garcia Family reads **Garcia Household**; the **Staff Household** (Custom Name) is unchanged. |
| 5 | Put the pattern back to `The {LastName} Family`, save, and recompute again. | Names return to **The Garcia Family** form. |
| 6 | As read-only, open the same panel. | **You can see these settings but not change them. Changing them needs the Manage BarnCRM Settings permission.** The patterns cannot be saved. |

**Cleanup:** pattern back to `The {LastName} Family`.

## T-HH-07: Merge two households (with cancel)

**Purpose:** merge combines two households after a warning, and cancel leaves both untouched.
**Prerequisites:** admin (staff also passes), The Testwell Family with Ada and Ben.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a contact `Cara` `Testwell` with no account. | A second household named **The Testwell Family** is created for her. |
| 2 | Open the first Testwell household (Ada's) and select **Merge or split** in the action bar. | A window titled **Merge or split households** opens on the **Merge** tab with **Pick a household to see the two side by side.** |
| 3 | Type `Testwell` in **Find the other household** and pick Cara's household. | The comparison shows **Field**, **This household**, **The other household**; differing values offer **Keep this one** or **Keep the other one**. **Members after the merge** lists Ada and Ben (**From this household**) and Cara (**From the other household**). |
| 4 | Select **Merge**. | A dialog headed **This cannot be undone** says Cara's household will be combined into this one. |
| 5 | Select **Cancel**. | Nothing changes: both households still exist with their members. |
| 6 | Select **Merge**, then **Merge households**. | Toast **Merged. The household you kept now holds everyone from both.** The window closes and the page refreshes: Member Count **3**, Cara in **Members**. Cara's old household no longer exists. |
| 7 | Type `Bayview` in **Find the other household**. | **No households match what you typed.** Organizations are never offered. |

**Cleanup:** keep the merged household for T-HH-08.

## T-HH-08: Split and reverse a split

**Purpose:** split moves people to a new household, and a second split to an existing household reverses it.
**Prerequisites:** admin, The Testwell Family with Ada, Ben and Cara.

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **Merge or split**, then the **Split** tab. | **Choose who moves out** lists the three members; **Split** is disabled until someone is ticked. |
| 2 | Tick Cara, leave **A new household**, and select **Split**. | A dialog headed **Split this household?** opens. |
| 3 | Select **Split** in the dialog. | Toast **Moved. Both household names and member counts are up to date.** Cara's new household **The Testwell Family** has Member Count **1**; the original has **2**. |
| 4 | Undo: on Cara's new household, **Merge or split**, **Split**, tick Cara, choose **An existing household**, search `Testwell`, pick the original, and split. | Cara is back in the original (Member Count **3**). Her emptied household remains with Member Count **0** and keeps its name, because **Delete a household once it is empty** ships off. |

**Cleanup:** delete the empty household.

## T-HH-09: Household settings

**Purpose:** delete-empty and the way-of-belonging guard work from the console.
**Prerequisites:** admin, sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Households**, switch **How people belong to a household** to the other way and save. | Refused with a message starting **You cannot switch to the flexible way of belonging yet.** (or **...to the simple way...**) naming how many people it affects. The setting is unchanged. |
| 2 | Tick **Delete a household once it is empty** and save. | Saved. |
| 3 | Create contact `Dee` `Testempty`, then move Dee into The Testwell Family with **Move to another household**. | Dee's own household is deleted (it is gone from the **Households** tab). |
| 4 | Untick **Delete a household once it is empty** and save. | Saved. |

**Cleanup:** delete Dee Testempty.

## T-HH-10: Read-only user on people and households

**Purpose:** a read-only user sees households but cannot change BarnCRM membership or settings.
**Prerequisites:** read-only user. The test users have the **Standard User** profile, which itself allows editing accounts and contacts, so this script checks what BarnCRM controls.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Households** tab and The Garcia Family. | The **Members** panel and **Name and Greetings** show. |
| 2 | Flexible way only: select **Make primary** on a member. | **The primary contact could not be changed. Check that you can edit this household and try again.** The badge does not move. |
| 3 | Open **BarnCRM Settings**, **Households**. | The settings show and cannot be saved; the naming panel shows the read-only notice from T-HH-06. |

**Cleanup:** None.

## T-HH-11: Preferred phone

**Purpose:** Preferred Phone copies the chosen number into Phone and refuses an empty choice.
**Prerequisites:** admin; **Copy preferred phone on a person** on (Automation page, ships on). Home Phone, Mobile and Other Phone are not on the shipped person page: add them to the **Reaching This Person** section first (gear icon, **Edit Page**).

| Step | Action | Expected result |
|---|---|---|
| 1 | On Ada Testwell enter Home Phone `555-0101`, Mobile `555-0102`, leave Preferred Phone empty, and save. | Phone is unchanged. |
| 2 | Set **Preferred Phone** to **Mobile** and save. | Phone reads **555-0102**. |
| 3 | Set **Preferred Phone** to **Work** and **Work Phone** to `555-0103`, and save. | Phone reads **555-0103**. |
| 4 | Set **Preferred Phone** to **Other** with Other Phone empty, and save. | Refused: **The Other phone number is empty, so there is nothing to put in the ordinary Phone box. Type that number in, or choose a different preferred phone.** |
| 5 | Undo: clear Preferred Phone, type `555-0199` in Phone, and save. | Phone keeps **555-0199**. |

**Cleanup:** None.

## T-HH-12: Log an interaction

**Purpose:** Log an interaction saves a completed activity on the person and the household.
**Prerequisites:** staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Harper Garcia and select **Log an interaction**. | A window opens with Subject, the date (defaults to today), Type (**Meeting**), Name, Assigned To and Comments. |
| 2 | Enter Subject `Coffee test`, change the date to last Friday, and save. | The note appears under past activity on Harper, dated last Friday, completed. |
| 3 | Clear Subject and try to save a second note. | The window refuses the save until Subject is filled. |
| 4 | Open The Garcia Family and select **Log an interaction**, choose **Luis Garcia** in Name, and save. | The note shows on the household and on Luis. |

**Cleanup:** delete both notes.

## T-HH-13: Record pages by record type

**Purpose:** the shipped pages show the right sections and actions per record.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open The Garcia Family. | Sections **Details** and **Name and Greetings**; panels **Members** and **Addresses**; actions **Edit**, **Log an interaction**, **Merge or split**, **Delete**. |
| 2 | Open **Bayview Hardware** from **Organizations**. | **Details** with Website; **Affiliations** and **Addresses** panels; no **Name and Greetings**, no **Members**, no **Merge or split**. |
| 3 | Open Harper Garcia. | Sections **Person**, **Household**, **Reaching This Person**; panels **Household**, **Relationships**, **Affiliations**, **Addresses**; no **Merge or split**. |

**Cleanup:** None.

## T-HH-14: Person account gets a household

**Purpose:** a person stored as an account gets a household in the flexible way.
**Prerequisites:** admin, Person Accounts org shape, flexible way, **Household of Person** added to the person account page ([Household members](../admin-guide/household-members.md)).

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a person account `Pat` `Testaccount`. | Saved. Its **Household** panel links to **The Testaccount Family**, **1 member**. |
| 2 | Open that household. | **Members** lists Pat Testaccount with **Primary**; Primary Contact names Pat. |
| 3 | In **BarnCRM Settings**, **Households**, try to switch to **One household per person (simple)** and save. | Refused with a message starting **You cannot switch to the simple way of belonging yet.** The setting is unchanged. |

**Cleanup:** delete Pat Testaccount and the household.
