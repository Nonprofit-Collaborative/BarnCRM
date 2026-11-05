# ADR-0166: One nightly job dispatcher runs every BarnCRM nightly job in sequence

**Status:** Accepted (Brandon approved the architect review fixes, decision 4, 2026-11-04)
**Date:** 2026-11-04
**Source:** architect review findings RT-10 and L-10 (scheduled jobs), RT-09 (donor level
writes) and L-08 (retention); amends ADR-0038 (Giving nightly jobs scheduled from the console),
ADR-0075 (Health Check schedules every nightly job) and ADR-0032 (acknowledgment send schedule)

## Context

The full suite scheduled about 19 separate CronTriggers (Core 6, Rollups 1, Giving 6,
Volunteers 2, Logic Models 1, Funders 1, Mirror 2) plus the hourly tab access check. Seven of
them started inside one 30-minute window, and several write the same Gift, Installment,
Account and Contact rows, which risks `UNABLE_TO_LOCK_ROW` and competes with NPSP and DLRS
nightly batches. Each job ran as whoever pressed its button, used a slot of the org's 100
scheduled Apex jobs, and had its own schedule to keep alive. Developer Edition orgs may allow
far fewer scheduled jobs.

## Decision

1. **One schedule.** Core schedules one job, "BarnCRM Nightly Jobs" (`NightlyRun`, every day
   at midnight in the scheduling user's time zone), plus the existing hourly "BarnCRM Tab Access
   Check". Nothing else BarnCRM ships is scheduled for good; the only other triggers are
   transient (the run's own continuation, the automation pause's resume, the Rollup Builder's
   one-off Run Tonight).
2. **Steps, registered without a Core dependency.** A step (`NightlyStep`) is a key, a label,
   a time of day and the schedulable that does its work, run with no context. Core lists its
   own steps; each module registers its steps through `NightlyStepProvider`, found by class name
   with `Type.forName` (the seam of ADR-0075 and ADR-0057), so Core names no module type. A
   provider that is missing, cannot be built or throws is skipped and logged.
3. **One at a time, in a fixed order.** Steps run in order of their time of day, ties in
   registration order. Each step starts at its usual time or when the step before it has
   finished, whichever is later, so the documented times still hold and no two steps overlap.
   A step has finished when no batch, queueable or future job its user started since the step
   began is still holding, queued, preparing or processing; the run checks every two minutes
   with a delayed queueable and gives up waiting after six hours, recording that and moving on.
   Waits longer than ten minutes, and any chain the platform refuses to extend (the Developer
   Edition queueable depth), continue through a one-time trigger "BarnCRM Nightly Jobs
   Continue". A run still going when the next night starts is superseded: the new run waits
   for the old step's work before its first step.
4. **Existing switches and times kept.** A step whose on/off was its schedule (Error Digest,
   Rollups, the four Giving jobs, Acknowledgments, Pledge Reminders, the two mirrors) keeps an
   on/off switch, stored per step and set by the same Schedule and Stop buttons on its own page.
   Shipped on, except Acknowledgments and Pledge Reminders (they email donors: the
   organization's choice). A step whose on/off was a setting (Seasonal Addresses, Ask Reminders,
   a mirror's direction, module turned off) reads that setting. The Rollups Nightly Run Hour is
   the Rollups step's time of day, so it is still honored.
5. **Last result per step.** Each step's last start, finish, outcome (Running, Done, Done With
   Errors, Failed, Skipped, Gave Up Waiting) and a short message are kept on one row per step of
   the new Core object `Nightly_Job__c`, with the run itself as one more row. The Nightly Jobs
   panel on the General page of BarnCRM Settings shows the schedule and every step.
6. **Upgrade path.** Each step's key is the name its old trigger carried. Adopting the old
   schedules aborts every old trigger a known step names, turns that step's switch on when it
   had one, and schedules the nightly run if anything was adopted. It runs from Core's and each
   module's install and setup steps, at the start of every nightly run, from Health Check's
   Schedule all nightly jobs fix, and when an old trigger fires (which also runs that night's
   work, so nothing is missed). It is idempotent, as the old schedulers' `start` was. The old
   schedulable classes stay schedulable so the deploy script's pause and restore of scheduled
   jobs still works on them.
7. **Health Check.** The finding "Nightly jobs are not scheduled" now names the nightly run and
   the hourly check; its fix schedules both. Nothing is scheduled on install unless an old
   schedule is adopted (ADR-0075's reason holds).
8. **Retention and write volume run as steps.** The new Record Cleanup step deletes Merge
   Journal, Setting Change, finished Import Batch (with its journal pages and rows) and Field
   Utilization Snapshot rows past their org-wide retention settings (L-08). The donor level and
   score pass writes only the fields whose values changed (RT-09).

## Alternatives considered

- **Each batch's finish starts the next step.** Rejected: every batch in every module would
  need a Core call in its finish, several steps chain more than one batch, and the same batches
  also run from Run Now buttons, where they must not start the night's next step.
- **A batch over the step list.** Rejected: a batch's execute cannot start another batch, so
  the steps' own batches would still overlap.
- **A fixed start hour, back to back.** Rejected: it moves the morning sends (grant and
  volunteer reminders, the error digest) into the night and drops the Rollups hour setting.
- **Keep per-job CronTriggers, staggered further apart.** Rejected: it keeps the job count and
  the overlap risk whenever a job runs long.

## Consequences

- Two persistent scheduled jobs instead of about twenty; the run uses async jobs only while a
  step waits (one delayed queueable every two minutes).
- One new Core object (`Nightly_Job__c`), counted against the org's custom object allocation.
- Every step runs as the user who scheduled the nightly run; Health Check's inactive owner
  check covers it as before.
- Turning a step on or off never touches Setup or a CronTrigger, so it saves instantly and
  never fails for want of the Author Apex permission.
- A module that adds a nightly job adds a step to its provider, never a CronTrigger.
