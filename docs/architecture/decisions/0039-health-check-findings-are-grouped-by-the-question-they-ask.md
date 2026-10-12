# ADR-0039: Health Check findings are grouped by the question they ask, not registered one by one

**Status:** Accepted
**Date:** 2026-09-09
**Source:** builder decision under plan Section 9.3, refactoring C-11 after the analyzer
reported HealthCheckService at a cognitive complexity of 86 against a Moderate threshold
of 50

## Context

`HealthCheckService` held every check the product performs. Thirteen checks, each a small
inner class delegating to a small private method, none of them individually complex: the
analyzer's highest single method scored 9. The number that mattered was the total, 86
cognitive and 70 cyclomatic, because it is a measure of the whole file, and the whole file
is what somebody adding a fourteenth check has to read.

That was the actual cost. Nothing was blocked: the merge gate is High and Critical only,
and these findings are Moderate. But three features in two days had each added a check to
the same class, and the trend is what a diagnostic can least afford. Health Check is the
page an administrator trusts to tell them the truth about their org, and a class where
thirteen unrelated conditions sit in one scroll is where a wrong answer hides in plain
sight.

## Decision

The vocabulary, the order and the report stay in `HealthCheckService`. What each check says
moves into one of three classes, named for the question it asks:

- **`HealthCheckOrgShapeChecks`**: what is installed alongside BarnCRM, which
  coexistence mode that implies, whether the settings match it, and whether the org runs
  multi-currency. Five checks.
- **`HealthCheckAccessChecks`**: who administers the app, who cannot see it, who holds the
  receipt lock override, and what a viewer without the administrator permission is told
  instead. Four checks.
- **`HealthCheckSettingsChecks`**: automation, the two fiscal years, receipt generation and
  the Error Log. Four checks.

`HealthCheckService` keeps the `Finding`, `Report`, `Check` and `AccessCounts` types, the
severity, category, section and fix constants, `run()`, `buildReport()`,
`canManageSettings()`, `modeLabel()`, the isolation of a check that throws, and `steps()`:
the one list that shows the reading order and the permission gate on the access and Error
Log checks. Nothing on the class's public surface changed, so `HealthCheckController`, the
`healthCheck` component and both test classes call exactly what they called before.

Adding a check is now: write the finding in the class that matches its question, and add
one line to `steps()` at the point it should be read.

## Alternatives considered

**Leave it alone.** The honest baseline, and it holds up on every count except one: the
file grows by one more check each time a feature touches Health Check, and the person
adding the fourteenth reads thirteen unrelated conditions to do it. That is the named
failure, and it is the only one. Nothing is broken today.

**Extract more private helper methods inside the one class.** This is already what the
class did: every check was a method with an inner class in front of it. Splitting those
methods further changes neither number the analyzer reports, because both are sums over
the class, and changes nothing about how much a contributor has to read. It fails the
named requirement outright.

**One class per check behind a registry, along the lines of `Automation_Registry__mdt`.**
Thirteen classes and a registry, so that a check could be added without editing
`HealthCheckService` at all, and disabled per org without a deployment. Rejected: nobody
has asked for a check to be turned off, the set of checks is fixed and small, and a
registry would move the reading order out of Apex and into metadata rows, which is exactly
where an order that matters to a reader should not live. It is machinery bought against a
requirement that does not exist.

## Consequences

- **Adding a check touches two files**, the grouped class and `steps()`. That second edit
  is deliberate: `steps()` is where the reading order and the permission gate are visible,
  and both are decisions a new check has to make consciously.
- **A check whose question does not fit the three groups** is a signal to think, not to
  create a fourth class by reflex. The groups are the four categories the component already
  groups findings by, with Licenses folded into org shape because multi-currency is detected
  the same way.
- **The analyzer reports no complexity finding for any of the four classes.** Cognitive
  complexity: `HealthCheckService` 86 before, 40 after; `HealthCheckOrgShapeChecks` 16,
  `HealthCheckSettingsChecks` 9, `HealthCheckAccessChecks` 5, all against a threshold of 50.
  Cyclomatic: 70 before, and 24, 22, 15 and 10 after. The parameter-list finding on the
  five-argument `Finding` constructor is unchanged and stays where it was.
- **The service's own number barely moves as checks are added now.** A new check adds one
  statement to `steps()`, which costs nothing on either measure; the growth lands in the
  grouped class, which is where a reader is looking.
- **No finding changed.** Same keys, same severities, same categories, same messages, same
  fix targets, same order. The existing tests assert all of that and were not modified.
- **Nothing here was executed against an org.** No Apex in this repository has been. What
  is verified is that it compiles offline, that the analyzer is clean at the gate, and that
  the diff moves code without rewriting it.
