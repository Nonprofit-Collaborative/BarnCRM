# BarnCRM Logic Models

## Purpose

Logic models the organization builds itself: inputs, activities, outputs, outcomes (short,
intermediate and long term) and impact, the assumptions between them, and indicators with a
baseline and a target and result per period. Separate from Programs on purpose (plan Section
5.7, ADR-0154 `0154-logic-models-module.md`).

## First ships in

Release **0.14** (L-01 builder, L-02 indicators). L-03 indicator sources and L-04 the logic model
report follow in 0.15.

## Depends on

- BarnCRM Core

Nothing in this package references Programs, Volunteers or Giving. A model may name a program by
its record identifier (text), resolved by describe only where a `Program__c` object exists.

## Contents

- Objects: `Logic_Model__c`, `Logic_Model_Element__c`, `Logic_Model_Link__c`, `Indicator__c`,
  `Indicator_Period__c` (canonical model Sections 29Z to 29ZD).
- The **Logic Model Builder** panel (`logicModelBuilder`) on the Logic Model record page, with its
  framework-free rules module `logicModelRules` and the thin controller
  `LogicModelBuilderController`.
- Permission sets Logic Models Admin, Staff and Read Only, given by role through
  `LogicModelsAccessSync`.
