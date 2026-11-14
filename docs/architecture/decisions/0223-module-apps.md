# ADR-0223: The big modules ship their own apps, left out of capped test orgs

**Status:** Accepted (builder decision)
**Date:** 2026-11-13
**Source:** Brandon, 2026-11-13: the big modules get their own Lightning app now (Events,
Projects, Corporate Hub, Portal Builder, Forms), and their tabs stay in the BarnCRM apps.
Amends ADR-0192 (Batch C modules add their tabs to the BarnCRM apps instead of shipping an app),
decision 1. Builds on ADR-0137 (module tabs reach the Core apps from outside Core's metadata),
ADR-0013 (Core runs alone) and ADR-0194 (role trio permission sets).

## Context

ADR-0192 took the Forms, Event Management and Portal Builder apps out because scratch orgs
refused a deploy past about 10 custom apps (`barn-sales` and `oi-test`, 2026-11-07), and later
modules (Corporate Hub, Project Management) followed it. The limit belongs to scratch and
Developer Edition orgs, which is what every test org is (`barn-sales`, `oi-test`,
`barn-platform`). Real orgs (Enterprise Edition and up, and their sandboxes, such as
`mwdbdevsb`) allow far more, and an app in a managed package does not count toward the limit at
all. The suite ships 8 apps today; five more makes 13.

A permission set that grants visibility to an app the org does not have fails to deploy, so
leaving an app out also means leaving its visibility out of every set that names it.

## Decision

1. **Five module apps.** Each ships a console app in its own package, with its logo
   (`scripts/brand/make-logos.py`), its tabs, standard Reports, and Error Log last (D-135):
   BarnCRM Events (`BarnCRM_Events`), BarnCRM Forms (`BarnCRM_Forms`), BarnCRM Portal Builder
   (`BarnCRM_Portal_Builder`, the admin header color), BarnCRM Corporate Hub
   (`BarnCRM_Corporate_Hub`, with Dashboards) and BarnCRM Projects (`BarnCRM_Projects`). Each
   catalog row's `App_Name__c` names the app, so the Home hub offers Open the App. App
   visibility is in the module's Staff set, so the generated Admin and Read Only sets carry it
   too (Portal Builder: its Admin set, the only role set it has).
2. **Tabs stay in the BarnCRM apps.** ADR-0192's catalog tabs and `module-app-tabs.py` step are
   unchanged, so the modules are reachable from BarnCRM and BarnCRM Console (BarnCRM Admin and
   BarnCRM Admin Console for Portal Builder) with or without their own app.
3. **Record pages stay the object default.** The objects' own `actionOverrides` (ADR-0192
   decision 2) already open the module record pages from every app, so the new apps carry no
   overrides.
4. **Capped orgs leave the five apps out.** `deploy-packages.sh` asks the org for
   `OrganizationType` and `TrialExpirationDate`. A Developer Edition org, or any scratch org
   (every scratch org has a trial expiration date, whatever its edition), is capped. On a
   capped org the five modules, listed in `LEFT_OUT` in `scripts/org/capped-org-apps.py`,
   deploy without their `applications` and `permissionsets` folders, and their permission sets
   follow in a stage of their own, written by that script with the left-out apps' visibilities
   removed. Every other org gets every app. A failed lookup counts as not capped: a real org
   must never lose an app, and a capped org then fails on the limit with the platform's own
   message. `MODULE_APPS=capped` or `all` overrides the lookup.
5. **A budget keeps the next app honest.** `CAPPED_ORG_APP_BUDGET` (9) is how many suite apps a
   capped org may receive. A CI test fails when the apps not left out exceed it, and when a
   permission set outside the left-out folders grants a left-out app.

## Alternatives Considered

- **No module apps (ADR-0192 as it was).** Real orgs would lose the apps the owner asked for to
  protect test orgs.
- **Count the org's apps and leave out only what does not fit.** The limit is not queryable,
  and an org-dependent set of apps would make test orgs differ from each other run to run.
- **A separate permission set per app for visibility.** Keeps the source sets unchanged on a
  capped org, but adds five sets to assign, sync and explain, for a test-org-only problem.
- **Temporary `.forceignore` entries.** Changes a tracked deploy input during a run, which the
  skip-unchanged record fingerprints, and still leaves the permission sets naming the apps.

## Consequences

- Real orgs and the packages get 13 apps; scratch and Developer Edition orgs get 8, with every
  module tab still in the BarnCRM apps.
- On a capped org the Home hub's Open the App link for these five modules points at an app the
  org does not have; test the five apps on a real org (`mwdbdevsb`).
- A new module app either fits the budget or joins `LEFT_OUT`; the CI test says which.
- Switching an org between capped and all (`MODULE_APPS`) needs `--full` once, since the
  skip-unchanged record does not know the mode.
