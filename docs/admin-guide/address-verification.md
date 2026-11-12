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
3. Select **Address Verification Setup**. Type the keys for your provider and select **Save
   Keys**. Each key then reads **Set, ending** and its last four characters. Keys are never shown
   again; to change one, type the new key and save. **Clear** removes one provider's keys.
4. Select **Verify Waiting Addresses** to check the addresses you already have, up to the nightly
   limit, in the background.

Saving keys and starting a check need the **Manage BarnCRM Settings** permission.

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
  first, up to the nightly limit. The step runs only while the module is on and your provider's
  keys are entered.
- **Now**: **Verify Waiting Addresses** on Address Verification Setup starts the same check.

Only **Current** addresses are checked; Former and Undeliverable ones never are. With Smarty, an
address whose country is not blank, US, USA or United States is left Unverified.

## What Is Written

| The service says | Verification Status | Latest Verified Date | Street, city, state, postal code |
|---|---|---|---|
| A deliverable address | Verified | Today | Standardized only with Apply Corrections on |
| Not found, or only part of it confirmed | Failed | Unchanged (the last success) | Unchanged |
| An error (wrong key, allowance used up, no answer) | Unchanged (Unverified) | Unchanged | Unchanged |

A provider error is logged once per run in the [Error Log](error-log.md) and the addresses are tried
again the next night. The module writes as the person who saved the address, or as whoever
scheduled the nightly run.

## Switching It Off

- **Automation**: the **Address Verification** switch on the [Automation](automation-control.md)
  page stops the on-save check and leaves Verification Status alone; Pause All covers it too.
- **Nightly**: the **Address Verification** switch on the Nightly Jobs panel stops the nightly
  check.
- **Module**: Turn off in the Module Manager stops both.

## Health Check

While the module is on, [Health Check](health-check.md) reports:

- **Address Verification Keys Are Missing** (warning): the chosen provider has no keys, so
  nothing is checked.
- **Addresses Are Waiting To Be Verified** (information): current addresses Unverified for more
  than 30 days, with the count. Raise the nightly limit, select Verify Waiting Addresses, or, with
  Smarty, check whether they are outside the United States.

## Access

| Permission set | Who gets it | What it allows |
|---|---|---|
| Address Verification Admin | BarnCRM Admin holders, and the installer | The Address Verification Setup tab |

Staff need nothing extra: anyone who can edit an address has it checked when they save. The keys
are granted to no one; until BarnCRM has its namespace, an administrator with View All Custom
Settings can read them in Setup.
