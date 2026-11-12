# ADR-0212: Engagement score: a nightly Core score on Contact from admin weights, with module signals found by name

**Status:** Accepted (builder decision)
**Date:** 2026-11-11
**Source:** plan Section 6.0a release 1.15 (C-64; D-157, D-190), Section 6.1.1 item 14 (Both
editions; Giving's RFM, G-19, stays the Nonprofit Edition version), Section 1.3 principle 3 (a
module adds, Core never needs it), Section 9.9 (portability). Builds on ADR-0017 (cross-package
mechanisms), ADR-0021 (system mode writes for package-owned data), ADR-0164 (help text in JSON)
and ADR-0166 (nightly job dispatcher).

## Context

C-64 asks for one number per person that says how engaged they are across gifts, volunteer
hours, event attendance and activity recency, weighted by the admin, with a meter on the person
page. Gifts live in Giving, hours in Volunteers and attendance in Event Management; Core may
name none of them, and Core must score a person on a Platform-only org with no module
installed. Giving's donor score (G-19) already rates gifts alone by recency, frequency and
amount; the engagement score is the broader, both-editions number and does not replace it.

## Decision

1. **Two fields on Contact, in Core.** `Engagement_Score__c` (Number(3, 0), 0 to 100) and
   `Engagement_Scored_On__c` (Date). Read by everyone who reads the person, edited by no one:
   only the nightly step writes them, in system mode (ADR-0021).
2. **Three settings in People and Households, off by default.** `Engagement_Score_Enabled__c`
   (Checkbox, false), `Engagement_Score_Weights__c` (Text, `Gifts 40, Hours 25, Events 20,
   Activity 15`) and `Engagement_Score_Targets__c` (Text, `Gifts 1000, Hours 40, Events 4,
   Activity 90, Months 12`). Weights and targets are one readable line each, a name and a
   number per part, so the admin sees and changes every default in one place and a setting
   costs two fields, not ten. A part left out or unreadable reads as its shipped value. The
   targets are the amount, hours and events in the window that earn a part's whole weight,
   Activity is the number of days over which an activity's credit falls to nothing, and Months
   (1 to 60) is the window.
3. **The score.** For each part, a fraction from 0 to 1: Gifts, Hours and Events are the
   person's total in the window divided by the target, capped at 1; Activity is
   1 minus (days since `LastActivityDate` divided by the Activity days), floored at 0, and 0
   with no activity. The score is the weighted sum of the fractions over the sum of the weights
   of the parts that can be measured, times 100, rounded. A part whose module is not installed
   is left out of both sums, so a Core-only org scores on activity alone and installing a
   module does not lower anyone's ceiling. No weight at all scores 0.
4. **Module signals through a Core seam, found by name.** Core's `EngagementSignalExtension`
   (`key()`, `totals(contactIds, since)`) is implemented by `GivingEngagementSignal` (Received
   gifts by `Donor_Contact__c` and `Gift_Date__c`, sum of `Amount__c`),
   `VolunteersEngagementSignal` (Approved hours by `Contact__c` and `Date_Worked__c`, sum of
   `Hours__c`) and `EventsEngagementSignal` (Attended attendees by `Contact__c` whose event
   started in the window, a count). `EngagementScore.SIGNAL_CLASSES` lists them;
   `NamespaceUtil.resolveType` builds them as ADR-0017 settles. Each reads in system mode
   because the score is a fact about the organization, not about the person who scheduled the
   run; it returns totals only. An extension that is installed but cannot be built, or throws,
   stops that chunk of the run with an Error Log entry rather than scoring people without it.
5. **A nightly step, no schedule of its own.** `EngagementScoreJob` is a step of the nightly run
   (key `BarnCRM Engagement Score`, 02:30), active only while scoring is on; turning the setting
   on schedules nothing (ADR-0166). The step rescores every person each night in chunks of 200
   and writes only the people whose score changed, with Scored On set to that day, so an
   unchanged person's Last Modified date is not moved every night (Org Optimizer's People Not
   Changed check reads it). Scored On is the day the current score was set. Turning scoring off
   stops the step and hides the meter; the last scores stay on the records for reports until
   the admin clears them.
6. **A meter on the person page.** The Core component `engagementMeter`, on the Contact record
   page, reads the two fields through Lightning Data Service and draws the score as a meter
   with the scored-on date; it draws nothing while scoring is off or the person has no score.
   Its title and captions are the fields' own labels and its explanation is help catalog text
   (ADR-0164), so it adds no custom label; the nightly step's name is the score field's label.
   The arithmetic lives in Apex only, in `EngagementScore`, a few lines over plain numbers and
   dates, so it ports.

## Consequences

- Core adds two Contact fields, three settings, one seam, one nightly step and one component;
  Giving, Volunteers and Event Management each add one class.
- Soft credits, household giving and person account gifts recorded without a contact are not
  counted; a later release can add them in the Giving signal without changing Core.
- The score is as fresh as the last nightly run; the meter shows the date it was scored.

## Alternatives considered

- **A field per weight and target (ten settings).** Clearer one by one, but ten fields and ten
  console rows for one feature; one readable line each keeps every default visible.
- **Live scoring on the person page.** Always current, but a module query on every page view;
  the nightly score also serves reports, list views and Find.
- **Reading Giving's rollups for the gift part.** Cheaper, but ties the score to the Rollup
  Builder's definitions and their window, which the admin may change for other reasons.
