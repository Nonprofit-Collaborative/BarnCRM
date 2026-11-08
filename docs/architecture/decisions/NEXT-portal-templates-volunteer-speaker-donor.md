# ADR-NEXT: Portal templates for volunteers, speakers and donors: shipped as template JSON, module actions through Core's seam, one read-only parent hop for the person

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan PB-03, PB-07, PB-08 (D-118, D-123, D-178), D-187; builds on ADR-0185 (Portal Builder,
decisions 3, 8 and 9), ADR-0180 (call for speakers), ADR-0013, ADR-0017, ADR-0021 and Section 9.9.

## Context

ADR-0185 shipped the portal engine and said PB-03 (volunteer), PB-07 (speaker) and PB-08 (donor)
"ship as template JSON in later items, with module actions through the Core seam". This record
fixes what those three templates contain and the two small engine changes they need.

## Decision

1. **A template is a JSON file in `portal-client/templates/`** (`volunteer.json`, `speaker.json`,
   `donor.json`), each naming its module in `requiresModules` (`Volunteers`, `Events`, `Giving`).
   An admin pastes one into a Portal's Template field. The template is unavailable while its
   module is turned off (`requiresModules`) and fails closed where the module is not installed,
   because its objects and fields do not exist (ADR-0185 decision 3). No package depends on
   another: the templates name objects, the engine reads them in system mode, scoped to the person.
2. **Volunteer (PB-03).** Open Shifts (catalog: Open, starting now or later, Sign Up), My Shifts
   (the person's sign-ups, not cancelled, Cancel Sign-Up), My Hours (view, and log new entries:
   date, hours and notes only; no edit after saving; the entry starts Submitted, or Approved when
   Volunteers' Hours Require Approval is off, through the same rules as any entry) and My Profile
   (contact, availability and emergency contact).
3. **Speaker (PB-07).** Events Open for Proposals (catalog, Propose a Talk), Open Proposals (the
   person's undecided proposals: edit title and abstract, Withdraw), All My Proposals (read only,
   shows decisions), My Sessions (read only), My Speaker Details (headline, bio, AV and travel
   needs) and My Details. A decided proposal (Accepted, Declined, Withdrawn) is never editable
   by the applicant. The call for speakers has no deadline field (ADR-0180), so the portal shows
   event and session dates and does not invent a call deadline.
4. **Donor (PB-08).** My Giving (the Contact's giving figures, including Pledge Balance), Gift
   History, Pledges and Recurring Gifts (with balance), Receipts (the issued list, no download)
   and My Contact Details (phone and mailing address only; the email address is read only because
   it is the sign-in). The template has no `create` action, no module action and no payment: it
   is read only except contact details (Section 1.5, ADR-0185).
5. **Module actions through the existing seam.** Volunteers implements `VolunteersPortalExtension`
   (`Volunteers.SignUp`, `Volunteers.CancelSignup`) and Event Management implements
   `EventsPortalExtension` (`Events.ApplyToSpeak`, `Events.WithdrawProposal`). Core's
   `PortalActionExtensions.EXTENSION_CLASSES` lists both names; a class not installed resolves to
   nothing and is skipped. Both run `without sharing` in system mode (Without Sharing Register,
   Portal) and act only for the person Portal Builder verified and the record it found on that
   person's page: a sign-up is for the person, a cancel or withdraw first re-reads the record by
   that person, an expected refusal (shift full or past, event closed, already applied) returns a
   message in the module's help catalog, and anything else throws and is logged as `action_failed`.
   Applying to speak creates a Submitted proposal titled for the event that the person then edits,
   since the portal cannot pass values to an action.
6. **One read-only parent hop for the person.** A session assignment (`Session_Speaker__c`)
   links the speaker, not the Contact, so a `related` page may name `personField` as
   `Parent__r.Contact__c`: a lookup to a parent that itself looks up to Contact. The filter is
   the same equality on the person; such a page is read only (no editable field, no `update` or
   `create`), because a write must set the person field and an update's parent could be changed
   by staff between read and save. `PortalTemplate` checks the parent is a single-object lookup
   whose named field looks up to Contact; the client's `checkTemplate` applies the read-only rule.

## Alternatives considered

- **A Contact lookup on Session Speaker, kept by a trigger.** Rejected: a new field and automation
  on Events for a read-only view.
- **A Draft status for a started proposal.** Rejected: it changes the reviewers' tab and the
  application's picklist; withdrawing covers a proposal started in error.
- **Hours that name a shift or job.** Rejected: lookups are never editable in a portal; the job
  and shift fill when staff approve against a sign-up. Sign-up attendance already writes hours.

## Consequences

- The portal's API user reads and writes these objects only through Portal Builder's checks and
  the two module classes; Core gains no object or field.
- A speaker with no sessions sees an empty page until staff assign them; staff should not assign
  a speaker to a session whose time is not yet public.
- Admin Guide, Testing Guide and the features catalog name the templates; the admin guide
  describes the connecting user neutrally as the portal's API user.
