# ADR-0095: User access policies are documented definitions, not packaged components

**Status:** Proposed (builder decision)
**Date:** 2026-10-13
**Source:** Core quality pass item Q-09; ADR-0046 (unlocked now, managed at listing); C-06 Access

## Context

Salesforce user access policies (`UserAccessPolicy`, Metadata API 57.0 and later) grant or
revoke permission sets, permission set groups, licenses, groups and queues for users who match
up to three filters (profile, role, permission set or group, package license, public group or
queue) and up to ten User fields. They run when a matching user record is created, updated or
both, or once when an admin clicks Apply Policy. Facts that bear on shipping them:

- The 2GP developer guide (Summer '26) lists User Access Policy as packageable in managed 1GP
  and 2GP. It installs in Design status and only the subscriber can set Status, Order and
  Trigger Type. The Metadata API also turns any deployed Active policy into Design.
- BarnCRM installs as unlocked packages until the listing (ADR-0046). Neither guide says
  whether unlocked packages carry the type; that needs an org check.
- The feature is off by default (User Management Settings), and is documented for Enterprise
  and Unlimited editions. Whether a package containing a policy installs into an org where it
  is off is not documented.
- When a user matches several active policies, only the one with the lowest Order is applied.
- Assigning a permission set group does not update the User record, so a policy keyed on a
  BarnCRM role does not run when the Access page gives that role.
- The most useful policy, "new staff get a role", filters on a profile, and profiles differ in
  every org, so it cannot ship as metadata at all.

## Decision

- **No package ships a `UserAccessPolicy`.** Core and Giving stay installable in any org,
  whatever its edition or its User Management Settings.
- **The admin guide page `docs/admin-guide/automatic-access.md` gives exact definitions** an
  admin creates in Setup: one profile-based "new staff get a role" policy, and three Giving
  policies that grant Giving Admin, Giving Staff and Giving Read Only to holders of the BarnCRM
  Admin, Fundraising Staff and Read Only roles.
- **The three org-independent policies are also kept as Metadata API files** in
  `docs/admin-guide/samples/user-access-policies`, deployable with `--metadata-dir`, for
  consultants and for the org check below. They are not in any package directory.
- **The Access page and the Setup Assistant's access step link to that page** under "Set up
  automatic access". BarnCRM cannot create or activate a policy from the app: both need Setup
  and the Manage User Access Policies permission, as creating a user already does.

## Alternatives considered

- **Ship the three Giving policies in the Giving package, inactive.** Rejected for now: unlocked
  support and install into a feature-off org are unverified, and a failed install of Giving is
  far worse than a manual step. A shipped policy also takes an Order slot that can silently
  stop an org's own policy from applying.
- **Create or activate policies from Apex.** Not possible from a package; policies are setup
  metadata and need a Metadata API callout with admin rights, which is a new framework.
- **A new Setup Assistant step.** Rejected: it would change the step count, the service and
  every step test for something that is optional; a link on the existing access step is
  enough.
- **Do nothing.** The module permission set gap on the Access page stays manual per person.

## Consequences

- Admins who want automation do one to four short Setup tasks. The guide states the field
  values, so nothing is designed by hand.
- The policies keyed on a role reach existing users only through Apply Policy or a user edit;
  the guide says so plainly.
- The definitions must follow any rename of the BarnCRM roles or Giving permission sets.
- Revisit at the managed listing (ADR-0046), on evidence from these org checks: deploy the
  sample folder to a scratch org with `userAccessPoliciesEnabled` on and off; create a Giving
  package version that contains one sample policy and install it into an org with the feature
  off. If both succeed, shipping the three Giving policies in Design status becomes the better
  choice, and this ADR is superseded.
- When the Module Manager joins module permission sets to the roles (Access page, version
  0.7), Policies 2 to 4 are no longer needed and the guide drops them.
