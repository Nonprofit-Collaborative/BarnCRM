# ADR-0011: Evaluate vendoring a proven Apex rollup library before building one

**Status:** Accepted; amended for rollups by `0082-barncrm-owns-its-rollup-engine.md` (owner
decision, 2026-10-12): the evaluation was done (ADR-0015), and for the rollup aggregation core
the owner's independence goal now outweighs the reuse-first rule. The engine requirements under
Consequences still hold.
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-11

## Context

The rollup engine is the highest-correctness-risk component in the product. Principle 2
makes giving totals, receipts, and fund balances the product's reputation, and plan
Section 11.1 rates "rollup engine correctness bugs damage trust" as medium likelihood and
very high impact. Every module depends on it (plan Section 4.10).

The work is also genuinely hard: aggregate correctness across insert, update, delete,
undelete, reparent, and merge; governor-limit safety through queueable chaining and
platform event fan-out; idempotent recalculation; fiscal-year awareness; a declarative
filter builder that an administrator can drive without typing SOQL; and both real-time
and scheduled modes with visible freshness.

Principle 8 says nothing is built that already exists and is good: standard platform
features first, well-maintained open source second, custom code last. Well-maintained
MIT-licensed Apex rollup libraries exist and have absorbed years of edge cases we would
otherwise rediscover. The Data Processing Engine, which Agentforce Nonprofit uses, is not
available to us (ADR-0009) and is batch-only besides.

## Decision

**Before any rollup engine code is written, evaluate vendoring an existing
well-maintained open source Apex rollup library**, and record the outcome as a new ADR.
This evaluation is scheduled as engineering work in v0.2 (plan Section 6).

Evaluation criteria (plan Section 4.10):

1. Packageable as source inside a 2GP managed package.
2. License compatible with ours (ADR-0008).
3. Supports parent-child and lookup rollups.
4. Has a declarative metadata model our settings UI can drive, so the administrator never
   sees the library's own configuration surface.
5. Has tests, and a maintenance history that suggests it will still exist next year.

The instruction is explicit: **do not build a lesser version of something that already
exists.** Whatever the outcome, our UI, our freshness surfacing, and our default rollup
definitions are ours; the question is only who owns the aggregation core.

## Alternatives considered

- **Build from scratch first, evaluate later**: guarantees rediscovering edge cases in
  the one component where a bug is most damaging. Rejected.
- **Adopt a library without evaluation**: risks a dependency that cannot be packaged,
  carries an incompatible license, or exposes its own configuration surface to the
  administrator, which would violate plan Section 2.3.
- **Use the Data Processing Engine**: unavailable without Industries licensing, and
  batch-only with compute credit consumption, which is one of the things plan Section 3.5
  names as a mistake to avoid.

## Consequences

- v0.2 begins with an evaluation, not with code, and that evaluation produces an ADR
  whichever way it goes.
- If a library is vendored, it lives in the repository under its own license with
  attribution, and upstream changes are pulled deliberately rather than tracked.
- Either way the engine must satisfy the plan's own requirements: modes (real-time,
  scheduled, both), a `Last calculated` sibling value on every rollup target, a Hub
  warning when the schedule has not run in 36 hours, and idempotency such that
  recalculating any record set produces the same result.
- Rollup correctness is tested after every path: insert, update, delete, undelete,
  reparent, and merge (plan Section 9.4).
