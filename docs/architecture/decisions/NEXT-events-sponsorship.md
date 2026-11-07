# ADR-NEXT: Event Management sponsorship: levels, sponsors on Core accounts, a deliverables checklist, and an optional link to Giving or Funders through Core

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan Section 5.12 (EV-09), Section 6.0a release 1.3 (D-123, D-177), ADR-0177 decision 11,
Section 1.5 (no payments), Section 4 and ADR-0013 (modules depend on Core only), ADR-0017 (the
extension seam pattern), Section 9.9 (portability).

## Context

EV-09 manages an event's sponsorship: sponsor organizations, tiers, benefits, a deliverables
checklist (logo, booth, passes) and status, with an optional link to a Giving gift or commitment, or
a Funders award, "when installed". Modules depend on Core only, so Events may name no Giving or
Funders object. ADR-0177 decision 11 said such a record is "named by record identifier as text".

## Decision

1. **Three objects, all details.** `Sponsorship_Level__c` (a detail of the event: amount, benefits,
   a deliverables template, sort order), `Event_Sponsor__c` (a detail of the event: the sponsoring
   Core account, an optional level, a contact, status Prospect, Committed, Confirmed or Declined,
   an amount, notes) and `Sponsor_Deliverable__c` (a detail of the sponsor: name, type Logo, Booth,
   Passes or Other, status Pending, Requested, Received or Done, due date, quantity, notes).
   Roll-up summaries on the sponsor count the deliverables and the done ones.
2. **One sponsorship per organization per event.** The Sponsors tab refuses a second sponsor for the
   same account at an event, and a level of another event. A record edited by hand is not blocked,
   as for event speakers' tab-level checks.
3. **A level starts the checklist.** Adding a sponsor at a level copies the level's amount and makes
   one deliverable per line of the level's Deliverables text (a first word of Logo, Booth or Passes
   sets the type; anything else is Other; blanks and repeats are dropped; at most 50). The
   parsing is a small Apex class (`SponsorDeliverableTemplate`) so the rule is testable on its own.
4. **The Giving or Funders link goes through Core.** A sponsor holds `Linked_Record_Id__c`, the
   record identifier as text. Core gains `LinkedRecords`, a small seam that turns identifiers into
   names: it knows the supported optional-module objects by API name (a gift, a commitment, a
   Funders award), resolves one only when that object is in the org and the person can read the
   record (user mode), and leaves out everything else without an error. Events names no other
   module's object and shows no label when Giving or Funders is absent. No Giving or Funders code
   changes.
5. **No payments.** The amount is what the sponsor has agreed to give; the tab totals Committed and
   Confirmed amounts. A payment received through the organization's processor is recorded in
   Giving, and the link ties the two.
6. **Levels are plain records.** A level is added and edited through the record form and removing
   one leaves its sponsors with no level (Clear on delete), keeping their amounts and checklists.

## Alternatives considered

- **A lookup to the Giving gift or commitment.** Rejected: it would make Events depend on Giving.
- **A Core registry of linkable objects in custom metadata.** Rejected for now: three objects named
  in one Core class is smaller than a metadata type nothing else uses. Revisit when a second
  module needs links.
- **Deliverables as a multi-select on the sponsor.** Rejected: each item has its own status, due
  date and quantity.

## Consequences

- Three objects and a Core class; no setting, no scheduled work.
- A link to an object the viewer cannot read, or that was deleted, shows only the identifier's
  absence (no label), not an error.
- Deleting an event deletes its levels and sponsors, and a sponsor's deletion deletes its checklist.
