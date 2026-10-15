# ADR-0003: Core package plus separate module packages, feature flags for minor behavior

**Status:** Accepted
**Date:** 2026-09-06
**Amended by:** ADR-NEXT (`NEXT-rollup-builder-module.md`): the rollup engine and the Rollup
Builder leave Core for a module of their own, BarnCRM Rollup Builder, which Giving depends on.
**Source:** plan Section 12, decision D-03

## Context

Principle 3 says: turn on only what you use, and a module that is off leaves nothing
behind in the org, no objects, no tabs, no triggers. Plan Section 3.3 item 4 names
"everything always installed" as one of NPSP's mistakes: an org that never ran a
volunteer program still carried the schema, the layouts, and the settings for one.

On the Salesforce platform, a feature flag can hide a tab and skip a trigger, but it
cannot remove an object. Schema installed is schema present: in the object list, in
report type pickers, in field pickers, in duplicate rules, and in every list a confused
administrator scrolls through. Only package boundaries actually remove it.

The cost of package boundaries is install friction: the administrator installs and
upgrades several packages instead of one.

## Decision

Heavy domains ship as **separate managed packages that depend on Core**: Giving,
Volunteers, Programs, Funders, Connect, and later Events. Core contains the constituent
model, the Nonprofit Hub app, the settings framework and console, the Module Manager,
permission sets, the trigger framework, the error log, the rollup engine, and the import
framework.

**Minor behavior inside a package is feature-flagged** with a hierarchy custom setting
per feature, exposed as a toggle in the settings console.

The dividing rule: **flags are for behavior, not for hiding schema.** A capability that
adds objects an org may never need is a package. A capability that changes how existing
objects behave is a flag.

## Alternatives considered

- **One package with everything, features hidden behind flags**: simplest install, but
  it violates Principle 3 in exactly the way NPSP did. Rejected.
- **A package per feature**: maximum removability, unusable install experience, and an
  unmanageable dependency graph. Rejected.
- **Core and Giving as one package** because nearly every org needs both: genuinely
  arguable, and it is open question 5 in plan Section 11.2. The current plan keeps them
  separate in the repository and revisits the packaging decision at v0.5 on measured
  install-friction evidence. Not decided here.

## Consequences

- Multi-package install and upgrade orchestration is real work, and it is paid by the
  Module Manager (C-24, v0.7): install links with instructions, "turn on" running the
  module's post-install configuration, "turn off" disabling automation and hiding tabs,
  and an uninstall pre-flight report of data that would be lost.
- Every new package costs install friction, so a package is justified only when its
  schema would clutter an org that does not need it (plan Section 6.2 rule 5).
- Cross-package calls go through `global` service interfaces only (plan Section 7.1), so
  the module boundary is a real contract and not an accident of file layout.
- Features must degrade gracefully when a module is off, and the review checklist asks
  this of every pull request (plan Section 9.4).
- Core plus Giving may ship as a bundled install link if beta evidence shows the friction
  is hurting time-to-first-gift (plan Section 11.1).
