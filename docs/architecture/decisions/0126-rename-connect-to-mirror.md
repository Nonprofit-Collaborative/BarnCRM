# ADR-0126: Rename BarnCRM Connect to BarnCRM Mirror

**Status:** Accepted (owner decision, Brandon, 2026-10-15)
**Date:** 2026-10-15
**Source:** owner decision 2026-10-15; renames the module set up by ADR-0003 and described in
ADR-0004, ADR-0051, ADR-0056, ADR-0057 and ADR-0058, without changing any of those decisions

## Context

The module that mirrors gifts to Opportunities, copies appeals to Campaigns, accepts gifts
through the inbound gift API and exports gifts for accounting was named BarnCRM Connect. The
name reads like an integration product (a connector to other systems). Its main feature is the
Opportunity mirror, Campaign sync copies appeals, and the inbound gift API and accounting export
sit beside them. "Mirror" says what the module does for the organizations that install it.

No subscriber installs exist yet and no package version has been created (the namespace is still
deferred), so the API names can change now at no cost to anyone outside the project. After the
first release they would be permanent.

## Decision

Rename the module everywhere, API names included:

- Display name: BarnCRM Connect becomes BarnCRM Mirror (package name in `sfdx-project.json`,
  labels, docs).
- Package folder: `packages/connect` becomes `packages/mirror`, and every script, CI check and
  config that names the folder follows.
- Module catalog: the `BarnCRM_Module__mdt` record `Connect` becomes `Mirror`, with package folder
  `mirror`. Core's module manager, Health Check and Setup Assistant refer to the module by the new
  key.
- API names: `Connect_Settings__c` becomes `Mirror_Settings__c`; Apex classes `Connect*` become
  `Mirror*` (for example `ConnectSync` becomes `MirrorSync`); custom labels `Connect_*` become
  `Mirror_*` and their label files follow; `Setting_Definition` records `Connect_*` become
  `Mirror_*`; Core's labels `Core_HealthCheck_ConnectMissing*` become
  `Core_HealthCheck_MirrorMissing*`; the module value `Connect` in `Module__c` fields becomes
  `Mirror`.
- Components whose names never carried the module name (permission sets, custom permissions,
  tabs, flexipages, LWCs, the `Appeal__c` and `Gift__c` fields) keep their API names.
- Behavior does not change.

Existing ADRs and iteration release notes are history and keep the old name.

## Consequences

- Test orgs that hold the old module keep its old `Connect*` components after the renamed module
  deploys. They are removed with a destructive deploy that lists only the renamed components
  (the old classes, labels, `Connect_Settings__c` with its fields, and the old custom metadata
  records); components whose names did not change must not be listed, since the new module
  deploys over them in place. Deleting `Connect_Settings__c` drops its org default values (the
  Campaign sync switch, the Opportunity mirror direction, start date, record types and last
  run); an administrator sets them again on the settings console, where they are stored in
  `Mirror_Settings__c`.
- No subscriber upgrade path is needed, since nothing has been installed outside the project.
- The namespace is still deferred (ADR-0001, `sfdx-project.json` namespace empty); the rename does
  not touch it.
- "Opportunity mirror" (the feature) and "Mirror" (the module) now share a word; docs say
  "BarnCRM Mirror" where the two could be confused.
