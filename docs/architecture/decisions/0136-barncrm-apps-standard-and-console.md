# ADR-0136: Four BarnCRM Apps, Everyday and Admin, Each in Standard and Console Navigation

**Status:** Accepted (owner decision, 2026-10-26)
**Date:** 2026-10-26
**Source:** Brandon, 2026-10-26: two app families, "BarnCRM" for everyday staff and "BarnCRM
Admin" for administrators, and "Please include a classic and a console version of each app so
the user can decide which to use and they can hide the other types if they want." Module apps
"can stay separate but with notes and/or navigation assistance to help them find them when
installed." Amends ADR-0102 (the BarnCRM app is a console app).

## Context

Core shipped one app, BarnCRM, a console app holding everything: the everyday record tabs and
every administrator tool (BarnCRM Settings, Data Manager, Org Optimizer, Error Log). Staff saw a
long menu of tools they could not use, and people who prefer records to replace the page had no
standard-navigation choice. Each module also shipped its own app, so an administrator had to know
which app held which tool.

## Decision

1. **Four Core apps.** "Classic" in the owner's request means standard Lightning navigation, not
   the Salesforce Classic interface; labels and docs say standard navigation.

   | Label | API name | Navigation | Tabs |
   |---|---|---|---|
   | BarnCRM | `BarnCRM_Standard` | Standard | Home, Contacts, Households, Organizations, Find |
   | BarnCRM Console | `BarnCRM` | Console | The same, plus Addresses, Relationships, Affiliations and Household Members |
   | BarnCRM Admin | `BarnCRM_Admin_Standard` | Standard | BarnCRM Settings, Data Manager, Import, Bulk Update, Org Optimizer (`Data_Hygiene`), Error Log |
   | BarnCRM Admin Console | `BarnCRM_Admin_Console` | Console | The same |

   The console app keeps the API name `BarnCRM` because the Metadata API refuses to change an
   existing app's `navType` (ADR-0102), and the four in-app guidance prompts name that app.
   The console staff app carries the four child record tabs because the platform accepts a
   workspace mapping only for a tab in the app (ADR-0102, decision 2); the standard app leaves
   them out, since they are reached from the related lists. The admin apps hold no record tab
   but the Error Log. Every app assigns the household and person record pages, so a record
   opened from any of them looks the same.

2. **Visibility through synced permission sets.** No role set shows an app any more. Four
   `BarnCRM_App_*` sets each show one app and nothing else, and `TabAccessService` gives and takes
   them the way it does the tool tab sets (ADR-0124): the everyday apps go to holders of
   BarnCRM Admin, BarnCRM Staff and BarnCRM Read Only (directly or through a role), the admin
   apps to BarnCRM Admin holders only. The same queued, sliced, nightly-checked sync covers both.

3. **App Navigation Style setting.** One row in BarnCRM Settings, General, saved org-wide on
   `BarnCRM_Settings__c.App_Navigation_Style__c`: Both (default), Standard or Console. It says
   which style's app sets are on; a save that changes it queues the sync. Each person still
   chooses their own default app in the App Launcher; the setting is how an administrator hides
   one style for everyone.

4. **Module apps stay.** Fundraising and BarnCRM Volunteers keep their own apps. The BarnCRM
   Rollup Builder app is retired and its tool joins the admin apps. Core cannot name a module's
   tab in its apps (ADR-0013: Core runs alone, and a deploy fails on a missing tab), so module
   tabs reach the Core apps from outside Core's metadata: the source deploy script adds each
   deployed module's tabs, and an installed package's tabs are listed for the administrator to
   add in App Manager. The home page's Modules list links each installed module to its own app.

5. **A logo for every app.** Owner, 2026-10-26: "Please make sure each of the apps has a logo.
   These logos can have a distinction to show which is the admin app." BarnCRM and BarnCRM
   Console keep the barn (`BarnCRM_Logo`, header `#007A9E`). The admin apps use
   `BarnCRM_Admin_Logo`, the same barn with a navy badge holding a white gear, and a navy header
   (`#032D60`; white text on it is about 14:1). A module app gets the same barn with its own
   badge, shipped as a ContentAsset in the module's own package (a module does not rely on
   naming Core's asset once the packages are namespaced). `scripts/brand/make-logos.py` makes
   every variant from the master with the standard library only, so they can be regenerated.

## Consequences

- An upgraded org keeps the console app it had under its old API name, relabelled BarnCRM
  Console, and gains the three new apps. Until the first sync runs, nobody sees an app: the
  install, the Access page, a source deploy and the nightly run all queue it.
- A person with only an extra permission (Find and Export, Bulk Update, Duplicate Review) and no
  BarnCRM role sees no BarnCRM app, as before when no role meant no app. A non-admin with Bulk
  Update or Duplicate Review reaches Data Manager or Org Optimizer from the App Launcher, since
  those tabs are now only in the admin apps.
- The in-app guidance prompts stay on the console app: a prompt names exactly one app.
