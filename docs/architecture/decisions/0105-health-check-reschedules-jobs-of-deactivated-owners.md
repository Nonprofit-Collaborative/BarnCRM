# ADR-0105: Health Check reschedules jobs whose owner was deactivated

**Status:** Accepted (in the owner-approved admin fix batch, 2026-10-13; builder decision on the shape)
**Date:** 2026-10-13
**Source:** Core review finding ADMIN-12; amends ADR-0048 (fixes never delete) and extends
ADR-0075 (one fix schedules every nightly job)

## Context

A scheduled Apex job runs as the person who scheduled it. When that person is deactivated,
the job stops running, but its CronTrigger stays, so every BarnCRM page and Health Check
read it as scheduled. Only the error digest had a staleness finding. The rollup run, the
seasonal address swap and every module's nightly job could stop for months while Health
Check stayed green.

ADR-0048 says a fix only creates what is missing and never deletes. Rescheduling a job as a
different person needs the old trigger aborted first: Salesforce has no way to change a
scheduled job's owner.

## Decision

1. `ScheduledJobSelector` reads every scheduled Apex job whose name starts "BarnCRM" in one
   query per transaction, and is the one place BarnCRM schedules and aborts its named jobs, so
   what it read is forgotten after each change (ADMIN-11).
2. A new Health Check finding, `jobs_inactive_owner`, lists the BarnCRM jobs whose owner is
   inactive. Its fix scope is those job names (ADR-0048 condition 5).
3. The fix aborts exactly those triggers, then runs the ADR-0075 schedule-all, which
   schedules every job it knows again as the running administrator, and schedules the end of a
   running automation pause again. A job Health Check never schedules for anyone (Giving's
   acknowledgment send, which emails donors) is left stopped and named in the outcome, so the
   administrator decides.
4. ADR-0048's "never deletes" gains one exception: aborting a trigger that has already stopped
   running. Nothing that is still working is ever stopped.

## Consequences

- An administrator who leaves no longer silently stops every nightly job.
- The fix is idempotent: once rescheduled, the jobs belong to an active user and the finding
  goes away.
- Every scheduler in Core, Giving and Connect schedules and aborts through
  `ScheduledJobSelector`, which is `@NamespaceAccessible` for that reason.
- Org check: deactivate a user who scheduled the jobs, run Health Check, press the fix, and
  confirm each trigger's owner is the administrator.
