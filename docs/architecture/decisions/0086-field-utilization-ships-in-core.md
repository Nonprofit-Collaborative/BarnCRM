# ADR-0086: Field utilization ships in Core, counts in user mode, and keeps weekly snapshots

**Status:** Accepted (builder decision, accepted as recommended under the owner standing instruction, 2026-10-12)
**Superseded in part by ADR-NEXT** `NEXT-field-utilization-on-demand.md` (owner decision,
2026-10-13): the count runs on demand in Org Optimizer. The batch, weekly schedule, tracked list,
run stamps, 13-month retention and Health Check registration (decisions 5, 6 and 7, the tracked
list in 3, the run stamps in 2) are replaced; decisions 1, 3 and 4 otherwise stand.
**Date:** 2026-10-12
**Source:** plan Section 6.1 item 10 (Analytics module, field utilization first; Brandon,
2026-09-23), plan Section 6.2 rule 5, ADR-0003, ADR-0038, ADR-0047

## Context

The plan parks an "Analytics module" whose first feature is field utilization: for each object,
and each record type in use, the share of records with a value in each field, with trends from
saved snapshots, reported through standard reports, with no CRM Analytics dependency, neutral
so both suites get it. Four things had to be settled to build it: whether it is a package, which
mode it counts in, how it stays inside governor limits on a large org, and how much it stores.

Platform facts that shape the answer: a query whose only aggregate is `COUNT()` or
`COUNT(field)` counts as one query row (one per group with `GROUP BY`), so a count of a
million-record object costs one row of the 50,000 limit, while any other aggregate counts every
row. Long text, rich text and encrypted fields cannot be filtered or counted that way. A
Lightning session cannot call the org's own APIs without a self-callout (ADR-0047).

## Decision

1. **It is part of Core, not a new package.** It adds one object, three settings keys and one
   console page. Plan Section 6.2 rule 5 justifies a package only when its schema would clutter
   an org that does not need it; one admin-only object does not, and a package costs every org
   an install step for a page both suites want. "Analytics module" names the feature area. A
   later analytics feature large enough to clutter Core gets its own ADR and package then.
2. **It counts in user mode.** Every query and every write is `AccessLevel.USER_MODE`. The run
   sees what the person who scheduled it, or pressed Count now, can see; the page says so. No
   ADR-0021 exception is needed. The two run stamps on `BarnCRM_Settings__c` go through
   `OrgSettingsSystemWriter`, as every Core job's stamps do.
3. **Objects and fields come from describe only**, never from text a person typed: the tracked
   list is validated against the global describe on save and again at run time. Counted fields
   are those the runner can read and edit, excluding formula, auto number, checkbox,
   non-nillable and compound fields.
4. **One query per field.** `SELECT RecordTypeId, COUNT(field) FROM object GROUP BY
   RecordTypeId` (no grouping when the object has no record types), one query row per record
   type. A field that cannot be filtered, or whose count query is refused, is counted on the 200
   most recently modified records instead and its rows are marked Sampled.
5. **A batch, one field per item, 25 items per chunk.** The plan step reads one grouped total
   per object; objects over 1,000,000 records are skipped and named in the run summary, so one
   run never scans for hours. Twenty-five count queries per chunk leave room under the 200
   asynchronous query limit and keep a chunk's wall time short on large objects.
6. **Weekly, not nightly, with 13 months kept.** Fill rates move slowly and each run writes one
   row per field and record type. The job runs Sundays at 04:00, outside the nightly window
   (00:30 to 03:00), and each run's finish deletes rows older than 13 months. The Admin
   permission set gets View All and Modify All on the snapshot object so that a user-mode
   delete reaches rows another administrator's run created.
7. **Scheduled from the console, registered with Health Check.** The schedule, stop and run now
   buttons follow ADR-0038. Once at least one object is chosen, the job is listed by
   `NightlyJobs` so the "Schedule all nightly jobs" fix covers it; with nothing chosen it is
   not listed, because an org that chose nothing has not missed a run.

## Alternatives considered

- **A separate Analytics package.** Rejected for now: an install step and a dependency for one
  object and one page, against plan Section 6.2 rule 5.
- **System mode counts.** Rejected: user mode answers the question for an administrator who can
  see everything, and a system-mode reader of every field on every object would be the widest
  read in the product, for a page that does not need it.
- **One snapshot row per object and run with the counts in a JSON field.** Rejected: far less
  storage, but no standard report could chart one field, which is the plan's reporting promise.
- **Nightly runs, kept forever.** Rejected: about 15,000 rows a year for two objects at weekly
  cadence becomes over 100,000 nightly, for no better answer.
- **"Where is this field used".** Not built: it needs the Tooling or Metadata API, which waits
  for the same decision as connections to other systems (plan Section 6.1 item 10).

## Consequences

- Core gains `Field_Utilization_Snapshot__c` (canonical model Section 29F) and three settings
  keys. The tracked list fits 255 characters, which limits an org to roughly eight to twelve
  objects at a time; the page says so when a choice does not fit.
- An org without a record-wide reader gets partial counts, stated on the page and in the guide.
- Registration with Health Check depends on `NightlyJobs` (ADR-0086,
  health-check-schedules-every-nightly-job) and is added when both are on main.
- Revisit the size limit and the chunk size after the 1M-gift scale test (plan v0.11).
