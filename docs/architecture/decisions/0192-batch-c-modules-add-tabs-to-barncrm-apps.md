# ADR-0192: Batch C modules add their tabs to the BarnCRM apps instead of shipping an app

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** D-188 (owner decision, Brandon, 2026-11-07: "Yes, they can use the existing app(s)").
Amends ADR-0175 (Forms), ADR-0177 (Event Management) and ADR-0185 (Portal Builder), each of
which shipped a console app. Builds on ADR-0013 (Core runs alone) and ADR-0137 decision 4 (module
tabs reach the Core apps from outside Core's metadata).

## Context

Forms (`BarnCRM_Forms`), Event Management (`BarnCRM_Events`) and Portal Builder
(`BarnCRM_Portal_Builder`) each shipped a Lightning app. The suite reached 12 custom apps; a
scratch org (and possibly some customer editions) refuses a deploy past about 10, and an app
deployed from source counts toward the limit. oi-test is already at its limit.

Core's four apps cannot list a module's tab in source: Core deploys without the module, and a
deploy naming a missing tab fails (ADR-0013). ADR-0137 already solved this for Giving,
Volunteers, Rollups and Mirror: each module's `BarnCRM_Module__mdt` row names its tabs
(`Staff_Tabs__c` for BarnCRM and BarnCRM Console, `Admin_Tabs__c` for BarnCRM Admin and BarnCRM
Admin Console), and `scripts/org/module-app-tabs.py`, the last stage of
`scripts/org/deploy-packages.sh`, deploys copies of the Core apps with those tabs added, before
Error Log. The three Batch C rows already name their tabs.

## Decision

1. **No app of their own.** The three app files go, with the module permission sets'
   `applicationVisibilities` and the catalog rows' `App_Name__c`. Their tabs reach the BarnCRM
   apps through the ADR-0137 step, unchanged: Forms (Forms, Form Submissions) and Event
   Management (Events Home, Events, Event Speakers) join BarnCRM and BarnCRM Console; Portal
   Builder (Portals, Portal Accesses) joins BarnCRM Admin and BarnCRM Admin Console. The script
   inserts before Error Log, so Error Log stays last (D-135).
2. **Record pages as the org default.** The module apps assigned `Form_Record_Page`,
   `Form_Submission_Record_Page` and `Event_Record_Page`. Those assignments move to each
   object's own `actionOverrides` (View, Flexipage, Large and Small), the org default, so the
   page opens from any app, including the App Launcher's All Items, with no app to carry it.
3. **Removal resets the apps.** `module-app-tabs.py --all` writes all four Core apps, each as
   Core ships it plus the tabs of the folders named, whether or not anything changed.
   `deploy-packages.sh` passes `--all`, so every source deploy leaves the apps holding exactly
   Core plus the modules it deployed. Removing a module from a source install deploys the
   apps this way, naming only the modules kept, before the destructive delete of the module.
4. **Package installs keep the ADR-0137 fallback.** Until BarnCRM ships as packages, the source
   deploy is the only install path, and it is automatic. For a package install, the Setup
   Assistant's Modules step lists each module's pages to add in App Manager, the Home hub's
   Modules list names the module, and each object tab is in the App Launcher.

## Alternatives Considered

- **Keep the three apps.** Breaks scratch orgs and oi-test at the custom app limit.
- **Write the apps through the org connection (`Barn_Org_Connection`, ADR-0148, ADR-0174).**
  `OrgToolingApi` already calls the org's Metadata API, so a queued job could read each Core
  app and add a module's tabs after a package install. Not chosen now: the connection needs an
  administrator's Setup step (ADR-0148 A1) and is off in many orgs, a packaged app's editable
  navigation in a subscriber org is unproven, and today's only install path, the source deploy,
  is already automatic. Revisit when the packages ship.
- **Name the module tabs in Core's apps.** A Core-only deploy fails (ADR-0013).

## Consequences

- An org deployed from source gets the module tabs in the BarnCRM apps with no Setup step.
- Three fewer custom apps (9 in the suite); the BarnCRM Forms and Events logos stay as content
  assets for the Home hub's Modules list.
- An org that already has a module app keeps it until the release's destructive manifest
  deletes it (`build-destructive-manifest.py` lists the removed `CustomApplication`).
- The Home hub shows no Open the App link for these modules, as for Rollups and Mirror.

**Amended by ADR-NEXT (2026-11-13):** Events, Forms, Portal Builder, Corporate Hub and Projects
ship their own apps again, their tabs stay in the BarnCRM apps, and scratch and Developer Edition
orgs are deployed without those five apps.
