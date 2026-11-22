# Integration Hub Design: the Mapper and BarnCRM Connector

**Status:** Approved with amendments (D-216, 2026-11-20); the build follows Section 7
**Date:** 2026-11-20
**Approval (D-216):** Brandon, 2026-11-20: "The Mapper and Connector designs are approved with
the excepts of: make a module specific console app for Connector, it needs to be able to send
info back (such as through a webhook connection), and the premade system integrations should be
templates that can easily be imported (but not already loaded into Salesforce in order to prevent
unnecessary tech debt and solution bloat) and those templates can wait to be built until later.
I'd also need some additional templates, such as GoFundMe Pro, and many others in the future. I'd
also like SFTP and direct database connections in the future but it doesn't need to be in the
first version. Event driven triggers (instead of every 15 minutes) should also be in a future
release." Section 8 lists where each exception is applied.
**Source:** Brandon, 2026-11-20: "I'd also like to create and integration/middleware module. I'd
like it to be similar to Workato in capabilities and super easy for a non technical user to setup
and use. Also, I'd like a UI feature to map objects and fields that can be reused for functions
like data import, transformations, automations, and integrations. I'd like it to be as easy or
easier/more intuitive to use as Salesforce's Flow/Data 360 transform screen. Please design,
build, and start integrating these now."
**Decisions:** ADR-0234 `0234-reusable-mapper.md` (the Mapper and the map document) and ADR-0235
`0235-integration-module.md` (the BarnCRM Connector module). Both cite this document.
**Builds on:** plan Section 1.3 (principles 1, 3, 4, 8), Section 4.2, Section 4.9, Section 9.9;
C-37, C-38, C-49, C-50, C-59, MIG-06; D-101, D-150, D-209; ADR-0013, ADR-0057, ADR-0081, ADR-0148,
ADR-0165, ADR-0166, ADR-0184, ADR-0197, ADR-0201, ADR-0227, ADR-0228, ADR-0229, ADR-0231.

Two pieces, built together:

- **The Mapper** (Core feature): one mapping screen and one documented JSON "map document",
  used by Super Importer, the Connector's recipes, a Flow action, and later Super Transformer and
  the gift mirrors.
- **BarnCRM Connector** (new optional module, both editions, Beta): Connections, Recipes (a When
  and a list of Then steps) and Runs, so a non-technical admin can move data between BarnCRM and
  other apps without Flow Builder, Apex or a paid iPaaS.

The canonical model additions are drafted in Appendix A of this document rather than in
`canonical-model.md`, because that file has no Proposed marking convention; the first build slice
copies them in before any metadata (canonical model rule 1).

---

## 1. Baseline, Steelman and What the Baseline Fails to Do

### 1.1 The Baseline (adds nothing new)

- **Salesforce Flow**: record-triggered flows with an asynchronous path, scheduled flows, the HTTP
  Callout action (an External Service generated from a sample JSON), Named Credentials and
  External Credentials, the Transform element for mapping collections, fault paths and the paused
  and failed interview list.
- **BarnCRM today**: Super Importer templates (R-IT1 mapping documents with transforms, matching
  and lookups), Super Transformer, Saved Step Lists, the Inbound Gift API (ADR-0051), the Payments
  webhook receiver (ADR-0201), Flow templates (ADR-0090), the Error Log and Nightly Jobs.
- **External iPaaS**: Zapier (BarnCRM documents recipes, MIG-06), Make, n8n, Workato.

### 1.2 Steelman of the Simpler Option

"Ship templates and docs, not a module": a few Flow templates that use HTTP Callout, one small
Apex REST receiver that turns any webhook into a platform event a flow can listen to, and Super
Importer's existing mapping step. That is perhaps 300 lines of Apex, no new objects, and every
run uses Salesforce's own engine, history and support. For an admin who already builds flows it
is enough, and it is the right answer for anything a flow already does well.

It is not chosen because it fails the named requirements below for the person the owner named:
a non-technical admin who should not need Flow Builder (principle 1).

### 1.3 Named Requirements the Baseline Fails

| ID | Requirement (what breaks without the new element) | Baseline gap |
|---|---|---|
| NR-1 | A non-technical admin sets up an integration without Flow Builder, Setup screens beyond one guided click, Apex or JSON schemas (principle 1, Section 2.3) | Flow HTTP Callout needs an External Service, a Named Credential and an External Credential set up in Setup, typed variables and Apex-defined types; principle 1 rules out "needs Flow Builder" |
| NR-2 | Receive data pushed by another app (webhooks) | Flow cannot receive a webhook; the steelman's receiver plus a flow per webhook still needs Flow Builder for every source |
| NR-3 | A run history per integration, with retry from the failed step, backoff on rate limits (HTTP 429) and automatic pause after repeated failures | Flow gives a failed interview email and a fault path; no per-run retry from the failed step, no backoff, no auto-pause |
| NR-4 | One saved map reused by import, automation and integration | Flow assignments and Transform elements live inside one flow; Super Importer mappings live inside one template; nothing is shared |
| NR-5 | Nothing paid for the organization | Zapier lists Salesforce as a premium app (paid plan; our own guide says so); Workato is a paid enterprise product; Make's free tier is capped; n8n is free only when the organization runs its own server; Data 360 transforms need Data 360, a paid add-on Section 4.2 forbids |
| NR-6 | BarnCRM-aware behavior: matching people by email or key, households, lookups by external key, undo where the import engine offers it, Automation Control respected | Generic tools know Salesforce objects, not BarnCRM's rules; each Zap re-builds matching by hand |
| NR-7 | Unattended scheduled imports that commit only inside admin-set limits (C-38) | Neither Flow nor iPaaS offers a dry run with commit limits |
| NR-8 | Configuration as JSON that ports to BarnCRM for WordPress (plan 9.9) | Flow metadata does not port |

What the design keeps from the baseline, on purpose: Named Credentials and External Credentials
hold every secret (ADR-0229); Flow stays a first-class way to start a recipe (a Flow action);
Scheduled Apex, Queueable Apex, the Error Log, Nightly Jobs, Health Check, the Site guest
pattern (ADR-0184) and the Super Importer engine are reused, not rebuilt.

### 1.4 What Is Deliberately Not Built (right-sizing)

- No formula or expression language anywhere: maps and recipes use paths and the closed step list
  of ADR-0081 (R-IT15). A request for one is a new ADR.
- No custom OAuth implementation and no secret storage of our own: External Credentials and Auth
  Providers do it.
- No connector code SDK: a connector is a JSON definition; generic HTTP is the only executor.
- No Change Data Capture, no Platform Event bus of our own, no Bulk API (Section 4.9 stands).
- No synchronous "respond with data" webhook API (the receiver answers at once with a fixed
  acknowledgement; anything computed is sent back afterwards by a step, Section 3.3a), no
  callable sub-recipes, no lookup-table object, no environment promotion beyond exporting and
  importing a recipe's JSON.
- No app connectors shipped in the package (D-216): only Generic REST is built in; every app
  connector is an importable JSON template, imported on demand (Section 3.6).
- No AI step (no paid AI API, Brandon's rule).

---

## 2. The Mapper (Core Feature)

### 2.1 Where It Lives

Core, because Super Importer is Core and the Mapper's first two consumers (Super Importer and the
Connector) span Core and a module. The screen and its logic are JavaScript: a framework-free model
module (`mapDocument`, no `lightning/*` or `@salesforce/*` imports, plan 9.9) and one component
(`barnMapper`). Core Apex grows only by the save checks and the preview call (Section 7.2). The
map **runtime** for records and JSON (paths, lookups, building a record or a JSON body) lives in
the Connector module, not Core: Super Importer and Super Transformer keep their existing,
tested runtimes and read the parts of a map they support.

### 2.2 The Map Document (extends ADR-0081 and R-IT1)

A map document is the R-IT1 mapping document, version 4, with three optional additions. Every
existing template document (versions 1 to 3) is already a valid map document whose source is file
columns and whose target is the template's entities, so nothing is migrated.

```json
{
  "version": 4,
  "from": { "kind": "json", "label": "Eventbrite attendee", "sample": { "profile": { "email": "a@b.org" } } },
  "to": { "kind": "record", "object": "Contact" },
  "columns": [
    { "source": "profile.email", "target": "Record.Email", "transforms": [{ "op": "trim" }, { "op": "lower" }], "required": true },
    { "source": "profile.last_name", "target": "Record.LastName", "transforms": [{ "op": "proper" }] },
    { "source": "order.company", "target": "Record.AccountId", "lookup": { "object": "Account", "field": "Name", "notFound": "leaveEmpty" } }
  ],
  "defaults": [{ "target": "Record.LeadSource", "value": "Eventbrite" }],
  "match": { "by": "field", "field": "Email", "several": "reject", "none": "create" }
}
```

| Key | Values | Meaning |
|---|---|---|
| `from.kind` | `columns` (a file; the default), `record` (fields of one object, `from.object`), `json` (a payload; `from.sample` is an example kept for the screen, at most 20,000 characters) | What the source looks like |
| `to.kind` | `record` (fields of `to.object`; the default), `json` (an outbound body; targets are paths) | What the map produces |
| `columns[].source` | A file column name, a field API name (one lookup hop allowed: `Account.Name`), or a JSON path: dot-separated keys, `[n]` for a list item, at most 10 parts | Where the value comes from |
| `columns[].target` | `Entity.Attribute` as in R-IT1 (`Record.<field>` for one object), or a JSON path when `to.kind` is `json` | Where it goes |
| `columns[].transforms` | The closed step list of R-IT15, unchanged | How the value changes |
| `columns[].value` | Literal text used instead of a source (a fixed value for this target) | A constant |
| `columns[].required` | Boolean | The Mapper and the dry run flag a blank result |
| `columns[].lookup` | `{ object, field, notFound: reject or leaveEmpty }`, the R-IT13 lookup generalized from `lookupField` (which stays valid) | Find the parent whose `field` equals the value and write its Id |
| `defaults` | As R-IT1 | Values for targets the row leaves blank |
| `match` | `by`: `id`, `field` (text, email or phone), `externalId`, `duplicateRules`; `field`; `several`: `reject` or `newest`; `none`: `create`, `skip` or `reject` | How a record target finds an existing record (R-IT2, R-IT8, R-IT9, R-IT16 semantics) |

