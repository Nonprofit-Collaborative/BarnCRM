# BarnCRM Connector

## Purpose

Connects BarnCRM to other apps without Flow Builder, Apex or a paid integration service (plan
6.1, D-210, D-216, ADR-NEXT integration module, `docs/architecture/integration-hub-design.md`).
CN-01 ships **Connections**: a saved, checked sign-in to another app's REST API, its key held in
an External Credential and a Named Credential and never returned (canonical model 29CN1). Setup
and use: [Admin Guide, BarnCRM Connector](../../docs/admin-guide/connector.md).

## First ships in

Release **1.31** (CN-01). Beta, offered in both editions, not installed by default.

## Depends on

- BarnCRM Core

## Contents

- `ConnectorConnections`: the rules (R-CN1 to R-CN8): names `BarnConn_rest_*`, the four auth
  kinds (API key header, Bearer, Basic, Secret URL), URL and header checks, the F2 refusal of any
  credential BarnCRM did not create, the BarnCRM Connections access set, the Admin Journal entry
  on a key replaced, redacted error logs.
- `ConnectorOrg`: the seam over `ConnectApi.NamedCredentials` and the setup objects, faked in tests.
- `ConnectorConnectionsController` and `c/superConnector`, `c/connectorKeyForm`: the Super
  Connector tab. `c/connectorRules` (framework-free) and `c/connectorText` hold the browser rules
  and texts.
- `ConnectorHealthCheckExtension` (registered in Core's `HealthCheckExtensions`) and
  `ConnectorPostInstall`.
- App `BarnCRM_Connector` (console; left out on capped orgs, ADR-0223), tab `Super_Connector`,
  custom permission `Manage_BarnCRM_Connector`, permission set `BarnCRM_Connector_Admin`, help
  texts `BarnHelp_Connector`.
- No custom object yet: the run objects come with CN-02.
