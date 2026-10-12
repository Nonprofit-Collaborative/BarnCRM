# ADR-NEXT: Receipt letters are edited as rich text, and the package prints the letterhead

**Status:** Accepted
**Date:** 2026-10-12
**Source:** UI/UX review item 9 (approved by the product owner "as recommended"); plan Section
2.3 (no setting requires markup or an API name) and Section 4.14 (every string is a label);
refines ADR-0016 and the R-RC13 rule in the canonical model

## Context

The Receipts page edited a receipt letter as raw HTML in a plain text box. The shipped letters
start with `<div class="letterhead">`, an `<h1>` holding `{{OrganizationName}}` and a paragraph
holding `{{OrganizationAddress}}`, so the first thing Maria sees is markup she has to keep intact.
There was no way to see the result before issuing a real, numbered receipt.

The renderer (ADR-0016) merges tokens into the stored HTML and prints a branding block above the
letter. Under R-RC13 it printed the organization's name and address in that block only when the
template did not contain `{{OrganizationName}}`. That test misfires on a letter that merely
mentions the organization in a sentence ("Thank you for supporting {{OrganizationName}}"): the
document then has no letterhead.

## Decision

1. **The letter is edited with `lightning-input-rich-text`**, limited to the formats the PDF
   rendering service prints (bold, italic, underline, lists, indent, alignment, links, headings;
   no images, fonts, sizes or colors). The stored format does not change: `Body__c` is still HTML
   with `{{Token}}` placeholders, and the renderer reads it exactly as before. No conversion is
   needed at save, because the editor's output is HTML.
2. **The letterhead is code, not template.** The package always prints the organization's legal
   name and address above the letter, under the logo. The template no longer carries them, and
   the editor never shows them.
3. **Compatibility with letters saved before this change.** A stored body that still contains
   the old `class="letterhead"` block is rendered exactly as before: the package prints the logo
   only, and the letter's own letterhead prints the name. When such a letter is opened in the
   editor, the old block is removed from what the editor shows, so the next save stores the
   letter without it and the package's letterhead takes over. The shipped defaults in
   `Receipt_Template_Default__mdt` no longer contain the block.
4. **A gift-lines token on a line of its own** (`<p>{{GiftLines}}</p>`, which is what the editor
   produces) is replaced by the table itself, not a table inside a paragraph.
5. **A preview renders the draft letter for a sample gift** through the same
   `ReceiptContentBuilder` path that issues a receipt, with a sample donor name and number from
   labels. It writes nothing, consumes no receipt number and creates no file. The page shows the
   HTML in `lightning-formatted-rich-text`; it is not a PDF.
6. **The gift page links to the stored PDF** with the standard file preview
   (`standard__namedPage`, `filePreview`), so no download URL is built by hand.

## Alternatives considered

- **Keep the textarea and add a help note.** Rejected: plan 2.3 says no setting requires
  knowing markup, and the review found Maria cannot tell which parts are safe to change.
- **Store a structured letter (paragraph fields) and build the HTML in code.** Rejected: a new
  data shape, a migration for every org's saved letters, and a second renderer path, for no gain
  over rich text that already produces HTML.
- **Keep the `{{OrganizationName}}` test for the letterhead.** Rejected: it is the misfire
  described above, and with the letterhead out of the editor there is nothing for it to detect.
- **Render a real PDF for the preview with `Blob.toPdf`.** Rejected for now: it needs a file or
  a download path for an unsaved document, and the HTML preview shows the wording, which is what
  is being edited. The PDF layout is checked by issuing a test receipt, as the admin guide says.

## Consequences

- A letter that an organization edited by hand to carry its own header without the
  `class="letterhead"` marker now gets the package's letterhead as well, so the name prints
  twice until the duplicate is deleted in the editor. The admin guide says so.
- The rich text editor drops `class` attributes. The shipped letters used one
  (`class="reference"`) that no style rule reads, so nothing visible changes.
- The preview does not show the PDF page margins, and whether the logo shows in the preview
  depends on the logo delivery route (ADR-0016's open spike). The admin guide says to issue a
  test receipt to check the printed layout.
- R-RC13 in the canonical model now states the rule in point 2 and the compatibility in point 3.