Rules: at most 200 columns and 50 defaults; a path names data, never code; nothing is evaluated
(ADR-0081 decision 2 holds). Checked on save (unknown key values, oversized lists, transform
problems via `DataTransform.problems`), forgiving on read (a broken column is skipped and the
screen says so). Field names are checked against describe as the person when the map is loaded,
previewed and run, never trusted from the document (the R-ST3 pattern).

### 2.3 Saved Maps (no new object)

A saved map is a `Saved_Transform__c` row with a new `Kind__c` of Map (the default, Step List, is
every existing row). `Object_Name__c` holds the target object; `Definition_JSON__c` holds the
map document. This follows ADR-0227 (merge kinds instead of adding objects) and ADR-0231 (store
definitions as JSON). Maps are org-wide; creating, renaming and deleting one needs Manage
BarnCRM Settings.

How tools reuse a map:

- **Linked** (Connector recipes, the Flow action): the recipe stores the map's key; editing the
  map changes every recipe using it. The Mapper says "Used by 3 recipes" before a save, from
  Where Used. A run records the map version it used.
- **Copied** (Super Importer templates, Super Transformer): "Use a Saved Map" copies the map into
  the tool's own document and "Save as Map" saves the tool's mapping as a map. The template keeps
  its own copy, so R-IT1 behavior and a running import never change underneath anyone.

### 2.4 UX (what the admin sees)

One screen, three panes on a wide screen, stacked on a phone:

1. **From** (left): the source fields, each with two or three real values from the sample (the
   C-49a pattern). Sources: a file's first rows, a record chosen with a search box, a pasted or
   received JSON sample shown as a tree with plain labels ("profile, email"), or the last data a
   recipe's trigger received.
2. **To** (middle): the target fields grouped as Required, Suggested and All, with the
   type-to-search picker (`importFieldPicker`). Each row reads as a sentence: "Email gets
   profile, email, then trimmed, then lower case."
3. **Preview** (right): the record (or JSON body) the sample produces, value by value, with a
   badge on each problem: required and blank, too long for the field, not a number or date,
   picklist value not in the list (with a one-click "Map These Values" step), lookup not found.

How it beats Flow's assignment and transform screens for Maria:

- **Auto-match on open.** Exact names after normalization first (C-49a), then likeness
  (`fieldSuggest`, the C-49e scorer) with the amber "Best guess, check it" badge that must be
  accepted (D-150). Flow's assignment screen starts empty.
- **Real values everywhere.** Every source shows sample values and the preview shows the result
  before anything runs; no debug run needed.
- **Plain-language changes instead of formulas.** The existing step editor
  (`importColumnTransforms`) with sentences: Trim Spaces, Capitalize Words, Replace, If Blank Use,
  Map Values, Format Phone, Read Dates As, Take Part, Shift Date, Today.
- **Drag or pick.** Drag a source onto a target with `c/barnDrag` (pointer and keyboard), or click
  Pick; drag is never the only way.
- **Lookups and matching in one sentence each:** "Find the Organization whose Name is order,
  company; if none, leave it empty." "This is an existing person when Email matches; if several
  match, skip the row." Each with the R-IT2 risk sentence.
- **Defaults** as "When blank, use".
- **Check Before Running:** a server dry run of the map over up to 200 sample rows, records or
  payloads, listing problems by field. Nothing is saved.
- **Saved and reusable** with Where Used, which Flow assignments are not.

### 2.5 Adoption Order (no capability removed)

1. **Connector recipes** (first consumer: new, so no regression risk).
2. **Super Importer: Save as Map and Use a Saved Map** in the Check Columns step.
3. **Automations:** the Flow action "Apply BarnCRM Map and Save" (Connector module).
4. **Super Importer's Check Columns step rendered by the Mapper**, only after a parity checklist
   passes (example values, field groups, Do Not Load, new-field creation C-49d, row rules,
   multi-object entities C-49c, related records R-IT17). Until then the Mapper is an extra view.
5. **Super Transformer: Apply a Map** whose source and target are the records being changed
   (field copies with steps, within the R-BU1 limit of five changes).
6. **Gift mirrors** (Fundraising, ADR-0228): extra field copies from Gift to Opportunity, edited
   in the Mapper. Today the mirror's field map is fixed in code; this adds, never replaces.

---

## 3. BarnCRM Connector (New Module)

### 3.1 Concepts in Plain Words

- **Connection:** a saved, checked sign-in to another app ("Mailchimp, main account"). The secret
  lives in Salesforce's credential store, never in a BarnCRM record.
- **Recipe:** "When this happens, then do these steps." One When, up to 25 Then steps.
- **Run:** one time a recipe ran, with each step's result, so the admin sees what happened, why it
  failed and can retry it.
- **Map:** the Mapper's saved map, used by steps that write a record or build a request body.
- **Template:** a JSON file the admin imports (from a file or pasted) that fills in a new
  connection and draft recipes for one app. Never preloaded (D-216, Section 3.6).

Tab **Super Connector** with four sections (`barnTabs`): Recipes, Connections, Run History,
Templates (the import). Each section arrives with the slice that builds it; CN-01 ships
Connections alone.

**In BarnCRM Admin Console (ADR-NEXT, nine console apps).** The module ships no app: the Super
Connector tab joins BarnCRM Admin Console, before Error Log, through the module's catalog row
(`Admin_Tabs__c`, ADR-0137). Tab visibility is in `Connector_Admin` and `Connector_Viewer` (the
module has no Staff set; Connector work is admin work, R-CR3).

### 3.2 Triggers (the When)

| Trigger | How it works | Why this mechanism |
|---|---|---|
| **On a schedule** | Every 15 minutes, hourly, daily at a time, or weekly | The recipe clock (below) |
| **When a record is created or changed** | Polls any queryable object every 15 minutes: `SystemModstamp` (or `CreatedDate`) after the recipe's watermark, with an optional Find filter document (R-R2), ordered by stamp then Id, at most 200 records a tick (recipe setting); one run per record, or one run with the list ("batch") | See below |
| **When another app sends data** | Inbound webhook to a Site guest REST endpoint with a per-recipe token (Section 3.3) | Only way to receive pushes without an API user |
| **When an app has new items** | Polls a connector's list endpoint with a watermark (for example Eventbrite attendees changed since, Mailchimp unsubscribes since) | For apps whose webhooks need a secret check Apex may not hold (Zoom), or that have none |
| **Manually or from a Flow** | Run Now on the recipe; the Flow action "Run BarnCRM Recipe" queues a run with record Ids | Lets an admin who uses Flow get an immediate trigger without the module depending on Flow |

**Record changes: polling, not the trigger framework or Change Data Capture.**

- *Trigger framework* (ADR-0165): covers only objects with a BarnCRM trigger (BarnCRM objects,
  Contact, Account), adds cost to every save in Core, and callouts cannot run in a trigger anyway,
  so a queue is needed regardless. Core would also have to name the module (it may not).
- *Change Data Capture*: an Apex change-event trigger must be deployed per object (the ADR-0138
  problem), each object must be selected in Setup, and editions include five selected entities
  before a paid add-on.
- *Platform events*: BarnCRM would still need a trigger per object to publish them.
- *Polling* works on every object, the org's own included, needs no metadata per object, catches
  imports and bulk updates, and resumes from the watermark after an outage. The cost is up to 15
  minutes of delay, the same order as Workato's own polling triggers. Deletes are not seen
  (a later option: an `ALL ROWS` poll of `IsDeleted`).
- *Loop guard:* "Ignore changes made by recipes" is on by default: records last changed by a
  recipe identity (Section 3.10) are skipped, so a recipe that writes to the object it watches
  does not trigger itself.
- *Event-driven triggers are a future release (D-216):* the first version polls. The owner wants
  record changes to start recipes as they happen instead of every 15 minutes; that is on the
  Later list (Section 7.2), designed when it is slotted. The likely shape is the ADR-0138
  generated trigger the admin deploys per object, publishing to the run queue (callouts still
  run in the runner), with Change Data Capture weighed against its five-entity allocation.

**The recipe clock (no scheduled job, no person).** Scheduled Apex runs as the user who scheduled
it and fails once that user is deactivated, so the clock is not a CronTrigger. Turn On Recipes
publishes a platform event; its Apex trigger runs as a recipe identity (Section 3.10), not as the
person pressing, and enqueues a heartbeat Queueable that re-enqueues itself with a 5-minute delay
(`System.enqueueJob` takes a delay of 0 to 10 minutes). Asynchronous Apex runs as the user who
enqueued it, so the heartbeat and every run it starts keep that identity. Each beat queues the
recipes that are due and starts the runner chain for each identity. A Transaction Finalizer
re-enqueues a beat that failed; any webhook post, Flow action or Run Now also publishes the event,
which restarts a missing heartbeat; and a Nightly Jobs step checks it. Health Check reports a
stopped heartbeat with a Restart button.

### 3.3 Inbound Webhooks: Security Analysis

Endpoint: `POST <site URL>/services/apexrest/barncrm/connector/v1/hook?token=<64 hex>`.

- **Guest only stores** (ADR-0184, ADR-0201): the receiver inserts one Run, Received, in system
  mode, publishes the start event (the guest permission set grants create on that event only), and
  makes no callout, no record read and no processing. The recipe's identity (Section 3.10)
  processes it later.
- **Token:** 256 random bits (`Crypto.generateAesKey(256)`), shown once with Copy and stored only
  as its SHA-256 hash on the recipe (`Webhook_Token_Hash__c`, unique). The receiver hashes the
  presented token and finds the recipe by the hash, so no token is stored and a read-only user who
  can see the recipe cannot rebuild the URL. Regenerate Token (confirmation first) replaces it.
  Missing or unknown token: 404 with an empty body, nothing stored.
- **Token in a header where possible (F13).** The receiver accepts the token in an
  `X-BarnCRM-Token` header, and the page shows that form first for apps that allow custom headers,
  because a query string can appear in the sender's logs, proxies and Event Monitoring URI fields.
  The `?token=` form stays for apps that cannot send headers.
- **Bounds:** JSON or form-encoded bodies only, at most 131,072 characters (413 otherwise); an
  hourly cap per recipe (default 500, recipe setting) whose first refusal each hour writes one
  Warning to the Error Log; a paused recipe still stores posts (up to its cap) and processes them
  when resumed, and a draft recipe answers 404.
