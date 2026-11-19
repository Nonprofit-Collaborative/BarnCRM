# BarnCRM Advanced Reporting

## Purpose

Reports and dashboards built inside BarnCRM, in either edition (O-02, D-202, D-207; ADR-0231
`0231-advanced-reporting.md`). A report reaches fields across lookups and related records,
totals related records per row, and groups and charts its rows; a dashboard puts up to 12
reports under shared filters that reach every widget. Everything runs as the viewing person, so
each person sees totals of only the records they can read. In beta.

## First ships in

Release **1.29** (O-02).

## Depends on

- BarnCRM Core

Module objects (Fundraising, Volunteers, Corporate Hub, Scholarships and Outbound Grants and
any other) are read by name at run time, never referenced in code, so any mix of modules works.

## Contents

- Objects: none. Saved reports and dashboards are Salesforce Files (`.barnreport`, `.barndash`)
  holding JSON; the format is canonical model 29AR.
- Apex: `ReportingQueryService` (object and field lists, run, page; user mode, binds only,
  every object, field and function allow-listed by describe), `ReportingLibrary` (list, load,
  save, share and delete the files, all user mode), `ReportingPostInstall`.
- LWC: `reportingModel` and `reportingChartModel` (framework-free definition, filter, totals,
  scan and chart logic), `reportingHome` (the Advanced Reporting tab), `reportingBuilder`,
  `reportingDashboard`, `reportingView`, `reportingChart`, `reportingFieldPicker`,
  `reportingRange`, `reportingShare`. Filters use Core's `filterBuilder` and `filterDocument`.
- Custom permission: `Reporting_Save` (save, share, delete).
- Permission sets: `Reporting_Admin`, `Reporting_Staff`, `Reporting_Read_Only`.
- Tab: `Advanced_Reporting`. Setting Definition: `Reporting_Page` (section Advanced Reporting).
- Static resources: `BarnHelp_Reporting` (help text), `BarnReporting_Templates` (the Board
  Governance, Giving Overview, Scholarships and Grants and Volunteers dashboard templates).
- Catalog row: `BarnCRM_Module.Reporting` (Core), beta, both editions.
