# ADR-NEXT: Event Management call for speakers: applications, reviewers' scores, and accept or decline notices through chosen email templates

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan Section 5.12 (EV-06), Section 6.0a release 1.3 (D-123, D-177), ADR-0177 decision 11,
ADR-0032 (email templates sent by developer name), ADR-0017 (a settings object per package),
Section 9.9 (portability).

## Context

EV-06 is the call for speakers: proposals per event, reviewers who score them, and a decision with
a notice to the applicant, "the same review pattern as SG-03 with no dependency on it". ADR-0177
decision 11 named `Speaker_Application__c` and `Speaker_Review__c` and said an accepted application
creates the speaker and a draft session. This record fixes the details.

## Decision

1. **Two objects, both details.** `Speaker_Application__c` is a detail of the event (applicant a
   Core person, title, abstract, optional track, status Submitted, In Review, Accepted, Declined or
   Withdrawn). `Speaker_Review__c` is a detail of the application (reviewer, a score from 1 to 5,
   notes). Roll-up summaries count and add the reviews and a formula gives the average, so no
   trigger is needed and the average cannot drift.
2. **One score per reviewer, replaced on a second save.** The Applications tab saves the viewing
   person's review as an upsert, so no unique-key automation is added. A record edited by hand can
   still hold two reviews from one person; the tab shows the person's latest and the average counts
   both, which is the same as any list a reviewer edits directly.
3. **Accepting creates or links the speaker, and does not make a session.** The applicant becomes
   an Event Speaker (status Invited, since the accepted notice asks them to confirm) or the
   speaker already at the event is linked. A draft session is not made: a session needs a time and
   a room that a proposal does not have, and the Agenda Builder is where staff place a talk. This
   narrows ADR-0177 decision 11, which said "and a draft session".
4. **Notices are standard email templates named in settings.** `Events_Settings__c` (hierarchy
   custom setting, ADR-0017) holds the developer name of the accepted and the declined template, in
   a new Events section of BarnCRM Settings. The send follows ADR-0032 (`setTemplateId`, the
   applicant as target, the application as `WhatId`) through Core's `EmailSender`; the package
   composes no email HTML. A blank setting sends nothing. A notice that cannot go out (no template,
   template missing or inactive, no email address, a failed send) never undoes the decision: the
   application records the reason in `Notice_Result__c`, or the time in `Notice_Sent__c`.
5. **A decided application is final in the tab.** Only Submitted and In Review applications can be
   scored or decided; changing a decision is an edit of the record, so one application never sends
   two notices from the tab.
6. **Staff add applications.** Applications are added on the tab, or through a form (Forms engine)
   or the speaker portal (EV-07) when those exist; the object has no dependency on either.

## Alternatives considered

- **Templates stored on the event.** Rejected: the owner asked for templates chosen in settings,
  and one wording per outcome serves the organization's every event.
- **A unique reviewer key.** Rejected: it adds an automation and a registry row for a case the tab
  already prevents.
- **A lookup to the email template.** Rejected: no custom lookup to `EmailTemplate` is possible
  (ADR-0032).

## Consequences

- Two objects and one custom setting; Core gains only the settings section name `Events`.
- Until an admin names a template, accepting and declining send nothing and say so.
- The settings page lists the two templates as text; naming a template that does not exist shows
  "template not found" on the application rather than sending an empty email.
