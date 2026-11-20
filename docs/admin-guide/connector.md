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
| Schedule | The recipe clock, every 15 minutes, every hour, every day at a time, or every week on a day at a time. Times are in your org's time zone. The steps read the time it was due as `trigger.scheduledAt`. |
| Record Change | Records of an object created, or created or changed, that match a saved Find query (see [Find](find.md)). The clock looks every 15 minutes. **One Run per Record** starts a run for each record (`trigger.recordId`, `trigger.record.LastName`); **One Run for All** starts one run with them all (`trigger.recordIds`, `trigger.records[0].LastName`). **Most Records per Look** is 1 to 200 (200 when blank). |
| Another App Sends Data | Another app posts to the recipe's webhook address (see [Webhooks: Data Sent In](#webhooks-data-sent-in)). The steps read the posted JSON under `trigger`, such as `trigger.amount` or `trigger.donor.email`. |

A Record Change recipe starts from the moment you publish it: records changed before then are
not run. It reads the fields the saved query lists, sees imports and bulk updates, and carries on
where it stopped after a pause or an outage; it does not see deleted records. **Ignore Own
Changes** (on by default, in **Run Settings**) skips records last changed by a recipe, so a
recipe that updates the records it watches does not start itself again. App polling comes in a
later release.

### Webhooks: Data Sent In

A webhook recipe gives another app (a giving form, an event tool, a survey) an address to post
data to. BarnCRM only stores each post and answers at once; the recipe's steps run moments later,
as the recipe's Run As, never as the visitor or the app.

**Once per org: a Site.** The address is on a Salesforce Site, because an app posting data has
no Salesforce login. Experience Cloud is not needed. Any active Site works, such as the one
Payments or Forms already uses:

1. If your org has no Site: in Setup, **Sites**, register a domain if asked, then select **New**,
   give the Site a label and name, leave the home page as it is, tick **Active** and save.
2. Open **Health Check**. **Site Guest Missing Webhook Access** lists each Site whose guest user
   does not yet hold **BarnCRM Connector Webhook Guest**; select **Give Webhook Access**. (In
   Setup you can instead open the Site, **Public Access Settings**, **View Users**, the guest
   user, and add that permission set.)

The guest set gives the receiver class and nothing else: no object, field, record, connection
or key.

**Per recipe:**

1. Choose **Another App Sends Data** as the recipe's **When** and save the draft.
2. On the **Webhook** card, select **New Webhook Token**. The token appears once, with the
   address and both ways to send it; copy them now. BarnCRM keeps only a fingerprint of the
   token, so nobody, you included, can see it again. **New Webhook Token** again replaces it, and
   the old token stops working at once.
3. In the other app, set the webhook address and, where the app allows custom headers, a header
   named `X-BarnCRM-Token` holding the token. Use the address ending in `?token=` only for an app
   that cannot send headers: an address can be written to the app's logs.
4. Paste an example of the app's post into the recipe's sample data, so value paths such as
   `trigger.amount` are offered, then build the steps, test and publish.

| Setting | Default | What it does |
|---|---|---|
| Event Id | Blank | A value path to the post's own id, such as `trigger.id`. When the app sends the same post again, it is answered as before and not run twice. |
| Reply Status | 202 | 200 or 202, sent to the app at once. |
| Reply Body | `{"received": true, "reference": "{reference}"}` | Fixed JSON, at most 4,000 characters. `{reference}` becomes the run's reference, which Run History shows, so the app and BarnCRM can be matched. It can never hold a record or a result, because nothing has run yet. |
| Challenge Field | Blank | For an app that confirms a new address by sending a value and expecting it back: the name of that field (in the posted JSON or the address). Its value is sent back as plain text. |
| Webhook Hourly Cap | 500 | 1 to 5,000 posts kept in any hour. More are refused with 429, which apps treat as "try again later", and one Error Log warning an hour names the recipe. |

**What the receiver refuses, with an empty answer:** a post with no token, a wrong token or a
recipe never published (404, nothing kept); a body over 131,072 characters (413); a body that is
neither JSON nor form fields (415, or 400 when unreadable); a post past the hourly cap (429). A
Paused recipe still keeps posts, up to its cap, and runs them when you select **Resume**.

