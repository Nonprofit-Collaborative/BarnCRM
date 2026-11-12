# ADR-NEXT: Event Management attendee app, personal agenda, event operations, and the service and partner portal templates

**Status:** Accepted (builder decision)
**Date:** 2026-11-11
**Source:** plan Section 6.0a releases 1.11 (EV-22, EV-29) and 1.13 (EV-23, EV-24, EV-25, EV-28,
PB-04, PB-05), D-190 (the networking app as an installable web app on the org's WordPress site,
no app store; the Midwest Dreamin' and Whova comparison), D-118 (Portal Builder templates),
Section 5.9, Section 5.12, Section 9.9. Builds on ADR-0177 (events module), ADR-0185 (Portal
Builder), ADR-0191 (portal templates and module actions), ADR-0187 (badges and their QR code),
ADR-NEXT `NEXT-events-paid-registration-proposals-ratings.md` (session ratings), ADR-0017,
ADR-0021 and ADR-0024.

## Context

Release 1.5 finished paid registration, proposal scoring, badge overrides and session ratings.
A community conference still needs what attendees carry on their phones (profiles, connections,
messages, announcements, sponsors, maps, their own agenda and ratings), what sponsors want from a
booth (the leads they scanned), and what the organizers track (venues and rooms, session and
speaker details, the budget). D-190 asks for the attendee app as a web app saved to the home
screen from the org's own WordPress site, not an app store app. Portal Builder (ADR-0185) already
signs people in from that site at no license cost and renders template pages; PB-04 and PB-05 are
two more templates.

Two things the portal engine cannot do today block these templates: a catalog page shows records
to every signed-in person (so an attendee would see every event's directory and announcements,
and a partner every organization's referrals), and a page cannot hand the person a file (an
`.ics` agenda, a CSV of leads) or read a QR code.

## Decision

### Portal engine additions (Portal Builder, both templates and the attendee app)

1. **A catalog page may be scoped to the person (`personScope`).** `{ "field": "Event__c",
   "object": "Event_Attendee__c", "personField": "Contact__c", "valueField": "Event__c", "where":
   [..] }` limits the page to records whose `field` is one of the values of `valueField` on the
   scope object's records whose `personField` is the verified person and that pass the scope's
   own fixed `where` tests. `field` is a lookup or `Id`; `valueField` a lookup to the same object
   (or the page's object for `Id`); `personField` a lookup to Contact; the scope object a custom
   object (the same rules as a page's object). The server reads the values first (at most 200)
   and binds them, so no semi-join limit applies and the page and scope may be the same object.
   Every read, action and record check goes through the same filter, so a module action on a
   scoped catalog record (Connect, Add to Agenda) only ever sees a record the person could see.
   An empty scope shows nothing. Scoped catalogs stay read only.
2. **Three page and field options for the client, checked by the server.** `calendar`
   (`{ "title", "start", "end", "location" }`, each a field path already on the page): the client
   offers Add to Calendar, an iCalendar file of the page's records built in the browser. `download:
   true`: the client offers Download CSV of the page's records as shown. A field's `scan: true` (an
   editable text field only): the client's add form offers Scan, which reads a QR code with the
   browser's own `BarcodeDetector` and camera where available, and the person types the code
   otherwise. Nothing is sent to an outside service.
3. **Installable app (PWA) from the WordPress plugin.** The shortcode takes `app="yes"` and an
   optional `name`; the plugin then serves a web app manifest (`?barncrm_portal_manifest=<key>`,
   standalone display, the site icon, else a bundled one) and a service worker at the site root
   (`?barncrm_portal_sw=1`, header `Service-Worker-Allowed: /`), and `boot.js` adds the manifest
   and Apple home screen tags and registers the worker. The worker caches only the plugin's own
   script and style files and an offline notice; it never caches a proxy call or a page's data,
   so nothing about a person is kept on the phone beyond the HttpOnly session cookie. No app
   store, no push service, nothing paid.

### Attendee app (EV-22) and personal agenda (EV-29)

4. **One template, `attendee.json`, requires Events.** Pages: My Events (the person's attendee
   rows, with their networking choices editable), Agenda (the confirmed sessions of the person's
   events, Add to My Agenda), My Agenda (their picks, rate a session, Remove, Add to Calendar),
   Attendees (the opted-in attendees of the person's events, searchable, Connect), Connections
   (accept or decline, a private note, a message to send), Messages (received, Reply) and Sent,
   Announcements, Sponsors (confirmed sponsors with booth), Event Info (dates, venue, venue map
   and online link) and My Details. Every list beyond the person's own rows is a scoped catalog
   (decision 1) through `Event_Attendee__c` rows that are not Cancelled.
5. **Profiles are opt-in, per event.** Event Attendee gains Show Me in the Attendee List
   (`Networking_Opt_In__c`, default off), Headline, About Me, How to Reach Me (shown only to
   accepted connections) and Share My Details With Sponsors (`Share_With_Sponsors__c`, default
   off, EV-28). The attendee list shows only opted-in attendees and only the headline, about,
   badge name, title and company; never email, phone or address.
6. **Connections need both sides.** Connect (`Events.Connect`, on an attendee list record) creates
   two Attendee Connection rows on the event, one for each person: Requested for the asker and
   Wants to Connect for the other, unless a row for that pair and event exists. Accept
   (`Events.AcceptConnection`) marks both Connected and copies each person's How to Reach Me onto
   the other's row; Decline (`Events.DeclineConnection`) marks both Declined, which hides them from
   both and stops a new request for the pair. The pair key (event, person, other) is unique.
7. **Messages only between connections, off by default.** Send Message
   (`Events.SendMessage`, on a Connected row) sends the row's draft as an Attendee Message and
   clears it; Reply (`Events.SendReply`, on a received message) sends that message's reply back
   while the two are still connected. The Events setting Attendee messages
   (`Attendee_Messages__c`, default off) turns both on; at most 50 messages per person per day.
   Messages are Salesforce records the event's staff can read; the help says so.
8. **Personal agenda.** Add to My Agenda (`Events.AddToAgenda`, on an Agenda record) creates an
   Agenda Item (master-detail to the session, the person) unless the person already picked it,
   the session is full (its Agenda Picks roll-up has reached its Capacity) or it overlaps a
   session already picked. The Events setting Allow overlapping picks (`Allow_Agenda_Overlaps__c`,
   default off) lets an overlap through and marks the item Overlaps. Remove from My Agenda
   (`Events.RemoveFromAgenda`) deletes the person's own item. The `.ics` export is decision 2.
9. **Ratings from the agenda keep EV-27's anonymity.** An Agenda Item's My Rating (1 to 5) and
   comment, saved once the session has started, add one anonymous Session Rating (29EV27) and mark
   the item Rated; the Session Rating names no person and no item. A rating is kept once: a later
   change is refused.
10. **Announcements** are records on the event (title, body, Publish At); the app shows those
    whose Publish At has passed, newest first. Staff add them from the event page's related list.
11. **Module actions run through Events' existing seam.** `EventsPortalExtension` names the new
    actions and hands them to `EventAttendeeApp`, which runs `without sharing` in system mode
    (register: Portal), re-reads every row by the verified person, and answers expected refusals
    from the Events help catalog.

### Sponsor lead scanning (EV-28)

12. **A sponsor portal template, `sponsor.json`, requires Events.** A sponsor's contact (Event
    Sponsor's Contact) or a booth staff member (an Event Attendee whose new Sponsor field names
    the sponsor) signs in and adds a lead by scanning or typing an attendee's badge QR code (the
    attendee's record identifier, ADR-0187). The page is a `related` page on Sponsor Lead whose
    person is the scanner; `create` sets the scanner, the code is the only editable field besides
    notes and a rating.
13. **The scan is resolved on save, in system mode.** A before-insert handler finds the attendee
    by the code and the scanner's sponsorship at that attendee's event, and sets the lead's
    sponsor (master-detail), attendee and status: Lead (the attendee opted in: name, email, title
    and company are copied), Not Shared (the attendee did not opt in: nothing about them is kept
    and the attendee link stays empty), Not Found (no such attendee: the lead stays on the
    scanner's latest sponsorship) or Already Scanned. A scanner with no sponsorship at all is
    refused. Leads are exported per sponsor from the Sponsors tab (Download Leads) and by the rep
    from the portal page (decision 2), Lead status only.

### Event operations

14. **Venues and rooms (EV-24).** Event Venue (a tab, with All Venues and My Venues list views:
    address, capacity, map link, notes) and Event Room (master-detail to venue: capacity, setup,
    where to find it). An event picks a Venue; a session picks a Room. Saving fills an event's
    blank Venue Name and Venue Address from the venue, and a session's Room text and blank Capacity
    from the room, so the agenda's room clash flags, the public page and badges keep reading the
    fields they read today.
15. **Session and speaker details (EV-25).** Session gains Level, Slides Link, Recording Link and
    Sponsored By (a sponsor of the same event); its format stays Session Type, which gains
    Lightning Talk and Roundtable. Speaker gains Headshot Link, LinkedIn, Website and a checklist:
    Agreement Signed, Slides Received, Dry Run Done. The Speakers tab shows the checklist count;
    the speaker portal lets the speaker edit their headshot and links.
16. **Budget, expenses and partner funding (EV-23).** Event Expense (one line: category, budgeted,
    actual, vendor, status, due date) and Event Funding (sponsor or partner money: type, partner
    organization, optional sponsor link, expected, received) are detail records of the event.
    The Budget panel on the Details tab (no new tab) shows budgeted against actual by category,
    funding expected against received, and Net Cost: actual spend less funding received and
    registration payments received (Amount Paid). The event dashboard shows Net Cost. Totals come
    from the framework-free `eventBudgetModel`; the controller only reads rows in user mode.
    Sponsorship amounts are not counted twice: money from a sponsor counts when it is recorded as
    funding.

### Service and partner portal templates (PB-04, PB-05)

17. **Service portal (`service.json`, requires Programs).** My Programs (enrollments not
    Withdrawn), My Services (service deliveries), Upcoming Sessions (Programs sessions of the
    cohorts the person is enrolled in, a scoped catalog), My Goals (through the enrollment, read
    only) and My Details. Case notes and referral notes are never on a page (participant privacy,
    P-08).
18. **Partner portal (`partner.json`, requires Programs; `partner-funders.json` adds Funders).**
    Referral gains Partner Organization (an Account) and Shared With Partner (default off). A
    person with a Current affiliation to the partner organization sees the referrals shared with
    it (a scoped catalog through `Affiliation__c`), without notes. Where Funders is installed,
    `partner-funders.json` adds the grants whose Funder Contact is the person and their submitted
    report requirements. Two files instead of an optional page, because a template whose object is
    missing fails closed whole (ADR-0185).

## Alternatives considered

- **A native app.** Rejected by D-190: no app store; the web app installs from the org's site.
- **A same-event filter special to Events.** Rejected: `personScope` serves the attendee app, the
  service portal and the partner portal with one rule.
- **Copying a person's details onto every connection at request time.** Rejected: How to Reach Me
  is copied only on accept, so a request reveals nothing the attendee list does not.
- **Refusing a scan that is not shared with an addError.** Rejected: the rep would only see "could
  not be saved"; a Not Shared lead tells them why and keeps nothing about the attendee.
- **Budget, Expense and Funding as three objects.** Rejected: one expense line carries both its
  budget and its actual, as small organizations budget events.
- **A Budget tab.** Rejected: the label budget is full; the panel sits under the dashboard.

## Consequences

- Nine new objects in Events (canonical model 29EV31 to 29EV39), two fields on Programs' Referral,
  two Events settings, three triggers through the Core dispatcher.
- The attendee and sponsor apps work only where Portal Builder is installed and its WordPress
  plugin set up; the event page works without them.
- The portal engine keeps its rule: a template is checked whole on every call; the new options
  are checked the same way in Apex and in `portal-client/src/portalTemplate.js`.
