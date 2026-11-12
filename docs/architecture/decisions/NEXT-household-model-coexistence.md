# ADR-NEXT: One Household Model per Account, Recorded in Household Model

**Status:** Proposed
**Date:** 2026-11-12
**Source:** D-196 (3), release 1.20 item MIG-02b; plan Section 11.2 item 9 (Party Relationship
Group coexistence, the provisional "guards only" choice of 2026-09-23 confirmed as guards plus
migration). Builds on ADR-0036 (empty household delete guard), ADR-0130 (contact relations are
not native households without native groups), ADR-0013 (Core runs on a Platform-only org) and
ADR-0141 (only Core's writer gives an Account the Household record type). The conversion that
sets the field is the companion ADR-NEXT `NEXT-npc-household-conversion.md`.

## Context

An Account in an org running Nonprofit Cloud can be a household twice over: a BarnCRM household
(the Household record type) and a native one (a `PartyRelationshipGroup` of type Household
pointing at it, members on `AccountContactRelation`). Plan Section 11.2 item 9 settled that one
Account has exactly one household model. The four Core guards built for it (naming on all three
callers, automatic household creation, address propagation, Health Check's informational count
and collision warning) all ask one predicate, `HouseholdSelector.nativeHouseholdAccountsAmong`,
which detects the native model from the native rows themselves.

Detection alone cannot express two facts an administrator needs to state:

1. **"BarnCRM owns this Account now."** A supervised conversion makes a native household a
   BarnCRM household but never deletes the native group or its membership rows (Section 11.2
   item 9). Detection still finds the group afterwards, so every guard would keep refusing to
   name, greet or address the household the administrator just converted.
2. **"This Account stays native, whatever you detect."** Detection reads with an object probe
   that can be ruled out by a licence or permission gap (ADR-0130), and the conversion must have
   a way to leave a household alone on purpose.

Core may not depend on Industries objects (ADR-0013). The existing probes stay as they are
(`// detection-only:` text, run only where the object is described); nothing new in Core may
name a native object.

## Decision

1. **`Account.Household_Model__c`, a Core field.** A restricted picklist with three values:
   - **Automatic** (the default): BarnCRM decides from what it detects, exactly as today.
   - **Nonprofit Cloud**: the Account is a native household and stays one. Every guard treats it
     as native whether or not the native group is detected, and the conversion never selects it.
   - **Converted**: BarnCRM owns the Account. It was a native household and was converted; the
     native group and membership rows are still there, untouched.
   Account records saved before the field existed read blank, and Core reads blank as Automatic,
   so no backfill runs. Field access: BarnCRM Admin edits, Staff and Read Only read.
2. **Who sets it.** Automatic is the default on every new Account. Converted is written only by
   the conversion (companion ADR) and put back to what it was by the conversion's undo. Nonprofit
   Cloud is set by an administrator by hand, on the record, to keep an Account native. An
   administrator may also set Converted by hand on an Account that is already a BarnCRM
   household and carries a native group (the collision Health Check warns about) to settle it on
   BarnCRM. Nothing else writes the field, and no automation, trigger or nightly job reads a
   change of it as an instruction.
3. **The guards read the field before detection.** `nativeHouseholdAccountsAmong`, the predicate
   behind naming, automatic creation, address propagation and person erasure, keeps its cheap
   org-wide check first (an org with no native household groups at all pays nothing, unchanged),
   then reads the field for the Accounts asked about, in system mode (an upkeep read, ADR-0021):
   Converted is never native, Nonprofit Cloud always is, and Automatic or blank falls through to
   the existing detection rule. One extra query per call, only in orgs where native households
   can exist.
4. **The delete and merge guards do not read it.** `getAccountsWithNativeDependents` (ADR-0036)
   and `accountsWithNativeHouseholdGroups` (merge, duplicates) protect the native rows
   themselves: deleting or merging the Account cascade-deletes its group. A converted Account
   still has its group, so it is still never deleted as empty and never merged. The field
   changes who writes the Account, never whether the native rows may be destroyed.
5. **Core never reads native objects for this.** The field is the only new input to Core. The
   existing collision count in Health Check leaves out Converted Accounts (they carry both
   models on purpose) and is otherwise unchanged. The drift report, which has to read the
   native group, lives in Mirror (companion ADR, decision 8).

## Consequences

- A converted household is named, greeted, addressed and counted by BarnCRM like any other,
  while its native group stays for Nonprofit Cloud features that read it.
- An administrator can pin an Account to Nonprofit Cloud in one edit, which also protects it in
  an org where the group probe cannot see the native object.
- No behavior changes for any org until a value other than Automatic is written.
- A hand edit to Converted on an Account that is not a BarnCRM household does nothing except
  appear in the drift report.

## Alternatives Considered

- **A Boolean "Converted" only.** Rejected: it cannot state "keep native", and the conversion
  needs that to leave chosen households alone.
- **Values BarnCRM, Nonprofit Cloud, Converted with BarnCRM as the default.** Rejected: the
  default would claim BarnCRM owns a native household created after install. Automatic says
  what the default does.
- **The field drives the conversion (a trigger that converts on Converted).** Rejected: the
  Account trigger can be switched off in Automation Control, so the field would say Converted
  while nothing happened, and an Account would change record type as a side effect of an edit.
- **Core reads the native group for the field's checks.** Rejected: ADR-0013; Mirror already
  holds Nonprofit Cloud names as run-time text.
