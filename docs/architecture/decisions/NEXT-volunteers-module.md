# ADR-NEXT: The BarnCRM Volunteers module: totals through Rollup Builder, person fields in the module, approval as a status

**Status:** Accepted (owner decision, Brandon, 2026-10-17: decisions D1, D3, D4, D6, D7 and D8 of
the v0.8 Volunteers build plan, each as recommended)
**Date:** 2026-10-17
**Source:** owner decision 2026-10-17; builds on ADR-0003, ADR-0005, ADR-0017, ADR-0018,
ADR-0021, ADR-0029, ADR-0035, ADR-0059, ADR-0071, ADR-0073, ADR-0121, ADR-0124 and ADR-0125.
Recurring shifts (D5) and hour letters (D2) have their own ADRs, written with the V-04 to V-08
design.

## Context

Volunteers (V-01 to V-08, plan Section 5.3) is the first module built after the Rollup Builder
left Core (ADR-0125). On main the module is a placeholder: `packages/volunteers` holds a README,
`sfdx-project.json` lists Core as its only dependency, and Core ships the catalog row
`BarnCRM_Module.Volunteers` (`Editions__c` `Impact`, Sort Order 20). Module Manager, edition
choice and the Settings Modules section already exist (C-24, C-30, ADR-0072, ADR-0073,
ADR-0124). A design branch from 2026-09-09 put the volunteer person fields in Core, totals in a
Core rollup engine and approval behind a custom permission of its own; all three premises have
since changed (ADR-0059 neutral Core, ADR-0125).

## Decision

1. **D1 Totals come from the Rollup Builder module.** Volunteers depends on Core and BarnCRM
   Rollup Builder (`sfdx-project.json`, install order Core, Rollup Builder, Volunteers) and ships
   its totals as 19 `Rollup_Definition_Default__mdt` rows with `Package__c` Volunteers, as Giving
   does (canonical model Section 29O): source Volunteer Hours filtered Status equals Approved, or
   Volunteer Sign-up for the filled count, all mode Both. `VolunteersPostInstall` materializes
   them (ADR-0029). `BarnCRM_Module.Volunteers` gains `Requires__c` `Rollups`. Volunteers ships
   no aggregation code.
2. **D3 Volunteer data lives in the module.** The person fields (status, since, emergency
   contact, availability, and the rollup targets) are shipped by Volunteers on Contact and on
   Account with the same API names (ADR-0005), never by Core: Core stays neutral (ADR-0059,
   `check-core-names-no-module.py`) and an org without the module carries none of them.
   Onboarding steps are a child object (Volunteer Requirement) and skills an admin list with
   junctions to the person and the job, specified with V-04 and V-05.
3. **D4 Four permission sets and a sync.** `Volunteers_Admin` (everything, including the
   settings), `Volunteers_Coordinator` (everything a Staff user has, plus the custom permission
   `Manage_Volunteers`, which approves and rejects hours), `Volunteers_Staff` (jobs, shifts,
   sign-ups and entering hours) and `Volunteers_Read_Only`. `VolunteersAccessSync`, on the
   `RollupAccessSync` pattern through `TabAccessService.giveToHolders`, gives them at install,
   at each Turn on and with each nightly run: Admin to holders of `BarnCRM_Admin`, Coordinator to
   the Coordinator role (`Volunteer_Coordinator`), Staff to the Team Member role
   (`Program_Staff`) and Read Only to the Read Only role (`Read_Only`). It never takes a set away.
4. **D6 Approval is a status on the hours record.** Volunteer Hours carries Status (Submitted,
   Approved, Rejected), Approved By and Approved Date, moved only by `VolunteerHoursService` for
   a user with `Manage_Volunteers`. A validation rule locks an approved entry's person, date and
   hours. Only Approved hours count in any rollup. No Salesforce approval process: there is one
   step and one approver role, and an approval process keeps its state where rollups and the
   settings console cannot reach and needs Setup (plan Section 4.8). The setting Hours Require
   Approval off creates entries Approved.
5. **D7 Done means built and tested unmanaged.** v0.8 is complete when the module is built and
   passes its tests in the development orgs. `Install_Version_Id__c` stays blank and install
   link testing waits for the first package versions (namespace deferred).
6. **D8 Sequencing.** The owner started modules on 2026-10-17, ahead of the order in plan
   Section 6.0 item 3.

## Alternatives considered

- **Totals in Volunteers' own Apex, or through Giving.** Rejected: a second engine duplicates
  the queue, freshness and nightly behavior, and Volunteers must not need Giving.
- **Person fields in Core** (the 2026-09-09 design). Rejected: four volunteer fields in every
  Standard Edition org break neutral Core.
- **A Volunteer object beside the person.** Rejected: a volunteer is a person the organization
  already knows; a second record has to be created and kept in step.
- **A Salesforce approval process.** Rejected for the reasons in decision 4.

## Consequences

- An org without Giving has no `Rollups_Last_Calculated__c` on Account or Contact (Giving ships
  it), so volunteer totals on people carry no freshness line there. The engine skips an absent
  stamp; the totals are still right. Jobs and shifts carry their own stamp.
- Turning Volunteers off stops its registry rows (ADR-0073), so hours saved while it is off are
  not queued. After Turn on, person and household totals catch up at the next nightly run (mode
  Both); until then they can be behind. The admin guide says so and Recalculate all is the
  immediate fix.
- Lightning Platform Starter allows about 10 custom objects per user. A coordinator on that
  license touches the four V-01 to V-03 objects, the V-04 to V-08 objects and Core's own; the
  count is measured on a Platform Starter user before v0.8 closes and recorded against ADR-0121.
- `giveToHolders` reads holders of permission sets, directly or through a group. The Coordinator
  and Team Member roles hold the same set (`BarnCRM_Staff`), so telling them apart needs the
  holders of a permission set group; the Core seams PR settles how (decision 3).
- Volunteers can never be offered in the Standard Edition (ADR-0124): it is Nonprofit Edition
  only, and requires Rollup Builder, which both editions offer.
- No Campaign or Opportunity is used (Platform-only org, ADR-0013), so nothing is copied from
  Volunteers for Salesforce.
