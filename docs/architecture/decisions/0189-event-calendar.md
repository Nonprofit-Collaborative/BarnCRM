# ADR-0189: Event calendar: a month, week and list view of events and sessions on its own tab, filters in the browser, and a calendar file built in the browser

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan Section 5.12 (EV-19), D-186, D-123, Section 4 and ADR-0013 (Platform-only, no
outside callouts), Section 9.9 (portability); builds on ADR-0177 `0177-events-module.md`
(decisions 4 and 6) and ADR-0162 `0162-funders-restricted-funds-schedules-calendar.md` decision 8
(the month grid pattern).

## Context

The Events Home page lists upcoming and past events. EV-19 asks for a calendar of events, and
optionally sessions, as a month, a week or a list, filtered by status and type, with a click
through to the record and an optional .ics file per event made in the browser. It must call no
outside service and add nothing to the data model.

## Decision

1. **Its own tab, no new data.** A tab `Events_Calendar` ("Event Calendar", an app page
   `Events_Calendar` holding the component `eventCalendar`) sits beside Events Home in the BarnCRM
   Events app, in the Events module's staff tabs, with the `Events_Admin`, `Events_Staff` and
   `Events_Read_Only` sets given the tab and the controller. No object or field is added: it
   reads `Event__c` and `Event_Session__c`.
2. **A thin controller that reads the days asked for.** `EventCalendarController.getCalendar`
   takes the first and last day the view shows and whether to read sessions, and returns plain
   rows for the events that overlap those days (and sessions that do, each with its event's
   name, status and format). It reads one day more on each side, so the day an entry falls on in
   the person's own time zone is always inside what was read, and it never reads more than 500
   events or 1,000 sessions, saying so when it stopped. Reads are `WITH USER_MODE`: the Events
   sets decide what a person sees.
3. **Everything else is framework-free.** `eventCalendarModel.js` (plan 9.9) works out the days
   each view shows (a month as whole weeks, a week, a list of the month's busy days), the day an
   entry falls on in the time zone, a multi-day entry on every day it spans, the filters and the
   .ics text, so a WordPress calendar can reuse it. The component only draws.
4. **Filters are in the browser.** Status (Draft, Open, Closed, Completed, Cancelled) and Format
   (In Person, Virtual, Hybrid) narrow what was read without another call; a session is filtered
   by its event's status and format, so a cancelled event's sessions go with it. "Type" in the
   brief is the event's format; a session also shows its own type (Talk, Workshop and so on) as
   the label. Sessions are off by default and read only once Show Sessions is turned on, since
   a conference carries many.
5. **The calendar file is made in the browser.** Each row of the list view has a download button:
   `icsFor` writes an RFC 5545 file (one VEVENT with a stable UID, UTC start and end, summary,
   location from the venue or the online link, description, URL and STATUS: Cancelled is
   CANCELLED, Draft is TENTATIVE, otherwise CONFIRMED; text escaped and lines folded at 75 octets,
   never inside a character), and the component hands it to the person as a Blob download. A
   session's file is named for the session and its event. Nothing is sent anywhere and nothing is
   stored.
6. **Accessible and printable.** An entry is a button that opens its record; a cancelled entry
   is struck through as well as labelled; the month grid becomes a list of busy days at phone
   width; the buttons are hidden when printed. All prose is in the help catalog.

## Alternatives considered

- **A view toggle on Events Home.** Rejected: Events Home is a list with row actions and Repeat
  Event; a calendar with its own range, filters and views is a separate page, as Funders keeps
  its Grant Calendar beside its pipeline.
- **A calendar library or Salesforce's calendar component.** Rejected: no outside service, no
  new dependency, and the model is needed anyway for filters and the file.
- **A subscription feed (a URL that serves .ics).** Rejected: it needs a public endpoint, which
  is the guest-user design ADR-0177 decision 10 keeps for a later item.
- **Downloading a file for a whole filtered view.** Not built: one file per entry is what the
  brief names; the model's `icsFor` already takes a list if it is wanted later.

## Consequences

- A view reads the server once per month, week or list change and once when Show Sessions
  changes; filters never read.
- The module's staff tabs gain one entry and the tab icon registry one (Custom66).
- Entries with no start (a session with no time) are not on the calendar.
