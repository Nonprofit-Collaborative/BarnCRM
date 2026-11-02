# ADR-NEXT: NPSP Household Adoption Lives in Core, Converts Accounts in Place, and Is Undone From a Journal

**Status:** Proposed
**Date:** 2026-11-02
**Source:** release 0.17 item X-05 (plan Section 6.0a, Section 4.5 NPSP coexistence row,
Section 6.3). Builds on ADR-0141 (the Household record type is given to nobody), ADR-0062
(Core names other products only when it detects them), ADR-0013 (Core runs on a Platform-only
org) and ADR-0021 (system mode for the package's own computed writes).

## Context

Plan Section 4.5 says NPSP coexistence mode "adopts NPSP household Accounts (record type
mapping)". Until now the mode only records that NPSP is installed: BarnCRM builds its own
households, so an org with NPSP has NPSP's household Accounts and, for anyone added later,
BarnCRM's, and reconciling them is manual (admin guide, Coexistence Mode).

An NPSP household is an Account. NPSP marks it with its own record type (developer name
`HH_Account`) and with `npe01__SYSTEM_AccountType__c = 'Household Account'`, keeps the
greetings in `npo02__Formal_Greeting__c` and `npo02__Informal_Greeting__c`, the primary
contact in `npe01__One2OneContact__c`, and which of name and greetings staff typed by hand in
the multi-select `npo02__SYSTEM_CUSTOM_NAMING__c`. Its members are Contacts whose `AccountId`
is the household, which is exactly BarnCRM's contact membership mode (R-H3).

Three questions were open:

1. **Which package.** X-05 sits in the Mirror catalog (plan 5.6) and Section 6.3 says
   integrations with NPSP live in Mirror or later adapters. But Mirror's reason to exist is
   the standard-object rule: Opportunity, Campaign and Nonprofit Cloud objects. Adoption reads
   and writes only Account and Contact, which Core owns, and the one write it needs (changing
   an Account's record type to Household) is, under ADR-0141, something only Core's system
   mode writer may do. Core already detects NPSP (`OrgShapeDetector.hasNpsp`) and owns the
   coexistence mode. X-09 (Nonprofit Cloud household guards) set the precedent of a Mirror
   catalog item built in Core.
2. **Adopt how.** Either treat NPSP's `HH_Account` record type as a second household record
   type, or convert each Account to BarnCRM's Household record type in place.
3. **Undo how.** The import journal undo (R-IB8, R-BU5) restores in user mode, and no user may
   set or clear the Household record type (ADR-0141).

## Decision

1. **Core, behind detection.** Adoption is a Core tool on the General page of BarnCRM
   Settings, shown only when NPSP is detected or the coexistence mode is already NPSP, or when
   households were adopted earlier (so an undo is never hidden). Mirror is not needed: an NPSP
   org that wants BarnCRM households but no Opportunity mirror installs nothing extra. NPSP is
   reached only by describe: every NPSP field and record type name is built at run time, a
   field the describe does not find is read as blank, and nothing is referenced at compile
   time, so Core still deploys and runs on an org without NPSP (`scripts/ci/check-namespace.sh`
   and `check-standard-objects.sh` unchanged). BarnCRM never writes an NPSP field.
2. **Convert in place.** An adopted household keeps its Id, name, members, Opportunities,
   activities and every lookup to it. Adoption changes only BarnCRM's own fields: the record
   type becomes Household; `Household_Formal_Greeting__c` and `Household_Informal_Greeting__c`
   take NPSP's greetings; `Primary_Contact__c` takes `npe01__One2OneContact__c` when that
   contact is still a member (R-H10), and is left blank otherwise; `Custom_Name__c` is set
   when the administrator chooses **Keep NPSP's names and greetings** (the default) or when
   NPSP recorded any custom naming. Household upkeep then runs on each household (member count,
   a blank greeting filled, the name recomputed unless Custom Name is set). A second household
   record type is rejected: every household query, guard and the tidy-up read one record type
   id, and a second would touch all of them.
3. **Contact membership mode only.** Adoption is refused while household membership is
   Junction: NPSP households hold their members by `AccountId`, and a junction org would need
   a membership row per person, which this item does not build. The refusal says to switch
   membership to Contact first.
4. **A journal of its own, undone in system mode.** Each adopted Account gets one
   `Household_Adoption__c` row: the Account, the run, the previous record type id, and the four
   BarnCRM fields before adoption as JSON. Undo is per run, counted and confirmed: it puts the
   record type and the four fields back on each Account that is still a Household, in system
   mode through `HouseholdWriter`, after checking the running user can edit each Account
   (`UserRecordAccess`), and marks the row Undone (or Not Restored, with the reason). Member
   count is left as written: NPSP does not read it.
5. **Access.** Previewing, adopting and undoing require Manage BarnCRM Settings. Each Account
   is adopted only if the person who started the run can edit it; the rest are skipped and
   counted. The journal is granted to `BarnCRM_Admin` only, Read and View All, and written
   only by the adoption job in system mode, as ADR-0021 allows for the package's own records.
6. **NPSP's own naming.** BarnCRM cannot switch off NPSP's household naming, and NPSP may
   still rename an Account it counts as a household by `npe01__SYSTEM_AccountType__c`. The
   admin guide tells the administrator to turn off NPSP's Automatic Household Naming before
   adopting. Whether NPSP renames an Account whose record type is no longer `HH_Account` is
   verified only on an org with NPSP (testing guide).

## Consequences

- An NPSP org gets BarnCRM households without a duplicate per family and keeps NPSP's
  Opportunities and rollups on the same Account.
- One new Core object (`Household_Adoption__c`, canonical model Section 29ZH) and one
  `HouseholdWriter` method (`adoptHouseholds`) that may change an Account's record type, the
  only place outside creation that does.
- The NPSP path is tested in a scratch-free way through a seam (`NpspHouseholdSource`) that
  stands in for the describe; the real describe path is proven only on an org with NPSP
  installed.
- Not built: junction mode adoption, NPSP's legacy `npo02__Household__c` object model,
  addresses (`npsp__Address__c`), relationships and affiliations (the import templates and
  admin guide Migrating From NPSP still cover those).

## Alternatives Considered

- **Mirror package.** Needs Giving installed for a households-only change and a cross-package
  seam into `HouseholdWriter` that lets another package change record types in system mode.
- **`HH_Account` as a second household record type.** Every household path reads one record
  type id; widening it touches the guards, the tidy-up, merge, naming and every selector.
- **Reuse the import journal undo.** It restores in user mode, which cannot clear the Household
  record type (ADR-0141).
