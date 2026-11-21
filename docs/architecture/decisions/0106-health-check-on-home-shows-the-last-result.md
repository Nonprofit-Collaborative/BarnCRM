# ADR-0106: Health Check on Home shows the last result, with Run now

**Status:** Accepted (owner approved, Brandon, 2026-10-13; builder decision on the shape)
**Amended by:** ADR-0233 `0233-org-optimizer-and-sample-data-modules.md` (D-215, 2026-11-20):
Core's Home page no longer places the Health Check panel (note at the end).
**Date:** 2026-10-13
**Source:** Core review finding ADMIN-7; follows ADR-0021 (system mode writes for package
owned data) for its run record

## Context

The Health Check panel sits on BarnCRM Home for administrators and ran every check each time
Home opened: a global describe, about 20 checks (anti-join counts over Contact and Account,
permission set assignment scans, scheduled job reads) and every module's extension. Home is
the page people open first and most often, so that cost was paid on almost every visit, and
the orphan counts in particular can be slow at volume (ADMIN-24).

## Decision

1. The panel gains one property, **Show the last result first** (`lastResultFirst`). With it
   on, the panel does not run Health Check when it opens. It shows when Health Check last ran
   in full and how many findings it had by severity, and a **Run now** button that runs the
   full report in place. BarnCRM Home sets it on. The Health page of the settings console
   leaves it off and keeps running in full on open. Any later page (the Org Optimizer, say)
   gets the same behavior by setting the same property: the logic lives in the panel and in
   `HealthCheckLastRun`, nowhere else.
2. A full run by someone with Manage BarnCRM Settings records its time and its counts on
   `BarnCRM_Settings__c` (`Health_Check_Last_Run__c`, `Health_Check_Last_Result__c`). A run
   by anyone else is not recorded, because it skips the access checks and would understate
   the result.
3. The record is written through `OrgSettingsSystemWriter`, without an audit row, like the
   other run stamps (seasonal swap, error digest, field utilization). It is package owned
   bookkeeping computed by the package, which is the ADR-0021 case. A failure to record is
   logged and never fails the report.
4. The stored result is counts only. Finding text is built in the reader's language when the
   report runs, and the full findings are one click away.

## Alternatives considered

- **Run a reduced set of checks on Home.** Still pays a global describe and the anti-joins
  on every load, and shows a partial answer that looks complete.
- **Store the whole report.** A hierarchy custom setting has no long text, and stored finding
  text would be in the language of whoever ran it.
- **Run Health Check nightly to keep the last result fresh.** Not needed for the finding;
  can be added later as one more nightly job if the stored result goes stale in practice.

## Consequences

- Home no longer shows a finding the moment it appears; it shows the last run's counts until
  someone clicks Run now or opens the Health page.
- Two new keys on `BarnCRM_Settings__c` (canonical model Section 12, Health Check keys).

## Amendment, 2026-11-20 (D-215, release 1.30): Home no longer places the panel

ADR-0233 `0233-org-optimizer-and-sample-data-modules.md` moves `healthCheckPanel` and
`HealthCheckLastRun` into the optional Org Optimizer module. Core's Home page cannot place a
module's component (ADR-0020), so it no longer places the panel; the last result and Run now are
on the Org Optimizer page's Health Check section. The component keeps its Home page target and
its Show the Last Result First setting, so an administrator can add it to Home in the Lightning
App Builder while the module is installed. The two `BarnCRM_Settings__c` keys stay.

D-217 (2026-11-20, ADR-0233 amendment): Core's Home places its own Health Check tile
(`hubHealthCheck`) for administrators while the module is installed. It reads the two keys
above and links to the module's Health Check section; it never runs Health Check.
