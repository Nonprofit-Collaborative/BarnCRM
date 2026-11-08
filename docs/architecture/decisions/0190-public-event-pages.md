# ADR-0190: Public event pages and registration: Events publishes a page view through a Core seam, Forms serves it on its Site and API with the public form intake

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** owner decision D-186 (EV-16, release 1.2; not yet in the plan mirror), plan Section 5.12
(Event Management), Section 1.5 (no payments), Section 4 and ADR-0013 (Core only, no Experience
Cloud), Section 4.13 (security), Section 9.9 (portability). Settles ADR-0177 `0177-events-module.md`
decision 10 (public pages wait for their own guest-user design); builds on ADR-0182
`0182-event-registrations.md` (registration service), ADR-0184 public forms on a Salesforce Site
(guest intake) and ADR-0185 portal builder off-platform portal API (off-platform sites).

## Context

EV-16 asks for a public page per published event (details, sessions and speakers, ticket types
with remaining capacity, a registration form), on the same Salesforce Site and security model as
public forms, with registration through the Forms public intake and EV-02's registration service so
matching, the waitlist and capacity apply; an optional public list of events; no payments; the same
through the REST API so an off-platform site can show events; and Events still working without
Forms. Event Management depends on Core only and Forms is optional, so neither may name the other.

## Decision

1. **A Core seam, Events provides and Forms hosts.** Core gains `PublicPageExtension` (a module
   says which object it handles, returns one record's public page or its list page, as plain
   values) and `PublicPageExtensions` (resolved by name, the ADR-0057 and ADR-0175 mechanism;
   `EXTENSION_CLASSES` names `EventPublicPage`). Forms, the only package with a guest surface,
   serves those pages. `PublicPageExtensions.hostInstalled()` tells a module whether a public host
   (Forms' intake) is installed. Neither module names the other.
2. **Publishing is an explicit choice per event.** `Event__c` gains three checkboxes, all off by
   default: Public Page (`Public_Page__c`: the page exists), Show Speakers (`Public_Speakers__c`:
   confirmed speakers' names, headlines and bios are shown) and Show Seats Left
   (`Public_Seats__c`: seats left per ticket are shown). A page is served only while Public Page is
   on and the status is Open or Closed; a Draft, Completed or Cancelled event has none.
3. **What the guest can be shown, and nothing more.** `EventPublicPage` (`without sharing`, system
   mode reads, in the without sharing register) reads only: the event's name, description, start,
   end, format, venue name and address, registration times, status and registration form key;
   its active ticket types whose sales have not ended (name, description, price; seats left only
   with Show Seats Left, as a count of seated attendees, never an attendee row); its Confirmed
   sessions (name, description, start, end, room, type, track name); and, only with Show Speakers,
   its Confirmed speakers' first and last names, headlines and bios. Never published: the online
   link (sent to registrants by reminders, so it is not handed to anyone with the address),
   capacity itself, promo codes, registrations, attendees, travel and audiovisual needs, speaker
   email or any other person field. No record identifier is returned except the event's own and
   its registration form's, both already in the page address.
4. **Registration goes through the public intake unchanged.** The page shows the event's
   registration form (its Registration Form Key) through `c:formPublic` with the event as the
   form's record, while the status is Open and now is inside Registration Opens and Closes. The
   form must itself be published and public (ADR-0184 decision 3); otherwise the page says
   registration is not taken online. The answers get the ADR-0184 spam checks and are stored as a
   Received submission; processing as the staff user reaches `EventFormAttachment` and
   `EventRegistrationService` (ADR-0182), so matching, the household, codes, capacity and the
   waitlist apply exactly as for staff. The `ticketType` and `promoCode` answers are the form's
   own questions.
5. **Paid tickets are shown with their price and a payment note, never left out.** A ticket with a
   price shows the amount in the org's currency and the Events setting Payment Note
   (`Events_Settings__c.Public_Payment_Note__c`, default "Pay at the door or by arrangement with
   us."); a free one shows Free. BarnCRM takes no payment (Section 1.5): the registration records
   the amount owed, as for staff. Leaving paid tickets out was rejected: it hides what the event
   offers and sends people to register for a ticket they do not want.
6. **One plain JSON page, three ways in (plan 9.9).** A record page is
   `{ kind, title, description, start, end, timeZone, facts[{label, value}], sections[{key, title,
   items[{title, subtitle, text, start, end, amount, currency, badges[], note}]}], formId,
   registration (Open, NotYet, Closed, None), message }`; the list page is
   `{ kind, title, items[{recordId, title, subtitle, start, end}], timeZone }`. Every text is
   finished in Apex from the module's help catalog, so a renderer needs no module vocabulary.
   They are served by `FormPublicController.getPage` and `listPages` (the Site guest), and by
   `FormPublicRest` at `GET /services/apexrest/barncrm/forms/v1/pages/<recordId>` and
   `GET .../pages?kind=events` (an integration user: Portal Builder or any off-platform site,
   which then posts the answers to the existing form endpoint with the event as
   `contextRecordId`). Dates and amounts are formatted in the browser by the framework-free
   `formPublicPageModel`.
7. **The Site address.** `<site URL>/FormsPublic?record=<event id>` opens an event's page (the
   form comes from the event); `<site URL>/FormsPublic?list=events` opens the list of Open
   public events that have not ended, soonest first, at most 50. The existing `form=` addresses
   are unchanged.
8. **Without Forms there is no public page.** Events works as before; its Health Check reports a
   published event while no public host is installed (warning: install BarnCRM Forms), and a
   published Open event with no registration form (information: the page shows details only).

## Alternatives considered

- **Events ships its own guest page and controller.** Rejected: a second guest surface, a second
  guest permission set to keep safe, and the spam checks and intake copied out of Forms.
- **A Portal Builder catalog page.** Rejected: portal pages need a sign-in; event pages are
  anonymous.
- **Generic fields chosen by the admin (a page template).** Rejected for now: the fixed list in
  decision 3 is what an event page needs and is easier to keep safe; a template can follow.
- **Publishing the online link.** Rejected: anyone with the page could join without registering.

## Consequences

- The Site guest now reads, through one module class in system mode, the public fields of a
  record that staff explicitly published; ADR-0184 decision 1 still holds for the intake itself.
- A Site needs no new Setup step: the guest permission set `Forms_Public_Guest` already grants
  `FormPublicController`.
- An off-platform registration is processed at once as the integration user (ADR-0184 decision
  2), so that user also needs Events Staff for the registration to be written immediately;
  otherwise the submission waits for the scheduled processing.
