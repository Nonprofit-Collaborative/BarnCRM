# ADR-NEXT: A Blank Feature List Means No Feature Is On

**Status:** Accepted (owner decision, 2026-11-18)
**Date:** 2026-11-19
**Source:** Brandon, 2026-11-18: BarnCRM is unreleased, so code kept only for earlier builds goes
(batch O, O-01, D-207). Amends ADR-0124 `0124-edition-gates-visibility.md`, which read an empty
`Features_Turned_On__c` as every feature on.

## Context

ADR-0124 gave an empty list two readings it could not tell apart from a value: a new install
stored `None`, and empty meant every feature was on, for orgs that had run builds from before
features existed. No released org has such a history, and a blank value that means "all" turns
every feature on for any org whose list is lost or never written.

## Decision

1. **Post-install fills a blank list.** Every Core post-install run (install, upgrade, source
   deploy, Finish Setup) calls `FeatureSwitchService.fillBlankList`: a new install stores `None`,
   an org already in use stores every feature's key, as it has run with them on. A list with a
   value is never changed.
2. **Blank means what it says.** `featuresOn` reads a blank list as no feature on. `None` and
   `NoneChosen` keep their meaning.
3. **Tests.** An Apex test never sees a list that post-install filled, so a blank list reads as
   every feature on in a test (`FeatureSwitchService.blankIsAllOnInTests`); a test of the blank
   reading turns that off.

## Consequences

- An org already running a build with a blank list needs Core's post-install run once on the
  next deploy (`CorePostInstall.runAsSourceDeploy`, which `scripts/org/deploy-packages.sh` runs);
  until then its features read as off.
- ADR-0124's "an upgraded org has it empty, which means every feature is on" no longer holds.
