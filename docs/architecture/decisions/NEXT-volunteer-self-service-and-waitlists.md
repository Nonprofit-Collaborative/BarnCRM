# ADR-NEXT: Volunteer self-service, capacity and waitlists: public shift pages on the Forms host, a signed personal page, one first-fit waitlist rule in Core

**Status:** Accepted (builder decision)
**Date:** 2026-11-11
**Source:** plan Section 6.0a releases 1.4 and 1.6 (V-09, V-12 to V-17, P-09; D-156, D-157),
Section 5.3 and 5.4, Section 1.5 (no payments, self-service only), Section 4.13 (security), Section
9.9 (portability). Builds on ADR-0175 (Forms module, the attachment seam), ADR-0184 (public forms
on a Salesforce Site), ADR-0188 (signed claims for a link that names a person's record), ADR-0190
(public pages through a Core seam) and ADR-0191 (the volunteer portal template, PB-03).

## Context

V-09 asks for public volunteer sign-up without a login, with the person's shifts, an hours report
and profile self-service. Volunteers depends on Core and Rollup Builder only, and Forms is
optional, so neither may name the other. V-14 (shift minimum, maximum and a waitlist) and P-09
(program capacity and a waitlist) need the same rule in two modules that may not reference each
other. V-16 (groups and standing sign-ups) changes what a place on a shift is. V-15 (minors) and
V-17 (background check details) extend onboarding (V-05).

## Decision

1. **Public shift pages through ADR-0190's seam.** Volunteers provides `VolunteerPublicPage`
   (registered in `PublicPageExtensions.EXTENSION_CLASSES`, kind `volunteers`) and
   `VolunteerFormAttachment` (registered in `FormAttachmentExtensions.EXTENSION_CLASSES`). A job
   is published only when its new Show on Public Page checkbox (`Public_Page__c`, off) is on and
   it is Active. `<site URL>/FormsPublic?list=volunteers` lists Open shifts of published jobs that
   start after now, soonest first, at most 50; `?record=<shift id>` opens one shift with the
   job's Sign-Up Form (`Signup_Form_Key__c`, a form record identifier as text, as Events'
   Registration Form Key) and the shift as the form's record. Shown: job name and description,
   shift start, end and location, and places left as a count. Never shown: who is booked, the
   coordinator, notes or any person field.
