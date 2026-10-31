# ADR-NEXT: A digit-format transform step, a shared fixture, and saved step lists

**Status:** Proposed (builder decision)
**Date:** 2026-10-31
**Source:** plan Section 6.0a C-50f1 and C-50f2 (D-154); Section 9.9 portability. Extends
`0112-more-transform-steps.md` (ADR-0112) and `0081-data-transform-document.md` (ADR-0081).
Amends canonical model R-IT15 and adds Section 29W.

## Context

Super Transform shipped with a Fix Name Capitals shortcut and no way to tidy phone numbers,
because the closed list of steps cannot reorder digits: `replace` removes one literal text and
`part` splits on one. Cleanup presets (D-154) also need a place to keep a person's own step lists
so the same cleanup is not rebuilt every time. Plan 9.9 asks that logic a browser could run be
framework-free, that Apex own enforcement, and that configuration be documented JSON.

## Decision

1. **One new step, `digits`.** Parameters `pattern` (one `#` per digit, other characters
   literal, at most 30 characters and 15 digits) and `country` (a code of at most 3 digits
   dropped when it makes the digits fit). It keeps the digits, drops the country code, keeps an
   extension (`x`, `ext`, `ext.`, `extension`) and writes ` x12` after the number, and leaves a
   value that does not fit unchanged. Still a closed operation with bounded literal parameters:
   no expression, no pattern from user text. The one regular expression, which finds the
   extension, is fixed in code. A document that may use it is version 3.
2. **Two implementations, one fixture.** `DataTransform.formatDigits` (Apex, the server run) and
   `transformFormat.js` (a framework-free LWC bundle, no `lightning/*` or `@salesforce/*`
   imports) are both tested against `staticresources/TransformFormatFixture.json`. The fixture
   is a static resource so the Apex test can read it and Jest reads the same file.
3. **Phone preset.** Super Transform offers Format Phone Number on phone and short text fields:
   one `digits` step with `(###) ###-####` and country `1`, shown and editable as Change With
   Steps, like Fix Name Capitals.
4. **Saved step lists in a new object.** `Saved_Transform__c` (Name, Object Name, Definition
   JSON) holds a version 1 document of object, filter and changes. Public read and write, so a
   list is org-wide; `BarnCRM_Bulk_Update` is granted create, edit and delete. Loading only
   fills the page in; every check and the run still happen as the person.

## Consequences

- Import mapping gains Format digits too (the step editor is shared); a phone column can be
  tidied on load.
- A reader that predates version 3 skips a `digits` step, as ADR-0112 already provides.
- Anyone with Bulk Update can delete anyone's list. A list is a convenience that holds no
  records, and nothing else reads it.
- The country-code rule is exact (drop only when the length fits), so a long international
  number is left unchanged rather than guessed at.

## Alternatives considered

- **A regular expression the administrator types:** refused as ADR-0081 refused one.
- **Reusing `Saved_Query__c`:** a Find query is private or shared by person (ADR-0076) and
  holds no changes; org-wide step lists need a different sharing model and document.
- **A custom setting or custom metadata for lists:** a person could not save one from the page
  without Setup access, and a record per list is simpler to rename and delete.
- **Formatting only in Apex:** the preview is the server's, so Apex alone would work, but the
  browser module keeps plan 9.9 and gives the phone preset a tested home for a later inline
  preview.
