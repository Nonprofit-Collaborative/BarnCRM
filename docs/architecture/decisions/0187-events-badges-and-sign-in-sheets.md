# ADR-0187: Event Management badges and sign-in sheets

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan Section 5.12 (EV-17), Section 6.0a (D-186: release 1.3), ADR-0182
`0182-event-registrations.md` (attendees), the Check-In tab (EV-12, QR codes), Section 9.9
(portability), Section 4 (no outside services in the core path).

## Context

Staff print name badges and a sign-in sheet for the door. BarnCRM must not call an outside service,
and no PDF library is bundled. The Check-In tab already draws QR codes in the browser with the
static resource `BarnQrCode`, and a QR code holds the attendee's record identifier.

## Decision

1. **No new object or field.** Badges and sheets are made from attendees (Registered or Attended),
   their ticket type and the person's organization (the Contact's account name), and the event's
   sessions. Nothing is stored.
2. **Pages are built as HTML text in the browser and printed there.** `eventBadgesModel.js`
   (framework-free, plan 9.9) returns a complete HTML page with its own print CSS (`@page`, page
   breaks kept off the middle of a badge or row). The Badges tab opens it in a new window from a
   Blob address and calls the browser's print. No PDF library, no server rendering, no outside
   service. If the browser blocks the window the tab says so.
3. **Three badge sizes:** Large (4 x 3 in), Standard (4 x 2 in, the default) and Compact
   (3.375 x 2.33 in). Each shows the name; organization, ticket type and a QR code are switches.
   The QR code is the attendee's record identifier, the same code Check-In reads, drawn by
   `BarnQrCode`.
4. **Sign-in sheets for the event or one session.** A table of name, organization and ticket with
   a signature column, ten blank lines for people who were not registered, a heading with the
   event or session name, time and place. Sessions have no attendance of their own in the
   module, so a session's sheet lists everyone registered for the event.
5. **Every value put in a page is escaped** in the model, so a name that holds markup prints as
   text.
6. **Read access is enough.** Printing reads attendees; Events Read Only may print.

## Alternatives considered

- **A PDF library.** Rejected: nothing in the repo ships one and the browser prints well.
- **Print CSS on the Lightning page.** Rejected: the surrounding page cannot be reliably hidden
  from inside a component, so a separate window is the dependable route.
- **Per-session registration.** Out of scope: attendees belong to the event.

## Consequences

- One Apex class (reads), one tab, one framework-free module; no object, setting or job.
- The QR drawing library already ships in the package; no new third-party code.
