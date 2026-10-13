# ADR-NEXT: Import row rules: skip rows, one row per key, and empty cells that clear

**Status:** Proposed (builder decision)
**Date:** 2026-10-13
**Source:** data tools parity report ranks 8 and 9 (owner decision 2026-10-13: build ranks 1 to
17). Amends canonical model R-IT1 and adds R-IT17 and R-IT18. Related: `0080-import-load-one-object.md`
(ADR-0080), `0081-data-transform-document.md` (ADR-0081).

## Context

Partner and event exports carry test rows, cancelled lines and repeats, which today either fail
one by one or load twice. Loading back an export corrected in Excel cannot blank a value, because
an empty cell never clears a field; a second bulk update is needed. dataimporter.io offers a row
filter, source dedupe and a "replace null values" option.

## Decision

1. **Two rules on the mapping decide which rows load**, stored in the R-IT1 document:
   `skipRows` (at most 5 rules of a column, a test `equals`, `contains` or `blank`, and literal
   text) and `uniqueBy` (at most 5 column names). They read the cells as uploaded, trimmed and
   ignoring capitals; nothing is evaluated, as ADR-0081 requires.
2. **They are applied when the file is staged, not in each pass.** A skipped row is staged with
   Status Skipped and its reason, and the processor's query leaves Skipped rows out, so the dry
   run and the commit see the same rows and count them the same. Skipped is not Rejected: the
   run log counts it, View rows lists it, and the rejected rows file does not.
3. **Keys travel as digests on the row.** A row's key cells are kept as a 64-bit digest in the
   new `Import_Row__c.Row_Key__c` (indexed, in no permission set, written in system mode as
   ADR-0021 allows for staging bookkeeping), so a later page finds an earlier row with one
   indexed query and the heap does not grow with the file.
4. **An empty cell clears a field only where the column says so** (`blankClears`, default off),
   only for a one-object Update or Upsert of a record that exists, after values for every row
   have filled blanks. A required field or a checkbox is never cleared; the run log says so.
   The clear is an ordinary change: compared, journaled with the value before, and put back by
   undo. The dry run counts what would be cleared. People imports never clear from a blank.

## Consequences

- A test row or a repeat is handled in the mapping once, for every later file of the kind.
- Rules apply to the cells as uploaded, before column changes; a rule cannot see a changed
  value. Changing a rule needs the file uploaded again, because staging decided the rows.
- Clearing is reachable only by a deliberate tick per column, previewed by count and undoable.

## Alternatives considered

- **Applying the rules in each pass:** the dedupe would need every earlier key in the batch's
  state (heap grows with the file) or a query per chunk on the raw JSON (not possible).
- **Deciding in the browser:** a future scheduled import (C-38) has no browser; staging is the
  one place both paths pass through.
- **Blank clears for people imports:** a people row is several records and a household; an
  empty cell clearing a household member's field is too easy to do by accident.
