# Pledge Reminders

## What It Does

Pledge reminders nudge donors about installments that are coming due or have gone unpaid. You
write a short ladder of steps once, in the language you already use ("an email a week before the
due date, a second email two weeks after, a letter a month after"), and BarnCRM works out, every
time it runs, which step each open installment is due for. Every reminder is recorded, so nobody
has to guess whether a donor was already asked.

It is built on the same pieces as [acknowledgments](acknowledgments.md): the email wording is a
standard Salesforce email template, a letter is a spreadsheet you merge with your own letter, and
the same permission and from address apply.

**Nothing is ever sent until you turn it on.** The setting is off by default, it is visible in
BarnCRM Settings, and while it is off neither the **Send Reminders Now** button nor the nightly
run does anything.

## How to Turn It On

1. Open **BarnCRM Settings**, then **Giving**. Under **Commitments and Installments**, open
   **Pledge Reminders**. This is the page where you write and watch the steps.
2. Write your steps (below) and choose your email templates. BarnCRM ships two to start from:
   **BarnCRM: pledge installment coming due** and **BarnCRM: pledge installment overdue**. Edit
   them, or write your own in Salesforce's email template editor.
3. Back in **BarnCRM Settings**, under **Commitments and Installments**, turn on **Send pledge
   reminders**. Until you do, the Pledge Reminders page says reminders are off.
4. Press **Send Reminders Now** to run once, or turn on **Run every night** on the Pledge
   Reminders page to have the run happen at 3:15 each morning. The nightly run only does
   anything while **Send Pledge Reminders** is on, so you can stop reminders at any time by
   clearing that setting.

## Steps

Choose **New Step** on the Pledge Reminders page. To change a step later, click **Edit** beside
it. Each step has:

- a **name**, which is also shown on each reminder it makes;
- **days from due date**: a negative number fires before the due date (`-7` is a week ahead),
  `0` fires on the due date, and a positive number fires after it (`14` is two weeks overdue);
- a **channel**: **Email** sends a templated email, **Letter** adds the installment to a merge
  file you print and post;
- an **email template**, chosen by name, required for an email step;
- **active**, so you can switch a step off without losing it.

### Which Step an Installment Gets

Each run looks at the installments still owed (Scheduled, Overdue or Partially paid) on an
**Active** pledge. A Paused, Completed or Cancelled pledge is never reminded about.

- **One step per installment per run: the latest one due.** An installment 15 days overdue, with
  steps at 7 and 14 days, gets the 14 day step, not both.
- **A step only fires for 14 days after its day.** So a night the run missed is made up the next
  night, and turning reminders on does not send a final notice about an installment that went
  overdue last spring.
- **A heads-up step stops on the due date.** A step with a negative days from due date applies
  only while today is before the installment's due date. Once the due date arrives it no longer
  fires, even within its 14 days.
- **A step never repeats for the same installment.** If a step's reminder went, the installment
  is not reminded by that step again, even if the run is repeated.

## Who Gets Each Reminder

An email goes to the pledge's donor, or to the organization's primary contact when the donor is
an organization. The template merges the person (`{!Contact.FirstName}`) and the installment
(`{!Installment__c.Due_Date__c}`, `{!Installment__c.Expected_Amount__c}`).

- A donor whose **Email Opt Out** is ticked, who has no email address, or whose email address
  bounced (Salesforce's **Email Bounced** flag) is reminded by letter instead, the same as for
  thank yous.
- A pledge with nobody to email (an organization with no primary contact) gets no reminder. The
  page counts these under **No donor email address** and the run names them in one Error Log
  entry.

## Letters

A letter step puts the installment in a queue. Press **Produce Letter File** to get a CSV, one
row per letter: pledge, installment, due date, amount still owed, days overdue, step, donor name,
greeting, and address. Merge it with your own letter in Word or Google Docs, print and post,
and then press **Mark Letters Sent**. Until you do, the letters stay queued, because BarnCRM
cannot tell whether anything was printed.

## The Log

Every reminder is a **Pledge Reminder** record, on the **Pledge Reminders Log** tab and in the
**Recent Reminders** list on the page: which pledge and installment, which step, the channel, the
status (Queued, Sent or Failed), when it went, and why it failed. List view **All Pledge
Reminders** is the full history.

A failed email keeps its row as history and is tried again by the next run while its step is
still recent. Each reminder row is claimed (Queued) before anything is sent. If Salesforce
refuses the whole send, every claimed email row is marked Failed with Salesforce's reason and
the next run retries it. If marking the rows Sent or Failed itself fails, each row is settled
again on its own with a fixed reason, so no email row is left Queued.

## A Five-Minute Walkthrough

1. Open **BarnCRM Settings**, then **Giving**, then **Pledge Reminders**. The page says
   reminders are off.
2. Choose **New Step**. Name it `Week late`, days from due date `7`, channel `Email`, and pick
   **BarnCRM: pledge installment overdue**. Save.
3. Choose **New Step** again. Name it `Final letter`, days from due date `30`, channel `Letter`.
   Save.
4. Create a pledge for a donor with an email address, starting seven days ago. Its first
   installment is seven days overdue.
5. Back in **BarnCRM Settings**, turn on **Send Pledge Reminders**. Return to the Pledge
   Reminders page: **Emails** reads 1.
6. Press **Send Reminders Now**. The log shows one reminder, `Week late`, by email, with its
   status, and the same row is on the **Pledge Reminders Log** tab. Press the button again:
   nothing new is sent.

## Common Mistakes

**Expecting a reminder the moment it is switched on for old installments.** A step fires for 14
days after its day. An installment that is months overdue is outside every step's window, so it
is left alone. Reminders on installments that are months overdue are a phone call, not a
template.

**A template that is no longer there.** If the template a step uses is deleted or switched off,
the page shows **Template not found** beside the step, and any reminder that tries to use it is
marked Failed with that reason rather than sending an empty message. Click **Edit** beside the
step and choose another template.

**Leaving the nightly run on after turning the setting off.** It does nothing while **Send
pledge reminders** is off. You can leave it scheduled.

**Steps that overlap.** Two steps on the same day: the first by name wins, and the other never
fires for that installment. Put them on different days.
