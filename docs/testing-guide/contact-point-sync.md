# Contact Point Sync

Scripts for the optional BarnCRM Contact Point Sync module: copying a person's email addresses, phone numbers and current addresses to Salesforce Contact Points, the backfill page, and orgs without the objects. Setup detail: [Contact Point Sync](../admin-guide/contact-point-sync.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Contact Point Sync deployed and sample data loaded. In Setup, **Data Protection and Privacy**, tick **Make data protection details available in records** so the Individual object is on (T-CPS-05 needs it off). To see the copies, open the App Launcher and search **Contact Point Emails**, **Contact Point Phones** and **Contact Point Addresses**, or add the Individual's related lists.

## T-CPS-01: The Page and the Backfill

**Purpose:** confirm the page explains each kind, previews the count and copies everyone already in the org.
**Prerequisites:** admin (BarnCRM Admin, which gives Contact Point Sync Admin).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM Admin** app and the **Contact Point Sync** tab. | The page shows three lines, Email, Phone and Address, each `copied after every save.` A count line starts `The backfill will check` with the number of people in the org. |
| 2 | Click **Run Backfill**. | The button greys out and `The backfill is running. Refresh the page later to see what it did.` shows. |
| 3 | Wait a minute and reload. | `Last backfill finished` with a time and `Created ...` counts. The managed count is above 0. |
| 4 | Open a sample person with a personal email and a home phone, then their Individual. | One Contact Point Email with that address and one Contact Point Phone with that number, type Home. |

**Cleanup:** None.

## T-CPS-02: A Save Is Copied, and an Edit Elsewhere Is Put Back

**Purpose:** confirm BarnCRM is the source.
**Prerequisites:** admin, after T-CPS-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create person `Ana Rivera` with **Personal Email** `ana@example.org` and **Mobile** `555 0100`. | Her Individual has one Contact Point Email `ana@example.org` and one Contact Point Phone `555 0100`, type Mobile. |
| 2 | Change her **Personal Email** to `ana.r@example.org` and save. | The same Contact Point Email now shows `ana.r@example.org`; no second one is added. |
| 3 | Open that Contact Point Email and change the address to `wrong@example.org`. Then edit Ana's **Mobile** to `555 0101` and save. | The Contact Point Email shows `ana.r@example.org` again, and the phone shows `555 0101`. |
| 4 | Clear Ana's **Mobile** and save. | Her Contact Point Phone is gone. |

**Cleanup:** None (T-CPS-03 uses Ana).

## T-CPS-03: Addresses, Delete and Restore

**Purpose:** confirm current addresses are copied, a former one is removed, and delete and undelete follow the person.
**Prerequisites:** admin, after T-CPS-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Ana's **Addresses** card, add a household address `1 Main St`, `Springfield`, and make it primary. | Her Individual has a Contact Point Address for `1 Main St`, marked default. |
| 2 | Mark the address **Former**. | The Contact Point Address is gone. The address stays on Ana's card. |
| 3 | Delete Ana. | Her Contact Point Email is gone. |
| 4 | Restore Ana from the Recycle Bin. | Her Contact Point Email is back. |

**Cleanup:** Delete Ana.

## T-CPS-04: Switches and Pause All

**Purpose:** confirm a kind turned off is left alone and that Pause All covers all four automations.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Contact Points**. Untick **Sync phones** and save. | The setting saves. The Contact Point Sync page says Phone is `turned off in BarnCRM Settings, Contact Points.` |
| 2 | Change a person's **Home Phone** and save. | Their Contact Point Phone keeps the old number. |
| 3 | Tick **Sync phones** again and save. Open the **Automation** page. | Four rows, **Contact Point Sync: People**, **Addresses**, **Person Accounts** and **Household Moves**, all on. |
| 4 | Click **Pause All**. Change the person's **Personal Email** and save. | Their Contact Point Email keeps the old address. |
| 5 | Resume automation, then run the backfill from the Contact Point Sync page. | After the backfill, the phone and the email match the person. |

**Cleanup:** Make sure automation is resumed.

## T-CPS-06: Household Moves and Person Accounts

**Purpose:** confirm a household move is copied at once, and that person accounts are copied like contacts where the org has them.
**Prerequisites:** admin; two households with different current addresses; a person with an email who belongs to the first household. For step 3, an org with Person Accounts turned on (skip it in any other org).

| Step | Action | Expected result |
|---|---|---|
| 1 | Move the person to the second household (change their membership, or their account, to the second household). Do not save the person again. | Their Individual's Contact Point Address now shows the second household's street and no longer the first's. |
| 2 | On the **Automation** page, switch off **Contact Point Sync: Household Moves**. Move the person back. | The Contact Point Address does not change yet. Switch the row back on and save the person: it catches up. |
| 3 | Create a person account with an email and a home address; change the email. | Their Individual has the Contact Point Email and Address; the email follows the change. Deleting the person account removes the copies. |

**Cleanup:** Switch **Household Moves** back on; delete the test people.

## T-CPS-07: A Large Save Is Copied by a Background Job

**Purpose:** confirm a save of more than 50 people finishes without copying inside it and every person is still copied moments later, while a smaller save is copied at once.
**Prerequisites:** admin; a CSV of 60 new people, each with a Last Name and an Email, and one of 10 more; Data Loader, Data Import Wizard or Workbench to insert them (not a BarnCRM import, which copies inside its own background job).

| Step | Action | Expected result |
|---|---|---|
| 1 | Insert the 10 people. Open one of them. | Their Contact Point Email is there straight away. |
| 2 | Insert the 60 people. Wait about a minute, then open one of them. | Their Contact Point Email is there. In Setup, **Apex Jobs**, a `ContactPointSyncService.Job` (or `Job`) row has Completed. The Error Log has no Contact Point Sync warning. |
| 3 | On the **Automation** page, switch off **Contact Point Sync: People**. Insert 60 more people. | No Contact Point Email is made for them, and no new sync job appears. Switch the row back on and run the backfill: they are copied. |

**Cleanup:** Delete the test people; make sure **Contact Point Sync: People** is on.

## T-CPS-05: An Org Without the Individual Object, and a Person Without the Permission

**Purpose:** confirm the module explains instead of failing, and the backfill needs Manage BarnCRM Settings.
**Prerequisites:** admin; a second user with the Staff role, given **Contact Point Sync Admin** through **BarnCRM Settings**, **Access**, **Extra Permissions**, and without **Manage BarnCRM Settings**.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Setup, **Data Protection and Privacy**, untick **Make data protection details available in records**. Open the Contact Point Sync page. | Each kind says `the Individual object is turned off, so nothing is copied.` **Run Backfill** is greyed out. |
| 2 | Create a person with an email. | The save succeeds. |
| 3 | Tick the Setup option again. Log in as the second user and open the page. | `Running the backfill needs the Manage BarnCRM Settings permission.` **Run Backfill** is greyed out. |

**Cleanup:** Log back in as admin.
