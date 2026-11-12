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
used. Paid registration (EV-20) reaches the optional BarnCRM Payments module only by name:
`EventPayments` builds `PaymentsApi` with `NamespaceUtil.build`, and Payments builds
`EventPaymentListener` by the name stored on each payment, so neither package depends on the other
(ADR-0207 `0207-events-paid-registration-proposals-ratings.md`).

## Contents

- Objects: `Event__c` (canonical model Section 29EV1).
- The **Event Calendar** tab (`eventCalendar`, tab `Events_Calendar`): month, week and list views,
  filters and an `.ics` download per entry, with the framework-free `eventCalendarModel` and the
  thin controller `EventCalendarController` (EV-19).
- The **Events** page (`eventsHome`, tab `Events_Home`) with New Event and Repeat Event
  (`eventRepeatModal`), the framework-free module `eventsModel` and the thin controller
  `EventsHomeController`.
- The event record page `Event_Record_Page`: Core's header, main and sidebar template with tabs,
  assigned as `Event__c`'s org default.
- No app of its own (D-188): the Events Home, Event Calendar, Events and Event Speakers tabs join BarnCRM and
  BarnCRM Console through the catalog row's `Staff_Tabs__c` and `scripts/org/module-app-tabs.py`.
- Registrations (EV-02): `Event_Registration__c` (Private) and `Event_Attendee__c` (29EV8,
  29EV9), the Registrations tab (`eventRegistrations`, `eventRegistrationsModel`,
  `EventRegistrationsController`), `EventRegistrationService` with `EventPersonMatcher` (Core's
  shared `PersonMatcher`, the one Forms calls, household-aware) and `EventPricing`, and `EventFormAttachment`, Core's form seam
  (`FormAttachmentExtensions`), used only when Forms is installed.
- Reminders, follow-ups and No-Show (EV-14): `Events_Settings__c` (29EV25, shared with EV-06's notice templates) with its Setting
  Definitions (section Events), `EventsSettings`, the nightly step `EventEmailScheduler` given to
  Core through `EventsNightlyJobProvider` (`NightlyJobs.PROVIDER_CLASSES`), `EventEmailBatch` and
  `EventEmailService`; templates in the `BarnCRM_Events` email folder.
- Summit Events (EV-10): `SummitEventsAdapter` (dynamic SOQL by object name, no dependency),
  `SummitEventsBatch` and the 7:15 AM step `SummitEventsScheduler`, listed only when Summit Events
  is installed; `External_Key__c` on `Event__c` and `Event_Registration__c`.
- Permission sets Events Admin, Staff and Read Only, given by role through `EventsAccessSync`;
  install steps in `EventsPostInstall`.
- Help and messages in `BarnHelp_Events.json`.
