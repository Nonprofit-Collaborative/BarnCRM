# Interaction notes

**Feature:** C-39 Interaction notes
**Package:** Core
**Iteration:** v0.9

## What it does

When you meet someone, call them or visit them, the useful part is what was said, and it is
usually written down a few days later, if at all. An interaction note records it on the
person's page or the household's or organization's page: the day it happened, what kind of
interaction it was, who took part, and your notes. The note appears in the activity timeline
on the record, where everyone who works with that person reads it, and in the standard
Tasks and Events reports, so you can see who your team met last month.

An interaction note is an ordinary completed activity. There is no new tab, no new record to
learn, and nothing to keep in step: if your team already logs calls, notes appear beside them.

## How to turn it on

Interaction notes work as soon as Core is installed. There is nothing to switch on.

**Where the button is.** **Log an interaction** sits in the action bar at the top of the
packaged person page and the packaged household and organization page, in the **BarnCRM**
app, on the desktop and on the phone. If you do not see it, you are probably looking at the
record outside the **BarnCRM** app, or somebody has assigned a different record page in the
Lightning App Builder.

**Who can log one.** Anyone who can see the record and whose Salesforce user can create
tasks, which most users can. BarnCRM's permission sets do not change that: it comes with the
user's profile.

**Who can read one.** Anyone who can see the person or the account it is on. A note has no
privacy of its own. Do not write something in a note that the people who can open that
record should not read.

**Several people at one meeting (optional, Setup).** One note can name several people when
your org allows several people on one activity. That is a single org-wide platform setting a
package cannot change: Setup, **Activity Settings**, **Allow Users to Relate Multiple
Contacts to Tasks and Events**. It is on in most orgs. Without it, a note names one person;
log it from the household or organization page to cover everyone there.

## A five-minute walkthrough

Maria does this from the sample data.

1. Open the **BarnCRM** app, click the **Contacts** tab, and open any sample person.
2. Click **Log an interaction** in the action bar. A window opens with **Date** set to today
   and **Type** set to **Meeting**. The note is saved as completed, so it is history, not a
   to-do.
3. Type a **Subject**, for example `Coffee to talk about the spring project`. Change **Date** to
   last Friday, when the coffee happened. Leave **Type** as **Meeting**, or choose **Call** if it
   was a phone call.
4. In **Comments**, write two or three lines about what was said and what you agreed.
   **Assigned To** is you; change it if you are writing the note for a colleague who held the
   meeting.
5. Click **Save**. The note appears under **Past Activity** in the activity timeline on the
   right, dated last Friday.
6. Open the person's household. The same note is in the household's activity timeline.
7. On the household, click **Log an interaction**, choose a member of the household in
   **Name**, and save a second note. It appears on the household and on that person.
8. To see everything your team logged: open **Reports**, click **New Report**, choose
   **Tasks and Events**, and filter on **Status** equals Completed and **Type** equals Meeting
   (add Call or other kinds you use), with **Date** in the range you want. Group by
   **Assigned** to see who met with whom.
9. If the meeting needs a follow-up, use **New Task** in the activity panel. A next step is
   an open task with a due date, not a line in the note, so it lands in someone's task list.

## Common mistakes

- **The note is dated today, not the day of the meeting.** The date defaults to today so a
  note written right after a call needs no change. When you write it later, change **Date**
  before you save. To fix a saved note, open it from the timeline and edit the date.
- **The note shows on the person but not on their household.** When your org records
  household membership the flexible way (household member records), a person's own page
  points at their employer or at nothing, not at their household, so a note logged on the
  person shows there. Log notes about the household from the household page and choose the
  person in **Name**.
- **Saving says a value is not allowed, or the note appears as open.** Your org has removed
  or renamed **Meeting** in the activity **Type** list, or **Completed** in the task
  **Status** list. Choose another Type in the window, or ask Maria to restore the value
  (Setup, Object Manager, Task, Fields).
- **Somebody read a note they should not have.** Notes follow the record. Edit the note to
  remove what should not be there, and keep sensitive matters out of notes.

## Field reference

For a report builder only. An interaction note is a Task.

| What you see | Task field |
|---|---|
| Subject | Subject |
| Date | Due Date (`ActivityDate`) |
| Type | Type |
| Comments | Comments (`Description`) |
| Assigned To | Assigned To (`OwnerId`) |
| Name | Name (`WhoId`) |
| Related To | Related To (`WhatId`) |