- **Duplicates:** a connector or recipe may name an event id path; the run's unique `Event_Key__c`
  drops a resend, answered 200.
- **Untrusted payload:** a post can only do what the recipe's steps do, with the recipe's identity
  and access mode (Section 3.10), never more. Where the sending app offers it, the connector's **fetch back** option
  reads only an id (or a resource URL whose host must equal the Connection's host) from the post
  and fetches the real data through the Connection, so a forged post with a stolen token cannot
  inject data (the ADR-0229 Stripe pattern; Eventbrite sends an `api_url` exactly for this). The
  posted URL is parsed under the F4 rules (Section 3.5): `https`, no user info, the connection's
  exact host and port, and only its path and query appended to `callout:`. When a connector
  offers fetch back, the page recommends it for webhook recipes that write records.
- **Payload values are untrusted text for F1:** a `{!` in any payload value that reaches a
  request fails that step (Section 3.5).
- **No signature checks:** an HMAC check would need Apex to read a signing secret, which ADR-0229
  rules out. Token, fetch back, caps and idempotency replace it. Apps that refuse to deliver
  without a secret-based handshake (Zoom's URL validation) use the polling trigger instead.
- **Guest access:** a `Connector_Webhook_Guest` permission set with the REST class and
  create on the start event only (no Connections controller, no principal access: the receiver
  makes no callout), assigned to Site guest users by the existing Health Check fix. A Site is needed (most orgs with
  Payments or Forms have one); the Settings tab says how to create one.
- **Logging:** the token never appears in a log, run or error message.

### 3.3a Sending Data Back (D-216)

The owner's condition: the Connector "needs to be able to send info back (such as through a
webhook connection)". Two ways, split by what can be synchronous.

**1. The reply to the app that posted (synchronous, fixed).** The receiver answers in the same
request, inside the Site guest REST transaction (synchronous limits: 10 seconds of CPU, 6 MB of
heap, and most senders' own timeouts of 3 to 30 seconds). Because the guest only stores (ADR-0184,
Section 3.3), the reply can hold only what is known without processing:

| Part | What the recipe can set | Default |
|---|---|---|
| Status code | 200 or 202 | 202 |
| Body | A fixed JSON reply typed on the recipe (at most 4,000 characters, checked on save; `{!` refused, F1), with one optional placeholder for the run reference | `{"received": true, "reference": "<run reference>"}` |
| Challenge echo | The name of one top-level field of the posted JSON (or query parameter) whose value is echoed back as the body, for apps that confirm an endpoint by echoing a value they sent (no secret involved) | Off |
| Run reference | An opaque 20-character reference stored on the run, so the app and Run History can be matched | Always present |

What it cannot do synchronously: return a record, a computed value or the result of a step.
Refused inputs keep Section 3.3's answers (404 empty, 413, an hourly cap refusal as 429). The
reply adds one small string to the response, so the receiver's cost is unchanged: one hash
lookup, one insert, one event publish.

**2. Sending results back after processing (asynchronous, through a connection).** Anything a
recipe computes goes back by a step in the runner, never in the guest's request:

- **Send to Webhook** (`sendWebhook`, new step, Section 3.4): POSTs a JSON body built from a map
  to a connection. A webhook URL that is itself the secret is a Secret URL connection (F5); any
  other webhook is a Generic REST connection. It runs under the same rules as Call an App: the
  `{!` guard on every header, path, query and body value (F1), the path rules and URL encoding
  (F4), the body serialized with `JSON.serialize`, transient failures retried (Section 3.7).
- **Reply to a callback URL the caller sent.** Some apps put a reply address in the post (a
  `response_url`). That URL is untrusted: Send to Webhook may use it only through a chosen
  connection, parsed exactly as fetch back is (F4: `https`, no user info, the connection's exact
  host and port, and only its path and query appended to `callout:`); any other host fails the
  step. The posted URL is never the endpoint.
- **Call an App** already writes back to an app's API (update the item that started the run).

Timing: a reply step runs when the runner reaches it, normally within a minute of the post (the
start event restarts the runner chain at once), and later under retries or backlog. An app that
needs a synchronous computed answer is out of scope (Section 4.1).

### 3.4 Actions (the Then steps)

| Step | Plain name | What it does |
|---|---|---|
| `find` | Find Records | A Find query document (R-R2) with values from earlier steps; returns up to 200 records; "stop if none" option |
| `create`, `update`, `upsert` | Create, Update, or Create or Update a Record | Applies a map (linked or inline) to build the record; upsert uses the map's `match`; `Database` DML in user mode with partial success off per run |
| `callApp` | Call an App | A connector action, or a custom request on a generic connection: method, path (F4 rules), query, non-secret headers (never `Authorization` or a `{!` value, F1), body built from a map (`to.kind` json, serialized with `JSON.serialize`, never by string substitution), expected success codes, "404 means not found" option |
| `sendWebhook` | Send to Webhook | POSTs a JSON body built from a map to a connection, or to a callback URL from the trigger that matches that connection's exact host (Section 3.3a, F1, F4); expected success codes |
| `transform` | Change Data | Applies a map with `to.kind` json to produce a new data object for later steps |
| `if` | If | A condition (filter document over trigger and step data) with Then steps and optional Otherwise steps; nesting at most 2 levels |
| `forEach` | For Each | Runs its steps once per item of a list from an earlier step, at most 1,000 items a run, checkpointing every 200 |
| `wait` | Wait | Pauses the run for minutes, hours or days; resumed by the clock (5-minute granularity) |
| `importRows` | Load Rows with an Import Template | Hands rows (from Google Sheets, a CSV at a connection, or a list from an app) to Super Importer staging with a template, runs the dry run, and commits only inside the recipe's limits (C-38) |
| `stop` | Stop | Ends the run as Succeeded, Skipped or Failed with a message |

Values from earlier steps are "data pills": paths such as `trigger.record.Email` or
`steps.s2.body.members[0].id`, chosen from a picker that shows sample values. Paths only, no
expressions.

### 3.5 Connections

Every connection is an External Credential plus a Named Credential, both created by BarnCRM at
run time with `ConnectApi.NamedCredentials` (`createExternalCredential`, `createNamedCredential`)
and named `BarnConn_<connector>_<6 random>` by the server only (F2); the admin's display name is
the label. There is no Connection object: the Connections section lists the org's External
Credentials with that prefix. `BarnConn_` names are subscriber names and never go through
`NamespaceUtil.qualify`.

The independent security review (`connector-secrets-security-review.md`, findings F1 to F13)
found page entry "secure with required mitigations". Each mitigation below is a binding
requirement, marked with its finding, and the slice that builds it carries its tests (Section 7).

Authentication kinds, from the connector definition:

| Kind | Setup the admin does | Example |
|---|---|---|
| API key or token in a header | Paste the key on BarnCRM's page | Mailchimp (Basic over any user and the key), Eventbrite (Bearer) |
| Basic user and password | Paste both | Older REST APIs |
| Secret URL | Paste the webhook URL. It becomes the Named Credential's URL, which is configuration, not an encrypted credential: administrators who can view Setup can read it (F5) | Microsoft Teams Workflows; Slack incoming webhook as the simpler alternative to a Slack bot token (Bearer, encrypted), which is recommended |
| OAuth 2.0 client credentials | Paste client id and secret (External Credential's native flow) | Many server-to-server APIs |
| Token step | Paste client id and secret; the connector's sign-in call returns a short-lived token held for one transaction (the PayPal pattern of ADR-0229) | Zoom Server-to-Server OAuth |
| OAuth 2.0 browser sign-in | Create an app at the provider (BarnCRM shows the callback URL and the scopes to tick); create the Auth Provider in Setup, pasting the client id and secret into Setup's own form (guided, F9); BarnCRM then creates the External Credential and Named Credential that reference it (no secret involved); then one Authenticate click | Google Sheets, Constant Contact, QuickBooks Online |

CN-01 builds API key in a header, Bearer token, Basic and Secret URL. OAuth client credentials,
the token step and OAuth browser sign-in arrive with the first template that needs each
(Section 7.2), so no unused kind ships.

Headers use merge formulas (`{!$Credential.BarnConn_x.ApiKey}`, Allow Formulas in HTTP Header
on), so Apex never reads a stored secret (ADR-0229 decision 1). The auth header template comes
only from the catalog's auth kind; Generic REST builds it from the auth kind, never from free text
(F1).

**Honest list of steps a non-technical admin must still do in Setup**, each shown on the page with
the exact clicks and a Check Again button (the ADR-0148 amendment A1 pattern):

1. **Enabled for Callouts, once per connection.** A Named Credential created through `ConnectApi`
   starts with callouts off and no API property turns them on (ADR-0148 A1). Setup, Named
   Credentials, the connection, Edit, Enabled for Callouts, Save.
2. **Authenticate, once per OAuth browser connection** (and again if the provider revokes it):
   Setup, Named Credentials, External Credentials, the connection, Principals, Authenticate.
   Salesforce does not let a package start this sign-in from its own page.
3. **At the provider, for OAuth browser connections:** register an app and copy two values. No
   shared BarnCRM app is offered: it would be a service BarnCRM runs and a client secret shipped
   to every org (self-service only; nothing paid).
4. **The Auth Provider, once per OAuth browser connection** (F9): Setup, Auth. Providers, New,
   with the provider type, callback URL and scopes the page shows, and the client id and secret
   pasted into Setup's form. BarnCRM never creates an Auth Provider, so the client secret never
   passes through BarnCRM's Apex, a queued job or a Metadata API call.
5. **A Salesforce Site**, only for webhooks, once per org.

The secret itself (for the other kinds) is pasted on BarnCRM's page and written to the principal
with `ConnectApi.NamedCredentials.createCredential` or `updateCredential`. This differs from
ADR-0229 decision 5 (packaged providers' secrets are entered in Setup) and is approved under
D-215 with the requirements below.

**Binding requirements for page-entered secrets (security review F1 to F13):**

- **F1 Merge-field injection guard.** Every Connector Named Credential is created with Allow
  Formulas in HTTP Body off, and the catalog schema cannot turn it on. Only the catalog's auth
  header template may contain `{!`. After building a request and before `send`, the executor
  fails the step with a fixed message if any header name or value, path, query value or body
  string that came from recipe configuration, data pills, webhook payloads, app responses or
  records contains `{!`. Saving a recipe or map whose literal values contain `{!` is refused.
- **F2 Only BarnCRM's own credentials.** The server generates every new name; the client never
  supplies one for creation. Update, Disconnect and Delete accept only a name that starts with
  `BarnConn_`, exists in the org's External Credential list and is linked to a Named Credential
  with the same prefix; anything else (for example `Barn_Stripe`, `Barn_PayPal`,
  `Barn_Org_Connection`) is refused before any ConnectApi call. Principal and parameter names
  come from the catalog, never the client.
- **F3 Who may write, and how.** Every credential-writing method first checks the custom
  permission `Manage_BarnCRM_Connector` and that the user holds `ManageNamedCredentials` or
  Customize Application (a `PermissionSetAssignment` query, as `BarnCRMPermissions` does), and
  refuses in plain words otherwise. The ConnectApi call runs synchronously in that request, as
  that user: a secret is never queued, scheduled, published or handed to a recipe identity or any
  system-context path. The controller is granted only by `Connector_Admin` (never the
  guest set or a user-level set) and its page is in the internal app only, with no Visualforce
  page or REST resource exposing the write.
- **F4 Hosts cannot move.** Base URLs must be `https://`. A connection's scheme and host are
  immutable once a secret is stored: changing them means a new connection with the secret entered
  again, or one call that replaces URL and secret together, never the URL alone. Catalog
  connectors lock the host to the catalog pattern (Mailchimp's `{dc}` must match
  `^[a-z]{2}[0-9]{1,3}$`). Every path appended to `callout:` starts with `/`, does not start with
  `//`, and contains no `@`, `\`, `{!`, CR or LF; each value inserted is URL-encoded. Fetch back
  parses the posted URL with `System.Url` and requires `https`, no user info, and the
  connection's exact host (case-insensitive) and port, then calls `callout:` plus that URL's path
  and query only; the posted URL is never the endpoint.
- **F5 Secret URLs are configuration.** Page text, guide and ADR say plainly that a secret-URL
  connection is stored as the Named Credential's URL and is visible to administrators who can
  view Setup. The URL is never returned to the client (the list shows host and last four
  characters); runs store the step's path, never the full URL. Slack recommends a bot token
  (`Authorization: Bearer` to `chat.postMessage`, an encrypted principal) with the incoming
  webhook as the simpler alternative; Teams Workflows keeps the disclosure. If the Setup Audit
  Trail records Named Credential URLs, the Setup Changes copy masks them.
- **F6 Encrypted, never read back.** Every secret parameter (key, token, password, client secret)
  is written with `encrypted = true`; only non-secret ids (client id, user name) may be `false`.
  BarnCRM never calls `getCredential` to return values; the list and edit form return names,
  labels, host, auth kind and status only, and the secret box is always empty ("Replace Key").
- **F7 Nothing echoes a secret.** Credential-writing methods catch every exception and log a fixed
  message plus the exception type only, after replacing any occurrence of the secret (and each
  secret part) with `****`; the raw exception never reaches `ErrorLogger.log`, `logWithMessage`
  or `UserErrors.wrap`. No `System.debug` of inputs, credential inputs or callout requests in the
  module (AvoidDebugStatements stays unsuppressed). The secret is never a field on any object,
  setting, Admin Journal row, Setting Change row, Connector Run or platform event, nor an LMS
  message. Failed-step responses are stored only for catalog check calls and recipe steps, never
  for the credential write.
- **F8 One method, no copies.** The `@AuraEnabled` parameter goes straight into the ConnectApi
  input in one method, with no helper chain or wrapper class holding it. The admin guide says to
  enter keys only when no debug logging is active for you, and to replace a key entered while a
  trace flag was on. BarnCRM never enables namespace debug logs at FINEST in a subscriber org, and
  production is supported on the managed package only.
- **F9 Auth Providers only in Setup** (step 4 above).
- **F10 Browser handling.** `lightning-input type="password"` with `autocomplete="new-password"`,
  never prefilled; the value is cleared after the call returns, success or failure, and kept out
  of any tracked object, store, `localStorage`, `sessionStorage`, URL, LMS message or event; the
  write method is not `cacheable=true` and its response never contains the secret; no
  `console.log` in the module; Mailchimp's data center is derived in the browser and sent as a
  separate non-secret value.
- **F11 Key replaced is visible.** Replacing a key writes one Admin Journal entry "Connection key
  replaced" with who and when (no value); where the app's check call returns an account name or
  id, it is shown after Check Connection; Health Check lists connections whose key changed in the
  last 7 days.
- **F12 The "BarnCRM Connections" permission set.** BarnCRM creates one org-owned permission set,
  "BarnCRM Connections" (unpackaged, because a packaged permission set cannot be changed in a
  subscriber org), and adds each connection's principal to it. It is assigned only to users who
  already hold `Connector_Admin` and to the recipe identities (Section 3.10); user Ids
  never come from the client; Health Check warns when the set holds anything other than External
  Credential principal access.
- **F13 Webhooks:** Section 3.3.

Each connection has **Check Connection** (the connector's check call, or a HEAD/GET of the base
URL for generic), **Replace Key**, **Disconnect** (deletes the principal's credential, keeps the
recipe definitions, pauses recipes that use it) and **Delete** (refused while a recipe uses it).
What remains to confirm in an org is listed in Section 3.11.

### 3.6 Built-in Generic REST and Importable App Templates (D-216)

**Only Generic REST is built in.** Its definition (the auth kinds of Section 3.5, each kind's
principal, parameter names and auth header template) lives in the module's Apex, so the header
template can never come from a client or a file (F1, F2); the form rules (base URL, header
name, check path) live in a framework-free JS module the page and Jest share (plan 9.9).

**App connectors are templates, imported on demand, never preloaded (D-216).** No app connector,
template or catalog file is shipped as package metadata, static resource or record: an org holds
only what its admin imported, so nothing unused sits in Salesforce. A template is one JSON file
(downloadable from the BarnCRM website and repository, or pasted) that the Templates section
imports (CN-08, release 1.32):

1. The file is checked against the template schema (below) in the browser and again in Apex; a
   template can carry no `{!` anywhere, no auth header template (the auth kind names one of the
   built-in templates) and no Allow Formulas in HTTP Body option (F1).
2. Import fills in a new Generic REST connection: label, auth kind, header name, base URL and
   check path, with the base URL's host locked to the template's pattern (F4). The admin pastes
   the key as for any connection; nothing secret is ever in a template. The check path is kept
   with the connection (canonical model R-CN9), so Check Connection asks the app for it and
   shows the account the answer names (F11).
3. Import creates the template's recipes as Draft recipes with each blank highlighted (Section
   3.8). Actions the recipes use are copied into their Call an App steps, so a recipe never
   depends on the template file afterwards.
4. Nothing else is stored: the template file is not kept. Importing the same template again
   offers a new connection or reuse of an existing one.

The templates themselves are built later, one at a time (Section 7.2); the import mechanism comes
first. A template in the schema (the Mailchimp example):

```json
{
  "key": "mailchimp", "label": "Mailchimp", "version": 1,
  "auth": { "kind": "BasicAuth", "params": [{ "name": "Password", "label": "API key", "help": "Account, Extras, API keys" }] },
  "baseUrl": "https://{dc}.api.mailchimp.com/3.0",
  "urlParams": [{ "name": "dc", "label": "Data center", "pattern": "^[a-z]{2}[0-9]{1,3}$", "fromParam": "Password", "after": "-" }],
  "check": { "method": "GET", "path": "/ping" },
  "actions": [
    { "key": "upsertMembers", "label": "Add or update subscribers", "method": "POST", "path": "/lists/{listId}" }
  ],
  "recipes": [
    { "name": "Add new people to an audience",
      "draft": { "version": 1, "trigger": { "kind": "manual" }, "steps": [{ "id": "send", "kind": "callApp", "action": "upsertMembers" }] } },
    { "name": "Pull unsubscribes back",
      "draft": { "version": 1,
        "trigger": { "kind": "appPoll", "connection": "Mailchimp", "path": "/lists/{listId}/members",
          "query": [{ "name": "status", "value": "unsubscribed" }, { "name": "since_last_changed", "value": "{{watermark}}" }],
          "items": "members", "id": "id", "stamp": "last_changed", "mode": "each" },
        "steps": [] } }
  ]
}
```

`urlParams.fromParam` is the one exception where a non-secret part of a key (Mailchimp's data
center suffix) is read: the page derives it in the browser before the key is sent, so Apex still
never reads the key. In an App Poll trigger, a query value `{{watermark}}` becomes the value path
`trigger.watermark` (the stamp of the newest item already seen); any other `{{...}}` value is
refused. Template `pollers`, a `webhook` part, and action `inputs` (with pickers that call the
app to list choices) and `body` are planned: until they are built, import refuses a template
that has them and says which part, rather than dropping it.

**Template backlog** (built later, Section 7.2; value for effort for small organizations; more
will be added as asked):

| Order | Template | Auth | First recipes |
|---|---|---|---|
| 1 | Generic REST (built in, not a template) | Any kind above | Any |
| 2 | Slack (bot token recommended; incoming webhook as the simpler alternative) and Microsoft Teams (Workflows webhook) | Bearer token; secret URL with the F5 disclosure | Post a message when a record matches (a large gift, a new volunteer) |
| 3 | Mailchimp | API key | Add new or changed people to an audience; pull unsubscribes back |
| 4 | Google Sheets (C-38 source) | OAuth browser (Auth Provider type Google) | Load a sheet daily through an import template |
| 5 | Giving tools that send webhooks (Givebutter, Donorbox, Zeffy and similar) | Webhook token; fetch back where the tool has an API | Gift and person, replacing the paid Zapier path of MIG-06 (needs Fundraising) |
| 6 | Eventbrite | Private token | Attendees to people (and to Event Management registrations when installed) |
| 7 | Zoom | Token step (Server-to-Server OAuth) | Webinar registrants and attendance, by polling |
| 8 | Constant Contact | OAuth browser | As Mailchimp |
| 9 | QuickBooks Online | OAuth browser | Daily gift summary as a journal entry or sales receipts (needs Fundraising) |
| 10 | GoFundMe Pro (owner's request, D-216) | API key or OAuth client credentials, per its API; webhooks with fetch back where offered | Donations and donors to gifts and people (needs Fundraising) |
| Later | Others as organizations ask | Any built-in kind | Added as templates, never as package metadata |

A recipe template whose steps need Fundraising, Event Management or another module says so on
import and creates nothing when the module is missing.

### 3.7 Runs, Retries, Errors and Pause

- **Run statuses:** Received (webhook stored), Queued, Running (claimed for the next runner
  job), Waiting (a Wait step or a retry), Succeeded, Skipped, Failed.
- **Run detail:** each step's outcome, duration, record Ids written, HTTP status and a trimmed
  response (first 2,000 characters, kept only for failed steps), and the map version used. Headers
  are never kept.
- **Retries with backoff:** transient failures (callout exception, timeout, HTTP 408, 429, 500,
  502, 503, 504) retry at 15 minutes, 1 hour, 4 hours and 12 hours (recipe setting 0 to 4
  attempts), honoring a longer `Retry-After`. A retry resumes at the failed step: completed steps
  are recorded in the run's state and never repeated. Other failures fail at once.
- **Errors:** a failed run writes one Error Log entry (grouped by recipe, ADR-0055 digest). After
  10 failures in a row (recipe setting) the recipe pauses itself, says so on the recipe and in
  Health Check, and the digest names it.
- **Pause:** per recipe, and Pause All Recipes on the tab. A paused recipe stops polling and
  processing; its webhook posts are still stored, up to the cap, and Received runs wait for
  Resume. BarnCRM Automation Control "Pause All" (ADR-0165)
  also pauses every recipe.
- **Retry** a failed run, or **Retry All Failed** for a recipe, after fixing the cause.
- **Retention:** each recipe keeps runs for 30 days by default (7 to 365); a Nightly Jobs step
  (`NightlyStepProvider`, ADR-0166) deletes older runs.

### 3.8 Test Run, Templates and Versioning

- **Test** runs the draft on a sample: pasted JSON, a chosen record, or the last received payload.
  Record steps show what they would write and do not save; Call an App steps with GET run for
  real; other methods show the request that would be sent unless "Send for real" is ticked. The
  test result is a run marked Test. Test and Run Now run with the recipe's own identity and access
  mode (Section 3.10), so a test shows what the live recipe would be allowed to do, not what the
  person testing may do.
- **Templates:** imported on demand from a file or pasted JSON (Section 3.6, D-216), never
  shipped; import creates the connection form and Draft recipes, each blank highlighted.
- **Versioning:** a recipe has a published definition and a draft. Publish checks the draft,
  increments the version and keeps the previous definition for one-click Roll Back. Export and
  Import Recipe (JSON) move a recipe between a sandbox and production.

### 3.9 Where Used, Health Check and Other Core Seams

- **Where Used** (C-59): the module implements `WhereUsedExtension` (ADR-0057 pattern), listing
  recipes that name a field or object in maps, filters or Find steps, and recipes using a saved
  map or a connection. Retire a Field warns before a field a recipe writes is retired.
- **Health Check** (`HealthCheckExtension`): heartbeat running; each identity in use holds its
  permission sets (and, for the integration user, is active and set on its event trigger); a
  notice listing every recipe that runs in System mode, with who chose it and when; recipes whose
  record owner is inactive; connections enabled for callouts and checked; recipes paused by
  failures; Site guest permission set assigned.
- **Nightly Jobs:** the run cleanup step and the heartbeat check.
- **Module Manager:** a `BarnCRM_Module__mdt` row and the module's objects in
  `ModuleManagerService.ownedObjects`; the Integrations page (C-48) links to the Connector when it
  is installed.

### 3.10 Who a Recipe Runs As (owner decision D-215)

Brandon, 2026-11-20: "I'd rather recipes being able to be ran as system, integration user, or
non-user specific to avoid disruptions due to changed permissions or deactivated users." No
recipe runs as a staff member, so nobody leaving or changing roles stops a recipe.

Two separate questions decide what a run may do:

- **Identity:** who Salesforce sees (Created By, Last Modified By, default record owner, whose
  credential access a callout uses).
- **Access mode:** whether the run's object, field and sharing checks are applied (user mode) or
  skipped (system mode).

Each recipe has a **Run As** choice, one of three. The choice is per recipe, made by an admin on the
recipe's Settings card, shown on the recipe list, and recorded with who made it and when.

| Run As | Identity | Access mode | What it means for a non-technical admin |
|---|---|---|---|
| **BarnCRM Automation** (recommended default) | Salesforce's built-in Automated Process user, which belongs to no person and cannot be deactivated | User mode, limited to the permission sets the admin picks on the Settings tab (BarnCRM picks BarnCRM Admin and each installed module's admin set to start) | "Recipes run as BarnCRM itself. They can do what the permission sets you picked allow, nothing more. Nobody leaving or changing roles affects them. Records they change show Automated Process as the last changer." |
| **System** | Automated Process | System mode: no object, field or sharing checks | "Recipes can read and change any record and field in the org. Use only when a recipe must reach something the permission sets cannot grant." Needs an explicit choice with a confirmation sentence, and Health Check lists every System recipe |
| **Integration User** | One designated Salesforce user, ideally on a Salesforce Integration license | User mode, with that user's own permission sets | "Recipes run as a dedicated user named, for example, BarnCRM Integration. Changes show that name. It keeps working when staff leave, as long as nobody deactivates that user or removes its permissions." |

How each works on the platform:

- **Dispatch by platform event.** Two platform events, one per identity: `Connector_Start__e` (its
  trigger left at Salesforce's default, which runs as the Automated Process user) and
  `Connector_Start_User__e` (its trigger set to run as the integration user). BarnCRM Automation and
  System recipes share the first; the access mode is applied per recipe in code (`WITH USER_MODE`
  and `AccessLevel.USER_MODE`, or `SYSTEM_MODE` for System recipes). A platform event trigger cannot
  make a callout itself, so each trigger only enqueues that identity's heartbeat and runner chain,
  which keep the identity.
- **Setting the integration user.** Salesforce sets a platform event trigger's running user only
  through `PlatformEventSubscriberConfig` (Tooling or Metadata API); Setup only shows it and offers
  Suspend and Resume. BarnCRM writes it through the Core org connection of ADR-0148 (already
  required for Super Importer's new fields). Then one guided Setup step: Setup, Platform Events,
  BarnCRM Connector Integration User, Subscriptions, Suspend, then Resume, so the new user takes
  effect at once instead of after caching.
- **Credential access.** A callout through a Named Credential needs the running user to have
  access to the External Credential's principal (and, by community report, read on User External
  Credential), granted by a permission set. BarnCRM assigns its "BarnCRM Connections" set and the
  chosen sets: to the integration user with an ordinary assignment, and to the Automated Process
  user with a `PermissionSetAssignment` inserted from Apex, since Setup does not show that user.
- **Integration license.** Salesforce provisions five free Salesforce Integration user licenses in
  Enterprise, Unlimited and Performance editions (one in Developer Edition). The license is API
  only (no screens) and its permission set license, Salesforce API Integration, grants no object
  access by itself; access comes from permission sets. Orgs without it can use any user license.

What happens when things change:

| Event | BarnCRM Automation and System | Integration User |
|---|---|---|
| A staff member who set recipes up leaves | Nothing | Nothing |
| An admin edits a picked permission set | Recipes gain or lose that access; Health Check shows what each identity can reach | The same for the user's sets |
| The integration user is deactivated | Not affected | Its recipes stop; Health Check reports it, the recipes say "Integration user inactive", and runs wait until a new user is chosen (choosing one rewrites the trigger setting) |
| A package upgrade | Assignments to the Automated Process user are kept (they are org data); Health Check confirms them after each upgrade | Not affected |

**Record ownership.** Records a run creates default to its identity as owner. A record owned by the
Automated Process user is reachable by people only through sharing rules or View All, so a recipe
that creates records asks for an owner (a person or a queue where the object allows queues), with
the integration user suggested when there is one. An owner who is later deactivated makes creates
fail with a plain message, and Health Check names the recipe; ownership is the one place a person
can still matter, and the admin sees it.

**Audit.** Created By and Last Modified By show Automated Process or the integration user. The run
history ties every record Id a run wrote to the recipe, its version and the admin who published it,
so "which recipe changed this?" is answered from the record's Ids in Run History.

**New Setup steps:** none for BarnCRM Automation and System (if Salesforce refuses the Apex
assignment to the Automated Process user, a one-time guided fallback is shown, and System is
offered only by explicit choice). For Integration User: create the user and assign the
Salesforce API Integration permission set license (Setup, Users), then the Suspend and Resume
click above; BarnCRM assigns the rest.

To confirm on the first org deploy (Section 3.5 lists the connection checks): that an Apex
`PermissionSetAssignment` to the Automated Process user is accepted and honored by `USER_MODE`; that
the Automated Process user can call out through a principal it was granted; that a Salesforce
Integration licensed user can be a platform event trigger's running user; and what the trigger
does when that user is deactivated (assumed: it fails until changed, which Health Check catches).

### 3.11 Confirm on the First Org Deploy

Only an org test settles these; each has a stated fallback, and the F1 to F13 requirements hold
whatever the results.

| # | Check | Source | If it fails or is worse than expected |
|---|---|---|---|
| 1 | Whether `{!$Credential.Other_EC.Param}` resolves in a header of a callout to a Named Credential linked to a different External Credential | Review F1 | Treat F1 as Critical; the `{!` guard already blocks it, and the release notes say so |
| 2 | Which permission `createCredential`, `updateCredential`, `createExternalCredential` and `createNamedCredential` require (expected `ManageNamedCredentials`); a user with only the Connector permission set gets an error | Review F3 | Adjust the F3 pre-check to the permission found |
| 3 | Whether `callout:NC` plus `.attacker.net/x` or `@attacker.net/x` changes the host | Review F4 | The F4 path rules stay either way |
| 4 | Whether the Setup Audit Trail records Named Credential URLs | Review F5 | The Setup Changes copy masks them |
| 5 | That `getCredential` returns no clear value for an `encrypted = true` parameter | Review F6 | BarnCRM never calls it for values anyway; record the finding |
| 6 | Whether a subscriber trace flag at FINEST shows variable assignments in namespaced code | Review F8 | Admin guide warning stands; strengthen it if they show |
| 7 | `createCredential` writes a Custom protocol principal parameter | Section 3.5 | Guided Setup entry |
| 8 | `SetupEntityAccess` rows for an External Credential principal can be inserted from Apex (one write-up says no Apex path exists) | Section 3.5, review F12 | Guided Setup step adding each principal to "BarnCRM Connections" |
| 9 | Namespaced Apex can call `callout:` on a subscriber-created Named Credential | Section 3.5 | Blocks the design; must pass before CN-01 lands |
| 10 | An Apex `PermissionSetAssignment` to the Automated Process user is accepted, and `USER_MODE` and callouts honor it | Section 3.10 | Integration User becomes the recommended default; System by explicit choice |
| 11 | A Salesforce Integration licensed user can be a platform event trigger's running user | Section 3.10 | Any full-license user as the integration user |
| 12 | What the trigger does once its configured user is deactivated | Section 3.10 | Health Check already pauses those recipes |

---

## 4. Governor Limits and Scale

| Limit (asynchronous Apex) | Value | Design response |
|---|---|---|
| Callouts per transaction | 100 | The runner stops at 90 and chains |
| Total callout time per transaction | 120 seconds | Each callout times out at 30 seconds (connector may set up to 120); the runner stops at 100 seconds and chains |
| Callout after uncommitted DML | Not allowed | When a step needs a callout and the transaction has DML pending, the runner checkpoints the run and chains a new Queueable |
| Queueable chaining | One child per async transaction; no depth limit in production (5 in Developer Edition and trial orgs) | One runner chain at a time (checked through `AsyncApexJob`); test orgs note the depth cap |
| Asynchronous executions per 24 hours | The greater of 250,000 and 200 per user license | Many runs per execution; the heartbeat costs 288 a day per identity in use; the Settings tab shows the day's use |
| Heap | 12 MB | Responses over 4 MB are refused with a clear message; run state keeps only paths later steps use (computed at Publish) |
| HTTP response size | 12 MB | As above; connectors page large lists |
| CPU | 60 seconds | The runner stops at 45 seconds and chains |
| SOQL, DML statements, DML rows | 200, 150, 10,000 | Batch mode writes lists in one statement; For Each checkpoints every 200 items |
| Queueable delay | 0 to 10 minutes | The heartbeat waits 5 minutes between beats |
| Long text field | 131,072 characters | Webhook body cap; run state cap, else the run fails with "data too large" |

Throughput estimate: with two callouts of about half a second per run, one execution finishes about
45 runs, so a single chain handles thousands of runs an hour; enough for the target organizations.
Large one-off loads belong in Super Importer, which a recipe can call (`importRows`).

### 4.1 Workato Capabilities Apex Cannot Match, and What to Do Instead

| Capability | Why not in Salesforce Apex | Instead |
|---|---|---|
| SFTP, FTP, raw TCP | Apex has HTTP only, no sockets | First version: ask the source for an HTTPS export or API; drop files in Google Drive or Sheets; or a tool the organization already runs pushes to the webhook. Wanted later (D-216, Section 7.2): needs an HTTPS bridge, designed when slotted |
| Direct database connections (SQL Server, MySQL) | No JDBC or sockets | First version: the database's own REST layer, or a scheduled export to a sheet. Wanted later (D-216, Section 7.2), with the same bridge question |
| On-premise agent | No agent can run inside Salesforce | Same as above |
| Long-running jobs and streams (Kafka, long polling) | 60-second CPU and 120-second callout budget per transaction | Polling with watermarks and chained transactions |
| Files over about 4 MB through a recipe | Heap and response size | Super Importer for big files; paging APIs |
| Code steps (Ruby, JavaScript, Python) and formula mode | Evaluating admin-typed code is refused (ADR-0081) | The closed step list, conditions, maps; a new step is an ADR |
| Webhooks with secret-based signatures or handshakes | Apex must not read secrets (ADR-0229) | Token plus fetch back, or polling |
| Synchronous API endpoints (recipe answers the caller with data) | Guest only stores (ADR-0184) | A fixed synchronous acknowledgement, then Send to Webhook or Call an App sends results back (Section 3.3a); the Inbound Gift API or a module's own REST resource for true request and response |
| Sub-minute polling and high concurrency | A delayed-Queueable heartbeat, one runner chain per identity | 15-minute polling; Flow action for immediate starts; event-driven triggers later (D-216) |
| A thousand prebuilt connectors | A small project | Generic REST plus importable JSON templates anyone can write (Section 3.6) |
| Inbound email trigger | Possible (Email Services) but not needed now | A later trigger if asked |

---

## 5. Security Review Notes

- **User mode for data unless the admin chose System.** Every Find, create, update and upsert in a
  BarnCRM Automation or Integration User recipe runs `WITH USER_MODE` and `AccessLevel.USER_MODE`
  as the recipe's identity (Section 3.10). A System recipe's data steps run in system mode: that
  is an explicit, recorded admin choice per recipe, confirmed with a sentence saying it skips
  every object, field and sharing check, listed by Health Check, and named in the security review
  notes as a deliberate admin-only option. Otherwise system mode is used only for the module's
  own Recipe and Run rows (ADR-0021 pattern) and the guest's store, each entered in the
  without-sharing register.
- **Who a run executes as.** Never a staff member (D-215): the Automated Process user or the
  designated integration user, so whoever publishes a recipe acts with that identity's access.
  Publishing, and choosing Run As, need the custom permission `Manage_BarnCRM_Connector`, granted
  only by `Connector_Admin`, which the guide says to give only to system administrators.
  At Publish, a BarnCRM Automation or Integration User recipe's map targets and Find fields are
  also checked against the identity's describe, so the editor sees access problems before the
  first run.
- **Queries are documents, never text** (Section 4.9): Find steps and record-change filters go
  through `QueryCompiler` with bind variables; object and field names come from describe.
- **Callouts only through Named Credentials** (`callout:`), no Remote Site Settings; paths are
  built from the connector's template with each value URL-encoded; bodies are built as structures
  and serialized; a fetch-back URL must match the Connection's host (no server-side request
  forgery to other hosts).
- **Secrets never in records,** logs, runs, errors or responses; headers are never stored. The one
  exception is stated, not hidden: a secret-URL connection's URL is Named Credential
  configuration, readable by administrators who can view Setup (F5).
- **Page-entered secrets** follow the binding requirements F1 to F12 in Section 3.5: the `{!`
  injection guard and formulas in body off (F1), server-generated `BarnConn_` names only (F2),
  permission checks and synchronous ConnectApi writes as the person (F3), fixed `https` hosts,
  path rules and exact-host fetch back (F4), `encrypted = true` and no read-back (F6), redacted
  errors and no debug statements (F7), one-method pass-through (F8), Auth Providers only in Setup
  (F9), browser handling (F10), a journaled key replacement (F11) and the Connections permission
  set rules (F12). The independent review is `connector-secrets-security-review.md`; its data
  flow and findings go in the AppExchange security review submission with the Code Analyzer run.
- **Guest endpoint:** Section 3.3, including the header token (F13).
- **Personal data in runs:** inputs and state can hold personal data; retention defaults to 30
  days, failed-step responses are trimmed, and a later minor adds runs to the GDPR erasure path
  (delete runs that name the person's record Id or email).
- **Code Analyzer:** zero high or critical findings (plan non-negotiable); no dynamic SOQL from
  text, no `without sharing` outside the register, no hard-coded endpoints, no namespace strings.

---

## 6. Objects, Metadata and Naming

### 6.1 Names (approved, D-215)

- **Module:** BarnCRM Connector (D-101: modules are "BarnCRM <name>"), package folder
  `packages/connector`, module key `Connector`, Beta (N-14). Not "BarnCRM Integrations", which
  would collide with Core's Integrations page (C-48); not "BarnCRM Connect", Mirror's old name
  (ADR-0126).
- **Tab:** Super Connector, beside Super Importer and Super Transformer.
- **Core feature:** the Mapper; saved items are Maps.

### 6.2 Objects and Object Count

| Package | Item | Kind | Count effect |
|---|---|---|---|
| Connector | `Connector_Recipe__c` | Custom object | +1 |
| Connector | `Connector_Run__c` | Custom object (master-detail to Recipe) | +1 |
| Connector | No settings object: every option is per recipe; the identity choices (picked permission sets, integration user) are read back from the permission set assignments and the event trigger's configuration | none | 0 |
| Connector | `Connector_Start__e`, `Connector_Start_User__e` | Platform events (their own allocation, not custom objects, ADR-0227) | 0 |
| Connector | Connections | External and Named Credentials created at run time, not objects | 0 |
| Connector | Generic REST definition | Apex constants and a framework-free JS module; app templates are imported files, never shipped (D-216) | 0 |
| Connector | Super Connector tab in BarnCRM Admin Console | Catalog `Admin_Tabs__c` (ADR-NEXT, nine console apps) | 0 |
| Connector | `Connector_Webhook_Rest`, the runner, clock and controllers | Apex | 0 |
| Connector | `Connector_Admin`, `Connector_Viewer`, `Connector_Webhook_Guest` | Permission sets | 0 |
| Core | `Saved_Transform__c.Kind__c` | Field (picklist Step List, Map) | 0 |
| Core | `barnMapper` and `mapDocument` | LWC | 0 |

The suite goes from 197 to 199 custom objects (custom settings included), under the 200 an
Enterprise org allows for the full-suite gate (ADR-0227). This leaves one slot: the next object
anywhere in the suite needs another cut first. Rejected to save the second object: recipes as
Salesforce Files (ADR-0231 style); a recipe carries mutable state (status, watermark, token hash,
failure count) the clock queries every 5 minutes, which a File cannot hold well. Rejected:
recipes as custom metadata (deploying records from Apex needs a Setup setting for packages that
are not certified, and every watermark change would be a deploy).

### 6.3 Apex Size

- **Core:** estimated 10,000 to 15,000 characters (map save checks in `SavedTransformService`, a
  `MapController` with list, load, save, delete and preview, `@NamespaceAccessible` on the few
  methods the module calls). Core is 2,255,311 characters against its 2,000,000 target (O-01); the
  Mapper puts its logic in JavaScript so Core grows by under 1 percent.
- **Connector:** estimated 120,000 to 180,000 characters of non-test Apex (runner, steps, map
  runtime, HTTP executor, receiver, clock, controllers). The suite stays well under the 6,000,000
  character org limit (4,987,461 now).

---

## 7. Release Slicing

Each slice is one PR under about 800 changed lines where possible, built on a feature branch and
tested in a landing batch (D-141, D-142). IDs are proposed: MAP for the Core Mapper, CN for the
Connector module.

| ID | Slice | Package | Size |
|---|---|---|---|
| MAP-01 | Map document v4 in the canonical model; framework-free `mapDocument` (validate, paths from a JSON sample, auto-match, type checks) with Jest and a shared fixture | Core | Major (with MAP-02) |
| MAP-02 | `barnMapper` component: three panes, pick and drag, step editor, sample preview, Check Before Running | Core | Major |
| MAP-03 | Saved Maps: `Kind__c`, save, load, rename, delete, Where Used for maps, Maps list in Data Manager | Core | Minor |
| MAP-04 | Super Importer: Save as Map and Use a Saved Map | Core | Minor |
| CN-01 | Package skeleton, the BarnCRM Connector console app (D-216), the Super Connector tab (Connections section), Connector Admin permission set, Module Manager row, Health Check extension, Generic REST Connections with the built-in auth kinds API key in a header, Bearer token, Basic and Secret URL (create, guided Enabled for Callouts step with Check Again, Check Connection, Replace Key, Disconnect, Delete) with F2, F3, F4 (base URL and host lock), F5, F6, F7, F8, F10, F11, F12. The two objects move to CN-02, the first slice that reads or writes them (nothing in CN-01 does). Tests: an update, Disconnect or Delete naming `Barn_Stripe` (or any name not created by BarnCRM) is refused before ConnectApi; a user with the Connector set but without `ManageNamedCredentials` or Customize Application is refused; no credential write is queued; each auth kind writes secrets with `encrypted = true` and ids with `false`; list and edit responses carry no secret and no secret URL (host and last four only); a ConnectApi exception echoing the secret is logged with `****` and only a fixed message reaches the user; no `System.debug` in the module; `http://` base URLs and host changes without a new secret are refused; a host pattern such as Mailchimp's `{dc}` (`^[a-z]{2}[0-9]{1,3}$`) is enforced by the shared host-lock rule templates will use (tested with a fixture, no Mailchimp connector shipped); a secret-URL connection's URL is never returned to the client and page text carries the Setup-visibility disclosure (F5, moved from CN-07); key replacement writes one Admin Journal entry; the Connections set is assigned only to Connector admins and identities, never to a client-supplied Id; Jest: the password input is cleared after success and failure and never stored | Module | Major |
| CN-02 | The two objects (Appendix A.3, A.4) and the Connector Viewer set; recipes and runs: editor (When and Then cards), manual and scheduled triggers, Find, Create, Update, Upsert, Call an App, If, Stop; run history; Test; map runtime; executor with F1 and F4. Tests: `{!$Credential.` text in a webhook payload value, a record field, a recipe header and a map literal fails the step or the save; Named Credentials are created with formulas in body off; paths with `//`, `@`, `\`, `{!`, CR or LF are refused and inserted values are URL-encoded; recipe headers cannot set `Authorization` | Module (may split into CN-02a model and history, CN-02b runner and steps) | Major |
| CN-03 | Recipe clock (platform event heartbeat), Run As identities (BarnCRM Automation, System, Integration User), record-change polling, retries with backoff, pause and auto-pause, Error Log, Health Check, Nightly cleanup | Module | Major |
| CN-04 | Inbound webhooks and sending data back (D-216): receiver, token in `X-BarnCRM-Token` or the query, caps, idempotency, fetch back under F4 (F13); the synchronous reply (status code, fixed body, challenge echo, run reference) and the Send to Webhook step, including a callback URL held to the connection's host (Section 3.3a). Tests: the reply body never carries record data and a `{!` reply is refused on save; Send to Webhook refuses a callback URL on another host, user info or port; header and query token both accepted, wrong token 404 with empty body; fetch back refuses `http`, user info (`https://api.example.com@attacker.net`), a suffix host (`api.example.com.attacker.net`) and another port, and calls `callout:` with path and query only; the guest set holds only the REST class and create on the start event | Module | Major |
| CN-05 | For Each, Wait, Change Data steps | Module | Minor |
| CN-06 | Flow actions "Run BarnCRM Recipe" and "Apply BarnCRM Map and Save"; Where Used extension | Module | Minor |
| CN-07 | Slack (bot token recommended, incoming webhook alternative) and Teams templates (F5). Later: a template file, not package metadata (D-216); the F5 tests moved to CN-01 | Template | Later |
| CN-08 | Publish, draft, Roll Back, Export and Import Recipe; Templates section with template import from a file or pasted JSON (Section 3.6): schema check in the browser and in Apex, a prefilled connection with the host locked, Draft recipes; nothing preloaded or kept. Tests: a template with `{!`, an auth header template or a body-formula option is refused; import stores no template | Module | Minor |
| CN-09 | Load Rows with an Import Template: scheduled dry run with commit limits (C-38), with the small Core staging seam | Module and Core | Major |
| CN-10 | OAuth browser sign-in auth kind with the guided Auth Provider step (F9; no code path creates an Auth Provider or accepts a client secret), built with the first template that needs it (Google Sheets as an import source) | Module, then a template | Later |
| CN-11 | Mailchimp template | Template | Later |
| CN-12 | Giving tool webhook templates (Givebutter, Donorbox, Zeffy) | Templates (need Fundraising) | Later |
| CN-13 | App polling trigger (generic) | Module | Minor |
| CN-14 | Eventbrite template | Template | Later |
| CN-15 | Token step auth kind and the Zoom template (polling) | Module, then a template | Later |
| CN-16 | Constant Contact template | Template | Later |
| CN-17 | QuickBooks Online template (gift summary export) | Template | Later |
| CN-19 | GoFundMe Pro template (owner's request, D-216); OAuth client credentials auth kind if its API needs it | Template | Later |
| MAP-05 | Super Importer's Check Columns step rendered by the Mapper after the parity checklist | Core | Major |
| MAP-06 | Super Transformer: Apply a Map | Core | Minor |
| MAP-07 | Gift mirrors: extra field copies in the Mapper | Fundraising | Minor |
| CN-18 | Runs in the GDPR erasure path | Module | Minor |

### 7.1 Releases (plan style: about 3 major and 3 to 6 minor each)

As slotted in the BMemory plan after D-216 (the plan is authoritative; the Mapper slices beyond
MAP-04 are slotted there):

- **Release 1.31 (Mapper and first connection):** MAP-01 to MAP-04 (the Mapper, by its own
  slices), CN-01 (major), CN-02 (major); CN-06 (minor). Useful on its own: an admin can connect
  any REST app from the Connector's own app, run a recipe by hand or on a schedule, and save and
  reuse maps in Super Importer and Flow.
- **Release 1.32 (Automatic recipes and sending back):** CN-03 (major), CN-04 with sending data
  back (major), CN-09 scheduled imports, C-38 (major); CN-05, CN-08 with versions and template
  import (minors).
- **Release 1.33:** CN-13 (app polling trigger), CN-18 (runs in the GDPR erasure path).

The build follows the batch rules (release gate, `barn-npc`, `mwdbdevsb` with approval).

### 7.2 Later (D-216, not in the first version)

- **App templates,** built one at a time after the import mechanism (CN-08): Slack and Teams
  (CN-07), Mailchimp (CN-11), giving-tool webhooks (CN-12), Eventbrite (CN-14), Zoom with the
  token step (CN-15), Constant Contact (CN-16), QuickBooks Online (CN-17), Google Sheets with the
  OAuth browser kind (CN-10), GoFundMe Pro (CN-19), and others as asked. Each ships as a file,
  never as package metadata.
- **Event-driven triggers** instead of 15-minute polling (Section 3.2).
- **SFTP connections** and **direct database connections** (Section 4.1): Apex has no sockets,
  so each needs an HTTPS bridge; whether that bridge can be free and self-service (no BarnCRM
  service, nothing paid) is the first design question when they are slotted.

---

## 8. Owner Decisions (D-215, D-216) and What Remains Open

Decided 2026-11-20 (plan D-215):

1. **C-38 starts inside the Connector:** approved. Scheduled imports are CN-09 with the scheduled
   dry run that commits only inside the admin's limits; Google Sheets (CN-10) is the first source;
   SFTP and direct database sources leave C-38 (Section 4.1).
2. **Pasting a connection's secret on BarnCRM's page through `ConnectApi`:** approved, subject to a
   separate in-depth security review. The review
   (`docs/architecture/connector-secrets-security-review.md`) found it secure with required
   mitigations; all of them (F1 to F13) are binding requirements in Sections 3.3 and 3.5, with
   tests in CN-01, CN-02, CN-04, CN-07 and CN-10. Consequences of the review: OAuth Auth
   Providers are created only by the admin in Setup (F9), and secret-URL connections (Teams, a
   Slack incoming webhook) are disclosed as Setup-visible configuration, with a Slack bot token
   recommended (F5). Stripe, PayPal, Smarty and Google keep ADR-0229.
3. **Names:** approved: module BarnCRM Connector, tab Super Connector, Core feature the Mapper
   with saved Maps.
4. **Runs as the admin who turned recipes on:** rejected. Brandon: "I'd rather recipes being able
   to be ran as system, integration user, or non-user specific to avoid disruptions due to changed
   permissions or deactivated users." Replaced by Section 3.10.
5. **Two new objects, suite at 199 of 200:** approved.

Approved with exceptions 2026-11-20 (plan D-216, quoted in the header), applied here:

6. **Where it lives:** Section 3.1 (the Super Connector tab in BarnCRM Admin Console, ADR-NEXT,
   nine console apps), Section 6.2, CN-01.
7. **Sending information back:** Section 3.3a (a synchronous fixed reply to the posting app; a
   Send to Webhook step and callback replies after processing, under F1 and F4), Section 3.4,
   CN-04 in release 1.32.
8. **Premade integrations are importable templates, not preloaded:** Section 3.6 (only Generic
   REST built in; import from a file or pasted JSON fills a connection and Draft recipes and keeps
   nothing else), Section 3.8, CN-08 in release 1.32; the templates themselves, GoFundMe Pro
   added, are Later (Section 7.2).
9. **SFTP and direct database connections:** Later (Sections 4.1 and 7.2), not in the first
   version.
10. **Event-driven triggers:** Later (Sections 3.2 and 7.2); the first version polls every 15
    minutes.

Still open:

1. **Run As default.** **Recommendation:** BarnCRM Automation (the Automated Process user in user
   mode, limited to the permission sets the admin picks, starting with BarnCRM Admin and the
   installed modules' admin sets) as the default for every new recipe; System only by explicit
   per-recipe choice; Integration User offered where the org has one. If the first org deploy
   shows that Salesforce refuses a permission set assignment to the Automated Process user, the
   fallback is: Integration User recommended, and System by explicit choice (Section 3.10).

---

## Appendix A: Canonical Model Additions (Draft, Proposed)

Drafted here in the canonical model's format; MAP-01, CN-01 and CN-02 copy them into
`canonical-model.md` (MAP-01 amends Sections 15 and 29X; CN-01 adds the Connector's Part with
its Connection rules (no object) and a row in Section 32; CN-02 adds A.3 and A.4 with the two
objects).

### A.1 Amendment to 29X. Saved Transform

New attribute:

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Kind | picklist(Step List, Map) | yes (defaults Step List) | Step List is a Super Transformer step list (R-ST1); Map is a saved map document (R-MAP1). |

**R-ST5 Maps.** A row of Kind Map holds a map document (R-MAP1) in Definition, and Object Name is
its target object (blank for a JSON target). Its name is unique among maps. It is created, renamed
and deleted by people with Manage BarnCRM Settings, read in user mode by every tool that uses it,
and never run by Super Transformer's Saved Step Lists card, which lists Step List rows only.

| Attribute | API name | Type | Notes |
|---|---|---|---|
| Kind | `Kind__c` | Picklist (restricted): `StepList` (default), `Map` | Every existing row reads as Step List. |

### A.2 Amendment to 15. Import Template

**R-MAP1 Map document.** The R-IT1 document, version 4, may carry `from`, `to` and `match` and,
per column, `value`, `required` and `lookup`, as defined in the integration hub design Section
2.2. A version 1 to 3 document is a version 4 document with `from.kind` columns and `to.kind`
record. Super Importer reads `columns`, `defaults`, `transforms` and `lookup` (as `lookupField`
when `lookup.object` is the field's own reference target), and ignores `from`, `to` and `match`,
which a template keeps in its own fields (R-IT2, R-IT9, R-IT12).
**R-MAP2 Paths.** A source or JSON target path is at most 10 parts of letters, digits,
underscores and hyphens joined by dots, each part optionally followed by `[n]` (n from 0 to 999).
A path that finds nothing gives a blank value. Nothing in a path is evaluated.
**R-MAP3 Checked on save, forgiving on read, checked as the person on use** (as R-IT1, R-IT15 and
R-ST3).

### A.3 Connector Recipe (new section, BarnCRM Connector)

**Definition.** A saved integration: a trigger and its steps, with the state its clock needs. Holds
no record data beyond what its definition names.

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The recipe's name, 1 to 80 characters, unique ignoring capitals. |
| Description | long text | no | What it does, in the admin's words. |
| Status | picklist(Draft, Active, Paused, Paused by Failures) | yes (defaults Draft) | Whether it runs. |
| Trigger Kind | picklist(Schedule, Record Change, Webhook, App Poll, Manual) | yes | Copied from the definition for list views and the clock's query. |
| Definition | long text | yes | The published recipe document (R-CR1). |
| Draft | long text | no | The definition being edited; Publish copies it to Definition. |
| Previous Definition | long text | no | The definition before the last Publish, for Roll Back. |
| Version | integer | yes (defaults 0) | Increments on each Publish. |
| Webhook Token Hash | text(64) | no | SHA-256 of the webhook token, hexadecimal; unique. |
| Watermark | text(60) | no | The last stamp and Id a poll reached. |
| Next Run At | datetime | no | When a schedule or poll is next due. |
| Last Run At | datetime | no | When it last ran. |
| Consecutive Failures | integer | yes (defaults 0) | Failed runs in a row; reset by a success. |
| Pause After Failures | integer | yes (defaults 10) | Failures in a row that pause it (1 to 100). |
| Retry Attempts | integer | yes (defaults 3) | Retries of a transient failure (0 to 4). |
| Webhook Hourly Cap | integer | yes (defaults 500) | Posts stored per hour (1 to 5,000). |
| Keep Runs Days | integer | yes (defaults 30) | Days runs are kept (7 to 365). |
| Ignore Own Changes | boolean | yes (defaults true) | Record Change trigger skips records last changed by a recipe identity. |
| Run As | picklist(BarnCRM Automation, System, Integration User) | yes (defaults BarnCRM Automation) | The identity and access mode its runs use (design Section 3.10). |
| Run As Chosen By | reference(User) | computed | Who last set Run As; shown with System recipes in Health Check. |
| Run As Chosen At | datetime | computed | When Run As was last set. |
| Record Owner | text(18) | no | The user or queue Id given as owner of records the recipe creates; blank means the identity. |

**R-CR1 The recipe document.** `{ "version": 1, "trigger": { "kind", ... }, "steps": [ { "id", "kind", ... } ] }`
with the trigger kinds and step kinds of the design Sections 3.2 and 3.4; at most 25 steps in all,
nesting at most 2, at most 100,000 characters. Steps name connections by developer name, maps by
key or inline, and values by paths (R-MAP2). A webhook trigger may carry `reply` (status 200 or
202, a fixed body of at most 4,000 characters with no `{!`, an optional challenge field name;
design Section 3.3a), which the receiver reads with the recipe it already finds by token hash.
**R-CR2 Checked on Publish,** as the publisher and against the identity's describe, and against
the catalog; a recipe whose connection is disconnected or whose map is gone cannot be published.
**R-CR3 Only Connector admins** (custom permission Manage BarnCRM Connector) create, publish,
pause and delete recipes and set Run As; Connector viewers read recipes and runs.
**R-CR4 Run As.** A run never executes as a staff member: BarnCRM Automation (Automated Process
user, user mode with the picked permission sets), System (Automated Process user, system mode;
set only through a confirmation that says so) or Integration User (the designated user, user
mode). Changing Run As writes Run As Chosen By and Chosen At.

| Attribute | API name | Type |
|---|---|---|
| Status | `Status__c` | Picklist (restricted) |
| Trigger Kind | `Trigger_Kind__c` | Picklist (restricted) |
| Definition, Draft, Previous Definition | `Definition_JSON__c`, `Draft_JSON__c`, `Previous_JSON__c` | Long Text Area(131072) |
| Version | `Version__c` | Number(6,0) |
| Webhook Token Hash | `Webhook_Token_Hash__c` | Text(64), unique, external ID |
| Watermark | `Watermark__c` | Text(60) |
| Next Run At, Last Run At | `Next_Run_At__c`, `Last_Run_At__c` | Date/Time |
| Consecutive Failures, Pause After Failures, Retry Attempts, Webhook Hourly Cap, Keep Runs Days | `Consecutive_Failures__c`, `Pause_After_Failures__c`, `Retry_Attempts__c`, `Webhook_Hourly_Cap__c`, `Keep_Runs_Days__c` | Number |
| Ignore Own Changes | `Ignore_Own_Changes__c` | Checkbox |
| Run As | `Run_As__c` | Picklist (restricted): `Automation` (default), `System`, `IntegrationUser` |
| Run As Chosen By, Run As Chosen At | `Run_As_Chosen_By__c` (Lookup(User)), `Run_As_Chosen_At__c` | Lookup, Date/Time |
| Record Owner | `Record_Owner_Id__c` | Text(18) |

Object `Connector_Recipe__c`, private sharing, `Connector_Admin` full access with View
All and Modify All, `Connector_Viewer` read with View All.

### A.4 Connector Run (new section, BarnCRM Connector)

**Definition.** One time a recipe ran or was asked to run: its input, its progress and its result.

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Recipe | reference(Connector Recipe) | yes | The recipe (master). |
| Status | picklist(Received, Queued, Running, Waiting, Succeeded, Skipped, Failed) | yes | Where the run stands. |
| Started By | picklist(Schedule, Record Change, Webhook, App Poll, Manual, Flow, Test) | yes | What started it. |
| Ran As | picklist(BarnCRM Automation, System, Integration User) | yes | The recipe's Run As when the run executed, for audit. |
| Recipe Version | integer | yes | The version it ran. |
| Input | long text | no | The trigger data (record Ids, webhook body or polled item). |
| State | long text | no | Completed step Ids and the data later steps need. |
| Step Log | long text | no | Each step's outcome, duration, Ids written, HTTP status, trimmed failed response. |
| Event Key | text(255) | no | Recipe plus event id; unique, so a resend is dropped. |
| Reference | text(20) | no | Opaque run reference returned in a webhook reply (design Section 3.3a); unique. |
| Attempt | integer | yes (defaults 0) | Retries made. |
| Next Attempt At | datetime | no | When a Waiting run resumes. |
| Started At, Finished At | datetime | no | When it ran. |
| Failed Step, Error Message | text | no | Where and why it failed, in plain words. |
| Records Written | integer | no | Records created or updated. |
| Is Test | boolean | yes (defaults false) | A Test run from the editor. |

**R-RUN1 Written in system mode by the module only** (the guest's insert of Received runs, the
runner's bookkeeping); nobody edits a run. **R-RUN2 Retention:** the nightly step deletes runs
older than the recipe's Keep Runs Days. **R-RUN3 No secret or header is ever stored.**

API names: `Recipe__c` (master-detail), `Status__c`, `Started_By__c`, `Ran_As__c`, `Recipe_Version__c`,
`Input_JSON__c`, `State_JSON__c`, `Step_Log_JSON__c` (Long Text Area(131072)), `Event_Key__c`
(Text(255), unique, external ID), `Reference__c` (Text(20), unique), `Attempt__c`, `Next_Attempt_At__c`, `Started_At__c`,
`Finished_At__c`, `Failed_Step__c` (Text(40)), `Error_Message__c` (Text(1000)),
`Records_Written__c`, `Is_Test__c`. Object `Connector_Run__c`, controlled by parent.
