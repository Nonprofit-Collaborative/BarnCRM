# ADR-NEXT: Typed Find queries are parsed into the query document in the browser

**Status:** Proposed (awaits owner confirmation: the first exception to plan Section 4.10's
rule against SOQL typed by admins)
**Date:** 2026-10-12
**Source:** plan Section 4.9 (Find, "If C-36 allows it later, it is parsed into the same
document in the browser and the server checks it exactly as before, so there is no second
enforcement path; it needs its own ADR"); feature C-36; builds on ADR-0047

## Context

Find (C-34) builds queries only from a document (canonical model R-SQ1) that `QueryCompiler`
compiles with names from the running user's describe, every value bound, in user mode
(R-SQ2). C-36 asks for typed SOQL, child subqueries and "with or without related" filters,
aggregates, Excel export and inline edit. Typed SOQL is the risky one: running text a person
typed would be a second path to the database with its own checks, and a SOQL string can name
any field, any object and any function.

## Decision

1. **A typed query is a way to fill in the builder, not a way to run SOQL.** The browser
   module `findQueryText` parses a subset of SOQL (`SELECT`, `FROM`, `WHERE`, `ORDER BY`,
   `LIMIT`, child subqueries in `SELECT`, and `Id IN (SELECT ...)` or `Id NOT IN` at the top
   level of `WHERE`) into a query document, and Find loads that document into the builder. The
   server receives only the document and checks it through `QueryCompiler` as before. No Apex
   method accepts query text.
2. **The subset is exactly what the document can hold.** Each comparison maps to one R-R2
   operator (`LIKE 'x%'` to starts with, `LIKE '%x%'` to contains, `= null` to is null, date
   literals to the relative operators); AND, OR, NOT and brackets become R-R2 condition logic.
   Mixed AND and OR need brackets, as SOQL itself requires. Anything else (functions,
   `GROUP BY`, other `LIKE` patterns, a second sort) is refused in the browser with the words
   it could not read.
3. **Round trip.** The text box starts with the SOQL Find displays for the current document,
   and the parser reads that rendering back, so a person can switch between the builder and
   text without losing anything.
4. **The other C-36 capabilities extend the document additively** (still version 1): related
   records as semi-joins and anti-joins with their own bound filters, related record columns
   as child subqueries, and a summary as one aggregate query (R-SQ8, R-SQ9). Each is compiled
   only from describe results, like every other part of the document.
5. **Inline edit is a small bulk update.** Edits are checked by `BulkUpdateFields` (R-BU4),
   saved in user mode and journaled as an Update data job, so the Bulk Update tab lists and
   undoes them (R-SQ10). It needs `Bulk_Update_Records` as well as Find's permission.
6. **Excel export is written in the browser by BarnCRM's own module** (`xlsxWriter`), a
   separate module from the import's reader, which keeps ADR-0049's reader to its fixed scope.

## Alternatives considered

- **Accept SOQL text on the server and run it after checks.** Rejected: a second enforcement
  path, and a SOQL parser in Apex would have to be as strict as the compiler or weaker than it.
- **Parse on the server into the document.** Rejected: the server would then accept text, the
  very thing R-SQ2 rules out, for no gain; the document is what the server checks either way.
- **No typed queries.** Viable, and the v1 decision. Rejected for C-36 because a trained admin
  copying a query from another tool is the use the plan names.
- **SheetJS to write workbooks.** Rejected for the reasons ADR-0049 gives.

## Consequences

- Section 4.10's rule holds in substance: no typed text reaches a query. The plan line for
  C-36 and Section 4.10 should cite this ADR once accepted.
- The parser is Jest tested and must track the document: a new operator needs a parser line.
- Server-side export for very large sets remains later.
