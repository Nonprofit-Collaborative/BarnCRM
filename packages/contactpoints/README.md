# BarnCRM Contact Point Sync

## Purpose

Copies each person's email addresses, phone numbers and addresses from BarnCRM to Salesforce
Contact Points (`ContactPointEmail`, `ContactPointPhone`, `ContactPointAddress`) and keeps the
copies up to date, for apps that read Contact Points (C-45, D-111, ADR-0176
`0176-contact-point-sync-module.md`). BarnCRM itself never reads Contact Points. Setup and use:
[Admin Guide, Contact Point Sync](../../docs/admin-guide/contact-point-sync.md).

## First ships in

Release **1.1** (C-45), with person accounts copied too (D-186).

## Depends on

- BarnCRM Core

The org needs the three Contact Point objects and the Individual object. Person accounts are read
through dynamic Apex, so there is no Person Account dependency.

## Contents

- Objects: `Contact_Point_Link__c` (which copy belongs to which BarnCRM value) and settings
  `Contact_Point_Sync_Settings__c`.
- Handlers registered in Core's automation registry: people, person accounts, addresses and
  household moves (`ContactPointPersonHandler`, `ContactPointAccountHandler`,
  `ContactPointAddressHandler`, `ContactPointMembershipHandler`), planned by
  `ContactPointPlan` and written by `ContactPointSyncService`.
- `ContactPointBackfillBatch` for people saved before the module was installed.
- The Contact Point Sync page (`contactPointSync`, controller `ContactPointSyncController`) and its
  tab.
- Permission set `Contact_Point_Sync_Admin` (given to BarnCRM Admin holders by
  `ContactPointsAccessSync`).
- Settings in the Contact Points section of BarnCRM Settings.
