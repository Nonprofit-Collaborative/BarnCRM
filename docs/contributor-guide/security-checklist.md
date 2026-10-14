# Security checklist

The checks an AppExchange security review makes, applied to BarnCRM on every change even
though there is no listing yet (plan Section 8.1). Run through it when a pull request adds an
`@AuraEnabled` method, a dynamic query, a `without sharing` class, a field that can hold
personal data, or any LWC that renders text. The last full pass was the v0.11 hardening pass
(2026-10-12); its open items are at the end.

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

- [ ] No `Http` callouts, Named or External Credentials, Remote Site Settings or CSP Trusted
  Sites. The only outbound traffic is `Messaging.sendEmail` (acknowledgments, digest) and
  `Metadata.Operations.enqueueDeployment` (custom metadata manager, rollup triggers).
- [ ] No third-party JavaScript. Static resources hold data (sample data JSON), not code.

### 7. LWC rendering

- [ ] No `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `lwc:dom="manual"`, `eval` or
  `Function()`.
- [ ] HTML built in Apex escapes merge values (`escapeHtml4`), and is shown only through
  `lightning-formatted-rich-text`, which sanitizes it.
- [ ] Links that open a new tab carry `rel="noopener noreferrer"`.

### 8. Secrets and debug output

- [ ] No passwords, keys or tokens in source, custom metadata or custom settings.
- [ ] `System.debug` only as the last resort when logging itself fails, with the exception
  message and no record contents. No `console.*` in LWC.

## Open items from the v0.11 pass

| Item | Where | Why it is open |
| ---- | ----- | -------------- |
| Error Log sharing model is Read/Write | `Error_Log__c` | Owner decision; the recommended default is to keep Read/Write. Every packaged set has View All on the object, so the sharing model only decides who may edit, and only BarnCRM Admin has Edit. Read would break **Mark as seen** (`ErrorLogController.acknowledge`, a user-mode update) on entries owned by someone else, which is most of them, since the event subscriber writes them. Moving to Read needs either Modify All for BarnCRM Admin (which also grants Delete) or a system-mode acknowledge |
| Inbound gift REST endpoint has no custom permission | `InboundGiftResource`, `InboundGiftAction` | Relies on class access (the Inbound Gift API set for the endpoint, the Record Inbound Gift Action set for the action) plus user-mode CRUD; say so in the review submission |
| Core agent-ready actions have no custom permission | `FindPeopleAction`, `GetHouseholdSummaryAction`, `CreatePersonAction`, `GetDataJobStatusAction` | Global invocables (ADR-0104, agent-ready Core actions): user-mode reads and writes, Create Person checks household edit access; class access granted by BarnCRM Staff and Admin (all four) and Read Only (Find People, Get Household Summary); say so in the review submission |
| After-save flow updates its own record | `Template_Relationship_Reciprocal` | Code Analyzer SameRecordUpdate. Cannot move to before-save: it writes the Id of a record it creates in the same run, which exists only after save |

Closed since the v0.11 pass:

| Item | What was done |
| ---- | ------------- |
| `Error_Log_Event__e` readable by Staff and Read Only | Kept (2026-10-13). The org refuses Create on a platform event without Read ("Permission Create Error_Log_Event__e depends on permission(s): Read Error_Log_Event__e"), and publishing needs Create, so every packaged set that publishes holds both |
