# ADR-NEXT: Health Check schedules every nightly job with one fix, and modules register theirs

**Status:** Accepted (owner approved the UI/UX review item, builder decision on the shape)
**Date:** 2026-10-12
**Source:** UI/UX review item 7; plan Section 3.3 item 3 (silent staleness); amends ADR-0048
(its nightly rollup fix) under its seven conditions; same seam as ADR-0057

## Context

BarnCRM has several scheduled jobs, each started by its own button on its own page: Core's
rollup recalculation, seasonal address swap and error digest, Giving's installment and donor
level jobs and acknowledgment send, and Connect's Opportunity mirror. Nothing is scheduled on
install, because a scheduled job runs as the person who scheduled it, and an install runs as
nobody in particular. Health Check offered a one-click fix for the rollup run only
(ADR-0048), so an org could go months with addresses never swapped or no digest sent, and
nothing said so.

Core may not name Giving or Connect (ADR-0059), so it cannot list their jobs itself.

## Decision

1. Core defines `NightlyJob` (a label, whether it is scheduled, schedule it, idempotently) and
   `NightlyJobProvider` (the jobs a package wants scheduled in this org now). `NightlyJobs`
   returns Core's three jobs plus those of each provider installed, found by class name with
   `Type.forName` (`GivingNightlyJobProvider`, `ConnectNightlyJobProvider`), the pattern
   `HealthCheckExtensions` uses. A provider that is missing, cannot be built or throws is
   skipped and logged; the rest still count.
2. A provider returns only jobs with one right answer (ADR-0048 condition 1). A job whose
   running is the organization's choice stays off the list: Giving's acknowledgment send,
   which emails donors, and Connect's mirror while its direction is Off.
3. One Health Check finding, "Nightly jobs are not scheduled", shown to a viewer who may manage
   settings, names every unscheduled job. Its fix, **Schedule all nightly jobs**, schedules
   each at its usual time under its usual name, so each page still sees and stops it. The
   fix scope is the list of job labels, checked again before it runs (condition 5), and the
   fix is recorded in the settings change history (condition 7).
4. The rollup finding stays, to say what a missing run costs, without a fix button of its own:
   one action for one cause. The rollup-only fix key is removed.

## Alternatives considered

- **Schedule everything on install.** Rejected: the jobs would run as the installing user,
  often a consultant whose account is later deactivated, which stops every job silently.
- **A method added to `HealthCheckExtension`.** Rejected: adding a method to an interface
  breaks the classes that already implement it in Giving and Connect.
- **A fix button per job.** Rejected: six buttons for one cause, and the review asked for one.

## Consequences

- Giving and Connect each add one small provider class to have their jobs counted; until
  they do, the finding lists Core's jobs only. Nothing in Core changes when they do.
- The Setup Assistant's last step does not mention this yet: that step is being reworked
  separately (C-30, C-24), and the mention belongs there.
- The jobs run as whoever pressed the fix, as they do from each page's own button.
