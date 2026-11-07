# ADR-NEXT: Event volunteer jobs and shifts live in Volunteers, reached from Event Management through a Core extension point

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan Section 5.12 (EV-08), Section 6.0a release 1.2 (D-155, D-177), D-123, Section 4
and ADR-0013 (modules depend on Core only); builds on ADR-0017 (cross-package mechanisms) and
ADR-0177 decision 12.

## Context

An event needs volunteers: a registration desk, AV help, setup and teardown, each with shifts and
a number of people wanted. Volunteers already owns jobs, shifts, sign-ups and hours. ADR-0177
decision 12 settled the shape: Events never names a Volunteers object, Volunteers never names an
Events object, and with Volunteers absent the event page shows no volunteer panel. It left the
interface to this item.

## Decision

1. **A Core interface, `EventVolunteerExtension`,** with three calls: `jobsFor(eventKey)` (the
   event's jobs, each with its shifts in time order), `createJob(eventKey, name, description)` and
   `createShift(jobId, startTime, endTime, needed)`. The value classes `EventVolunteerJob` and
   `EventVolunteerShift` are plain Core classes, so neither module needs the other's types.
2. **Found by name,** by `EventVolunteerExtensions` (the `FormAttachmentExtensions` and
   `HealthCheckExtensions` mechanism, ADR-0017): `NamespaceUtil.resolveType`, an absent, unbuildable
   or wrong-typed class is absent and logged. Listing never fails the event page; creating reports
   its failure to the person who asked.
3. **Volunteers implements it** (`VolunteersEventExtension`) and stores the event as text:
   `Volunteer_Job__c.Event_Key__c`, the event's record identifier (an external ID, never a
   lookup, ADR-0014). Shifts are ordinary `Volunteer_Shift__c` records, so sign-up, reminders,
   hours and totals work on them unchanged.
4. **User mode throughout.** Volunteers' own permission sets decide who may list or add; a person
   without them sees the section but cannot add, and is told so in plain words.
5. **The Events panel is a section of the Details tab,** `eventVolunteers`, drawing nothing when
   `EventVolunteerExtensions.isAvailable()` is false. No label, no tab and no Events field names
   Volunteers.
6. **A shift outside the event's dates only warns.** Setup the day before and teardown the day
   after are ordinary; the event's own date rules are not applied to volunteer shifts.

## Alternatives considered

- **A lookup from the job to the event.** Rejected: it makes Volunteers depend on Events.
- **Events creating `Volunteer_Job__c` records itself.** Rejected: Events would name a Volunteers
  object and fail to deploy without Volunteers.
- **Volunteers reading `Event__c`.** Rejected: the same dependency the other way.

## Consequences

- One field added to Volunteers (`Event_Key__c`), one class added to Volunteers
  (`VolunteersEventExtension`) and four to Core.
- An event's volunteer jobs are found by the event's identifier, so deleting an event leaves its
  jobs in Volunteers (they hold history); Volunteers' own pages manage them.
- Other modules wanting the same (a gala, a program) can register their own key on the same seam
  later without a new object.
