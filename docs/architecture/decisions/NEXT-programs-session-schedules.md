# ADR-NEXT: Repeating sessions are a saved schedule that creates ordinary sessions to a rolling horizon

**Status:** Accepted (owner decision, Brandon, 2026-11-06, plan D-183: "Repeating events
(modules-24): build all")
**Date:** 2026-11-06
**Source:** v1.0 UX review finding modules-24; plan D-183; canonical model Section 29ZA7;
mirrors ADR-0128 (recurring volunteer shifts); amends ADR-0160 decision 14 and its rejected
alternative "a stored recurrence record"

## Context

Volunteers repeat through a saved Shift Schedule that keeps creating shifts every night
(ADR-0128). Programs repeat through the one-shot Schedule Sessions panel, which creates a batch
of sessions once and keeps nothing (ADR-0160 decision 14). Staff who use both modules learn two
models, and a weekly class that runs all year has to be scheduled again every few months.
ADR-0160 rejected a stored recurrence "for now" because nothing edited a series as a whole; the
owner has now asked for one.

A session is a record that attendance (Service Delivery, R-SD7), the session list views and the
dashboard all point at, so whatever produces repeating sessions must end in real `Session__c`
records. Attendance is a person's service history: no automation may delete a session that has
any. Core must run on a Platform-only org, so Salesforce recurring Events are not available.

## Decision

1. **A Session Schedule object** (`Session_Schedule__c`, master-detail to `Program__c`, so it is
   shared as its program is) holds the pattern: service, optional cohort, days of the week,
   repeat every N weeks, start and end time, start and end date, and Active. Sessions have no
   location, so the schedule has none. A session it creates carries a `Session_Schedule__c`
   lookup (SetNull) and is otherwise an ordinary session.
2. **The same days rule and horizon as shift schedules.** A day is a session day by R-SSC1's
   rule (weekday chosen, within the dates, whole weeks from Start Date's Monday divisible by
   Repeat Every). An active schedule keeps sessions created from today to Weeks Ahead to
   Create Sessions (`Programs_Settings__c.Session_Horizon_Weeks__c`, 1 to 26, default 8, as
   Volunteers' shift horizon; the integrator asked for the setting on review). Before it, the
   draft fixed eight weeks, as nothing had asked for another
   value. `Created_Through__c` records the last day done, so a run is idempotent and a session
   someone deleted is not recreated. A day that already has a session of the schedule, or a
   session (not Cancelled) of the same service for the same cohort, is skipped, so the
   schedule never duplicates sessions the panel made.
3. **When it runs.** Saving an active schedule queues a run (`Session_Schedule_Rules`); every
   night `ProgramsNightlyJobProvider`, named in `NightlyJobs.PROVIDER_CLASSES`, supplies
   `SessionScheduleBatch`, ten schedules per transaction; the schedule page's Create Sessions
   Now runs the same code at once. A run locks the schedule rows first, so two runs never
   create the same day twice. Sessions are a date and a local time, so no time zone applies.
4. **Editing or ending never deletes.** A pattern change applies to the days after Created
   Through; clearing Active, an earlier End Date or deleting the schedule only stops new
   sessions. Removing sessions is a separate, explicit action: Remove Future Sessions on the
   schedule page, after a confirm, deletes the schedule's sessions after today that are
   Scheduled and have no service delivery, in user mode (so only a user who may delete sessions
   can), then lets an active schedule recreate them from its current pattern. Held, Cancelled
   and attended sessions are never touched.
5. **The panel stays.** Schedule Sessions keeps creating one-off batches, and gains Save as
   Repeating Schedule, which saves its service, cohort, dates, days and times as a weekly
   schedule and creates its sessions at once.

## Alternatives considered

- **Keep the one-shot panel only.** Rejected by the owner (D-183): two models for one idea.
- **Delete and recreate future sessions on every pattern edit, as ADR-0128 decision 4 does for
  shifts.** Rejected: a session's empty roster today is tomorrow's attendance, and the owner
  asked that edits and endings only stop new sessions. The explicit Remove Future Sessions
  gives the same result when it is wanted, and needs none of ADR-0128's inline budget, Rebuild
  Pending mark or removal job.
- **A horizon setting in Programs Settings.** Not built: a setting with one sensible value adds
  a console row, docs and tests for nothing. Easy to add later if asked for.
- **A Session Schedules tab.** Not built: schedules are managed from the program and cohort
  pages (their related lists) and the panel.

## Consequences

- One more object for a program user (Module Manager uninstall counts, the Platform object
  count) and one more nightly step.
- After a pattern edit, sessions already created keep the old pattern until Remove Future
  Sessions is used; the schedule page says through which day sessions exist.
- Programs Staff, who cannot delete sessions, cannot use Remove Future Sessions; they cancel
  sessions one by one or ask an admin.
- A cohort or service with schedules cannot be deleted (Restrict) until its schedules are.
