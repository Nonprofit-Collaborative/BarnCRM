# ADR-0040: Simple rules in Flow, engine logic in Apex, and customers switch ours off to run theirs

**Status:** Accepted
**Date:** 2026-09-22
**Source:** product owner decision (Brandon), plan Section 4.8

## Context

BarnCRM ships as unlocked packages for the foreseeable future. In an unlocked package a
customer can edit anything, and the next upgrade can overwrite what they edited, so a
customer who changes a packaged automation loses the change without warning. The product
owner prefers Flow for automation because a customer can see how a Flow works and make a
version of their own. Every packaged automation today is Apex, dispatched by
`TriggerDispatcher` from Automation Registry records, each with an on/off switch in
Nonprofit Settings (C-04).

Flow is not the right tool for everything. Household naming, merge and split, rollups and
the membership mode guards are complex, bulk sensitive and heavily tested; in Flow they
would be slow, hard to test, and fragile for a customer to copy.

## Decision

- **Simple business rules ship as packaged Flows**, for example address propagation,
  deleting an empty household, reciprocal relationships. A customer can read them and copy
  them.
- **Engine logic stays in Apex** and is offered to Flow as invocable actions, so a customer
  flow can call the same logic the package uses.
- **Every packaged automation, Flow or Apex, is registered in the Automation Registry** with
  its on/off switch. A packaged Flow checks its switch as its first step, not its activation
  state, because an upgrade can change which version of a Flow is active; the switch
  survives an upgrade.
- **Customization is "switch ours off, run yours."** Each switchable automation has a Flow
  template the customer can Save As and own. Customers build their own record-triggered
  flows; they do not edit packaged ones.
- **Not built yet:** a registry entry that runs a customer-named Flow at a set point in the
  packaged order. It is added only when a real need for ordering between packaged and
  customer automation is named.

## Consequences

- Moving an existing Apex automation to Flow is a per-automation decision made against the
  line above (simple rule or engine logic), not a rewrite of the framework.
- Each Flow template is a second artifact to keep in step with the packaged automation it
  mirrors; the Definition of Done for a switchable automation includes its template.
- Upgrades never touch a customer's own flows, templates they saved, or their switch
  settings, so a customization survives every upgrade.
