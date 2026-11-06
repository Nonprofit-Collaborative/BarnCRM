# ADR-NEXT: Core ships an organization record type, offered only where the org has none

**Status:** Accepted (owner decision D-184, Brandon, 2026-11-06)
**Date:** 2026-11-06
**Source:** owner decision D-184 A ("Ship with one": Core ships an Account record type for
organizations, used only when the org has none of its own); amends ADR-0141 decision 2 ("Core
ships no Organization record type")

## Context

ADR-0141 stopped shipping an Organization record type: most orgs have their own, and BarnCRM's
overlapped it. An org with no Account record type of its own runs on "No record type", which
works but gives organizations no record type for a page layout, list views or reports, and
stops working the day the org adds any Account record type. The owner chose to ship one again,
used only where the org has none, without disturbing orgs that have their own.

ADR-0141 also recorded the constraints: Apex cannot create or activate a record type; an
inactive packaged record type is written inactive again by every upgrade or redeploy; a record
type given to a user by a permission set becomes their default where the profile has none
(spike V2); a source deploy of a new record type gives it to no profile (V6).

## Decision

1. **Ship `BarnCRM_Organization`, active, given to nobody.** Label BarnCRM Organization, so it
   never collides with an org's own Organization (NPSP's, or the one an earlier BarnCRM left).
   Active, because an inactive one would be deactivated again by each upgrade under an org that
   had activated and chosen it. No profile or permission set gives it, so no user is offered it
   and no default record type changes, in orgs with their own or without.
2. **Never chosen automatically.** It is never a candidate (R-O5): detection never picks it and
   it never makes a stored "No record type" stale, so installing or upgrading changes no org's
   organizations.
3. **Offered only where the org has none.** "Record type for organizations" in General offers
   it beside "No record type" only while the org has no candidate of its own, or while it is
   the stored value. Once chosen it stays in force while active, even if the org later adds its
   own, so nothing switches an org's organizations without an administrator choosing.
4. **The administrator gives it to people**, in Setup, as for any record type they choose.
   BarnCRM's role permission sets do not carry it: giving it to every BarnCRM user would make it
   the default where profiles have none and put it in every picker in orgs that have their own.

## Alternatives considered

- **Ship it inactive and activate it when chosen:** Apex cannot activate a record type, and
  each upgrade would write it inactive again.
- **Detect it automatically where the org has none:** its users would have to be given it
  before they could create organizations, and existing accounts without a record type would
  stop counting as organizations.
- **Give it through the role permission sets:** see decision 4.
- **Name it Organization:** collides with an org's own record type of that name or label.

## Consequences

- Every install lists BarnCRM Organization in Setup beside Household, active and unused unless
  chosen.
- An org that chooses it does one Setup step (give it to the people who create organizations);
  Health Check's existing warning names it until they do.
