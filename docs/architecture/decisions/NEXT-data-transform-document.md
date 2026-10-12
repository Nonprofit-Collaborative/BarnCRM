# ADR-NEXT: Column changes as a declarative transform document, and import matching through the org's duplicate rules

**Status:** Accepted (builder decision)
**Date:** 2026-10-12
**Source:** plan Section 4.9 ("Matching", "Bulk update", "Queries are built from a document,
never from text") and feature C-37 (part 1: transforms and dedupe on import; bulk delete is
out of scope). Builds on ADR-0047 (D-13), `NEXT-import-matching-per-entity-and-per-file-values.md`
and `NEXT-import-load-one-object.md`. Adds canonical model R-IT15 and R-IT16 and amends R-IT1.

## Context

Files from other systems need tidying before they load: names in capitals, codes where the org
keeps words, dates written day first, a name split over columns. Today Maria fixes these in
Excel, every month, for every file. dataimporter.io and Jetstream offer formulas for this; the
plan puts "formulas and find-and-replace in mappings and bulk update" in C-37.

A formula language is the obvious answer and the wrong one here. Anything that evaluates text
the administrator typed (a formula parser, a regular expression, dynamic Apex) is a new
enforcement surface for security review, a source of runaway CPU on a 250,000-row file, and
something Maria has to learn. The plan already rules out typed SOQL for the same reasons and
builds queries from a document (Section 4.9).

The plan also lists "matching through the org's own duplicate rules" for C-37. An org that
has tuned its duplicate rules (fuzzy names, phone, address) expects an import to respect them,
and Core already calls the platform's matcher for its duplicate scan (C-20, ADR-0050).

## Decision

1. **Column changes are a short list of named steps, stored on the column.** The R-IT1 mapping
   document's column gains `transforms`: at most 10 steps, each one of a closed set (`trim`,
   `upper`, `lower`, `proper`, `replace`, `ifBlank`, `append`, `date`), with bounded literal
   parameters. No new field: the document is already the template's mapping and already travels
   as one JSON file in `data/import-templates/`. Steps run in order on the cell's text, before
   values for every row, and before matching, so matching sees the tidied value.
2. **Nothing is evaluated.** `replace` treats its text as literal (quoted before any pattern
   call); `date` reads three numbers in an order chosen from three; `append` reads other cells
   of the same row by column name. No step reads a record, calls code, or accepts a pattern or
   an expression. Each step is linear in the length of the value, so a file's cost grows with
   its size and nothing else.
3. **Checked on save, forgiving on read.** Saving a mapping with an unknown step, a missing or
   oversized parameter, or more than 10 steps is refused with the column named. A stored step
   that fails the check (a hand-edited template file) is skipped on read, as R-IT1 already
   reads a broken document as empty rather than failing an import.
4. **One engine in Core, shared with bulk update.** `DataTransform` takes the steps, the value
   and the other values of the row (or record) by name, and returns the new value. It knows
   nothing of imports. Bulk update (C-35) adopts it as a fourth assignment kind ("change the
   value with steps"), where `append` names fields of the same record; that wiring lands with or
   after C-35, not on this branch.
5. **Duplicate rules are a second look, not a fourth rule.** A people template gains Use
   Duplicate Rules. When ticked, a person or organization the template's rule found nobody for
   (and that no record ID names and no earlier row of the pass is creating) is passed, as an
   unsaved record, to `Datacloud.FindDuplicates`, 50 a call. The rule's key still decides
   identity inside the file, so two rows for one new person still create one person.
6. **The platform matches; the user's access decides.** The matcher's answers are filtered to
   the entity's object, then read again in user mode with the entity's record type
   restriction, so a record the user cannot see, a household or a person account is never taken
   for an organization, and nothing outside the user's sharing is matched. Several records
   follow Several Matches (R-IT9), reject by default. Each row matched this way is ticked
   Matched By Duplicate Rule and counted in the run log, so the dry run lists them.
7. **No active rule degrades to the template's rule.** When the user can see no active duplicate
   rule for the object, or the matcher raises, the entity is matched by the template's rule
   alone and the run log says so once; nothing is rejected for it, and the wizard warns before
   the dry run.

## Consequences

- Maria tidies a recurring file once, in the mapping, and sees each change before and after in
  the wizard and in the dry run. There is still no formula language: arithmetic, conditions on
  other columns and lookups to records are not offered. A request for one is a new ADR.
- The steps are data. Security review has a closed list of operations to read, no evaluator, and
  no pattern compiled from user text.
- Duplicate rule matching is looser than the template's rule by design, so a wrong match is
  possible; the dry run's ticked rows and the reject-by-default several-matches policy are the
  guard. A dry run cannot ask duplicate rules about people the same file creates (they do not
  exist yet), so a commit can match a few more rows than its dry run; the admin guide says so.
- The platform matcher's per-transaction cost is not documented as a governor limit. A 200-row
  chunk with two people and an organization makes at most 12 calls; the org run confirms this
  fits, and the rows per chunk setting is the lever if it does not.
- Bulk update gains formulas and find-and-replace without a second engine, once C-35 lands.

## Alternatives considered

- **A formula language** (parsed and evaluated in Apex): refused for the reasons above; it is
  the one thing in this feature a security reviewer would ask most about.
- **Regular expressions in find and replace:** refused; a pattern an admin types can run in
  time far beyond its length, and Maria does not write them.
- **Transforms in the browser only:** the browser already parses the file, but the commit runs
  in Batch Apex from staged raw values, and the dry run must show what the commit will write. A
  browser-only change would also be lost for a file staged by a future scheduled import (C-38).
- **Duplicate rules as a fourth matching rule replacing the key:** two rows of one new person in
  a file would then create two people, because nothing would tie them together before either
  exists.
- **Duplicate rules first, then the template's rule:** costs a platform call for every row,
  including the ones an exact key already settles, and lets a loose rule overrule an exact one.
