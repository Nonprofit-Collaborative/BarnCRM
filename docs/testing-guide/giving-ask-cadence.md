# Giving: Ask Cadence

Scripts for the Next Ask Date and Last Touch Date fields, the nightly reminder task and the Who Is Due list. Setup detail: [Ask cadence reminders](../admin-guide/ask-cadence.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, BarnCRM Rollup Builder and Giving deployed and sample data loaded.

## T-ASK-09: A Next Ask Date Creates One Reminder Task

**Purpose:** Confirm the nightly job creates one task for the donor's owner, once per date.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)). **Valentina Singh** owned by a known active user.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Giving**, open **Ask Reminders** under **Acknowledgments and Stewardship**. | The checkbox is on by default. |
| 2 | Open **Nightly Jobs**. If it says the jobs are not scheduled, select **Schedule**. | Four jobs are listed, including **Ask Reminders, 3:30 AM**, each scheduled. |
| 3 | Open Valentina Singh, select **Edit**, set **Next Ask Date** to today and **Last Touch Date** to last week. **Save**. | Saved. **Ask Reminder For Date** is empty and read only. |
| 4 | On **Nightly Jobs** select **Run now**, or wait for 3:30 AM. | The jobs start. After a minute, refresh: **Ask Reminders** shows a last run and "Created 1 ask reminders." |
| 5 | Open the owner's tasks. | One task "Ask Valentina Singh: next ask is due", due today, assigned to the owner, related to Valentina Singh. |
| 6 | Open Valentina Singh. | **Ask Reminder For Date** is today. |
| 7 | Run the job again, then delete the task and run it once more. | No second task either time. |
| 8 | Change **Next Ask Date** to yesterday and run the job. | A second task, due yesterday. |

**Cleanup:** Delete the tasks and clear the three date fields.

## T-ASK-10: Dates Outside the Window and the Off Switch

**Purpose:** Confirm future and stale dates get no task, and the setting stops tasks.
**Prerequisites:** admin. Two donors, for example **Rosa Hall** and **Susan Ortiz**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set Rosa Hall's **Next Ask Date** to tomorrow and Susan Ortiz's to 45 days ago. Run the job. | No task for either. |
| 2 | Open the **Contacts** tab, list view **Who Is Due for an Ask**. | Susan Ortiz is listed (her date is past). Rosa Hall is not. Columns include **Next Ask Date**, **Last Touch Date** and owner. |
| 3 | Set Susan's date to 10 days ago. Turn **Ask Reminders** off in **BarnCRM Settings** and run the job. | No task. Susan stays in the list. |
| 4 | Turn **Ask Reminders** back on and run the job. | One task for Susan, due 10 days ago. |
| 5 | Open an **Accounts** record for an organization, set **Next Ask Date** to today, run the job. | One task for its owner, related to the account. |
| 6 | As **Giving Read Only**, open a donor. | The dates are visible and not editable. |

**Cleanup:** Delete the tasks and clear the date fields.
