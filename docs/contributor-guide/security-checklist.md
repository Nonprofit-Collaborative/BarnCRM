# Security checklist

The checks an AppExchange security review makes, applied to BarnCRM on every change even
though there is no listing yet (plan Section 8.1). Run through it when a pull request adds an
`@AuraEnabled` method, a dynamic query, a `without sharing` class, a field that can hold
personal data, or any LWC that renders text. The last full pass was the pre-AppExchange review
of 2026-10-28, after the v0.11 hardening pass (2026-10-12); open items are at the end. The
scanner false positives and design justifications for the submission are in
[AppExchange Submission Notes](appexchange-submission-notes.md).

## What CI already enforces

| Check | Where |
| ----- | ----- |
| Every packaged Apex class states its sharing, and every query and DML states an access mode | `scripts/ci/check-apex-access-modes.py` |
| Zero High or Critical Code Analyzer findings (PMD, ESLint LWC rules, retire-js, Flow scanner) | `sf code-analyzer run --severity-threshold 2` in the workflow |
| No dependency on objects a Platform-only org lacks | `scripts/ci/check-standard-objects.sh` |
| Every test runs as a user it creates, so no test passes on access the runner happens to hold | `scripts/ci/check-tests-run-as.py` |

## Manual checks

### 1. `@AuraEnabled` methods

- [ ] A method that writes data, or reads admin-only data, checks a custom permission first
  (`FeatureManagement.checkPermission`, or the service guard that wraps it, such as
  `requireManagePermission()` or `AutomationControl.canManage()`), and returns a structured
  error rather than a stack trace when refused.
- [ ] Record reads and writes run in user mode (`WITH USER_MODE`, `AccessLevel.USER_MODE`,
  `as user`). System mode is allowed only where the class header says why (package-owned
  fields, scheduled upkeep, protected settings: ADR-0021, ADR-0027, ADR-0057, ADR-0076).
- [ ] A read with no permission check returns only non-sensitive configuration (job state,
  schedules, module state, release notes).
- [ ] A lookup that returns people's names and email addresses is gated like the action it
  serves (`AccessController.searchUsers` follows `changeRole`).

### 2. Injection

- [ ] No user text is concatenated into SOQL or SOSL. Values go in binds
  (`Database.queryWithBinds` or `:variable`).
- [ ] Object and field names in a dynamic query come from `Schema` describe or constants, and
  names typed by a user are checked against the running user's describe first (Find's
  `QueryFieldCatalog` is the model). Sort direction and operators come from an allowlist.
- [ ] A `LIKE` term typed by a user escapes `%` and `_` (`UserSelector` does) when wildcards
  are not meant.
- [ ] A CSV a user downloads guards cells that start with `=`, `+`, `-`, `@`, tab or carriage
  return (`AccountingExportService` does).

### 3. Sharing

- [ ] Classes are `with sharing` unless the header comment justifies `without sharing` by
  ADR. No `inherited sharing`, no inner `without sharing` classes.

### 4. Hard-coded Ids

- [ ] No Id literal in packaged code or metadata. Tests that need an Id no record carries use
  `FakeIds.of(type, n)` or `FakeIds.ofPrefix(prefix, n)`, which build it from the key prefix
  at run time.

### 5. Error Log and personal data

- [ ] `Message__c` is a custom label plus counts or record names, never exception text.
- [ ] Exception text and stack traces go only to `Technical_Detail__c`, which only the
  BarnCRM Admin permission set can read: a validation message can repeat a record's values.
- [ ] Nothing logs a full record, a request body, a token or an email body. Inbound gift
  refusals log the external id and the error code only.
- [ ] The digest email never copies a message, a technical detail or a record Id.

### 6. Callouts and external resources

Checked 2026-11-12 (D-200, N12). Every callout site, its endpoint and how it is allowed:

