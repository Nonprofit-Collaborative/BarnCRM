# BarnCRM Memberships

Optional module, both editions, depending on Core only (ADR-0206 `0206-memberships-module.md`).
Members (people, households, organizations) with one `Membership_Term__c` per term at a
`Membership_Level__c`, benefits per level (`Membership_Benefit__c`), renewals by hand, from Fundraising
gifts and recurring gifts (read by name when Fundraising is installed) and from online payments
through BarnCRM Payments (`PaymentsApi`, found by name), lapse handling and optional renewal
reminders in one nightly step, a member directory portal template
(`portal-client/templates/member.json`) and a Migration Assistant kit for Memberships Essentials.

Object names differ from Memberships Essentials' (`Membership__c`) on purpose: both are
unpackaged today, so a shared name would collide on deploy.

App `BarnCRM_Memberships` (BarnCRM Memberships, logo `BarnCRM_Patch_Memberships_Logo`), visible
through the Memberships permission sets; left out of scratch and Developer Edition orgs (ADR-0223,
module apps, and its 2026-11-14 amendment). The tabs also join the BarnCRM apps through the
catalog row's `Staff_Tabs__c` and `Admin_Tabs__c`.

Admin guide: `docs/admin-guide/memberships.md`. Canonical model: Sections 29MEM1 to 29MEM4.
