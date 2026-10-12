# Error Log

## What it does

When something goes wrong inside Open Impact, it writes down what happened in plain
language and puts it somewhere you can read it. That is the Error Log. Instead of a
technical failure disappearing into a log file only a developer can open, you get a list
of entries that say what went wrong, which record it happened on, and what to do about it.

You can work through the list, mark the ones you have looked at, and mark the ones you
have fixed, so the list stays short and honest.

## What you will see in v0.1

This page describes the finished feature. The Open Impact app and its home page, where
the tile lives, are built by feature C-03. Until then the Error Log tab is the way in, and
the tile can be placed on any Lightning page. Everything else on this page works today.

## How to turn it on

The Error Log is on as soon as Open Impact is installed. Nothing is recorded unless
something actually fails, so on a healthy organization the list is empty.

You will find it in two places:

- **The Open Impact home page.** A tile shows how many new errors are waiting and the
  five most recent, with the message and where it came from. Click any of them to open it,
  or click the tile heading to see the whole list.
- **The Error Log tab** in the Open Impact app. This is the full list, and you can sort
  it, filter it, and build reports on it like any other list in Salesforce.

Everyone with the Open Impact Staff or Open Impact Admin role can read the Error Log. Only the
Open Impact Admin role can change an entry's status.

Errors are recorded whatever else is happening: turning an automation off, or pausing all
automation, never stops the Error Log from recording a problem.

## The error digest email

If nobody opens the Hub for a few days, nobody sees the tile. The error digest fixes that:
once a day (or once a week), Open Impact emails a short summary of the new entries to the
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

### Switch it on

1. Open **Open Impact Settings** and click **Error Log** in the left navigation.
2. In **Digest recipients**, leave the box empty to send the digest to everyone who holds
   the Manage Open Impact Settings permission (the Open Impact Admin role), or type the email
   addresses of the people who should get it, separated by commas. Each address has to be
   the email address of an active user of your Salesforce: the digest is never sent to
   anyone outside it, and an address that is not a user's is refused when you save.
3. In **Digest frequency**, choose **Every day** or **Once a week**, then click **Save**.
4. In the **Error digest** panel, click **Schedule**. The panel now says the digest is
   scheduled and when it runs next: every morning at 7:00, after the nightly jobs, so their
   problems are in it. A weekly digest checks every morning and sends once seven days have
   passed since the last one.
5. Click **Send now** to try it. If there are new entries, the email arrives in a minute or
   two; if not, the panel says there was nothing new and no email went out.

The panel always shows when the digest last ran, what it did in one sentence (for example
"Sent 7 new entries to 2 people" or "Nothing new since Sep 23, 7:00 AM: no email sent"),
and who it goes to. Click **Stop** to switch it off.

Sending the digest does not use up your organization's daily email allowance: it goes to
users of your own Salesforce, which the platform does not count. At most 50 people receive
it.

## A five-minute walkthrough

Maria has heard from a colleague that "something did not save this morning."

1. Open the **Open Impact** app. On the home page, look at the **Error Log** tile. It
   says how many new errors there are, for example "3 new".
2. Read the five most recent entries in the tile. Each line shows the message and where it
   came from, for example "Household naming".
3. Click the entry your colleague described. The record opens.
4. Read the **Message**. It is written for you, not for a developer: it says what went
   wrong and what to do about it, for example "This household could not be renamed because
   every member is marked deceased. Add a living member, or set a custom name on the
   household."
5. Do what it says on the record it names. The **Record reference** on the entry is the
   record involved, so you can open it and fix the data.
6. Come back to the Error Log entry and set **Status** to **Resolved**, then save. It
   drops out of the "New" count on the home page tile.
7. If you cannot fix an entry yourself, set **Status** to **Acknowledged** instead, so
   your colleagues know someone has seen it, and send the **Technical detail** to whoever
   supports your Salesforce. That section is the part written for a developer.
8. Go back to the home page. The tile count has gone down by one.

## Common mistakes

- **Treating the Error Log as a to-do list that someone else owns.** Unless you switch on
  the error digest, nobody is emailed about these. If you do not look at the tile, nobody
  looks at it.
- **Expecting the digest to arrive when your organization blocks email.** If your
  Salesforce is set to send system email only (Setup, Deliverability), no digest can be
  sent. The panel's last run says so, and an entry appears in the Error Log (once, not
  every day). Whoever administers your Salesforce can change the setting.
- **Deactivating the person who scheduled the digest.** The digest runs as that person, so
  it stops. Health Check warns when a scheduled digest has not run for two days: open the
  Error Log section of Open Impact Settings, click **Stop**, then **Schedule** again as
  yourself.
- **Marking entries Acknowledged and expecting them in the digest.** The digest counts only
  entries that are still New, because those are the ones nobody has looked at.
- **Deleting entries to clear the list.** Use the status instead. Marking something
  Resolved keeps the history, which is what you want the next time the same thing happens,
  and it keeps the tile count accurate either way.
- **Reading the technical detail first.** The message at the top is the one written for
  you. The technical detail underneath is for a support request, and it will not tell you
  anything about your data that the message does not already say.
- **Expecting an entry for a mistake you made in a spreadsheet.** The Error Log records
  failures inside Open Impact, not every data problem. A person imported with the wrong
  address is a data question, not an error, and it will not appear here.
- **Assuming an empty list means nothing has failed.** If automation is paused, the work
  that would have failed is not running at all. Check the automation banner on the home
  page as well. See the [Automation control page](automation-control.md).
