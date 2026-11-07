# BarnCRM Portal Builder

## Purpose

Logged-in portals people use off-platform, with no Salesforce license per person (PB-01, D-118,
D-187, ADR-NEXT `NEXT-portal-builder-off-platform-portal-api.md`). The portal client (in
`portal-client/` at the repository root, not deployed to Salesforce) signs in as one integration
user and calls this package's person-scoped API. Salesforce sends and checks the one-time code,
checks the optional authenticator code and issues sessions; every call returns or changes only
what the verified person's template allows.

## First ships in

Release **1.3** (PB-01). The volunteer (PB-03), speaker (PB-07) and donor (PB-08) templates follow.

## Depends on

- BarnCRM Core

Nothing in this package references another module. A template names only objects and fields, and
a module offers actions (such as signing up for a shift) through Core's `PortalActionExtension`
seam.

## Contents

- Objects: `Portal__c`, `Portal_Access__c`, `Portal_Session__c`, settings `Portal_Settings__c`
  (canonical model 29PB1 to 29PB4).
- Apex REST API `PortalApi` (`/services/apexrest/barncrm/portal/v1/*`), with `PortalAuth`
  (sign-in, sessions), `PortalData` (pages), `PortalTemplate` (template checks) and
  `PortalTokens` (hashes, codes, authenticator codes).
- Permission sets `Portal_Admin` (given to BarnCRM Admin holders by `PortalAccessSync`) and
  `Portal_Integration` (assigned by hand to the integration user only).
- Console app `BarnCRM_Portal_Builder` with the Portals and Portal Accesses tabs, Error Log last.
- Settings in the Portals section of BarnCRM Settings.
