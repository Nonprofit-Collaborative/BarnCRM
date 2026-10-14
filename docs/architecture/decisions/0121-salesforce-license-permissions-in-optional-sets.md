# ADR-0121: Permissions only a Salesforce license can hold live in optional sets, never in a role

**Status:** Accepted (builder decision; confirm on review)
**Date:** 2026-10-14
**Source:** ADR-0013 mechanism 2 failing on barn-core, a fresh Platform-only scratch org;
ADR-0050 (the same pattern for duplicate record sets); plan Section 4.2

## Context

ADR-0013 verifies the Platform-only floor by assigning every Core permission set to a user
with the Salesforce Platform license. On barn-core that check stopped at two sets:

- **BarnCRM_Admin** was refused: the Salesforce Platform license cannot hold the user
  permissions Assign Permission Sets or View All Users. C-06 had added both so that a BarnCRM
  Admin who is not a system administrator could give roles on the Access page (user-mode
  insert and delete of `PermissionSetAssignment`) and see colleagues in its search box. The
  Module Manager's "give me the module's admin set" step uses the same Salesforce permission.
- **BarnCRM_Duplicate_Review** was refused, as ADR-0050 already says it must be: only a Sales
  Cloud or Service Cloud license can be given duplicate record sets. The set was always
  optional and in no role; the check simply did not know that.

So BarnCRM_Admin, and through it the BarnCRM Admin role, could not be given to a Platform
user at all, which breaks the floor for the whole settings console, not just the Access page.

## Decision

1. A permission the Salesforce Platform license cannot hold is never granted by a set that a
   role uses. It goes in an **optional set named for it, in no permission set group**, the
   pattern ADR-0050 set for duplicate record sets.
2. **BarnCRM_Admin drops Assign Permission Sets and View All Users.** They move to a new
   optional set, **BarnCRM_Access_Manager**, for a BarnCRM Admin on a Salesforce license who
   is not a system administrator. A system administrator already holds both through the
   profile, so the installing administrator loses nothing.
3. **The license check expects the optional sets to be refused** and skips them; it tries
   every other Core set and names every refusal before failing. The list of optional sets,
   the license-limited objects and the license-limited user permissions live in
   `scripts/ci/check-permission-sets.py`, which fails CI if any other set grants one, and the
   org check reads its list from there.

## Alternatives considered

- **Document that BarnCRM Admin needs a Salesforce license.** Rejected: it gives up the
  Platform-only floor for every admin feature to keep one page's write path, and a nonprofit
  whose settings person has a Platform license could not configure BarnCRM at all.
- **Remove the two permissions with no replacement.** Rejected: a BarnCRM Admin on a
  Salesforce license who is not a system administrator could no longer give roles, a
  functionality loss. The optional set keeps it with one Setup assignment.
- **Exempt BarnCRM_Admin from the license check.** Rejected: the check is the only thing
  that catches a license-limited grant leaking into a role (ADR-0013 consequences).

## Consequences

- On a Platform license, the BarnCRM Admin role gives the whole settings console. Giving roles
  on the Access page, and the Module Manager handing its admin set to the person who turned a
  module on, need Assign Permission Sets, which that license cannot have. The Access page
  checks this up front (below); the Module Manager's grant is refused by the platform and
  shows its error message. Such an org gives roles through an administrator with a
  Salesforce license.
- A BarnCRM Admin on a Salesforce license who is not a system administrator needs BarnCRM
  Access Manager, assigned in Setup, to give roles. The admin guide's Access page says so.
- Without View All Users, a person finds colleagues in the Access search box through the
  org's User sharing (public read only by default). An org that made User private gives the
  people who manage access BarnCRM Access Manager, or View All Users through their profile.
- The Access page uses one check for roles and add-ons, the one pull request #402 added for
  add-ons (`AccessService.changeRefusal`: Manage BarnCRM Settings, plus Assign Permission
  Sets or Manage Users from any source). A person who fails only the second sees who holds
  what, with Give access disabled, no Remove or add-on controls, and a notice
  (`Core_Access_ErrorNeedsAccessManager`) naming BarnCRM Access Manager and the
  Salesforce-license limit; the server returns the same message if a change is attempted.
  BarnCRM Access Manager stays off the add-on allowlist: it is assigned in Setup.
- Test users who give roles as a non-administrator hold BarnCRM Access Manager as well as the
  BarnCRM Admin role.
