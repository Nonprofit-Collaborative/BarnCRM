# ADR-0184: Public forms on a Salesforce Site: a guest intake that only stores answers, processing as a staff user, spam checks with no outside service, and one submit service for a Site page and an API caller

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan Section 6.0a release 1.1 (C-42b, C-42c, D-157), Section 6.1 item 15 (Forms
module: "needs a guest-user security design before build"), Section 4.13 (security), Section 9.9
(portability), Section 11.4; D-187 (Portal Builder serves forms off-platform through an
integration user). Builds on ADR-0175 (Forms module, decision 10 lists what this ADR must settle),
ADR-0014, ADR-0017, ADR-0048, ADR-0057, ADR-0131 and ADR-0164.

## Context

C-42a built the engine for staff: answers are written as the person filling the form, in user
mode, through Core's matchers. A public form is filled by someone with no Salesforce login. On a
Salesforce Site that person is the Site's guest user, which Salesforce restricts on purpose:
guest sharing is "secure guest user record access" (always on), a guest cannot own records, and
a guest given read access to people would expose them to the internet. Core's matchers
(`ImportMatcher`, `ImportDuplicateRuleMatcher`) run `with sharing` in user mode, so as the guest
they find nobody and every public submission would create a duplicate. ADR-0175 decision 10 asks
this ADR to settle: an allowlist of what a public form may write, checked at publish and at
submit; spam protection before any read; that matching never discloses who is on file; a rate
limit; and how far system mode reaches. D-187 adds that Portal Builder will serve the same forms
off-platform through an integration user, so the rules cannot live only in a Site page.

## Decision

1. **The guest only stores answers.** The guest entry point (`FormPublicController`, through
   `FormIntakeService`, `without sharing`) does exactly three reads and one write, all in Apex
   with explicit checks: the form (Published and marked public), its version (public in its
   definition), the count of the form's public submissions in the last hour, and one insert of a
   Form Submission with Status Received and Source Public. It never reads a person, an
   organization or any other record, and never returns a record identifier. The guest user is
   given no object or field permission at all: the permission set `Forms_Public_Guest` grants
   only the `FormPublicController` class and the `FormsPublic` Visualforce page.
2. **Processing runs as a staff user, through C-42a unchanged.** A received submission is
   processed by `FormSubmitService.processReceived`, in user mode, with sharing, by the job
   `FormPublicProcessor`, scheduled every 15 minutes (four `BarnCRM Forms Public` jobs at :00,
   :15, :30 and :45) by an administrator from Health Check. It therefore runs as that
   administrator, through Core's matchers exactly as a staff submission does (ADR-0175 decision
   7: one matcher, a key held by several never guessed, held for review). An API caller that is
   a real user (Portal Builder's integration user, D-187) has its submission processed at once,
   as itself, in user mode. Writes never run in system mode.
3. **What a public form may write (the allowlist), checked at publish and again at
   processing.** `FormPublicPolicy`: a person (Contact), an organization (Account) or a related
   custom object that is not a Forms object or a custom setting. An answer may be mapped only to
   a field that is createable by the person publishing (or processing), is not a lookup, and is
   not encrypted; lookups are set only through `links` the administrator wrote. `onMatch` must
   be `fillBlanks`: an anonymous answer never overwrites what is on file, and processing forces
   it for every public submission, also when staff process it again. A link to `context` (the
   record the form was filled from) is honoured only when a module's `FormAttachmentExtension`
   says that record uses this form; otherwise the submission is held for review.
4. **Matching discloses nothing.** The guest is told only that the answers were received (or
   which of their own answers to fix). Whether anyone matched, was created or was held is
   visible only to staff on the submission. The definition served to the guest is a public copy
   with `records`, every `target` and every constant removed, so no API name is published.
5. **Spam checks with no outside service, before anything is read.** In this order:
   - a honeypot: a hidden question a person never sees; a filled one returns "received" and
     stores nothing;
   - a signed ticket: loading a form returns `versionId:issuedAt:HMAC-SHA256`, signed with the
     version's own random key (`Form_Version__c.Signing_Key__c`, generated at publish, readable
     by no permission set); a ticket that does not verify, or is older than 24 hours, asks the
     person to reload;
   - timing: a ticket younger than the form's `minSeconds` (default 3) asks the person to send
     again, which a person does and a script does not;
   - a rate limit per form: more than `hourlyLimit` public submissions (default 50) in the last
     hour asks the person to try later.
   The engine's answer checks (`FormRules`) then run as for staff.
6. **The settings are part of the definition.** An optional `public` block
   `{ "enabled", "minSeconds", "hourlyLimit", "confirmation" }` in schemaVersion 1 (additive):
   it is versioned with the questions, checked by `formDefinition.js` and Apex, and portable.
   Publishing copies `enabled` onto `Form__c.Public__c` so public forms are listed with one
   query. Closing a form stops it at once; a form is public only while Published.
