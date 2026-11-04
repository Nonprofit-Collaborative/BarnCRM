# Relationships and Affiliations

Scripts for person-to-person relationships with their automatic other side, and person-to-organization affiliations with one primary. Setup detail: [Relationships](../admin-guide/relationships.md), [Affiliations](../admin-guide/affiliations.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest. The affiliation scripts name two sample organizations, **Bayview Hardware** and **Heritage Rotary Club**: create two organizations (the record type in **Record type for organizations**) named `Zztest Bayview Hardware` and `Zztest Heritage Rotary Club` and read the sample names as those. The **Relationships** and **Affiliations** features must be on (BarnCRM Settings, **General**). The sample Garcia family (Harper, Luis, Diego) has no relationships or affiliations; **Bayview Hardware** and **Heritage Rotary Club** are sample organizations.

## T-REL-01: Add a Relationship and Get the Other Side

**Purpose:** a relationship entered on one person appears on the other with the matching type.
**Prerequisites:** staff user. **Keep both sides of relationships in step** on (ships on).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Harper Garcia**. | The **Relationships** card shows **No Relationships Yet** with an **Add Relationship** button. |
| 2 | Select **Add Relationship**. | A **New Relationship** form opens with Related Person, Type, Status, Start Date, End Date and Description. |
| 3 | Choose Related Person **Luis Garcia**, Type **Spouse**, leave Status **Current**, and select **Add Relationship** in the form. | Toast **Relationship saved, and the other person's record now shows it too.** The card shows **Luis Garcia**, **Spouse**, with no badge. |
| 4 | Open **Luis Garcia**. | His card shows **Harper Garcia**, **Spouse**. |
| 5 | On Harper, add Related Person **Diego Garcia**, Type **Child**. | Harper's card shows **Diego Garcia**, **Child**. |
| 6 | Open **Diego Garcia**. | His card shows **Harper Garcia**, **Parent**. |
| 7 | Open the **Households** tab and The Garcia Family. | Members and household are unchanged. |

**Cleanup:** keep both relationships for T-REL-02 to T-REL-04.

## T-REL-02: End a Relationship on One Side

**Purpose:** an end date makes both sides Former.
**Prerequisites:** staff user, T-REL-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Relationships** tab, open Harper's relationship to Luis, select **Edit**, set **End Date** to last month, and save. | Status reads **Former**. |
| 2 | Open Harper. | The Luis line carries a **Former** badge. |
| 3 | Open Luis. | The Harper line carries **Former**; his record has the same End Date. |
| 4 | Undo: clear **End Date** on either side and save. | Both sides return to **Current** and the badges disappear. |

**Cleanup:** None.

## T-REL-03: Duplicate and Self Relationships Are Refused

**Purpose:** the checks stop a second copy and a relationship with oneself.
**Prerequisites:** staff user, T-REL-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Luis, **Add Relationship**: Related Person **Harper Garcia**, Type **Spouse**. Submit with **Add Relationship** in the form. | Refused: **Luis Garcia already has this relationship with Harper Garcia. Open RL-** followed by the record number **to change it.** |
| 2 | On Luis, **Add Relationship**: Related Person **Luis Garcia**, any type. Submit with **Add Relationship** in the form. | Refused: **A relationship needs two different people.** |
| 3 | On the **Relationships** tab select **New** and save with only a Type. | Refused: **A relationship needs a person on each side.** |

**Cleanup:** None.

## T-REL-04: Remove a Relationship and Restore It

**Purpose:** Remove deletes both sides, and restoring one side brings both back.
**Prerequisites:** staff user, T-REL-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Harper's card select **Remove** on the Luis line. | No confirmation. Toast **Relationship removed from both people.** The line is gone. |
| 2 | Open Luis. | The Harper line is gone. |
| 3 | Undo: open the **Recycle Bin**, find the Harper to Luis relationship, and restore it. | Restored. |
| 4 | Open Harper and Luis. | Both cards show the Spouse line again, once each. |

**Cleanup:** None.

## T-REL-05: Keep Both Sides in Step Switched Off

**Purpose:** with upkeep off only the entered side is written, and the checks still run.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **People and Households**, **Relationships** box, untick **Keep both sides of relationships in step** and save. | Saved. |
| 2 | On Luis, add Related Person **Diego Garcia**, Type **Child**. | Luis shows Diego, Child. Diego's card does not show Luis. |
| 3 | On Luis, add the same relationship again. | Still refused as a duplicate (T-REL-03). |
| 4 | Turn the setting back on and save. Open Luis's relationship to Diego on the **Relationships** tab, select **Edit**, and save without changes. | Diego's card now shows **Luis Garcia**, **Parent**. |
| 5 | Open that relationship and untick **Keep Both Sides In Step**, set an End Date, and save. | Only Luis's side turns **Former**. |

**Cleanup:** delete the Luis to Diego relationship on both sides.

## T-REL-06: Read-Only User on Relationships

**Purpose:** a read-only user sees relationships and cannot add or remove them.
**Prerequisites:** read-only user, T-REL-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Harper Garcia. | The **Relationships** card lists Luis and Diego. |
| 2 | Look at each line. | No line shows a **Remove** button. |
| 3 | Look at the card header. | There is no **Add Relationship** button. |

**Cleanup:** as admin, remove Harper's relationships to Luis and Diego.

## T-REL-07: Add Affiliations and Move the Primary

**Purpose:** a primary affiliation fills Primary Affiliation, and a new primary takes over.
**Prerequisites:** staff user.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Harper Garcia. | The **Affiliations** card shows **No Affiliations Yet** with an **Add Affiliation** button. |
| 2 | Select **Add Affiliation**: Organization **Bayview Hardware**, Role `Store Manager`, tick **Primary**, Start Date January 1 last year. Save with **Add Affiliation** in the form. | Toast **Affiliation saved.** The line shows Bayview Hardware, the role Store Manager, and a **Primary** badge. **Primary Affiliation** on Harper reads **Bayview Hardware**. |
| 3 | Open **Bayview Hardware** from **Organizations**. | Its **Affiliations** card shows Harper Garcia. |
| 4 | On Harper, add **Heritage Rotary Club**, Role `Club president`, tick **Primary**. | The **Primary** badge moves to Heritage Rotary Club; Bayview Hardware shows **Make Primary**. **Primary Affiliation** reads Heritage Rotary Club. |
| 5 | Select **Make Primary** on Bayview Hardware. | Toast **Primary affiliation updated.** The badge and **Primary Affiliation** move back to Bayview Hardware. |
| 6 | Open The Garcia Family. | Harper is still a member. |

**Cleanup:** keep both affiliations for T-REL-08.

## T-REL-08: End an Affiliation and Overlap Checks

**Purpose:** ending the primary clears it, and overlapping or incomplete affiliations are refused.
**Prerequisites:** staff user, T-REL-07 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Affiliations** tab, edit Harper's Bayview Hardware affiliation, set End Date to last month, and save. | Status reads **Former**. On Harper the line carries **Former**, no **Primary**, and **Primary Affiliation** is empty. |
| 2 | Select **Make Primary** on Heritage Rotary Club. | **Primary Affiliation** reads Heritage Rotary Club. |
| 3 | On Harper, add Heritage Rotary Club again with Role `Club president` and no dates. | Refused: **Harper Garcia already has an affiliation with Heritage Rotary Club as Club president covering those dates. Open AF-** followed by the record number **to change it.** |
| 4 | On the **Affiliations** tab select **New**, choose Person **Harper Garcia**, leave Organization empty, and save. | Refused: **An affiliation needs an organization.** |

**Cleanup:** delete Harper's two affiliations.

## T-REL-09: Affiliations From the Organization, and Read-Only

**Purpose:** an affiliation can be added from the organization page, and a read-only user cannot change one.
**Prerequisites:** staff user, then read-only user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Bayview Hardware** and select **Add Affiliation**. | The form asks for the person (Person) instead of the organization. |
| 2 | Choose **Luis Garcia**, Role `Customer`, and save. | The line shows Luis Garcia. Luis's own **Affiliations** card shows Bayview Hardware. |
| 3 | As read-only, open Luis and look at the Bayview Hardware line (Primary was not ticked). | The line shows, with no **Make Primary** button. |
| 4 | As read-only, look at the **Affiliations** card header. | There is no **Add Affiliation** button. |

**Cleanup:** as admin, delete Luis's Bayview Hardware affiliation.

## T-REL-10: List Views and Ready-to-Use Types on a Fresh Org

**Purpose:** Relationships and Affiliations open with useful list views, and a new org can add a relationship without any sample data.
**Prerequisites:** staff user, **Relationships** and **Affiliations** on. Best run on an org with no sample data loaded; on an org with sample data the lists also hold sample rows.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Relationships** tab and open the list view menu. | The views **All Relationships**, **Current Relationships**, **Former Relationships** and **My Relationships** are listed, besides Recently Viewed. |
| 2 | Choose **All Relationships**. | The list opens with columns for the person, Type, the related person and Status. On a fresh org it is empty. |
| 3 | Open the **Affiliations** tab and open the list view menu. | The views **All Affiliations**, **Current Affiliations**, **Former Affiliations** and **My Affiliations** are listed. |
| 4 | Open any person, select **Add Relationship** and open the **Type** list. | The 11 shipped types are there: Spouse, Partner, Parent, Child, Sibling, Grandparent, Grandchild, Friend, Colleague, Employer contact and Other. Nothing had to be set up first. |
| 5 | Add a relationship of Type **Friend**, then return to **Current Relationships** and **My Relationships**. | Both sides of the relationship show in **Current Relationships** and in **My Relationships**. **Former Relationships** is empty. |
| 6 | Set an end date on one side (see T-REL-02) and refresh **Former Relationships**. | Both sides now show there, with the end date, and have left **Current Relationships**. |
| 7 | Add an affiliation (see T-REL-07) and check **Current Affiliations**, then end it and check **Former Affiliations**. | The affiliation moves from **Current Affiliations** to **Former Affiliations**. **My Affiliations** shows it throughout. |

**Cleanup:** delete the relationships and affiliations you added.
