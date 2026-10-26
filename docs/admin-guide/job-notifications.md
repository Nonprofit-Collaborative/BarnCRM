# Job notifications

## What it does

Some BarnCRM work takes longer than a page can wait for: an import, a bulk update or bulk
delete, undoing one of those, loading the sample data, recalculating every rollup, the field
utilization count, the seasonal address swap, a duplicate scan, or recomputing every household
name. With Giving installed, the year end statement run, sending acknowledgment emails and
recalculating donor levels count too. When you start one of these yourself, BarnCRM tells you when it is done. A notification
appears under the bell at the top of every Salesforce page (and in the Salesforce mobile app),
saying what finished, how it went in numbers, and where to look. Click it to open the job's own
record or the settings page the job belongs to.

## How to turn it on

Notifications are on from the day BarnCRM is installed. There is nothing to set up.

To turn them off for everyone:

1. Open the **BarnCRM Settings** tab and choose the **General** section.
2. Clear **Tell people when their long jobs finish**.
3. Click **Save**.

Jobs still run and still record what they did on their own page or record; only the
notification stops. Tick the box again to bring notifications back.

## A five-minute walkthrough

Start with no sample data loaded.

1. Open the **BarnCRM Settings** tab, choose **General**, and check that **Tell people when
   their long jobs finish** is ticked.
2. On the same section, click **Load sample data** on the sample data card. You can leave the
   page and carry on working.
3. After a minute or two the bell at the top of the page shows a new notification:
   **Sample data load finished**, with the number of households, people and organizations.
4. Click the notification. The BarnCRM Settings console opens at the General section, where the
   sample data card shows the same counts.
5. Open the **Find** tab, run a query that returns a few sample records, press **Bulk update**
   and set a field on them (the [bulk update](bulk-update.md) page has the steps). When it
   finishes, the bell shows **Bulk update finished** with how many
   records were updated, left as they were, and could not be saved. Click it to open the bulk
   update's record, with the full run log.

## Who gets a notification

- **The person who started the job, and nobody else.** If Maria starts an import, Maria is told.
- **Only jobs somebody started by hand.** The nightly rollup run, the nightly seasonal address
  swap run on a schedule and send nothing; their results
  are on the Hub and the settings pages as before. With Giving, the nightly acknowledgment
  send and the nightly donor level pass are quiet in the same way. Clicking **Run now** or **Recalculate** on
  those pages does send one, because you are waiting for it. A field utilization count runs on
  its own tab while you watch it, so it sends none.
- **One notification per job**, when the whole job is over: an import undo that runs in several
  passes, or a rollup recalculation across several kinds of record, sends one at the end.
- **A job that stops sends one too**, titled "did not finish", with the counts so far. Its
  record or page says what went wrong, and the Error Log has the detail.

| Job | Notification opens |
|---|---|
| Import, check before importing (dry run), import undo | The import's record |
| Bulk update and its undo | The bulk update's record |
| Bulk delete and its undo | The bulk delete's record |
| Sample data load, and removal if it stops part way | BarnCRM Settings, General |
| Rollup recalculation (Recalculate, Recalculate all) | BarnCRM Settings, Rollups |
| Seasonal address swap (Run now) | BarnCRM Settings, Addresses |
| Duplicate scan, household name recompute | BarnCRM Settings, Households |
| With Giving: year end statement run | The statement run's record |
| With Giving: acknowledgment email send (Send now) | The acknowledgment run's record |
| With Giving: donor level recalculation (Recalculate now) | BarnCRM Settings, Giving |

Removing the sample data runs as background batch jobs, like the load, and sends a
notification only if it stops part way ("Sample data removal did not finish"). When it
finishes normally, the Sample Data card returns to **Not loaded** and nothing is sent.

## Common mistakes

- **Expecting a notification for the nightly jobs.** Scheduled runs send nothing on purpose,
  so nobody gets a bell every morning. Check the Hub tiles or the job's settings page instead.
- **Expecting someone else to be told.** Only the person who clicked the button is notified.
  If a colleague started the import, ask them, or open the import's record yourself.
- **No notification at all, with the setting on.** Check the bell's settings in your own
  Salesforce profile: a person can mute notifications there. If notifications are muted or
  cannot be delivered in your org, the job still finishes normally, and an entry in the Error
  Log under "Job notification" says the notification could not be sent.
- **Turning the setting off to stop the Error Log entries.** If notifications fail to send,
  fix the cause the Error Log names; turning the setting off hides the symptom and also stops
  the notifications that do work.

## Fields behind this page, for report builders

| What you see | Where it is stored |
|---|---|
| Tell people when their long jobs finish | BarnCRM Settings: `Job_Notifications__c` |
| The notification itself | Salesforce's own notifications, type **BarnCRM job finished**; not stored on a BarnCRM record |
