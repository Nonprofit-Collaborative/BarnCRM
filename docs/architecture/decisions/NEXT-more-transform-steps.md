# ADR-NEXT: Six more transform steps, still a closed list with no evaluation

**Status:** Proposed (builder decision)
**Date:** 2026-10-13
**Source:** data tools parity report rank 6 (owner decision 2026-10-13: build ranks 1 to 17).
Extends `0081-data-transform-document.md` (ADR-0081) decision 1, whose closed set of steps this
widens. Amends canonical model R-IT15 and R-BU7.

## Context

ADR-0081 gave import columns and bulk update a closed list of eight steps. The files nonprofits
load still need a spreadsheet pass for the rest of what dataimporter.io's formulas are used for:
translating codes (`CA` to `California`, `M` to `Monthly`), writing a value when a cell says
something (`N/A` to empty), keeping the domain of an email or the last word of a name, keeping
the first five characters of a postal code, and dates relative to another date or to today.
ADR-0081 refused a formula language and conditions on other columns; that refusal stands.

## Decision

1. **Seven new operations join the closed set** (six features; first and last N are two):
   `map` (a table of at most 100 from and to pairs, an optional value for anything else, match
   capitals), `ifThen` (when the value equals, contains or is empty, write a value, optionally
   another one otherwise), `part` (split on a literal separator and keep part N, from the
   start or the end), `first` and `last` (N characters), `shiftDate` (plus or minus days or
   months on a date written `YYYY-MM-DD`) and `today` (today's date, always or only when
   empty). Every parameter is a bounded literal.
2. **Still nothing is evaluated.** Comparisons are literal text, case folded unless match
   capitals is ticked, on the trimmed value. `part` splits by `indexOf`, never a pattern.
   `ifThen` tests only the value so far, never another column, so ADR-0081's refusal of
   conditions on other columns is unchanged. Every step stays linear in the value's length,
   and a `map` lookup is one map read per value.
3. **The document version becomes 2.** A mapping document and a bulk update definition
   written from now on carry `"version": 2`, meaning its steps may use the new operations. A
   reader that predates them skips an operation it does not know, as R-IT15 already reads a
   stored step that fails the check, so an older document still reads and a newer one never
   fails a load: it only loses the unknown step, which the version tells a reader to expect.
4. **Dates stay text.** `shiftDate` reads the first three numbers year first (so a stored
   date with a time, or the output of Read as a date, both read) and writes `YYYY-MM-DD`; a
   value that is not a date, or a result outside the years 1700 to 4000, is left unchanged.
   `today` is the running user's date in their time zone, taken once per value.

## Consequences

- Most dataimporter.io formula uses (MAP, IF, SPLIT, LEFT, RIGHT, timedelta, TODAY) are now a
  step in the mapping, previewed before and after like the others.
- Security review still reads a closed list: no evaluator, no pattern from user text.
- A dry run and its commit on different days give different `today` values; the dry run shows
  the day it ran.
- Bulk update gains the same steps with no wiring: it already checks and applies the engine's
  steps. A date and time field refuses a `shiftDate` or `today`
  result (a date with no time) for each record, as R-BU7 refuses any result a field cannot
  take; these steps are for date fields.

## Alternatives considered

- **Nested IF, AND, OR:** a condition language in disguise; refused as ADR-0081 refused one.
- **Conditions on other columns:** refused by ADR-0081; a two-column rule is a new ADR.
- **A regular expression for Keep part:** refused for the reason ADR-0081 gives for replace.
- **Today as a value for every row:** values for every row are literal text; a step keeps the
  dynamic value in the one place that already changes values per row.
