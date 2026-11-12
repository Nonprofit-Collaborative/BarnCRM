# Address Verification

Scripts for the optional BarnCRM Address Verification module: settings and keys, Health Check, checks on save, corrections, the nightly check and its limit, and switching it off. Setup detail: [Address Verification](../admin-guide/address-verification.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Address Verification deployed, the Addresses feature on, and a Smarty account (the free plan is enough) with a secret key pair. T-AV-04 also needs a Google Cloud API key with the Address Validation API enabled; skip it without one.

## T-AV-01: Settings, Keys and Health Check

**Purpose:** confirm the settings show their defaults, keys are write-only and Health Check lists missing keys.
**Prerequisites:** admin (BarnCRM Admin, which gives Address Verification Admin).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Addresses**. | **Address verification provider** Smarty, **Verify addresses when saved** on, **Apply corrections** off, **Re-check verified addresses (months)** 12, **Most addresses checked a night** 200, and an **Address Verification Setup** link. |
| 2 | Open **Health Check**. | `Address Verification Keys Are Missing`. |
| 3 | Open **Address Verification Setup**. Every key reads **Not set**; **Verify Waiting Addresses** is greyed out. | As described. |
| 4 | Enter your Smarty Auth ID and Auth Token and select **Save Keys**. | **Saved.** Both read **Set, ending** and their last four characters; the boxes are empty. |
| 5 | Reload the page and look at the network response. | No key appears, only the last four characters. Health Check no longer lists missing keys. |

**Cleanup:** None (the keys are used below).

## T-AV-02: A Saved Address Is Checked

**Purpose:** confirm a new or changed address is checked moments after saving.
**Prerequisites:** admin, after T-AV-01.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | On a household, add the address `1600 Amphitheatre Pkwy`, `Mountain View`, `CA`, `94043`. Wait a minute and open the address. | **Verification Status** Verified, **Latest Verified Date** today. The street is as you typed it. |
| 2 | Edit the address: change the street to `99999 Nowhere Rd`. Save, and open it again at once. | **Verification Status** Unverified. |
| 3 | Wait a minute and refresh. | **Verification Status** Failed; **Latest Verified Date** still today (the last success). |
| 4 | Change the address **Type** only. | Verification Status does not change. |

**Cleanup:** Delete the test address.

## T-AV-03: Corrections

**Purpose:** confirm corrections are taken only when switched on, and never the country.
**Prerequisites:** admin, after T-AV-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Addresses** settings turn **Apply corrections** on. | Saved. |
| 2 | Add the address `1600 amphitheatre parkway`, `mountain view`, `ca`, `94043`, country `United States`. Wait a minute and open it. | Verified, and the street, city, state and postal code are in the service's form (for example `1600 Amphitheatre Pkwy`, `Mountain View`, `CA`, `94043-1351`). The country is still `United States`. |
| 3 | Turn **Apply corrections** off. | Saved. |

**Cleanup:** Delete the test address.

## T-AV-04: Google and Other Countries

**Purpose:** confirm Smarty skips addresses outside the United States and Google checks them.
**Prerequisites:** admin, a Google key.

| Step | Action | Expected result |
|---|---|---|
| 1 | With Smarty chosen, add the address `290 Bremner Blvd`, `Toronto`, `ON`, `M5V 3L9`, country `Canada`. Wait a minute. | Still Unverified: Smarty checks United States addresses only. |
| 2 | Enter your Google key on Address Verification Setup, choose **Google** as the provider, then edit the street to `290 Bremner Boulevard`. Wait a minute. | Verified, today. |

**Cleanup:** Set the provider back to Smarty and delete the test address.

## T-AV-05: The Nightly Check and Its Limit

**Purpose:** confirm Verify Waiting Addresses and the nightly limit bound the lookups.
**Prerequisites:** admin, after T-AV-01; at least 5 current United States addresses that are Unverified (import them, which leaves them for the nightly check).

| Step | Action | Expected result |
|---|---|---|
| 1 | Set **Most addresses checked a night** to 3. | Saved. |
| 2 | On **Address Verification Setup** select **Verify Waiting Addresses**. | "Started." |
| 3 | After a minute, run a Find query on Addresses where Verification Status is Unverified. | 3 fewer than before. |
| 4 | Open **Nightly Jobs** in Settings. | An **Address Verification** step at 3:30 AM, switched on. |

**Cleanup:** Set the limit back to 200.

## T-AV-06: Switching It Off

**Purpose:** confirm the automation switch and Pause All stop the on-save check.
**Prerequisites:** admin, after T-AV-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Automation**, switch **Address Verification** off. Change the street of a verified address. | It keeps its old Verification Status; nothing is looked up. |
| 2 | Switch it back on and change the street again. | Unverified, then checked within a minute. |
| 3 | Sign in as a staff user (Team Member) and open BarnCRM Settings. | No Address Verification Setup tab; their own address edits are still checked. |

**Cleanup:** None.
