# ADR-0129: Volunteer hour letters and certificates have their own small generator, not Giving's receipts engine

**Status:** Accepted (owner decision, Brandon, 2026-10-17, decision D2 of the v0.8 Volunteers plan)
**Date:** 2026-10-17
**Source:** plan Section 6 feature V-08 ("hour letters and certificates via the receipts
engine"), which this decision changes; canonical model Section 29U; builds on ADR-0127 (the Volunteers module), ADR-0016 (PDFs
through the Visualforce PDF rendering service, called from Apex) and ADR-0034 (a file link is
an access control list)

## Context

Volunteers want a letter stating their hours, for school service requirements, court ordered
service or employer matching, and organizations like to hand out certificates. The plan said
these come "via the receipts engine". That engine lives in Giving: `Receipt_Template__c`,
`ReceiptRenderer` and `BlobToPdfReceiptRenderer`, receipt numbering, immutability (ADR-0010) and
tax wording (R-RC7).

Volunteers depends on Core and the Rollup Builder only (ADR-0127), and an organization may
run Volunteers without Giving. A letter about hours is not a receipt: it has no number, no tax
sentence, no void and reissue, and nothing in Giving's lock rules applies to it. What it shares
with a receipt is one technique: compose HTML and call `Blob.toPdf()`, which renders through
the Visualforce PDF service as plain Apex (ADR-0016). `BlobToPdfReceiptRenderer` is about
thirty lines.

## Decision

1. **Volunteers ships its own generator**, with no reference to Giving: `VolunteerLetterService`
   merges a template, `VolunteerLetterRenderer` calls `Blob.toPdf()` on the HTML (the
   `BlobToPdfReceiptRenderer` technique, restated, not called), and `VolunteerLetterBatch`
   produces letters for a list of people, ten per transaction.
2. **Templates** are `Volunteer_Letter_Template__c` records of Type Hours letter or Certificate,
   one active per type, with a closed set of HTML escaped tokens (R-VL2). The shipped wording is
   `Volunteer_Letter_Template_Default__mdt`, materialized by `VolunteersPostInstall` at install and
   upgrade without touching an existing template (plan Section 4.8 storage strategy).
3. **A letter counts approved hours only**, in a period the coordinator chooses, read in the
   user's own access. Organization name and address come from Core's settings keys, never from
   Giving's.
4. **Output is a PDF file linked to the person** and to nothing else (ADR-0034). No letter
   record, number or log: the file is the record. Generating needs `Manage_Volunteers`.

## Alternatives considered

- **Use Giving's receipts engine as the plan said.** Makes Volunteers require Giving, or
  requires moving the renderer seam into Core, which then names a nonprofit capability (Core's
  neutral naming rule). Receipt rules (numbering, lock, tax text) would need switches to turn
  them off for letters. Rejected for a thirty line technique.
- **Move a generic PDF renderer into Core.** Possible later if a third module needs PDFs; two
  users of a thirty line class do not justify a Core seam now.
- **Print from the browser (LWC).** No stored file for a letter run over a list, and ADR-0016
  rejected it for the same reason.

## Consequences

- The plan's V-08 wording "via the receipts engine" is replaced by this decision; the plan and
  the feature catalog say "own letter generator".
- ADR-0016's open spike (whether `Blob.toPdf()` is metered inside a batch) applies here too. If it
  fails, the fallback is the same as Giving's: a Visualforce `renderAs="pdf"` page behind
  `VolunteerLetterRenderer`, changing nothing else.
- No logo in v0.8: the logo setting belongs to Giving. A letter template may still include an
  image the renderer can reach, under ADR-0016's image rules.
- Two copies of the technique to maintain; if they diverge in a bug fix, both are fixed.
