# Migration Assistant

Scripts for the Integrations page's detected apps and migration links and for the Migration
Assistant. Setup detail: [Migration Assistant](../admin-guide/migration-assistant.md) and
[Integrations](../admin-guide/integrations.md).

Before you start: an org from [Before you test](before-you-test.md) with Core and BarnCRM Rollup
Builder deployed. T-MIG-02 to T-MIG-05 need DLRS installed (free, from the AppExchange listing
"Declarative Lookup Rollup Summaries Tool") with the **Test child count** rollup of
[T-RB-33](rollup-builder.md#t-rb-33-turning-on-a-rollup-that-dlrs-also-fills-asks-first-and-the-answer-is-recorded)
active and its BarnCRM copy not yet made. T-MIG-06 needs an org with NPSP.

## T-MIG-01: Integrations Lists Only Installed Alternatives, and No Migration Without a Kit

**Purpose:** confirm detected apps, notes and migration links show only where they apply.
**Prerequisites:** admin user; an org without DLRS, NPSP or Nonprofit Cloud; a staff user without Manage BarnCRM Settings.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Integrations**. | Complementary Apps and In Development are listed. No DLRS, NPSP or Nonprofit Cloud Fundraising listing. No **Start Migration** button anywhere. |
| 2 | Log in as the staff user and open the same page. | The same list. No **Start Migration** button. |

**Cleanup:** None.

## T-MIG-02: Start Migration Opens the DLRS Rollups Kit

**Purpose:** confirm a detected app with a kit offers Start Migration, and the Assistant opens in place.
**Prerequisites:** the org with DLRS; admin user with Manage BarnCRM Settings; a staff user without it.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Integrations**. | **DLRS (Declarative Lookup Rollup Summaries)** shows **Installed in this org** and **Start Migration**. |
| 2 | Click **Start Migration**. | The list is replaced by **DLRS Rollups** with **Back to Integrations**, its description, one step **Copy DLRS Rollups** (**Not Started**) with **Open Rollup Builder** and **Mark Done**, and **Retire the Old App** with its items, not yet tickable. |
| 3 | Under the step, read **Verification**. | **In the other app now** is the number of active DLRS rollups (at least 1); **Done** is 0; **Check this step**. |
| 4 | Click **Back to Integrations**. | The list returns. |
| 5 | Log in as the staff user and open **Integrations**. | DLRS is listed without **Start Migration**. |

**Cleanup:** None.

## T-MIG-03: A Tool Step, Verified and Marked Done

**Purpose:** confirm a tool step opens its tool, verifies, and is marked done and undone.
**Prerequisites:** T-MIG-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | In the Assistant, click **Open Rollup Builder**. | The **Rollup Builder** tab opens. |
| 2 | Click **Import From DLRS** and copy, compare and turn on **Test child count** as in [T-RB-35](rollup-builder.md). | The copy is on. |
| 3 | Return to **BarnCRM Settings**, **Integrations**, **Start Migration** on DLRS. | The same run opens. **Verification**: **Done** equals **In the other app now** for the copied rollups; **Verified** when every active DLRS rollup has a copy that is on. |
| 4 | Click **Mark Done**. | The step reads **Done**; **Mark Not Done** replaces it. **Retire the Old App** items can now be ticked. |
| 5 | Click **Mark Not Done**, then **Mark Done** again. | The step goes back to **Not Started**, then **Done**. |

**Cleanup:** keep the run for T-MIG-04.

## T-MIG-04: Retire Checklist Completes the Migration and Changes Nothing in DLRS

**Purpose:** confirm the checklist completes the run, reopens it when unticked, and never touches the other app.
**Prerequisites:** T-MIG-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | Tick every item under **Retire the Old App**. | Each stays ticked after **Refresh**. After the last, the kit shows **Complete**. |
| 2 | Untick one item. | **Complete** is gone. Tick it again: **Complete** returns. |
| 3 | Open the **Lookup Rollup Summaries** tab (DLRS). | **Test child count** is exactly as before: still active. BarnCRM changed nothing in DLRS. |

**Cleanup:** switch **Test child count** off in DLRS if you are done with it.

## T-MIG-05: Only Administrators Can Run a Kit

**Purpose:** confirm the server refuses a migration action without Manage BarnCRM Settings.
**Prerequisites:** the org with DLRS; a test user with the Staff role and no Manage BarnCRM Settings.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the test user, in the Developer Console run `MigrationController.getKit('DLRS_Rollups');` | Fails: "You need Manage BarnCRM Settings to run a migration." |
| 2 | As the test user, run `MigrationController.setToolStep('DLRS_Rollups', 'copy', true);` | Fails with the same message. No Migration Run record is created. |

**Cleanup:** None.

## T-MIG-06: NPSP and Its Rollup Kit Appear Only With NPSP

**Purpose:** confirm NPSP is detected, its compatibility note shown, and the NPSP rollup kit offered.
**Prerequisites:** an org with NPSP and Customizable Rollups enabled (NPSP Settings, Customizable Rollups), Core and Rollup Builder deployed; admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Integrations**. | Under Alternatives to BarnCRM Modules, **Nonprofit Success Pack (NPSP)** shows **Installed in this org**, its compatibility note and one button per NPSP kit installed, each named **Start Migration:** and the kit's name, in order (**NPSP People and Addresses** first, **NPSP Customizable Rollups** last). |
| 2 | Click **Start Migration: NPSP Customizable Rollups**. | **NPSP Customizable Rollups** opens with one step **Copy NPSP Customizable Rollups** and **Open Rollup Builder**. **Verification** counts the active NPSP customizable rollups. |
| 3 | Run [T-RB-49](rollup-builder.md). Come back and click **Refresh**. | **Done** counts the copies turned on. |

**Cleanup:** None.

## T-MIG-07: NPSP People and Addresses Moves Relationships, Affiliations and Addresses

**Purpose:** confirm the NPSP People and Addresses kit runs its steps in order, copies each NPSP relationship once, and verifies.
**Prerequisites:** the NPSP org of T-MIG-06 with Core deployed; in NPSP, a household with two contacts, Ana and Ben, a Spouse relationship between them (NPSP makes both sides), an affiliation of Ana to an organization **Test Org** as Primary, and a seasonal Vacation address on the household. Admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Integrations**, click **Start Migration: NPSP People and Addresses**. | Four steps: **Adopt NPSP Households** (Not Started, with **Open BarnCRM Settings**), then **Relationships**, **Affiliations** and **Household Addresses**, each Waiting. |
| 2 | Click **Start** on **Relationships**. | Refused: "Finish the steps above this one first." |
| 3 | Adopt the households ([T-HH-21](people-and-households.md#t-hh-21-adopt-npsp-households)). Come back and click **Mark Done** on the first step. | **Relationships** shows **Start**. |
| 4 | Click **Start** on **Relationships**, then **Refresh** until **Ready to Review**. Click **Show Results**. | The preview creates 1 relationship (not 2): NPSP's own other side is not read. |
| 5 | Click **Load** and confirm. **Refresh**. | **Done** and **Verified** (1 in the other app now, 1 read, 1 loaded, 0 rejected). Ana's record shows Ben as **Spouse**, and Ben's shows Ana as **Spouse**, made by BarnCRM. |
| 6 | Run **Affiliations** and **Household Addresses** the same way. | Each **Verified**. Ana's affiliation to **Test Org** is primary. The household has a **Seasonal** address with the NPSP months and days, and both street lines. |
| 7 | Click **Undo** on **Household Addresses**, then **Refresh**. | **Undone**; the addresses are gone. **Undo** is not offered on **Affiliations** while a later step is done; after the undo it is. |
| 8 | Tick every item under **Retire the Old App**. | **Complete** only once every step is done again. NPSP's records are unchanged. |

**Cleanup:** delete the test records, or keep them for the NPSP giving kits.
