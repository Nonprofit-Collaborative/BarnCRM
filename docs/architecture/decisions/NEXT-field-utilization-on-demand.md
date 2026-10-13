# ADR-NEXT: Field utilization runs on demand in Org Optimizer

**Status:** Accepted (owner decision, Brandon, 2026-10-13)
**Date:** 2026-10-13
**Source:** owner decision 2026-10-13 ("Field utilization doesn't need to be a nightly job but
can be run on demand on a field utilization tab where the object can be selected, then the
fields for that object and their utilization are displayed"; make it efficient and simple
without removing functionality). Supersedes in part ADR-0086
`0086-field-utilization-ships-in-core.md` (decisions 2 in part, 3 in part, 5, 6 and 7).

## Context

ADR-0086 built field utilization as a weekly batch over a saved list of objects: a scheduler,
a batch class, three settings keys (the tracked list, capped at 255 characters, and two run
stamps), a 13-month retention pass, a console panel, and a Health Check registration. The owner
wants the question answered when it is asked, one object at a time, on its own tab. A weekly
job answers a question nobody asked that week, and its machinery (schedule, stamps, retention,
Health Check entry, the 255-character list) is most of the feature's code.

Platform facts that shape the answer: a synchronous Apex transaction may run 100 queries and
read 50,000 query rows; a `COUNT(field)` query costs one query row per group (ADR-0086); a
Lightning server call should return in well under two minutes.

## Decision

1. **A Field utilization section of Org Optimizer.** The `fieldUtilization` component is a
   section of Org Optimizer and has no app page or tab of its own (owner decision, 2026-10-13:
   "Field utilization lives only inside Org Optimizer"). The person picks an object;
   the page lists every countable field of it with its label, API name, record type, filled
   count, record count and percent, sortable. The console panel is removed: the feature has no
   setting left to live in the console.
2. **Objects come from describe, as Find offers them.** The picker lists every object the person
   can query, by the same rule Find uses (`FindController.isOffered`: accessible, queryable, not
   a custom setting, not deprecated, not a share, history, feed, change event, metadata, event,
   external or big object), minus the snapshot object itself. Fields come from that object's
   describe. ADR-0086 decisions 3 (describe only, the countable field rule) and 4 (one
   `COUNT(field)` query per field grouped by record type; non-filterable or refused fields
   sampled on the 200 most recently modified records and marked Sampled) stand unchanged.
3. **Counted synchronously, in chunks the page requests.** The page asks for the object's plan
   (record totals by record type and the field list) in one call, then asks for counts 40 fields
   per call (10 when the object holds more than 100,000 records, so one call stays short),
   filling the table as each call returns, with a progress bar. Each call reads the totals again
   (one query) so no client number becomes a denominator. No batch, scheduler or queueable.
4. **The 1,000,000-record guard stays.** The plan call counts the object first; above the limit
   the page says so and counts nothing, and every count call refuses it too.
5. **User mode stays** (ADR-0086 decision 2): every count, read and write runs as the person on
   the page. The run stamps and their system-mode writer go with the schedule.
6. **Trends without a schedule.** A "Save these counts" button writes the counts on the page as
   `Field_Utilization_Snapshot__c` rows, the same shape as before, so standard reports keep
   working. The server checks every saved row's object, field and record type against describe
   and keeps a filled count within its record count. The page shows the latest saved count for
   the object next to the current one, with the change in points.
7. **No retention job.** Rows are written only when someone chooses to save, so growth is
   small. Old rows are cleared with the product's own Bulk delete (a Find query on Field
   Utilization Snapshots by Taken At) or any standard delete; the admin guide says so.
8. **Permissions unchanged in substance.** BarnCRM Admin carries the controller and the
   snapshot object (Read, Create, Delete, View All, Modify All). Every controller method requires
   `Manage_BarnCRM_Settings`, which BarnCRM Admin carries.

## Alternatives considered

- **Keep the weekly job alongside the tab.** Rejected by the owner: the schedule, stamps,
  retention and Health Check entry cost more than the trend they automate.
- **A queueable per object.** Rejected: the page would have to poll, and an on-demand count of
  one object fits synchronous limits once chunked.
- **One call for every field.** Rejected: 100 queries is the synchronous ceiling, and objects
  with more than about 90 countable fields (Account and Contact in most orgs) would hit it.
- **Save by recounting on the server.** Rejected: it doubles the queries for no gain; the saving
  person is an administrator who could create the rows by hand, and the server validates them.

## Consequences

- Removed from Core: `FieldUtilizationBatch`, `FieldUtilizationScheduler` and their tests, the
  settings keys `Field_Utilization_Objects__c`, `Field_Utilization_Last_Run__c` and
  `Field_Utilization_Last_Run_Summary__c`, the `Field_Utilization` setting definition, the
  `NightlyJobs` registration, and the labels only the old page used. An org upgraded from a
  build with the weekly job needs those components removed by a destructive deploy, and its
  scheduled job "BarnCRM Field Utilization" aborted.
- The component is reached only from Org Optimizer; no tab or app page is added.
- `FindController.isOffered` becomes public so both pages offer objects by one rule.
- An object with many fields takes several calls; a 300-field object is eight calls.
- ADR-0086's revisit of chunk size after the 1M-gift scale test now applies to the 40 and 10
  field chunks.
