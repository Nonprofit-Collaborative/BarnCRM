# ADR-0217: Nonprofit Cloud Households Are Converted in Place, Once, Supervised and Reversible

**Status:** Proposed
**Date:** 2026-11-12
**Source:** D-196 (3), release 1.20 item MIG-02b; plan Section 11.2 item 9. Builds on the
companion ADR-0216 `0216-household-model-coexistence.md` (the `Household_Model__c` field),
ADR-0155 (NPSP household adoption: in place, journaled, undone in system mode), ADR-0197 (the
Migration Assistant), ADR-0141 (only Core's writer sets the Household record type), ADR-0057
(extension seams found by class name) and ADR-0013 (no compile-time Industries dependency).

## Context

A Nonprofit Cloud household is an Account (usually a business account with a record type the
org built) plus a `PartyRelationshipGroup` of type Household whose master is that Account, with
members on `AccountContactRelation` rows (`docs/architecture/reference/nonprofit-cloud-data-model.md`
Section 4). Plan Section 11.2 item 9 asks for a supervised, reversible, one-time migration in
Mirror that never deletes a native group, a membership relation or an Account, with a drift
report and no sync. The Migration Assistant (ADR-0197) already runs Nonprofit Cloud kits for
relationships, affiliations and gifts; MIG-02 left households out until this decision.

Neither part of a household fits the Assistant's import steps:

- **The Account.** Making it a BarnCRM household means giving it the Household record type,
  which only Core's system mode writer may do (ADR-0141), and which the Import engine's undo
  cannot put back, because it restores in user mode. NPSP adoption (ADR-0155) solved exactly
  this with a journal of its own and a system mode undo.
- **The members.** The Import engine refuses to load Household Member rows at all: memberships
  are kept by the households they belong to and written only through
  `HouseholdService.addMembers` (R-M5, `DataProtectedFields`).

## Decision

1. **A Mirror kit with one tool step.** Mirror ships Migration Kit `NPC_Households` (source app
   `Nonprofit_Cloud_Fundraising`, as `NPC_Relations` and `NPC_Gifts`) whose extension is the
   source class itself, `NpcHouseholdSource`. Its one step, `households`, is a tool step:
   **Convert Nonprofit Cloud Households** on BarnCRM Settings, General. The administrator
   previews, confirms the count, runs and undoes there, then marks the step done; the kit's
   check counts Accounts carrying a native household group (less those kept native) against
   those converted, and the retire checklist covers native naming, related lists and the drift
   report.
2. **The step reuses NPSP adoption with a second source.** The adoption service,
   batch, journal (`Household_Adoption__c`) and panel take a source key, NPSP (unchanged) or
   NPC. Core resolves the NPC source by class name (`NpcHouseholdSource`, Mirror), which extends
   Core's `NpspHouseholdSource` and holds every native name as run-time text; without Mirror, or
   in an org without the native objects, the NPC source is not available and the panel row is
   hidden. An NPC run's Run ID starts `NPC-`, so each panel shows and undoes only its own runs.
3. **What a group becomes.** The group's Account itself becomes the BarnCRM household, keeping
   its Id, name, members, gifts, activities and every lookup to it. Per Account, in system mode
   through `HouseholdWriter`: record type Household; `Household_Model__c` Converted;
   `Custom_Name__c` true when the run keeps names (the default: native names are typed by hand,
   there is no native automatic naming before the paid Winter '27 add-on); `Primary_Contact__c`
   the member marked `IsPrimaryMember` when that contact's own Account is the household (contact
   membership mode, R-H10), else blank; greetings blank (Nonprofit Cloud has none), so upkeep
   fills them. Household upkeep then runs (count, greetings, name unless Custom Name).
   Selected: Accounts carrying a native group of type Household whose record type is not
   Household and whose model is neither Converted nor Nonprofit Cloud, that the person running
   it can edit, at most 48,000 a run. A native group of type Group is never a household.
4. **Members follow BarnCRM's membership mode.**
   - Junction: in the same chunk and savepoint as the Account, each membership row on a
     converted household joins its person through `HouseholdService.addMembers` (R-M5), as the
     person running it; the person is the contact, or the person account when the contact is a
     person account's own. Each new Household Member row then gets Is Primary from
     `IsPrimaryMember` (the Primary Contact follows the primary member, ADR-0044), Role from the
     first of `Roles` that maps (Husband and Wife to Spouse or Partner, Son and Daughter to
     Child, Father and Mother to Head, Other to Other; anything else blank), and Start and End
     Date as they are. A row that is inactive with no End Date is not joined (a former member
     with no date to record), and a person already a current member is left as they are.
   - Contact: a person belongs to the household their Contact names. Nonprofit Cloud orgs
     without person accounts usually already point a member's Contact at the household; nobody
     is moved. Changing a contact's primary account rewrites its native direct relation, which
     this decision never touches, and a person account cannot belong by reference at all.
5. **Never touched.** No `PartyRelationshipGroup`, `AccountContactRelation`,
   `ContactContactRelation` or `PartyRoleRelation` row is created, changed or deleted, no native
   field is written, and no Account is deleted or merged (the delete and merge guards still see
   the group, companion ADR decision 4). The Account's own name and address are not changed by
   the conversion; from then on BarnCRM upkeep owns them.
6. **The undo journal.** Each converted Account gets one `Household_Adoption__c` row: previous
   record type and, as JSON, the previous `Custom_Name__c`, both greetings, `Primary_Contact__c`
   and `Household_Model__c`, plus the ids of the Household Member rows the run created. Undo is
   per run, counted and confirmed, in system mode, and puts all of them back on each Account that
   still exists, is still a Household and the person can edit, then removes the run's own
   membership rows (as the person, after the record type is back, so the empty household is
   never tidied away). An Account with any other Household Member row, one added since by hand,
   is Not Restored with the reason: a household with BarnCRM members cannot stop being one.
7. **Idempotent, so "one-time" is safe to repeat.** A converted Account is Converted and a
   Household, so a second run never selects it, and a member already joined is left alone. A
   run stopped part way is finished by running it again. A native household created after the
   conversion stays native (detected by the guards) until the next run.
8. **The drift report is a Health Check row, not a sync.** `MirrorHealthCheckExtension` adds a
   warning, for viewers who may manage settings and only where the native group object is
   described, counting and naming up to ten Accounts whose model and native group disagree:
   (a) a BarnCRM household with a native household group whose model is not Converted (both
   models claim it), (b) model Nonprofit Cloud and no native household group, (c) model Converted
   but no longer a BarnCRM household. It changes nothing; the administrator settles each one by
   editing Household Model, running the conversion or undoing it. Nothing is ever copied from one
   model to the other afterwards: a computed name and a hand-edited name have no convergence rule.
9. **Access.** Preview, run and undo require Manage BarnCRM Settings (R-HA5). Native rows are
   read in the running person's access (user mode): without read access to the native objects
   (the Group Membership permission set) nothing is selected, and the preview shows none.

## Consequences

- A Nonprofit Cloud org gets BarnCRM households on the same Accounts, without a duplicate
  household per family, and keeps every native record for anything that still reads it.
- Core gains a source key on the adoption service and panel, and a settings row hidden unless
  the NPC source is installed and available or NPC runs exist; Mirror gains one source class
  (also the kit's extension), one kit and one Health Check finding. No new object or template.
- The real describe and DML path (native group selection in user mode, person account members,
  the platform's behavior on the native rows after the record type change) is proven only on an
  org with Nonprofit Cloud (testing guide); the tests stand in for the native rows.

## Alternatives Considered

- **The Account step as an import step (Update by record Id).** Rejected: the Import engine
  restores in user mode and cannot clear the Household record type (ADR-0141), the reason
  ADR-0155 gave its adoption its own journal.
- **Members as a separate import step.** Rejected: the Import engine refuses Household Member
  loads (R-M5), and a second step would leave converted households without members between
  the two runs.
- **A new BarnCRM household Account per group, copying members.** Rejected: it leaves the
  native household as a second household for the same people, the duplicate Section 11.2 item 9
  forbids, and moves every gift and activity.
- **Members in contact mode by moving each Contact.** Rejected: it rewrites native direct
  relations and cannot hold a person account.
- **The conversion in Core.** Rejected: Core would have to name the native group in a query
  (ADR-0013); Mirror already does, as text.
- **A two-way sync or a nightly re-conversion.** Rejected by Section 11.2 item 9.
