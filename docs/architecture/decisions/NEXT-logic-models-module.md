# ADR-NEXT: The BarnCRM Logic Models module: its own package on Core, five objects, a program named by its record identifier

**Status:** Proposed (built as recommended for release 0.14, L-01 and L-02; awaits owner confirmation)
**Date:** 2026-10-31
**Source:** plan Section 4.1 (packaging table), Section 5.7 (L-01 to L-06 and the owner decision of
2026-09-23), Section 6.0a release 0.14 (D-155), Section 9.9 (portability); builds on ADR-0003,
ADR-0013, ADR-0014, ADR-0017, ADR-0024, ADR-0124, ADR-0127 and ADR-0131.

## Context

Logic Models (L-01 to L-06, plan Section 5.7) records what changed for the people an organization
serves and how it knows it, as a logic model the organization builds itself: inputs, activities,
outputs, outcomes (short, intermediate and long term) and impact, the assumptions between them,
and indicators with a baseline and a target and result per period. Release 0.14 builds L-01 (the
builder) and L-02 (indicators); L-03 (indicator sources), L-04 (the report) and later L-05 and L-06
follow. Plan Section 6.0a asks for an ADR before each new module.

The plan settles the package: the owner decided on 2026-09-23 that Logic Models is its own
package, depending on Core only, and that neither Logic Models nor Programs references the other
(Section 5.7; the Section 4.1 table lists it). Main had no folder for it and no catalog row.

## Decision

1. **Its own package, Core only.** `packages/logicmodels`, package `BarnCRM Logic Models`, depends
   on BarnCRM Core alone (install order Core, Logic Models). Not inside `packages/programs`: an
   organization can build and report on its logic model before it tracks any services in
   Salesforce, and outcomes can draw on volunteer hours or giving as well as programs. Core ships
   the catalog row `BarnCRM_Module.LogicModels` (Nonprofit Edition only, Sort Order 35, after
   Programs), so the module key is `LogicModels` and the classes Core finds by name are
   `LogicModelsAccessSync` and `LogicModelsPostInstall`.
2. **Five objects.** Logic Model (`Logic_Model__c`); its elements (`Logic_Model_Element__c`, a
   detail of the model, each an Input, Activity, Output, Outcome with a term, or Impact); the
   links between elements, each carrying the assumption that one leads to the other
   (`Logic_Model_Link__c`, a detail of the model); indicators on outputs and outcomes
   (`Indicator__c`, a detail of the element); and an indicator's target and result for one period
   (`Indicator_Period__c`, a detail of the indicator). Canonical model Sections 29Z to 29ZD.
3. **Assumptions live on links.** An assumption is the reason one element leads to another, so it
   is a field of the link, not an element type. A link is a record (not JSON on the model) so the
   evidence log (L-05) can point at the assumption it supports and a report can list them.
4. **The chain is enforced by the platform.** Each element has a formula stage rank (Input 1,
   Activity 2, Output 3, short, intermediate and long term outcome 4 to 6, Impact 7). Validation
   rules refuse a link that does not move forward, joins two models, or misses an end; an
   indicator on an input, activity or impact; and an element type change that would leave
   indicators on such an element. No Apex runs for any of these, so they hold for imports and the
   API too. The builder's pure JavaScript module (`logicModel.js`, plan 9.9) holds the same rank
   table as JSON, so the builder offers only links the platform accepts.
5. **One model for the organization and one per program, named by record identifier.** A model
   with no program is the organization's; a model may name a program by its record identifier as
   text (`Program_Id__c`, the ADR-0014 pattern), never a lookup, so Logic Models installs without
   Programs. The builder offers a program picker only where an object named `Program__c` exists
   (read by describe), and shows the program's name the same way. At most one model per scope: an
   automation that always runs (registry row `Logic_Model_Scope`, ADR-0024) sets the unique
   `Scope_Key__c` and refuses a second model for the same scope with a plain message, counting
   models the user cannot see; the unique field backs it against two saves at once.
6. **Indicators: unit, direction, baseline, and a target and result per period.** A period is
   named (for example "2026 Q1") with a start and end date; one indicator holds any number of
   periods, so a yearly and a quarterly target can sit side by side. Better When (Higher or
   Lower) says which way is better, so the builder shows progress correctly for an indicator such
   as emergency room visits. Results are typed by hand in 0.14; L-03 adds import
   and computed sources.
7. **Three permission sets, given by role.** `Logic_Models_Admin` (everything) to holders of
   `BarnCRM_Admin`; `Logic_Models_Staff` to the Team Member (`Program_Staff`) and Coordinator
   (`Volunteer_Coordinator`) roles: create and edit models, and create, edit and delete elements,
   links, indicators and periods, since building a model means removing parts of it, but never
   delete a whole model; `Logic_Models_Read_Only` to the Read Only role. Given by
   `LogicModelsAccessSync` on the Programs and Volunteers pattern (ADR-0127 decision 3, ADR-0131),
   never taken away.
8. **Built in the app, never in Setup.** The **Logic Model Builder** panel on the model's record
   page is where models are built (columns per stage, links and assumptions, indicators and
   periods). Its Apex controller is thin and returns plain JSON shapes; checks and grouping run in
   the framework-free module (plan 9.9).
9. **No settings yet.** Nothing in L-01 or L-02 is a choice the organization needs to make, so
   there is no settings object and no Logic Models section in BarnCRM Settings; L-03 adds the
   first if it needs one.

## Alternatives considered

- **Logic Models inside `packages/programs`.** Rejected by the owner decision of 2026-09-23 (plan
  Section 5.7): Programs records what was done and for whom, Logic Models what changed; an
  organization without Programs still needs a logic model.
- **A lookup from the model to the program.** Rejected: it would make Programs a dependency.
- **Assumptions as an element type, or links as JSON on the model.** Rejected: an assumption sits
  between two elements, and L-05 needs a record to attach evidence to.
- **Link and indicator rules in Apex triggers.** Rejected: validation rules enforce them with no
  code, everywhere, and are simple enough to mirror in the builder's module.
- **A status (draft, active) per model with one active per scope.** Rejected for now: nothing in
  L-01 to L-04 needs versions; periods already compare years within one model.

## Consequences

- Five more custom objects for a logic model user (the Lightning Platform Starter object count,
  ADR-0121).
- Deleting an element deletes its indicators and their periods (master-detail), and the builder
  deletes its links first; deleting it from the standard record page leaves its links with an end
  empty, which the builder does not show; they can be deleted from the model's Links related list.
- A program deleted in Programs leaves its identifier on the model; the builder shows the program
  as missing and the model can be moved to the organization or another program.
- The module can never be offered in the Standard Edition (ADR-0124), and no Opportunity,
  Campaign or Case is used (ADR-0013).
