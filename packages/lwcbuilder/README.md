# BarnCRM LWC Builder

## Purpose

Admins build their own Lightning components on a drag-and-drop grid and place them on record,
app and home pages (LB-01 to LB-06, D-120, ADR-0203 `0203-lwc-builder-module.md`). A component
is a `Built_Component__c` record holding a JSON definition; one packaged component,
`lwcBuilderRenderer` (BarnCRM Built Component), draws it as the viewing user. Nothing is
generated or deployed at run time.

## First ships in

Releases **1.14** (LB-01, LB-02), **1.16** (LB-03 to LB-06) and **1.20** (LB-07, D-196: charts
by two groupings and three totals, working list and chart export).

## Depends on

- BarnCRM Core

## Contents

- Objects: `Built_Component__c`, settings `LWC_Builder_Settings__c` (canonical model 29LB1,
  29LB2).
- Apex: `LwcBuilderController` (the builder's list and save; the renderer's component, list,
  chart and permission reads, all user mode), `LwcBuilderComponentPicklist` (the App Builder
  property), `LwcBuilderPostInstall`, `LwcBuilderAccessSync`.
- LWC: `lwcBuilderModel` (framework-free definition logic, chart layout and source export), `lwcBuilderStudio`
  (the LWC Builder tab), `lwcBuilderRenderer` (BarnCRM Built Component), `lwcBuilderBlock`,
  `lwcBuilderExportKit` (the exported controller, test, helpers and chart styles, as text).
- Permission sets: `LWC_Builder_Admin`, `LWC_Builder_Staff`, `LWC_Builder_Read_Only`.
- Help text: `BarnHelp_LwcBuilder`.
