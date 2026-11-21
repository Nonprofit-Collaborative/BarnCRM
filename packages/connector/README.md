# BarnCRM Connector

## Purpose

Connects BarnCRM to other apps without Flow Builder, Apex or a paid integration service (plan
6.1, D-210, D-216, ADR-0235, `docs/architecture/integration-hub-design.md`).
CN-01 ships **Connections**: a saved, checked sign-in to another app's REST API, its key held in
an External Credential and a Named Credential and never returned (canonical model 29CN1). CN-02
ships **Recipes** and **Runs** (29CN2, 29CN3): a When and Then steps that find, write through a
saved map and call apps, run as BarnCRM Automation or System. CN-06 ships two Flow actions.
CN-03 ships the **recipe clock**: Schedule and Record Change triggers, retries, pausing, the
Integration User Run As and the nightly cleanup (R-CR6 to R-CR8, 29CN4 Connector Settings).
CN-05 ships the For Each, Wait and Change Data steps (R-CR12); CN-08 ships versions, Roll Back,
Export Recipe and the Templates tab, importing templates and recipe files that are never
preloaded or kept (R-CR13 to R-CR15, D-216). CN-04 ships webhooks in and Send to Webhook
(R-CR10, R-CR11); CN-13 the App Poll trigger (R-CR16); CN-18 runs in a person's erasure (R-CR17).
Setup and use: [Admin Guide, BarnCRM Connector](../../docs/admin-guide/connector.md).

## First ships in

Release **1.31** (CN-01, CN-02, CN-06); release **1.32** adds CN-03, CN-04, CN-05, CN-08 and CN-09; release **1.33** adds CN-13 and CN-18. Beta, offered in both
editions, not installed by default.

## Depends on

- BarnCRM Core (Saved Find queries and Mapper maps, `Saved_Transform__c`)

## Contents

- `ConnectorConnections`: the rules (R-CN1 to R-CN8): names `BarnConn_rest_*`, the four auth
  kinds (API key header, Bearer, Basic, Secret URL), URL and header checks, the F2 refusal of any
  credential BarnCRM did not create, the BarnCRM Connections access set, the Admin Journal entry
  on a key replaced, redacted error logs.
- `ConnectorOrg`: the seam over `ConnectApi.NamedCredentials` and the setup objects, faked in tests.
- `ConnectorConnectionsController` and `c/superConnector`, `c/connectorKeyForm`: the Super
  Connector tab. `c/connectorRules` (framework-free) and `c/connectorText` hold the browser rules
  and texts.
- Recipes (CN-02): `ConnectorRecipeDocument` (the document rules, F1 and F4), `ConnectorRecipes`
  and `ConnectorRecipesController` (save, publish, Run As, test, run, retry), `ConnectorIdentity`
  (Recipe Access and the Publish access check), `ConnectorRunner` (the queued runner, started by
  the `Connector_Start__e` event so it runs as the Automated Process user, with checkpoints),
  `ConnectorStepRunner` (each step kind), `ConnectorMapRuntime` (applies a saved map),
  `ConnectorRunStore` (run state, without sharing, registered). Objects `Connector_Recipe__c`,
  `Connector_Run__c`. `c/connectorRecipes`, `c/connectorRecipeEditor`, `c/connectorRuns`,
  `c/connectorRecipeRules` (framework-free) and `c/connectorRecipeText`.
- Flow actions (CN-06): `ConnectorRunRecipeAction` (Run a BarnCRM Connector Recipe) and
  `ConnectorApplyMapAction` (Apply a Saved Map).
- Recipe clock (CN-03): `ConnectorClock` (each lane's heartbeat Queueable, Pause All Recipes),
  `ConnectorTriggers` (schedule times and the Record Change poll), `ConnectorIntegrationUser`
  (the chosen user, its `PlatformEventSubscriberConfig` written through the org connection, the
  BarnCRM Connections move), `ConnectorClockChecks` (Health Check) and
  `ConnectorNightlyJobProvider` (the Connector Cleanup step, registered on Core's Connector
  catalog row). Platform events `Connector_Start__e` (BarnCRM Automation and System lane) and
  `Connector_Start_User__e` (Integration User lane, trigger `ConnectorStartUserTrigger`);
  protected hierarchy setting `Connector_Settings__c`. `c/connectorRecipeClock`.
- Steps and versions (CN-05, CN-08): `ConnectorControlSteps` (For Each items, Wait, Change
  Data), `ConnectorRecipeFiles` (Export Recipe and the import of templates and recipe files,
  storing nothing), field `Previous_JSON__c` for Roll Back. `c/connectorTemplates` (the
  Templates tab) and `c/connectorFileRules` (framework-free file checks).
- `ConnectorHealthCheckExtension` (registered in Core's `HealthCheckExtensions`),
  `ConnectorWhereUsedExtension` (registered in Core's `WhereUsedExtensions`) and
  `ConnectorPostInstall`.
- App `BarnCRM_Connector` (console; left out on capped orgs, ADR-0223), tab `Super_Connector`,
  custom permission `Manage_BarnCRM_Connector`, permission sets `BarnCRM_Connector_Admin` and
  `BarnCRM_Connector_Viewer`, help texts `BarnHelp_Connector`.
