# ADR-NEXT: Portal Builder: an off-platform portal with its own one-time-code login, reaching Salesforce through one integration user and a person-scoped portal API

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan D-118 (Portal Builder module, Section 5.9), D-120 (amended here by D-187), D-178
(Portal Builder in release 1.3 with PB-03, PB-07 and PB-08), D-187 (owner decision 2026-11-07),
D-09, Section 1.5, Section 4.13 (security), Section 9.9 (portability), Section 11.2 item 30;
builds on ADR-0013, ADR-0017, ADR-0021, ADR-0057, ADR-0131, ADR-0164, ADR-0167 and ADR-0175.

## Context

D-118 asks for logged-in portals built from templates (Board, Volunteer, Service, Partner, later
Speaker, Donor, Applicant, Member directory) whose users need no Salesforce license. D-120 required
an on-platform Salesforce Site with BarnCRM's own login (option B) and waited on a terms check.
D-187 (Brandon, 2026-11-07) replaces that requirement:

> "the Titan and FormAssembly approach. The portal runs off-platform with its own login (one-time
> code by email, optional second factor) and reaches Salesforce through one integration user,
> compatible with the free Salesforce Integration user licenses where the org has them. The
> Salesforce side is a person-scoped portal API in the Portal Builder module: every call names the
> verified portal person and the API returns or changes only what that person's template allows.
> The on-platform Site with BarnCRM's own login (option B) is dropped. Donated internal licenses
> (option C) stay documented for small boards."

D-09, ADR-0013 and the Section 1.5 non-goal are kept: there is no Experience Cloud, no Site and no
guest user. The portal is not a donor portal for payments (Section 1.5): BarnCRM takes no money.
BarnCRM promises no hosting, installation or support (self-service only).

## Research: the Salesforce Integration user license

What was verified, with sources (fetched 2026-11-07):

1. **What it is.** Salesforce Spring '23 release notes, "Assign the New Salesforce Integration User
   License to Grant API Only Access" (PDF:
   https://resources.docs.salesforce.com/242/latest/en-us/sfdc/pdf/salesforce_spring23_release_notes.pdf,
   web: https://help.salesforce.com/s/articleView?id=release-notes.rn_api_integration_license.htm&release=242&type=5):
   "The Salesforce Integration user license grants a user access to Salesforce data and features
   only through an API." "Use the Salesforce Integration API permission set license to extend and
   restrict specific user and object permissions. This user license is designed for
   system-to-system integrations. It may not be used for human users to access Salesforce data or
   features through any user interface."
2. **Editions.** Same note: "One or more Salesforce Integration user licenses are available by
   default in Enterprise, Unlimited, Performance, and Developer Editions. More add-on licenses are
   available to purchase for these editions." Professional Edition is not listed.