7. **One submit service for a Site page and an API caller (D-187, plan 9.9).** Rendering and
   answer rules stay in the framework-free modules (`formDefinition`, `formRules`); the public
   page `formPublic` reuses them and the runner's question views. `FormIntakeService.load` and
   `submit` take and return plain values; `FormPublicController` (Aura, guest) and
   `FormPublicRest` (`/services/apexrest/barncrm/forms/v1/<formId>`, for an authenticated
   integration user) are thin wrappers. Portal Builder needs no Forms change to serve a form.
8. **Household-aware, duplicate-safe matching is Core's.** A new person is inserted with no
   household and Core's household trigger gives them one, as for a person added by hand or by
   import; a matched person keeps their household. People who share a household email are told
   apart by first name (R-IB12), and a key several people hold is never guessed (R-FS2). In an
   org with person accounts, a match that is a person account is held for review, never written
   through its contact (closes the ADR-0175 consequence on person accounts).
9. **Setup Salesforce forces, and the in-app checks.** Salesforce requires an administrator, in
   Setup, to register a Sites domain once, create and activate a Site, and choose its default
   record owner; no API can do this for a package. Everything else is in the app: Health Check
   (Settings console) reports a public form with no active Site, a Site guest user without
   `Forms_Public_Guest` (fix: assign it), a guest user that can read people or organizations
   (error, never changed automatically), processing not scheduled (fix: schedule it as the
   administrator) and received submissions waiting over an hour. The Form Builder shows each
   public form's link on every active Site.
10. **Page delivery.** The Visualforce page `FormsPublic` loads `c:formPublic` through Lightning
    Out (`formsPublicApp`, `ltng:allowGuestAccess`); no Experience Cloud. The address is
    `<site URL>/FormsPublic?form=<form id>` (`&record=<id>` for a form attached to a record).
11. **Files and save for later (C-42c, amendment of 2026-11-07).** Both go through the same
    intake and the same spam checks, and neither lets a guest read a record:
    - A `file` question's answer is the file's name; the file is sent beside the answers as
      base64 and stored by the intake as a Salesforce File on the submission (system mode, as the
      submission is), then shared with the person and organization by processing as the staff
      user. Only documents and pictures are taken (no HTML, SVG or scripts), and at most 1 MB per
      submission, because the base64 text and its decoded copy must fit the 6 MB a request's
      Apex may hold. The staff runner takes files the same way. Salesforce forces one more Setup
      step for a Site: Salesforce Files General Settings, "Allow site guest users to upload
      files".
    - Saving for later is per form (`public.saveForLater`, `public.resumeDays` 1 to 30, default
      7). The intake makes a random 256-bit token, stores only its SHA-256 hash on a Form Draft
      with the answers (files left out), the version and an expiry, and emails the link
      `FormsPublic?form=<id>&resume=<token>` built from the Site's own address, never from the
      caller, so the org cannot be made to mail an outside link. The email address is not stored.
      A link opens the draft's version only, until it expires or the form is sent; drafts count
      toward the hourly limit; processing deletes expired drafts. Not offered on a form opened
      from a record, since the link does not carry the record.

## Alternatives considered

- **Matching as the guest in system mode.** Rejected: Core's matchers are user mode with
  sharing, and copying them into a system mode Forms matcher breaks ADR-0175 decision 7 and puts
  every person record one bug away from the internet.
- **Processing by platform event as the Automated Process user.** Rejected: that user's object
  access in user mode is not documented to cover the records a form writes, and choosing another
  running user needs `PlatformEventSubscriberConfig`, an org-specific Setup step.
- **A CAPTCHA or outside spam service.** Rejected: plan 4.13 and Section 11.4, no outside
  callouts; the checks above stop scripted posts, the common case for nonprofit forms.
- **Experience Cloud.** Rejected: ADR-0009 and ADR-0013.
- **One shared signing key in a setting.** Rejected for a key per version: no new settings
  object, and republishing rotates it.

## Consequences

- A public submission reaches records up to 15 minutes after it is sent; the person sees the
  form's confirmation at once.
- Staff see Source Public and Status Received on waiting submissions; Process Again works on
  them as on any held one.
- The administrator who schedules processing must stay active (Health Check already reports jobs
  owned by inactive users).
- C-42c (file upload, save and resume) builds on the same intake (decision 11): drafts and files
  are stored by the intake and never read back except by the person holding the emailed link.
- Files larger than 1 MB together need a later change (for example a chunked upload); the
  limit is shown to the person when they choose a file.
