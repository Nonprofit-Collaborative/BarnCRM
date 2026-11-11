# Field History

Scripts for Field History Keeper (C-68). Setup detail: [Field History](../admin-guide/field-history.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded.

## T-FH-01: Keep and Restore a Change to an Address

**Purpose:** Confirm Field History keeps a change to a chosen field, shows it on the record and restores the earlier value after a confirm.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)); a sample Address with **City** `Springfield`.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Address's **Record Inspector**. | No **Field History** card while Field History is off. |
| 2 | In **BarnCRM Settings**, **Field History**, turn on **Turn On Field History** and save. | **Days to keep field history** shows 730. |
| 3 | In **BarnCRM Settings**, **Custom Metadata**, **History Fields**, add `Address__c.City__c` and save. Wait for the deployment to finish. | The entry is listed as active. Adding `Contact.LastName` instead is refused with a message naming it. |
| 4 | Change the Address's **City** to `Shelbyville` and save. Open its Record Inspector. | The **Field History** card lists one change: City, `Springfield` to `Shelbyville`, your name and the time. |
| 5 | Click **Restore** beside it and confirm. | The Address's City is `Springfield` again, and the card lists the restore as a new change at the top. |

**Cleanup:** archive the `Address__c.City__c` entry; turn Field History off.

## T-FH-02: Nothing Is Kept While Automation Is Paused, and Readers Cannot Restore

**Purpose:** Confirm Automation Control stops capture, and a person without BarnCRM Admin sees the history without **Restore**.
**Prerequisites:** T-FH-01 steps 2 and 3 done; a staff user (see [Test users](before-you-test.md#test-users)).
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Automation**, pause BarnCRM automation for everyone. Change the Address's City. Resume automation. | The card lists no change for that save. |
| 2 | Change the City again with automation running. | The change is listed. |
| 3 | Log in as the staff user and open the Address's Record Inspector, or a record page with the **Field History** card. | The change is listed, with no **Restore** button. |

**Cleanup:** archive the entry; turn Field History off.

## T-FH-03: Health Check and Retention

**Purpose:** Confirm Health Check warns about an unusable choice and the nightly Record Cleanup applies the retention setting.
**Prerequisites:** admin; Field History on.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | With Field History on and no active History Fields entry, open **Org Optimizer**, **Health Check**, and run it. | A warning: Field History is on but no field is chosen. |
| 2 | Add an entry, then run Health Check again. | The warning is gone. |
| 3 | Set **Days to keep field history** to 30 and save. Ask a developer to run the nightly Record Cleanup in the test org with a change older than 30 days in place (or see the Apex test `RecordRetentionBatchTest.fieldHistoryPastItsDaysIsDeleted`). | Changes older than 30 days are deleted; newer ones stay. |

**Cleanup:** set **Days to keep field history** back to 730; archive the entry; turn Field History off.
