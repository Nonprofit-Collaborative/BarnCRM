# Integration Hub Design: the Mapper and BarnCRM Connector

**Status:** Proposed (design for the build to follow; nothing here is built yet)
**Date:** 2026-11-20
**Source:** Brandon, 2026-11-20: "I'd also like to create and integration/middleware module. I'd
like it to be similar to Workato in capabilities and super easy for a non technical user to setup
and use. Also, I'd like a UI feature to map objects and fields that can be reused for functions
like data import, transformations, automations, and integrations. I'd like it to be as easy or
easier/more intuitive to use as Salesforce's Flow/Data 360 transform screen. Please design,
build, and start integrating these now."
**Decisions:** ADR-NEXT `NEXT-reusable-mapper.md` (the Mapper and the map document) and ADR-NEXT
`NEXT-integration-module.md` (the BarnCRM Connector module). Both cite this document.
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
- No synchronous "respond with data" webhook API, no callable sub-recipes, no lookup-table
  object, no environment promotion beyond exporting and importing a recipe's JSON.
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
- **Template:** a ready-made recipe to start from.

Tab **Super Connector** with four sections (`barnTabs`): Recipes, Connections, Run History,
Templates. The module's own app and Settings tab follow D-101 and ADR-0223.

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
- *Loop guard:* "Ignore changes made by the recipe runner" is on by default, so a recipe that
  writes to the object it watches does not trigger itself.
- *Later, only if delay proves a problem:* an instant option through the ADR-0138 generated
  trigger the admin deploys, publishing to the run queue.

**The recipe clock.** One Schedulable class scheduled four times an hour (four CronTriggers at :00,
:15, :30 and :45; the org limit is 100). Turn On Recipes on the module's Settings tab schedules it
as the person pressing it, who becomes the **runner** (Section 5). Each tick queues due runs and
starts one runner chain. Health Check reports a missing clock, an inactive runner, or a runner
without the permission set.

### 3.3 Inbound Webhooks: Security Analysis

Endpoint: `POST <site URL>/services/apexrest/barncrm/connector/v1/hook?token=<64 hex>`.

- **Guest only stores** (ADR-0184, ADR-0201): the receiver inserts one Run, Received, in system
  mode, and makes no callout, no record read and no processing. The runner processes it later as
  the runner, in user mode.
- **Token:** 256 random bits (`Crypto.generateAesKey(256)`), shown once with Copy and stored only
  as its SHA-256 hash on the recipe (`Webhook_Token_Hash__c`, unique). The receiver hashes the
  presented token and finds the recipe by the hash, so no token is stored and a read-only user who
  can see the recipe cannot rebuild the URL. Regenerate Token (confirmation first) replaces it.
  Missing or unknown token: 404 with an empty body, nothing stored.
- **Bounds:** JSON or form-encoded bodies only, at most 131,072 characters (413 otherwise); an
  hourly cap per recipe (default 500, recipe setting) whose first refusal each hour writes one
  Warning to the Error Log; a paused recipe still stores posts (up to its cap) and processes them
  when resumed, and a draft recipe answers 404.
- **Duplicates:** a connector or recipe may name an event id path; the run's unique `Event_Key__c`
  drops a resend, answered 200.
