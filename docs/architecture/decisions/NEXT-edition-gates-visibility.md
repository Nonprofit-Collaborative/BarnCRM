# ADR-NEXT: The edition decides which modules Core shows, and is chosen once

**Status:** Accepted (owner decision, Brandon, 2026-10-14)
**Date:** 2026-10-14
**Source:** owner decision of 2026-10-14; builds on ADR-0122 (edition names); amends ADR-0072
(suite choice is the first setup step) and ADR-0062 (Giving installed offers every module)

## Context

ADR-0072 made the edition (stored in `BarnCRM_Settings__c.Suite__c` as `Community` or `Impact`)
the Setup Assistant's first step, and said it "installs, removes and hides nothing" and "can
be changed later". In practice the Standard Edition still listed Volunteers in the module
step, the Module Manager and the home Modules card, an installed Giving made every nonprofit
module appear in a Standard Edition org (ADR-0062), and Health Check suggested the Connect
module to any Nonprofit Cloud org. The step also kept offering the choice on every visit, so
a casual click could change what every admin and user sees.

The owner decided that nonprofit modules are not visible unless the Nonprofit Edition is
chosen, and that the edition is chosen once. The repo rule that every admin setting lives in
the in-app Settings console still holds.

## Decision

- **Visibility.** Core shows and offers the nonprofit modules (Giving, Volunteers, Programs,
  Funders, Connect) only when the Nonprofit Edition is chosen. With the Standard Edition, or no
  edition chosen, Core lists Core and any module that is already installed, and nothing else.
  One rule in `ModuleDetectionService.getModules()` feeds the Setup Assistant's module step,
  the Module Manager and the home Modules card. The Health Check Connect hint
  (`connect_module_absent`) appears only in the Nonprofit Edition.
- **Installed modules keep working.** A module that is physically installed stays listed and
  keeps its own settings sections, Setup Assistant steps, Health Check findings, What's New
  notes, roles and tabs, because those come from the installed package itself. The edition
  never installs, removes or turns off anything.
- **Chosen once.** Once `Suite__c` has a value, the Setup Assistant's first step shows the
  edition read-only, also after Start again. It keeps the Giving install link while the
  Nonprofit Edition is chosen and Giving is missing.
- **Changing it later.** The console's General section shows Edition read-only through a
  Component row (`editionSetting`), with a collapsed "Change edition" disclosure, visible only
  to holders of Manage BarnCRM Settings, whose button opens a confirmation that says what
  changes. Saving goes through `SetupAssistantController.changeEdition`, which validates the
  value and writes an audited settings change. Setup, Custom Settings, BarnCRM Settings, Edition
  (`Community` or `Impact`) also works; a value that is neither counts as no edition.
- **No new field or object.** `Suite__c` already exists.

## Alternatives considered

- **Keep Edition a plain picklist row in the console.** Rejected: it makes changing the edition
  as easy as any other setting, which the owner ruled out.
- **Remove Edition from the console and leave only Setup, Custom Settings.** Rejected: it breaks
  the rule that every admin setting lives in the in-app console.
- **A separate "Advanced" console section.** Rejected: a new section for one control is more
  surface than a disclosure on the existing row, and Edition belongs in General.
- **Hide installed modules too in the Standard Edition.** Rejected: hiding something that is
  installed and running would leave admins unable to find or manage it.

## Consequences

- Volunteers is no longer offered in the Standard Edition (it was in ADR-0046's "modules that
  fit"); the feature catalog marks it Nonprofit Edition.
- ADR-0062's "Giving installed offers every module" is superseded: Giving installed preselects
  the Nonprofit Edition in step one, but only the chosen edition decides what is offered.
- The admin guide gains `editions.md`, the one place that explains both editions and how to
  change the edition, which the Setup Assistant, Settings, Module Manager and What's New pages
  link to.
- Accepted ADRs keep their wording; read this record for the current rule.
