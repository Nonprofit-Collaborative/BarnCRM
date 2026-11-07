# ADR-NEXT: The BarnCRM Contact Point Sync module: one-way copies of a person's email, phone and addresses into Contact Points

**Status:** Accepted (builder decision)
**Date:** 2026-11-06
**Source:** plan D-111 and Section 4.7 (Contact Points), Section 5 row C-45, Section 6 release 1.1,
D-101 (single-feature modules are their own packages), D-155; builds on ADR-0013, ADR-0017,
ADR-0021, ADR-0024, ADR-0110, ADR-0131, ADR-0133 and ADR-0165.

## Context

Salesforce's consent model, Nonprofit Cloud and several marketing and commerce tools keep contact
details on `ContactPointEmail`, `ContactPointPhone` and `ContactPointAddress`. BarnCRM keeps them on
the person (the standard and BarnCRM email and phone fields) and in `Address__c`. Core never reads
or writes the three objects (ADR-0110, ADR-0013, `check-standard-objects.sh`); D-111 makes keeping
them in step an optional module, C-45, for orgs that use Contact Points.

The three objects are not in every org, the parent they hang from (`Individual`) exists only where
data protection details are turned on, and an org can restrict them (no create access, required
custom fields, validation rules). Whatever the org, a person's save must never fail because of
this module.

## Decision

1. **Its own package, Core only.** `packages/contactpoints`, package `BarnCRM Contact Point Sync`,
   depends on BarnCRM Core alone, offered in both editions. Core ships the catalog row
   `BarnCRM_Module.ContactPoints` (Sort Order 45, after Funders, probe object `Contact_Point_Link__c`, admin tab
   `Contact_Point_Sync`, no app), so the module key is `ContactPoints` and the classes Core finds
   by name are `ContactPointsAccessSync` and `ContactPointsPostInstall`.
2. **One way: BarnCRM is the source.** The person's fields and `Address__c` are copied to Contact
   Points; nothing flows back. A managed Contact Point edited directly is put back to the BarnCRM
   value the next time that person is synced (a save of a mapped field or address, or the
   backfill). This is the conflict rule: BarnCRM wins, always, for the rows the module manages.
   Two-way sync was rejected: two sources of truth for one value need a merge rule per field and
   loop guards, and BarnCRM's preferred-email and preferred-phone rules (R-C6, R-C6a) already
   decide which value is the person's.
3. **Managed rows are recorded, never guessed.** A module object, Contact Point Link
   (`Contact_Point_Link__c`, a detail of Contact), records each Contact Point the module manages:
   its kind, its source (a field name or an `Address__c` record ID) and the Contact Point's ID as
   text. A Contact Point with no link (made by a form, Nonprofit Cloud or a person) is never
   updated or deleted. When a new copy would duplicate an unlinked Contact Point on the same
   Individual with the same value, that row is adopted (linked) instead, so a first backfill in an
   org that already has Contact Points does not double them.
