# ADR-NEXT: Backup Sets are saved Find queries exported to Files on demand

**Status:** Proposed (build agent, 2026-11-11; for the integrator and Brandon)
**Date:** 2026-11-11
**Source:** Plan C-66 (release 1.17, D-157: "Backup Sets: saved Find queries run on demand as CSV
files in the admin's Files, with a run list and restore through Load by Id; reuses the C-67 file
format; scheduled runs wait for C-38"). Amends D-13 and ADR-0047 ("Never built: ... dataimporter.io's
org-to-org migration and backup"). Builds on ADR-0115 (Find export to Files) and R-BD9 (Archive by
Query's file format).

## Context

D-13 kept backup out of BarnCRM: Salesforce's weekly export and third-party backup services cover
it. D-157 approved a narrow kind of backup: an administrator keeps a copy of the records a Find
query returns, in a file they own, before a risky change or as a habit, and puts values back from
it. Archive by Query (C-67) already writes such a file: every field the person may read, headed by
field API name, so Load one object maps every column. Find already saves queries.

## Decision

1. **D-13 amended.** "Never built: backup" now reads "never built: org-to-org migration, and
   backup outside the org (a stored copy held by BarnCRM or any third party)". A Backup Set's
   file is written in the org, owned by the person who runs it, and never leaves the org unless
   they download it.
2. **A Backup Set is a saved query.** The query document gains an optional `backup` key,
   `{ "version": 1 }` (R-SQ15), as `grid` marks a saved grid (R-SQ14). No object is added; a set
   is shared, renamed and deleted through the saved query's own rules. Only its owner adds or
   removes the key. Alternative: a Backup Set object with a lookup to the saved query (one more
   object, tab and permission set grants for no new behavior).
3. **A run is a data job.** `Import_Batch__c` Operation gains `Backup`. The run starts the C-67
   archive export (`FindExportBatch` with every readable field and API name headings) without the
   delete, at most Find's export row limit, and its finish records the rows, the parts and the
   first file on the job. The run list is the person's Backup jobs, and Data Jobs lists them with
   every other job. A Backup job has nothing to undo.
4. **Administrators only.** Running needs Manage BarnCRM Settings and Find and Export Records:
   the files hold every readable field of many records, and restoring needs Import, which is
   already an administrator tool.
5. **Restore is Load one object.** Nothing new: a file loaded as **Update by record ID** puts back
   the values of records that still exist; loaded as **Create**, it brings deleted records back as
   new records. The page links to Import and says which to choose.
6. **On demand now, on a schedule with C-38.** C-38 (scheduled imports and connections) is on hold
   (D-39); a scheduled run is added there, not here.

## Consequences

- Files count against the org's file storage; the admin guide says so and suggests deleting old
  runs' files. BarnCRM never deletes them.
- A set larger than the export row limit is saved in part; the run log says so.
- No new object, field or permission set: one picklist value and one document key.
