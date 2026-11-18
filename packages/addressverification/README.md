# BarnCRM Address Verification

## Purpose

Checks `Address__c` records with the organization's own Smarty or Google account and writes
Verification Status and Latest Verified Date, plus the standardized street, city, state and
postal code when Apply Corrections is on (C-46, D-112, ADR-0209
`0209-address-verification-module.md`). No provider is bundled and BarnCRM holds no key. Setup and
use: [Admin Guide, Address Verification](../../docs/admin-guide/address-verification.md).

## First ships in

Release **1.15** (C-46).

## Depends on

- BarnCRM Core

## Contents

- Settings `Address_Verification_Settings__c` (29AV1) in BarnCRM Settings, Addresses, with the
  connected provider (no secret).
- `AddressVerifier`: the Smarty and Google lookups and the writes (R-AV1 to R-AV3).
- `AddressVerificationHandler`: registry row `Address_Verification` on `Address__c`.
- `AddressVerificationJob`: the on-save queued job, the nightly batch and Verify Waiting Addresses.
- `AddressVerificationController` and `c/addressVerificationSetup`: the Address Verification Setup
  tab.
- Health Check extension, nightly step provider, access sync and post-install.
- External Credentials `Barn_Smarty` (principal `Barn_Smarty_Key`, parameters `AuthId`,
  `AuthToken`) and `Barn_Google_Address` (principal `Barn_Google_Address_Key`, parameter
  `ApiKey`), shipped with no value, and Named Credentials of the same names. Apex merges the keys
  into headers and never reads them (ADR-NEXT `NEXT-provider-secrets-named-credentials.md`).
- Permission sets `Address_Verification_Admin` (the setup tab and credential access) and
  `Address_Verification_User` (credential access only, for lookups on save; assigned in Setup).
