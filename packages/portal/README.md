# BarnCRM Portal Builder

## Purpose

Logged-in portals people use off-platform, with no Salesforce license per person (PB-01, D-118,
D-187, ADR-0185 `0185-portal-builder-off-platform-portal-api.md`). The portal client (in
`portal-client/` at the repository root, not deployed to Salesforce) signs in as one integration
user and calls this package's person-scoped API. Salesforce sends and checks the one-time code,
checks the optional authenticator code and issues sessions; every call returns or changes only
what the verified person's template allows.

## First ships in

Release **1.3** (PB-01), with the volunteer (PB-03), speaker (PB-07) and donor (PB-08) templates in
`portal-client/templates/`. Their module actions (`Volunteers.SignUp`, `Events.ApplyToSpeak` and
the like) are classes in Volunteers and Event Management that Core's `PortalActionExtensions`
finds by name; this package depends on neither.

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
- App `BarnCRM_Portal_Builder` (BarnCRM Portal Builder, logo `BarnCRM_Patch_Portal_Logo`), visible
  through `Portal_Admin`; left out of scratch and Developer Edition orgs (ADR-0223, module apps).
  The Portals and Portal Accesses tabs also join BarnCRM Admin and BarnCRM Admin Console, before
  Error Log, through the catalog row's `Admin_Tabs__c` and `scripts/org/module-app-tabs.py`.
- Settings in the Portals section of BarnCRM Settings.
