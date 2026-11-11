# ADR-NEXT: The BarnCRM Memberships module: its own package on Core, one record per membership term, renewals from Giving and from online payments, and a member directory portal

**Status:** Accepted (builder decision)
**Date:** 2026-11-11
**Source:** plan Section 6.0a release 1.8 (G-22a to G-22d, PAY-02) and release 1.11 (PB-09),
D-157 (research proposal 4, Memberships module approved), D-190 (payments through the org's own
Stripe or PayPal), Section 6.1.1 item 5 and Section 6.1.5 (Memberships Essentials, Fonteva,
Nimble AMS), Section 9.9 (portability). Builds on ADR-0013 (Core runs alone), ADR-0017
(cross-package mechanisms by name), ADR-0110 (erase a person), ADR-0131 (module access by role),
ADR-0164 (help text JSON), ADR-0166 (nightly dispatcher), ADR-0185 and ADR-0191 (portal templates)
and ADR-NEXT `NEXT-payments-module.md` (the payment seam).

## Context

Memberships is the largest structural gap the research found (plan Section 6.1.5): museums,
associations, friends groups and community organizations sell yearly memberships in tiers, renew
them, remind members before they lapse, and give benefits per tier. D-157 approved a module for
both editions, not built on Opportunity, with renewals from Giving when it is installed, a member
directory portal later and certifications (G-22e) later still. D-190 adds paying dues online.

The Commons project Memberships Essentials, which some first customers may already run, is
unpackaged (no namespace) and ships its own `Membership__c`, `Membership_Contact_Role__c` and
`Membership_Form_Submission__c`, a Product2-based catalog, Opportunities for dues, and membership
fields on Contact and Account. BarnCRM has no namespace yet either, so any BarnCRM object or
field with one of those API names would collide on deploy.

## Decision

