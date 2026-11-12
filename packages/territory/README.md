# BarnCRM Territory Management

## Purpose

Assigns people, households and organizations to territories and owners by rules, with a preview
before anything changes and undo afterwards (plan C-40 and C-40b, ADR-0205
`0205-territory-management-module.md`, D-98, D-120, D-156). Never uses Salesforce's Enterprise
Territory Management, so it runs on a Platform-only org.

## First ships in

Release **1.16** (C-40, C-40b).

## Depends on

- BarnCRM Core

Nothing here references another module. Rules compile through Core's `QueryCompiler`; an Assign
run is a Core data job whose Undo is Core's (`ImportJournalService`, `ImportUndoService`).

## Contents

- Objects: `Territory__c` (29TM1), `Territory_Rule__c` (29TM2), `Territory_Member__c` (29TM3),
  `Territory_Run__c` (29TM4), and the lookup `Territory__c` on Account and Contact.
- Permission sets `Territory_Admin`, `Territory_Staff`, `Territory_Read_Only`, given through
  BarnCRM's roles by `TerritoryAccessSync`.
- Apex: `TerritoryRunBatch` (preview and assign, one kind after another), `TerritoryRouting`
  (owner routing), `TerritoryController` (the page), `TerritoryNightlyJobProvider` (the 5:45 AM
  step, shipped off), `TerritoryAccessSync`, `TerritoryPostInstall`.
- The Territory Management tab and page (`territoryManager`, `territoryModel`), help text in
  `BarnHelp_Territory`.
