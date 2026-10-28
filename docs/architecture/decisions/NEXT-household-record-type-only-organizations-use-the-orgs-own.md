# ADR-NEXT: Core Ships the Household Record Type for Households Only, and Organizations Use a Record Type the Org Already Has

**Status:** Accepted (owner decision, Brandon, 2026-10-28)
**Date:** 2026-10-28
**Source:** owner feedback of 2026-10-26 (RT1) and the approval of all eight design
recommendations on 2026-10-28, plan decision D-134. Amends ADR-0005 (Organization is no
longer a packaged record type), ADR-0041 ("Account keeps its two record types" becomes one),
ADR-0124 (a feature can carry an access set) and ADR-0074 (adds a single record type choice).

## Context

Core shipped two Account record types, Household and Organization, and the three role
permission sets gave both to every BarnCRM user whether or not households were on. Every
Person Account org already has a business record type (Salesforce requires one), and most
real orgs have their own (Business, Default, NPSP's Organization), so BarnCRM added a second,
overlapping Organization. Accounts of the org's own record types were treated as neither
household nor organization: no address capture, refused as an organization by import.

A package cannot leave out a record type it ships, and Apex cannot create or activate one
without a Metadata API callout and an admin-authorized app. A record type reaches a user only
through profile or permission set visibility.

## Decision

1. **Household stays packaged and active**, listed in Setup on every install, but no user has
   it until Households is on. A new packaged permission set, `BarnCRM_Households`, carries the
   Household record type and the Households tab. The three role sets lose both. The
   `HouseholdUpkeep` feature carries the set (ADR-0124 amended: a feature, not only a tool,
   can carry an access set), and `TabAccessService` gives it to the role holders while the
   feature is on, on turn-on, on install and upgrade, and nightly. While off, the Households
   tab is hidden like any other feature's tab.
2. **Core ships no Organization record type.** Organizations are the accounts of one record
   type the org already has, stored in `BarnCRM_Settings__c.Organization_Record_Type__c`
   (a developer name, or `Master` for "No record type"). One record type, for now.
3. **Detection** when nothing is stored, on install and source deploy: active Account record
   types that are not person types and whose name does not contain Household; one already
   used by accounts first; then by developer name Organization, Business_Account, Business,
   Default; then the first by label; with none, `Master`. A stored value that is gone or
   inactive falls back to detection. One Core resolver, `AccountKinds`, replaces every fixed
   `'Organization'` in Core and the modules.
4. **One console row in General, always visible:** "Record type for organizations", a single
   choice of the candidates plus "No record type", preselected with the stored or detected
   value. ADR-0074 gains the `RecordType` data type (one choice) beside `RecordTypeList`.
5. **A formula field, `Account.Is_Organization__c`**, true for accounts of the chosen record
   type (or of none, for `Master`), reading the setting through `$Setup`. The Organizations
   list view and every page rule that named Organization use it.

## Alternatives considered

- **Ship both record types inactive and activate on turn-on:** activation needs the Metadata
  API, and every upgrade or redeploy writes inactive back, breaking household inserts.
- **Create record types on demand by a callout:** needs an admin-authorized app and a
  self-callout; packaged list views, page rules and permission sets could not name them.
- **The admin creates them in Setup:** about six Setup steps, against "every admin setting
  lives in the in-app console".
- **Several organization record types:** not needed now; a list can come later without a
  migration.

## Consequences

- A new install adds no record type any user sees until Households is turned on; Setup still
  lists Household. Orgs already running BarnCRM keep Household and their Organization record
  type, which detection picks because accounts use it. Nothing is deleted or rewritten.
- In mwdbdevsb, BarnCRM's leftover Organization record type is deactivated and deleted later,
  in Setup, once a count shows no record uses it (owner approval).
- Mapping BarnCRM households onto another product's household record type stays X-05.
- Before the build, a scratch org spike confirms: the record type picker and default when a
  user gains Household in an org with no other record types (V2); household inserts in
  system mode by a user without Household (V3); a `$Setup` formula in a list view filter and
  a Dynamic Forms rule (V4); whether a deploy removes a record type visibility a permission
  set no longer names (V5); and that a deploy makes a new record type visible to no profile
  (V6). A contrary answer comes back to the owner before the build continues.