2. **Sign-up goes through the public intake unchanged.** Forms matches or creates the person
   (Core's matcher, ADR-0184) and, processing as the staff user, `VolunteerFormAttachment`
   books that person on the shift through `VolunteerBooking.book`, the one booking path the
   portal action (PB-03) also uses, so R-VU2, the waitlist (decision 5), groups (decision 6) and
   the minors check (decision 8) apply exactly as for staff. A shift that is full while the
   waitlist is off shows registration closed; a submission that races past it is booked, as
   R-VS4 allows.
3. **A signed personal page for the hours report and profile.** A sign-up is the person's own
   record, so `VolunteerFormAttachment.signedClaim` is true for it and its link is
   `?record=<sign-up id>.<claim>` (the ADR-0188 HMAC with the form's signing key). Its form is
   the org's Self-Service Profile Form (`Volunteer_Settings__c.Profile_Form_Key__c`); with none
   set there is no personal page. The page shows the person's first name, upcoming bookings
   (job, start, status), approved hours this year and in total with their value (V-12), and the
   latest ten approved entries; the profile form below it updates only that person's
   availability days and times and emergency contact name and phone, on the person the sign-up
   names, never a person the answers name. Forms gains one check: `FormIntakeService.publicPage`
   accepts `<id>.<claim>`, and a record whose module asks for a claim gets a page only with the
   right claim, which it passes to `PublicPageExtensions.page(recordId, true)`. Core keeps the
   flag for that call only, and `VolunteerPublicPage` refuses a sign-up page without it, so an
   older host can never serve one. The link reaches the person as one more line in the shift
   reminder (V-10), built by `FormCatalogExtensions.publicLink`; without Forms, a profile form
   or an active Site the line is left out.
4. **The value of an hour (V-12)** is one org-wide number, `Hour_Value__c` (default 34.79, the
   Independent Sector 2024 national value; changeable; 0 hides it). It only displays: a Value of
   Hours This Month figure on Volunteers Home, the personal page, and the letter tokens
   `{HoursValue}` and `{HourValue}`. No stored field holds a value.
5. **One first-fit rule, in Core, for both waitlists.** Core gains `WaitlistQueue`, plain Apex
   with no query or save: given free places per parent and candidates oldest first, it returns
   those that fit, each taking its places (a group's size), skipping one that does not fit so a
   smaller one behind it can go. Volunteers (V-14) and Programs (P-09) each count their own
   places, call it on save to waitlist what does not fit, and on a freed place to promote. Each
   module keeps its own setting, off by default, so nothing changes until an admin turns it on:
   Volunteers' Waitlist When Full (`Waitlist_Enabled__c`) and Programs' Waitlist When Full
   (`Waitlist_Enabled__c` on `Programs_Settings__c`). The order is the record's Created Date.
   A sign-up is Waitlisted (a new Status value); an enrollment is Waitlisted (a new Stage value,
   open for R-EN2). A place frees when a booking or enrollment is cancelled, ended or deleted,
   or the shift's Volunteers Needed or the program's Capacity is raised; counting and
   promotion run in system mode in the same transaction, with no email of their own (the shift reminder covers volunteers).
   Shift minimum (`Minimum_Volunteers__c`) only shows: Below Minimum (a formula) and a list view.
6. **A place is a person or a group (V-16).** A sign-up gains Group Size (default 1) and Group
   Name; a formula Places (Group Size, 1 when blank) is what Slots Filled now sums, leaving out
   Cancelled and Waitlisted. A standing sign-up (`Standing__c`) on a shift of a recurring
   schedule books the same person on every later shift of that schedule: when a schedule creates
   shifts and when a sign-up becomes standing. The person's latest sign-up on the schedule
   decides: it continues while that one is Standing and not Cancelled. Standing bookings do not
   keep a future shift from being removed when the schedule's pattern changes.
7. **Recognition (V-13)** is a morning step (`VolunteerRecognitionJob`, 7:30 AM, off until
   Send Thank-You Tasks is on): a Contact whose total hours reached a milestone in Hour
   Milestones (default `25, 50, 100, 250, 500, 1000`) above Last Hour Milestone gets one Task
   for the highest one reached, and Last Hour Milestone is set; a Contact whose Volunteer Since
   falls on today, one or more years ago, gets one anniversary Task. Tasks go to the Contact's
   owner when active, otherwise to the job runner. Contacts only.
8. **Minors (V-15)** use the Contact Birthdate and Onboarding. With Guardian Consent Required on
   (off by default) and Minor Age (default 18), a sign-up for a Contact under that age on the
   shift's day with no current Guardian consent requirement is saved with Consent Needed checked
   and gets a Not started Guardian consent requirement, created in system mode, naming the
   guardian a public form wrote under the record key `guardian`. The consent's expiry is the
   requirement's Expires. Nothing is refused: the coordinator decides (R-VQ3).
9. **Background check details (V-17)** are three fields on a requirement: Provider, Reference ID
   and Entry Source (Entered, the default, or Imported). BarnCRM calls no provider.

## Alternatives considered

- **Volunteers ships its own guest page.** Rejected as in ADR-0190: a second guest surface.
- **A shift question in the sign-up form.** Rejected: a form's options are fixed when published,
  while shifts change daily; the shift as the form's record needs no form change.
- **A personal page keyed on the Contact.** Rejected: Volunteers would claim every Contact page
  of the seam, and a Contact is not a Volunteers record the module can sign for.
- **A waitlist service in Core that queries and saves.** Rejected: Core cannot name module
  objects, and dynamic queries per module cost more code than the counting they replace.
- **A Standing Sign-up object.** Rejected for now: a checkbox on the sign-up covers a person
  holding one weekly shift without a new object, permission sets and erasure rules.

## Consequences

- Existing orgs keep their installed Slots Filled roll-up definition (COUNT not Cancelled) until
  an admin edits it in Rollup Builder or reinstalls defaults; group sizes and waitlisted sign-ups
  count correctly only with the new definition. Health Check is unchanged.
- The Site guest reads, through `VolunteerPublicPage` in system mode, only published jobs'
  shifts, and a person's own page only with a valid claim.
- `VolunteersPortalExtension` now books through `VolunteerBooking`, so a portal sign-up on a
  full shift is waitlisted when the waitlist is on, instead of refused.
