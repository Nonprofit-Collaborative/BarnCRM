# ADR-NEXT: One-Field Rules Ship as Before-Save Flows That Read Their Own Switch

**Status:** Proposed (builder decision under owner decision D-219, release 1.36 item PF-03)
**Date:** 2026-11-22
**Source:** Brandon, D-219: one-field rules as before-save flows with a switch and a template;
the trigger framework manages every automation (Apex, flows, triggers) and an admin can switch
any of them off. Applies ADR-0040 (simple rules in Flow) and ADR-0165 (Automation Control);
amends ADR-0090 (which automations get a template) and ADR-0017 decision 3 (dispatch).

## Context

ADR-0040 says simple business rules ship as packaged Flows that check their switch first, and
engine logic stays in Apex. Every packaged automation was still Apex. Several handlers only set
one field on the record being saved from that record's own values, with no query, no related
record and no callout: filling a date when a status moves, deriving a due date. A before-save
(Fast Field Update) flow does that work without a DML statement, an admin can read it in Flow
Builder, and Save As gives the admin a copy with nothing hidden.

A before-save flow cannot call an action, so it cannot ask **Check BarnCRM Automation**
(ADR-0165 2.7). It can read `$Setup` values in a decision or formula, and it can Get Records.

## Decision

1. **When a rule is a before-save flow.** A rule ships as a packaged before-save flow when it
   sets fields only on the record being saved, from that record's values (`$Record`,
   `$Record__Prior`, `ISNEW`, `ISCHANGED`, `PRIORVALUE`), with no query of business data, no
   related record, no callout, no refusal message from help JSON, no field-level security
   decision and no field named only at run time (a Person Account field, ADR-0013). Anything
   else stays a handler: a refusal, a lookup to another record, a value computed by shared
   Apex (match keys), sharing, rollups and household engine logic.
2. **The registry row stays; the handler class goes.** The flow's API name is its
   `Automation_Registry__mdt` DeveloperName, its label is the row's label, and the row keeps
   its switch, module, description and Always Runs. `Handler_Class__c` is blank: the
   dispatcher passes over a row with no handler class without a warning, and the flow is the
   only owner of the rule.
3. **The flow reads its own switches, cheapest first.** After an entry condition that admits
   only records the rule would change, a decision ends the flow when
   `$Setup.BarnCRM_Automation_Control__c` has Pause All or Bypass on, or its `Paused_Until__c`
   (the timed pause, ADR-0238 decision 7) is later than now; none of these costs a query. Then
   one Get Records reads the row's `Automation_Setting__c` switch when it is off (no row means
   on, as `AutomationControl.isEnabled`), and, for a module's row, one Get Records on
   `Setting_Value__mdt` `Modules_Turned_Off` containing the module name (custom metadata, no
   query limit). Either found ends the flow. Ships **Active**; switching off is the switch,
   never deactivation, because an upgrade can change which version is active (ADR-0040).
4. **An always-run rule reads nothing.** A row with `Always_Runs__c` (ADR-0024) gets a flow
   with no switch reads, as its handler had.
5. **What a flow does not follow.** The per-transaction Apex bypass (`AutomationControl.bypass`)
   and the dispatcher's rollup-write skip cannot reach a flow. No code bypasses a converted
   rule by name today; a rule that needs either stays a handler. A module turned off in an org
   whose settings were not yet carried over to custom metadata still runs the flow; that is
   pre-release only.
6. **A template for one-field rules.** Core ships `Template_Before_Save_Field_Rule`
   (inactive, `isTemplate`): the same decision and switch lookup, with the switch name in a
   constant `cSwitchName` the admin sets to `Flow:` and the copy's API name, so a copy listed
   on the Automation page (ADR-0165 2.7) follows its switch without the action. It is the
   pattern contributors copy too, with the module lookup from a shipped flow.
7. **CI keeps it honest.** `check-flow-templates.py` fails when a packaged non-template flow is
   not named after a registry row with no handler class, is not Active, or (unless always run)
   does not read the setting, the timed pause, its switch row and, for a module row, the
   Module Manager list; and when a row with no handler class ships no flow. A Core row whose
   packaged flow ships needs no template (ADR-0090): the flow itself is Saved As.
8. **First conversions.** `Grant_Requirement_Dates` (Funders), `Data_Subject_Request_Due`
   (Corporate Hub) and `Stewardship_Plan_Completed_Date` (Giving, always runs). Core has no
   handler that fits decision 1 today: the preferred email and phone rules refuse a save with
   help JSON text and decide by field-level security, and the address match key uses shared
   Apex.

## Alternatives considered

- **Entry condition with `$Setup` only, no switch lookup.** Rejected: the per-automation switch
  and the Module Manager would not stop the flow, so an admin could not switch it off from the
  Automation page.
- **Switching off by deactivating the flow through the Metadata API.** Rejected: an upgrade can
  reactivate it (ADR-0040), and a deployment per switch is slow and asynchronous.
- **After-save flows calling Check BarnCRM Automation.** Rejected: an extra DML per save for a
  one-field update, which is what before-save flows exist to avoid.
- **Keep the handler and add the flow as a template only (ADR-0090).** Rejected for these rules:
  the owner asked for flows admins can read and switch, and two owners of one rule drift.

## Consequences

- One shipped rule costs one SOQL query per save batch only when its entry condition admits the
  record and no `$Setup` control stopped it; the custom metadata read costs no query.
- A before-save flow runs before every before trigger, so a converted rule now runs ahead of
  the handlers on its object; none of the converted objects' handlers read the fields they set.
- Tests: record-triggered flows run in Apex tests, so the existing save-and-assert tests cover
  each flow, plus a switch-off test, and for Data Subject Request a Bypass and timed pause test.
  The Module Manager check cannot be tested in Apex (settings deploy in memory in tests) and is
  a manual step (testing guide T-SET-07H).
- The removed handler classes left `scripts/ci/api-surface.txt` by hand, before the first
  promoted version, as `docs/contributor-guide/ci.md` allows with owner approval.
