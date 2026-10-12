# ADR-0085: The custom metadata manager edits only types BarnCRM reads directly

**Status:** Accepted (owner standing instruction to proceed as recommended, 2026-10-12; to be amended if he decides otherwise)
**Date:** 2026-10-12
**Source:** plan Section 6.1 item 9 (CMDT Manager, for consideration); ADR-0006 (D-06)

## Context

Plan Section 6.1 item 9 proposes an in-app place for administrators to add, edit and
archive BarnCRM's custom metadata records, because Principle 1 and Section 9.3 keep every
admin setting out of Setup. ADR-0006 made shipped defaults custom metadata, read only to
admins, and materialized the ones admins edit into custom object records.

Core ships five types. Rollup Definition Default and Import Template Default are
materialized into `Rollup_Definition__c` and `Import_Template__c`, which the Rollups and
Import pages already edit (Giving's Receipt Template Default likewise). Automation Registry
and Setting Definition describe packaged handler classes and console rows. Relationship
Type is read directly by `RelationshipService`: it has no materialized copy, so today an
organization that adds a Type picklist value gets "Other" on the other side, and the only
fix is Setup.

The platform constrains the design. Apex writes custom metadata only through
`Metadata.Operations.enqueueDeployment`, which is asynchronous, reports through a
`Metadata.DeployCallback`, cannot delete a record, and cannot run in a test. A packaged
caller needs the subscriber's "Deploy Metadata from Non-Certified Package Versions via
Apex" setting. With the namespace deferred (ADR-0001) `NamespacePrefix` cannot tell a
shipped row from a subscriber row.

## Decision

1. **Only types read directly are editable.** `CustomMetadataManagerService` holds a
   registry of editable types: today Relationship Type alone, with its editable fields, its
   archive field (`Active__c`), the field that must be unique among active rows
   (`Type__c`), and the fields whose values must be active choices of
   `Relationship__c.Type__c`. Materialized types and code catalogs are not registered
   (canonical model R-D2).
2. **Shipped rows are marked and read only.** A registered type carries `Is_Shipped__c`,
   true on every shipped row. The manager lists shipped rows separately and refuses to
   change one. Rows it creates have `Is_Shipped__c` false, `protected` false, and a
   DeveloperName starting `Org_`, which no shipped row may use.
3. **Archive, never delete.** Archive clears the archive field; restore sets it, after the
   uniqueness check. The admin guide says where to delete in Setup.
4. **Outcome is recorded by the callback.** `CustomMetadataDeployCallback` writes one
   `Setting_Change__c` with `Deployment_Id__c` on success (canonical model R-S6) and an
   Error Log entry referencing the deployment on failure. The page polls by deployment Id.
5. **Access is a custom permission in its own permission set.** `Manage_BarnCRM_Metadata`
   gates the console row (`Required_Permission__c`) and every controller method. It is
   granted only by `BarnCRM_Metadata_Admin`, which is in no role, like Duplicate Review.
   The set carries no user permissions (Customize Application, Modify Metadata): their
   dependency chains vary by license and would make the packaged set fail to install.
6. **A section of BarnCRM Settings, not a tab.** The page is a `Component` row in General,
   following ADR-0020, so it shares the console's search and audit list.

## Alternatives considered

- **Every type editable, as the plan item reads.** Rejected: a subscriber row in a
  materialized type would never reach the record the feature reads, and one in Automation
  Registry or Setting Definition would name a class or field that does not exist.
- **Move relationship types to a custom object.** Simpler writes, and the plan's offered
  alternative, but not accepted by the owner yet; this ADR keeps that door open.
- **Tell shipped rows apart by a hard-coded name list or `NamespacePrefix`.** The list
  drifts from the metadata; the prefix is empty until the namespace exists.
- **Check the user's Customize Application and Modify Metadata in Apex.** Not done until an
  org run shows the deployment needs them; a failed enqueue already returns a plain message.

## Consequences

- A new editable type needs a registry entry, `Is_Shipped__c` on the type and its shipped
  rows, and an admin guide row.
- The owner should confirm the scope narrowing (decision 1) and the section placement
  (decision 6), both of which differ from the plan item's wording.
- Revisit decision 5 if an org run shows the deployment fails for a holder without
  Customize Application or Modify Metadata.
