# Address Verification

## What It Does

The optional **BarnCRM Address Verification** module checks your addresses with an address
service your organization already has an account with, and marks each one **Verified** or
**Failed** in its **Verification Status**, with the **Latest Verified Date** of the last success.
A report or a Find query on those two fields shows which mailing addresses to fix before a
mailing. With **Apply Corrections** on, a verified address also takes the service's standard
spelling, such as "123 Main St" for "123 main street".

No provider comes with BarnCRM and BarnCRM sells no lookups. You bring your own account and key,
and every lookup counts against that account's allowance.

## Before You Install

- Offered in both editions (see [Editions](editions.md)). It needs BarnCRM Core only.
- An account with one of the two supported services:
  - **Smarty** (smarty.com): United States addresses only. Create a **secret key** pair in your
    Smarty account; you need its **Auth ID** and **Auth Token**. Smarty has a small free monthly
    allowance.
  - **Google Address Validation** (Google Cloud): most countries. Create an API key in a Google
    Cloud project with the **Address Validation API** enabled, and restrict the key to that API.
    Google charges per lookup beyond its monthly credit.
- Another verification app may already write Verification Status and Latest Verified Date. Use
  one or the other: switch this module's automation off (below) if you keep the other app.

## Setting It Up

1. Install the module from **BarnCRM Settings**, **Modules** (see [Module Manager](module-manager.md)).
   Holders of BarnCRM Admin get **Address Verification Admin**.
2. Open **BarnCRM Settings**, **Addresses**, and choose the **Address verification provider**
   (default Smarty).
3. Enter your provider's key in Salesforce **Setup** (see
   [Entering the Key in Setup](#entering-the-key-in-setup)).
4. Select **Address Verification Setup** and, on your provider's card, **Check Connection**. It
   looks up one sample address through the provider (this counts as one lookup) and, when the
   provider answers, reads **Connected**. Nothing is checked until it does.
5. Give **Address Verification User** to everyone whose saves should be checked at once (see
   [Access](#access)).
6. Select **Verify Waiting Addresses** to check the addresses you already have, up to the nightly
   limit, in the background.

Checking a connection, **Disconnect** and starting a check need the **Manage BarnCRM Settings**
permission. **Disconnect** asks you to confirm, then marks one provider not connected, so nothing is looked up with it;
its key stays on the External Credential until you remove it in Setup. It shows only on the connected provider.

### Entering the Key in Setup

The key is kept by Salesforce on an External Credential the module ships empty, never by
BarnCRM: its code cannot read, show or store it. Each provider's card on Address Verification
Setup names the credential, principal and parameters, with the steps:

1. **Setup > Named Credentials**, then the **External Credentials** tab.
2. Open **BarnCRM Smarty** or **BarnCRM Google Address Validation**.
3. Under **Principals**, edit `Barn_Smarty_Key` or `Barn_Google_Address_Key`.
4. Add each **Authentication Parameter**, named exactly as the card says, and save:
   - Smarty: `AuthId` (the Auth ID) and `AuthToken` (the Auth Token). They are sent in an
     Authorization header, never in the address of the call.
   - Google: `ApiKey` (the API key), sent in the `X-Goog-Api-Key` header.
5. Back on Address Verification Setup, select **Check Connection**.

To change a key later, edit the parameter's value the same way and check the connection again.
With a namespaced package install, the names on the card carry the package prefix; use them as
shown.

## Settings

All in **BarnCRM Settings**, **Addresses**, saved for the whole organization:

| Setting | Default | What it does |
|---|---|---|
| Address verification provider | Smarty | Smarty (United States addresses) or Google (most countries). |
| Verify addresses when saved | On | Checks a current address within moments of it being added, or its street, city, state, postal code or country changing. |
| Apply corrections | Off | A verified address also takes the provider's street, city, state and postal code. The country is never changed. |
| Re-check verified addresses (months) | 12 | The nightly check looks up a verified address again after this many months. 0 never re-checks. |
| Most addresses checked a night | 200 | The most addresses the nightly check looks up in one night, oldest first. 0 stops the nightly check. Set it to what your provider plan covers. |

## When Addresses Are Checked

- **When saved.** A change to the street, city, state, postal code or country sets the address
  back to **Unverified** at once, then it is looked up moments later. Up to 50 addresses of one
  save are looked up this way; the rest, and addresses saved by an import or another background
  job, wait for the nightly check.
- **Every night**, in the [nightly run](nightly-jobs.md) as **Address Verification** at 3:30 AM:
  current addresses that are Unverified, and verified ones older than the re-check months, oldest
  first, up to the nightly limit. The step runs only while the module is on and your provider is
  connected.
- **Now**: **Verify Waiting Addresses** on Address Verification Setup starts the same check.

Only **Current** addresses are checked; Former and Undeliverable ones never are. With Smarty, an
address whose country is not blank, US, USA or United States is left Unverified.

## What Is Written

| The service says | Verification Status | Latest Verified Date | Street, city, state, postal code |
|---|---|---|---|
| A deliverable address | Verified | Today | Standardized only with Apply Corrections on |
| Not found, or only part of it confirmed | Failed | Unchanged (the last success) | Unchanged |
| An error (wrong key, allowance used up, no answer, no access to the credential) | Unchanged (Unverified) | Unchanged | Unchanged |

A provider error is logged once per run in the [Error Log](error-log.md) and the addresses are tried
again the next night. A call that cannot use the credential at all (no key in Setup, or a person
without access to it) stops that run at once, so nothing else is tried. The module looks up and
writes as the person who saved the address, or as whoever scheduled the nightly run.

## Switching It Off

- **Automation**: the **Address Verification: check on save** switch on the [Automation](automation-control.md)
  page stops the on-save check and leaves Verification Status alone; Pause All covers it too.
- **Nightly**: the **Address Verification** switch on the Nightly Jobs panel stops the nightly
  check.
- **Module**: Turn off in the Module Manager stops both.

## Health Check

While the module is on, [Health Check](health-check.md) reports:

- **Address Provider Is Not Connected** (warning): **Check Connection** has not succeeded for
  the chosen provider, so nothing is checked. Health Check makes no test lookup itself, since
  each one counts against your account.
- **Addresses Are Waiting To Be Verified** (information): current addresses Unverified for more
  than 30 days, with the count. Raise the nightly limit, select Verify Waiting Addresses, or, with
  Smarty, check whether they are outside the United States.

## Access

| Permission set | Who gets it | What it allows |
|---|---|---|
| Address Verification Admin | BarnCRM Admin holders, and the installer | The Address Verification Setup tab, and access to both provider credentials (never their values) |
| Address Verification User | Whoever you choose, on the **Access** page (never given automatically) | Access to both provider credentials (never their values), and nothing else |

A lookup on save runs as the person saving, and Salesforce lets it use the credential only when
that person has access to it. In BarnCRM, open the **Access** page, choose **Address Verification
User** among the extra permissions and add it to the staff whose saves should be checked at once
(see [Access](access.md)). Without it, no lookup is queued when they save: their new and
changed addresses stay Unverified until the nightly check, which runs as the admin who scheduled
it, and the Error Log gets one Warning a day saying so, not one per save. Nobody can read a key:
Salesforce keeps it encrypted on the External Credential.