3. **How many.** Salesforce's own note says only "one or more". Secondary sources say five in
   Enterprise, Performance and Unlimited and one in Developer Edition
   (https://www.salesforceben.com/salesforce-release-5-free-integration-user-licenses/). Observed
   directly: the BarnCRM test org `oi-test` (an Enterprise Edition sandbox) lists the user license
   `Salesforce Integration` with 5 licenses and the permission set license `Salesforce API
   Integration` with 5. The count is therefore stated as "5 in the orgs checked", not as a promise.
4. **Profile.** The license carries the profile `Minimum Access - API Only Integrations`. In
   `oi-test` that profile has API Enabled and API Only User, and does **not** have Apex REST
   Services.
5. **Object access.** Salesforce Help ("Give Integration Users API Only Access",
   https://help.salesforce.com/s/articleView?id=platform.integration_user.htm&type=5) could not be
   fetched (the page renders only in a browser); its search summary says the permission set
   license carries many of the System Administrator profile's permissions. Practitioner sources
   (https://bluninjas.com/how-tos/how-to-use-the-new-salesforce-integration_user-licenses/,
   https://www.freelikeapuppy.tech/post/setting-up-the-free-integration-users) report that custom
   object access is granted by an ordinary permission set with no license, and standard object
   access (Account, Contact) only by a permission set whose license is `Salesforce API
   Integration`; that Visualforce page access cannot be granted; and that some readers could not
   reach Account at all. **Unverified by BarnCRM:** whether Apex class access and the Apex REST
   Services permission can be granted to this license. Nothing in this design is stated to work on
   the Integration license until the admin guide's check (below) passes in a real org.

What this means for the design:

- **The portal API needs no object access at all.** The integration user is granted only API
  access to one Apex REST class (`PortalApi`) and the Apex REST Services permission, through the
  shipped permission set `Portal_Integration` (no license). The Apex reaches records in system
  mode, scoped by the verified person and the template (decision 6). So the uncertain standard
  object access of the Integration license does not matter, and the integration credentials alone
  cannot read Contacts through the standard REST API.
- **Fallback, stated plainly:** where the Integration license is missing (Professional Edition, or
  all its seats used), or the org refuses to assign `Portal_Integration` to an Integration-licensed
  user, the integration user is a regular API-enabled user (a Salesforce Platform or Salesforce
  license the org already pays for, or one more seat). That costs one license, not one per portal
  person. The admin guide says which to use and how to tell.
- **Terms, stated plainly:** the release note says the license "may not be used for human users to
  access Salesforce data or features through any user interface". A portal shows a person their
  own records in a non-Salesforce interface through the integration user. Whether that is the
  "system-to-system integration" the license allows, and whether Salesforce's general rule against
  sharing one user's access among many people applies, is a contract question only Salesforce can
  answer. BarnCRM does not claim either way; the admin guide tells the organization to confirm with
  its Salesforce account executive, as Titan and FormAssembly customers do, and lists option C.

## Decision

1. **Its own package, Core only, both editions.** `packages/portal`, package `BarnCRM Portal
   Builder`, module key `Portal`, catalog row `BarnCRM_Module.Portal` (Editions
   `Standard;Nonprofit`). Core finds `PortalAccessSync` and `PortalPostInstall` by name.
2. **Three objects and a settings object** (canonical model 29PB1 to 29PB4): Portal
   (`Portal__c`: key, title, status, access mode, second factor policy, session length, sender
   address, the template as JSON); Portal Access (`Portal_Access__c`, detail of Portal: the person,
   status, failed attempts, locked until, second factor enrolment); Portal Session
   (`Portal_Session__c`, detail of Portal Access: the stage, hashes of the token and code, expiry,
   attempts, last used); Portal Settings (`Portal_Settings__c`, hierarchy: the org-wide switch and
   limits, edited in the Settings console under a new Portals section).
3. **Template definitions are versioned JSON** (`schemaVersion` 1), the same contract in Apex
   (`PortalTemplate`) and the client (`portal-client/src/template.js`). A template has a key, a
   title, `requiresModules` (module keys; the portal is unavailable when one is not installed),
   and pages. Each page has a key, title and `kind`:
   - `person`: the verified person's own Contact.
   - `related`: records of one custom object whose `personField` (a lookup to Contact) is the
     person; optional fixed `where` tests and `orderBy`, a `limit` (at most 200).
   - `catalog`: records of one custom object offered to every signed-in person (open shifts,
     sessions), read only, narrowed by required fixed `where` tests.
   Each page lists `fields` (`field`, optional `label`, `edit`, `required`) and `actions`
   (`update`, `create`, or `{ "extension": "Module.Action", "label": ... }`). `where` tests are
   `{ field, op, value }` with ops `equals`, `notEquals`, `greaterOrEqual`, `lessOrEqual`,
   `isBlank`, `isNotBlank`, and the values `TODAY` and `NOW` resolved on the server. A field may
   name one parent hop (`Session__r.Name`) for reading only. Rules checked on every call, so a
   broken template fails closed: objects are custom (`__c`, not a custom setting, not a Portal
   object) except Contact on a `person` page; every field exists; editable fields are
   updateable, non-reference, non-system fields of a safe type; `personField` is a lookup to
   Contact. PB-03 (volunteer: open shifts as `catalog`, my sign-ups and hours as `related`, sign up
   as an extension action), PB-07 (speaker: profile, applications, sessions) and PB-08 (donor:
   gifts and pledges as `related`, contact details as `person`, no payments) fit this shape.
4. **Login: one-time code, sent and checked by Salesforce.** `login/start` takes the portal key
   and an email. Salesforce finds the person (Invited portals: an active Portal Access whose
   person's email matches; Any Matching Person portals: exactly one Contact with that email, given
   an access row on first use), creates a Portal Session at stage Code Sent holding a SHA-256 hash
   of a random 256-bit challenge token and a hash of a six-digit code from `Crypto`, valid for the
   setting's minutes (10 by default), and emails the code from Salesforce
   (`Messaging.SingleEmailMessage`, from the portal's organization-wide address). The response is
   the same for a known and an unknown email (a random challenge that matches nothing), so the API
   never says who is on file. `login/verify` checks the code in constant time. Codes and tokens are
   never stored in clear and never returned by the API, so whoever holds the integration
   credentials cannot sign in as a person without that person's mailbox.
5. **Second factor (optional per portal).** Off, Optional or Required. The factor is a time-based
   authenticator code (TOTP, RFC 6238, HMAC-SHA1, 30 seconds, six digits, one step of drift),
   checked in Apex: no paid SMS service. Required: a person not yet enrolled enrols during sign-in
   (the secret is returned once, as a base32 secret and an `otpauth://` URI) and confirms with a
   first code. Optional: a signed-in person may enrol. Staff reset it on the Portal Access record.
   The secret is kept on Portal Access in a field no permission set grants.
6. **Sessions.** A verified sign-in turns the session to Active with a new random 256-bit token
   (only its hash kept); the token goes to the client once. Every data call resolves the token's
   hash and refuses unless the session is Active, unexpired (absolute: the portal's session hours,
   8 by default; idle: the setting's minutes, 30 by default), the access is Active and unlocked,
   the portal is Active and the org-wide switch is on. **Revocation from Salesforce:** set the
   session's stage to Ended, suspend the person's Portal Access, set the portal Inactive, or turn
   the org-wide switch off; each takes effect on the next call. Revoking the integration user's
   connected app token stops every portal at once.
7. **Rate limits and lockout** (Portal Settings, org-wide): code requests per person per hour (5),
   code emails per portal per hour (200), wrong codes per challenge (5), consecutive failures
   before a lockout (10) and the lockout length (30 minutes). A limit reached on `login/start`
   sends no email and still answers as usual, so limits never reveal who is on file. The WordPress
   proxy adds a per-browser-address limit, since only it sees the visitor's address.
8. **A thin Apex REST API, system mode, person scoped.** `PortalApi`
   (`/services/apexrest/barncrm/portal/v1/*`) parses JSON and calls `PortalAuth` and `PortalData`,
   which run `without sharing` with `WITH SYSTEM_MODE` reads and `AccessLevel.SYSTEM_MODE` writes
   (register: Portal kind). This is the security boundary, replacing sharing: a read selects only
   the template's fields, filtered by the person (or the catalog's fixed tests); an update first
   re-reads the record through the same filter; a create always sets `personField` to the person;
   only `edit: true` fields are written, values coerced to the field's type; every refusal is
   `not_allowed`. Errors return a short code, never a stack or record detail.
9. **A Core seam for module actions.** Core gains `PortalActionExtension` and
   `PortalActionExtensions` (the ADR-0057, ADR-0167 and ADR-0175 mechanism: class names resolved
   with `NamespaceUtil.resolveType`, absent when not installed, a failure logged and skipped). A
   module (Volunteers for PB-03 sign-ups) names its actions and runs one for a verified person and
   a record Portal Builder has already checked is on that page. The extension acts only for that
   person. Neither package depends on the other.
10. **Permission sets.** `Portal_Admin` (portals, access and sessions; given to BarnCRM Admin
    holders by `PortalAccessSync`, never taken away) and `Portal_Integration` (the API class and
    Apex REST Services only; never given automatically: the admin assigns it to the integration
    user).
11. **Off-platform client, framework free.** `portal-client/` at the repository root (not a
    package, never deployed to Salesforce, ignored by `.forceignore`): plain ES modules for the
    API calls, the login screens and the template renderer, with Jest tests, and a minimal
    WordPress plugin `portal-client/wordpress/barncrm-portal/` that serves the client from a
    shortcode and proxies every call through PHP. The plugin holds the OAuth client secret and the
    access token server side (client credentials flow, run as the integration user through an
    External Client App or connected app); the browser sees only the session token, in an
    HttpOnly, Secure, SameSite=Strict cookie the proxy sets. BarnCRM ships the plugin as source
    and documents setup; it promises no hosting or support.

## Threat model (summary)

| Threat | Control |
|---|---|
| Stolen integration credentials | They reach only `PortalApi`; with no session they can request codes (emails to real owners, rate limited) and nothing else. Revoke the token or deactivate the user. |
| Guessing codes | 10^6 codes, 5 tries per challenge, 10 failures lock the access, codes expire in 10 minutes. |
| Finding who is on file | `login/start` answers the same for every email; limits are silent. |
| Stolen session token | HttpOnly cookie, idle and absolute expiry, revocable in Salesforce; only hashes stored. |
| A person reading another's records | Every read and write filtered by the person in Apex; updates re-read through the filter; lookups never editable. |
| A bad template | Re-checked on every call; fails closed with `portal_unavailable` and an Error Log entry. |
| Email flooding | Per-person and per-portal hourly caps; the org's daily email limits still apply. |

## Alternatives considered

- **Option B, a Salesforce Site with BarnCRM's own login.** Dropped by D-187.
- **Experience Cloud.** Rejected by D-09 and Section 1.5 (license cost).
- **The client sends and checks codes.** Rejected: the integration credentials alone could then act
  as anyone.
- **Granting the integration user object access and running the API in user mode.** Rejected: it
  needs standard object access the Integration license may not give, and lets the credentials read
  every Contact through the standard API.
- **A Portal Page object per page.** Rejected: one JSON template is versioned by copying one value,
  matches the Forms contract (ADR-0175) and ports to WordPress (plan 9.9).

## Consequences

- One integration user per org runs every portal; its daily API calls count against the org's API
  limit, and code emails against the org's email limits.
- The Integration license works only where the admin guide's check passes; otherwise one paid
  API-enabled user is needed. Terms are for the organization to confirm with Salesforce.
- PB-03, PB-07 and PB-08 ship as template JSON in later items, with module actions through the
  Core seam. Option C (donated internal licenses for a small board) stays documented, not built.
