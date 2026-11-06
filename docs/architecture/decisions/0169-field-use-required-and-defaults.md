# ADR-0169: Field Use shows required, default value and at default

**Status:** Proposed
**Date:** 2026-11-05
**Source:** owner QA request 2026-11-05 ("On field use (or somewhere useful), also include if a
field has a default value, percentage of fields with that default value, and if a field is
required"). Supersedes in part ADR-0086 `0086-field-utilization-ships-in-core.md` (decision 3:
the checkbox and non-nillable exclusions).

## Context

ADR-0086 left checkboxes and non-nillable fields out of the count because a checkbox is never
empty and a required field is always filled, so their fill rate says nothing. The owner now
wants each field's required flag, its default value, and the share of records still holding
that default. With required fields left out, Required would never be true on any row; with
checkboxes left out, the most common defaulted field (a checkbox) would have no At Default.

A synchronous call may run 100 queries; a 40-field chunk already spends up to two per field
(count, then a sample when the count is refused). `Field_Utilization_Snapshot__c` has no field
that could carry more values per row without adding fields.

## Decision

1. Required fields and checkboxes are counted (canonical model R-FU2). A checkbox is filled on
   every record and needs no count query.
2. Required and Default Value come from describe only (R-FU13): required means createable, not
   nillable and not defaulted on create; the default is the picklist default, the checkbox
   default, a literal, or a default formula that is only a quoted text or only a number. Any
   other default formula shows as Formula. Layouts and validation rules are not read.
3. At Default is one more `COUNT(Id)` query per field in user mode, grouped by record type like
   the filled count, with the default passed as a bind (R-FU14). It is skipped for formula
   defaults, percent, unfilterable and encrypted fields, sampled rows, and when the call has
   fewer than two queries left. A field costs at most two queries, so a 40-field chunk stays
   under the limit.
4. The new values are not saved in snapshots: no field is added to
   `Field_Utilization_Snapshot__c`.

## Alternatives considered

- **Show the values only on rows already counted.** Required would never be true, and
  checkboxes would have no At Default; it does not meet the request.
- **Show them in the Data Dictionary instead.** It already shows Required, but it has no
  per-record-type counts to hang At Default on, and Field Use is where the owner asked.
- **Store the new values in snapshots.** Needs new fields on the snapshot object for values
  that are either describe-based (re-read on every count) or cheap to recount.
- **Compute At Default from a sample.** Cheaper on huge objects, but inconsistent with Filled,
  which is an exact count.

## Consequences

- The table gains rows for required fields (always 100% filled) and checkboxes. Mitigation: the
  table sorts by any column, and the admin guide says to read At Default for checkboxes.
- A saved snapshot's average fill rate now includes those rows, so a snapshot saved after this
  change averages higher than one saved before it on the same object. The per-field Change
  column is unaffected.
- Percent defaults are shown but not compared, because their scale in a default formula is not
  reliable to compare.
