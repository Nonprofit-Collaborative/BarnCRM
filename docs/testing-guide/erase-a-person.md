# Erase a person

Scripts for the **Erase person** action: the preview, the erasure itself, what is kept and what is removed, the confirmation, and the permission behind it. Setup detail: [Erase a person](../admin-guide/erase-a-person.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. Erasing cannot be undone: use a scratch org, never one with real people.

The admin user holds **BarnCRM Erase People** from the create script. It is in no role, not even BarnCRM Admin; the staff and read-only users do not have it.

## T-ERASE-01: Preview lists the changes and changes nothing

**Purpose:** Confirm the preview shows exactly what an erasure would do without changing any record.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Luis Garcia** (in **The Garcia Family**). | The person's page has an **Erase person** action. |
| 2 | Click **Erase person**. | A window **Erase person** with **Erasing removes what your organization holds about this person, and it cannot be undone. Press Preview first: it lists exactly what will change, and changes nothing.**, and the buttons **Close** and **Preview**. No **Erase** button yet. |
| 3 | Click **Preview**. | A spinner (**Working**), then a table **What erasing this person changes** with the columns **Record**, **What happens**, **How many**, **Fields**, **Note**. |
| 4 | Read the rows. | The person, **Emptied**, with the fields that hold values (name, email, phone, mailing address, birth date). Their addresses, if any, **Deleted**. Relationships and affiliations, if any, **Ended**. **Household** **Changed**, with **Recounted without this person. Its name and greetings were made again from the remaining members.** **Files** and activities **Kept**, with **Not erased. Open them from the person's record and delete or edit what is about this person by hand, before you erase.** |
| 5 | Read the confirmation fields under the table. | **Request reference** and **Type the person's name to confirm: Luis Garcia**. **Erase** is shown and disabled. |
| 6 | Click **Close** and reload **Luis Garcia**. | Every field is as it was: name, email `luis.garcia2@example.org`, phone, household. |

**Cleanup:** None.

## T-ERASE-02: Erase a person in a shared household

**Purpose:** Confirm the erasure empties the person, keeps the anonymous record and its totals, recounts the household and writes an Erasure record.
**Prerequisites:** admin. Note **Luis Garcia**'s household totals (with Giving) before you start.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Luis Garcia**, click **Erase person**, then **Preview**. | The table from T-ERASE-01. |
| 2 | Type `TEST-001` in **Request reference**. | Accepted (80 characters at most). |
| 3 | Type `luis  garcia` (lower case, two spaces) in the name field. | **Erase** becomes enabled: case and extra spaces do not matter. |
| 4 | Click **Erase**. | **Erased. The list above is what changed, and the Erasure record keeps it.** **Preview** and **Erase** are replaced by **Open the Erasure record**. |
| 5 | Click **Open the Erasure record**. | The **Erasure** record: **Request Reference** `TEST-001`, **Contact** pointing at the erased record, **Erased Record Id**, and **Details** listing the same rows in the same words. **Details** holds no name, email or other erased value. |
| 6 | Open the erased contact. | Name **Erased person**. Email, phone, mailing address and birth date are empty. **Email Opt Out** is ticked. |
| 7 | Open **The Garcia Family**. | Only Harper and Diego are current members. The household's name and greetings are made from them. |
| 8 | With Giving: check the erased record's and the household's giving totals and gifts. | Gifts and totals are kept, credited to **Erased person**. |

**Cleanup:** None (an erasure cannot be undone). Recreate the org before another full run if you need Luis.

## T-ERASE-03: Erase the only member of a household

**Purpose:** Confirm a household left empty is kept and made anonymous when empty households are not deleted.
**Prerequisites:** admin. **Delete Empty Households** off in **BarnCRM Settings**, **Households** (the default). Create a contact `Erin Erasetest` with an email, phone and mailing address; a household of its own is created for it.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open `Erin Erasetest`, click **Erase person**, then **Preview**. | Among the rows: **Household**, **Changed**, with the note **Kept because Delete Empty Households is off (BarnCRM Settings, Households). Renamed, and its greetings and addresses emptied.** The household's addresses are **Deleted**. |
| 2 | Type `TEST-002` and `Erin Erasetest`, click **Erase**. | **Erased. The list above is what changed, and the Erasure record keeps it.** |
| 3 | Open the household that held Erin. | Name **Erased household**. Greetings and address are empty. It is not deleted. |
| 4 | Open **Org Optimizer**, **Data quality**, and click **Recount**. | **People with no household** does not count the erased person. |

**Cleanup:** None.

## T-ERASE-04: The typed name must match

**Purpose:** Confirm a wrong name keeps **Erase** disabled and nothing is erased.
**Prerequisites:** admin. A sample person, for example **Margaret Young**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Margaret Young**, click **Erase person**, then **Preview**. | The table and the confirmation fields. |
| 2 | Type `Margaret Youn`. | **Erase** stays disabled. |
| 3 | Type `Maria Whitfield`. | **Erase** stays disabled. |
| 4 | Click **Close**. Reload **Margaret Young**. | Unchanged. No Erasure record names her. |

**Cleanup:** None.

## T-ERASE-05: A person cannot be erased twice

**Purpose:** Confirm an erased record is refused a second time.
**Prerequisites:** admin; T-ERASE-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the erased **Erased person** record from T-ERASE-02. Click **Erase person**, then **Preview**. | Refused: **This person was already erased on** followed by the date. |
| 2 | Click **Close**. | Nothing changed. Still one Erasure record for this person. |

**Cleanup:** None.

## T-ERASE-06: Staff without Erase People

**Purpose:** Confirm someone without the permission set never sees the action.
**Prerequisites:** staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Harper Garcia**. | No **Erase person** action on the page. |
| 2 | Open a sample organization's record page, then a household's. | No **Erase person** action. |

**Cleanup:** None.

## T-ERASE-07: The action leaves when the permission set is removed

**Purpose:** Confirm the Erase People permission, not the admin role, controls the action, and the Access page gives and takes it with a warning.
**Prerequisites:** admin; staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open **BarnCRM Settings**, **Access**, **Extra permissions**, and choose **BarnCRM Erase People**. | Its line reads **Erase a person on their request (the right to be forgotten), which cannot be undone.**, with the warning **This permission lets the person remove data. Give it only to someone you trust to do that.** |
| 2 | Give it to the staff user with **Give permission** and confirm. | A message says the staff user now has it. |
| 3 | As staff, reload **Harper Garcia**. | **Erase person** is on the page. Click it: **Preview** is offered. Click **Close**. |
| 4 | As admin, remove **BarnCRM Erase People** from the staff user and confirm. | A message says the staff user no longer has it. |
| 5 | As staff, reload **Harper Garcia**. | No **Erase person** action. |

**Cleanup:** None.

## T-ERASE-08: Nothing offers an undo

**Purpose:** Confirm an erasure has no undo anywhere and its record keeps no erased value.
**Prerequisites:** admin; T-ERASE-02 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Data Manager** and read **Data jobs**. | No erasure is listed; erasing is not a data job. |
| 2 | Open the Erasure record from T-ERASE-02. | No undo or restore button. **Details** names records and fields only. |
| 3 | Open the Recycle Bin and search for the street of Luis Garcia's deleted address (if the preview listed one). | Not there: the erasure empties deleted records from the Recycle Bin. The erased contact is not there either (it was kept and made anonymous). |

**Cleanup:** None.
