# Error Log

## What It Does

When something goes wrong inside BarnCRM, it writes down what happened in plain
language and puts it somewhere you can read it. That is the Error Log. Instead of a
technical failure disappearing into a log file only a developer can open, you get a list
of entries that say what went wrong, which record it happened on, and what to do about it.

You can work through the list, mark the ones you have looked at, and mark the ones you
have fixed, so the list stays short and honest.

## How to Turn It On

The Error Log is on as soon as BarnCRM is installed. Nothing is recorded unless
something actually fails, so on a healthy organization the list is empty.

You will find it in three places:

- **The BarnCRM home page.** The **Errors to Review** tile shows a count of the new
  errors waiting, and an **Open the Error Log** link that opens the list of new entries.
  The tile shows the count only, not the entries. When some of those errors came from the
  install or an upgrade (including a package's setup steps), a line under the count says how many ("Of the new errors above, 3
  came from the install and upgrades"); that number is part of the count, not added to it.
- **The Org Optimizer tab, Errors section.** The **Error Log** card shows the count of new
  entries and the five most recent, each with its message and where it came from, an
  **Open This Entry** button and a **Mark Acknowledged** button. The Errors section needs
  the Manage BarnCRM Settings permission (the BarnCRM Admin role).
- **The Error Log tab** in the BarnCRM app. This is the full list, and you can sort
  it, filter it, and build reports on it like any other list in Salesforce.

Everyone with the BarnCRM Staff, BarnCRM Admin or BarnCRM Read Only role can read the
Error Log entries. Only the BarnCRM Admin role can change an entry's status, and only the BarnCRM Admin role sees an
entry's **Technical detail**: the error Salesforce raised can repeat values from a record
that a colleague's own access would not show them.

Errors are recorded whatever else is happening: turning an automation off, or pausing all
automation, never stops the Error Log from recording a problem.

## The Error Digest Email

If nobody opens the BarnCRM home page for a few days, nobody sees the tile. The error digest fixes that:
once a day (or once a week), BarnCRM emails a short summary of the new entries to the
people who look after it. It is off until you switch it on.

What the email says:

- how many new entries arrived since the last digest, counting only the ones still marked
  **New**;
- how many came from each source (for example "Household naming: 4") and how many at each
  severity;
- the 25 newest, each as its entry number with a link that opens it;
- a link to the whole Error Log, and how many entries in all are still New.

If a great many entries arrive at once, the email counts the newest 2,000 and says "more
than 2,000" rather than an exact number. Open the Error Log for the rest.

It never copies an entry's message, its technical detail or the record it names. Those stay
in Salesforce, where the same access rules as always decide who can read them. Click a link
to see the rest.

If nothing new has arrived, no email is sent at all.

### The Weekly Admin Summary

When the digest is set to **Once a week**, it also carries a short **Admin Summary** of what an
administrator would otherwise have to go looking for:

- any org limit at 80 percent or more (data and file storage, daily API requests, daily
  asynchronous Apex runs and single emails), each with its percentage;
- BarnCRM data jobs (imports, bulk updates, bulk deletes and their undos) that failed since the
  last digest, up to ten, each with a link that opens it;
- how many duplicate suggestions are waiting for review (counted only when the person who
  scheduled the digest holds the BarnCRM Duplicate Review permission set).

An email is sent when there are new Error Log entries or something to report; when there is
neither, nothing is sent. With no new entries the subject reads **BarnCRM: Weekly Admin
Summary**. Like the rest of the digest, it counts and names; it never copies record content.
The summary is on by default for a weekly digest. To turn it off, clear **Weekly admin
summary** on the same page. A daily digest never carries it.

Recent Setup changes will join the summary once the Setup Changes Log exists (C-56).

### Switch It On

1. Open **BarnCRM Settings** and click **Error Log** in the left navigation.
2. In **Digest recipients**, leave the box empty to send the digest to everyone who holds
   the Manage BarnCRM Settings permission (the BarnCRM Admin role), or type the email
   addresses of the people who should get it, separated by commas. Each address has to be
   the email address of an active user of your Salesforce: the digest is never sent to
   anyone outside it, and an address that is not a user's is refused when you save. While
   the box is empty it reads **Everyone with the Manage BarnCRM Settings permission**, with a
   **Default** badge.
3. In **Digest frequency**, choose **Every day** or **Once a week**, then click **Save**.
4. In the **Error Digest** panel, click **Schedule Daily Run**. The panel now says the digest is
   scheduled and when it runs next: every morning at 7:00 AM in your organization's time zone, after the nightly jobs, so their
   problems are in it. A weekly digest checks every morning and sends once seven days have
   passed since the last one.
5. Click **Send Now** to try it. If there are new entries, the email arrives in a minute or
   two; if not, the panel says there was nothing new and no email went out.

The panel always shows when the digest last ran, what it did in one sentence (for example
"Sent 7 new entries to 2 people" or "Nothing new since Sep 23, 7:00 AM: no email sent"),
and who it goes to. Click **Stop Daily Run** to switch it off.

Sending the digest does not use up your organization's daily email allowance: it goes to
users of your own Salesforce, which the platform does not count. At most 50 people receive
it.

## How Long Entries Are Kept

Each entry can hold a long technical detail, so an Error Log that is never emptied slowly
fills your organization's data storage. BarnCRM deletes entries older than **180 days**, whatever
their status, every morning when the daily Error Log run starts (the same 7:00 AM run that
sends the digest).

1. Open **BarnCRM Settings** and click **Error Log** in the left navigation.
2. In **Days to keep Error Log entries**, type how many days to keep them, from 1 to
   3,650, or 0 to keep every entry forever. Click **Save**. The next morning's run deletes
   anything older; nothing is deleted when you save.
3. Make sure the daily run is scheduled: the **Error Digest** panel says so, and Health
   Check lists it under **Nightly jobs are not scheduled** when it is not. Old entries are
   deleted only while it runs, whether or not anyone receives the digest.

Deleted entries go to the Recycle Bin for 15 days, like any record you delete. If you need
an entry for longer, export the Error Log list or build a report on it before it ages out.

## A Five-Minute Walkthrough

Maria has heard from a colleague that "something did not save this morning."

1. Open the **BarnCRM** app. On the home page, look at the **Errors to Review** tile. It
   shows how many new errors there are, for example "3".
2. Open the **Org Optimizer** tab and choose **Errors**. The **Error Log** card shows
   "3 new" and the five most recent entries. Each shows the message and where it came
   from, for example "Household naming".
3. Click **Open This Entry** on the entry your colleague described. The record opens.
4. Read the **Message**. It is written for you, not for a developer: it says what went
   wrong and what to do about it, for example "This household could not be renamed because
   every member is marked deceased. Add a living member, or set a custom name on the
   household." When BarnCRM hit something it did not expect, the message names where it
   happened, for example "BarnCRM hit a problem it did not expect in Household naming.",
   so two such entries from different places read differently in the list.
5. Do what it says on the record it names. The **Record reference** on the entry is the
   record involved, so you can open it and fix the data.
6. Come back to the Error Log entry and set **Status** to **Resolved**, then save. It
   drops out of the "New" count on the home page tile.
7. If you cannot fix an entry yourself, set **Status** to **Acknowledged** instead, so
   your colleagues know someone has seen it, and send the **Technical detail** to whoever
   supports your Salesforce. That section is the part written for a developer.
8. Go back to the home page. The **Errors to Review** count has gone down by one.

## Common Mistakes

- **Treating the Error Log as a to-do list that someone else owns.** Unless you switch on
  the error digest, nobody is emailed about these. If you do not look at the home page count or the Org Optimizer's Errors section, nobody
  looks at them.
- **Expecting the digest to arrive when your organization blocks email.** If your
  Salesforce is set to send system email only (Setup, Deliverability), no digest can be
  sent. The panel's last run says so, and an entry appears in the Error Log (once, not
  every day). Whoever administers your Salesforce can change the setting.
- **Deactivating the person who scheduled the digest.** The digest runs as that person, so
  it stops. Health Check warns when a scheduled digest has not run for two days: open the
  Error Log section of BarnCRM Settings, click **Stop Daily Run**, then **Schedule Daily Run** again as
  yourself.
- **Marking entries Acknowledged and expecting them in the digest.** The digest counts only
  entries that are still New, because those are the ones nobody has looked at.
- **Deleting entries to clear the list.** Use the status instead. Marking something
  Resolved keeps the history, which is what you want the next time the same thing happens,
  and it keeps the tile count accurate either way.
- **Reading the technical detail first.** The message at the top is the one written for
  you. The technical detail underneath is for a bug report on GitHub (see [SUPPORT.md](../../SUPPORT.md); remove names,
  emails and amounts first), and it will not tell you
  anything about your data that the message does not already say.
- **Expecting an entry for a mistake you made in a spreadsheet.** The Error Log records
  failures inside BarnCRM, not every data problem. A person imported with the wrong
  address is a data question, not an error, and it will not appear here.
- **Assuming an empty list means nothing has failed.** If automation is paused, the work
  that would have failed is not running at all. Check the automation banner on the home
  page as well. See the [Automation control page](automation-control.md).
