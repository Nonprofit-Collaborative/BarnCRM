# BarnCRM Logic Models

## Purpose

Logic models the organization builds itself: inputs, activities, outputs, outcomes (short,
intermediate and long term) and impact, the assumptions between them, and indicators with a
baseline and a target and result per period. Separate from Programs on purpose (plan Section
5.7, ADR-0154 `0154-logic-models-module.md`).

## First ships in

Release **0.14** (L-01 builder, L-02 indicators). Release **0.15** (L-03 indicator sources,
L-04 the logic model report).

## Depends on

- BarnCRM Core

Nothing in this package references Programs, Volunteers or Giving. A model may name a program by
its record identifier (text), resolved by describe only where a `Program__c` object exists.

## Contents

- Objects: `Logic_Model__c`, `Logic_Model_Element__c`, `Logic_Model_Link__c`, `Indicator__c`,
  `Indicator_Period__c` (canonical model Sections 29ZC to 29ZG).
- The **Logic Model Builder** panel (`logicModelBuilder`) on the Logic Model record page, with its
  framework-free rules module `logicModelRules` and the thin controller
  `LogicModelBuilderController`.
- The **Logic Model Report** (`logicModelReport`, L-04) at the bottom of the builder: report,
  CSV and printable HTML worked out by `logicModelRules`; no Apex, nothing stored.
- Permission sets Logic Models Admin, Staff and Read Only, given by role through
  `LogicModelsAccessSync`.
- Indicator sources (L-03, ADR `0158-indicator-sources.md`): `IndicatorSourceService`, the
  batch `IndicatorResultsBatch` (system mode, `without sharing`), the nightly
  `IndicatorResultsScheduler` registered with Core through `LogicModelsNightlyJobProvider`, and
  the Core import template **Indicator Results** (`Import_Template_Default.Indicator_Results`),
  made at install by `LogicModelsPostInstall`.
