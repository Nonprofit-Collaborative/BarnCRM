# ADR-0089: Interaction notes are completed tasks logged through one packaged action

**Status:** Accepted (builder decision)
**Date:** 2026-10-12
**Source:** plan Section 5.1 feature C-39 and Section 3.4 item 4; builds on ADR-0042 (activities,
not Chatter), ADR-0043 (actions the package owns are placed on the page), ADR-0059 (Core is
neutral) and ADR-0013 (Core runs on a Platform-only org)

## Context

C-39 asks for interaction notes on people and accounts: a lightweight version of Nonprofit
Cloud's Interaction Summaries, the "contact report" a staff member writes after a meeting or a
call with someone the organization is building a relationship with. The plan says no more than
that, so the question is how little has to be built.

Interaction Summaries carry: a date, a purpose or kind of interaction, the notes, the staff
member, the people who took part, the account, next steps, and a confidentiality setting that
narrows who can read a summary.

The platform already has a record for "something a staff member did with a person, on a date,
with notes": a completed Task. ADR-0042 made the activity panel the one place to record a call,
a task or a note about a record, and the panel is already on the packaged Account and Contact
pages. Tasks run on Platform licenses, so Core may use them (ADR-0013).

What breaks if staff use the standard **Log a Call** action with nothing packaged:

1. **The date.** Log a Call stamps today. A note written on Monday about Friday's lunch is
   dated Monday, and a report of "who did we see last month" is wrong. Adding the date to Log a
   Call's layout is a Setup change to a standard global action, which a package cannot ship.
2. **The kind of interaction.** Log a Call records every note as a call and does not show Type,
   so a visit cannot be told from a phone call in a report.
3. **Placement.** On the packaged pages the activity panel takes its actions from the page
   layout the org assigns, which the package does not control (ADR-0043). On the Account page's
   fallback layout the action list carries no activity actions at all.

What breaks with Enhanced Notes (`ContentNote`) instead: a note has no date of its own beyond
its creation, no kind, no staff member other than its creator, cannot carry a custom field, is
not on the activity timeline, and reports on it are poor. It fails the reporting half of the
need.

What standard tasks cannot do: hide one note from someone who can see the person. A task's
visibility follows the record it is on, and the platform has no private task on a record. That
is the one part of Interaction Summaries a task cannot copy. The plan does not ask for it; it is
recorded as an owner question rather than built.

## Decision

1. **An interaction note is a completed Task.** No object, no field on Task or Activity, and no
   automation on Task is added, the same line G-15 drew for stewardship tasks. The parts map to
   standard fields: Date to `ActivityDate`, kind to `Type`, notes to `Description`, staff member
   to `OwnerId`, the people to `WhoId` (several people where the org relates multiple contacts to
   tasks), the account to `WhatId` or the platform-derived `AccountId`. Next steps are an open
   task, which the activity panel's follow-up already creates.
2. **Core ships one action per page, "Log an interaction".** `Contact.Log_Interaction`
   (parent field Who) and `Account.Log_Interaction` (parent field What) are Create actions on
   Task. Each shows Subject, Date, Type, Name, Assigned To and Comments, and fills in Status
   Completed, Date today (editable) and Type Meeting (editable).
3. **The actions are placed with Dynamic Actions on the packaged record pages** (ADR-0043):
   after Edit on `Account_Record_Page` for every record type, and on `Contact_Record_Page`, which
   gains Dynamic Actions with Edit, Log an interaction and Delete, the same set the Account page
   already ships. The Account fallback layout lists the action too, as it lists Merge or split.
4. **Wording is neutral** (ADR-0059): "interaction", never donor, gift or fundraising wording.
5. **Notes are read where they already are:** the activity timeline on the person and the
   account, and the standard Tasks and Events report type. No report or list view is shipped.

## Alternatives considered

- **A custom Interaction Note object** with its own sharing. Rejected for now: it copies the
  Task fields, needs its own page, tab, permissions, reports and a second history beside the
  activity timeline (the split ADR-0042 removed), and the one thing it adds, per-note
  confidentiality, also needs sharing rules a package cannot ship as configuration an org can
  rely on. Revisit if the owner wants confidential notes.
- **A packaged field on Task** (for example an "is interaction note" flag or a purpose
  picklist). Rejected: Type already says what kind of interaction it was, and every packaged
  field on Activity is shared by every task and event in the org.
- **Enhanced Notes.** Rejected: no date, kind or reporting (see Context).
- **Ship nothing and document Log a Call.** Rejected: the date and the kind are the two facts a
  report of interactions needs, and both need a Setup change without the action.
- **Ship a report.** Rejected for now: the standard report type answers it in a minute, and Core
  ships no reports folder; the admin guide shows the filter.

## Consequences

- An interaction note follows its record's sharing. Anyone who can see the person or the
  account can read the note. The admin guide says so.
- Type Meeting comes from the platform's default Type values. An org that removed Meeting, or
  renamed Completed in Task Status, sees the action fill a value the org no longer offers; an
  org run confirms the behavior, and the admin guide names the fix.
- In junction mode a person's contact points at their employer or at nothing, not at their
  household, so a note logged on the person shows on that account's timeline. Staff who want a
  note on the household log it from the household and pick the person.
- The Contact page's header now shows the packaged actions (Edit, Log an interaction, Delete)
  rather than the org's layout actions, as the Account page already does. An org that wants
  more actions there assigns its own page. The activity panel still takes its actions from the
  org's layout.
- Several people per note needs the org setting that relates multiple contacts to tasks, which
  is org-wide and outside what a package can set.
