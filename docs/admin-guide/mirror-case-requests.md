# Cases Sent to a Service Provider

## What It Does

Some organizations get help from a service provider: an IT partner, a shared back office, a
consultant. When the provider runs BarnCRM Project Management with
[Requests and Issues](projects-requests.md), your org can send Salesforce Cases straight into
their request queue and see their progress without anyone retyping or emailing.

BarnCRM Mirror sends each Case to the provider's request API and keeps what comes back on a
**Provider Request**: the provider's request number, its status, the resolution once they
resolve it, when it was last synced, and the last error if a send failed. Nothing is written to
the Case itself, so Mirror adds no fields to Case.

It is off until you turn it on, and it needs the provider to set your org up first.

## Before You Start

The provider, in their org (see [Requests From Another Organization](projects-requests.md#requests-from-another-organization)):

1. Turns on **Take requests from outside**.
2. Creates an integration user for you with **Projects Request Intake**, and an External Client
   App with the OAuth client credentials flow run as that user.
3. Adds a **Request Connection** with your organization id (Setup, Company Information,
   Salesforce.com Organization ID) and that user.
4. Gives you the app's consumer key and secret by a secure route, and their My Domain address.

## Set It Up

1. In Setup, **Named Credentials**, **External Credentials**: create one with Authentication
   Protocol OAuth 2.0, Authentication Flow Type Client Credentials with Client Secret Flow, and
   the provider's token address (`https://<their My Domain>/services/oauth2/token`). Add a
   principal with the consumer key and secret.
2. Create a **Named Credential** named exactly `Barn_Request_Provider`, URL the provider's My
   Domain address (`https://<their My Domain>`), using that External Credential.
3. Give the External Credential's principal to the users who send Cases (a permission set with
   External Credential Principal Access), including the administrator who scheduled BarnCRM
   Nightly Jobs.
4. In Setup, **Case**, **Type**: add a value **Service Provider** (or choose another in step 5).
5. In **BarnCRM Settings**: turn on **Send Cases to a service provider**, and set **Case type to
   send** if you chose another Type.
6. Make sure [BarnCRM Nightly Jobs](nightly-jobs.md) is scheduled.

The secret stays in Salesforce's credential store. BarnCRM keeps no secret in its settings.

## How Cases Go

- **Every night** at 1:40 AM, every open Case of the chosen Type that the provider has not yet
  accepted is sent, oldest first.
- **At once**, if you want it: build a record-triggered flow on Case (after save, for example
  when Type equals Service Provider) that calls the action **Send Cases to a Service Provider**
  with the Case's Id. It sends in the background.

Each Case is sent with its Case Number as the reference, its subject, description and
priority, and the contact's name and email (or the web name and email). Sending the same Case
twice never makes a second request at the provider, and a Case the provider accepted is not sent
again.

## Following Progress

Open the **Provider Requests** tab: one row per Case sent, named by Case Number, with the
provider's **Request Number**, **Provider Status**, **Provider Resolution** and **Last Synced**.
Each night BarnCRM asks the provider for the status of every request not yet Resolved, Closed or
Cancelled. Reports can use the Provider Requests object.

## Common Mistakes

- **Last Error says the provider refused the Case (403).** The provider's Request Connection is
  inactive, names another user, or has another organization id; or Take requests from outside is
  off at the provider.
- **Last Error says the provider could not be reached.** The Named Credential is missing, not
  named `Barn_Request_Provider`, or the running user has no access to its principal. The Error
  Log has the details.
- **429 in the Error Log.** More new Cases in an hour than the provider's Hourly Limit. The next
  run sends the rest.
- **Nothing is sent.** Check the setting, the Case Type value, and that Nightly Jobs is
  scheduled.
