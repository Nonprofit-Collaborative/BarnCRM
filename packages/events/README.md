# BarnCRM Event Management

## Purpose

Events the organization runs, from an evening talk to a community conference: the event itself,
its ticket types and promo codes, its tracks, sessions and agenda, and its speakers (plan Section
5.12, ADR-0177 `0177-events-module.md`). Registrations, call for speakers, sponsorship, check-in
and reminders follow in their own items, on the data model the ADR sets out.

## First ships in

Release **1.2** (EV-01 events, EV-03 ticket types, EV-04 tracks, sessions and agenda, EV-05
speakers).

## Depends on

- BarnCRM Core

Nothing in this package references Volunteers, Giving, Funders, Programs, Forms or Portal
Builder; those links go through Core extension points when their items are built. No Campaign is
used, and BarnCRM takes no payment.

## Contents

- Objects: `Event__c` (canonical model Section 29EV1).
- The **Events** page (`eventsHome`, tab `Events_Home`) with New Event and Repeat Event
  (`eventRepeatModal`), the framework-free module `eventsModel` and the thin controller
  `EventsHomeController`.
- The event record page `Event_Record_Page`: Core's header, main and sidebar template with tabs.
- Registrations (EV-02): `Event_Registration__c` (Private) and `Event_Attendee__c` (29EV8,
  29EV9), the Registrations tab (`eventRegistrations`, `eventRegistrationsModel`,
  `EventRegistrationsController`), `EventRegistrationService` with `EventPersonMatcher` (Core's
  matchers, household-aware) and `EventPricing`, and `EventFormAttachment`, Core's form seam
  (`FormAttachmentExtensions`), used only when Forms is installed.
- Permission sets Events Admin, Staff and Read Only, given by role through `EventsAccessSync`;
  install steps in `EventsPostInstall`.
- Help and messages in `BarnHelp_Events.json`.