- **Untrusted payload:** a post can only do what the recipe's steps do, as the runner, in user mode
  (CRUD, FLS, sharing). Where the sending app offers it, the connector's **fetch back** option
  reads only an id (or a resource URL whose host must equal the Connection's host) from the post
  and fetches the real data through the Connection, so a forged post with a stolen token cannot
  inject data (the ADR-0229 Stripe pattern; Eventbrite sends an `api_url` exactly for this).
- **No signature checks:** an HMAC check would need Apex to read a signing secret, which ADR-0229
  rules out. Token, fetch back, caps and idempotency replace it. Apps that refuse to deliver
  without a secret-based handshake (Zoom's URL validation) use the polling trigger instead.
- **Guest access:** a `BarnCRM_Connector_Webhook_Guest` permission set with the REST class only,
  assigned to Site guest users by the existing Health Check fix. A Site is needed (most orgs with
  Payments or Forms have one); the Settings tab says how to create one.
- **Logging:** the token never appears in a log, run or error message.

### 3.4 Actions (the Then steps)

| Step | Plain name | What it does |
|---|---|---|
| `find` | Find Records | A Find query document (R-R2) with values from earlier steps; returns up to 200 records; "stop if none" option |
| `create`, `update`, `upsert` | Create, Update, or Create or Update a Record | Applies a map (linked or inline) to build the record; upsert uses the map's `match`; `Database` DML in user mode with partial success off per run |
| `callApp` | Call an App | A connector action, or a custom request on a generic connection: method, path, query, non-secret headers, body built from a map (`to.kind` json, serialized with `JSON.serialize`, never by string substitution), expected success codes, "404 means not found" option |
| `transform` | Change Data | Applies a map with `to.kind` json to produce a new data object for later steps |
| `if` | If | A condition (filter document over trigger and step data) with Then steps and optional Otherwise steps; nesting at most 2 levels |
| `forEach` | For Each | Runs its steps once per item of a list from an earlier step, at most 1,000 items a run, checkpointing every 200 |
| `wait` | Wait | Pauses the run for minutes, hours or days; resumed by the clock (15-minute granularity) |
| `importRows` | Load Rows with an Import Template | Hands rows (from Google Sheets, a CSV at a connection, or a list from an app) to Super Importer staging with a template, runs the dry run, and commits only inside the recipe's limits (C-38) |
| `stop` | Stop | Ends the run as Succeeded, Skipped or Failed with a message |

Values from earlier steps are "data pills": paths such as `trigger.record.Email` or
`steps.s2.body.members[0].id`, chosen from a picker that shows sample values. Paths only, no
expressions.

### 3.5 Connections

Every connection is an External Credential plus a Named Credential, both created by BarnCRM at
run time with `ConnectApi.NamedCredentials` (`createExternalCredential`, `createNamedCredential`)
and named `BarnConn_<connector>_<6 random>`; the admin's display name is the label. There is no
Connection object: the Connections section lists the org's External Credentials with that prefix.

Authentication kinds, from the connector definition:

| Kind | Setup the admin does | Example |
|---|---|---|
| API key or token in a header | Paste the key on BarnCRM's page | Mailchimp (Basic over any user and the key), Eventbrite (Bearer) |
| Basic user and password | Paste both | Older REST APIs |
| Secret URL | Paste the webhook URL (it becomes the Named Credential's URL) | Slack, Microsoft Teams Workflows |
| OAuth 2.0 client credentials | Paste client id and secret (External Credential's native flow) | Many server-to-server APIs |
| Token step | Paste client id and secret; the connector's sign-in call returns a short-lived token held for one transaction (the PayPal pattern of ADR-0229) | Zoom Server-to-Server OAuth |
| OAuth 2.0 browser sign-in | Create an app at the provider (BarnCRM shows the callback URL and the scopes to tick), paste its client id and secret; BarnCRM creates the Auth Provider and External Credential; then one Authenticate click | Google Sheets, Constant Contact, QuickBooks Online |

Headers use merge formulas (`{!$Credential.BarnConn_x.ApiKey}`, Allow Formulas in HTTP Header
on), so Apex never reads a stored secret (ADR-0229 decision 1).

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
4. **A Salesforce Site**, only for webhooks, once per org.

The secret itself is pasted on BarnCRM's page and written to the principal with
`ConnectApi.NamedCredentials.createCredential`: it passes through Apex memory once and is never
stored in a record, logged or returned. This differs from ADR-0229 decision 5 (packaged
providers' secrets are entered in Setup) and is Open Decision 2.

Principal access: BarnCRM creates one org-owned permission set, "BarnCRM Connections"
(unpackaged, because a packaged permission set cannot be changed in a subscriber org), adds each
connection's principal to it, and assigns it to the runner and to Connector admins.

Each connection has **Check Connection** (the connector's check call, or a HEAD/GET of the base
URL for generic), **Disconnect** (deletes the principal's credential, keeps the recipe
definitions, pauses recipes that use it) and **Delete** (refused while a recipe uses it).

Things to confirm on the first org deploy, as ADR-0229 listed its own: that `createCredential`
writes a Custom protocol principal parameter for an admin with Customize Application; that
`SetupEntityAccess` rows for an External Credential principal can be inserted from Apex (fallback:
a guided Setup step); that an Auth Provider can be created at run time (fallback: guided Setup
step with the values to paste); and that a namespaced package's Apex can call `callout:` on a
subscriber-created Named Credential.

### 3.6 Connector Catalog (JSON)

One JSON file per connector, shipped as a static resource and contributed as JSON only:

```json
{
  "key": "mailchimp", "label": "Mailchimp", "version": 1,
  "auth": { "kind": "apiKeyBasic", "params": [{ "name": "ApiKey", "label": "API key", "help": "Account, Extras, API keys" }] },
  "baseUrl": "https://{dc}.api.mailchimp.com/3.0",
  "urlParams": [{ "name": "dc", "label": "Data center", "fromParam": "ApiKey", "after": "-" }],
  "check": { "method": "GET", "path": "/ping" },
  "actions": [
    { "key": "upsertMembers", "label": "Add or update subscribers", "method": "POST", "path": "/lists/{listId}",
      "inputs": [{ "name": "listId", "label": "Audience", "pick": { "path": "/lists", "items": "lists", "value": "id", "label": "name" } }],
      "body": { "members": "{{list}}", "update_existing": true } }
  ],
  "pollers": [
    { "key": "unsubscribes", "label": "New unsubscribes", "path": "/lists/{listId}/members",
      "query": { "status": "unsubscribed", "since_last_changed": "{{watermark}}" }, "items": "members", "id": "id", "stamp": "last_changed" }
  ],
  "webhook": { "eventId": "id", "fetchBack": null },
  "templates": ["mailchimp-new-people"]
}
```

`urlParams.fromParam` is the one exception where a non-secret part of a key (Mailchimp's data
center suffix) is read: the page derives it in the browser before the key is sent, so Apex still
never reads the key. Pickers (`pick`) call the app to list choices (audiences, events, sheets).

**Generic REST first**, then, for small organizations, in this order (value for effort):

| Order | Connector | Auth | First templates |
|---|---|---|---|
| 1 | Generic REST | Any kind above | Any |
| 2 | Slack and Microsoft Teams (Workflows webhook) | Secret URL | Post a message when a record matches (a large gift, a new volunteer) |
| 3 | Mailchimp | API key | Add new or changed people to an audience; pull unsubscribes back |
| 4 | Google Sheets (C-38 source) | OAuth browser (Auth Provider type Google) | Load a sheet daily through an import template |
| 5 | Giving tools that send webhooks (Givebutter, Donorbox, Zeffy and similar) | Webhook token; fetch back where the tool has an API | Gift and person, replacing the paid Zapier path of MIG-06 (needs Fundraising) |
| 6 | Eventbrite | Private token | Attendees to people (and to Event Management registrations when installed) |
| 7 | Zoom | Token step (Server-to-Server OAuth) | Webinar registrants and attendance, by polling |
| 8 | Constant Contact | OAuth browser | As Mailchimp |
| 9 | QuickBooks Online | OAuth browser | Daily gift summary as a journal entry or sales receipts (needs Fundraising) |

### 3.7 Runs, Retries, Errors and Pause

- **Run statuses:** Received (webhook stored), Queued, Running, Waiting (a Wait step or a retry),
  Succeeded, Skipped, Failed, Rejected (webhook refused at processing).
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
  test result is a run marked Test.
- **Templates:** shipped as recipe JSON with placeholders for connections and choices; Use
  Template opens the draft with each blank highlighted.
- **Versioning:** a recipe has a published definition and a draft. Publish checks the draft,
  increments the version and keeps the previous definition for one-click Roll Back. Export and
  Import Recipe (JSON) move a recipe between a sandbox and production.

### 3.9 Where Used, Health Check and Other Core Seams

- **Where Used** (C-59): the module implements `WhereUsedExtension` (ADR-0057 pattern), listing
  recipes that name a field or object in maps, filters or Find steps, and recipes using a saved
  map or a connection. Retire a Field warns before a field a recipe writes is retired.
- **Health Check** (`HealthCheckExtension`): clock scheduled, runner active with the permission
  set, connections enabled for callouts and checked, recipes paused by failures, Site guest
  permission set assigned.
- **Nightly Jobs:** the run cleanup step.
- **Module Manager:** a `BarnCRM_Module__mdt` row and the module's objects in
  `ModuleManagerService.ownedObjects`; the Integrations page (C-48) links to the Connector when it
  is installed.

---

## 4. Governor Limits and Scale

| Limit (asynchronous Apex) | Value | Design response |
|---|---|---|
| Callouts per transaction | 100 | The runner stops at 90 and chains |
| Total callout time per transaction | 120 seconds | Each callout times out at 30 seconds (connector may set up to 120); the runner stops at 100 seconds and chains |
| Callout after uncommitted DML | Not allowed | When a step needs a callout and the transaction has DML pending, the runner checkpoints the run and chains a new Queueable |
| Queueable chaining | One child per async transaction; no depth limit in production (5 in Developer Edition and trial orgs) | One runner chain at a time (checked through `AsyncApexJob`); test orgs note the depth cap |
| Asynchronous executions per 24 hours | The greater of 250,000 and 200 per user license | Many runs per execution; the clock costs 96 a day; the Settings tab shows the day's use |
| Heap | 12 MB | Responses over 4 MB are refused with a clear message; run state keeps only paths later steps use (computed at Publish) |
| HTTP response size | 12 MB | As above; connectors page large lists |
| CPU | 60 seconds | The runner stops at 45 seconds and chains |
| SOQL, DML statements, DML rows | 200, 150, 10,000 | Batch mode writes lists in one statement; For Each checkpoints every 200 items |
| Scheduled Apex jobs | 100 per org | The clock uses 4 |
| Long text field | 131,072 characters | Webhook body cap; run state cap, else the run fails with "data too large" |

Throughput estimate: with two callouts of about half a second per run, one execution finishes about
45 runs, so a single chain handles thousands of runs an hour; enough for the target organizations.
Large one-off loads belong in Super Importer, which a recipe can call (`importRows`).

### 4.1 Workato Capabilities Apex Cannot Match, and What to Do Instead

| Capability | Why not in Salesforce Apex | Instead |
|---|---|---|
| SFTP, FTP, raw TCP | Apex has HTTP only, no sockets | Ask the source for an HTTPS export or API; drop files in Google Drive or Sheets; or a tool the organization already runs pushes to the webhook |
| Direct database connections (SQL Server, MySQL) | No JDBC or sockets | The database's own REST layer, or a scheduled export to a sheet |
| On-premise agent | No agent can run inside Salesforce | Same as above |
| Long-running jobs and streams (Kafka, long polling) | 60-second CPU and 120-second callout budget per transaction | Polling with watermarks and chained transactions |
| Files over about 4 MB through a recipe | Heap and response size | Super Importer for big files; paging APIs |
| Code steps (Ruby, JavaScript, Python) and formula mode | Evaluating admin-typed code is refused (ADR-0081) | The closed step list, conditions, maps; a new step is an ADR |
| Webhooks with secret-based signatures or handshakes | Apex must not read secrets (ADR-0229) | Token plus fetch back, or polling |
| Synchronous API endpoints (recipe answers the caller with data) | Guest only stores (ADR-0184) | The Inbound Gift API or a module's own REST resource |
| Sub-minute polling and high concurrency | Scheduled Apex granularity, one runner chain | 15-minute polling; Flow action for immediate starts |
| A thousand prebuilt connectors | A small project | Generic REST plus a short JSON catalog anyone can extend |
| Inbound email trigger | Possible (Email Services) but not needed now | A later trigger if asked |

---

## 5. Security Review Notes

- **User mode for data, system mode for bookkeeping only.** Every Find, create, update and upsert
  runs `WITH USER_MODE` and `AccessLevel.USER_MODE` as the person the run executes as. System mode
  is used only for the module's own Recipe and Run rows (ADR-0021 pattern) and the guest's store,
  each entered in the without-sharing register.
- **Who a run executes as.** Scheduled, record-change, webhook, app-polling and Flow-queued runs
  execute as the **runner**, the admin who pressed Turn On Recipes (asynchronous Apex runs as the
  user who scheduled it). Run Now and Test execute as the person pressing. Anyone who can publish a
  recipe can therefore act with the runner's access: publishing needs the custom permission
  `Manage_BarnCRM_Connector`, granted only by `BarnCRM_Connector_Admin`, which the guide says to
  give only to system administrators. Open Decision 4 records this.
- **Queries are documents, never text** (Section 4.9): Find steps and record-change filters go
  through `QueryCompiler` with bind variables; object and field names come from describe.
- **Callouts only through Named Credentials** (`callout:`), no Remote Site Settings; paths are
  built from the connector's template with each value URL-encoded; bodies are built as structures
  and serialized; a fetch-back URL must match the Connection's host (no server-side request
  forgery to other hosts).
- **Secrets never in records,** logs, runs, errors or responses; headers are never stored.
- **Guest endpoint:** Section 3.3.
- **Personal data in runs:** inputs and state can hold personal data; retention defaults to 30
  days, failed-step responses are trimmed, and a later minor adds runs to the GDPR erasure path
  (delete runs that name the person's record Id or email).
- **Code Analyzer:** zero high or critical findings (plan non-negotiable); no dynamic SOQL from
  text, no `without sharing` outside the register, no hard-coded endpoints, no namespace strings.

---

## 6. Objects, Metadata and Naming

### 6.1 Names (Open Decision 3)

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
| Connector | No settings object: every option is per recipe, and the clock is its CronTriggers | none | 0 |
| Connector | Connections | External and Named Credentials created at run time, not objects | 0 |
| Connector | Connector catalog and templates | JSON static resources | 0 |
| Connector | `Connector_Webhook_Rest`, the runner, clock and controllers | Apex | 0 |
| Connector | `BarnCRM_Connector_Admin`, `BarnCRM_Connector_Viewer`, `BarnCRM_Connector_Webhook_Guest` | Permission sets | 0 |
| Core | `Saved_Transform__c.Kind__c` | Field (picklist Step List, Map) | 0 |
| Core | `barnMapper` and `mapDocument` | LWC | 0 |

The suite goes from 197 to 199 custom objects (custom settings included), under the 200 an
Enterprise org allows for the full-suite gate (ADR-0227). This leaves one slot: the next object
anywhere in the suite needs another cut first. Rejected to save the second object: recipes as
Salesforce Files (ADR-0231 style); a recipe carries mutable state (status, watermark, token hash,
failure count) the clock queries every 15 minutes, which a File cannot hold well. Rejected:
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
| CN-01 | Package skeleton, two objects, permission sets, app, tab, Module Manager row, catalog loader, generic REST Connections (create, guided callout step, Check, Disconnect) | Module | Major |
| CN-02 | Recipes and runs: editor (When and Then cards), manual and scheduled triggers, Find, Create, Update, Upsert, Call an App, If, Stop; run history; Test; map runtime | Module (may split into CN-02a model and history, CN-02b runner and steps) | Major |
| CN-03 | Recipe clock, record-change polling, retries with backoff, pause and auto-pause, Error Log, Health Check, Nightly cleanup | Module | Major |
| CN-04 | Inbound webhooks: receiver, token, caps, idempotency, fetch back | Module | Major |
| CN-05 | For Each, Wait, Change Data steps | Module | Minor |
| CN-06 | Flow actions "Run BarnCRM Recipe" and "Apply BarnCRM Map and Save"; Where Used extension | Module | Minor |
| CN-07 | Slack and Teams connectors with templates | Module | Minor |
| CN-08 | Publish, draft, Roll Back, Export and Import Recipe; Templates section | Module | Minor |
| CN-09 | Load Rows with an Import Template: scheduled dry run with commit limits (C-38), with the small Core staging seam | Module and Core | Major |
| CN-10 | Google Sheets connector (OAuth browser; Auth Provider guided creation) as an import source | Module | Major |
| CN-11 | Mailchimp connector and templates | Module | Major |
| CN-12 | Giving tool webhook templates (Givebutter, Donorbox, Zeffy) | Module (templates need Fundraising) | Minor |
| CN-13 | App polling trigger (generic) | Module | Minor |
| CN-14 | Eventbrite connector | Module | Minor |
| CN-15 | Zoom connector (token step, polling) | Module | Minor |
| CN-16 | Constant Contact connector | Module | Major |
| CN-17 | QuickBooks Online connector (gift summary export) | Module | Major |
| MAP-05 | Super Importer's Check Columns step rendered by the Mapper after the parity checklist | Core | Major |
| MAP-06 | Super Transformer: Apply a Map | Core | Minor |
| MAP-07 | Gift mirrors: extra field copies in the Mapper | Fundraising | Minor |
| CN-18 | Runs in the GDPR erasure path | Module | Minor |

### 7.1 Releases (plan style: about 3 major and 3 to 6 minor each)

- **Release 1.31 (Mapper and first connection):** MAP-01 and MAP-02 (one major: the Mapper),
  CN-01 (major), CN-02 (major); MAP-03, MAP-04, CN-06 (minors). Useful on its own: an admin can
  connect any REST app, run a recipe by hand or on a schedule, and save and reuse maps in Super
  Importer and Flow.
- **Release 1.32 (Automatic recipes):** CN-03 (major), CN-04 (major), CN-09 (major); CN-05,
  CN-07, CN-08 (minors).
- **Release 1.33 (Nonprofit connectors):** CN-10 (major), CN-11 (major), MAP-05 (major); CN-12,
  CN-13, CN-14, MAP-06 (minors).
- **Release 1.34 (More apps):** CN-16 (major), CN-17 (major); CN-15, MAP-07, CN-18 (minors).

All four are one or two landing batches per D-155; the build follows the batch rules (release gate,
`barn-npc`, `mwdbdevsb` with approval).

---

## 8. Open Decisions for the Owner

1. **Start C-38 now, inside the Connector.** C-38 (scheduled imports and external sources) is on
   hold until you start it (D-39). This request starts it: scheduled imports become a recipe step
   (CN-09) with the scheduled dry run that commits only inside your limits, and Google Sheets
   (CN-10) is the first source. SFTP and direct database sources are dropped from C-38 because
   Apex cannot open them (Section 4.1). **Recommendation:** approve; release C-38 from hold as
   CN-09 and CN-10.
2. **Where an admin pastes a connection's secret.** ADR-0229 has packaged providers' secrets typed
   in Setup. For Connector connections, BarnCRM's page would take the key and write it to the
   External Credential through `ConnectApi` (it passes through Apex memory once and is never
   stored, logged or shown again). **Recommendation:** approve page entry for the Connector, with
   the Setup path documented as an alternative; Stripe, PayPal, Smarty and Google keep ADR-0229.
3. **Names.** Module BarnCRM Connector, tab Super Connector, Core feature the Mapper with saved
   Maps. **Recommendation:** approve (alternatives: BarnCRM Recipes; BarnCRM Automations collides
   with the Automation page).
4. **Runs execute as the runner.** Unattended runs act with the access of the admin who turned
   recipes on, so anyone allowed to publish recipes can act with that admin's access.
   **Recommendation:** approve, with publishing limited to `BarnCRM_Connector_Admin` (system
   administrators only) and Health Check watching the runner.
5. **Two new objects, suite at 199 of 200.** **Recommendation:** approve; the next new object in
   any module needs a cut first (the alternative, recipes as Files, is workable but makes the
   clock and webhook lookups slower and harder to read).

---

## Appendix A: Canonical Model Additions (Draft, Proposed)

Drafted here in the canonical model's format; MAP-01 and CN-01 copy them into
`canonical-model.md` (MAP-01 amends Sections 15 and 29X; CN-01 adds two new sections in a new
Part for the Connector and a row in Section 32).

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
| Ignore Runner Changes | boolean | yes (defaults true) | Record Change trigger skips records last changed by the runner. |

**R-CR1 The recipe document.** `{ "version": 1, "trigger": { "kind", ... }, "steps": [ { "id", "kind", ... } ] }`
with the trigger kinds and step kinds of the design Sections 3.2 and 3.4; at most 25 steps in all,
nesting at most 2, at most 100,000 characters. Steps name connections by developer name, maps by
key or inline, and values by paths (R-MAP2).
**R-CR2 Checked on Publish,** as the publisher, against describe and the catalog; a recipe whose
connection is disconnected or whose map is gone cannot be published.
**R-CR3 Only Connector admins** (custom permission Manage BarnCRM Connector) create, publish,
pause and delete recipes; Connector viewers read recipes and runs.

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
| Ignore Runner Changes | `Ignore_Runner_Changes__c` | Checkbox |

Object `Connector_Recipe__c`, private sharing, `BarnCRM_Connector_Admin` full access with View
All and Modify All, `BarnCRM_Connector_Viewer` read with View All.

### A.4 Connector Run (new section, BarnCRM Connector)

**Definition.** One time a recipe ran or was asked to run: its input, its progress and its result.

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Recipe | reference(Connector Recipe) | yes | The recipe (master). |
| Status | picklist(Received, Queued, Running, Waiting, Succeeded, Skipped, Failed, Rejected) | yes | Where the run stands. |
| Started By | picklist(Schedule, Record Change, Webhook, App Poll, Manual, Flow, Test) | yes | What started it. |
| Recipe Version | integer | yes | The version it ran. |
| Input | long text | no | The trigger data (record Ids, webhook body or polled item). |
| State | long text | no | Completed step Ids and the data later steps need. |
| Step Log | long text | no | Each step's outcome, duration, Ids written, HTTP status, trimmed failed response. |
| Event Key | text(255) | no | Recipe plus event id; unique, so a resend is dropped. |
| Attempt | integer | yes (defaults 0) | Retries made. |
| Next Attempt At | datetime | no | When a Waiting run resumes. |
| Started At, Finished At | datetime | no | When it ran. |
| Failed Step, Error Message | text | no | Where and why it failed, in plain words. |
| Records Written | integer | no | Records created or updated. |
| Is Test | boolean | yes (defaults false) | A Test run from the editor. |

**R-RUN1 Written in system mode by the module only** (the guest's insert of Received runs, the
runner's bookkeeping); nobody edits a run. **R-RUN2 Retention:** the nightly step deletes runs
older than the recipe's Keep Runs Days. **R-RUN3 No secret or header is ever stored.**

API names: `Recipe__c` (master-detail), `Status__c`, `Started_By__c`, `Recipe_Version__c`,
`Input_JSON__c`, `State_JSON__c`, `Step_Log_JSON__c` (Long Text Area(131072)), `Event_Key__c`
(Text(255), unique, external ID), `Attempt__c`, `Next_Attempt_At__c`, `Started_At__c`,
`Finished_At__c`, `Failed_Step__c` (Text(40)), `Error_Message__c` (Text(1000)),
`Records_Written__c`, `Is_Test__c`. Object `Connector_Run__c`, controlled by parent.