1. **Its own package, Core only, both editions.** `packages/memberships`, package
   `BarnCRM Memberships`, module key `Memberships`. Core ships the catalog row
   `BarnCRM_Module.Memberships` (editions `Standard;Nonprofit`, no probe object, its Setting
   Definition rows name the module, #1053), so Core finds `MembershipsAccessSync` and
   `MembershipsPostInstall` by name. No app of its own (ADR-0192): the Memberships tab is a staff
   tab and Membership Levels an admin tab in the BarnCRM apps. Install leaves the module off.
   Giving and Payments are optional: Memberships reads them by name (dynamic SOQL and
   `System.Callable`), so it deploys and runs with neither.
2. **Three objects, names that cannot collide with Memberships Essentials.**
   - `Membership_Level__c` (29MEM1): a type and tier (`Type__c` text such as Individual,
     Household or Corporate; `Tier__c` rank), yearly dues, term in months (0 means the
     membership does not expire), grace days, active, and the Giving fund whose gifts pay for it.
   - `Membership_Benefit__c` (29MEM2): the benefits of a level, master-detail to it (G-22c).
   - `Membership_Term__c` (29MEM3): one term of one membership. The member is a person
     (`Contact__c`), a household or organization (`Account__c`), or an account with a named
     contact. Status Pending, Current, Grace, Lapsed, Renewed or Cancelled; start and end dates
     (no end date means no expiry); member since; the term it renews; origin (New, Renewal,
     Rejoin); source (Staff, Gift, Recurring Gift, Online Payment, Import); dues and amount paid;
     the Giving gift, recurring commitment or payment that paid it, as record ids in text so
     Memberships names no Giving or Payments object (ADR-0014); and the member's opt-in
     directory listing.
   No field is added to Contact or Account: Essentials already adds membership fields there.
   Household and organization members are the account's people through Core's household
   membership and affiliations; there is no member role object (an Essentials role imports as the
   term's contact only).
3. **One record per term, not one record with moving dates.** A renewal is a new term that points
   to the one it renews, which becomes Renewed. History, retention reports (new, renewal and
   rejoin counts) and the payment of each term stay as they were, the way Essentials and
   association systems count members. A member is current when they hold a Current or Grace term
   (`Is_Active__c`).
4. **Dates and renewals in one service.** `MembershipService` fills a new term (dues from the
   level; start today when Current and blank; end the start plus the term less a day; member
   since carried from the term renewed) through a trigger handler registered in the Automation
   Registry, and renews: the new term starts the day after the old one ends when the old one is
   Current or Grace (renewing early or in grace keeps the member's dates), otherwise on the
   renewal date (Origin Rejoin).
5. **The nightly run** (`MembershipsNightlyJobProvider`, one step, 6:50 AM, ADR-0166), in order:
   - **Gift renewals (G-22b)**, when Giving is installed and Renew From Gifts is on: each Received
     gift of the last 45 days allocated to an active level's fund, from a donor contact or
     donor account, and on no term yet (`Gift_Id__c` is unique), pays a term at the highest active
     level on that fund whose dues the gift meets. A gift on a Recurring commitment counts the
     commitment's yearly amount, and the term keeps the commitment. The member's latest term is
     renewed; with none, a New term starts on the gift date. A gift that meets no level is left
     alone.
   - **Recurring renewals:** a Current or Grace term past its end whose commitment is still
     Active renews instead of lapsing.
   - **Lapse handling:** a Current term past its end becomes Grace while within its level's grace
     days, then Lapsed; a term with no end never lapses.
   - **Reminders**, when Send Renewal Reminders is on (ships off: it emails members): one email
     per term from the template named in settings (shipped `BarnCRM_Membership_Renewal`, editable)
     to the term's contact, Reminder Days before the end, stamped first and unstamped when the
     send fails, as Events does (EV-14). No email address, or opted out of email, means no email.
   Each phase handles up to 2,000 terms a night; the rest are handled the next night.
6. **Dues paid online (PAY-02) through Payments, never a second payment path.** Staff (the Email
   Payment Link button on a term) or the member (the Pay Dues action on the member portal) ask
   for a payment link. A queued job (callouts are not allowed after the portal's or the page's
   writes) calls `PaymentsApi.startCheckout` by name with the level's dues, the member as payer,
   the term as `sourceRecordId` and `MembershipPaymentListener` as listener, stores the hosted
   checkout address on the term and emails it to the member with the template
   `BarnCRM_Membership_Payment_Link`. The checkout address works for a limited time (Stripe 24
   hours), so the email says to ask for a new link after that. The return address after paying is
   the org's first active Salesforce Site's home page, else the org's own domain.
   `MembershipPaymentListener.paymentChanged` dates the membership on payment: when Paid, a
   Pending term becomes Current from the payment date, and any other term is renewed (the new
   term carries the payment id, unique, so a second notice changes nothing); when Refunded, the
   term the payment made becomes Cancelled. Failed or Cancelled payments change nothing.
   BarnCRM holds no money and no card data; without Payments installed and connected the button
   and the portal action say so and do nothing.
7. **Member directory (PB-09)** is the portal template `portal-client/templates/member.json`
   (`requiresModules: ["Memberships"]`): My Membership (the person's terms, read only, with the
   Pay Dues action), My Directory Listing (opt in, location and a short bio, on the person's
   active terms) and Member Directory (a catalog of active terms whose member opted in, showing
   only the member name, level, location and bio). The catalog is searchable in the browser: a
   page may set `"search": true`, which Portal Builder passes to the client with the page, and
   the client filters the rows it was sent by the text typed (nothing new is queried). No other
   person's contact details are ever on a page. The pay action is `MembershipsPortalExtension`
   (`Memberships.PayDues`), registered in Core's `PortalActionExtensions`.
8. **Memberships Essentials (G-22d).** Coexistence: different object names, no Contact or Account
   fields, no Opportunity, so both deploy together; the Integrations page row names Memberships as
   the related module. Import: the Migration Assistant kit `Memberships_Essentials` (Section 6.1.4
   item 1, MIG-01) copies Essentials products with a tier (`Product2`, read by name only when
   Essentials is detected) as levels and Essentials memberships as terms, linked to their level,
   with a small kit extension for the months and the status. Essentials is never changed.
9. **Erasure.** `MembershipsErasureExtension` clears an erased person's directory listing and
   notes on their terms and turns the listing off (ADR-0110); the terms themselves stay, as gifts
   do.
10. **Access.** `Memberships_Admin` (BarnCRM Admin holders): levels, benefits, every term,
    settings; `Memberships_Staff` (Team Member, Fundraising Staff): read levels and benefits,
    create and edit terms; `Memberships_Read_Only` (Read Only): read. Given by
    `MembershipsAccessSync`, never taken away.
11. **Pages are thin.** Help text in `BarnHelp_Memberships` (ADR-0164), no custom labels; the term
    actions panel (`membershipActions`) calls a thin controller returning plain shapes, user mode.

## Alternatives considered

- **Memberships on Opportunity (NPSP and Essentials style).** Rejected by D-157: BarnCRM gifts are
  Giving gifts, Core runs on a Platform-only org, and dues would then sit outside Giving totals.
- **One membership record with moving dates.** Rejected: loses each term's payment and the
  retention counts members and boards ask for.
- **`Membership__c` as the object name.** Rejected: it collides with Memberships Essentials while
  BarnCRM has no namespace.
- **Starting the checkout inside the portal action.** Rejected: Portal Builder writes the session
  and sets a savepoint before the action, and Salesforce allows no callout after either.
- **A payment link in every reminder.** Rejected for now: a hosted checkout expires within a day,
  and reminders go weeks ahead.
- **A member roles object (Essentials' `Membership_Contact_Role__c`).** Rejected for now: Core's
  household membership and affiliations already say who belongs to a household or organization.

## Consequences

- New package `packages/memberships` with three objects, a settings object, three permission sets,
  one nightly step, two email templates and one portal extension; Core gains only the catalog
  row, the settings section, and the class names in its lists.
- Gift renewals need the admin to name the Giving fund on each level; a gift to the fund that meets
  no level's dues is left for staff.
- G-22e (certifications and continuing credits) adds its own objects later on the same terms.
- Multi-currency orgs are out of scope (plan Section 6.1): dues are in the org's currency.
