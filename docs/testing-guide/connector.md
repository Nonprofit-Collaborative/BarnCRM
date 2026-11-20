# BarnCRM Connector

Scripts for the optional BarnCRM Connector module, release 1.31 (CN-01): creating Connections of each sign-in kind, the one Setup step with Check Again, checking, replacing, disconnecting and deleting, the refusals that keep keys safe, access and Health Check. Setup detail: [BarnCRM Connector](../admin-guide/connector.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and BarnCRM Connector deployed, and an HTTPS test endpoint that echoes requests (for example a free request bin you control). Use made-up keys such as `test-key-1234`; never a real one.

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
| 3 | Select **Replace Key** on the Secret URL connection and enter an address on another host. Then do it again with an address on the same host and another path. | The other host is refused: the host must stay the same. The same host is saved (`Key replaced`), the row still shows only the host and the new last four characters, and the Named Credential URL in Setup is the new address. |

**Cleanup:** None.

## T-CN-05: Replace, Disconnect and Delete

**Purpose:** confirm key changes are journaled and shown in Health Check, and removal leaves nothing behind (R-CN6, F12).
**Prerequisites:** admin, after T-CN-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Echo Test** select **Replace Key**, enter `test-key-5678` and save. | `Key replaced`; Check Connection sends the new key. The Admin Journal has a **Connection** row, **Key Replaced**, with your name and the connection, without the key. |
| 2 | Open **Health Check**. | `Connection Keys Replaced This Week` names Echo Test. |
| 3 | Select **Disconnect**, **Cancel**, then **Disconnect** and confirm. | Cancel changes nothing; confirming shows **Disconnected**. |
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
