# ADR-NEXT: The BarnCRM Event Management module: its own package on Core, events with ticket types, tracks, sessions and speakers, and room for registration, sponsorship and check-in

**Status:** Accepted (builder decision)
**Date:** 2026-11-06
**Source:** plan Section 5.12 (EV-01 to EV-15), Section 6.0a releases 1.2 and 1.3 (D-155, D-156,
D-177), D-123, Section 1.5 (no payments), Section 4 and ADR-0013 (Platform-only), Section 9.9
(portability); builds on ADR-0014, ADR-0017, ADR-0024, ADR-0124, ADR-0131, ADR-0154 and ADR-0161.

## Context

Event Management (plan Section 5.12, owner request D-123) runs an organization's events, from a
single evening talk to a community "Dreamin" conference with tracks, sessions, speakers, a call for
speakers, volunteers and sponsors. It is "similar to Summit Event App but easier to use and more
full feature" and keeps Summit Events compatibility (EV-10). Release 1.2 (D-177) builds EV-01
(events), EV-03 (ticket types), EV-04 (tracks, sessions and agenda) and EV-05 (speakers), then
EV-02 (registrations on the Forms engine), EV-08 (volunteer shifts), EV-10 and EV-14 (reminders and
No-Show); release 1.3 adds EV-06 (call for speakers), EV-09 (sponsorship), EV-11 (dashboard and
conference template), EV-12 (check-in) and EV-15 (appointments). EV-13 (gala seating) is later.
Plan Section 6.0a asks for an ADR before each new module; this one covers the whole module's data
model so the later items fit it: decisions 1 to 7 are built now, decisions 8 to 14 are designed
now and built by their items.

Constraints from the plan: Core is the only dependency (Volunteers, Giving, Funders, Forms and
Portal Builder are optional links); no Campaign dependency; BarnCRM takes no payments; public
pages need a guest-user security design of their own.

## Decision

1. **Its own package, Core only, both editions.** `packages/events`, package
   `BarnCRM Event Management`, depends on BarnCRM Core alone. Core ships the catalog row
   `BarnCRM_Module.Events` (editions `Standard;Nonprofit`, as the plan's packaging table proposes
   for Event Management; Sort Order 45), so the module key is `Events` and the classes Core finds
   by name are `EventsAccessSync` and `EventsPostInstall`. The app is BarnCRM Events; the help
   catalog is `BarnHelp_Events`. No object of another module is named anywhere in the package.
2. **The event.** `Event__c` (canonical model 29EV1): name, status (Draft, Open, Closed,
   Completed, Cancelled), format (In Person, Virtual, Hybrid), start and end as date and time,
   venue name and address, online link, capacity, registration open and close times and a
   description. A multi-day event is one event with a start and an end on different days. A
   recurring event is a series: Repeat Event (on the Events page) creates the later occurrences as
   events of their own, each pointing at the first through `Series__c`, with the first event's
   ticket types and tracks copied. Each occurrence then lives on its own (its own registrations,
   capacity and agenda), which is what a monthly class or a yearly conference needs; there is no
   repeat rule kept on the record to keep in step.
3. **Ticket types and promo codes (EV-03).** `Ticket_Type__c` (29EV2, a detail of the event):
   price, quantity (empty for no limit), sales start and end, active, sort order. `Promo_Code__c`
   (29EV3, a detail of the event): the code, a percent or amount off, an optional ticket type it is
   limited to, a use limit and valid dates. A code is unique within its event, regardless of case:
   an automation that always runs (registry row `Promo_Code_Key`, ADR-0024) sets the unique
   `Code_Key__c`. Prices are what the organization charges; BarnCRM takes no payment (Section 1.5).
   The price a registrant owes with a code applied is worked out by the framework-free module
   `eventTickets.js` (plan 9.9), shared by the staff pages now and registration (EV-02) later.
