# ADR-0227: Fewer Custom Objects: One Admin Journal and Match Reasons on Duplicate Dismissal

**Status:** Accepted (owner decision, 2026-11-20, D-213)
**Date:** 2026-11-14
**Source:** D-208, release 1.28 item N-11 (Brandon, 2026-11-14: "Cut by a few if possible without
losing functionality"). Amends ADR-0174 (automation snapshot), ADR-0145 (merge journal),
ADR-0155 (household adoption journal), ADR-0197 (migration run) and ADR-0133 (duplicate reason).
Keeps ADR-0017 (each package owns its settings object) and ADR-0116 (the rollup run lock).

## Context

The whole suite ships 203 custom objects: 181 custom objects and 22 custom settings (every
`objects/*__c` folder with its own `.object-meta.xml` under `packages/*`; the three Mirror
folders that only add fields to Giving's Appeal, Fund and Gift are not objects). An Enterprise
Edition org allows 200 custom objects, custom settings included, so a full-suite source deploy
to the scratch gate orgs (`barn-sales`, `oi-test`) fails with "reached maximum number of custom
objects". The 15 custom metadata types and 3 platform events are not part of that count: the
gate failure reproduces at 203 without them, and Salesforce tracks them under their own
allocations (custom metadata types and platform event definitions). Nothing is packaged yet, so
objects can be merged freely, but no capability, admin experience or access rule may be lost.

Every candidate was checked for four costs: lost function, a changed admin or user experience,
widened record access, and a reversed recorded decision.

## Decision

1. **One Admin Journal.** `Merge_Journal__c` becomes the Admin Journal (label Admin Journal,
   name `AJ-{000000}`), the one object where admin tools keep what they need to show progress or
   undo: a new restricted picklist `Kind__c` says which tool wrote the row (Merge, Scan,
   Deactivation, Migration, Household Adoption). `Automation_Snapshot__c` (Scan and
   Deactivation rows, Section 10A), `Migration_Run__c` (Section 29ZS) and
   `Household_Adoption__c` (Section 29ZQ) are removed; their fields move with their API names
   (`Items__c`, `Message__c`, `Restored_At__c`, `Kit__c`, `State_JSON__c`, `Account_Id__c`,
   `Previous_Record_Type_Id__c`, `Previous_Values__c`), `Run_Id__c` is shared by merges and
   adoptions, an adoption's note is written to `Notes__c`, and `Status__c` carries every
   tool's values with no default (every writer sets it). Every query names its kind, including
   the retention pass, which ages out Merge rows only. Import Batch's lookup to the run becomes
   `Migration_Journal__c` (label Migration Run, relationship `Data_Jobs`): a new field, because a
   lookup's target cannot change in an org that has it.
   - All four objects were private, granted only to `BarnCRM_Admin` with View All, and had no
     tab, page layout or list view: admins reach them only through the tools, which look the
     same. Merge, Scan, Deactivation and Migration rows were already Read, Create, Edit, Delete,
     View All and Modify All for that role.
   - **Access change, stated:** adoption rows were read-only for `BarnCRM_Admin` (written by
     the adoption job in system mode). They now share the object, so the role may also edit
     Status or delete an adoption row, as it already may for merge rows, the same kind of undo
     record. The adoption's own fields (`Account_Id__c`, `Previous_Record_Type_Id__c`,
     `Previous_Values__c`) stay read-only by field permission. No one else gains access.
2. **Match reasons on Duplicate Dismissal.** `Duplicate_Reason__c` is removed. A match reason is
   a `Duplicate_Dismissal__c` row with the new `Kind__c` Match Reason (the default, Dismissal,
   is every other row), `Pair_Key__c` holding the duplicate record set's 18 character Id and
   `Reason__c` the match source's words. Both were key plus reason, public read/write, unique by
   key. Dismissal queries skip Match Reason rows; the All Duplicate Dismissals list view shows
   dismissals only. Reasons are written and deleted in system mode (they were read in system
   mode already): the dismissal object is creatable only by administrators, and a reason must
   still reach the review list whoever's scan found the pair. The text is the match source's
   label and the key the set just written in user mode, so nothing a person typed is elevated.
   Staff and Read Only lose their now-unused read grant on the removed object and gain read on
   `Kind__c`.

Result: 203 to 199 custom objects (Core 30 to 26), under the Enterprise Edition limit of 200.

## Candidates rejected

- **Module settings into Core's `BarnCRM_Settings__c`** (up to 14 objects). Reverses ADR-0017:
  Core would carry module fields, and a dependent package adding fields to a Core custom setting
  is the constraint ADR-0017 records. Needs an owner decision.
- **Merging two module settings objects of one package.** None exists outside the protected
  secret settings (`Payment_Keys__c`, `Address_Verification_Keys__c`), excluded pending the
  owner's secrets decision. (Since removed: D-209 moved the secrets to Named Credentials, see
  ADR-0229, 199 to 197 objects.)
- **`Rollup_Run_Lock__c` into `Rollup_Settings__c`.** The run lock is a `FOR UPDATE` on one row.
  `Rollup_Settings__c` is also written by record saves (`Processor_Requested_At__c`, D-200 P13),
  so saves would queue behind run starts, which ADR-0116 avoids ("only the start is locked,
  never a save"). A scale-tested lock is not worth one object.
- **`Whats_New_Seen__c` into `BarnCRM_Settings__c` or `BarnCRM_Automation_Control__c`.** User
  level rows of a 77 field setting count against the org's custom settings cache limit per
  user; a user row on Automation Control overrides a profile's Bypass (getInstance), which would
  switch a bypass off for that person.
- **`Setup_Change__c` or `Field_History__c` into `Setting_Change__c`.** Setting Change is read by
  every Staff user; Setup Audit Trail copies are admin-only and Field History holds field values
  of any tracked field (private, system read). Merging widens access.
- **`Saved_Transform__c` into `Saved_Query__c` or `Import_Template__c`.** Different sharing
  (shared transforms against private queries) and audiences (Bulk Update set).
- **`Job_Skill__c` into `Volunteer_Skill__c`.** Master-detail on the job against lookups with
  Read sharing; the job's related list and reports would change.
- **`Event_Funding__c` into `Event_Expense__c`, `Event_Announcement__c` into
  `Attendee_Message__c`, `Service_Count__c` into `Service_Delivery__c`.** Each changes what staff
  see (record names Item and Source, required picklists, a tab, related lists) or who may create
  rows. Possible later with the owner's agreement on the visible change.
- **Not touched by instruction:** Mirror and Case-request objects, Form and `Form_Submission__c`,
  Error Log objects, and protected secret settings.

## Consequences

- Orgs that had the removed objects keep them until the release's destructive manifest runs
  (`scripts/org/build-destructive-manifest.py`, which lists the three objects, the Duplicate
  Reason object and `Import_Batch__c.Migration_Run__c`). A deleted custom object still counts
  toward the limit until it is erased from Setup, Deleted Objects, or the org is recreated.
- Existing rows in long-lived test orgs are not moved: nothing is packaged and no customer org
  has them.
- Headroom is one object. Any new object (or custom setting) needs another cut, or one of the
  rejected options decided by the owner.
- Reports on Merge Journal now show every kind; filter on Kind.
