# ADR-0237: The suite ships nine console apps

**Status:** Accepted (owner decision)
**Date:** 2026-11-21
**Source:** Brandon, plan D-220, D-221 and D-222 (item APP-01, release 1.36): only
console-navigation apps ship, exactly nine of them, and the universal modules never appear in a
nonprofit app. Amends ADR-0137 (four BarnCRM apps, standard and console), ADR-0192 (Batch C
modules add their tabs to the BarnCRM apps), ADR-0223 (module apps, capped test orgs) and
ADR-0226 (Memberships and Scholarships apps). Builds on ADR-0013 (Core runs alone), ADR-0102
(console app) and the Module Home pattern (ADR-0236, `0236-module-home-pattern.md`, release
1.34).

## Context

The suite shipped 17 apps: four Core apps (everyday and admin, each in standard and console
navigation, ADR-0137), Fundraising in standard navigation, and a console app for almost every
module (ADR-0223, ADR-0226, and BarnCRM Connector). The App Launcher was long, two Core apps
repeated the other two, Fundraising was the one module app that did not open records in tabs, and
a scratch or Developer Edition org could take only nine of them, so `capped-org-apps.py` left
eight module apps out of every test org. Several module apps held two to five tabs.

## Decision

1. **Console navigation only.** `BarnCRM_Standard` and `BarnCRM_Admin_Standard` go, with their
   permission sets (`BarnCRM_App_Standard`, `BarnCRM_App_Admin_Standard`) and the App Navigation
   Style setting (`BarnCRM_Settings__c.App_Navigation_Style__c` and its Setting Definition), which
   only chose between the styles. `TabAccessService` keeps the two console app sets always on.
2. **Fundraising is a console app** with its utility bar and a workspace mapping for each tab.
   The Metadata API refuses to change an existing app's `navType` (ADR-0102), so the app takes a
   new API name, `BarnCRM_Fundraising`, and `Fundraising` leaves through the destructive manifest.
3. **Nine apps.** Universal (every organization): BarnCRM Console (`BarnCRM`), BarnCRM Admin
   Console (`BarnCRM_Admin_Console`), BarnCRM Members and Partners (`BarnCRM_Members_Partners`,
   new, in Core), BarnCRM Events, BarnCRM Projects. Nonprofit: BarnCRM Fundraising, BarnCRM
   Grants (`BarnCRM_Funders`), BarnCRM Programs, BarnCRM Volunteers. The apps of Connector,
   Corporate Hub, Forms, Memberships, Portal Builder and Scholarships go.
4. **The catalog's App Name says where a module's tabs go.** `module-app-tabs.py` (ADR-0137,
   the source deploy's last stage) reads each module's `BarnCRM_Module__mdt` row:
   - `App_Name__c` names an app another package ships (a host app): the module's staff and admin
     tabs join it, before its Reports, Dashboards and Error Log tabs, in catalog order. Memberships
     and Corporate Hub name `BarnCRM_Members_Partners` (Core); Scholarships names
     `BarnCRM_Funders`.
   - `App_Name__c` names the module's own app: the app already lists its tabs; they join no
     other app. BarnCRM Console no longer repeats every module's tabs.
   - `App_Name__c` is empty (Forms, Portal Builder, Connector and the tool modules), or names a
     host app whose package is not deployed (Scholarships without Grants): staff tabs join
     BarnCRM Console.
   - Admin tabs always join BarnCRM Admin Console too, so every admin tool is in one app.
   Forms splits its tabs to match: Forms and Form Submissions are staff tabs (BarnCRM Console,
   where staff fill in forms and work submissions); Forms Home and Forms are admin tabs (BarnCRM
   Admin Console, beside Portal Builder and Super Connector).
   Corporate Hub's catalog row gains its three privacy tabs, which only its app listed.
5. **Members and Partners lives in Core** so either Memberships or Corporate Hub alone fills it:
   a module may not depend on another module, and Core is the one package both depend on. Core's
   file lists only Reports, Dashboards and Error Log, so the app opens on Memberships Home, or on
   Corporate Hub Home when Memberships is not installed (Memberships sorts first in the catalog).
   Its visibility is in the Memberships and Corporate Hub role sets (a module set may grant a
   Core app), so nobody sees it until one of the two is installed. Its logo,
   `BarnCRM_Patch_Members_Partners_Logo`, is made from the Memberships Patch master.
6. **Scholarships joins Grants without a dependency.** Scholarships does not depend on Funders
   and Funders does not depend on Scholarships, so neither package names the other's tabs. The
   same deploy step adds them, and Grants keeps Grants Home first. The Grants app gains
   Dashboards for the Scholarships dashboard. Scholarships' sets cannot show an app in a package
   it does not depend on, so a host app outside Core also leaves the staff tabs in BarnCRM
   Console, and the Scholarships sets show BarnCRM Console: Scholarships-only staff keep an app.
7. **The universal modules stay out of nonprofit apps.** Memberships, Corporate Hub, Forms, Events
   and Projects never name Fundraising, Grants, Programs or Volunteers as their app; a CI test
   (`test_module_app_tabs.py`) holds the rule.
8. **Every org gets every app.** Nine apps fit `CAPPED_ORG_APP_BUDGET` (9), so `LEFT_OUT` in
   `capped-org-apps.py` is empty and a capped org deploys every module whole. The mechanism and
   its CI tests stay, so a tenth app must fit or be left out; a test also holds the suite at nine
   console apps.

## Alternatives Considered

- **Keep the standard-navigation apps beside the console ones.** Doubles the Core apps for a
  choice the owner retired, and keeps a setting whose only job is to hide half of them.
- **Members and Partners in the Memberships package, Corporate Hub depending on it.** Corporate
  Hub alone would then need Memberships installed, which the owner ruled out.
- **Scholarships depending on Funders, or Funders naming the Scholarships tabs.** Either makes
  one module require the other for a navigation convenience.
- **A new catalog field naming the host app.** `App_Name__c` already names the app a module
  opens in (the Home hub's Open the App link); pointing it at the host app gives the right link
  and the deploy rule with no field added.
- **Write the apps through the org connection after a package install.** Still unproven for a
  packaged app (ADR-0192, Alternatives); the Setup Assistant keeps listing the pages to add.

## Consequences

- An org deployed from source gets the nine apps with each module's tabs in place. An org that
  had the removed apps keeps them until the release's destructive manifest deletes them
  (`build-destructive-manifest.py` lists each removed `CustomApplication`, permission set, field
  and Setting Definition): `BarnCRM_Standard`, `BarnCRM_Admin_Standard`, `Fundraising`,
  `BarnCRM_Connector`, `BarnCRM_Corporate_Hub`, `BarnCRM_Forms`, `BarnCRM_Memberships`,
  `BarnCRM_Portal_Builder`, `BarnCRM_Scholarships`.
- Nobody who had an app loses one. Each set that showed a removed module app now shows a Core
  app: the Forms Staff, Read Only and Scholarships sets show BarnCRM Console; Forms Admin shows
  BarnCRM Console and BarnCRM Admin Console; Portal Builder Admin and both Connector sets show
  BarnCRM Admin Console. A CI test (`test_core_navigation.py`) holds every set that showed an app
  to showing at least one shipped app.
- Scholarships staff see the Grants app only with a Grants role set, and the Scholarships pages
  in BarnCRM Console always. With Grants installed but not visible to the user, the Home hub's
  Open the App link for Scholarships points at an app they cannot open.
- A package install still needs the administrator to add hosted tabs in App Manager; the Setup
  Assistant's Modules step lists them.
- Module logos with no app stay as content assets for the Home hub's Modules list.
