# ADR-0148: Import Creates a New Field Through a One-Time Org Connection

**Status:** Accepted (owner decision, Brandon, 2026-10-30: "in the import mapping step, a column
can be mapped to a new field, which the app then creates with permissions")
**Date:** 2026-10-30
**Source:** feature C-49d (Super Importer: create a new field); supersedes ADR-0047's "no call to
Salesforce's own APIs" rule and its never-built entry for this one case; reuses the connection
designed in ADR-0082 amendment A2 (slice S15, branch `feature/rollup-s15-spike`)

## Context

A file often has a column the org has no field for. Today the admin leaves the wizard, creates
the field in Setup, gives it field-level security, comes back and starts the import again.
The owner wants the mapping step to create the field.

What the platform allows:

- Apex's `Metadata.Operations.enqueueDeployment`, the path the custom metadata manager uses
  (ADR-0085, with the org setting "Deploy Metadata from Non-Certified Package Versions via
  Apex"), deploys only custom metadata records and page layouts. It cannot create a
  `CustomField`. Neither can DML or `ConnectApi`.
- The admin-deployed pattern of ADR-0138 (D-132: BarnCRM shows the code, the admin deploys it)
  needs no connection, and is what this feature does when there is none: the field's details,
  ready to copy into Setup.
- Only the Metadata API (or the Tooling API) creates a field. A Lightning session cannot call
  it, so Apex calls the org's own API, the self-callout ADR-0047 ruled out.
- Field permissions are ordinary records (`FieldPermissions`), so access is granted with DML,
  not a deploy.

## Decision

1. **One connection, the S15 design, shared.** Core ships one External Credential,
   `Barn_Org_Connection` (Custom protocol, one named principal, no secret). **Set Up
   Connection** on BarnCRM Settings, Import page, creates the Named Credential
   `Barn_Org_Connection` pointing at the org's own My Domain with `ConnectApi` (the URL is only
   known in the org). A queued job calls the Metadata API SOAP endpoint through it with the
   job's own session id in the SOAP header, as S15 and DLRS do. The rollup one-click deploy
   (ADR-0138's deferred alternative) uses this same connection when it is built; no second one
   is added.
2. **Who may.** Creating a field needs Manage BarnCRM Metadata (BarnCRM Metadata Admin, which
   also carries the credential's principal) and Manage BarnCRM Settings (import), plus the
   Salesforce permissions Customize Application and Modify Metadata. Everyone else never sees
   the option.
3. **What can be created.** Text, Long Text Area, Number, Currency, Percent, Date, Date/Time,
   Checkbox, Email, Phone, URL and Picklist (values from the column's distinct values, at most
   200). The label comes from the header; the API name is derived and checked (letters, digits
   and single underscores, starts with a letter, 40 characters at most, not a reserved word,
   not already on the object). The type is suggested from the column's values. The object is the
   one-object template's object, or Contact (a person) or Account (an organization) for a
   people import.
4. **How.** `createMetadata` for the `CustomField` (synchronous); then `FieldPermissions` rows
   give read and edit through BarnCRM Admin and BarnCRM Staff, read through BarnCRM Read Only,
   and read and edit through one optional permission set the admin chooses. The wizard polls
   the job; once the field is in describe it maps the column to it. A failure is one Error Log
   entry in plain words and the message shown in the dialog.
5. **No connection, or a failed call.** The dialog shows the field's details (object, label,
   API name, type, length, picklist values) as text to copy, the steps to create it in Setup,
   and **Refresh Fields**.

## Alternatives considered

- **Setup guidance only (ADR-0047 as written).** No security review scope; keeps the detour the
  owner asked to remove. Kept as the fallback.
- **The custom metadata manager's Apex deploy.** Cannot create a field (above).
- **An OAuth Named Credential with an External Client App per org.** No session id in a callout,
  but an app, a consumer key and an Auth Provider for every org; more setup than the field.
- **Tooling API REST create.** Same connection and session; the Metadata API is what S15 and
  the rollup deploy already speak.

## Consequences

- Security review scope gains one self-callout, one External Credential and a session id in a
  callout header (a standard finding ADR-0138 named). The review notes say: admin-only, one
  endpoint (the org's own), no stored secret, created on an explicit click.
- Unproven on an org: the queued job's session being accepted by the Metadata API, and
  `ConnectApi` creating the Named Credential from packaged code. Both are verified on a test
  org before release; if either fails the feature stays on the Setup guidance path.
- With a namespace, BarnCRM's permission sets become managed and cannot take new field
  permissions in a subscriber org; the grant then goes only to the chosen permission set. The
  External Credential name is qualified at run time (`NamespaceUtil`).
- No new BarnCRM object or field; canonical model unchanged.

## Amendment A1, 2026-10-31: the admin turns on callouts in Setup; access is a second job

QA v21 (D3) proved the path on a test org and found two gaps.

1. **Callouts start off.** A Named Credential created through `ConnectApi` has Enabled for
   Callouts off, and every callout through it fails ("Callout blocked for named credential").
   No `ConnectApi.NamedCredentialInput` or `NamedCredentialCalloutOptionsInput` property sets
   it (compile probes at API 68); Tooling API updates need the full metadata and a working
   callout, which is the thing missing. A `NamedCredential` metadata file with
   `calloutStatus` Enabled does deploy enabled, and a later `ConnectApi` update of its URL keeps
   it enabled, but it would have to ship with a placeholder URL that every package upgrade
   puts back, breaking the connection each release. So the decision stays a one-time
   connection, with one guided Setup step: Set Up Connection creates the Named Credential,
   the panel reads its callout status (`ConnectApi.NamedCredentials.getNamedCredential`; SOQL
   has no such column), shows "Set up, one step left" with the exact steps (Setup, Named
   Credentials, BarnCRM: this org, Edit, Enabled for Callouts, Save) and **Check Again**, and
   only then reads **Connected**. Until then the dialog keeps the Setup fallback and creating a
   field is refused in words. Upgrades never touch the admin's Named Credential.
2. **Access in its own transaction.** `FieldPermissions` rows for the new field are not saved in
   the transaction whose `createMetadata` created it (no rows on the test org). The create job
   now chains a `GrantAccessJob`, which gives the access.

With both, the test org created a Text field through the queued job (the session in the SOAP
header was accepted), BarnCRM Admin and Staff got read and edit, Read Only read, and
`deleteMetadata` through the same connection removed it.
