# BarnCRM Connector

## What It Does

The optional **BarnCRM Connector** module (Beta) connects BarnCRM to the other apps your
organization uses, without Flow Builder, Apex or a paid integration service. It has three parts,
each a tab of **Super Connector**:

- **Recipes**: "when this happens, then do these steps" automations that find, create and update
  BarnCRM records through saved maps and call other apps (see [Recipes](#recipes)).
- **Run History**: every run of every recipe, step by step, with Retry (see
  [Run History](#run-history)).
- **Connections**: a saved, checked sign-in to another app's REST API. Each connection keeps its
  key in Salesforce's own credential store (an External Credential and a Named Credential), never
  in a BarnCRM record, and BarnCRM never shows a key again once it is saved.

Connections are generic: any app with an HTTPS REST API works, with one of four sign-in kinds.
Nothing for a particular app is preloaded into your org.

## Before You Install

- Offered in both editions (see [Editions](editions.md)). It needs BarnCRM Core only.
- The app you connect must offer an HTTPS API and a key, token, user name and password, or a
  secret webhook address. Create the key in that app first.
- To save a key you need **BarnCRM Connector Admin** and either **Customize Application** or
  **Manage Named Credentials** (a Salesforce system administrator has both).

## Setting It Up

1. Install the module from **BarnCRM Settings**, **Modules** (see [Module Manager](module-manager.md)).
   Holders of BarnCRM Admin get **BarnCRM Connector Admin**.
2. Open the **BarnCRM Connector** app (or the **Super Connector** tab in the BarnCRM admin apps).
3. Select **New Connection** and fill it in (see [Creating a Connection](#creating-a-connection)).
4. Turn on callouts for it in Setup, once (see [The One Setup Step](#the-one-setup-step)), then
   select **Check Again**.
5. Select **Check Connection**.

## Creating a Connection

| Field | What to enter |
|---|---|
| Name | Your name for it, such as "Mailing list service, main account". |
| Sign-in kind | How the app expects its key (below). The app's API documentation says which. |
| Base URL | The address every request starts with, such as `https://api.example.org/v2`. It must start with `https://`. |
| Header name | API Key in a Header only: the header the app reads, such as `X-Api-Key`. |
| User name | Basic only. |
| Key | The key, token or password. The box never shows a saved value. |

Sign-in kinds:

| Kind | What BarnCRM sends |
|---|---|
| API Key in a Header | The key in the header you name. |
| Bearer Token | `Authorization: Bearer` and the token. |
| Basic | `Authorization: Basic` with the user name and password. |
| Secret URL | Nothing extra: the address itself is the secret, as with a Microsoft Teams Workflows or Slack incoming webhook address. |

**Secret URL connections are visible in Setup.** Salesforce cannot encrypt an address, so a
Secret URL is stored as the Named Credential's URL, which every administrator who can view
Setup can read. BarnCRM shows only its host and last four characters. Where the app offers a
token instead (Slack offers a bot token), prefer **Bearer Token**.

**Enter keys only when no debug logging is on for you.** A Salesforce debug log at its finest
level can record what a page sends. If a trace flag was on for you while you entered a key,
replace the key.

The host of a connection never changes once its key is saved. To point at another host, create
a new connection and delete the old one.

## The One Setup Step

Salesforce creates every new Named Credential with callouts turned off, and only Setup can turn
them on. Until you do, the connection shows **Callouts Off** and these steps:

1. In **Setup**, search for **Named Credentials**.
2. Select the connection's name, then **Edit**.
3. Tick **Enabled for Callouts** and **Save**.
4. Back on **Super Connector**, select **Check Again**.

If the connection shows **Access Missing**, BarnCRM could not add it to the **BarnCRM
Connections** permission set: in **Setup**, **Permission Sets**, **BarnCRM Connections**,
**External Credential Principal Access**, **Edit**, add the connection's principal, **Save**, then
select **Check Again**.

## Using a Connection

- **Check Connection** sends one GET request to the base URL and shows the app's answer:
  **Connected** (the app accepted the key), **Key Refused** (the app answered 401 or 403: replace
  the key), or the status the app returned. A Secret URL usually answers a GET with 400 or 405,
  which still shows the address is reachable.
- **Replace Key** writes a new key over the old one. Each replacement is recorded in the Admin
  Journal (who and when, never the key), and Health Check lists keys replaced in the last 7 days,
  so a key swapped to another account is noticed. For a Secret URL, the new address must keep the
  same host.
- **Disconnect** removes the key and keeps the connection, to be given a new key later.
- **Delete** removes the connection and its key from Salesforce. A connection a recipe uses (in
  its published version or its draft) cannot be deleted: take it out of every recipe first.

## Recipes

A recipe is one **When** and a list of **Then** steps. You build it on the **Recipes** tab, test
it on sample data, then publish it. Only holders of **BarnCRM Connector Admin** can create,
change, test, publish, run or delete a recipe; holders of **BarnCRM Connector Viewer** can see
recipes and their runs.

### Before Your First Recipe: Recipe Access

Recipes never run as the person who started them. They run as Salesforce's **Automated Process**
user, which belongs to no person and cannot be deactivated. **Recipe Access** (on the Recipes
tab) chooses the permission sets that user holds, and so what every BarnCRM Automation recipe may
read and write:

1. On **Super Connector**, open **Recipes**, then **Recipe Access**.
2. Tick the permission sets recipes may use. **BarnCRM Admin** and each installed module's admin
   set are ticked to start. Untick any you do not want recipes to have.
3. Select **Save Access**. BarnCRM assigns the ticked sets and the **BarnCRM Connections** set
   (so recipes can use your connections) and removes the sets you unticked.

Until Recipe Access is saved, Health Check warns while an Active recipe runs as BarnCRM
Automation. BarnCRM Connector Admin, BarnCRM Connector Viewer and the setup-only admin app sets
are never offered.

### When

| When | What starts a run |
|---|---|
| Run Now or a flow | **Run Now** on the recipe, with data you paste (optional), or the Flow action **Run a BarnCRM Connector Recipe** (see [Flow Actions](#flow-actions)). |

Clock schedules, record changes, webhooks and app polling come in later releases.

### Then: the Steps

Each step has a short name of letters, digits or underscores (such as `findDonor`). A later step
reads an earlier step's result, or the run's own data, by a **value path**:

| Value path | What it reads |
|---|---|
| `trigger.email` | The `email` value of the data the run started with (Run Now JSON, or the flow's Data). |
| `trigger.recordId` | The record Id a flow passed. |
| `steps.findDonor.records[0].Id` | The first record a Find step found. |
| `steps.makeGift.id` | The record a Create or Update step saved. |
| `steps.askApp.body.id` | A value in the JSON an app answered with. |

| Step | What it does | What you choose |
|---|---|---|
| Find Records | Runs a saved Find query (see [Find](find.md)), up to 200 records. | The saved query; a value path for any of its conditions; whether to stop the run as Skipped when nothing is found. |
| Create a Record | Builds one record through a saved record map (see [Mapper](mapper.md)) and inserts it. | The map; the value path it reads (blank is the run's data). |
| Update a Record | Builds the map's fields and updates the record whose Id the value path gives. | The map; the record Id's value path; the value path it reads. |
| Create or Update a Record | Finds the existing record through the map's **Match** (by record Id, a field or an external Id) and updates it, or creates one. | The map; the value path it reads. |
| Call an App | Sends one request over a connection and keeps the app's answer. | The connection; GET, POST, PUT, PATCH or DELETE; the path after the connection's base URL, such as `/contacts/{id}`; a value for each `{slot}`; query parameters; extra headers; a body map (a map that builds JSON) and the value path it reads; the status codes that count as success (blank is any 2xx); whether a 404 is all right. |
| If | Runs its **Then** steps when its conditions hold, otherwise its **Otherwise** steps. | Up to 10 conditions (value path, operator, value), all or any. An If can hold one more If, no deeper. |
| Stop | Ends the run as Succeeded, Skipped or Failed, with a message. | The outcome and message. |

A recipe holds at most 25 steps. Records created by a recipe are owned by the **Owner of New
Records** you choose on the recipe, or by the Automated Process user when blank.

**How Call an App keeps your keys safe.** Every request goes to `callout:` and the connection,
then a path that must start with one `/` and cannot hold `//`, `@`, `\`, `?`, `#` or spaces, so a
recipe can never reach another host. Each `{slot}` and query value is URL-encoded, so a value
cannot add a path segment or a parameter. Authorization and the other sign-in headers come from
the connection, never from a step. Any value that holds a Salesforce merge field (an opening
brace followed by an exclamation mark), whether typed in the recipe, sent by an app or read from a
record, fails the step and nothing is sent: a recipe can never make Salesforce insert a key.

### Run As

| Run As | What the steps may do |
|---|---|
| BarnCRM Automation (the default) | What the Recipe Access sets allow, with field-level security and sharing. Publish checks every record map against those sets and refuses a map whose object or fields they do not grant. |
| System | Everything, without permission or sharing checks. Choosing it asks you to confirm; who chose it and when are shown on the recipe, and Health Check lists every System recipe. Use it only when Recipe Access cannot be widened. |

Both run as the Automated Process user. The Integration User choice comes in a later release.

### Test, Publish and Run Now

1. **Save Draft** keeps your changes without affecting the published recipe. A draft is checked
   on every save: step names, value paths, Call an App paths and headers, and merge fields.
2. **Test** runs the draft once on the sample data in **When** (or on a record Id you enter).
   Create and Update steps save nothing: Run History shows the fields each would write. Call an
   App sends only GET requests unless you tick **Send requests for real**: other methods show the
   request they would send.
3. **Publish** checks the draft again, checks each connection has a key and callouts on, each
   map exists and fits its step, and, for BarnCRM Automation, each record map against Recipe
   Access. Then the draft becomes the published version, the version number goes up and the
   recipe is **Active**.
4. **Run Now** queues a run of the published version with the JSON you paste (blank is `{}`).
   Runs start within moments and appear on **Run History**.

Delete removes a recipe and its runs.

### Limits

A run that writes records and then calls an app pauses before the call and continues in a new
transaction, because Salesforce allows no callout after an unsaved write. A run also pauses near
Salesforce's limits (90 callouts, 100 seconds of callouts, 45 seconds of processing, 180 queries
or 140 saves in one transaction) and continues where it stopped; a step that already ran is never
run again. A run's data, kept between steps, is limited to about 130,000 characters.

## Run History

**Run History** lists the latest 50 runs, newest first, with the recipe, status (Queued,
Succeeded, Skipped, Failed), what started it (Manual, Flow, Test), Run As, version, records
written and the failed step. Open a run to see each step: its outcome, how long it took, the
records it wrote, the app's status code and, for a failed Call an App, the first 2,000 characters
of the app's answer. A Test run also shows what each step would have written or sent. No request
header and no key is ever kept.

**Retry** (BarnCRM Connector Admin only) queues a failed run again from its failed step: steps
that already succeeded are not repeated. Each failed run also writes one Error Log entry naming
the recipe, run, step and plain message, never the request.

## Flow Actions

Two Flow actions appear under **BarnCRM** in Flow Builder:

| Action | Inputs | Outputs |
|---|---|---|
| Run a BarnCRM Connector Recipe | Recipe Name (an Active recipe), and optionally Record Id, Record Ids and Data (JSON). The steps read them as `trigger.recordId`, `trigger.recordIds` and `trigger.data`. | Queued, Run Id, Message. |
| Apply a Saved Map | Map Name (a record map), and Source Record Id or Data (JSON), and optionally Record Id to Update. | Record Id, Action (created, updated or skipped), Message. |

**Run a BarnCRM Connector Recipe** only queues the run: the recipe runs moments later as its own
Run As, never as the person whose flow started it, so the flow needs no access to the recipe and
the recipe gains none from the flow. **Apply a Saved Map** saves at once as the person running
the flow, with their own access: it updates the record given, or finds the record through the
map's Match, or creates one.

## Where Used

**Where Used** (see [Where Used](where-used.md)) lists recipes whose Find steps name the field or
object you ask about, and the Mapper warns before you change a map a recipe links.

## Access

| Permission set | Gives |
|---|---|
| BarnCRM Connector Admin | The BarnCRM Connector app, the Super Connector tab, Manage BarnCRM Connector and every recipe and run. Give it only to system administrators: whoever holds it decides where your data goes. |
| BarnCRM Connector Viewer | The BarnCRM Connector app and the Super Connector tab, to see recipes and Run History without changing them. |
| BarnCRM Connections | Created by BarnCRM in your org, not part of the package. It holds each connection's principal access and is given only to Connector admins when they create or check a connection, and to the Automated Process user when you save Recipe Access. Do not add other permissions to it: Health Check warns when it holds anything else. |

## Health Check

With the module installed, Health Check reports:

- connections whose callouts are still off in Setup;
- connections missing from the BarnCRM Connections permission set;
- keys replaced in the last 7 days, by connection;
- the BarnCRM Connections permission set holding anything other than connection access;
- every recipe that runs as System, with who chose it and when;
- Active BarnCRM Automation recipes while Recipe Access has never been saved.

## Removing It

Delete each recipe, then each connection, on **Super Connector** first, so no credential is left
in Setup, then uninstall the module from the [Module Manager](module-manager.md). Delete the
**BarnCRM Connections** permission set in Setup afterwards if you no longer need it, and remove
the Recipe Access sets from the Automated Process user if you want them gone.