| Site (`setEndpoint`) | Endpoint | Allowed by | Credential |
|---|---|---|---|
| `PaymentStripe.cls:96` | `https://api.stripe.com/v1/` | Remote Site `Barn_Stripe_Api` | Stripe secret key, `Authorization: Bearer` header |
| `PaymentPayPal.cls:462`, `:482` | PayPal live or sandbox API | Remote Sites `Barn_PayPal_Api`, `Barn_PayPal_Sandbox_Api` | OAuth client credentials (client id and secret, Basic header) for a short-lived token |
| `AddressVerifier.cls:242` | `https://us-street.api.smarty.com/street-address` | Remote Site `Barn_Smarty_Api` | Smarty auth id and token in the query string (Smarty's only server-side scheme) |
| `AddressVerifier.cls:301` | `https://addressvalidation.googleapis.com/v1:validateAddress` | Remote Site `Barn_Google_Address_Api` | Google API key in the query string |
| `GrantFinder.cls:66` | `https://api.grants.gov/v1/api/search2` | Remote Site `BarnCRM_Grants_Gov` | None (public API) |
| `ImportNewFieldService.cls:350` | `callout:Barn_Org_Connection` (the org's own Metadata API) | Named credential over External Credential `Barn_Org_Connection` | The admin's own OAuth principal |
| `OrgMetadataApi.cls:31`, `OrgToolingApi.cls:69` | The org's own Metadata and Tooling APIs | Same org | The running admin's session id (`UserInfo.getSessionId`), see below |

- [ ] Every endpoint is a constant or the org's own domain; nothing builds a host from input.
- [ ] Every response body is parsed, never logged; failures log the status code and our label.
- [ ] Session id: `OrgMetadataApi`, `OrgToolingApi` and `ImportNewFieldService` send the
  running user's session id to the org's own APIs only, never off the org, never stored or
  logged, and only for admin tools (verify each caller's permission check at review). Say so in
  the review submission; the reviewer's rule is that a session id never leaves Salesforce.
- [ ] No third-party JavaScript. Static resources hold data (sample data JSON), not code.

**Inbound endpoints (`@RestResource`).** All `global` because the platform requires it.

| Class | URL mapping | Who calls it | Gate |
|---|---|---|---|
| `FormPublicRest` (forms) | `/barncrm/forms/v1/*` | An integration user (Portal Builder, off-platform pages) | Class access through a Forms permission set; the form's `ticket`; honeypot `trap` |
| `PortalApi` (portal) | `/barncrm/portal/v1/*` | The portal's integration user | Class access; every route but sign-in needs the `X-Barn-Portal-Session` token |
| `PaymentWebhookRest` (payments) | `/barncrm/payments/v1/*` | Stripe and PayPal, as the Site guest user (`Payments_Webhook_Guest`) | Stripe: `Stripe-Signature` HMAC verified with the webhook secret before anything is stored; PayPal: verified by a call back to PayPal. Stores one Payment Event in system mode, nothing else |
| `InboundGiftResource` (mirror) | `/v1/gifts` | An integration user | Class access in the Inbound Gifts set, user-mode CRUD (open item below) |

**Guest Sites.** BarnCRM ships no Site. `FormsSites` and `PaymentSites` only read the org's
active Salesforce Sites (system mode, Experience Cloud left out, ADR-0009) for Health Check and
the public links. The guest permission sets (`Forms_Public_Guest`, `Payments_Webhook_Guest`)
grant class access to the public page or webhook and no object access; Health Check's fix
assigns them to a chosen Site's guest user only.

### 7. LWC rendering

- [ ] No `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `lwc:dom="manual"`, `eval` or
  `Function()`.
- [ ] HTML built in Apex escapes merge values (`escapeHtml4`), and is shown only through
  `lightning-formatted-rich-text`, which sanitizes it.
- [ ] Links that open a new tab carry `rel="noopener noreferrer"`.

### 8. Secrets and debug output

- [ ] No passwords, keys or tokens in source or custom metadata. Provider secrets live only
  in the two Protected hierarchy custom settings, org defaults only: `Payment_Keys__c`
  (`Stripe_Secret_Key__c`, `Stripe_Webhook_Secret__c`, `PayPal_Client_Secret__c`, plus the
  PayPal client id) and `Address_Verification_Keys__c` (`Google_Api_Key__c`,
  `Smarty_Auth_Token__c`). In a managed package a Protected setting is unreadable to the
  subscriber's Apex and API; only the packages' own setup pages write them, and those pages
  never send a stored secret back to the browser (at most its last four characters). Why not Named Credentials: see the
  ADR on provider secrets (ADR-0220, `0220-provider-secrets-protected-settings.md`).
- [ ] `System.debug` only as the last resort when logging itself fails, with the exception
  message and no record contents. No `console.*` in LWC.

## Open items from the v0.11 pass

| Item | Where | Why it is open |
| ---- | ----- | -------------- |
| Error Log sharing model is Read/Write | `Error_Log__c` | Owner decision; the recommended default is to keep Read/Write. Every packaged set has View All on the object, so the sharing model only decides who may edit, and only BarnCRM Admin has Edit. Read would break **Mark as seen** (`ErrorLogController.acknowledge`, a user-mode update) on entries owned by someone else, which is most of them, since the event subscriber writes them. Moving to Read needs either Modify All for BarnCRM Admin (which also grants Delete) or a system-mode acknowledge |
| Inbound gift REST endpoint has no custom permission | `InboundGiftResource`, `InboundGiftAction` | Relies on class access (the Inbound Gifts set, for both the endpoint and the action) plus user-mode CRUD; say so in the review submission |
| Core agent-ready actions have no custom permission | `FindPeopleAction`, `GetHouseholdSummaryAction`, `CreatePersonAction`, `GetDataJobStatusAction` | Global invocables (ADR-0104, agent-ready Core actions): user-mode reads and writes, Create Person checks household edit access; class access granted by BarnCRM Staff and Admin (all four) and Read Only (Find People, Get Household Summary); say so in the review submission |
| After-save flow updates its own record | `Template_Relationship_Reciprocal` | Code Analyzer SameRecordUpdate. Cannot move to before-save: it writes the Id of a record it creates in the same run, which exists only after save |

Closed since the v0.11 pass:

| Item | What was done |
| ---- | ------------- |
| `Error_Log_Event__e` readable by Staff and Read Only | Kept (2026-10-13). The org refuses Create on a platform event without Read ("Permission Create Error_Log_Event__e depends on permission(s): Read Error_Log_Event__e"), and publishing needs Create, so every packaged set that publishes holds both |
| Any BarnCRM user could publish `Merge_Settlement_Ready__e` (review C-M1, 2026-10-28) | Fixed (#654): Read Only holds neither Read nor Create on it, and the subscriber settles only records the event's `CreatedById` may edit |
| Error Log entries attributed from a payload field (C-L1) | Fixed (#654): `User__c` comes from the event's `CreatedById` |
| Finish Setup could grant BarnCRM Admin in system mode (C-L2) | Fixed (#654): outside an install, only to the running user, and only with Assign Permission Sets or Manage Users (ADR-0121) |
| Inner queued job with no sharing keyword (C-L4) | Fixed (#654): `TabAccessService.Job` is `with sharing`, and `check-apex-access-modes.py` flags any Core inner async job without a keyword |
| Read Only could read every role assignment (C-L7) | Fixed (#654): `getAccessOverview` refuses anyone without Manage BarnCRM Settings |
| Find, export, Super Transformer and Bulk Delete trusted the picker's object list (C-L3) | Fixed: `QueryFieldCatalog.describeObject` refuses system objects, which covers every entry point and each parent a field path crosses |
| New-tab links without `rel` (C-L6) | Fixed in `findExportFiles`, `optimizerSetup` and `dataManager` |
| View All and Modify All on Account and Contact for BarnCRM Admin (C-M2) | Kept, justified in ADR-0142, the permission set description and the submission notes |
| BarnCRM Access Manager carries Assign Permission Sets (C-L5) | Kept (ADR-0121, D-91), justified in the submission notes |
| Acknowledgment emails ignored the donor's Email Opt Out (G-L4) | Fixed (owner decision, 2026-10-29): an opted-out recipient is never emailed and is thanked by letter (ADR-0144, R-AK13) |
| Giving Admin had View All on `Commitment__c` but not `Gift__c` (G-L5) | Fixed (owner decision, 2026-10-29): removed, so no Giving set has View All on either Private object |
