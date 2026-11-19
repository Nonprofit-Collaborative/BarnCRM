# ADR-0225: A Forms Administrator Deletes a Form With Submissions, and the Submissions Stay

**Status:** Accepted (owner decision, 2026-11-14)
**Date:** 2026-11-14
**Source:** Brandon, 2026-11-14 (plan D-208, release 1.27, N-04): "Keep protection except for
admins." Amends ADR-0175 (Forms module), decision 2: Form Submission is no longer a master-detail
of Form.

## Context

A submission's Form Version lookup restricts delete, so a form whose versions have submissions
cannot be deleted by anyone, a Forms administrator included. The submission is also a
master-detail of Form, so lifting the restriction alone would delete every submission with its
form: the answers people sent, and the record of what was written from them, would be lost.

## Decision

1. **Submissions outlive their form.** `Form_Submission__c.Form__c` becomes a lookup, set null on
   delete, and `Form_Version__c` becomes set null on delete (was restrict). Nothing is packaged
   yet, so the field type can change. Form Version and Form Draft stay master-details of Form and
   go with it.
2. **Same access as before.** Without a master the submission needs its own sharing: Public
   Read/Write, which is what master-detail under a Public Read Only form with "write requires
   master read" gave (anyone whose permission set may edit submissions edits any of them). The
   Forms permission sets now grant the Form field itself (Staff and Admin edit, Read Only reads).
   A public submission stored by the Site guest user is owned by the Site's default record owner,
   which Salesforce assigns and ADR-0184 decision 9 already has the administrator choose.
3. **Only a Forms administrator deletes an answered form.** `FormDeleteGuard`, before delete on
   Form and on Form Version (registry rows that always run), refuses a form or version that any
   submission answers unless the person holds the new custom permission Manage Forms
   (`Forms_Manage`, in Forms Admin), with a message that names the form and says to set its
   Status to Closed instead. A form or version nobody answered deletes as before.
4. **Submissions name what they answered.** New fields Form Name (`Form_Name__c`) and Version
   Number (`Version_Number__c`), filled by `FormSubmissionNames` before insert and update when
   Form Name is blank (canonical model R-FS8); a Forms administrator's delete fills them first on
   any older submission without them. The Submission panel names a deleted form from Form Name and
   shows the answers by their keys; Process Again is not offered, and processing refuses with a
   message, since no questions are left to process against.

## Alternatives Considered

- **Delete the submissions with the form for an administrator.** Simple, but loses what people
  sent; the owner asked for the protection to stay in substance.
- **Soft delete (a Deleted status on Form).** Keeps every lookup, but leaves the record in every
  list and report, and closing a form already stops it being filled in.
- **Check the Forms Admin permission set by name.** A custom permission is what Salesforce checks
  cheaply (`FeatureManagement.checkPermission`) and survives the set being cloned or renamed.

## Consequences

- Reports on submissions that group by Form show a blank group for a deleted form's submissions;
  Form Name groups them.
- An org that already deployed the master-detail changes the field type on its next deploy
  (a normal source deploy); its existing submissions get Form Name the next
  time they are saved or when an administrator deletes their form.
- Remove Sample Data is unchanged: the sample file removes the submissions before the forms.
