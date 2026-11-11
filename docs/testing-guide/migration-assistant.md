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
| 1 | Open **BarnCRM Settings**, **Integrations**. | Under Alternatives to BarnCRM Modules, **Nonprofit Success Pack (NPSP)** shows **Installed in this org**, its compatibility note and **Start Migration**. |
| 2 | Click **Start Migration**. | **NPSP Customizable Rollups** opens with one step **Copy NPSP Customizable Rollups** and **Open Rollup Builder**. **Verification** counts the active NPSP customizable rollups. |
| 3 | Run [T-RB-49](rollup-builder.md). Come back and click **Refresh**. | **Done** counts the copies turned on. |

**Cleanup:** None.
