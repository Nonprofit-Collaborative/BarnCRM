# ADR-0182: Event registrations and attendees, reminders and No-Show, and the Summit Events adapter

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan Section 5.12 (EV-02, EV-10, EV-14), Section 6.0a release 1.2 (D-123, D-156,
D-177), Section 1.5 (no payments), Section 4 and ADR-0013 (standard-object rule), Section 9.9
(portability); settles the details ADR-0177 `0177-events-module.md` decisions 8, 13 and 14 leave
to these items; uses ADR-0175 `0175-forms-module.md` decision 9 (the Core form seam) and ADR-0166
(nightly run).

## Context

ADR-0177 designs `Event_Registration__c` and `Event_Attendee__c` and leaves EV-02 to settle their
sharing and how registrants are matched; it puts reminders and No-Show in the nightly run and
maps Summit Events onto BarnCRM's objects. Event Management depends on Core only, so it must work
when Forms is absent, and Summit Events is a package many orgs do not have.

## Decision

1. **Two objects, Private.** `Event_Registration__c` (canonical model 29EV8: the event, the person
   who registered, status Registered, Waitlisted or Cancelled, the promo code, the amount owed, the
   source, the Forms submission's identifier as text, an external key) and `Event_Attendee__c`
   (29EV9, a detail of the registration: the Core person, the ticket type, the price, status
   Registered, Waitlisted, Cancelled, Attended or No-Show). The registration looks the event up
   (not master-detail), so its sharing is its own: **Private**. The Events permission sets carry
   View All on both objects (Read Only and Staff) and Modify All (Staff and Admin): only people
   with an Events set see who registered, which is what ADR-0177 asks for personal data.
2. **One registration service, Core's matcher.** `EventRegistrationService` takes a registrant
   (a chosen Core person, or first name, last name, email and postal code) and its attendees and
   writes everything under one savepoint, in user mode. A person is found as Forms finds one
   (ADR-0175 decision 7): by email, then by last name and postal code, each narrowed by first
   name, then by the org's duplicate rules; a key held by several people is never guessed (the
   registration is refused and staff pick the person). Nobody found means a new Contact, whose
   household Core makes as for any new person. **Household-aware:** a guest is first looked for
   among the registrant's household members by first and last name, then by email; a new guest is
   created in the registrant's household (Contact membership mode; in Junction mode Core makes
   the household as usual). A person already holding an attendee on the event that is not
   cancelled is never added twice: the existing attendee is reported instead.
3. **Prices, codes, capacity and the waitlist.** The ticket type must be active and on the event;
   a code must be the event's, active, inside its dates, for the ticket (or any ticket) and under
   its use limit (uses are the event's registrations with that code that are not cancelled). The
   price with a code applied follows `eventTicketsModel.js` (R-PC5); Apex repeats the same rule
   because a Forms submission is processed on the server, and both are tested against the same
   cases. Seats taken are the event's attendees Registered, Attended or No-Show. While the event's
   capacity or the ticket's quantity has no seat left, an attendee is **Waitlisted**; a
   registration is Waitlisted when all its attendees are. The event row is locked while seats are
   counted, so two registrations at once never take the last seat twice. **Move Off Waitlist**
   checks the seats again; nothing is promoted automatically.
4. **Forms through the Core seam, built-in registration otherwise.** `EventFormAttachment`
   implements Core's `FormAttachmentExtension` and is registered in
   `FormAttachmentExtensions.EXTENSION_CLASSES`. An event names its registration form by the
   form's record identifier as text (`Registration_Form_Key__c`, ADR-0014); a processed
   submission filled from the event registers the person Forms matched, with the answers
   `ticketType` (a ticket type's name or identifier) and `promoCode`, source Form and the
   submission's identifier. Without Forms the field is unused and staff register people on the
   **Registrations** tab, which always works.
5. **Check-in and attendance (EV-02 part).** Staff mark an attendee Attended or No-Show from the
   Registrations tab; EV-12 adds the check-in time and code.
6. **Reminders, follow-ups and No-Show (EV-14).** `Events_Settings__c` (hierarchy, org-wide) holds
   reminders on or off, the lead days (1 to 30, default 2), the reminder template, follow-ups on
   or off, the follow-up template and whether attendees still Registered after an event become
   No-Show. Templates are named by developer name (no lookup to a template is possible, the
   ADR-0032 pattern); the module ships one of each as the defaults. One nightly step (ADR-0166,
   `EventsNightlyJobProvider`, 7:30 AM) emails reminders to attendees Registered for an Open or
   Closed event starting inside the lead time, follow-ups to attendees marked Attended of an event
   that ended within the last seven days, and marks No-Show, each once (a sent stamp on the
   attendee, stamped before sending and cleared on a failed send, as V-10 does). Mail goes
   through Core's `EmailSender` with the person as the target and the attendee as the record, so
   the org's limits apply; a person with Email Opt Out or no email is skipped. Reminders and
   follow-ups ship off, No-Show marking ships off (an org that does not check people in would
   otherwise see everyone as No-Show).
7. **Summit Events adapter (EV-10), inactive without Summit.** `SummitEventsAdapter` reads Summit's
   objects by name only (dynamic SOQL, no reference the compiler checks), so the package installs
   and runs with no Summit; with Summit absent it does nothing and its nightly step is not listed.
   With Summit present, a 7:15 AM nightly step (before the reminders) takes every Summit
   registration the first time and afterwards those changed in the last two days, leaving out
   Started and Cancelled ones: each Summit event instance becomes an event (keyed by
   `Event__c.External_Key__c`), each registration a registration and one attendee (keyed by
   `External_Key__c`, imported once; Summit's Attended or No Show is kept, and later changes are
   made in BarnCRM), and the registrant
   lands in Core people through decision 2's matching, never a duplicate. The matched person is
   written back to Summit's contact field when it is blank. Summit's own Lead handling is not
   touched: no Lead is read or written in this package (the standard-object rule); Lead matching,
   if ever wanted, belongs in Mirror.

## Alternatives considered

- **Registration as a master-detail of the event.** Rejected: it would make the records Public
  Read/Write through the event, and registrations hold personal data.
- **A matcher of Events' own.** Rejected: Core's matcher (ADR-0175 decision 7) is the one rule.
- **Automatic promotion from the waitlist.** Rejected for now: a seat freed late may not suit the
  next person; staff choose.
- **A Summit dependency or a Mirror-only adapter.** Rejected: a dependency breaks installs without
  Summit; Summit's objects are custom, not standard, so the rule that keeps standard objects in
  Mirror does not apply to them, and keeping the adapter beside the objects it fills is simpler.

## Consequences

- Two objects now (`Session_Signup__c` from ADR-0177 decision 8 waits for its own item).
- A Forms submission that cannot be registered (an unknown ticket, a bad code) is rolled back
  for the extension only and marked for review by Forms; the person Forms wrote stays.
- Reminder and follow-up mail counts against the org's daily single email limit.
