# BarnCRM Connector

Scripts for the optional BarnCRM Connector module, release 1.31: creating Connections of each sign-in kind, the one Setup step with Check Again, checking, replacing, disconnecting and deleting, the refusals that keep keys safe, access and Health Check (CN-01, T-CN-01 to T-CN-06); Recipe Access, recipes, Test, Publish, Run Now, Run History, Retry, Run As and the merge-field guard (CN-02, T-CN-07 to T-CN-12); the Flow actions and Where Used (CN-06, T-CN-13 and T-CN-14); the recipe clock, Schedule and Record Change triggers, retries, pausing, the integration user, Health Check and the nightly cleanup (CN-03, release 1.32, T-CN-15 to T-CN-20); scheduled imports through Load Rows with an Import Template (CN-09, release 1.32, T-CN-21 and T-CN-22); webhooks in, their refusals, fetch back and Send to Webhook (CN-04, release 1.32, T-CN-23 to T-CN-25); For Each, Wait and Change Data (CN-05, release 1.32, T-CN-26 to T-CN-28); versions, Roll Back, Export Recipe and the Templates tab (CN-08, release 1.32, T-CN-29 to T-CN-31); watching an app for new items and erasing a person's runs (CN-13, CN-18, release 1.33, T-CN-32 to T-CN-34); the backup destination and its storage services, S3 and OAuth (BK-10, release 1.36, T-CN-35 and T-CN-36). Setup detail: [BarnCRM Connector](../admin-guide/connector.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and BarnCRM Connector deployed, and an HTTPS test endpoint that echoes requests (for example a free request bin you control). Use made-up keys such as `test-key-1234`; never a real one. In a Developer Edition or trial org, Salesforce stops a chain of queued jobs after 5 links, so many runs queued at once (more than about 5 batches of 50, or a long run that continues across many transactions) may stop partway: the rest wait for the next start, and Health Check may show runs waiting. That is the org's limit, not a fault; a sandbox or production org has no such cap.

## T-CN-01: Install, App and Access

**Purpose:** confirm the module installs with its app, tab and admin set, and nothing else is needed.
**Prerequisites:** admin (BarnCRM Admin).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Modules**, install or turn on **BarnCRM Connector**. | Listed as Beta in both editions. You hold **BarnCRM Connector Admin**. |
| 2 | Open the **BarnCRM Connector** app (or the **Super Connector** tab in a BarnCRM admin app on an org with capped apps). | **Super Connector** opens with the keys icon, **Connections** and **No connections yet**. **Error Log** is the last tab of the app. |
| 3 | Open **Setup**, **Permission Sets**. | No **BarnCRM Connections** set yet (it is created with the first connection). |

**Cleanup:** None.

## T-CN-02: Create a Bearer Token Connection and the Setup Step

**Purpose:** confirm a key is saved into Salesforce credentials, never shown again, and the Setup step with Check Again works (R-CN1 to R-CN3, F3, F10).
**Prerequisites:** admin, after T-CN-01.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **New Connection**. | A form with Name, Sign-In Kind (Bearer Token), Base URL and a password box, and the debug logging notice. |
| 2 | Enter Name `Echo Test`, Base URL your endpoint (`https://...`), key `test-key-1234`, and select **Create Connection**. | `Connection created`, the key box is empty, and the row shows `Bearer Token, <host>` with **Callouts Off** and the Setup steps. |
| 3 | Look at the browser's network answers for the page. | The key appears in none of them. |
| 4 | In **Setup**, **Named Credentials**, open the new `BarnConn_rest_...` credential. | Its URL is your base URL; **Allow Formulas in HTTP Body** is off; an `Authorization` header; **Enabled for Callouts** off. The External Credential's principal shows the key as stored, not readable. |
| 5 | Tick **Enabled for Callouts**, save, and on Super Connector select **Check Again**. | **Ready** (or `You were given access` first, then **Ready** on the next check). **BarnCRM Connections** now exists and you hold it. |
| 6 | Select **Check Connection**. | `Connected` with the status your endpoint returned; the endpoint received `Authorization: Bearer test-key-1234`. |

**Cleanup:** None (used below).

## T-CN-03: The Other Sign-In Kinds

**Purpose:** confirm API Key in a Header, Basic and Secret URL connections, and the Secret URL disclosure (F5).
**Prerequisites:** admin, after T-CN-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create an **API Key in a Header** connection with header `X-Api-Key`, then try header `Authorization`. | `X-Api-Key` saves; `Authorization` is refused with the header name message. After the Setup step, Check Connection sends `X-Api-Key: <key>`. |
| 2 | Create a **Basic** connection without a user name, then with user `api-user`. | Without: `Enter the user name.` With: saved; after the Setup step the endpoint receives `Authorization: Basic` with the encoded user name and key. |
| 3 | Choose **Secret URL**. | No Base URL field; the key box asks for the Secret URL; a warning says the address is readable in Setup and suggests Bearer Token. |
| 4 | Enter your endpoint with a path as the Secret URL and create it. | The row shows only the host and `address ending` with its last four characters; **Disconnect** is not offered. |

**Cleanup:** None.

## T-CN-04: Refusals

**Purpose:** confirm unsafe addresses, merge fields and credentials BarnCRM did not create are refused before anything is written (F2, F4, R-CN4).
**Prerequisites:** admin, after T-CN-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a connection with Base URL `http://example.org`, then `https://user:pw@example.org`, then `https://example.org/?key=1`, then `https://example.org/{!$Credential.X}`. | Each refused with the address message; no new Named Credential in Setup. |
| 2 | Run in Anonymous Apex as an admin: `ConnectorConnectionsController.deleteConnection('Barn_Org_Connection');` | Refused with `That is not a BarnCRM connection`; Core's `Barn_Org_Connection` is unchanged. |
| 3 | Select **Replace Key** on the Secret URL connection and enter an address on another host. Then do it again with an address on the same host and another path. | The other host is refused: the host must stay the same. The same host is saved (`Key replaced`), the row still shows only the host and the new last four characters, and the Named Credential URL in Setup is the new address. Within a minute the Admin Journal has a **Key Replaced** row for it. |
| 4 | On **Org Optimizer**, **Setup Changes**, press **Copy New Changes Now**, then **Refresh**, and search for `BarnConn_`. | The rows for the Secret URL connection show the address as its host and `/****` only, never its path. |

