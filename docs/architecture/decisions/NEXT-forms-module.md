# ADR-NEXT: The BarnCRM Forms module: versioned JSON form definitions, a framework-free engine, Core's matchers, and a Core seam for modules that attach forms

**Status:** Accepted (builder decision)
**Date:** 2026-11-06
**Source:** plan Section 6.0a release 1.1 (C-42a, D-157), Section 6.1 item 15 (Forms module),
Section 4.1 (packaging), Section 4.13 (security), Section 9.9 (portability), Section 11.4; builds on
ADR-0013, ADR-0014, ADR-0017, ADR-0057, ADR-0131, ADR-0133, ADR-0159, ADR-0164 and ADR-0167.

## Context

D-157 places the Forms engine first after v1.0 because V-09 (public volunteer sign-up), Event
Management registrations (EV-02), the G-34 donation page, Scholarships applications (SG-02) and the
Portal Builder templates all collect answers from a person and turn them into BarnCRM records. One
engine is built once and reused. C-42a is the engine and the staff builder: multi-step forms,
conditional fields, matching to existing people and organizations, and records created or updated
in BarnCRM. C-42b adds public forms on a Salesforce Site (guest user, spam protection) and C-42c
file upload and save and resume. Plan Section 6.1 item 15 asks for a decision log entry and a
guest-user security design before the public path is built; this ADR settles the engine so that
design fits it, and builds no public or guest access.

## Decision

1. **Its own package, Core only, both editions.** `packages/forms`, package `BarnCRM Forms`,
   depends on BarnCRM Core alone. Forms are not nonprofit-specific, so Core ships the catalog row
   `BarnCRM_Module.Forms` with Editions `Standard;Nonprofit` (Sort Order 45). The module key is
   `Forms`; Core finds `FormsAccessSync` and `FormsPostInstall` by name.
2. **Three objects.** Form (`Form__c`: name, description, status Draft, Published or Closed, the
   working definition as JSON, the published version number); Form Version (`Form_Version__c`,
   master-detail of Form: the definition JSON frozen at publish, with its number); Form Submission
   (`Form_Submission__c`, master-detail of Form: the version it answered, the answers as JSON, the
   person and organization it matched or created, the record it was filled from, its status
   Processed, Needs Review or Failed, and what was written as JSON). Canonical model Sections 29ZW
   to 29ZY.
3. **Definitions are versioned JSON.** A definition carries `schemaVersion` (1 now) and is checked
   on save and on publish by the engine. Publishing freezes the working definition into a new Form
   Version; a submission always names the version it answered, so answers are read against the
   questions as they were asked. Editing a published form changes only the working copy until it
   is published again. The JSON shape (canonical model 29ZW) is the documented contract a
   WordPress block or another module can produce or read (plan 9.9):
   steps with keys and titles; fields with key, label, type (text, textarea, email, phone, number,
   date, checkbox, picklist), required, options, help, limits, an optional `showWhen` condition and
   an optional `target` (`{ record, field }`); a step may also have a `showWhen`; `records` naming
   what a submission writes; `matching` settings per record.
4. **Conditions are data.** `showWhen` is `{ all: [...] }` or `{ any: [...] }` of
   `{ field, op, value }` tests (equals, notEquals, isBlank, isNotBlank, contains, greaterThan,
   lessThan) or nested groups, and may only refer to a field on an earlier step or earlier on the
   same step, so no condition can loop. A hidden field is never required and its answer is dropped
   before anything is written.
5. **The engine is framework-free JavaScript; Apex re-checks.** Parsing, definition checks,
   conditions, answer validation, step navigation and the mapping preview live in plain ES modules
   in the Forms package (`formDefinition`, `formRules`, `formMapping`; no `lightning/*` or
   `@salesforce/*` imports) with Jest tests, so the builder, the runner and a later WordPress block
   share them. The server never trusts the browser: `FormRules` in Apex re-applies the same
   visibility, required and type rules to the published version before anything is written, and
   both are tested against the same cases.
6. **Records written: a person, an organization and related records.** `records` lists up to ten
   entries, each with a key and a kind: `person` (a Contact), `organization` (an Account of the
   organization record type, `AccountKinds`), or `related` (a record of any custom object the
   person may create, with `links` setting its lookups to another entry, the person, the
   organization or the record the form was filled from, and `values` for constants). Fields map
   to an entry by `target.record`. Person and organization are found before they are written;
   related records are always created, in the listed order. A person with no last name or an
   organization with no name that matches nobody is skipped (its questions were optional and
   left blank), and so is a related record linking to a skipped one.
