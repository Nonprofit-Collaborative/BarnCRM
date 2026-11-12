# ADR-NEXT: Files import loads a zip with a manifest into Files, in the browser

**Status:** Proposed (build agent, 2026-11-11; for the integrator and Brandon)
**Date:** 2026-11-11
**Source:** Plan C-70 (release 1.17, D-157: "Import files and attachments: a zip with a manifest
loaded into Files linked to records, with dry run and undo"). Reverses D-50's "Not approved: ...
files import". Builds on ADR-0049 (the workbook is read in the browser without SheetJS) and the
import journal (Section 17A).

## Context

Orgs moving from another system bring documents: signed forms, grant letters, photos. Salesforce's
own tools load files only through the Data Loader or the API. BarnCRM runs in the org with no call
to Salesforce's APIs (D-13), and a Lightning session cannot call the REST API. The import wizard
already reads zips (an .xlsx file is one) in the browser.

## Decision

1. **D-50 amended.** Files import is approved (D-157). Seeding templates stay not approved.
2. **A zip with `manifest.csv` at its root.** One row per file: `File` (its path in the zip),
   `Record Id` (the record it is linked to), and optional `Title` and `Description`. Record Ids
   come from a Find export or a results file. Alternative: matching by a field such as an
   external key (more columns and a query per object); left for later.
3. **Read in the browser.** The zip reader is moved out of the workbook reader into its own
   framework-free module (`c/zipReader`), and the CSV parser into `c/csvParser`, so both the
   import wizard and the files import use one copy.
4. **Sent in groups.** Apex receives at most about 4 MB per call, so a file may be at most 2.5 MB
   and the page sends files in groups of at most 3 MB or 20 files. Each file is a `ContentVersion`
   saved as the person with `FirstPublishLocationId` set to its record, so the record shows it in
   Files and the person owns it.
5. **Dry run first.** The dry run checks every row in the browser (file in the zip, size, Id
   shape) and on the server (the record exists and the person can see it) and loads nothing.
   A job holds at most 2,000 files.
6. **A data job with a journal and undo.** `Import_Batch__c` Operation gains `Files`. Each group
   writes one journal page (R-IJ1) with a Created entry per file (`ContentDocument`) and a Failed
   entry per refused row. Undo, within the import undo window, deletes the documents the journal
   lists, as the person, except one that has gained a newer version since, which is kept and
   counted. Undo is synchronous: 2,000 documents fit one transaction.

## Consequences

- No new object, field or permission set: one picklist value, two browser modules.
- Files over 2.5 MB are refused with the reason; they can be added by hand.
- A page closed in the middle leaves the job Running with what was sent; it can still be undone.
