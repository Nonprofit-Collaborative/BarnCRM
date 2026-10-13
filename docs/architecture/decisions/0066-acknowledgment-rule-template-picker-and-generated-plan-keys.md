# ADR-0066: Acknowledgment rules pick their template by name, and plan keys are generated

**Status:** Accepted
**Date:** 2026-10-12
**Source:** UI/UX review item 5 (approved by the product owner "as recommended"); plan Section
2.3 (no setting requires knowing an API name); refines ADR-0032 and the G-15 stewardship plan
page

## Context

Two settings asked Maria for an identifier.

- **An acknowledgment rule names its email template by developer name**, as text (ADR-0032: no
  lookup to `EmailTemplate` is possible from a custom object). Rules were created on the
  standard New page, so she had to copy a developer name such as `BarnCRM_Thank_You` from a
  table on the Acknowledgments page into a text box. Typing the label instead is the mistake the
  admin guide had to warn about.
- **A stewardship plan asked for a "Plan key"**, a code such as `first_gift_welcome`. The key
  exists so a shipped default is recognized on upgrade after a rename (`Plan_Key__c`, unique),
  which is a package concern, not something an administrator should have to invent.

## Decision

1. **Rules are created and edited on the Acknowledgments page**, in a `lightning-record-edit-form`
   (a standard base component): every field except the template is a standard
   `lightning-input-field`, so field-level security, required fields and validation rules apply
   exactly as on the standard page. The template is a `lightning-combobox` built from the active
   templates the page already loads, offered by name, storing the developer name. It shows when
   the channel is Email and is required there. The rule's name still opens the standard record
   page for viewing.
2. **The rule's template is shown by its name** in the rules table, and the table of templates
   with their developer names is removed. The `Email_Template__c` field and its validation rule
   do not change, so a rule created anywhere else is still checked, and a name that does not
   resolve is still flagged "Template not found".
3. **A new stewardship plan's key is generated from its name**: lower case, runs of other
   characters replaced by one underscore, at most 70 characters, `plan` when nothing is left,
   and `_2`, `_3` and so on added until it is unique (compared without case, as the unique field
   compares). Uniqueness is checked in system mode, because a key held by a plan the user cannot
   see would still refuse the save. An edit never changes the key. The page no longer shows it.
   An API caller that passes a key for a new plan keeps it.

## Alternatives considered

- **Keep the standard New page and add help text.** Rejected: the identifier is still typed by
  hand, which is what plan 2.3 forbids.
- **A custom modal or a full custom rule editor.** Rejected: a record edit form inside the page
  gives standard validation and field rendering with only the picker custom.
- **A quick action LWC on the rule record.** Rejected: it would still leave the standard New
  page as the way rules are created, and the review item is about creation.
- **A picklist field of template names.** Rejected: templates are created by the org at any
  time, so a packaged picklist cannot list them.
- **Derive the plan key in a trigger.** Rejected: the page is the only place an administrator
  creates plans, shipped defaults bring their own key, and a trigger would be a second writer of
  a field that must never change after creation.

## Consequences

- A rule created or edited on the standard record page (for example from the Acknowledgment
  Rules tab) still shows the text field, whose help text now points to the Acknowledgments page.
  A fallback layout for the rule object belongs to the record page work, not this decision.
- The rule form depends on `lightning-record-edit-form` submitting a field that is not on the
  form (`Email_Template__c`), which the component supports. An org run should confirm the
  validation rule's message appears in the form's message area if it ever fires.
- Generated keys follow the plan's first name. A plan renamed later keeps the key of its
  first name, which is the point of the key.