4. **Tracks, sessions and the agenda (EV-04).** `Event_Track__c` (29EV4, a detail of the event)
   and `Event_Session__c` (29EV5, a detail of the event, with an optional track): start and end,
   room (text: a room is a name on the agenda, not a record to manage), capacity, type (Talk,
   Workshop, Panel, Keynote, Break, Other) and status (Draft, Confirmed, Cancelled). Programs
   already owns `Session__c`, so the event's object is `Event_Session__c`. Validation rules keep a
   session's end after its start, inside the event's dates, and its track in its own event. The
   **Agenda Builder** on the event page lists sessions by track and day; a session moves to
   another track by its menu, by drag and drop (c/barnDrag) or by keyboard, and the builder flags
   two sessions in one room, or one speaker in two sessions, at the same time. Session sign-up
   (EV-04's "sign-up") needs attendees, so it is built with EV-02 as `Session_Signup__c`
   (decision 8).
5. **Speakers on Core people (EV-05).** `Event_Speaker__c` (29EV6, a detail of the event) names
   the Core person (`Contact__c`, required), with a headline, bio, status (Invited, Confirmed,
   Declined, Cancelled) and travel and audiovisual needs. `Session_Speaker__c` (29EV7) joins a
   speaker to a session, with a role (Speaker, Moderator, Panelist); it is a detail of the session
   with a lookup to the speaker (a junction under two objects that are themselves details is
   avoided), and the Speakers panel removes a speaker's assignments before the speaker. A person
   speaks once per event
   and once per session: automations that always run (`Event_Speaker_Key`, `Session_Speaker_Key`)
   set unique key fields. A validation rule keeps a session's speaker in the session's own event.
6. **Staff pages.** The **Events** tab (an app page) lists upcoming, draft and past events with
   New Event and Repeat Event; the event record page uses Core's header, main and sidebar template
   with tabs (Overview, Tickets, Agenda, Speakers, Details) and the related lists in the sidebar.
   Every panel's Apex controller is thin and returns plain JSON shapes; grouping, conflict checks,
   series dates and prices run in framework-free modules (plan 9.9).
7. **Access.** `Events_Admin` (everything) to holders of `BarnCRM_Admin`; `Events_Staff` (create
   and edit events, ticket types, promo codes, tracks, sessions and speakers; delete everything but
   an event) to the Team Member (`Program_Staff`), Coordinator (`Volunteer_Coordinator`) and
   Fundraising Staff roles; `Events_Read_Only` to the Read Only role. Given by `EventsAccessSync`
   on the ADR-0131 pattern, never taken away. Event objects are Public Read/Write: they describe
   the organization's own events, not people.
8. **Registrations and attendees (EV-02).** `Event_Registration__c` (one booking: the event, the
   person who registered, status Registered, Waitlisted or Cancelled, the promo code, the amount
   owed, the source) and `Event_Attendee__c` (one person attending, a detail of the registration:
   the Core person, the ticket type, status Registered, Waitlisted, Cancelled, Attended or No-Show).
   Registrants are matched to Core people through Core's matching, household-aware, never creating
   a duplicate. Registration uses the Forms engine (C-42a) through the Core extension point that
   module adds, when Forms is installed, and a simple built-in registration otherwise; a Forms
   submission is named on the registration by its record identifier as text (ADR-0014), never a
   lookup. `Session_Signup__c` joins an attendee to a session, within its capacity. Registration
   and attendee records hold personal data, so they are Private, with access through the event's
   owner and the Events sets; EV-02 settles the details. Ticket and code counts (sold, used) are
   roll-up summaries or a handler on these objects.
9. **No payments, no Campaign.** BarnCRM records what is owed and never takes a payment: a payment
   made through the organization's own processor is recorded through Mirror's inbound gift API
   (X-03) when Giving is installed, and the registration keeps the gift's record identifier as
   text. No Campaign is used; Campaign sync, if wanted, belongs in Mirror (ADR-0013).
10. **Public pages later.** Nothing in the module is shared with a guest user now. A public event
    page and public registration (EV-01, EV-02) wait on a guest-user security design in their own
    ADR, built on the Forms module's public forms (C-42b) and Portal Builder (EV-07, PB-07) where
    they fit.
11. **Call for speakers and sponsorship (EV-06, EV-09).** `Speaker_Application__c` (a person's
    proposal for an event: title, abstract, track, status) with `Speaker_Review__c` (one reviewer's
    score and note), the same review pattern as SG-03 with no dependency on it; an accepted
    application creates the speaker and a draft session. `Sponsorship_Level__c` (the event's tiers
    with amount and benefits), `Event_Sponsor__c` (an organization, a Core Account, at a level, with
    status) and `Sponsor_Deliverable__c` (logo, booth, passes, each with status). A sponsor's Giving
    gift or commitment, or a Funders award, is named by record identifier as text.
12. **Volunteers through Core (EV-08).** Event volunteer jobs and shifts live in Volunteers. Core
    gains an extension point (an interface Events calls by name, implemented in Volunteers, the
    ADR-0017 pattern) that lists and creates shifts for an event identifier; Volunteers stores the
    event's record identifier as text. With Volunteers absent, the event page shows no volunteer
    panel. Events never names a Volunteers object.
13. **Check-in, reminders and appointments (EV-12, EV-14, EV-15).** Check-in adds a check-in time
    and a random check-in code to the attendee (QR codes drawn in the browser, no outside service);
    a walk-in is a registration made at the door. Reminders and follow-ups are a nightly job step
    (ADR-0166) with a lead time setting and a sent stamp on the attendee; No-Show is an attendee
    status set after the event for those not checked in. Appointments are `Event_Appointment__c`
    (a host, a person, a time slot).
14. **Summit Events compatibility (EV-10).** The objects map onto Summit's: Summit Event and
    Instance to Event, Instance Session to Event Session, Registration to Event Registration and
    Event Attendee. Summit registrants land in Core people through Core's matching; a registrant
    that is a Lead is matched only in Mirror or a small adapter (the standard-object rule).

## Alternatives considered

- **Event as a Campaign.** Rejected: Campaign is a standard object outside Mirror (ADR-0013), and
  a Platform-only org has none.
- **`Session__c` for event sessions.** Rejected: Programs owns the name, and the two mean
  different things (a program meeting with attendance, a conference talk with speakers).
- **A room object.** Rejected for now: nothing needs room records (capacity lives on the session);
  a room name on the session drives the agenda and the room conflict check.
- **A repeat rule on the event, regenerated like Programs' session schedules (ADR-0171).**
  Rejected: an occurrence of an event has its own registrations and agenda, so a rule that
  rewrites occurrences would fight the staff who edit them.
- **Speakers as a field on the session.** Rejected: a speaker has needs and a bio per event,
  speaks in several sessions, and EV-06 and EV-07 (the speaker portal) need a speaker record.

## Consequences

- Seven custom objects now, about seven more with EV-02, EV-06 and EV-09.
- Deleting an event deletes its ticket types, codes, tracks, sessions and speakers (master-detail).
  Only Events Admin deletes an event.
- The module is offered in both editions (ADR-0124); no Opportunity, Campaign, Case or Lead is
  used, and it runs on a Platform-only org.
