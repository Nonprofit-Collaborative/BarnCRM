# BarnCRM Memberships

Optional module, both editions, depending on Core only (ADR-NEXT `NEXT-memberships-module.md`).
Members (people, households, organizations) with one `Membership_Term__c` per term at a
`Membership_Level__c`, benefits per level (`Membership_Benefit__c`), renewals by hand, from Giving
gifts and recurring gifts (read by name when Giving is installed) and from online payments
through BarnCRM Payments (`PaymentsApi`, found by name), lapse handling and optional renewal
reminders in one nightly step, a member directory portal template
(`portal-client/templates/member.json`) and a Migration Assistant kit for Memberships Essentials.

Object names differ from Memberships Essentials' (`Membership__c`) on purpose: both are
unpackaged today, so a shared name would collide on deploy.

Admin guide: `docs/admin-guide/memberships.md`. Canonical model: Sections 29MEM1 to 29MEM4.
