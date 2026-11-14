# Nightly Jobs

## What It Does

BarnCRM does its regular overnight work in one nightly run. The run is one scheduled job,
**BarnCRM Nightly Jobs**, that starts at midnight in the time zone of the person who scheduled it (the panel's times are in
that zone, written the way your Salesforce locale writes them) and takes
each job in turn, one at a time, at its usual time or as soon as the job before it has
finished, whichever is later. A job never starts while the one before it is still working, so
the jobs never compete with each other for the platform's limits.

Before this version each job had its own schedule, up to about 19 of them. There is now one,
plus the hourly tab access check Health Check keeps.

The jobs in the run, by time of night:

| Time | Job | Package | Switched on and off |
|---|---|---|---|
| 0:30 | Seasonal Address Swap | Core | **Turn On Seasonal Addresses**, Addresses section |
| 1:20 | Record Cleanup | Core | Always on; how long each kind of history is kept is set as below (the staged rows of finished imports follow **Delete Import Rows**, Import section) |
| 1:30 | Setup Changes Copy | Core | Org Optimizer on or off |
| 1:45 | Empty Household Tidy-Up | Core | **Delete Empty Households**, People and Households section |
| 2:30 | Engagement Score | Core | **Turn on engagement score**, People and Households section (off until turned on); see [Engagement Score](engagement-score.md) |
| 7:00 | Error Log digest | Core | **Schedule Daily Run** and **Stop Daily Run**, Error Log section |

With modules installed, these join the run (a job with a switch is turned on and off on the
**Nightly Jobs** panel, or with Schedule and Stop on its own page where it has one; a job
without a switch runs whenever its module is on):

| Time | Job | Module | Switched on and off |
|---|---|---|---|
| 1:15, 1:45, 3:00, 3:30 | Installment top up, installments overdue, donor levels, ask reminders | Giving | **Nightly Jobs** panel, each on its own (on unless switched off) |
| 1:30 | Opportunity mirror | Mirror | Opportunity mirror page, while a direction is chosen |
| 1:35 | Gift Transaction mirror | Mirror | Gift Transaction mirror page, while the mirror is on |
| 2:00 (the **Time of the Nightly Run** setting) | Rollup recalculation | Rollup Builder | Rollups page |
| 2:45 | Acknowledgment emails | Giving | Acknowledgments page (off until switched on) |
| 3:00 | Volunteer schedules | Volunteers | No switch |
| 3:15 | Pledge reminders | Giving | Pledge Reminders page (off until switched on) |
| 3:30 | Indicator results | Logic Models | No switch |
| 5:45 | Territory assignment (records with no territory yet) | Territory Management | **Nightly Jobs** panel (off until switched on) |
| 6:00 | Grant reminders | Grants | No switch |
| 7:00 | Volunteer shift reminders | Volunteers | No switch |
| 7:15 | Volunteer unfilled shift nudges | Volunteers | No switch (the **Send unfilled shift nudges** setting decides) |

