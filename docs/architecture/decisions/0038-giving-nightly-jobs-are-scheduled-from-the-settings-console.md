# ADR-0038: The Giving nightly jobs are scheduled from the settings console

**Status:** Accepted
**Date:** 2026-09-09
**Source:** defect found in the G-07 documentation sweep and again during C-18; applies plan
Principle 1 and Section 4.8, and follows the shape ADR-0020 and ADR-0027 already set

## Context

`GivingScheduler.scheduleAll()` schedules the Giving module's three nightly jobs: the
installment top up, the overdue pass, and the donor level pass. Nothing called it except its
own test. Its comment said "the module turn on step in the Settings console calls scheduleAll",
and that step is part of the Module Manager, which the roadmap puts in v0.7.

The consequence in a real org is not a missing convenience. No installment is ever marked
Overdue, so the Overdue list view the admin guide sends Jen to is permanently empty, no
recurring schedule is ever topped up, and the only evidence available to an administrator is
`Installment_Top_Up_Last_Run__c`, a field on a protected custom setting that nothing displayed
and that stays empty forever whether the job is broken or was never switched on.

C-18 had the same problem for the seasonal address swap and solved it: a Schedule button and a
Stop button on a page of the Nonprofit Settings console, gated on `Manage_Nonprofit_Settings`,
with a visible last run beside them.

## Decision

**The Giving nightly jobs are scheduled, stopped and watched from a Nightly Jobs page in the
Nonprofit Settings console, in the same shape C-18 used, and they are not scheduled by anything
else.**

1. `GivingScheduler` keeps `scheduleAll()` and its three named, staggered jobs, and gains
   `stopAll()`, `isScheduled()` and `nextRunAt()`. Scheduling looks the job up by name through
   `CronJobDetail` before scheduling it, so pressing Schedule twice returns the job that is
   already there rather than relying on a duplicate-name exception, which would otherwise write
   an Error Log entry every time an administrator pressed a button twice.
2. `GivingJobsController` and the `givingNightlyJobs` component carry the page. The page is
   reached by navigation from the Giving section of the console, as a module page must be
   (ADR-0020): the tab is `Giving_Nightly_Jobs` and the Setting Definition row names it in
   `Navigation_Target__c`.
3. The page is readable by anybody who can open the console and writable only with
   `Manage_Nonprofit_Settings`, checked in the controller. That permission is the authorization
   for everything the runs do afterwards, exactly as in ADR-0027.
4. Each pass records when it finished and one sentence saying what it did, whether or not it
   changed anything (R-IN5). A pass that has never run is blank and is reported as "not
   scheduled" rather than as late, because an org that never switched the jobs on has not
   missed a run.
5. **The times are 01:15 top up, 01:45 overdue, 03:00 donor levels.** The first two are
   unchanged. The donor level pass moves from 02:15 to 03:00: the rollups start at 02:00 and
   the ladder reads a total the rollups maintain, so fifteen minutes was not the "rollups have
   settled" the old comment claimed. Nothing now shares an hour with the rollups at 02:00 or
   the seasonal address swap at 00:30.

## Alternatives considered

- **Schedule the jobs from the Giving post-install script.** Rejected. It gives the
  administrator no way to stop them, it runs as the install user with no chance to explain what
  it started, and a job that appears in an org without anybody choosing it is the Setup-shaped
  behavior Principle 1 exists to avoid. ADR-0029 puts data the module cannot work without in
  post-install; a nightly write over every donor record is not that.
- **Wait for the Module Manager in v0.7.** Rejected. It is the answer that has been in force
  since v0.3 and it is why the defect exists. When the Module Manager arrives it can call
  `GivingScheduler.scheduleAll()`, which is the same entry point this page calls.
- **Tell administrators to schedule the classes from Setup.** Rejected: this is what the admin
  guide said, and it is directly against the non-negotiable that every admin setting lives in
  the console.
- **One page per job.** Rejected. The three jobs are switched on together, they are the same
  administrator's decision, and three pages would each be one button.

## Consequences

- An org has to switch the jobs on. That is deliberate and visible: the console line says "not
  scheduled" with the button under it, which is a better failure than three jobs quietly
  running in an org that never asked for them.
- Giving Settings gains three fields: `Installment_Overdue_Last_Run__c`,
  `Installment_Overdue_Last_Run_Summary__c` and `Installment_Top_Up_Last_Run_Summary__c`.
- The donor level page keeps its own Recalculate now button, so the Nightly Jobs page's Run now
  starts the top up and the overdue pass only, rather than carrying a second button for
  something that already has one.
- Three of the five nightly jobs BarnCRM ships are now started this way. If a fourth
  appears, the shared shape is worth extracting; two is a coincidence and three is a pattern
  worth naming, not yet worth a framework.
