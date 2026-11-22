# ADR-0244: Panels on One Page Refresh Each Other Through One Lightning Message Channel

**Status:** Accepted
**Date:** 2026-11-22
**Source:** plan D-219 (adopt newer GA platform features where they do not hinder adoption),
release 1.36 item PF-04.

## Context

Some record pages carry two BarnCRM panels where a save in one changes what the other shows.
An audit of every record page on 2026-11-22 found:

- **Volunteer Shift:** Suggested Volunteers told the Sign-Ups panel about a booking through a
  custom `window` event (`barnshiftsignupschanged`). The other way had nothing: a person added
  in the Sign-Ups panel stayed in the suggestions until the page was reloaded. A `window`
  event is global to the browser tab, so in a console with several shift tabs open it reaches
  every one, and the record id in its detail is the only guard.
- **Program:** enrolling a person or changing a stage on the Program Roster did not reach the
  Service Delivery Log on the Attendance tab until the page was reloaded.

Other cross-panel calls use `notifyRecordUpdateAvailable` or `RefreshEvent` to refresh the
record's own fields and the standard components. Those are the right tools for that job and
are not about two custom panels, so they stay.

## Decision

- **One Lightning Message Channel, `BarnCRM_Record_Changed`, in Core** (`isExposed` false),
  with two fields: `recordId` (whose rows changed) and `source` (the publishing component's
  name). It carries ids only, never record data: a subscriber reads again as its own user.
- **One Core helper, `c/barnRecordChanged`**, wraps publish, subscribe (ignoring its own
  source and other records) and unsubscribe, so each panel adds a few lines.
- **Volunteer Shift:** Suggested Volunteers and Sign-Ups both publish after a successful save
  and both subscribe; the `window` event is removed.
- **Program:** Program Roster publishes after a successful enroll or stage change; the Service
  Delivery Log subscribes and reads the same service and day again, but never while
  attendance is marked and not saved (the save reads the fresh list).
- A new pair of panels that must refresh each other uses this channel, not a new channel,
  a `window` event, polling or a page reload.

## Alternatives considered

- **Keep the `window` event and add the reverse one.** Rejected: browser-tab global, not a
  platform contract, and each pair invents its own event name.
- **A channel per page.** Rejected: the payload is the same everywhere; one channel keeps the
  metadata and the review rule small.
- **`RefreshEvent` with `registerRefreshHandler` in every panel.** Rejected: it refreshes the
  whole page's registered components and standard ones, so a stage change would reload every
  panel and the record view, not the one panel that cares.

## Consequences

- Core gains a `messageChannels` folder; `scripts/org/deploy-packages.sh` deploys it with the
  Core config stage and `build-destructive-manifest.py` knows the type.
- Message channels are GA on the Lightning Experience desktop and the Salesforce mobile app in
  every edition BarnCRM supports; no setting, permission or license is needed.
- `isExposed` false keeps the channel to BarnCRM's own code once a namespace is set; module
  packages can use it as long as they share Core's namespace. The namespace pass checks this
  with the other cross-package references.
