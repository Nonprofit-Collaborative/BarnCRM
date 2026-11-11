# ADR-NEXT: Brand management in Core, and brand-restricted visibility through BarnCRM-owned groups

**Status:** Proposed (build agent, 2026-11-11; for the integrator and Brandon)
**Date:** 2026-11-11
**Source:** Plan C-47 and C-47a to C-47f (releases 1.13 and 1.14), D-119 and D-120 ("an option to
restrict record visibility based on the brand(s) assigned to the record and what brand(s) the
user has access to"; "the brand sharing code ... need[s] a new ADR before build"), plan Section
11.2 item 31. Builds on ADR-0017 (registry-driven trigger dispatch), ADR-0019 (picklist keys as
text), ADR-0021 (system mode writes for package owned data) and ADR-0013 (Core on a Platform-only
org).

## Context

One organization can run several brands (programs, chapters, affiliates, a thrift store, DBAs),
some of them separate legal entities. Receipts, letters, documents and portals need the brand's
own name, logo and sender; reports need to filter by brand; and some organizations need staff of
one brand not to see another brand's people. Standard sharing rules cannot express this: a
criteria rule reads one field, and a person can belong to several brands (D-120). Core must not
depend on any module, must stay inside the Apex budget, and must change nothing anyone sees while
the feature is off.

## Decision

1. **Three Core objects** (canonical model 29BR1 to 29BR3): `Legal_Entity__c`, `Brand__c`
   (lookup to its entity) and the junction `Brand_Assignment__c` (master-detail to Brand; exactly
   one of Contact, Account or User). Staff membership is the same junction with `User__c`, so
   there is one place to say who belongs to a brand. Brands and entities are data on their own
   tabs, not settings; the two switches are settings (Section 12, Brand keys).
2. **Two switches, both shipped off.** `Brand_Management__c` turns on defaulting and brand-aware
   outputs; `Brand_Visibility__c` (saved on only while management is on) turns on share upkeep.
   Off, no code path reads a brand, so behavior and pages are as before. No shipped app or page
   gains a brand tab or field; the Brands and Legal Entities tabs are Available to the Admin
   permission set only.
3. **A seam, not a dependency.** `BrandService.profileFor(Id)` returns a plain profile and
   `BrandService.applyDefaults(List<SObject>, String parentField)` fills a blank `Brand__c`.
   A module adds its own `Brand__c` lookup and calls these from its own code; Core reads module
   objects only by describe. Outputs fall back field by field: brand, then its legal entity, then
   the organization settings.
4. **Visibility through groups BarnCRM owns.** Each active brand gets a public group named
   `BarnCRM_Brand_<Brand Id>`, its members the users assigned to the brand. Each Account with a
   brand (directly, or through a person whose Account it is) gets a Manual `AccountShare`, Edit,
   to each brand's group. Contacts follow their Account under the usual "controlled by parent"
   Contact sharing. Because every row BarnCRM writes is granted to one of its own groups,
   upkeep can delete exactly its own rows and never a share a person or another tool made. The
   alternative, per-user Manual shares, cannot be told apart from a person's own manual shares
   and multiplies rows by staff count.
5. **Restriction is the org's sharing setting.** BarnCRM never changes organization-wide
   defaults. The administrator sets Account to Private in Setup; Health Check warns while
   visibility is on and Account is not Private. A record with no brand keeps whatever access the
   org's sharing gives it.
6. **Upkeep is asynchronous and split by the mixed DML rule.** Groups and group members are setup
   objects and Account shares are not, so one transaction cannot write both. `BrandShareJob`, a
   queueable, writes groups and members in one run and chains a run per chunk of accounts for the
   shares. It is enqueued once per transaction by the Brand and Brand Assignment triggers while
   visibility is on, and in full when the setting is turned on; turned off, it deletes every row
   granted to BarnCRM brand groups, then the groups. Writes run in system mode in
   `BrandShareWriter`, registered in the without sharing register (Platform kind): a staff member
   assigning a brand cannot grant shares on records they do not own.
7. **Module records are not shared yet.** Gifts are Private and child records follow their
   parents; sharing a module's own records by brand needs that module's Apex sharing reason and
   is left to a later module change through the same groups.

## Consequences

- An organization with one brand pays nothing: off by default, and on with one brand only labels.
- Owner changes on an Account do not remove the rows (they are granted to groups, not to the old
  owner), but Salesforce deletes Manual shares when an owner changes; the job runs again after a
  Brand Assignment change, and the full run on turning the setting on (or off and on) restores
  them. A nightly full run is a later addition if orgs need it.
- Large orgs: share rows are one per Account per brand; groups keep them independent of staff
  count.
- Receipt numbering per brand or legal entity (C-47f) is a Giving setting that keys a new series
  per entity or brand, leaving existing series untouched (ADR-0016 numbering rules hold).