The rollup recalculation goes over every record once a week (Sunday unless the **Night of the
full recalculation** setting says otherwise) and over what changed on the other nights; see
[How the Nightly Run Works](rollups.md#how-the-nightly-run-works).

The donor levels pass writes a donor only when its level or scores changed.

Modules add their own jobs to the same run when they are installed (Rollup Builder, Giving,
Mirror, Volunteers, Logic Models, Grants). The Nightly Jobs panel lists every job your org has.

## Where to Find It

1. Open the **BarnCRM Settings** tab and choose the **General** section.
2. Find the **Nightly Jobs** panel.

The panel shows:

- whether the nightly run is scheduled, and when it last started and how it ended;
- every job in the order the run takes it, with its **Time**, its **Status** (On, Off, or
  Not Scheduled when it is on but the nightly run is not scheduled, so it does not run yet), its
  **Last Run** and its **Result**: Done, Done With Errors, Failed, Skipped (it was off),
  Gave Up Waiting, or Running.

A result other than Done comes with a short reason. Done With Errors means the job finished but
some of its records failed: the [Error Log](error-log.md) has the details. A job that keeps its
own summary of what it did (the Giving installment, reminder and acknowledgment jobs) shows it
under its result, and a job that is on but did not run when the last nightly run did is marked
**Missed Last Run**.

People who can manage BarnCRM Settings also see, on each job's row:

- **Turn On** or **Turn Off**, for a job with a switch of its own. It saves at once, for the
  whole organization, and turning a job on schedules the nightly run when it is not scheduled.
- **Run Now**, for a job that is safe to start by hand at any time (the Giving installment top
  up, installments overdue, pledge reminders and ask reminders). It starts the job's work now
  without waiting for tonight; the job still runs tonight as usual. Donor levels and
  acknowledgment emails have no **Run Now** here: the Donor Levels page has its own
  **Recalculate Now**, and acknowledgments are sent from the Acknowledgments page.

This panel replaces the Giving module's own **Nightly Jobs** page and tab, which earlier versions
had: every module's jobs, Giving's included, are on this one panel.

## How to Turn It On

The nightly run is scheduled for you when:

- BarnCRM is installed new (the install schedules it; a schedule that already exists is kept and
  no job's switch is changed), or you finish first-run setup;
- you upgrade from a version that had any job scheduled on its own (the old schedules are
  replaced by the one run, and each job that was scheduled stays on);
- you switch on a job that has its own switch, such as **Turn On Seasonal Addresses** or the
  Error Log's **Schedule Daily Run**;
- you press **Schedule Nightly Jobs** on the panel, or Health Check's **Schedule All Nightly
  Jobs** fix.

A scheduled job runs as the person who scheduled it, so press the button as the administrator the
run should belong to. Only people who can manage BarnCRM Settings see the button.

A job's switch is on its row of the panel, and also on its own page where it has one. Switching
a job off leaves it out of tonight's run; the run itself stays scheduled for the others.

## How Long History Is Kept

The **Record Cleanup** job deletes history BarnCRM keeps for you once it is older than your
organization's choice. Each choice is a number of days on BarnCRM Settings, shows its default,
and applies to the whole organization:

| Setting | Section | Default | Accepted | What is deleted |
|---|---|---|---|---|
| **Days to keep merge history** | Duplicate Matching | 365 | 30 to 3650 | Merge Journal entries (undo is offered for 15 days, so this does not shorten it) |
| **Days to keep field history** | Field History | 730 | 30 to 3650 | The changes [Field History](field-history.md) kept |
| **Days to keep settings changes** | General | 730 | 180 to 3650 | The record of who changed which setting |
| **Days to keep import history** | Import | 365 | 30 to 3650 | Finished imports and bulk jobs, with their rows and journal, once they can no longer be undone; and imports abandoned in Draft, Parsing or Preview (started and never committed), with their staged rows |
| **Days to keep field use counts** | Org Optimizer | 730 | 90 to 3650 | Saved Field Utilization counts |
| **Days to keep Error Log entries** | Error Log | 180 | 1 to 3650, or 0 to keep every entry | Error Log entries, whatever their status |

A value outside the accepted range is read as the nearest end. An import that is still running,
or that can still be undone, is never deleted. An import is counted from the day it was
started, so a wizard left open and forgotten goes with the rest of the history after the same
number of days. The staged rows of a finished import go sooner or later by the **Delete Import
Rows** choice in the Import section (see [Importing](importing.md)); Record Cleanup applies it
every night.

## How Long a Job May Take

The run waits for everything a job started (batch and background jobs) before it moves on.
Only that work counts: other background work running in the org at the same time, such as an
import someone started, neither holds a job up nor makes it Done With Errors. The run
checks every two minutes. After six hours it gives up waiting on that job, records **Gave Up
Waiting**, and goes on with the next one. If a run is still going when the next night's run
starts, the new run takes over: the job the old run was on is recorded as **Gave Up Waiting**,
and the new run waits for what it started before beginning.

## Common Mistakes

- **Deactivating the person who scheduled the run.** The run stops with them. Health Check
  says so; press **Schedule Them Again as Me** on that finding.
- **Deleting the BarnCRM Nightly Jobs job in Setup.** Every nightly job stops. The panel and
  Health Check both say it is not scheduled; press **Schedule Nightly Jobs** to put it back.
- **Looking in Setup, Scheduled Jobs, for each job.** Only the one run is there, plus
  **BarnCRM Nightly Jobs Continue** while a run is waiting for a job that is due later in the
  night. The panel is where each job's result is.

## A Five-Minute Walkthrough

1. Open **BarnCRM Settings**, choose **General**, and find **Nightly Jobs**.
2. If it says the run is not scheduled, press **Schedule Nightly Jobs**. The panel now says it
   is scheduled.
3. Open the **Addresses** section and turn on **Turn On Seasonal Addresses**. Save.
4. Back on **Nightly Jobs**, the seasonal address swap now reads **On**.
5. The next morning, read the **Last Run** and **Result** of each job.
