# ADR-NEXT: BarnCRM Connector: Recipes, Connections on Named Credentials, Polling and Webhook Triggers, Run History, and C-38 Started Inside It

**Status:** Proposed
**Date:** 2026-11-20
**Source:** Brandon, 2026-11-20 ("an integration/middleware module ... similar to Workato in
capabilities and super easy for a non technical user to setup and use"); design in
`docs/architecture/integration-hub-design.md` Sections 1 and 3 to 8; owner decisions D-215
(2026-11-20: C-38, secrets subject to security review, names and two objects approved; running as
the admin who turned recipes on rejected in favor of system, integration user or non-user runs)
and the security review `docs/architecture/connector-secrets-security-review.md`. Starts C-38 (held by D-39)
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
   principal, adds the principal to one org-owned permission set, and guides the one Setup click
   Salesforce requires (Enabled for Callouts) and, for OAuth browser sign-in, the provider app,
   the Auth Provider (created by the admin in Setup) and the Authenticate click. Headers use
   `$Credential` merge formulas, so Apex never reads a secret. Page entry is approved (D-215)
   under the binding requirements of decision 11.
3. **Connectors are JSON definitions** (auth kind, base URL, check call, actions, pollers, webhook
   options, templates) run by one generic HTTP executor. Generic REST first; then Slack and Teams,
   Mailchimp, Google Sheets, giving-tool webhooks, Eventbrite, Zoom, Constant Contact, QuickBooks
   Online.
4. **Triggers:** schedule; record created or changed by polling `SystemModstamp` past a watermark
   every 15 minutes (not the trigger framework, not Change Data Capture); inbound webhook; app
   polling; manual and the Flow action Run BarnCRM Recipe. The clock is not Scheduled Apex (which
   runs as, and fails without, the user who scheduled it): a platform event trigger starts a
   heartbeat Queueable that re-enqueues itself every 5 minutes and keeps the trigger's identity
   (decision 10).
5. **Webhooks follow ADR-0184 and ADR-0201:** a Site guest REST receiver only stores a Received run;
   a 256-bit token, sent in an `X-BarnCRM-Token` header where the app allows it and in the query
   otherwise, is kept only as its SHA-256 hash; body and hourly caps; idempotency by event key;
   optional fetch back through the connection under decision 11's F4 rules. No HMAC signatures
   (they need a readable secret); apps that require one are polled instead.
6. **Steps:** Find, Create, Update, Create or Update (through a map), Call an App, Change Data, If,
   For Each, Wait, Load Rows with an Import Template, Stop. Values are paths, never expressions.
   Data steps run in user mode as the recipe's identity, or in system mode for a System recipe
   (decision 10); otherwise only the module's own rows are written in system mode.
7. **Runs:** one Queueable runner chain processes many runs per execution and checkpoints before a
   callout that follows DML, before 90 callouts, 100 seconds of callout time or 45 seconds of CPU.
   Transient failures retry at 15 minutes, 1, 4 and 12 hours from the failed step; repeated
   failures pause the recipe; failures go to the Error Log and digest; runs are kept per recipe
   (30 days by default) and cleaned by a Nightly Jobs step.
8. **C-38 starts here.** Scheduled imports are a recipe step that stages rows through Super Importer,
   runs the dry run and commits only inside the recipe's limits. Google Sheets is the first source.
   SFTP and direct database sources leave C-38's scope: Apex cannot open them.
9. **Two objects, no settings object:** `Connector_Recipe__c` and `Connector_Run__c` (suite 197 to
   199). Every option is per recipe. Two platform events (`Connector_Start__e`,
   `Connector_Start_User__e`) dispatch the work; they are not custom objects.
10. **No recipe runs as a staff member (D-215).** Each recipe has Run As, set only by a Connector
    admin and recorded with who set it and when:
    - **BarnCRM Automation** (default): the Automated Process user, in user mode, limited to the
      permission sets the admin picks (BarnCRM Admin and installed modules' admin sets to start),
      which BarnCRM assigns to that user with a `PermissionSetAssignment` from Apex.
    - **System:** the Automated Process user in system mode (no object, field or sharing checks),
      set only through a confirmation that says so, and listed by Health Check.
    - **Integration User:** one designated user, ideally on a free Salesforce Integration license
      (five in Enterprise, Unlimited and Performance editions), in user mode with its own
      permission sets. It is set as the running user of the second event's trigger through
      `PlatformEventSubscriberConfig`, which Salesforce exposes only in the Tooling and Metadata
      APIs; BarnCRM writes it over the ADR-0148 org connection, then guides one Suspend and Resume
      click on the event's Subscriptions list.

    Each identity holds the connections' principal access. Records a recipe creates get the owner
    the recipe names (an Automated Process owner hides records from people). Test and Run Now run
    as the recipe's identity.
11. **Binding security requirements for connections and the executor** (independent review
    `docs/architecture/connector-secrets-security-review.md`, findings F1 to F13; each is tested
    in the slice that builds it):
    - **F1** Named Credentials are created with Allow Formulas in HTTP Body off. Only the catalog's
      auth header template may contain `{!`; any header, path, query or body value from recipe
      configuration, data pills, payloads, app responses or records containing `{!` fails the
      step, and recipes or maps with `{!` in a literal cannot be saved. Generic REST builds its
      auth header from the auth kind, never free text.
    - **F2** The server generates every `BarnConn_` name. Update, Disconnect and Delete accept only
      an existing `BarnConn_` External Credential linked to a `BarnConn_` Named Credential;
      `Barn_Stripe` and every other credential are refused before any ConnectApi call. Principal
      and parameter names come from the catalog.
    - **F3** Credential writes check `Manage_BarnCRM_Connector` and `ManageNamedCredentials` or
      Customize Application first, and call ConnectApi synchronously as that user; a secret is
      never queued, scheduled, published or passed to a recipe identity. The controller is in
      `BarnCRM_Connector_Admin` only and is never exposed through Visualforce or REST.
    - **F4** Base URLs are `https`; scheme and host cannot change while a secret is stored (a new
      connection, or URL and secret replaced together); catalog hosts are locked to their pattern
      (Mailchimp `{dc}` matches `^[a-z]{2}[0-9]{1,3}$`); appended paths start with one `/` and
      contain no `@`, `\`, `{!`, CR or LF, with inserted values URL-encoded; fetch back parses with
      `System.Url`, requires `https`, no user info and the exact host and port, and calls
      `callout:` with that URL's path and query only.
    - **F5** A secret-URL connection (Teams Workflows, a Slack incoming webhook) is stored as Named
      Credential configuration and is readable by administrators who can view Setup; the page,
      guide and this ADR say so. The URL is never returned to the client or stored on a run (host
      and last four characters only). Slack recommends a bot token. The Setup Changes copy masks
      Named Credential URLs if the audit trail records them.
    - **F6** Secret parameters are written with `encrypted = true` (ids may be `false`); BarnCRM
      never reads values back with `getCredential`; the secret box is always empty.
    - **F7** Credential methods catch every exception and log a fixed message and the exception
      type with any secret text replaced by `****`; raw exceptions never reach `ErrorLogger`,
      `UserErrors.wrap` or the user; no `System.debug` in the module; no secret in any field,
      setting, journal, Setting Change, run, platform event or LMS message.
    - **F8** The `@AuraEnabled` parameter passes straight into the ConnectApi input in one method;
      the admin guide warns against entering keys while a trace flag is on; BarnCRM never enables
      namespace FINEST logs in subscriber orgs; production is supported on the managed package.
    - **F9** BarnCRM never creates an Auth Provider: the admin creates it in Setup from the page's
      guidance, so client secrets never pass through BarnCRM.
    - **F10** Password input with `autocomplete="new-password"`, never prefilled, cleared after
      every call, kept out of tracked state, storage, URLs, events and LMS; the write method is not
      cacheable and returns no secret; no `console.log`.
    - **F11** Replacing a key writes an Admin Journal entry (who and when, no value), shows the
      account the check call returns where available, and Health Check lists keys changed in the
      last 7 days.
    - **F12** The "BarnCRM Connections" permission set is assigned only to holders of
      `BarnCRM_Connector_Admin` and the recipe identities, never to client-supplied Ids, and Health
      Check warns if it holds anything but principal access.
    - **F13** The header token above; payload values are subject to F1; the guest permission set
      holds only the REST class and create on the start event.

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
- **Runs as the admin who turned recipes on (Scheduled Apex):** rejected by Brandon (D-215):
  recipes would stop when that admin left or lost permissions.
- **Integration User as the only option:** survives staff changes, but needs a license, a user to
  create and a Tooling API write, too much for a default; kept as a choice.
- **System mode by default:** the simplest identity that never breaks, but it drops CRUD and FLS for
  every recipe; kept as an explicit per-recipe choice.

## Consequences

- An admin connects an app, picks a template, tests it with a sample and turns it on without Flow
  Builder; one guided Setup click per connection remains, and OAuth apps need an app at the
  provider.
- Record-change recipes can lag up to 15 minutes (polled at most every 15, checked by a 5-minute
  heartbeat); the Flow action gives immediate starts.
- Recipes survive staff leaving and staff permission changes. Created By and Last Modified By show
  Automated Process or the integration user; Run History ties each written record to its recipe,
  version and publisher. Anyone who can publish recipes acts with the chosen identity's access, so
  publishing and Run As are limited to `BarnCRM_Connector_Admin`.
- A deactivated integration user stops its recipes until another is chosen, and a deactivated
  record owner makes creates fail; Health Check reports both.
- The suite reaches 199 of 200 objects; the next object anywhere needs a cut.
- Page entry is no weaker than Setup entry once decision 11 holds, and narrower in one way (only
  `BarnConn_` credentials can be written). Residual risks, accepted: a FINEST trace on the person
  entering a key (F8); secret URLs readable in Setup (F5); administrators with Modify All Data,
  Author Apex or `ManageNamedCredentials` can use or swap any connection (inherent to Named
  Credentials; F11 makes a swap visible); a stolen webhook token creates runs, bounded by caps and
  fetch back.
- OAuth connections need one more guided Setup step (the Auth Provider, F9).
- To confirm on the first org deploy (design Section 3.11): cross-credential `$Credential`
  resolution (decides whether F1 is Critical), the permission each ConnectApi credential method
  requires, whether `callout:` suffixes can change the host, whether the Setup Audit Trail records
  Named Credential URLs, what `getCredential` returns for encrypted values, whether subscriber
  FINEST traces show namespaced variable assignments, `createCredential` for Custom protocol
  principals, `SetupEntityAccess` inserts for principals, `callout:` to a subscriber-created Named
  Credential from namespaced Apex, a `PermissionSetAssignment` to the Automated Process user (and
  that `USER_MODE` and callouts honor it), an Integration-licensed user as an event trigger's
  running user, and that trigger's behavior once the user is deactivated. Each has a stated
  fallback; if the Automated Process assignment is refused, Integration User becomes the
  recommended default and System stays an explicit choice.
- Workato features left out (SFTP, databases, agents, streams, code steps, synchronous APIs) are
  listed in the design with what to do instead.
