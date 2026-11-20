# BarnCRM Connector

## What It Does

The optional **BarnCRM Connector** module (Beta) connects BarnCRM to the other apps your
organization uses, without Flow Builder, Apex or a paid integration service. This page covers
**Connections**: a saved, checked sign-in to another app's REST API. Each connection keeps its
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
- **Delete** removes the connection and its key from Salesforce.

## Access

| Permission set | Gives |
|---|---|
| BarnCRM Connector Admin | The BarnCRM Connector app, the Super Connector tab and Manage BarnCRM Connector. Give it only to system administrators: whoever holds it decides where your data goes. |
| BarnCRM Connections | Created by BarnCRM in your org, not part of the package. It holds each connection's principal access and is given only to Connector admins when they create or check a connection. Do not add other permissions to it: Health Check warns when it holds anything else. |

## Health Check

With the module installed, Health Check reports:

- connections whose callouts are still off in Setup;
- connections missing from the BarnCRM Connections permission set;
- keys replaced in the last 7 days, by connection;
- the BarnCRM Connections permission set holding anything other than connection access.

## Removing It

Delete each connection on **Super Connector** first, so no credential is left in Setup, then
uninstall the module from the [Module Manager](module-manager.md). Delete the **BarnCRM
Connections** permission set in Setup afterwards if you no longer need it.