**Cleanup:** None.

## T-CN-05: Replace, Disconnect and Delete

**Purpose:** confirm key changes are journaled and shown in Health Check, and removal leaves nothing behind (R-CN6, F12).
**Prerequisites:** admin, after T-CN-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Echo Test** select **Replace Key**, enter `test-key-5678` and save. | `Key replaced`; Check Connection sends the new key. The Admin Journal has a **Connection** row, **Key Replaced**, with your name and the connection, without the key. |
| 2 | Open **Health Check**. | `Connection Keys Replaced This Week` names Echo Test. |
| 3 | Select **Disconnect**, **Cancel**, then **Disconnect** and confirm. | Cancel changes nothing; confirming shows **Disconnected**, the row says no key is stored, and Check Connection no longer sends a key. A Secret URL connection offers no Disconnect. |
| 4 | Select **Delete** and confirm on each test connection. | `Connection deleted`; each row goes, and in Setup no `BarnConn_rest_...` Named or External Credential is left. |

**Cleanup:** None.

## T-CN-06: Access and Health Check

**Purpose:** confirm only Connector admins manage connections, saving a key also needs the credential permission, and Health Check reports what needs doing (F3, F7).
**Prerequisites:** admin, and a staff user without BarnCRM Admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user, open the Super Connector tab by URL. | No access to the tab; no connection data. |
| 2 | Give a test user **BarnCRM Connector Admin** but not Customize Application or Manage Named Credentials, and open Super Connector as them. | They can check connections; **New Connection** and **Replace Key** are not offered, and a notice says why. |
| 3 | As the admin, create a connection and leave its callouts off. Open **Health Check**. | `Connections Waiting for Their Setup Step` names it. |
| 4 | In Setup add any object permission to **BarnCRM Connections**, then open Health Check. | `BarnCRM Connections Holds Extra Access`. Remove the permission; the finding goes. |

**Cleanup:** Delete the test connection; remove BarnCRM Connector Admin from the test user.

## T-CN-07: Recipe Access

**Purpose:** confirm recipes get only the access the admin chooses, through the Automated Process user.
**Prerequisites:** admin, after T-CN-02 (one connection with callouts on and Check Connection passing).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Super Connector**. | Three tabs: **Recipes** (open), **Run History** and **Connections**. Recipes says **No recipes yet.** |
| 2 | Select **Recipe Access**. | A card lists permission sets with **BarnCRM Admin** and the installed module admin sets ticked, and a notice that Recipe Access has not been saved. BarnCRM Connector Admin and Viewer are not listed. |
| 3 | Untick one module set and select **Save Access**. | **Recipe Access saved.** A query on PermissionSetAssignment for the user whose UserType is AutomatedProcess shows it holds the ticked sets and **BarnCRM Connections**, not the unticked one. |

**Cleanup:** None (later scripts need Recipe Access saved).

## T-CN-08: Build, Test and Publish a Recipe

**Purpose:** confirm a recipe with Find, Create or Update and Call an App can be built, tested without writing, and published.
**Prerequisites:** admin, after T-CN-07; a saved Find query on Contact with an Email condition; a record map **Contact by Email** (record, Contact, match by Email, column `email` to Email, `last` to LastName); a JSON map **Person Body** (`last` to `name`).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Recipes**, select **New Recipe**. Name it `Welcome Test`. In **Sample Data (JSON)** enter `{"email":"ada.test@example.org","last":"Lovelace"}`. | The editor opens with **No steps yet.**, **Save the draft to choose Run As.** and a problem saying the recipe has no steps. |
| 2 | **Add Step**, **Create or Update a Record**. Choose map **Contact by Email**; leave **Reads From** as `trigger`. | Step `upsert1` appears; the value path hint lists `trigger.email` and `trigger.last`. |
| 3 | **Add Step**, **Call an App**. Choose the connection, **POST**, path `/people/{id}`, slot value `steps.upsert1.id`, body map **Person Body**. | Step `callApp1`; the problems notice is gone. |
| 4 | Type `/people/{id}?x=1` in **Path**. | A problem names step `callApp1`'s path. Put back `/people/{id}`. |
| 5 | Select **Save Draft**, then **Test**. Wait a moment and select **Check Result**. | **Draft saved.** then **The test was queued.** The result shows Succeeded with both steps; `upsert1` shows the fields it would write; `callApp1` shows the POST it would send. No Contact was created and the echo endpoint got nothing. |
| 6 | Select **Publish**. | **Published as version 1. The recipe is Active.** The list shows Active, Runs as BarnCRM Automation, version 1. |

**Cleanup:** None (T-CN-09 uses the recipe).

## T-CN-09: Run Now, Run History and Retry

