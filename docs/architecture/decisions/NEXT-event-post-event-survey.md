# ADR-NEXT: Post-event survey: a Forms form named on the event, sent in the follow-up email with the attendee's own link, answers kept per attendee, through a Core form catalog seam

**Status:** Accepted (builder decision)
**Date:** 2026-11-07
**Source:** plan Section 5.12 (EV-18), D-186, D-123, Section 4 and ADR-0013 (modules depend on Core
only), Section 9.9 (portability); builds on ADR-0175 `0175-forms-module.md` (decision 9, the form
attachment seam), ADR-0184 `0184-public-forms-on-a-salesforce-site.md` (public forms), ADR-0177
`0177-events-module.md` and ADR-0182 `0182-event-registrations.md` (decision 6, the morning email
run).

## Context

EV-18 asks that an event can name a form as its survey; after the event the existing follow-up
step of the morning run sends each attendee who came a link; responses tie to the attendee and the
event; the event shows a simple results summary. Forms is optional: Events depends on Core only,
so without Forms the survey option is hidden. A survey is answered by someone with no login, so
the form must be a public form (ADR-0184), and the link must reach the form through the org's
Salesforce Site. Events cannot read Forms' objects, and Core cannot name them (the
`check-core-names-no-module.py` rule).

## Decision

1. **The event names its survey form as text.** `Event__c.Survey_Form_Key__c` (Text 18) holds the
   form's record identifier, as `Registration_Form_Key__c` does (ADR-0014). Nothing is a lookup.
2. **A Core seam finds the forms and builds the link.** Core gains the interface
   `FormCatalogExtension` (publicForms, questions, publicLink), its registry
   `FormCatalogExtensions` and the plain value class `FormCatalogEntry`, the ADR-0057, ADR-0159,
   ADR-0167 and ADR-0175 mechanism: a class name Core resolves with `NamespaceUtil.resolveType`,
   absent when not installed, a failure logged and skipped. Forms implements it
   (`FormsCatalogExtension`): published forms with Public set, a form's questions read from its
   definition, and the address `<first active Site URL>/FormsPublic?form=<id>&record=<id>.<claim>` from
   the same Sites list the Form Builder uses (`FormsSites`). Without Forms the registry reports
   `isAvailable` false and the Survey section of the event page draws nothing.
3. **The attendee is the form's context record.** The link carries the attendee's record
   identifier as `record`. `EventFormAttachment` (the ADR-0175 seam) now also handles
   `Event_Attendee__c`: for an attendee its `formFor` answers the survey form of the attendee's
   event, which is exactly the check ADR-0184 decision 3 requires before a public form honours a
   context record, and its `received` keeps the answers instead of registering anyone. A survey
   form needs no question that finds or writes a person.

   **The link carries a signed claim.** The attendee's identifier alone must not open the form, so
   the address is `...&record=<attendee id>.<claim>`. The claim is an HMAC-SHA256 of
   `claim:<form id>:<attendee id>` with the signing key of the form's current public version, the
   key ADR-0184 decision 5 already generates for tickets (no new secret;
   `FormIntakeService.claimFor`). `FormAttachmentExtension` gains `signedClaim(recordId)`, true
   for attendees; the public intake closes a submission for such a record with a missing or wrong
   claim and stores nothing. An attendee who is not Attended gets no link and no survey form
   (`formFor` returns null, so processing holds the submission as ADR-0184 decision 3 says).
   Republishing the form issues a new key, so links sent earlier stop working until the follow-up
   is sent again; a form is not republished casually, and this is the cost of no new secret.
4. **Answers are kept in Events.** `Event_Survey_Response__c` (canonical model 29EV18) is a detail
   of the attendee (Controlled by Parent, so the registration's privacy applies): the answers as
   JSON, when received and the submission's identifier as text. One response per attendee: a
   second submit replaces the first (chosen over refusing it, so a person can correct an answer). The event is the attendee's event, so a report or the summary
   reads responses by event through the attendee. Events staff therefore read the summary without
   any Forms permission.
5. **The follow-up carries the link.** In the morning run's follow-up phase (ADR-0182 decision 6),
   attendees of an event with a survey form for which Forms gives an address are sent the survey
   email template (new setting `Survey_Template__c`, default `BarnCRM_Event_Survey`, shipped in the
   BarnCRM Events folder) and stamped with `Event_Attendee__c.Survey_Link__c`, which the template
   merges; all others get the follow-up template as before. The stamp-before-send, clear-on-failure
   and once-each rules are unchanged, and only people marked Attended within seven days after the
   event are sent. A separate template, rather than a merge field in the follow-up, means an event
   without a survey never shows a blank link line.
6. **Results are computed in the browser.** `EventSurveyController` returns the questions, the
   responses (answers as JSON) and the counts; the framework-free `eventSurveyModel.js` works out
   the summary (average, lowest and highest for number questions, counts and percentages for
   picklists and checkboxes, the newest twenty comments) and the response rate (of links sent, or
   of attendees when none were sent) (plan 9.9). Up to 2,000 responses are read.

## Alternatives considered

- **Events reads Form_Submission__c directly.** Rejected: it would depend on Forms, and Events
  staff would need Forms permissions to see their own survey.
- **Core names Forms' objects to list forms.** Rejected by `check-core-names-no-module.py`; the
  extension seam is the pattern for every optional module.
- **The link in the existing follow-up template.** Rejected: a blank link line for every event
  without a survey, and an admin's custom follow-up template would silently lose the link.
- **A new object for survey questions.** Rejected: the form already holds the questions, versioned.
- **A form tied to the event by registering a new context type in Forms.** Rejected: Forms already
  accepts any record a module's `FormAttachmentExtension` claims.

## Consequences

- A link still works for anyone who holds that attendee's whole link, but a record identifier
  alone does not; the survey should not ask for anything sensitive (stated in the admin guide).
- A response reaches Events up to 15 minutes after it is sent (ADR-0184 decision 2: public
  submissions are processed on the schedule).
- Answers are JSON, so a report reads who answered and when, not an individual answer.
- One more object, three fields (event, attendee, setting) and one more email template.
- Public forms still need the one-time Site setup Salesforce forces (ADR-0184 decision 9).