4. **What maps.** Contacts only (people stored as accounts are left out; their saves do not fire
   Contact triggers and their Individual link lives on Account).
   - Email: `Personal_Email__c`, `Work_Email__c`, `Alternate_Email__c` and the standard `Email`,
     one `ContactPointEmail` per distinct address (case ignored), `IsPrimary` on the one that
     equals `Email` (Core's preferred email, R-C6).
   - Phone: `HomePhone`, `MobilePhone`, `Work_Phone__c`, `OtherPhone` and the standard `Phone`,
     one `ContactPointPhone` per distinct number (digits compared), `IsPrimary` on the one equal to
     `Phone` (R-C6a), `PhoneType` set from the source where the org's picklist has the value.
   - Address: every `Address__c` with Status Current (or blank) that is the person's own
     (`Contact__c`) or their household's (`Account__c` is a household they belong to, through
     Core's `HouseholdService`), one `ContactPointAddress` each, `IsDefault` from `Is_Default__c`,
     Name from Type. Former and Undeliverable addresses are not copied: their managed Contact
     Points are deleted, and the history stays on `Address__c`.
   Each kind can be turned off on the settings page (Sync Emails, Sync Phones, Sync Addresses,
   all on by default). A kind turned off is left alone, neither created, updated nor deleted.
5. **Parent: the person's Individual.** Every copy hangs from `Contact.IndividualId`. A person
   with something to copy and no Individual gets one (first and last name), linked through
   `IndividualId`. Without the Individual object the module copies nothing and says why.
6. **Delete, merge, undelete.** Deleting a person deletes their managed Contact Points (to the
   Recycle Bin) and, by master-detail, their links. A merge deletes the losing records' copies; the
   survivor is synced again, and the links Salesforce moves to it that point at deleted copies are
   cleaned up. Undeleting a person restores their links (master-detail) and the sync makes new
   copies. Deleting, restoring or changing an address syncs every person it applies to. Erasing a
   person (ADR-0110) clears their fields, so the sync deletes their managed copies; unlinked
   Contact Points are untouched, as ADR-0110 says.
7. **Through Core's trigger framework.** Two registry rows, each a switch on the Automation page
   that Pause All covers (not Always Runs): `Contact_Point_Sync_Person` on Contact
   (`ContactPointPersonHandler`) and `Contact_Point_Sync_Address` on `Address__c`
   (`ContactPointAddressHandler`), both on by default. A turned-off module runs neither (Core's
   dispatcher skips a turned-off module's rows).
8. **Never fails a save.** The sync runs after the save, writes with partial success, and logs
   every refused row to the Error Log; any exception is caught and logged. When too few queries or
   DML statements are left in the transaction, the work is queued instead. The backfill repairs
   whatever was missed.
9. **System mode for the copy, a permission for the page.** The copy is upkeep of data the user
   was allowed to change (ADR-0021): it runs without sharing, in system mode, so staff without
   Contact Point access still keep the copies right, and no permission set grants Contact Point
   object access (a permission on a standard object the org may lack would refuse the install).
   The settings page and the backfill need `Contact_Point_Sync_Admin` (class access) and starting
   the backfill also Manage BarnCRM Settings (`AutomationControl.canManage`).
10. **Backfill from the settings page.** The Contact Point Sync page (admin tab, linked from the
    Contact Points section of BarnCRM Settings) says, per kind, whether this org can sync it and
    why not; shows a preview count (people to check, Contact Points managed now) and starts the
    backfill, a batch of 200 people per chunk that syncs each person exactly as a save would. The
    last run's time and summary (created, updated, deleted, failed) are kept on the module's
    settings and shown on the page.
11. **Detect and explain, never fail Core.** The three objects, `Individual` and
    `Contact.IndividualId` are reached only through describe and dynamic Apex, never named at
    compile time, so the module installs in any org. A kind whose object is missing is reported
    as "not in this org"; one the running admin cannot create is reported as "restricted for you"
    (the copy itself still runs in system mode). `check-standard-objects.sh` allows the three
    names in `packages/contactpoints` only, and, as for Mirror, no object or field metadata there
    may declare anything on them.
12. **One permission set, given by role.** `Contact_Point_Sync_Admin` (the page, the backfill, the
    link object read only) goes to holders of `BarnCRM_Admin` through
    `ContactPointsAccessSync` (ADR-0131), never taken away. Staff need nothing: the copy runs in
    system mode.
13. **Portable logic.** Which values map, how they are compared and what changes is decided by a
    pure function over plain maps (`ContactPointPlan`); the page's text and counts come from a
    thin controller returning plain JSON (plan 9.9).

## Alternatives considered

- **Two-way sync or BarnCRM reading Contact Points.** Rejected (decision 2).
- **Contact Points in Core behind describe.** Rejected by D-111: Core stays free of the objects.
- **A custom field on the Contact Point objects to mark managed rows.** Rejected: field metadata
  on a standard object the org may lack refuses the install (ADR-0013, the Mirror rule).
- **Ending (ActiveToDate) instead of deleting a former address's copy.** Rejected: the history
  already lives on `Address__c`, and consumers of Contact Points read current rows.
- **User mode for the copy.** Rejected (decision 9): it leaves copies stale whenever someone
  without Contact Point access edits a person.
- **Person accounts.** Left out of this release: their Individual link and email fields live on
  Account and their saves fire Account triggers. A later release can add an Account handler.

## Consequences

- One more custom object (`Contact_Point_Link__c`) and one hierarchy custom setting
  (`Contact_Point_Sync_Settings__c`).
- A person's first sync may create an Individual, which Salesforce's privacy tools then see.
- Contact Points the module manages are rewritten on each sync; edits made to them elsewhere do
  not last. The admin guide says so.
- Saving a person costs a few more queries and DML statements while the module is on.