7. **One matcher: Core's.** Forms never adds a matcher. A person is found by email
   (`ImportMatcher.contactsByEmail`), then by last name and postal code
   (`ImportMatcher.contactsByNameAndPostalCode`), each narrowed by first name
   (`ImportMatcher.firstNameKey`, R-IB12), then, when neither finds anyone and the org has an
   active duplicate rule, by the org's duplicate rules (`ImportDuplicateRuleMatcher`). An
   organization is found by name (`ImportMatcher.accountsByName` with the organization record
   type), then by duplicate rules. A key several records hold (`ImportMatcher.isHeldByMany`) is
   never guessed: the submission is kept with status Needs Review and nothing is written; staff
   set the person or organization on the submission and choose Process Again, which uses the
   chosen record. On a match the form fills only blank fields by default (`onMatch: fillBlanks`);
   a form may choose `overwrite`. Core's duplicate review still finds any duplicate a form leaves.
8. **Written as the person, all or nothing.** `FormSubmitService` runs `with sharing`; every read
   is `WITH USER_MODE` and every write `AccessLevel.USER_MODE`, under one savepoint. A failure
   rolls the records back and keeps the submission with status Failed and the reason, so nothing
   typed is lost. Controllers are thin and return plain JSON shapes.
9. **A Core seam for modules that attach forms.** Core gains the interface
   `FormAttachmentExtension` and its registry `FormAttachmentExtensions` (the ADR-0057, ADR-0159
   and ADR-0167 mechanism: class names Core resolves with `NamespaceUtil.resolveType`, absent when
   not installed, a failure logged and skipped). A module (Event Management first) implements it to
   say which of its objects take a form, which form one of its records uses (the form's record
   identifier held as text on the module's record, the ADR-0014 pattern, never a lookup), and to
   receive each processed submission (`FormSubmissionReceipt`: the form, the submission, the
   record it was filled from, the person, the organization, the answers by key and the records
   written by entry key), inside the same transaction, so a registration is written with its
   person. Neither package depends on the other: without Forms the module's text field is unused;
   without the module Forms simply has no extension to call. The Form Runner component can be
   placed on any record page and asks the registry for the record's form when none is set.
10. **Staff only in C-42a; the public path fits later (C-42b).** Nothing here is exposed to a guest
    user. The submit service takes a published version, the answers and an optional context
    record, and returns plain JSON, so C-42b adds a guest entry point beside it rather than
    changing it. The C-42b ADR must settle, at least: a guest-safe allowlist of objects and fields
    a public form may write (checked at publish and at submit); spam protection before any read;
    that a guest submission never reads back or overwrites an existing record's data (fill blanks
    only, or held for review), so matching cannot disclose who is on file; a rate limit; and the
    system-mode writes, confined to the mapped fields of a re-validated published version, that a
    guest user needs.
11. **Three permission sets, given by role.** `Forms_Admin` (build, publish, delete) to holders of
    `BarnCRM_Admin`; `Forms_Staff` (read forms, fill them in, read and process submissions) to the
    Team Member and Coordinator roles; `Forms_Read_Only` (read forms and submissions) to the Read
    Only role. Given by `FormsAccessSync` (ADR-0131), never taken away. A form writes a record only
    where the person filling it may create or edit it: the Forms sets grant nothing on Contact,
    Account or any related object.
12. **Built in the app.** The **Form Builder** panel on the form's record page edits steps,
    fields, targets, conditions and records, previews the form with the runner, saves the working
    copy and publishes. The **Form Runner** fills a published form (on the form's page, an app
    page or any record page). The **Submission** panel shows answers by question and processes a
    held submission again. No settings object: nothing yet is an organization-wide choice.

## Alternatives considered

- **Forms inside Core.** Rejected: plan 4.1 and Principle 3 keep optional features out of Core,
  and a Standard Edition org that never collects forms should carry none of it.
- **One record per field (a Form Field object).** Rejected: a definition as JSON is versioned by
  copying one text value, is the portable contract plan 9.9 asks for, and keeps a form to one read.
- **A Forms matcher tuned for forms.** Rejected by the brief: one matcher (Core's) means imports,
  duplicate review and forms agree on who a person is.
- **Guessing when several people share an email.** Rejected: writing to the wrong person is worse
  than a held submission (the same rule as R-IB12).
- **A lookup from a module's record to Form.** Rejected: it would make the module depend on Forms.
- **Screen Flow or OmniStudio forms.** Rejected: OmniStudio is excluded (plan 4.2), and a Flow is
  neither versioned JSON nor portable.

## Consequences

- Three more custom objects in an org with Forms.
- A form that maps fields the person filling it cannot edit fails at submit, with the field named;
  the builder shows a field's access when it is mapped.
- A person-account org matches people on Contact only in C-42a; matching person accounts through
  `ImportMatcher.personAccountsByEmail` is left for C-42b, which will also need it.
- Answers are kept as JSON on the submission (up to 131,072 characters); a report reads the
  person, organization, status and dates, not individual answers.
- Event Management (EV-02) and the other reusers implement `FormAttachmentExtension` in their own
  package; Core lists each class name, as it does for the other seams.
