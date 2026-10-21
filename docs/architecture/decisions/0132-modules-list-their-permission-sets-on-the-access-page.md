# ADR-0132: A module lists its permission sets on the Access page by shipping Access Add-On rows

**Status:** Accepted
**Date:** 2026-10-20
**Source:** final audit finding S1 (module permission sets can be assigned only in Setup); plan
Section 7.4 ("no Setup step required for normal use") and the non-negotiable that every admin
setting lives in the in-app console; builds on ADR-0017, ADR-0059, ADR-0121 and ADR-0131.

## Context

The Access page gives a person a role (a packaged permission set group) or an extra
permission (an add-on permission set). `AccessService.ADD_ON_PERMISSION_SETS` lists only
Core's six add-ons, and the page refuses any name not on that list, so it never assigns an
arbitrary permission set. A module's sets (Giving Admin, Giving Staff, Giving Read Only,
Campaign Sync, Opportunity Mirror, Accounting Export, Inbound Gift API, Record Inbound Gift
Action) are in no Core role, and Core may not name them (ADR-0059), so an administrator had to
leave BarnCRM for Setup to give them.

ADR-0131 already keeps some module sets in step with the roles automatically (Volunteers by
role, Rollup Builder by Core set). That suits a set every holder of a role should have. It does
not suit a set only some people should have, such as Accounting Export for the bookkeeper or
Giving Admin for a second administrator: those are a choice per person, which is what an
extra permission is.

## Decision

1. **A new Core custom metadata type, `Access_Add_On__mdt`,** with three fields:
   `Permission_Set__c` (the set's API name, without a namespace prefix),
   `Description_Label__c` (the name of a custom label, shipped by the same package, holding
   the one sentence the page shows) and `Sort_Order__c`. A module ships one protected row per
   set it wants on the page, as it ships Setting Definition and Automation Registry rows
   (ADR-0017). Core names no module set: the names are data in the module's own rows.
2. **The Access page lists Core's six add-ons, then every registered row,** in sort order,
   and the allowlist the page checks before giving or removing is the same list. A row counts
   only when it is in the package's own namespace and its permission set is a packaged set in
   that namespace, so a row or a set an org creates itself is never used. A row naming one of
   Core's add-ons again is ignored. A module that is not installed ships no rows and its sets
   do not exist, so the page lists nothing for it.
3. **The sentence comes from the module's label,** read by name with `System.Label.get` in the
   package namespace. A row whose label cannot be read is still listed, without a sentence,
   rather than taking the page down.
4. **Only sets a person is given by choice are registered.** Giving registers its three sets
   and Mirror its five. A set a module's access sync keeps in step with a role (ADR-0131:
   Volunteers, Rollup Builder) is not registered, because removing it on the page would be
   undone by the next sync.
5. No module set is marked as removing data. The warning stays on Core's Bulk Delete and
   Erase People.

## Alternatives considered

- **A field on `BarnCRM_Module__mdt` listing the module's add-on sets.** Rejected: the module
  catalog rows ship in Core, so Core would name module sets, which ADR-0059 forbids and
  `check-core-names-no-module.py` fails.
- **A convention class per module (`<ModuleKey>AccessAddOns`), as ADR-0131 does for syncs.**
  Rejected: a list of names and labels is data, and every other module catalog Core reads
  (Setting Definition, Automation Registry) is custom metadata a module ships.
- **Plain description text on the row.** Rejected: user-facing text lives in custom labels so
  it can be translated.
- **Add the module sets to Core's roles.** Rejected: a Core group cannot include a set from a
  package that depends on Core, and most of these sets are per person, not per role.

## Consequences

- An administrator gives Giving Admin, Campaign Sync, Accounting Export and the rest on the
  Access page, under Extra permissions, with the same checks as Core's add-ons (Manage BarnCRM
  Settings plus Assign Permission Sets, ADR-0121) and the same per person refusal message
  when a license does not allow what the set grants.
- A future module puts a set on the page by shipping a row and a label; Core does not change.
- Canonical model gains the Access Add-On section.
