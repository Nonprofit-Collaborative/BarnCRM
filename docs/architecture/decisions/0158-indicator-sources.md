# ADR-0158: Indicator sources: hand entry, a Core Import template, or a Find saved query counted per period in system mode

**Status:** Proposed (built as recommended for release 0.15, L-03; awaits owner confirmation)
**Date:** 2026-11-02
**Source:** plan Section 5.7 (L-03 and its note on proving the computed source), Section 6.0a
release 0.15, Section 9.9 (portability); builds on ADR-0154, ADR-0075 (nightly jobs), ADR-0047
(Find runs as the user), ADR-0080 (one-object import templates).

## Context

L-03 lets an indicator's results come from somewhere other than typing: an import, or a value
worked out from other records (service deliveries, attendance, volunteer hours, gifts), with no
dependency on Programs, Volunteers or Giving. The plan's note records that Core's rollup engine
cannot do this (it needs a lookup from the source record to the indicator period, which no
source object has) and asks to try a standard report first.

## Decision

1. **Three sources per indicator.** `Indicator__c.Source__c`: Manual (the default, as today),
   Import, or Computed. Blank reads as Manual. Only Logic Models Admin may change an indicator's
   source (field-level security on the source fields); Staff and Read Only see it.
2. **Import is a Core Import template, not new code.** Logic Models ships the one-object
   template **Indicator Results** (`Import_Template_Default.Indicator_Results`): Indicator Period,
   Update by record Id, columns Period Id, Target, Result and Notes. The builder's **Download
   Results Sheet** writes those columns (plus the model, part, indicator and dates, which the
   template ignores) for every period whose indicator is not computed, through Core's `c/findCsv`.
   The organization fills in Result and loads the file in Import, with its dry run, results,
   journal and undo, in the user's own access. The install step materializes the template.
3. **Computed is a Find saved query counted per period.** The admin picks a saved query from Find
   (`Source_Query__c`, a lookup to Core's `Saved_Query__c`; it holds the object and filter, so no
   new filter builder or query engine is written), the date field that places a record in a
   period, and what to work out: **Count** of records, **Sum** of a number field, or **Count
   Unique** values of a field (an unduplicated count such as people served). The choice is
   stored as JSON in `Source_Definition__c`:
   `{"version": 1, "dateField": "Delivery_Date__c", "function": "count|sum|unique", "field": null}`.
   It is checked when saved, as the admin: the query must be one they can open and it must
   compile (`QueryCompiler.compile`, the admin's describe), and the date and measured fields must
   resolve (`QueryCompiler.resolve`) to a date or date-time, a number, or a groupable field.
4. **Run in batches, never in the request.** `IndicatorResultsBatch` reads the query's records
   whose date falls between the earliest start and the latest end of the indicator's periods that
   have started (a `QueryLocator`, 2,000 records a chunk, so no query row or heap limit is reached
   however many records match), puts each record in every period whose dates hold it (periods may
   overlap, a year and its quarters), and in its finish writes every started period's Result
   Value, the indicator's Computed At, and Source Status (blank, or the problem in plain words).
   One indicator per batch; the finish starts the next, so a refresh of many indicators is one
   chain. Count Unique keeps the values seen per period and stops with a status message near the
   heap limit rather than writing a wrong number. A period that has not started is left alone.
5. **Refreshed nightly and on demand.** **Refresh Results** in the builder starts the chain for one
   indicator; saving a computed source starts it too. The nightly job **BarnCRM Indicator
   Results** (3:30 AM, `IndicatorResultsScheduler`) refreshes every computed indicator, and is a
   `NamedNightlyJob` returned by `LogicModelsNightlyJobProvider`, which Core's
   `NightlyJobs.PROVIDER_CLASSES` names, so Health Check counts and schedules it.
6. **Access mode: the definition as the admin, the count in system mode.** The query is compiled
   as the person running it (the admin who saves or the user who scheduled the job), so an object
   or field they cannot read is refused. The records are then read in system mode in a
   `without sharing` class, so the result is the organization's figure, not the share of records
   one person can see: under the participant privacy preset (P-08) a staff member's refresh must
   not shrink the count. Only numbers are written, never record details, and only Logic Models
   Admin can define what is counted; this is the same trade Core's rollups make.
7. **Results of a computed indicator are not typed.** The builder shows them read only, and
   `LogicModelService.savePeriod` keeps the stored result for a computed indicator, so a target or
   notes can still be changed without fighting the nightly run.

## Alternatives considered

- **A standard report as the source (the plan's first try).** Rejected: Apex runs a report only
  with the running user's sharing (no organization figure); reports cannot be created or read in
  Apex tests without `SeeAllData`; a report's date filter must be rewritten per period; and a
  report has no portable form for BarnCRM for WordPress, where Find's query document is JSON.
- **Core's rollup engine.** Rejected, as the plan notes: it needs a lookup from each source record
  to the period.
- **One aggregate query per period.** Rejected: each aggregated row counts toward the 50,000 query
  rows of one transaction, so a large organization would fail; the batch has no such ceiling.
- **The definition copied into the indicator instead of a lookup to the saved query.** Rejected:
  the lookup keeps one place to fix a filter, and a deleted query shows as a status message.
- **Counting in user mode.** Rejected: the result would depend on who pressed the button or
  scheduled the job.

## Consequences

- Five fields on `Indicator__c` (Source, Source Query, Source Definition, Source Status, Computed
  At), canonical model Section 29ZF, rules R-IN3 to R-IN6; no new object.
- One more nightly job and one more import template.
- Two small Core changes: `NightlyJobs.PROVIDER_CLASSES` names `LogicModelsNightlyJobProvider`,
  and `QueryCompiler.Compiled` makes `objectName`, `fromWhere` and `binds` namespace accessible so
  the batch can run the compiled query. The definition JSON also keeps the date and field labels
  for display.
- Editing or deleting the saved query in Find changes or stops the indicator; the builder names
  the query on the indicator and shows the status.
