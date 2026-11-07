# ADR-NEXT: Deactivate org flows and validation rules with a snapshot and restore

**Status:** Accepted (owner decision, Brandon, 2026-11-06, plan D-184: an optional "Deactivate
org flows and validation rules" tool with a snapshot and Restore, available in sandboxes, and in
production behind a clear warning and a typed confirm; "Automation inventory (C-60) with the
'Covered by Pause All' column and snippets: Yes, build now"; "Automation as its own tab")
**Date:** 2026-11-06
**Source:** C-60, plan D-184; canonical model Section 10A (Automation Snapshot) and Section 29F
"Automation tab inventory"; amends the plan's Section 4 non-goals ("org-wide automation
switches"); reuses the org connection of ADR-0148

## Context

A data load, a migration or a cleanup is often blocked by the org's own automation: a flow
that sends email for every record, a validation rule that rejects old data. BarnCRM's own
automation already pauses (ADR-0165, the BarnCRM Automation Control setting), and an org's flow,
trigger or rule follows that pause only if it checks the setting. Admins today turn the rest off
one by one in Setup and must remember to turn each back on, at the version that was active.

Section 4 listed "org-wide automation switches" among the things BarnCRM deliberately does not
build. The owner reversed that for this one tool (D-184).

What the platform allows:

- User-mode SOQL reads flows (`FlowDefinitionView`) and Apex triggers (`ApexTrigger`, with their
  source), as the Data Dictionary inventory already does. Validation rules, workflow rules and
  metadata dependencies are Tooling API only.
- A flow is deactivated by setting its `FlowDefinition` metadata's `activeVersionNumber` to 0,
  and reactivated by setting it back; a validation rule by saving its metadata with `active`
  false. Both are Tooling API writes.
- A Lightning session cannot call the API. The org connection of ADR-0148 (External Credential
  and Named Credential `Barn_Org_Connection`, a queued job sending its own session) already
  calls the org's own Metadata API; the Tooling API is on the same host.

## Decision

1. **The inventory reads with SOQL; the connection adds the rest.** The Automation tab lists
   BarnCRM's switches, flows, processes and triggers from user-mode SOQL (R-OA1 to R-OA6). With
   the connection, **Scan Org Automation** queues a job that reads validation rules, workflow
   rules and `MetadataComponentDependency` rows that refer to Check BarnCRM Automation,
   `AutomationControl` or the `BarnCRM_Automation_Control__c` setting and its fields; the result
   is one Scan snapshot that sets Covered by Pause All for the org's own flows and adds the rules.
2. **Deactivate only the org's own flows and validation rules.** Never a BarnCRM item, never a
   managed package's (any namespace), never a trigger (triggers cannot be deactivated in
   production) and never a workflow rule (retired by Salesforce; migrate to flow).
3. **Snapshot first, then change, per item.** A queued job reads each chosen item's current
   state through the Tooling API (active, and a flow's active version number) and saves it on
   an `Automation_Snapshot__c` record before any change; a second job changes the items, a few
   per job, chained, and saves each item's result. A failure on one item is recorded with its
   reason and never stops the rest (Done, Partial or Failed).
4. **Restore puts back exactly the snapshot** for each item that changed: the flow's active
   version, the rule's active state. One deactivation or restore runs at a time.
5. **Production is guarded.** The tool works in sandboxes with a plain confirmation; in
   production the dialog warns that the org's automation stops for everyone until restored, and
   the confirm button stays disabled until the person types the confirmation phrase.
6. **Who may.** The connection's own rule (ADR-0148 decision 2): Manage BarnCRM Metadata and
   Manage BarnCRM Settings, plus Customize Application and Modify Metadata. The page shows the
   connection's status and how to set it up when it is missing.

## Alternatives considered

- **Keep the non-goal: snippets only.** Every org item gets the code that makes it respect
  Pause All, and that stays the first answer on the page. Rejected as the only answer by the
  owner: many admins cannot edit every flow before a load.
- **Metadata API deploy of `FlowDefinition` and `ValidationRule`.** Asynchronous deploys, a zip
  to build, and a validation rule's full metadata anyway; the Tooling API updates one item per
  call and reports per item.
- **Deactivate triggers too.** A trigger cannot be made inactive in production except by
  deploying it; out of reach and a security review concern.

## Consequences

- Plan Section 4 "What we deliberately do not build" and Section 6's out-of-scope list lose
  "org-wide automation switches" (the integrator updates the plan, BMemory first).
- Security review scope grows within the ADR-0148 connection: Tooling API reads and two Tooling
  writes (flow active version, validation rule active), admin-only, on an explicit click, with a
  production confirmation and a stored snapshot to restore.
- New Core object `Automation_Snapshot__c` (canonical model Section 10A); BarnCRM Admin only.
- Unproven on an org until QA: the Tooling API accepting the job's session, a validation rule
  update with its read-back metadata, and `MetadataComponentDependency` listing a flow's use of
  an invocable action and a formula's use of a `$Setup` field. Until proven, the page names the
  scan's coverage as read through the connection, and the snippets stay the fallback.
