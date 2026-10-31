# ADR-0102: The BarnCRM app is a Lightning console app with a packaged logo

**Status:** Accepted (owner request)
**Date:** 2026-10-13
**Source:** Brandon, 2026-10-13: "I'd like the BarnCRM app to be a console app and to have some
kind of icon." Admin guide `barncrm-app.md`.

## Context

The BarnCRM app (`packages/core/main/default/applications/BarnCRM.app-meta.xml`) used standard
navigation and the default app icon. Staff move between a household, its people, their
addresses and relationships many times a day; in standard navigation each click replaces the
page.

## Decision

1. **Console navigation.** `navType` is `Console`. Each household, organization, person and
   Error Log record opens in its own workspace tab.
2. **Child records open as subtabs of their parent** through `workspaceConfig`: Address under
   its household (`Account__c`), Relationship and Affiliation under the person (`Contact__c`),
   Household Member under the household (`Household__c`). The platform accepts a workspace
   mapping only for a tab that is in the app's navigation, so the Address, Relationship,
   Affiliation and Household Member tabs were added to the end of the navigation menu (a
   console's navigation is a menu, so the extra items cost little). A child record whose
   parent field is blank opens as its own workspace tab.
3. **No utility bar.** No existing feature needs one.
4. **Logo and brand color.** A flat blue barn with a white X-braced door, shipped as the
   ContentAsset `BarnCRM_Logo` and referenced from `<brand><logo>`. The walls are `#00A8D9`,
   a bright blue whose shade (only the shade) follows the Blue Bottle Coffee logo, per the
   owner (2026-10-13). The header color is `#007A9E`, the same hue darkened, which is also
   the roof color: Lightning puts white text on the header, and `#00A8D9` gives white text
   only 2.76:1, while `#007A9E` gives 4.91:1 (WCAG AA needs 4.5:1). Giving's BarnCRM Fundraising app is unchanged (Core may not reference Giving objects,
   so Giving records keep their own app's behavior).

## Consequences

- The Metadata API refuses to change `navType` on an existing custom app ("NavType isn't
  updateable for custom apps"). A fresh install or a new org is unaffected. A development org
  that already has the standard-navigation BarnCRM app needs one of: change **Navigation
  Style** to **Console Navigation** in Setup, App Manager, BarnCRM, Edit, App Options, then
  deploy; or deploy with a pre-destructive manifest that deletes `CustomApplication:BarnCRM`
  in the same deploy that re-adds it with the three BarnCRM permission sets.
- No BarnCRM package version has been released, so no subscriber upgrade crosses this
  change. If one had, the app would have needed a new API name.
- Record links built as `/lightning/r/<id>/view` or `NavigationMixin` `standard__recordPage`
  open in console tabs. Links to Setup pages leave the console, as in any console app.
