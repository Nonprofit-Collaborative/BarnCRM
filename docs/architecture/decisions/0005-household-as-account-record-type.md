# ADR-0005: Household as an Account record type with two membership modes behind one service

**Status:** Accepted
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-05
**Amended by:** ADR-0141 (D-134): Core no longer ships an Organization record type;
  organizations are the accounts of a record type the org already has, chosen in settings, and
  no user is given the Household record type: BarnCRM creates households in system mode.

## Context

The household is the unit of relationship and recognition for individual donors: one
mailing, one greeting, one giving history. Every nonprofit CRM needs it, and it is the
feature NPSP users most consistently name as the reason they stayed on NPSP. Agentforce
Nonprofit's answer, Party Relationship Groups, is widely reported as harder to
administer, and it lacks NPSP's naming and greeting conventions (plan Section 1.2 and
4.6).

Three implementations are available:

1. **Account with a Household record type**, membership through the Contact's Account
   reference. This is NPSP's shape.
2. **A custom Household object** with a lookup from Contact.
3. **Party Relationship Groups**, the Industries construct.

There is a complication: where Person Accounts are enabled, which is common in
Agentforce Nonprofit orgs, a person is an Account, so the Contact-to-Account membership
mechanism does not work. Separately, some nonprofits genuinely need one person in two
households: children of divorced parents, students with a campus and a family address.

## Decision

**A household is an Account with record type `Household`.** Organizations are Accounts
with record type `Organization`. Both record types ship with packaged page layouts and
compact layouts.

**Membership has two modes, and both sit behind a single Apex service,
`HouseholdService`, so that no other code knows which is in use:**

- **Contact mode** (default): the Contact's Account reference points at the household.
- **Junction mode** (required when Person Accounts are enabled, optional otherwise): a
  `Household_Member__c` record joins a person to a household, with role, primary flag,
  and start and end dates, allowing multi-household membership and full history.

The mode is one org-level setting. Feature code that branches on membership mode outside
`HouseholdService` is a review failure. The membership abstraction may not be changed
without escalation to Brandon (plan Section 11.4).

## Alternatives considered

- **A custom Household object**: loses standard Account behavior that the whole ecosystem
  assumes: activities, standard address fields, standard reports, and every AppExchange
  app that expects a Contact to belong to an Account. Rejected.
- **Party Relationship Groups**: an Industries construct, so it fails Principle 4 and
  ADR-0009, and it is the administration burden we exist to avoid.
- **Junction mode only, everywhere**: correct and general, but it breaks the Contact to
  Account assumption that third-party apps and standard reporting rely on, and it makes
  the common case harder. Rejected as the default, kept as a mode.
- **Contact mode only**: cannot support Person Accounts at all, which forecloses the
  Agentforce Nonprofit coexistence shape.

## Consequences

- Households get standard object benefits for free: activities, reports, list views,
  address fields, and third-party app compatibility.
- NPSP households are adopted directly in NPSP coexistence mode by mapping record types,
  which is what makes self-migration realistic (plan Section 4.5).
- Two modes mean two code paths to test, but they exist in one service, CI runs a Person
  Accounts org shape (plan Section 7.3), and hardening is its own feature in v0.5 (C-22).
- Household naming, greetings, primary contact, member count, merge and split, and the
  household rollups all address the Account, so they are written once regardless of mode,
  and the canonical model documents those rules once, platform-neutrally, so the two
  modes cannot drift apart in behavior (`docs/architecture/canonical-model.md`).
