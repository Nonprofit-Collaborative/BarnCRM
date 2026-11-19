# ADR-NEXT: Advanced Reporting Module

**Status:** Accepted (owner decision)
**Date:** 2026-11-19
**Source:** D-202 and D-207, batch O item O-02, release 1.29 (Brandon: an optional module for
basic BI, with reports and dashboards that handle cross-object reporting and dashboard
filtering better than Salesforce, reproducing the Board Governance, Giving Overview,
Scholarships and Grants and Volunteers dashboards with viewer-aware data).

## Context

Salesforce reports need a report type for each object path, cannot total related records per
row except through rollup fields, and a dashboard filter reaches only widgets whose source
reports carry the same field. Dashboards run as one running user unless dynamic dashboards are
used, which are limited by edition and count. BarnCRM's modules each ship dashboards that hit
these limits. The suite is also trying to add fewer custom objects (ADR-0227), and Core must run on a Platform-only org (ADR-0013).

## Decision

1. **A separate optional module, `packages/reporting`, depending on Core only**, in both
   editions, shipped as beta (`BarnCRM_Module.Reporting`). Module objects are read by name at
   run time through describe; no module is referenced in code, so it works with any mix of
   modules and offers each one's objects once it is installed.
2. **Every read is the viewer's.** All Apex is `with sharing` and runs queries `WITH
   USER_MODE` with bind variables only. Each object, field, relationship path, grouping and
   function in a definition is allow-listed against the viewer's describe before any SOQL text
   is built; anything else is refused with a message. Two people opening one dashboard see
   totals of only what each can read.
3. **Joins across Core and modules** are expressed three ways, each a single SOQL shape: fields
   through up to two lookups (`Fund__r.Name`); conditions on related records (has, or has no,
   matching children, as a semi or anti join); and up to three related totals per row (an
   aggregate over the children of the listed rows, merged by parent Id).
4. **Dashboard filters bind per widget.** A dashboard has up to four filters (a date range, or a
   record of an object). Each widget binds a filter to one of its own fields, or through
   related records (a gift's fund through its allocations); an unbound widget ignores the
   filter and says so. Record filter choices come from a run of the object's Name list, searched
   and capped at 50.
5. **Saved and shared definitions are Salesforce Files, not a custom object.** A definition is
   JSON (canonical model 29AR) in a ContentVersion with extension `barnreport` or `barndash`,
   owned by its saver. Sharing is a ContentDocumentLink per person, Viewer for View and
   Collaborator for Edit, so the platform enforces who can open one. A public group is expanded
   to its active members whenever the owner saves or shares. Saving, sharing and deleting need
   the custom permission `Reporting_Save` (Staff and Admin sets). Templates are the same JSON in
   a static resource.
6. **Export** is CSV from the browser, of every row of a list report or the groups shown in a
   totals report, offered only to people with Salesforce's Export Reports permission.
7. **Large data volumes.** A totals report is counted first. If the count fits the aggregate
   query limits, one aggregate query totals it; otherwise the browser keyset-pages the records
   in Id order, 5,000 per call, and totals them itself, up to 1,000,000 records, with progress,
   Stop, and a note when totals are partial. Lists show up to 2,000 rows; export pages through
   all of them.
8. **Relation to other items.** Analytics (item 10) is a later module for trends and
   forecasting and can reuse these definitions and the query service. Grid (item 14) is for
   viewing and editing records in a spreadsheet; Advanced Reporting only reads. Find keeps its
   saved queries; both use Core's filter document and filter builder, now exposed for module
   use.
9. **Portable toward WordPress on Pegwork (plan 9.9).** The definition format, filter logic,
   date ranges, browser totals and chart layout live in framework-free JS
   (`reportingModel`, `reportingChartModel`); Apex is a thin query and storage layer returning
   plain JSON; definitions never carry a namespace prefix.

## Consequences

- No custom object is added. Saved definitions count toward file storage, a few kilobytes each,
  and need Files access, which every org has by default.
- Group sharing is a snapshot taken when the owner saves or shares; a newcomer to the group
  sees the item after the owner's next save or share. The admin guide says so.
- A Collaborator can save a new version but cannot share or delete; only the owner can.
- Browser totals above the aggregate limits cost one Apex call per 5,000 records; very large
  reports are slower than Salesforce's own engine and are capped at 1,000,000 records.
- A lookup grouping is labelled by the related record's Name field, and a picklist grouping by
  the labels stored in the definition; a template stores none, so its picklist groupings show
  the stored values.
- Template definitions name objects without a prefix; in a namespaced org the server resolves
  them, and this needs checking on the first namespaced org.
