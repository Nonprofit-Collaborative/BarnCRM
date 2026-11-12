# BarnCRM Address Verification

## Purpose

Checks `Address__c` records with the organization's own Smarty or Google account and writes
Verification Status and Latest Verified Date, plus the standardized street, city, state and
postal code when Apply Corrections is on (C-46, D-112, ADR-NEXT
`NEXT-address-verification-module.md`). No provider is bundled and BarnCRM holds no key. Setup and
use: [Admin Guide, Address Verification](../../docs/admin-guide/address-verification.md).

## First ships in

Release **1.15** (C-46).

## Depends on

- BarnCRM Core

## Contents

- Settings `Address_Verification_Settings__c` (29AV1) in BarnCRM Settings, Addresses; keys
  `Address_Verification_Keys__c` (29AV2, granted to no one).
- `AddressVerifier`: the Smarty and Google lookups and the writes (R-AV1 to R-AV3).
- `AddressVerificationHandler`: registry row `Address_Verification` on `Address__c`.
- `AddressVerificationJob`: the on-save queued job, the nightly batch and Verify Waiting Addresses.
- `AddressVerificationController` and `c/addressVerificationSetup`: the Address Verification Setup
  tab.
- Health Check extension, nightly step provider, access sync and post-install.
- Remote Site Settings `Barn_Smarty_Api` and `Barn_Google_Address_Api`.
- Permission set `Address_Verification_Admin`.
