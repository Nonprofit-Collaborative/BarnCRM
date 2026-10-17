# ADR-0128: Recurring volunteer shifts are a schedule that creates ordinary shifts to a rolling horizon

**Status:** Accepted (owner decision, Brandon, 2026-10-17, decision D5 of the v0.8 Volunteers plan)
**Date:** 2026-10-17
**Source:** plan Section 6 feature V-07; canonical model Section 29T; builds on ADR-0127 (the
Volunteers module), ADR-0017
(nightly job providers resolved by name) and the commitment installment horizon (R-CM2)

## Context

Most volunteer work repeats: a food bank sorts every Saturday morning, a tutoring program runs
Tuesdays and Thursdays. Coordinators need those shifts to exist far enough ahead for people to
sign up, without typing each one. A shift is a record that sign-ups, hours, rollups
(`Slots_Filled__c`) and the dashboard all point at, so whatever produces repeating shifts must
end in real `Volunteer_Shift__c` records.

An open-ended pattern cannot be expanded in full, and a pattern changes: a new start time, a
second weekday, fewer places. Shifts people already signed up for must not move under them.
Core must run on a Platform-only org, so Salesforce's Shift and Event recurrence objects are not
available, and the generator must batch at scale.

## Decision

1. **A Shift Schedule object** (`Shift_Schedule__c`, master-detail to `Volunteer_Job__c`)
   holds the pattern: weekdays, every N weeks, start and end time, start and end date, places
   needed, location and Active. A shift it creates carries a `Shift_Schedule__c` lookup and is
   otherwise an ordinary shift.
2. **A rolling horizon.** An active schedule keeps shifts created from today to
   `Shift_Horizon_Weeks__c` weeks ahead (Volunteer Settings, default 8). The schedule records
   `Created_Through__c`, and each run creates only the days after it, so a run is idempotent and
   a shift a coordinator deleted is not recreated by the nightly run.
3. **When it runs.** Saving a schedule queues a run for it (`Shift_Schedule_Rules`,
   `ShiftScheduleGenerator`); every night `VolunteersNightlyJobProvider`, named in
   `NightlyJobs.PROVIDER_CLASSES`, supplies `ShiftScheduleBatch`, ten schedules per
   transaction. A run locks the schedule row first, so the two never create the same day twice.
   Times are read in the org's default time zone.
4. **Edits change only future shifts with no sign-ups.** A change to the pattern deletes the
   schedule's future shifts that have no sign-up record and are not Cancelled, and recreates
   them from the new pattern. Past shifts, shifts with sign-ups and Cancelled shifts are never
   changed, and their days are not given a second shift. Ending or deleting a schedule removes
   the same kind of shift and keeps the rest.

## Alternatives considered

- **Expand the whole pattern at save.** Impossible for an open-ended schedule and wasteful for a
  long one: thousands of empty shifts crowd reports and the dashboard.
- **Virtual occurrences computed on read, a record created at first sign-up.** Every list,
  report, rollup and the unfilled-shifts dashboard would need the same expansion code, and
  reports cannot run Apex. Rejected.
- **Update shifts in place on an edit.** Matching old days to new ones is ambiguous when the
  weekdays change; delete and recreate is simple, and only shifts nobody signed up for are
  touched.
- **Salesforce recurring Events or Field Service shifts.** Not available on a Platform-only
  org (ADR-0013) and not packageable as our model.

## Consequences

- A shift-level edit to a generated shift with no sign-ups (a note, a different location) is lost
  when its schedule's pattern is next edited. The save says how many shifts were kept; the
  admin guide tells coordinators to cancel a day rather than delete it.
- Shifts appear at most eight weeks (the setting) ahead; a longer horizon costs storage.
- Health Check reports an active schedule whose horizon is not filled, which is how a nightly job
  that stopped running shows up.
- `Volunteer_Shift__c.Shift_Schedule__c` clears when its schedule is deleted, so kept shifts
  survive.
