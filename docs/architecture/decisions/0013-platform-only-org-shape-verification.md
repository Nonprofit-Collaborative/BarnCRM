# ADR-0013: How the Platform-only org shape is provisioned and verified

**Status:** Accepted
**Date:** 2026-09-06
**Source:** builder decision under plan Section 9.3 ("when a platform limitation blocks the plan, record an ADR with the workaround and continue")
**Applied by:** ADR-0136 (`0136-rollup-builder-dlrs-parity.md`): a rollup definition naming a
standard object as data, offered through describe, is not a dependency on that object.

## Context

Plan Section 4.2 makes the Platform-only org shape the floor of the product: Core,
Giving, Volunteers, Programs, and Funders must work with only Salesforce Platform
licenses, where Opportunity, Campaign, Lead, Case, Product, Person Account fields, and
the Industries objects are unavailable. Plan Section 7.3 requires every pull request to
run its tests on that shape, and plan Section 9.4 asks of every change: does it work on
the Platform-only org shape.

The platform does not allow that org to be created. A scratch org is provisioned from a
scratch org definition against a Dev Hub, and the available editions all include the
Sales Cloud standard objects. There is no scratch org edition or feature combination that
removes Opportunity, Campaign, Lead, and Case from an org's schema. A true Platform-only
org is a licensing state of a production org, not a scratch org shape.

So the check cannot be performed the way the plan describes it. Under plan Section 9.3
the platform wins and the workaround is recorded here.

## Decision

The **Platform-only shape in CI is a Developer edition scratch org with no Sales or
Service features requested**, defined in `config/scratch-defs/platform-only.json`. Since
that org still contains the standard objects, the actual Platform-license constraint is
verified by three mechanisms rather than by the org's schema:

1. **A static CI check**, `scripts/ci/check-standard-objects.sh`, which fails the build
   if source in Core, Giving, Volunteers, Programs, or Funders references Opportunity,
   Campaign, Lead, Case, Person Account fields, or any Industries object. This enforces
   the hard rule in plan Section 4.2 directly, at the level where it is actually stated.
2. **A license-shaped user.** The scratch org creation script creates a user holding the
   Salesforce Platform user license and assigns every Core permission set to that user.
   That assignment fails if any packaged permission set grants access to an object the
   Platform license cannot see, which catches the most common way a standard-object
   dependency leaks in: a permission set, not Apex.
3. **Connect exercised elsewhere.** Connect's dynamic Apex is the one place standard
   object references are allowed, and it is exercised in the org shapes where those
   objects are present (Sales Cloud, NPSP, Person Accounts), with its graceful-degradation
   path covered by tests that describe the object away.

## Alternatives considered

- **Skip the shape** and rely on code review to catch standard-object references:
  rejected, because the Platform-license floor is the product's central compatibility
  promise (ADR-0009) and review does not catch permission set leakage.
- **Maintain a real Platform-license org by hand** and run tests against it: it would be
  a true test, but it is not reproducible in CI, cannot be created per pull request, and
  drifts from the repository over time.
- **Wait for a scratch org edition that omits Sales Cloud objects**: none exists and none
  is announced; the requirement cannot wait on it.

## Consequences

- The CI shape is a **proxy**, not the real thing, and this must not be forgotten. A
  manual check on a real Platform-license org is part of the v0.10 hardening iteration,
  alongside the security review remediation and the scale test.
- The standard-object grep is maintained metadata: it must be extended as new Industries
  object names appear, and as new packages are added to the repository. A stale grep is a
  silently weakened gate.
- The grep works on source, so it can produce false positives on words like "Case" in
  comments and labels. It matches API-name patterns and is kept narrow enough to stay
  useful; a legitimate match in Connect is excluded by path, not by an inline suppression.
- Because mechanism 2 depends on permission set assignment failing loudly, packaged
  permission sets must never be permissive by accident, which is consistent with the rule
  that they are never meant to be cloned (plan Section 4.8).