**Purpose:** confirm a run writes, calls the app after a checkpoint, and that a failed run is shown plainly and retried from its failed step.
**Prerequisites:** admin, after T-CN-08.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open `Welcome Test`. In **Data for This Run (JSON)** enter `{"email":"ada.test@example.org","last":"Lovelace"}` and select **Run Now**. | **R-... was queued. See Run History.** |
| 2 | Open **Run History** and **Refresh** until the run ends. | Succeeded, started by Run Now, ran as BarnCRM Automation, version 1, 1 record written. The Contact exists. The echo endpoint got one POST to `/people/<Contact Id>` with `{"name":"Lovelace"}` and the connection's sign-in, and no other header the recipe set. |
| 3 | Open the run. | Each step with its outcome and time; `upsert1` lists the Contact Id; `callApp1` shows HTTP 200 (or the endpoint's code). |
| 4 | Change the connection's base URL path or the recipe path so the app answers 404 or 500 (for example path `/missing/{id}`), publish, and Run Now again. | Run History shows Failed at step `callApp1` with a plain message; opening it shows the app's status and the first part of its answer. One Error Log entry names the recipe, run and step, with no key or header. |
| 5 | Put the path back, publish, and select **Retry** on the failed run. | **R-... was queued again from its failed step.** The run ends Succeeded; `upsert1` was not run again (still one Contact, one write in the step log). **Retry** is no longer offered on it. |

**Cleanup:** Delete the test Contact.

## T-CN-10: Run As System and Health Check

**Purpose:** confirm System needs confirmation, is recorded and listed by Health Check, and that BarnCRM Automation is checked against Recipe Access at Publish.
**Prerequisites:** admin, after T-CN-08.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Recipe Access, untick every set and save (only BarnCRM Connections stays). Publish a new recipe with one Create or Update a Record step using `Contact by Email`. | Publish is refused, naming Contact as the object Recipe Access does not grant. |
| 2 | On that recipe choose **Run As**, **System**, then **Cancel** in the confirmation. | Run As stays BarnCRM Automation. |
| 3 | Choose **System** again and confirm with **Run as System**. | **Run As saved.** and **Chosen by <you> on <date>.** Publish now succeeds. |
| 4 | Open **Health Check**. | An info finding lists the recipe as running as System, with who chose it and when. |
| 5 | Set Run As back to **BarnCRM Automation**, restore Recipe Access. | The Health Check finding is gone. |

**Cleanup:** Delete the test recipe.

## T-CN-11: Merge-Field and Path Guard (F1, F4)

**Purpose:** confirm a recipe can never make Salesforce insert a key or reach another host.
**Prerequisites:** admin, after T-CN-08.

| Step | Action | Expected result |
|---|---|---|
| 1 | On `Welcome Test`, add a header `X-Test` with value `{!$Credential.Password}` (type it exactly). | A problem: merge fields are refused. **Save Draft** is refused by the server with the same message. Remove the header. |
| 2 | Set the path to `//evil.example/x`, then `/a@b`, then `/a b`. | Each is refused as an unsafe path. Put back `/people/{id}`. |
| 3 | Add a header named `Authorization`. | Refused: sign-in headers come from the connection. Remove it. |
| 3a | Add a header `X-Api-Key` with the typed value `abc123`, and **Save Draft**. Then set its value from the trigger (`trigger.key`) and save. | The typed value is refused: the header looks like a sign-in header, so keys belong on the connection. The value from the trigger saves. Remove the header. |
| 4 | Run Now with data `{"email":"ada.test@example.org","last":"{!$Credential.Password}"}`. | The run fails at `callApp1` with a message that the value holds a merge field; the echo endpoint got nothing. The Error Log entry has no key and no request. |
| 5 | Run Now with `{"email":"ada.test@example.org","last":"Lovelace / Ada?x=1"}` and a path slot reading `trigger.last`. | The endpoint gets `/people/Lovelace%20%2F%20Ada%3Fx%3D1`: one path segment, no query. |

**Cleanup:** Delete the test Contact.

## T-CN-12: Viewer Access

**Purpose:** confirm Viewers see recipes and runs and change nothing.
**Prerequisites:** admin, and a test user given **BarnCRM Connector Viewer** only.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the test user, open **Super Connector**, **Recipes**, and open `Welcome Test`. | The recipe shows read only: no **New Recipe**, **Recipe Access**, **Save Draft**, **Publish**, **Test**, **Run Now** or **Delete**. |
| 2 | Open **Run History**. | Runs are listed and can be opened; no **Retry**. |
| 3 | As the test user, open **Connections**. | A notice says Connector admins manage connections; no connection is listed and no error shows. |

**Cleanup:** Remove BarnCRM Connector Viewer from the test user.

## T-CN-13: Flow Actions

**Purpose:** confirm a flow can queue a recipe and apply a saved map, each with the right identity.
**Prerequisites:** admin, after T-CN-08; a test user with Contact access but no BarnCRM Connector set.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Flow Builder, build a screen flow with an Action **Run a BarnCRM Connector Recipe** (Recipe Name `Welcome Test`, Data `{"email":"flow.test@example.org","last":"Flow"}`) and show its Message. Run it as the test user. | Queued is true and a run Id is returned. Run History shows the run started by Flow, ran as BarnCRM Automation, and it succeeds although the test user has no Connector access. |
| 2 | Enter a Recipe Name that is Draft or does not exist. | Queued is false and the message says the recipe is not Active or not found; nothing is queued. |
| 3 | Add an Action **Apply a Saved Map** (Map Name `Contact by Email`, Data `{"email":"flow.test@example.org","last":"Changed"}`) and run it as the test user. | Action is updated and the Contact's last name is Changed. |
| 4 | Remove Contact edit from the test user and run step 3 again. | The action returns a plain message that the save was refused; nothing changes. |
| 5 | Run **Apply a Saved Map** with `Person Body` (a JSON map). | Refused: only a record map can be applied. |

**Cleanup:** Delete the flow and the test Contact; restore the test user's access.

## T-CN-14: Where Used and Connection In Use

**Purpose:** confirm recipes appear in Where Used and keep their connection from being deleted.
**Prerequisites:** admin, after T-CN-08.

| Step | Action | Expected result |
|---|---|---|
| 1 | Add a **Find Records** step using the saved Contact query with the Email condition to `Welcome Test` and save. Open **Where Used** for Contact.Email. | `Welcome Test` is listed with its Find step (Step find1); its edit link opens Super Connector on that recipe. |
| 2 | Open **Where Used** for the map `Contact by Email`. | `Welcome Test` is listed with Step upsert1, with a warning that changing the map changes what the recipe writes. |
| 3 | On **Connections**, delete the connection `Welcome Test` calls. | Refused: the connection is used by a recipe. Delete the recipe first, then the connection deletes. |
| 4 | Create a Record Change recipe on Contact whose condition is Title is not blank, and save it. Open **Where Used** for Contact.Title. | The recipe is listed with **Trigger**. |

**Cleanup:** Delete the test recipe, then the test connection.

## T-CN-15: A Schedule Recipe and the Recipe Clock

**Purpose:** confirm a Schedule recipe runs on the clock as the Automated Process user, with no Scheduled Apex.
**Prerequisites:** admin, after T-CN-07 (Recipe Access saved).

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **New Recipe**, name it `Clock Test`. Under **When**, choose **Schedule**, **Every** **15 Minutes**. Add a **Stop** step (Succeeded). Save and **Publish**. | The recipe is Active; the editor shows **Next run** about 15 minutes ahead in your time zone. The list shows Schedule, runs as BarnCRM Automation. |
| 2 | Select **Recipe Clock** on the Recipes tab. | The BarnCRM Automation and System lane shows **Going** (or **Stopped** for a moment before the first beat); Integration User shows **No Work**. |
| 3 | In Setup, open **Scheduled Jobs**, then **Apex Jobs**. | No Scheduled Apex job for Connector. Apex Jobs lists `ConnectorClock` Queueable jobs submitted by the Automated Process user. |
| 4 | Wait until the next run time, then open **Run History** and **Refresh**. | A run started by Schedule, ran as BarnCRM Automation, Succeeded. The recipe's next run moved on 15 minutes. |
| 5 | Change **Every** to **Week**, a time a few minutes ahead and today's day. Save and Publish. | **Next run** is that time today. After it passes, one Schedule run appears. |

**Cleanup:** Keep `Clock Test` for T-CN-17.

## T-CN-16: A Record Change Recipe

**Purpose:** confirm a Record Change recipe runs for new and changed records only, once each, and does not start itself.
**Prerequisites:** admin, after T-CN-08 (the `Contact by Email` map); a saved Find query on Contact with LastName and Email.

| Step | Action | Expected result |
|---|---|---|
| 1 | New recipe `Watch Contacts`: **When** **Record Change**, the saved Contact query, **New and Changed Records**, **One Run per Record**. One **Update a Record** step using `Contact by Email`, record `trigger.recordId`, reading `trigger.record`. Publish. | Publish succeeds. The value path hints list `trigger.recordId` and `trigger.record.LastName`. |
| 2 | Create two Contacts by hand, then wait up to 20 minutes and refresh Run History. | Two runs started by Record Change, one per Contact, Succeeded. A Contact created before Publish has no run. |
| 3 | Wait another 20 minutes. | No new runs: the recipe's own update is skipped (Ignore Own Changes), and nothing is run twice. |
| 4 | Change **Runs** to **One Run for All**, publish, and update both Contacts. | After the next look, one run whose data holds `recordIds` with both Ids. |
| 5 | Import 50 Contacts with the Data Import Wizard. | Runs appear for them within the next looks, at most 200 records per look. |

**Cleanup:** Delete `Watch Contacts` and the test Contacts.

## T-CN-17: Retries, Pause After Failures and Pause All

**Purpose:** confirm a failure that may pass waits and is retried, a recipe that keeps failing pauses itself, and Pause All stops every recipe but Test.
**Prerequisites:** admin, after T-CN-15; an echo endpoint you can make answer 503.

| Step | Action | Expected result |
|---|---|---|
| 1 | Add a **Call an App** GET step to `Clock Test` against the endpoint, set it to answer 503, and publish. | After the next run, Run History shows the run **Waiting** with **Tried again at** about 15 minutes later. |
| 2 | Wait 15 minutes. | The run was tried again (Attempt 1) and waits again about 1 hour. |
| 3 | In **Run Settings**, set **Retry Attempts** 0 and **Pause After Failures** 2, then **Save Run Settings**. Wait for two runs. | Both runs are Failed. The recipe is **Paused by Failures**; one Error Log entry says it was paused after 2 failures in a row. Health Check lists it under Recipes Paused by Failures. |
| 4 | Make the endpoint answer 200. Select **Retry All Failed**, then **Resume**. | **Failed runs queued again: 2.** They end Succeeded. The recipe is Active and its failures in a row are 0. |
| 5 | On **Recipe Clock**, turn on **Pause All Recipes**. Wait past the next run time. In the editor, select **Test**. | No new Schedule run; the Test run still runs. Health Check shows All Recipes Paused. |
| 6 | Turn **Pause All Recipes** off. | **Pause All Recipes is off.** The next Schedule run appears on time. |

**Cleanup:** Delete `Clock Test`.

## T-CN-18: The Integration User

**Purpose:** confirm the integration user is written as the lane's running user, its recipes run as that user, and an inactive user is reported.
**Prerequisites:** admin; the org connection set up (see the Admin Guide page Creating a New Field From an Import); a spare active user with a Salesforce license and Contact access, here `Integrator`.

| Step | Action | Expected result |
|---|---|---|
| 1 | On a saved recipe, open **Run As**. | Only BarnCRM Automation and System are offered. |
| 2 | On **Recipe Clock**, under **Integration User**, choose a user with a Customer Community or other non-Salesforce license and **Save User**. | Refused: **Choose an active user with a Salesforce license.** |
| 2a | Choose yourself (a System Administrator) and **Save User**. | Refused: the user must not be a System Administrator or hold Modify All Data or View All Data. |
| 2b | On an Integration User recipe, before any user is saved, select **Run Now**. | Refused: **Choose an active integration user on Recipe Clock first.** No run is queued. |
| 3 | Choose `Integrator` and **Save User**. | **Saved. BarnCRM is writing the subscriber setting...**. Reopen Recipe Clock: `Integrator` is shown, the last write is Completed, and `Integrator` holds **BarnCRM Connections** (Setup, the user's permission set assignments). |
| 4 | In Setup, open **Platform Events**, **Connector Start User**, **Subscriptions**. | The trigger row shows **Running User** `Integrator`. Select **Suspend**, then **Resume**. |
| 5 | Set a Schedule recipe's Run As to **Integration User** and publish. | Its runs show ran as Integration User; records it writes show `Integrator` as Last Modified By. Recipe Clock shows **Confirmed**. |
| 6 | Deactivate `Integrator` (or, if it must stay, freeze it). Open **Health Check**. | An error **Integration User Inactive** names `Integrator` and the recipe. The recipe's runs stay Queued; after 30 minutes Health Check also shows Recipe Runs Waiting to Start. |
| 7 | Reactivate `Integrator`, then on Recipe Clock choose no user and **Save User**. | The subscriber setting is gone from the Subscriptions list after Suspend and Resume; `Integrator` no longer holds BarnCRM Connections. |

**Cleanup:** Set the recipe back to BarnCRM Automation, or delete it.

## T-CN-19: Health Check and Restart Clock

**Purpose:** confirm a stopped lane is reported with a way to restart it.
**Prerequisites:** admin, an Active Schedule recipe.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Setup, **Apex Jobs**, abort every queued `ConnectorClock` job. Open **Health Check**. | A warning **Recipe Clock Stopped** names the BarnCRM Automation and System lane, with **Open Super Connector**. |
| 2 | Select **Open Super Connector**, open **Recipes**, **Recipe Clock**, and select **Restart Clock**. | **The clock was restarted for each lane with work.** The lane shows **Going**; Health Check no longer reports it. |

## T-CN-20: The Nightly Cleanup

**Purpose:** confirm old finished runs are deleted on the nightly run and a stopped clock restarts.
**Prerequisites:** admin, a recipe with runs.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open BarnCRM Settings, **Nightly Jobs**. | **Connector Cleanup** at 2:40, switched on. |
| 2 | Set the recipe's **Keep Runs Days** to 7. The next morning, open Run History. | Finished runs older than 7 days are gone; Queued and Waiting runs and newer runs remain. If the clock was stopped, it is going again. |

## T-CN-21: A Scheduled Import Inside Its Limits

**Purpose:** confirm Load Rows with an Import Template stages, dry runs and commits through Super Importer when the dry run is inside every limit.
**Prerequisites:** admin; Recipe Access holds BarnCRM Admin; a Super Importer template with columns First Name, Last Name and Email, tried once on a file.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a recipe with **When** Run Now and a step **Load Rows with an Import Template**. | The step shows Import Template, Rows (`trigger.rows`) and the limits Most Rows 1,000, Most Rejected Rows 0, Most New Records 1,000, Most Updated Records 1,000. |
| 2 | Choose the template. Type 5000 in Most Rejected Rows. | The editor says each limit is a whole number from 0 to 4,000; Publish is off. Set it back to 0. |
| 3 | In the sample data, paste `{"rows":[{"First Name":"Test","Last Name":"Loader","Email":"loader@example.org"}]}`. Select **Test**, then **Check Result**. | Succeeded; the step shows the template, 1 row and the limits. Super Importer has no new data job. |
| 4 | Publish. Under Run Now, paste the same JSON and select **Run Now**. Open Run History. | The run is Waiting. Super Importer lists a data job named "Recipe <name>, run <run>", Dry run complete within a minute. |
| 5 | Wait up to 10 minutes and refresh Run History. | The run is Waiting again while the commit runs, then Succeeded; the step reads "Data job IB-...: 1 rows, 1 created, 0 updated, 0 rejected." Records Written is 1. The contact exists, and the data job is Complete with Undo available. |
| 6 | Change the recipe's When to a Schedule every day at a time a few minutes ahead, with an earlier Call an App step that returns rows, and publish. | The next day's run loads the rows on its own the same way. |

## T-CN-22: A Scheduled Import Outside Its Limits

**Purpose:** confirm nothing is committed when the dry run crosses a limit, and that the data job waits for a person.
**Prerequisites:** the recipe from T-CN-21.

| Step | Action | Expected result |
|---|---|---|
| 1 | Run Now with two rows, one without a Last Name (so the dry run rejects it). | After up to 5 minutes the run is Failed: "The dry run of data job IB-... would reject 1 rows, more than the limit of 0 set on this step, so nothing was committed." One Error Log entry names the recipe and step. |
| 2 | Open Super Importer. | The data job is Dry run complete; no contact was created. Commit it there: the valid row loads. |
| 3 | Set Most Rows to 1 and Run Now with two rows. | The run fails at once saying 2 rows arrived, more than the 1 the step allows; no data job is created. |
| 4 | In Recipe Access, untick BarnCRM Admin and save. Publish. | Publish refuses: recipes cannot create data jobs. Tick it again. |
| 5 | Retry the failed run from step 1 after raising Most Rejected Rows to 1 and publishing. | A new data job is staged and dry run, then committed; the run Succeeds. |

## T-CN-23: A Webhook Recipe

**Purpose:** confirm a post with the token is kept at once, answered with its reference and run as the recipe's Run As.
**Prerequisites:** admin, after T-CN-08 (the `Contact by Email` map); an active Salesforce Site (Setup, **Sites**); a terminal with `curl`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Health Check**. | A warning **Site Guest Missing Webhook Access** names the Site. Select **Give Webhook Access**: the finding is gone, and the Site's guest user holds **BarnCRM Connector Webhook Guest**. |
| 2 | New recipe `Gifts In`: **When** **Another App Sends Data**. Before saving, the **Webhook** card says **Save the draft to get a webhook address and token.** Save Draft. | The card shows the Site's **Address**, the **Header** `X-BarnCRM-Token` and **No token yet**. |
| 3 | Select **New Webhook Token**. | **Copy the token now.** The token and the **Address With Token** are shown. Copy both. |
| 4 | Paste `{"id":"evt_1","email":"ada@example.org","last":"Lovelace"}` as sample data. Add a **Create or Update a Record** step using `Contact by Email`, reading `trigger`. Set **Event Id** `trigger.id` and **Reply Status** 200. Publish. | Publish succeeds. The value path hints list `trigger.email`. |
| 5 | Run `curl -i -X POST -H "X-BarnCRM-Token: <token>" -H "Content-Type: application/json" -d '{"id":"evt_1","email":"ada@example.org","last":"Lovelace"}' "<address>"`. | `200` at once, with the body `{"received": true, "reference": "..."}`. |
| 6 | Open Run History. | A run started by **Webhook**, with the same **Reference**, Succeeded within a minute or two; the Contact exists. |
| 7 | Send the same `curl` again. | The same reply and reference; no second run. |
| 8 | Send it once more with `"id":"evt_2"` to the **Address With Token** and no header. | Accepted; a second run. |
| 9 | Pause the recipe and post `evt_3`. | Accepted; the run shows **Received** and waits. Select **Resume**: it runs. |

**Cleanup:** Keep `Gifts In` for T-CN-24; delete the test Contact.

## T-CN-24: Webhook Refusals

**Purpose:** confirm the receiver refuses everything without a valid token with an empty 404, and enforces its size, type and hourly limits.
**Prerequisites:** admin, after T-CN-23.

| Step | Action | Expected result |
|---|---|---|
| 1 | Post with no token, with a made-up 64-character token, and with `?token=abc`. | Each answers `404` with an empty body. Run History shows nothing new. |
| 2 | On `Gifts In`, select **New Webhook Token** and confirm **Replace the Webhook Token?**. Post with the old token. | `404`. The new token is accepted. |
| 3 | Post a body of 140,000 characters; then `{not json` with JSON content type; then `<a/>` with `Content-Type: application/xml`. | `413`, `400` and `415`, each with an empty body; nothing kept. |
| 4 | Post form fields `email=ada%40example.org&last=Lovelace` with `Content-Type: application/x-www-form-urlencoded`. | Accepted; the run's data holds `email` and `last` as text and no `token`. |
| 5 | Set **Webhook Hourly Cap** to 1 and **Save Cap**, then post twice. | The second is `429`. One Error Log warning names `Gifts In`; a third post adds no second warning. Set the cap back to 500. |
| 6 | Set **Reply Body** to `{"name": "{!$User.Email}"}` and publish. | Refused: **A recipe cannot hold a Salesforce merge field.** Set it back to the default. |
| 7 | Open the Site guest user's permission sets in Setup and **BarnCRM Connector Webhook Guest**. | Apex class access to the receiver and Read and Create on the two Connector Start events only: no object, field or record access. |

**Cleanup:** None.

## T-CN-25: Fetch Back and Send to Webhook

**Purpose:** confirm a recipe reads the item back from the app and sends data back over a connection, and that an address in the data never reaches another host.
**Prerequisites:** admin, after T-CN-23; a Generic REST connection `Echo` to your HTTPS echo endpoint (base path `/hooks`); a Secret URL connection `Chat` to a request bin standing in for a chat app's incoming webhook.

| Step | Action | Expected result |
|---|---|---|
| 1 | On `Gifts In`, add a first step **Call an App** over `Echo`, GET, **Address From the Data** `trigger.resource_url`. | The path, path values and query clear. |
| 2 | Add a last step **Send to Webhook** over `Chat`, path blank, with a JSON body map holding the email. Publish. | Publish succeeds. |
| 3 | Post `{"id":"evt_9","email":"ada@example.org","resource_url":"https://<echo host>/hooks/orders/9?expand=x"}`. | The run Succeeded. The echo endpoint received GET `/hooks/orders/9?expand=x`; the chat request bin received one POST with the mapped body. |
| 4 | Post `evt_10` with `resource_url` set to `https://evil.example/hooks/orders/9`, then to `http://<echo host>/hooks/orders/9`, then to `https://<echo host>/other/9`. | Each run Failed at the first step: **The address read from the data was not used, so nothing was sent...** Neither endpoint received anything for these runs. |

**Cleanup:** Delete `Gifts In`, `Echo` and `Chat`.
## T-CN-26: For Each Over a List

**Purpose:** confirm For Each runs its steps once per item, continues past 200 items without repeating one, and refuses more than 1,000.
**Prerequisites:** admin; a saved record map onto Contact with source columns `last` (Last Name) and `mail` (Email), matched by Email.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a recipe with **When** Run Now and a **For Each** step. Leave List to Work Through blank. | Save refuses: choose the list to work through. |
| 2 | Set List to Work Through to `trigger.people`. From **Add Step Inside**, add **Create or Update a Record** with the map and Input `loop.item`. | The inner step shows one level in, under "For each item"; the value path hints offer `loop.item` and `loop.index`. Add Step Inside offers no For Each, Wait or Load Rows. |
| 3 | Paste sample `{"people":[{"last":"Test1","mail":"t1@example.org"},{"last":"Test2","mail":"t2@example.org"}]}`. Select **Test**. | Succeeded; the For Each line reads "Worked through 1 items." and the inner step shows what it would write. No contact is created. |
| 4 | Publish, then Run Now with the same JSON. | Succeeded after up to 5 minutes; Records Written is 2 and both contacts exist. Run History shows one line for the For Each, not one per item. |
| 5 | Run Now with a list of 250 people (build it with a spreadsheet formula). | Succeeded with 250 contacts; the run may show Queued between passes; none is written twice. |
| 6 | Run Now with a list of 1,001 people. | Failed at the For Each: "The list holds 1001 items. For Each works through at most 1000 in a run." Nothing written. |

## T-CN-27: Wait

**Purpose:** confirm Wait makes a run Waiting without using a retry, and the recipe clock carries it on.
**Prerequisites:** admin; the recipe clock running (Recipe Clock shows a heartbeat).

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a recipe with **When** Run Now, a **Wait** step and a **Stop** step (Succeeded). Set Wait For to 2 and Unit to Minutes. | Save refuses: wait from 5 minutes to 30 days. Set 31 Days: refused the same way. |
| 2 | Set Wait For to 5, Unit Minutes. Select **Test**. | Succeeded at once; the Wait line reads "Would wait 5 minutes. A test does not wait." |
| 3 | Publish and Run Now. Open Run History. | The run is Waiting, tried next about 5 minutes on; Attempt shows no retry used. |
| 4 | Wait up to 10 minutes and refresh. | The run is Succeeded, the Stop step after the Wait ran. |
| 5 | Try to put a Wait inside a For Each by editing the steps. | Save refuses: a For Each cannot hold a For Each, Wait or Load Rows step. |

## T-CN-28: Change Data

**Purpose:** confirm Change Data builds data later steps read and writes nothing.
**Prerequisites:** admin; a saved JSON map (to JSON) with source `last` and target `fullName`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a recipe with **When** Run Now, a **Change Data** step named `reshape` with that map and Input `trigger`, then an **If** with condition `steps.reshape.fullName` equals `Lovelace`, Otherwise a Stop (Failed). | The If condition's hints offer `steps.reshape`. Choosing a record map for Change Data is refused at Publish. |
| 2 | Paste sample `{"last":"Lovelace"}` and select **Test**. | Succeeded; the Change Data step shows `fullName` Lovelace. |
| 3 | Publish and Run Now with `{"last":"Lovelace"}`. | Succeeded; Records Written is 0. |

## T-CN-29: Versions, Roll Back and Discard Draft Changes

**Purpose:** confirm Publish keeps the version before, and Roll Back and Discard Draft Changes work and ask first.
**Prerequisites:** admin; a recipe never published.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the recipe. | No Roll Back or Discard Draft Changes button. |
| 2 | Publish (version 1). Change a step, Save Draft, Publish (version 2). | Roll Back shows. |
| 3 | Change a step and Save Draft. Select **Roll Back**, then Cancel. | Nothing changes. Select it again and confirm: "Rolled back. The earlier version is published as version 3." The draft keeps your change. |
| 4 | Select **Roll Back** again and confirm. | Version 4 is the version 2 definition again. |
| 5 | Select **Discard Draft Changes** and confirm. | The editor shows the published steps; Unpublished changes is gone. |
| 6 | As a Viewer, open the recipe. | No Roll Back, Discard Draft Changes or Export Recipe. |

## T-CN-30: Export and Import a Recipe

**Purpose:** confirm Export Recipe carries no key or sample, and Import opens an unsaved draft matched by name with blanks highlighted.
**Prerequisites:** admin; a recipe with a Call an App step on connection "Test App", a body map, a header `X-Api-Key` with a typed value and sample data.

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **Export Recipe**. Open the downloaded file in a text editor. | The file holds the recipe, the map and connection by name; the `X-Api-Key` value is blank; no sample, Run As or owner. |
| 2 | Open the **Templates** tab, choose the file and select **Import**. | "Recipe: <name>" with Open as Draft, the step listed as having blanks, and "Nothing has been saved." No recipe is added to the list. |
| 3 | Select **Open as Draft**. | The editor opens a new draft: map and connection filled in; the step shows "The import left these blank ... headers". Save refuses until the header value is filled. |
| 4 | Fill it and Save Draft. | The recipe is saved as a Draft; Publish works as for any draft. |
| 5 | Rename the body map and import the file again. | The body map is blank and listed to fill. |

## T-CN-31: Import a Template and Refusals

**Purpose:** confirm a template fills a connection form with its host locked, never preloads or keeps anything, and files holding secrets or formulas are refused whole.
**Prerequisites:** admin; a template file such as the Mailchimp example in [Templates and Moving Recipes](../admin-guide/connector.md#templates-and-moving-recipes).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Templates tab before importing. | No template is listed; there is nothing preloaded. |
| 2 | Paste the template and select **Import**. | "Template: Mailchimp" with the connection (name, sign-in kind, address) and its recipes. |
| 3 | Select **Create Connection**. | The New Connection form opens filled in; the base URL cannot be edited and a Data center box shows. Type `evil.example.com` there and save: refused, fill in each part matching its pattern. |
| 4 | Clear the Data center box, paste a key ending in `-us21` and save. | The connection saves with base URL `https://us21.api.mailchimp.com/3.0`; the key is never shown. |
| 5 | Edit the template text to add `"apiKey":"abc"` and import. | Refused: the file holds what looks like a key ... (apiKey). Nothing imported. |
| 6 | Instead add `{!$Credential.X.Y}` in a description, or `"headerTemplate":"x"` under auth, or `"allowMergeFieldsInBody":true`, or set baseUrl to `http://...`, or a description `Bearer abcdef1234567890`. Import each. | Each is refused whole and the message never repeats the value. |
| 7 | Add `"requires":["No_Such_Object__c"]`. | Refused: install the module first. |
| 8 | Add `"pollers":[{"key":"unsubscribes"}]`, then instead a `"body"` on the action, then instead a query value `"{{list}}"` on the action. Import each. | Each is refused: **The template uses pollers** (then **body**, then **{{list}}**), **which BarnCRM cannot import yet**. Nothing imported. |
| 9 | Add a second recipe whose trigger is an App Poll with the query value `{{watermark}}` and import. | It opens as a draft whose trigger query value is `trigger.watermark`. |
| 10 | Make your endpoint answer GET `/ping` with `{"account_name":"Test Org"}`. On the connection made in step 4, after the Setup step, select **Check Connection**. | The endpoint got GET `/3.0/ping`; the page shows **Connected as Test Org**. |

## T-CN-32: An App Has New Items

**Purpose:** confirm an App Poll recipe notes the newest stamp on its first look, then starts runs only for items past its watermark, oldest first.
**Prerequisites:** admin; a Generic REST connection `Lists` to an HTTPS test endpoint you control that answers GET `/lists/L1/members` with `{"members":[...]}`, each member holding `id`, `email` and `last_changed` (for example `2026-11-20T09:00:00Z`).

| Step | Action | Expected result |
|---|---|---|
| 1 | Create recipe `Unsubscribes`. Under **When**, choose **An App Has New Items**: connection `Lists`, path `/lists/{listId}/members` with `listId` = `L1`, query `status` = `unsubscribed` and `since` = `trigger.watermark`, Item List `members`, Item Id `id`, Item Stamp `last_changed`, **One Run per Item**, Most Items per Look `2`. | The form shows each field with its help text. |
| 2 | Set Item Stamp blank and select Save Draft, then Publish. | Publish is refused: **Choose a connection, a list path starting with a slash, ...** Put `last_changed` back. |
| 3 | Add a step that keeps `trigger.item.email` (for example Find a Contact by email). Have the endpoint answer two members, stamps 09:00 and 10:00. Publish. | Publish succeeds. |
| 4 | Wait for the recipe clock (up to 15 minutes), then open Run History. | No item run. The endpoint received one GET `/lists/L1/members?status=unsubscribed` with no `since`. |
| 5 | Add three members stamped 11:00, 12:00 and 12:00 and wait for the next look. | Three item runs, started by **App Poll**, oldest first; the 12:00 pair is kept together although the limit is 2. The request carried `since=2026-11-20T10%3A00%3A00Z`. No App Poll run remains. |
| 6 | Wait for the next look with no new member. | Nothing new in Run History. |

**Cleanup:** Keep `Unsubscribes` and `Lists` for T-CN-33.

## T-CN-33: A Failing Look and Its Retry

**Purpose:** confirm a failed look stays in Run History without a key, is retried when it may pass, and moves no watermark.
**Prerequisites:** admin, after T-CN-32.

| Step | Action | Expected result |
|---|---|---|
| 1 | Make the endpoint answer 503 and wait for the next look. | One **Waiting** run started by **App Poll**, failed on the step `trigger`, showing when it is tried again. |
| 2 | Make the endpoint answer 401 with a short error body. Wait for the retry. | The run is **Failed** with a plain message; the step log shows the answer trimmed. One Error Log entry. Neither shows the connection key. |
| 3 | Make the endpoint answer `{"data":[]}` and select **Retry**. | Failed: **The answer from the app has no list of items at members. Check Item List under When.** |
| 4 | Change the `since` value to the path `trigger.item.id` and select Publish. | Publish is refused: each value is fixed or `trigger.watermark`. |
| 5 | Restore the endpoint and the value, publish, add a member stamped 13:00 and wait. | One item run for the 13:00 member only; nothing from before the failures runs twice. |

**Cleanup:** Delete `Unsubscribes` and `Lists`.

## T-CN-34: Erasing a Person Deletes Their Runs

**Purpose:** confirm erasing a person deletes every Connector run that names them, lists the runs by Id and keeps the rest.
**Prerequisites:** an admin who may erase people (BarnCRM Erase People) and holds no Connector permission set; a Connector admin; a webhook recipe from T-CN-23.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create Contact `Ana Lee`, email `ana.lee@example.org`. As the Connector admin, post three webhook items: one with `"email":"Ana.Lee@example.org"`, one with Ana's record Id, one with `"email":"joana.lee@example.org"`. | Three Succeeded runs. |
| 2 | Wait a few minutes. As the eraser, open Erase a Person for Ana and preview. | The preview lists **Connector Runs** under Deleted, with the first two runs. |
| 3 | Erase Ana. | The first two runs are gone from Run History; the `joana.lee` run and the recipe stay. The Erasure record lists the two run Ids and no email address. |

**Cleanup:** Delete the webhook recipe and its remaining run.

## T-CN-35: The Backup Destination

**Purpose:** confirm one connection becomes the backup destination, unsafe settings are refused, each Backup Set file is one request through the connection, and nothing secret is kept (BK-10, R-CN11).
**Prerequisites:** admin, after T-CN-02; an HTTPS test endpoint that echoes requests and can be set to answer 201 or 403; Core's Backup Sets with one set (T-BULK-17).

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a Bearer Token connection `Backup Bin` to the test endpoint and select **Check Connection**. | Created; the check answers. Under **Backup Destination**: **No connection is the backup destination.** |
| 2 | Select **Set Destination**. Choose `Backup Bin`, PUT, path `/backups`, and save. | Refused: `{file}` must appear in the path, a header or the metadata. |
| 3 | Change the path to `/backups/{file}` and add the header line `X-Api-Key: abc`. Save. | Refused: a header name may not look like a sign-in header. |
| 4 | Replace the header with `X-Folder: crm` and save. | The section shows `Backup Bin: PUT /backups/{file}` with no warning. |
| 5 | On **Backup Sets**, choose **Files and backup destination** under **Save To** for the set and select **Run Now**. | The run ends **Sent to backup destination**. The endpoint received one PUT per part to `/backups/<part title>.csv`, with `Content-Type: text/csv`, `X-Folder: crm`, the bearer header and the CSV as the body. |
| 6 | Set the endpoint to answer 403 and select **Run Now** again. | The run shows **Not all sent: the next scheduled run tries again**. The Error Log names status 403 and no key. |
| 7 | Log in as a user without BarnCRM Connections and open **Backup Sets**. | Edit Schedule says why the backup destination cannot be used now. |
| 8 | Back as the admin, select **Stop Using**. | **No connection is the backup destination.** Backup Sets shows the note in place of a send. |
| 9 | On the **Templates** tab, import `docs/connector-templates/webdav-backup-folder.json` from the repository and select **Create Connection**. | The Base URL is typed by you, not locked. After saving the key, the Backup Destination shows the new connection with PUT `/{file}`. |

**Cleanup:** Stop Using, then delete `Backup Bin` and the WebDAV connection.

## T-CN-36: Storage Services (S3 and OAuth)

**Purpose:** confirm Amazon S3 uploads are signed by Salesforce with AWS Signature Version 4, an OAuth connection made in Setup is listed, given access and used without BarnCRM writing its tokens, and each service's template builds the right request (BK-10b, R-CN12).
**Prerequisites:** admin, after T-CN-35; an S3 bucket without dots in its name and an IAM user allowed only `s3:PutObject` on it, with an access key; a Dropbox account with an app registered (or any one of Google Drive, OneDrive or Azure Blob Storage); the admin guide's [OAuth Connections Made in Setup](../admin-guide/connector.md#oauth-connections-made-in-setup) open.

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **New Connection**, kind **AWS Signature Version 4**, Base URL `https://files.example.org`. | Refused before anything is made: the address must be an AWS regional address. The user name box is labelled **Access Key ID** and the key box **Secret Access Key**. |
| 2 | On **Templates**, import `docs/connector-templates/amazon-s3-backup.json`, select **Create Connection**, type the bucket, region, access key ID and secret access key, and create it. | Created. In Setup, its External Credential uses **AWS Signature Version 4** with service `s3` and your region; the Named Credential has **Generate Authorization Header** on. The Backup Destination shows PUT `/barncrm/{file}`. |
| 3 | Do the Setup step, then **Run Now** a Backup Set saving to **Files and backup destination**. | The run ends **Sent to backup destination**; each part is in the bucket under `barncrm/`. |
| 4 | In Setup, create the Dropbox Auth Provider, External Credential `BarnConn_dropbox` (OAuth 2.0, Browser Flow, principal `OAuth`, Authenticate) and Named Credential `BarnConn_dropbox` as the admin guide says. Open Super Connector. | The connection is listed as **OAuth 2.0 (Made in Setup)**, with Check Connection, Disconnect and Delete but no **Replace Key**. |
| 5 | Select **Check Connection**. | Its principal is added to BarnCRM Connections (check again if asked). |
| 6 | On **Templates**, import `docs/connector-templates/dropbox-backup.json` and select **Create Connection**. | No connection form opens. The Backup Destination form opens filled in (POST `/2/files/upload`, the `Dropbox-API-Arg` and `Content-Type` headers) with a note, and offers only OAuth connections. |
| 7 | Choose `BarnConn_dropbox`, save, and **Run Now** the Backup Set. | Each part arrives in Dropbox's `BarnCRM-Backups` folder under its own title. |
| 8 | Select **Change Destination** and set the path to `/2/files/upload?sig=abc`. Save. | Refused: a path may end only with the fixed `uploadType` query. |
| 9 | Optional, for Google Drive: import `google-drive-backup.json`, replace `FOLDER_ID` in **Upload Metadata** with a folder's ID, save and run. | Each part arrives in that Drive folder, named for the part. |

**Cleanup:** Stop Using; delete the S3 connection; delete the Dropbox connection (which removes its Named and External Credential) and the Auth Provider in Setup; delete the IAM access key.
