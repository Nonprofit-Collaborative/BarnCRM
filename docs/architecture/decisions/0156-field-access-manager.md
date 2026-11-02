# ADR-0156: Field Access Manager changes Read and Edit on permission sets the admin chooses, previewed, journaled and undoable

**Status:** Proposed
**Date:** 2026-11-02
**Source:** plan release 0.17 item C-65 and decision D-157 (Brandon, 2026-10-31: all eleven
research proposals approved, C-65 placed in 0.17); amends ADR-0047 and the plan Section 4.9
"What we deliberately do not build" line for permission management. Extends Access Explorer
(C-53, C-53b); admin guide `field-access-manager.md`.

## Context

ADR-0047 and D-13 listed permission tools among the things BarnCRM never builds: Setup and
Jetstream serve the rare technical user, and a package that writes permissions adds security
review risk. Since then BarnCRM grew Create New Field (ADR-0082), which already gives its own
permission sets access to a field it creates, and Access Explorer (C-53, C-53b), which shows who
can see what and why but is read only. The research for D-156 found the gap Maria actually hits:
after a new field, a new module or a new volunteer role, she has to open each permission set in
Setup, find the object, then tick fields one at a time, with no preview and no way back. Brandon
approved the Field Access Manager in D-157, which reverses the non-goal for this one tool.

Salesforce stores access as `ObjectPermissions` and `FieldPermissions` rows whose parent is a
permission set. The parent can also be a profile's own set, a permission set group's calculated
set, a muting set, a set a managed package installed, a standard set Salesforce ships, or a user
license (`100...`) or permission set license (`0PL...`); rows for licenses are limits, not grants.
Field access means nothing without Read on the object, field Edit needs field Read, object Edit
needs object Read, and Delete and Modify All need Edit. Required and system fields, and fields
Salesforce always shows, cannot be given or taken (`isPermissionable` is false); formula,
roll-up summary and auto number fields can be read but never edited. Orgs have thousands of
fields and permission sets with hundreds of rows each.

## Decision

1. **One narrow tool, inside Access Explorer.** A **Change Field Access** view in Org
   Optimizer's Access Explorer section. It gives or removes **Read** and **Edit** on fields and
   on kinds of record, for permission sets the admin chooses, and nothing else: no Create,
   Delete, View All or Modify All grants, no system or user permissions, no assignments, no
   tabs, no apps. Everything else stays in Setup, and the ADR-0047 "never built" list keeps
   metadata deploy, anonymous Apex, API exploration, org-wide automation switches and
   org-to-org migration.
2. **Only permission sets the organization made.** A set can be chosen only when it is custom
   (`IsCustom`), not owned by a profile, of type Regular (so not a group's calculated set and
   not a muting set) and has no namespace (so not one a managed package installed, BarnCRM's
   own included once packaged). Every query of `ObjectPermissions` and `FieldPermissions` is
   filtered by the Ids of the sets chosen and checked, so license-owned rows are never read or
   written. Up to 10 sets per change.
   **Never a set BarnCRM ships, packaged or not.** The package and the access syncs
   (`TabAccessService`, `ModuleAccessSyncBase`, `RollupAccessSync`) manage those sets' access,
   so an edit there would be overwritten or would drift from what the syncs expect. A packaged
   install hides them by namespace; an unpackaged install (a source deploy, as on the test
   orgs) does not, so they are also excluded by name. The names come from
   `BarnCRMShippedPermissionSets`, generated from every package directory in
   `sfdx-project.json` by `scripts/ci/check-shipped-permission-sets.py`, which fails CI when the
   class and the packages differ. A hand-kept list was rejected: it goes stale when a module
   adds a set.
3. **Never profiles or groups.** Profiles are excluded: Salesforce is moving permissions off
   profiles, a profile change reaches everyone on it at once, and standard profiles cannot be
   changed. A group is changed by changing a set inside it, which Salesforce then recalculates,
   so the tool names the set and never the group.
4. **Dependencies are added, never left to fail.** Giving field Read or Edit adds object Read
   when the set lacks it. Giving Edit gives Read. Giving object Edit gives object Read. Removing
   object Edit also removes Delete and Modify All. Removing object Read removes every object
   flag and the set's access to every field on that kind of record. Fields that cannot be
   changed are not offered; fields that can only be read are offered Read only. The preview
   lists every added change with the reason.
5. **A preview of every row, then a confirmed apply.** The browser sends a change document
   (`{ version, setIds, items: [{ object, field, access }] }`, access `read`, `edit` or `none`;
   a blank field means the kind of record). Apex works out every row change, with its current
   and new access and why, and the browser shows them. Apply works the changes out again and
   refuses when the count differs from the count the admin confirmed, so a change made in Setup
   in between is never applied blind. One apply holds at most 2,000 row changes, inside one
   transaction's limits; a larger change is split by the admin.
6. **Written as the admin, journaled as a data job, undone the same way.** Rows are written in
   user mode, so Salesforce's own Manage Profiles and Permission Sets check applies; a row the
   platform refuses is reported and the rest are kept. Each apply is a data job
   (`Import_Batch__c`, new Operation **Access**) whose definition holds the change document
   and the confirmed count, with every row's before and after access in its journal
   (`Import_Journal__c`, ADR-0047's journal) and the import undo window. **Undo** puts back
   each row whose access is still what the change left, and keeps and reports any row changed
   since. Access jobs are listed and undone only on the Field Access Manager, never by the
   import or bulk update undo.
7. **A strict permission check.** Every method requires BarnCRM Admin's Manage BarnCRM
   Settings permission and the system permission Manage Profiles and Permission Sets, read
   from `UserPermissionAccess`. Without both, the view shows why and offers nothing.
8. **Recorded where admins already look.** Salesforce writes each row change to its Setup
   Audit Trail, which Setup Changes (C-56) copies; the data job's run log names who, when and
   how many; refusals go to the Error Log.
9. **Portable (plan Section 9.9).** Building the change document, checking it, and grouping and
   counting a preview are a framework-free JavaScript module (`fieldAccessPlan`). Apex keeps
   every query, check and write, and returns plain JSON shapes.

## Alternatives considered

- **Keep permission management a non-goal.** Rejected by Brandon in D-157: the Setup path is
  the slowest common admin task left, and Access Explorer already shows what is missing.
- **Change profiles too.** Rejected: see decision 3.
- **The Metadata API (deploy a permission set file).** Rejected: a deploy replaces the whole
  set, needs the Named Credential Create New Field uses, and cannot be previewed row by row or
  undone per row. `ObjectPermissions` and `FieldPermissions` are plain records.
- **A new object for the change history.** Rejected: the data job and its journal already give
  status, owner, an undo window, paged entries and a run log.
- **All or nothing.** Rejected: one refused row (for example, a set whose license does not
  allow an object) would block every other change; the journal records exactly what landed.

## Consequences

- ADR-0047's "Never built" line no longer lists permission tools; plan Section 4.9's non-goal
  line and D-13 are amended to point here.
- Canonical model: `Import_Batch__c.Operation__c` gains the value Access, and a new section
  (Field access change, rules R-FA1 to R-FA7) defines the change document, the journal entry
  and the undo. No new object or field.
- Import history excludes Access jobs (as it excludes Update and Delete), and the import undo
  refuses one.
- The security review submission describes the tool: it writes setup rows in user mode, only
  for sets the admin chose and only after the check in decision 7.
