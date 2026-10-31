# Ask Cadence Reminders

## What It Does

Fundraisers keep a date in their head for when to ask a donor again. Ask cadence puts that date on the donor record, and reminds the donor's owner when it arrives.

Each person (Contact) and each household or organization (Account) gets three fields:

- **Next Ask Date**: the day the donor should next be asked. Staff enter it.
- **Last Touch Date**: the day somebody last contacted the donor. Staff enter it. BarnCRM does not guess it from tasks or emails.
- **Ask Reminder For Date**: the Next Ask Date a reminder was last made for. The nightly job sets it, and nobody edits it. It is how BarnCRM knows not to remind about the same date twice.

Every night at 3:30 AM, BarnCRM finds donors whose Next Ask Date is today or earlier and creates one ordinary Salesforce task for the donor's owner, due on the Next Ask Date. The task lists the donor on **Name** (people) and **Related To**, so it shows up in the owner's usual task list.

## How to Set It Up

Everything is in the app. You never open Setup.

1. Open **BarnCRM Settings**, choose the **Giving** section, and find **Ask Reminders** under **Acknowledgments and Stewardship**. It is **on** by default and does nothing until somebody enters a Next Ask Date. Turn it off if you do not want tasks created. The dates and the list below keep working when it is off.
2. Open **Nightly Jobs and Accounting Periods**, then **Nightly Jobs**, and choose **Schedule** if the jobs are not scheduled yet. **Ask Reminders, 3:30 AM** is the fourth job on the page, with its last run and a one sentence summary (how many reminders it created, how many it could not).
3. Add **Next Ask Date** and **Last Touch Date** to the record pages your fundraisers use. They are on the Contact and Account objects, and the Giving permission sets already grant them: **Giving Staff** and **Giving Admin** can edit the two dates, **Giving Read Only** can read them. Nobody edits **Ask Reminder For Date**.

## Who Is Due

Open the **Contacts** or **Accounts** tab and choose the list view **Who Is Due for an Ask**. It shows every donor whose Next Ask Date is today or earlier, with their Last Touch Date, donor level, last gift date, total giving and owner. Click the **Next Ask Date** column heading to sort the longest overdue to the top. The list does not depend on the setting.

## What You Should Know

- **One reminder per donor per date.** Running the job twice, or on every night after the date, creates nothing more. If staff change the Next Ask Date to a different date, that is a new ask and gets a new reminder.
- **A deleted task stays deleted.** BarnCRM remembers the reminder on the donor, not in the task list, so deleting or completing the task does not bring it back. BarnCRM never edits, closes or deletes a task it created.
- **Old dates do not flood anyone.** A Next Ask Date more than 30 days in the past gets no task. This protects the first night you turn the job on, when an old import may have left many stale dates. A date inside the last 30 days that the job missed (for example, jobs were stopped for a week) is caught up. Donors with older dates still show in **Who Is Due for an Ask**.
- **The owner gets the task.** If a donor's owner is an inactive user, no task can be made. The job counts the donor in its summary, writes the reason to the **Error Log**, and tries again the next night. Reassign the donor to an active owner to fix it.
- **No emails.** Reminders are tasks inside Salesforce. Nothing is sent to the donor or to the owner by email.
- **Health Check.** **Schedule all nightly jobs** in Health Check schedules this job with the other Giving jobs.

## What This Does Not Do Yet

- It does not set the Last Touch Date for you when a task is completed or a gift arrives.
- It reads only the dates on the donor. A solicitation or ask record with its own date is a separate feature.
- It does not send a daily digest or a Chatter post.

## Related

- [Stewardship plans](stewardship-plans.md): sequences of follow-up tasks that start when a gift arrives.
- [Donor levels](donor-levels.md): the level shown in the **Who Is Due for an Ask** list.
- User Guide: [Ask reminders](../user-guide/ask-reminders.md). Testing Guide: [Giving: ask cadence](../testing-guide/giving-ask-cadence.md).
