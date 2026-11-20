# ADR-NEXT: BarnCRM Connector: Recipes, Connections on Named Credentials, Polling and Webhook Triggers, Run History, and C-38 Started Inside It

**Status:** Proposed
**Date:** 2026-11-20
**Source:** Brandon, 2026-11-20 ("an integration/middleware module ... similar to Workato in
capabilities and super easy for a non technical user to setup and use"); design in
`docs/architecture/integration-hub-design.md` Sections 1 and 3 to 8. Starts C-38 (held by D-39)
and amends plan Section 4.9's C-38 scope; builds on ADR-0013, ADR-0057, ADR-0148 amendment A1,
ADR-0165, ADR-0166, ADR-0184, ADR-0201, ADR-0227, ADR-0229 and MIG-06. Companion: ADR-NEXT
`NEXT-reusable-mapper.md`.

## Context

Moving data between BarnCRM and other apps today takes Flow Builder with HTTP Callout and Setup
credentials, a hand-written receiver for anything pushed in, or a paid iPaaS (Zapier lists
Salesforce as a premium app; Workato is a paid enterprise product). Principle 1 forbids needing
Flow Builder, Section 4.2 forbids paid add-ons, and the owner wants Workato-like capability for a
non-technical admin. Apex limits (callouts, time, heap, asynchronous executions), the rule that
Apex never reads a stored secret (ADR-0229), the guest-only-stores rule (ADR-0184) and the object
budget (197 of 200) bound the design.

## Decision

1. **A new optional module, BarnCRM Connector** (`packages/connector`, both editions, Beta,
   depending on Core only), tab Super Connector. Concepts: Connections, Recipes (one When, up to 25
   Then steps), Runs, Maps and Templates.
2. **Connections are Salesforce credentials, not records.** BarnCRM creates an External Credential
   and a Named Credential per connection through `ConnectApi`, writes the pasted secret to the
   principal (it is never stored, logged or shown again), adds the principal to one org-owned
   permission set, and guides the one Setup click Salesforce requires (Enabled for Callouts) and,
   for OAuth browser sign-in, the Authenticate click and the provider app. Headers use
   `$Credential` merge formulas, so Apex never reads a secret.
3. **Connectors are JSON definitions** (auth kind, base URL, check call, actions, pollers, webhook
   options, templates) run by one generic HTTP executor. Generic REST first; then Slack and Teams,
   Mailchimp, Google Sheets, giving-tool webhooks, Eventbrite, Zoom, Constant Contact, QuickBooks
   Online.
4. **Triggers:** schedule; record created or changed by polling `SystemModstamp` past a watermark
   every 15 minutes (not the trigger framework, not Change Data Capture); inbound webhook; app
   polling; manual and the Flow action Run BarnCRM Recipe. A clock of four CronTriggers runs as the
   admin who turned recipes on (the runner).
5. **Webhooks follow ADR-0184 and ADR-0201:** a Site guest REST receiver only stores a Received run;
   a 256-bit token in the URL is kept only as its SHA-256 hash; body and hourly caps; idempotency
   by event key; optional fetch back through the connection, limited to the connection's host. No
   HMAC signatures (they need a readable secret); apps that require one are polled instead.
6. **Steps:** Find, Create, Update, Create or Update (through a map), Call an App, Change Data, If,
   For Each, Wait, Load Rows with an Import Template, Stop. Values are paths, never expressions.
   Data steps run in user mode as the person the run executes as; only the module's own rows are
   written in system mode.
7. **Runs:** one Queueable runner chain processes many runs per execution and checkpoints before a
   callout that follows DML, before 90 callouts, 100 seconds of callout time or 45 seconds of CPU.
   Transient failures retry at 15 minutes, 1, 4 and 12 hours from the failed step; repeated
   failures pause the recipe; failures go to the Error Log and digest; runs are kept per recipe
   (30 days by default) and cleaned by a Nightly Jobs step.
8. **C-38 starts here.** Scheduled imports are a recipe step that stages rows through Super Importer,
   runs the dry run and commits only inside the recipe's limits. Google Sheets is the first source.
   SFTP and direct database sources leave C-38's scope: Apex cannot open them.
9. **Two objects, no settings object:** `Connector_Recipe__c` and `Connector_Run__c` (suite 197 to
   199). Every option is per recipe.

## Alternatives considered

- **Templates and docs only (Flow HTTP Callout templates and a webhook-to-platform-event
  receiver):** cheapest, but every integration still needs Flow Builder, has no per-run retry or
  auto-pause, and shares no maps. Kept as the advice for admins who already build flows.
- **Recommend Zapier or Workato:** paid for the organization.
- **Change Data Capture or the trigger framework for record changes:** per-object deployment, a
  five-entity allocation, or Core naming the module; polling covers every object.
- **Packaged credentials per connector (the ADR-0229 shape):** removes the Enabled for Callouts
  click for fixed-host apps but makes each connector code plus metadata, and does not cover
  generic REST or per-account hosts.
- **Recipes as custom metadata or Files:** custom metadata deploys from Apex need a Setup setting
  for packages that are not certified, and a watermark would be a deploy; Files hold mutable state
  poorly.
- **A formula or code step:** refused (ADR-0081).

## Consequences

- An admin connects an app, picks a template, tests it with a sample and turns it on without Flow
  Builder; one guided Setup click per connection remains, and OAuth apps need an app at the
  provider.
- Record-change recipes can lag up to 15 minutes; the Flow action gives immediate starts.
- Anyone who can publish recipes acts with the runner's access; publishing is limited to
  `BarnCRM_Connector_Admin`, and Health Check watches the runner.
- The suite reaches 199 of 200 objects; the next object anywhere needs a cut.
- To confirm on the first org deploy: `createCredential` for Custom protocol principals,
  `SetupEntityAccess` inserts for principals, run-time Auth Provider creation, and `callout:` to a
  subscriber-created Named Credential from namespaced Apex. Each has a guided Setup fallback.
- Workato features left out (SFTP, databases, agents, streams, code steps, synchronous APIs) are
  listed in the design with what to do instead.
