# ADR-0050: Duplicate detection uses the org's own duplicate rules, and BarnCRM ships none

**Status:** Accepted (builder decision, conservative; confirm on review)
**Date:** 2026-09-23
**Source:** plan Section 5.1, feature C-20 ("uses platform duplicate rules where present");
Principles 1 and 8; canonical model Section 29A

## Context

C-20 asks for duplicate detection and merge suggestions for households and people. The
platform already has every part of detection: matching rules say what counts as the same
record, duplicate rules run them when a record is saved, `Datacloud.FindDuplicatesByIds`
runs them on request, and Duplicate Record Set and Duplicate Record Item hold what was found.
Every org starts with the standard Contact and Account duplicate rules switched on.

Two gaps remain. A duplicate rule only runs when a record is saved, so records already in the
org are never compared with each other, and the platform job that does that (duplicate jobs)
exists only in Performance and Unlimited Edition, which the nonprofits BarnCRM is built for
do not have. And nothing records a person's decision that a proposed pair is not a duplicate.

An earlier, unmerged draft of this feature shipped its own matching and duplicate rules keyed
to the import framework's matching (exact email, or last name with postal code). The platform
deploys a packaged matching rule inactive, and activating one is a Setup action an installed
app cannot perform, so that draft needed four Setup steps before anything worked.

## Decision

- **BarnCRM ships no matching rule and no duplicate rule.** Detection is whatever
  duplicate rules for Contact and Account are active in the org: the standard ones by default,
  or the administrator's own.
- **A scan fills the first gap.** Started by a person from the Duplicates panel of Nonprofit
  Settings, it runs `FindDuplicatesByIds` over existing contacts and households fifty at a
  time and writes the pairs it gets back as standard Duplicate Record Sets. It is not
  scheduled. It refuses to start when no rule for either object is active, and the panel says
  so and links to Duplicate Rules in Setup.
- **One object fills the second gap.** `Duplicate_Dismissal__c` holds a pair a person said is
  not a duplicate, so the next scan passes over it.
- **Merges are the ones that already exist.** Households through the household merge (R-H13),
  one pair at a time from the panel. People through the platform's own merge, reached from the
  Potential Duplicates card, which the packaged Contact record page now carries. The Account
  record page does not carry the card, so a household is never merged past R-H13.
- **Scope is people and households.** A pair where an account side is an organization or a
  person stored as an account is not proposed.
- **Reviewing suggestions takes an optional permission set.** Salesforce licenses Duplicate
  Record Set and Duplicate Record Item only to users with a Sales Cloud or Service Cloud
  license; no other license, Salesforce Platform included, can be given access to them. So no
  Core permission set grants them (a Core set must be assignable on a Platform-only org,
  ADR-0013). `Nonprofit_Duplicate_Review` grants them, is in no permission set group, and is
  assigned in Setup to the people who review duplicates, which the admin guide says. Without it
  the panel still lists the active rules and the last scan, says that suggestions need that
  access, and offers no scan, dismissal or merge. `scripts/ci/check-permission-sets.py` fails
  if a Core set other than the optional one grants either object.
- **A scan says what it could not check.** A chunk the matcher refuses, or whose suggestions
  cannot be written, is logged and skipped, and counted. The scan's one summary entry in the
  Error Log is at Warning when that count is above zero, and the panel shows the latest summary
  as its last-scan line, so a partly failed scan never reads as a clean one.
- **A people merge keeps what it touches.** The platform's merge deletes the merged-away
  person and moves their children without saving them. BarnCRM's contact triggers, and
  its account triggers for a person stored as an account, handle the delete as a merge when
  `MasterRecordId` is filled in `after delete`:
  - In junction mode the merged-away person's memberships are recreated on the survivor, all
    or none, so a row that cannot be written fails the merge instead of going missing. Only a
    current row counts as already being a member, so an ended row never blocks a current one.
  - Primary stays per household (R-M3, ADR-0044). Where the merged-away person was a
    household's primary member and nobody else there is, the survivor becomes its primary
    (the copied row carries the flag, or the survivor's own row is promoted), so the
    household's Primary Contact keeps mirroring somebody.
  - In both modes a household the merged-away person was in is recounted but never tidied
    away by the merge, because gifts and history credited to it would lose their household.
    An emptied household is left for a person to merge into the survivor's with R-H13; until
    then Health Check lists it as a household with nobody in it, detected and never changed
    (ADR-0048).
  - The real-time totals that target the merged entity are recalculated for the survivors
    only (`RollupService.runAfterMerge`, driven by the definitions that target that entity, so
    Core names no Giving object, ADR-0014). For a person stored as an account that is the
    totals on Account and on the survivor's person contact, which is read with dynamic SOQL
    only when the org has person accounts. By `after delete` the children already point at the
    survivor, so the engine's recalculation is handed the survivors as its parents and counts
    and reads only their children, one small queued job per source entity. The engine's own
    after-delete merge handling queued nothing in a test run. When the transaction has too
    little room left for the jobs, nothing is queued, an Info entry says so, and the nightly
    run brings the totals up to date.

## Alternatives considered

- **Ship BarnCRM matching and duplicate rules** (the earlier draft). Rejected: four Setup
  steps before first use (Principle 1), a second set of active rules beside the standard ones
  that would alert twice on every save, and rules an upgrade may not change once an
  administrator has edited them. What it bought, an import and a scan that agree on "the same
  person", matters less than it looks: the scan only proposes, a person decides.
- **A matching engine of BarnCRM's own.** Rejected: Principle 8, and the platform's
  matching (fuzzy names, normalized addresses) is better than a packaged one would be.
- **Schedule the scan nightly.** Deferred: duplicate rules already catch new records on save,
  so a schedule would mostly re-scan unchanged records. Rerunning after a large import is in
  the admin guide. Revisit if reviewers report missed duplicates between scans.
- **Merge two people in the app** with `Database.merge`. Rejected for now: the platform merge
  already carries related records, and the household membership and totals it cannot carry
  are repaired by the contact triggers (above), which an in-app merge would need as well.
- **Grant duplicate record sets in the Core permission sets.** Rejected: a permission set that
  grants them cannot be assigned to a Salesforce Platform user at all, which would break every
  Core role on a Platform-only org (ADR-0013).

## Consequences

- An org whose administrator switched the standard rules off sees an explanation and a Setup
  link instead of suggestions. That is one Setup step, only in that org.
- What counts as a duplicate varies by org. The admin guide describes the standard rules and
  says how an administrator narrows or widens them.
- The platform refuses a `FindDuplicatesByIds` call that includes a person account when no
  person account rule is active, so the scan sends accounts of the Household record type only.
- `DuplicateRule`, `DuplicateRecordSet` and `DuplicateRecordItem` join the standard object
  allowlist. Duplicate rules run in every edition and for every license. The record sets exist
  in every edition, but only a Sales Cloud or Service Cloud user can be given access to them.
- In an org of Salesforce Platform users, duplicate rules still alert and block on save, but
  nobody can review suggestions on the panel, and the Potential Duplicates card on the Contact
  record page shows them nothing usable, because the card reads the same record sets. Such an
  org needs at least one Sales Cloud or Service Cloud user to review and merge duplicates.
- A household merge (R-H13) is also an account merge, so the surviving household's real-time
  totals are recalculated for it alone in the same way.
- The permission set to review duplicates is assigned in Setup, not the Nonprofit Settings
  console, as with `Override_Receipt_Lock`: it is a license question for the administrator,
  not a setting.
