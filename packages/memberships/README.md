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

No app of its own: the catalog row's `App_Name__c` is `BarnCRM_Members_Partners` (a Core app,
shown by the Memberships permission sets), so `scripts/org/module-app-tabs.py` adds
`Staff_Tabs__c` there first and `Admin_Tabs__c` to BarnCRM Admin Console and that app
(ADR-NEXT (nine console apps)).

Admin guide: `docs/admin-guide/memberships.md`. Canonical model: Sections 29MEM1 to 29MEM4.
