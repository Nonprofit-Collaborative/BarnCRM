# ADR-0186: Event Management gala tables and seating

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan Section 5.12 (EV-13), Section 6.0a (D-156, D-186: moved up to release 1.3),
ADR-0177 decision 8 (Event Management objects), ADR-0181 `0181-events-sponsorship.md` (sponsors),
ADR-0182 `0182-event-registrations.md` (registrations and attendees), Section 4 and ADR-0013
(modules depend on Core only), Section 9.9 (portability).

## Context

A gala needs people at tables: tables with a number of seats and a host, guests assigned so that
people who came together sit together, a warning when a table is overfull, the dietary and access
needs the venue must know, tables a sponsor has bought, and a chart to send to the caterer.
Registrations and attendees already exist (ADR-0182); sponsors exist (ADR-0181).

## Decision

1. **One new object, `Event_Table__c` (canonical model 29EV26).** Master-detail to the event
   (Controlled by Parent, so it follows the event's sharing), a name, a required Capacity, a Host
   (lookup to Contact, Clear on delete) and an optional Sponsor (lookup to `Event_Sponsor__c`,
   Clear on delete). A table is never required to be a sponsor table.
2. **Three fields on the attendee.** `Event_Table__c` (lookup, Clear on delete, so removing a table
   leaves its guests registered with no table), `Dietary_Needs__c` and `Access_Needs__c` (Text 255,
   plain words). They live on the attendee, not the registration, because needs belong to a person.
3. **A party is a registration.** The people on one registration are a party. Seating a person moves
   the whole party to the table unless **Keep Party Together** is turned off; a household outside
   the registration is not inferred, because Core's household model varies by mode and the
   registration is the booking the guests made together.
4. **Over capacity warns, never refuses.** A table may hold more people than its seats (a host
   squeezes a chair in). The tab flags it on the chart and in a toast. The rule is arithmetic in
   `eventSeatingModel.js`, not Apex.
5. **Suggest Seating is deterministic and leaves sponsor tables alone.** It places whole parties,
   largest first, at the first non-sponsor table with room for the party (a part-seated party
   joins its table when it fits) and reports who did not fit. It never fills a sponsor table: those
   seats are for the sponsor's own guests.
6. **Seated guests are those Registered or Attended.** Waitlisted, Cancelled and No-Show attendees
   have no seat to assign.
7. **Thin Apex, framework-free logic, export in the browser.** `EventSeatingController` lists and
   writes in user mode; counts, parties, the suggestion and the CSV are in `eventSeatingModel`
   (plan 9.9). CSV cells that start with `=`, `+`, `-` or `@` are prefixed so a spreadsheet does
   not run them as formulas.
8. **No cross-module dependency.** Sponsors are in the same package. Nothing here touches another
   module.

## Alternatives considered

- **Seat on the registration.** Rejected: guests of one registration may sit apart on purpose.
- **Refuse over-capacity.** Rejected: staff need the override and the warning is enough.
- **Seat assignments as a junction object.** Rejected: one table per person, so a lookup is the
  smaller design.

## Consequences

- One object and three fields; no setting, no scheduled work.
- Deleting an event deletes its tables; deleting a table clears its guests' tables.
- The Events permission sets carry the object and fields (Read Only reads; Staff and Admin edit).
