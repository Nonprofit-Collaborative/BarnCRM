# Relationships and affiliations

Scripts for person-to-person relationships with their automatic other side, and person-to-organization affiliations with one primary. Setup detail: [Relationships](../admin-guide/relationships.md), [Affiliations](../admin-guide/affiliations.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. The **Relationships** and **Affiliations** features must be on (BarnCRM Settings, **General**). The sample Garcia family (Harper, Luis, Diego) has no relationships or affiliations; **Bayview Hardware** and **Heritage Rotary Club** are sample organizations.

## T-REL-01: Add a relationship and get the other side

**Purpose:** a relationship entered on one person appears on the other with the matching type.
**Prerequisites:** staff user. **Keep both sides of relationships in step** on (ships on).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Harper Garcia**. | The **Relationships** card reads **No relationships on file yet.** |
| 2 | Select **Add relationship**. | A **New relationship** form opens with Related Person, Type, Status, Start Date, End Date and Description. |
| 3 | Choose Related Person **Luis Garcia**, Type **Spouse**, leave Status **Current**, and select **Add relationship** in the form. | Toast **Relationship saved, and the other person's record now shows it too.** The card shows **Luis Garcia**, **Spouse**, with no badge. |
| 4 | Open **Luis Garcia**. | His card shows **Harper Garcia**, **Spouse**. |
| 5 | On Harper, add Related Person **Diego Garcia**, Type **Child**. | Harper's card shows **Diego Garcia**, **Child**. |
| 6 | Open **Diego Garcia**. | His card shows **Harper Garcia**, **Parent**. |
| 7 | Open the **Households** tab and The Garcia Family. | Members and household are unchanged. |

**Cleanup:** keep both relationships for T-REL-02 to T-REL-04.

## T-REL-02: End a relationship on one side

**Purpose:** an end date makes both sides Former.
**Prerequisites:** staff user, T-REL-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Relationships** tab, open Harper's relationship to Luis, select **Edit**, set **End Date** to last month, and save. | Status reads **Former**. |
| 2 | Open Harper. | The Luis line carries a **Former** badge. |
| 3 | Open Luis. | The Harper line carries **Former**; his record has the same End Date. |
| 4 | Undo: clear **End Date** on either side and save. | Both sides return to **Current** and the badges disappear. |

**Cleanup:** None.

## T-REL-03: Duplicate and self relationships are refused

**Purpose:** the checks stop a second copy and a relationship with oneself.
**Prerequisites:** staff user, T-REL-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Luis, **Add relationship**: Related Person **Harper Garcia**, Type **Spouse**. Submit with **Add relationship** in the form. | Refused: **Luis Garcia already has this relationship with Harper Garcia. Open RL-** followed by the record number **to change it.** |
| 2 | On Luis, **Add relationship**: Related Person **Luis Garcia**, any type. Submit with **Add relationship** in the form. | Refused: **A relationship needs two different people.** |
| 3 | On the **Relationships** tab select **New** and save with only a Type. | Refused: **A relationship needs a person on each side.** |

**Cleanup:** None.

## T-REL-04: Remove a relationship and restore it

**Purpose:** Remove deletes both sides, and restoring one side brings both back.
**Prerequisites:** staff user, T-REL-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Harper's card select **Remove** on the Luis line. | No confirmation. Toast **Relationship removed from both people.** The line is gone. |
| 2 | Open Luis. | The Harper line is gone. |
| 3 | Undo: open the **Recycle Bin**, find the Harper to Luis relationship, and restore it. | Restored. |
| 4 | Open Harper and Luis. | Both cards show the Spouse line again, once each. |

**Cleanup:** None.

## T-REL-05: Keep both sides in step switched off

**Purpose:** with upkeep off only the entered side is written, and the checks still run.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Relationships**, untick **Keep both sides of relationships in step** and save. | Saved. |
| 2 | On Luis, add Related Person **Diego Garcia**, Type **Child**. | Luis shows Diego, Child. Diego's card does not show Luis. |
| 3 | On Luis, add the same relationship again. | Still refused as a duplicate (T-REL-03). |
| 4 | Turn the setting back on and save. Open Luis's relationship to Diego on the **Relationships** tab, select **Edit**, and save without changes. | Diego's card now shows **Luis Garcia**, **Parent**. |
| 5 | Open that relationship and untick **Keep Both Sides In Step**, set an End Date, and save. | Only Luis's side turns **Former**. |

**Cleanup:** delete the Luis to Diego relationship on both sides.

## T-REL-06: Read-only user on relationships

**Purpose:** a read-only user sees relationships and cannot add or remove them.
**Prerequisites:** read-only user, T-REL-01 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Harper Garcia. | The **Relationships** card lists Luis and Diego. |
| 2 | Select **Remove** on a line. | **BarnCRM could not remove that relationship. Check that you can delete relationships, and if it happens again ask your administrator to check the Error Log.** The line stays. |
| 3 | Select **Add relationship**, fill it in, and save. | The save is refused with an error; nothing is added. |

**Cleanup:** as admin, remove Harper's relationships to Luis and Diego.

## T-REL-07: Add affiliations and move the primary

**Purpose:** a primary affiliation fills Primary Affiliation, and a new primary takes over.
**Prerequisites:** staff user.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Harper Garcia. | The **Affiliations** card reads **No affiliations on file yet.** |
| 2 | Select **Add affiliation**: Organization **Bayview Hardware**, Role `Store Manager`, tick **Primary**, Start Date January 1 last year. Save with **Add affiliation** in the form. | Toast **Affiliation saved.** The line shows Bayview Hardware, the role Store Manager, and a **Primary** badge. **Primary Affiliation** on Harper reads **Bayview Hardware**. |
| 3 | Open **Bayview Hardware** from **Organizations**. | Its **Affiliations** card shows Harper Garcia. |
| 4 | On Harper, add **Heritage Rotary Club**, Role `Club president`, tick **Primary**. | The **Primary** badge moves to Heritage Rotary Club; Bayview Hardware shows **Make primary**. **Primary Affiliation** reads Heritage Rotary Club. |
| 5 | Select **Make primary** on Bayview Hardware. | Toast **Primary affiliation updated.** The badge and **Primary Affiliation** move back to Bayview Hardware. |
| 6 | Open The Garcia Family. | Harper is still a member. |

**Cleanup:** keep both affiliations for T-REL-08.

## T-REL-08: End an affiliation and overlap checks

**Purpose:** ending the primary clears it, and overlapping or incomplete affiliations are refused.
**Prerequisites:** staff user, T-REL-07 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Affiliations** tab, edit Harper's Bayview Hardware affiliation, set End Date to last month, and save. | Status reads **Former**. On Harper the line carries **Former**, no **Primary**, and **Primary Affiliation** is empty. |
| 2 | Select **Make primary** on Heritage Rotary Club. | **Primary Affiliation** reads Heritage Rotary Club. |
| 3 | On Harper, add Heritage Rotary Club again with Role `Club president` and no dates. | Refused: **Harper Garcia already has an affiliation with Heritage Rotary Club as Club president covering those dates. Open AF-** followed by the record number **to change it.** |
| 4 | On the **Affiliations** tab select **New**, choose Person **Harper Garcia**, leave Organization empty, and save. | Refused: **An affiliation needs an organization.** |

**Cleanup:** delete Harper's two affiliations.

## T-REL-09: Affiliations from the organization, and read-only

**Purpose:** an affiliation can be added from the organization page, and a read-only user cannot change one.
**Prerequisites:** staff user, then read-only user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Bayview Hardware** and select **Add affiliation**. | The form asks for the person (Person) instead of the organization. |
| 2 | Choose **Luis Garcia**, Role `Customer`, and save. | The line shows Luis Garcia. Luis's own **Affiliations** card shows Bayview Hardware. |
| 3 | As read-only, open Luis and select **Make primary** on the Bayview Hardware line (it shows because Primary was not ticked). | **BarnCRM could not make that the primary affiliation. Check that you can edit affiliations, and if it happens again ask your administrator to check the Error Log.** |
| 4 | As read-only, select **Add affiliation**, fill it in, and save. | The save is refused with an error; nothing is added. |

**Cleanup:** as admin, delete Luis's Bayview Hardware affiliation.