**Keep a stolen token from doing harm.** Anyone with the token can post data, so a post is
untrusted: it can only do what the recipe's steps do, and a value holding a Salesforce merge
field fails any step that would send it. When the app has an API, prefer **fetch back**: make
the first step a **Call an App** GET over a connection to that app, using the post's id in the
path (such as `/orders/{id}` with `trigger.id`) or, when the post carries the item's own API
address (such as Eventbrite's `api_url`), **Address From the Data**. The recipe then writes what
the app itself says, not what was posted. Apps that insist on a signed handshake (such as Zoom)
cannot use a webhook recipe; use a Schedule recipe that calls the app instead.

### The Recipe Clock

Schedule and Record Change recipes need no Scheduled Apex and no person. Each Run As lane has a
heartbeat: a short job that starts every 5 minutes while the lane has work, runs or polls each
recipe that is due, queues again the runs waiting for a retry and starts the runner. It runs as
the lane's identity (the Automated Process user, or the integration user), so it never stops
because someone left. The nightly run (see [Nightly Jobs](nightly-jobs.md); step **Connector
Cleanup**, on by default at 2:40) restarts a heartbeat that stopped and deletes old runs (see
[Run History](#run-history)).

**Recipe Clock** (on the Recipes tab) shows each lane, whether it has work and whether its
heartbeat is going, with:

- **Pause All Recipes**: the clock and the runners stop starting runs, org-wide, until you turn
  it off. Queued runs wait; Test runs from the editor still run. BarnCRM's own pause in
  [Automation Control](automation-control.md) pauses recipes too.
- **Restart Clock**: starts the heartbeat of each lane with work. Health Check sends you here
  when a lane stopped.

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
| Call an App | Sends one request over a connection and keeps the app's answer. | The connection; GET, POST, PUT, PATCH or DELETE; the path after the connection's base URL, such as `/contacts/{id}`; a value for each `{slot}`; query parameters; extra headers; a body map (a map that builds JSON) and the value path it reads; the status codes that count as success (blank is any 2xx); whether a 404 is all right. Or, in place of the path, **Address From the Data**: a value path to a full address on the connection's own host, for fetch back. |
| Send to Webhook | Posts JSON to another app's webhook over a connection and keeps the app's answer (see [Sending Data Back](#sending-data-back)). | The connection; a path (blank posts to the connection's own address) or **Address From the Data** for a callback address the app sent; extra headers; the body map and the value path it reads; the status codes that count as success. |
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
The same rules hold for Send to Webhook. An **Address From the Data** is used only when it is
`https`, holds no user name, is on the connection's exact host and port and starts with the
connection's own path; only its path and query are sent, through the connection. Any other
address, such as `https://api.example.com.attacker.net` or `https://api.example.com@attacker.net`,
fails the step and nothing is sent.

### Sending Data Back

A recipe sends data back to an app in two ways:

- **At once, to the app that posted:** the webhook's reply (see
  [Webhooks: Data Sent In](#webhooks-data-sent-in)): a fixed status and body with the run's
  reference. Nothing the recipe works out can go in it, because the steps have not run yet.
- **After the steps run, through a connection:** **Send to Webhook** posts JSON built by a body
  map to the app's webhook (a Secret URL connection for an address that is itself the secret,
  such as a Slack incoming webhook or a Microsoft Teams Workflows address; a Generic REST
  connection otherwise). When the post carried a reply address (such as `response_url`), set
  **Address From the Data** to it, with a connection to that app's host. **Call an App** can also
  update the item that started the run through the app's API. These steps run when the runner
  reaches them, normally within a minute of the post, and are retried like any call.

### Run As

| Run As | What the steps may do |
|---|---|
| BarnCRM Automation (the default) | What the Recipe Access sets allow, with field-level security and sharing. Publish checks every record map against those sets and refuses a map whose object or fields they do not grant. |
| System | Everything, without permission or sharing checks. Choosing it asks you to confirm; who chose it and when are shown on the recipe, and Health Check lists every System recipe. Use it only when Recipe Access cannot be widened. |
| Integration User | What the user you choose in **Integration User** may do, with field-level security and sharing. Use it when an app or your audit needs records changed by a named user, or when a recipe needs access the Automated Process user cannot hold. Publish checks every record map against that user's access. |

BarnCRM Automation and System run as the Automated Process user; Integration User runs as the
user you choose. Who started a run never matters.

### Integration User

Salesforce lets a platform event trigger run as a chosen user only through a subscriber setting
Setup shows but cannot edit, so BarnCRM writes it for you:

1. Create or pick a user for recipes only, such as "BarnCRM Integration", with a Salesforce
   license that lets it edit what your recipes write. Give it the permission sets your
   Integration User recipes need. Keep it active.
2. On **Super Connector**, open **Recipes**, then **Recipe Clock**. Under **Integration User**,
   choose the user and select **Save User**. BarnCRM saves the choice org-wide, writes the
   subscriber setting **BarnCRM_Connector_Start_User** through the org connection
   (`Barn_Org_Connection`, set up as in [Creating a New Field From an
   Import](import-new-fields.md)), and gives the user **BarnCRM Connections**, taking it from the
   user chosen before unless that user is a Connector admin.
3. In Setup, open **Platform Events**, then **Connector Start User**. Under **Subscriptions**,
   select **Suspend** on the trigger's row, then **Resume**. The new user takes effect at once.
4. Back on Recipe Clock, the card shows **Confirmed** once a job has run as the user.

Integration User recipes can be chosen only while a user is chosen and active. When the user is
deactivated, those recipes stop: Health Check reports **Integration User Inactive** with the
recipes it stops. Choose another user, then Suspend and Resume again. Saving with no user clears
the subscriber setting. The card shows the last write's job status; a refused write is in the
Error Log, and the user's access stays as it was.

### Run Settings, Retries and Pausing

Each saved recipe has **Run Settings**:

| Setting | Default | What it does |
|---|---|---|
| Retry Attempts | 3 | 0 to 4. A run that failed for a reason that may pass (the app could not be reached, or answered 408, 429, 500, 502, 503 or 504) waits and is tried again from its failed step: after 15 minutes, 1 hour, 4 hours and 12 hours. When the app sends `Retry-After`, the run waits that long instead, at most a day. Test runs are never retried. |
| Pause After Failures | 10 | 1 to 100. A recipe whose runs fail this many times in a row is **Paused by Failures**: it neither polls nor runs, and one Error Log entry says so. |
| Keep Runs Days | 30 | 7 to 365. The nightly step deletes the recipe's finished runs older than this, at most 9,000 a night. Waiting and Queued runs are kept. |
| Ignore Own Changes | On | For Record Change: skip records last changed by a recipe identity. |

**Pause** stops an Active recipe; its queued runs wait. **Resume** makes a Paused or Paused by
Failures recipe Active again, counts its failures from 0, gives a schedule its next time and lets
a Record Change carry on from where it stopped. **Retry All Failed** queues every failed run of
the recipe again from its failed step, up to 200 at a time.

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

**Run History** lists the latest 50 runs, newest first, with the recipe, status (Received,
Queued, Waiting, Succeeded, Skipped, Failed), what started it (Manual, Flow, Test, Schedule,
Record Change, Webhook), Run As, version, records written, the failed step and, for a Waiting run,
when it is tried next. A webhook run also shows the reference its app was given. Open a run to see each step: its outcome, how long it took, the
records it wrote, the app's status code and, for a failed Call an App, the first 2,000 characters
of the app's answer. A Test run also shows what each step would have written or sent. No request
header and no key is ever kept.

**Retry** (BarnCRM Connector Admin only) queues a failed run again from its failed step: steps
that already succeeded are not repeated. Each failed run also writes one Error Log entry naming
the recipe, run, step and plain message, never the request. The nightly step deletes finished
runs older than each recipe's **Keep Runs Days**.

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
| BarnCRM Connector Webhook Guest | For a Site's guest user only: the webhook receiver and nothing else (no object, record, connection or key). Health Check's **Give Webhook Access** assigns it. |
| BarnCRM Connections | Created by BarnCRM in your org, not part of the package. It holds each connection's principal access and is given only to Connector admins when they create or check a connection, to the Automated Process user when you save Recipe Access, and to the integration user when you choose it. Do not add other permissions to it: Health Check warns when it holds anything else. |

## Health Check

With the module installed, Health Check reports:

- connections whose callouts are still off in Setup;
- connections missing from the BarnCRM Connections permission set;
- keys replaced in the last 7 days, by connection;
- the BarnCRM Connections permission set holding anything other than connection access;
- every recipe that runs as System, with who chose it and when;
- Active BarnCRM Automation recipes while Recipe Access has never been saved;
- a lane with Schedule, Record Change or waiting runs whose heartbeat is not going, with **Open
  Super Connector** to restart it;
- **Integration User Inactive**: Active Integration User recipes while no user is chosen or the
  user is inactive (an error), or the user lacks BarnCRM Connections (a warning);
- runs Queued for more than 30 minutes, for example after a subscriber change not yet applied
  with Suspend and Resume;
- recipes Paused by Failures, and Active recipes whose Owner of New Records is inactive;
- Pause All Recipes on;
- while a published recipe receives webhooks: no active Site, and **Site Guest Missing Webhook
  Access** for each Site whose guest user lacks BarnCRM Connector Webhook Guest, with **Give
  Webhook Access**.

## Removing It

Delete each recipe, then each connection, on **Super Connector** first, so no credential is left
in Setup, then uninstall the module from the [Module Manager](module-manager.md). Delete the
**BarnCRM Connections** permission set in Setup afterwards if you no longer need it, and remove
the Recipe Access sets from the Automated Process user if you want them gone. Before
uninstalling, save **Integration User** with no user, so the subscriber setting is removed, and
remove **BarnCRM Connector Webhook Guest** from each Site guest user that holds it.
