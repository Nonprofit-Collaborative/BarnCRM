# BarnCRM Connector: Security Review of Connection Secrets Entered on a BarnCRM Page

**Status:** Review (independent, read-only)
**Date:** 2026-11-20
**Reviewer:** W2 R1.31 Security review
**Scope:** `integration-hub-design.md` Sections 3.3, 3.5, 3.6 and 5, Section 8 Open Decision 2;
ADR-NEXT `NEXT-integration-module.md`; ADR-0229 and ADR-0220; the current Payments and Address
Verification credential code; Core `ErrorLogger`, `ErrorLogWriter`, `UserErrors`, the Admin
Journal and `Setting_Change__c` / `Setup_Change__c`.

## 1. Verdict

**Secure with required mitigations.** Taking a secret on a BarnCRM page and writing it to an
External Credential principal with `ConnectApi.NamedCredentials` is not materially less secure
than typing it in Setup, provided the mitigations marked **Required** below are in the ADR and
covered by tests before the Connector is merged. Without them, the design has two High findings
that let a recipe author or a forged webhook leak a secret (F1, F4), and one that lets a
Connector admin replace a packaged provider's key (F2).

Most serious findings are not caused by page entry at all: F1 (merge-field injection), F4 (host
change and path host confusion) and F5 (secret URLs) exist even if every secret were typed in
Setup, because they come from the Connector's generic executor. Only F3, F7, F8, F9 and F10 are
specific to the secret passing through BarnCRM's page and Apex.

Open Decision 2 can be approved on condition that F1 to F7 are accepted as design requirements
and F9 changes the OAuth browser path to a guided Setup step.

## 2. How the Secret Travels (as designed)

1. Admin types the secret into an LWC input on the Connections section.
2. The LWC calls an `@AuraEnabled` method; the value is in the Aura POST body (`/aura?...`) over
   TLS, protected by the session's Aura CSRF token.
3. Apex builds a `ConnectApi.CredentialInput` and calls `createCredential` / `updateCredential`
   as the running user. The platform encrypts the value into the principal.
4. Callouts go to `callout:BarnConn_<connector>_<6>`; the auth header is a
   `{!$Credential.BarnConn_x.Param}` formula resolved by the platform, so Apex never reads it.

At rest the secret is where ADR-0229 already puts Stripe's key. The new exposure is steps 1 to 3
(transit through BarnCRM's UI and Apex) and the generic executor in step 4.

## 3. Findings

Severity: High (exploitable to leak a secret or redirect money/data, needs a fix before build),
Medium (real exposure or a false security claim, fix in the design), Low (defense in depth or
documentation).

### F1 (High): Merge-field injection into callouts

**Issue.** Connector Named Credentials have Allow Formulas in HTTP Header on, and the platform
resolves any `{!$Credential...}` text that Apex puts into a header (that is how ADR-0229's
headers work). The Call an App step sends "non-secret headers" typed by a recipe author, and
data pills put values from webhook payloads, app responses and records into headers, query,
path and body. A value such as `{!$Credential.BarnConn_mailchimp_ab12cd.ApiKey}` arriving in a
webhook post, a record field or a recipe header would be resolved by Salesforce and sent to the
app (and possibly echoed back into a record or a run's stored response). If the platform also
resolves `$Credential` for an External Credential that is not the one linked to the called
Named Credential, a recipe author could send any connection's secret, or `Barn_Stripe`'s, to a
generic connection pointing at a host they control. If Allow Formulas in HTTP Body were ever on,
the body path is open too.

**Required mitigation.**
- Every Connector Named Credential is created with Allow Formulas in HTTP Body **off**; the
  catalog schema has no way to turn it on.
- Only the catalog's auth header template may contain `{!`. The executor refuses (fails the
  step with a fixed message) any header name or value, path, query value or body string that
  came from recipe configuration, data pills, webhook payloads, app responses or records and
  contains `{!` (checked after building, before `send`). Tests cover a payload, a record field
  and a recipe header carrying `{!$Credential.` text.
- The Generic REST connector builds its auth header from the auth kind, never from free text.

**Org test.** Whether `{!$Credential.Other_EC.Param}` resolves in a callout to a Named
Credential linked to a different External Credential. If it does, treat F1 as Critical.

### F2 (High): Writing a credential BarnCRM does not own

**Issue.** The page's Apex can create, update and delete principals and Named Credentials by
name. If a name (or id) comes from the client, a Connector admin could point the write at
`Barn_Stripe` / `Barn_Stripe_Key` and replace the org's Stripe key with their own Stripe
account's key: donations would then settle to the attacker. The same applies to `Barn_PayPal`,
to `Barn_Org_Connection` (ADR-0148) and to any subscriber credential.

**Required mitigation.**
- The server generates every new name (`BarnConn_<connector>_<6 random>`) and never accepts one
  from the client for creation.
- Update, Disconnect and Delete accept only a name that starts with `BarnConn_`, exists in the
  org's External Credential list, and is linked to a Named Credential with the same prefix.
  Anything else is refused before any ConnectApi call. A test tries `Barn_Stripe`.
- The principal name and parameter names come from the connector catalog, never the client.

### F3 (High): Who may call the credential methods

**Issue.** An `@AuraEnabled` method is callable directly from the Aura endpoint by any user
whose profile or permission sets grant the Apex class, regardless of which page shows the
button. A third-party write-up states the platform gates Connect API credential writes on the
system permission `ManageNamedCredentials` ("modify Named Credentials and External Credentials
through the Metadata, Tooling, and Connect API"); the official reference could not be fetched.
The same write-up suggests, as a workaround, running the update asynchronously "on behalf of an
admin". That pattern would let anyone with the Connector permission write credentials with an
administrator's rights and would persist the secret in queued job state.

**Required mitigation.**
- Every credential-writing method checks, first, the custom permission
  `Manage_BarnCRM_Connector` **and** that the user holds `ManageNamedCredentials` or Customize
  Application (a `PermissionSetAssignment` query, as `BarnCRMPermissions` already does for
  Customize Application). Refuse with a plain message otherwise.
- The ConnectApi call runs synchronously in that request, as that user. Never queue, schedule
  or hand a secret to the runner, a Queueable, a platform event or any system-context path.
- The controller class is granted only by `BarnCRM_Connector_Admin`; it is never in the webhook
  guest permission set or any user-level set. The page is in the internal app only (not on an
  Experience site).
- Clickjacking and CSRF: Lightning Experience requests carry the Aura token and are framed only
  by Salesforce's own clickjack protection; no Visualforce page or `@RestResource` exposes the
  write. No extra work beyond keeping it that way.

**Org test.** Which permission `createCredential`, `updateCredential`, `createExternalCredential`
and `createNamedCredential` require (expected `ManageNamedCredentials`; confirm that a user with
only the Connector permission set gets an error).

### F4 (High): Host change and host confusion after the secret is stored

**Issue.** The secret is bound to whatever URL the Named Credential has. Three ways to send it
elsewhere:
1. **Editing the base URL** of an existing connection to an attacker host while keeping the
   principal (on the BarnCRM page, or via a "Generic REST" base URL field).
2. **Path suffix host confusion.** A Call an App custom request appends a typed path to
   `callout:BarnConn_x`. If the Named Credential URL is `https://api.example.com` and the path is
   `.attacker.net/x` or `@attacker.net/x`, simple concatenation yields another host. Whether the
   platform normalises or blocks this is not documented.
3. **Fetch back.** A posted `api_url` compared to the Connection's host by string prefix
   (`https://api.example.com.attacker.net`, `https://api.example.com@attacker.net`) passes a
   naive check.

**Required mitigation.**
- A connection's scheme and host are immutable once a secret is stored. Changing them means a
  new connection with the secret entered again (or one call that replaces URL and secret
  together, never URL alone). Catalog connectors lock the host to the catalog pattern
  (Mailchimp's `{dc}` must match `^[a-z]{2}[0-9]{1,3}$`, derived in the browser as designed).
- Base URLs must be `https://` (refuse `http://`, which would send the secret in clear).
- Every path appended to `callout:` must start with `/`, must not start with `//`, and must not
  contain `@`, `\`, `{!`, CR or LF; each value inserted into it is URL-encoded (as designed).
- Fetch back parses the posted URL with `System.Url`, requires `https`, no user info, the exact
  host (case-insensitive) and port of the connection, then calls `callout:` plus that URL's path
  and query only. The posted URL is never used as the endpoint.

**Org test.** `callout:NC` plus `.attacker.net/x` and plus `@attacker.net/x` against a test
endpoint, to learn whether the platform already blocks it (the validation above stays either
way).

### F5 (Medium): Secret-URL connections (Slack, Microsoft Teams) are not stored encrypted

**Issue.** For Slack incoming webhooks and Teams Workflows the URL is the secret. Salesforce does
not substitute encrypted External Credential values into a Named Credential URL (Salesforce Help
article 004695556), so the design stores the whole secret URL as the Named Credential's URL,
which is configuration, not an encrypted credential. It is readable by anyone who can view the
Named Credential in Setup (View Setup and Configuration), through Tooling and Metadata API
retrieve, through `ConnectApi.NamedCredentials.getNamedCredential(s)` (which the Connections
list itself would call), possibly in Setup Audit Trail entries and therefore in BarnCRM's
`Setup_Change__c` copy (reportable, ReadWrite sharing), and in debug logs that show callout
endpoints. The design's claim "never stored, logged or shown again" is false for this kind.
Typing the URL in Setup has the same exposure, so it is not worse than Setup, but it must not be
described as protected. Impact if leaked: anyone can post messages (phishing) into that channel.

**Required mitigation.**
- Correct the design, ADR and page text: a secret URL is stored as configuration and is visible
  to administrators who can view Setup.
- Never return the URL to the client: the Connections list shows the host and last four
  characters only; Run records store the step's path, never the full URL.
- Slack: offer and recommend a bot token sent as `Authorization: Bearer` to `chat.postMessage`
  (an encrypted principal), with the incoming webhook as the simpler alternative. Teams
  Workflows has no header option: keep it with the disclosure.
- `SetupChangesCopy` (or its equivalent) masks Named Credential URL values if org testing shows
  the audit trail records them.

**Org test.** Whether Setup Audit Trail records the old and new URL of a Named Credential.

### F6 (Medium): Read-back of stored secrets

**Issue.** The Connect credential input carries an `encrypted` flag per value (Salesforce's own
examples send secrets with `encrypted: true` and ids such as `clientId` with `false`). A value
written with `encrypted: false` is plain configuration and can be expected to come back from
`getCredential` to anyone allowed to call it. Setup always encrypts authentication parameters,
so this is a way page entry could be weaker than Setup if coded carelessly.

**Required mitigation.**
- Every secret parameter (key, token, password, client secret) is written with
  `encrypted = true`; only non-secret ids (client id, user name) may be `false`. A unit test
  asserts the flag for each auth kind.
- BarnCRM never calls `getCredential` to return values. The Connections list and the edit form
  return names, labels, host, auth kind and status only; the secret box is always empty
  ("Replace key").

**Org test.** That `getCredential` returns no clear value for an `encrypted = true` parameter.

### F7 (Medium): Error Log, exceptions and audit records

**Issue.** `ErrorLogger.technicalDetail` stores `getTypeName() + getMessage() + stack trace` in
`Technical_Detail__c` and `ErrorLogWriter` also publishes it as a platform event (retained by the
bus and visible to subscribers of that event). A ConnectApi or validation exception whose
message echoes an input value would put the secret in a record that every Error Log reader and
the digest email see. `UserErrors.wrap` shows "known" exception messages to the user. An
unhandled exception would send an Apex exception email with the message. Separately,
`SettingsService` writes `Setting_Change__c` with `Old_Value__c` / `New_Value__c`: a secret must
never go through it.

**Required mitigation.**
- Credential-writing methods catch every exception. They log a fixed message plus the exception
  type only, after replacing any occurrence of the secret (and of each secret part) in the
  message with `****`; they never pass the raw exception to `ErrorLogger.log`, `logWithMessage`
  or `UserErrors.wrap`.
- No `System.debug` of inputs, credential input objects or callout requests anywhere in the
  module (Code Analyzer's AvoidDebugStatements already flags it; keep it unsuppressed here).
- The secret is never a field on any object, setting, Admin Journal row, Setting Change row,
  Connector Run, or platform event, and never in a Lightning Message Service message.
- Callout responses stored on runs (failed-step responses are trimmed) are stored only for
  catalog check calls and steps, never for the credential write.

### F8 (Low, Medium for unmanaged installs): Debug logs capture method arguments

**Issue.** Salesforce documents that an Apex Code log level of FINEST records "all Apex variable
assignments" and warns to consider sensitive data before enabling it. A method parameter holding
the secret is logged as a variable assignment. Setup entry does not have this exposure. In an
unmanaged or source install, any administrator who can set a trace flag on the person entering
the key captures it. In the managed package, managed code is logged as `[EXTERNAL]` for the
subscriber, but the ISV can enable debug logs for its namespace (License Management App or
subscriber login access), and those logs show the package's code unobfuscated.

**Required mitigation.**
- Keep the secret in as few variables as possible: pass the `@AuraEnabled` parameter straight
  into the ConnectApi input in one method; no helper chain, no wrapper class holding it.
- Admin guide: enter keys only when no debug logging is active for you; replace a key if it was
  entered while a trace flag was on.
- BarnCRM's own policy: never enable namespace debug logs at FINEST in a subscriber org.
- Support only the managed package for production (as ADR-0220 already states).

**Org test.** In a managed install, whether a subscriber trace flag at FINEST shows
`VARIABLE_ASSIGNMENT` lines for namespaced code.

### F9 (Medium): OAuth browser sign-in: Auth Provider created at run time

**Issue.** An Auth Provider holds the OAuth client secret. Creating one at run time needs the
Metadata API, which in BarnCRM is called only from a queued job because "a Lightning session
cannot call the API" (`OrgMetadataApi`). The client secret would therefore be held in Queueable
state, placed in a SOAP body, and exposed to F7 and F8 on the job's failure paths. Salesforce's
reference also says the consumer secret must be supplied encrypted on create, so the run-time
path may not work at all.

**Required mitigation.** Make the guided Setup step the primary path for the Auth Provider: the
page shows the provider type, callback URL and scopes, and the admin pastes the client id and
secret into Setup's Auth Provider form. BarnCRM may then create the External Credential and
Named Credential that reference it (no secret involved). Drop run-time Auth Provider creation
from the design.

### F10 (Low): Browser and LWC handling

**Issue and required mitigation.**
- Use `lightning-input type="password"` with `autocomplete="new-password"`; never prefill.
- Clear the value from the component after the call returns, success or failure; keep it out of
  any `@track` object that is logged, any store, `localStorage`, `sessionStorage`, URL, LMS
  message or custom event.
- The write method is not `cacheable=true` (Aura client action storage applies only to cacheable
  methods); its response never contains the secret.
- No `console.log` in the module (lint rule).
- Mailchimp's data center is derived in the browser (as designed) and sent as a separate
  non-secret value.

Residual: the person typing can see the value in their own browser developer tools, and browser
extensions with page access can read the field. This is the same for Setup.

### F11 (Low): Key swap to another account on the same host

**Issue.** A Connector admin who replaces a Mailchimp key with a key for their own Mailchimp
account keeps the host, so F4 does not catch it, and every recipe then sends donor data to the
other account. This is equally possible in Setup (and for `Barn_Stripe` today).

**Mitigation (recommended).** Write one Admin Journal or Error Log Info entry "Connection key
replaced" with who and when (no value); where the app's check call returns an account name or id
(Mailchimp `/ping` does not, `/` does), show it after Check Connection so a change of account is
visible; Health Check lists connections whose key changed in the last 7 days.

### F12 (Low): The org-owned "BarnCRM Connections" permission set

**Issue.** BarnCRM inserts principal access into an unpackaged permission set and assigns it.
Apex DML on `PermissionSetAssignment` runs in system mode, so a careless method could assign it
to arbitrary users, and anyone who adds permissions to that set gets them auto-assigned to every
Connector admin. One write-up also reports there is no Apex path to link a permission set to a
principal (`SetupEntityAccess`), which the design already lists as an org test with a fallback.

**Mitigation (required for the assignment part).** Assign only to users who already hold
`BarnCRM_Connector_Admin` or are the runner; never take user ids from the client; Health Check
warns when the set contains anything other than External Credential principal access.

### F13 (Low): Inbound webhook endpoint (Section 3.3)

The design is sound: guest only stores, 256-bit token kept only as its SHA-256 hash, 404 with
an empty body, body and hourly caps, idempotency, fetch back limited to the connection's host,
user-mode processing as the runner. Notes:
- The token is in the query string, so it can appear in the sending app's logs, proxies and
  Event Monitoring URI fields. Accept it also in a header (`X-BarnCRM-Token`) where the sender
  allows custom headers; keep the query form for those that do not.
- Webhook payload values are the main source of F1 injection text; the F1 check applies to them.
- Fetch back must follow F4's parsing rules.
- The guest permission set keeps only the REST class (no Connections controller, no principal
  access: the receiver makes no callout).
- Without signatures, a stolen token lets anyone create runs that the recipe then processes as
  the runner. Recipes on webhook triggers that write records should prefer fetch back, and the
  page should say so when a connector offers it.

## 4. Areas Checked and Found Acceptable

| Area | Finding |
|---|---|
| Aura transport | TLS, same-origin, Aura CSRF token. No server-side request-body logging by Salesforce found; Event Monitoring's Aura Request event records Apex action names and timings, not arguments. |
| Lightning debug mode | Only turns off minification; logs nothing server-side. |
| Field Audit Trail, field history, Shield | Not involved: no field holds the secret. |
| Setup Audit Trail | Records that a credential changed and who; encrypted parameter values are not expected to appear (to confirm with F5's test). Same as Setup entry. |
| Platform events, LMS | Not used for the secret if F7 and F10 are followed. |
| At rest | Same store and encryption as ADR-0229 (External Credential principal). |
| Who can use a stored secret | Same as Setup entry: holders of principal access can make callouts; Modify All Data or Author Apex users can use the credential or change its URL in Setup (Trailhead: they "might be able to extract the credentials themselves"). A platform property, not a BarnCRM one. |
| Managed package boundary | The secret is never in a Protected setting, so the namespace boundary is not what protects it; the platform credential store is. Subscriber-created credentials have no namespace: do not pass `BarnConn_` names through `NamespaceUtil.qualify`. |

## 5. Comparison with Entering the Secret in Setup

| Property | Setup (ADR-0229) | BarnCRM page, with mitigations |
|---|---|---|
| Who can write | Users with Setup access to Named Credentials | Same platform gate (`ManageNamedCredentials`), plus BarnCRM's custom permission (F3) |
| Where it rests | Encrypted principal | Same, if `encrypted = true` (F6) |
| Read-back | None | None, if F6 holds |
| Transit | Salesforce Setup only | Also BarnCRM's LWC and one Apex method (F7, F8, F10) |
| Debug log exposure | None | FINEST trace on the person entering it (F8) |
| Error Log exposure | None | None, if F7 holds |
| Which credentials can be written | Any | Only `BarnConn_` ones (F2): narrower |
| Secret URL kinds | Visible in Setup | Same (F5) |

**Residual risks after mitigation:**
1. A FINEST debug log on the person entering the key (F8); documented, rare, admin-only.
2. Secret-URL connections remain readable configuration (F5); impact limited to posting into one
   channel.
3. Administrators with Modify All Data, Author Apex or `ManageNamedCredentials` can use any
   connection, change its URL in Setup, or swap its key (F11); inherent to Named Credentials.
4. Anyone who can publish recipes acts with the runner's access and every connection
   (Open Decision 4); a Connector admin can build a recipe that sends records to a generic
   connection of their choosing. This is data movement by an administrator by design, not a
   secret leak, and equals what Flow HTTP Callout allows.
5. A stolen webhook token lets someone create runs (F13), bounded by caps and fetch back.

## 6. AppExchange Security Review

- Salesforce's checklist asks that secrets are stored in protected custom metadata, protected
  custom settings or Named Credentials, are never hard-coded, and are never displayed to the user.
  The protected-setting guidance is aimed at secrets common to all package users (the ISV's own
  key); BarnCRM holds none. Subscriber-owned keys in Named Credentials is the ADR-0229 position.
- A search-result excerpt of Salesforce's "Top 20 vulnerabilities" blog says Named Credentials
  are "generally not recommended" but may be permitted case by case; the page could not be
  fetched to read the context. Expect the reviewer to ask why. The answer to give: these are the
  subscriber's own third-party keys, used only in callouts the subscriber configures, never
  readable by Apex, and the Trailhead caveat (admins with Modify All Data or Author Apex can use
  them) applies equally to any store the subscriber's admins control.
- UI entry is not prohibited. Reviewers check that the value is not logged (`System.debug`),
  not returned to the client, not stored in a readable field or setting, sent only over HTTPS,
  and that the endpoint enforces CRUD/permission checks. F3, F6, F7 and F10 cover these; F4's
  `https` rule covers transport.
- Provide in the submission: the data flow in Section 2, this review, and the Code Analyzer run
  showing no debug statements or unsuppressed findings in the module.

## 7. Verified in Documentation versus Assumed

**Verified (page read):**
- Salesforce Help 004695556: encrypted (secret) values are not substituted into Named Credential
  endpoint URLs; put the key in a header instead.
  https://help.salesforce.com/s/articleView?id=004695556&language=en_US&type=1
- Trailhead, Secure Secrets Storage: Modify All Data or Author Apex users can modify or call
  Named Credentials and "might be able to extract the credentials themselves"; protected
  settings in a managed package are invisible to subscribers.
  https://trailhead.salesforce.com/content/learn/modules/secure-secrets-storage/protect-secrets-using-platform-features
- Connect API credential payloads use a per-value `encrypted` flag (secrets `true`, ids `false`);
  secrets cannot be moved between orgs in clear. Unofficial gist by a Salesforce author.
  https://gist.github.com/rossbelmont/b797c1871dd1187657db81cf1431b755
- Connect API credential writes require the `ManageNamedCredentials` system permission; the
  "asynchronous on behalf of an admin" workaround. Third-party.
  https://www.digitalflask.com/blog/granting-non-admin-users-access-to-update-named-credentials-in-salesforce
- No Apex API links a permission set to a principal. Third-party.
  https://www.robbieduncan.com/blog/summer-23-named-credentials-for-apex-developers
- Apex Recipes `createNamedCredential` takes a permission set name.
  https://github.com/trailheadapps/apex-recipes/wiki/NamedCredentialRecipes

**From Salesforce documentation search excerpts only (pages returned 403 to fetching):**
- Debug logs: FINEST logs all variable assignments; managed code is marked `[EXTERNAL]`.
  https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_debugging_debug_log.htm
- ISV debug logs for a namespace through the LMA or login access, unobfuscated.
  https://developer.salesforce.com/docs/platform/pkg2-dev/guide/apex-debugging-sub-org.html
- Aura Request event type records action names and timings.
  https://developer.salesforce.com/docs/platform/object-reference/references/eventlogfile-supported-event-types/object-eventlogfile-lightning-component.html
- AuthProvider consumer secret: must be encrypted on create; exported as a placeholder.
  https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/meta_authproviders.htm
- Security review: secrets in protected custom metadata or settings; Named Credentials
  case by case.
  https://developer.salesforce.com/blogs/2023/08/the-top-20-vulnerabilities-found-in-the-appexchange-security-review
  and https://developer.salesforce.com/docs/atlas.en-us.secure_coding_guide.meta/secure_coding_guide/secure_coding_storing_sensitive_data.htm

**Not verified (official ConnectApi.NamedCredentials reference returned 403):** the exact
permissions per method, and what `getCredential` returns for encrypted values.

**From the repo (read):** `ErrorLogger.technicalDetail` content, `ErrorLogWriter` event
publishing, `UserErrors.wrap` behavior, `Setting_Change__c` old and new values,
`Setup_Change__c` copying the Setup Audit Trail, `OrgMetadataApi` running only in queued jobs,
`PaymentsSetupController` never writing principals, and the packaged `Barn_Stripe` credential
shape.

## 8. Only an Org Test Can Confirm

1. Cross-credential `$Credential` resolution in a header (F1; decides Critical or High).
2. Permission each ConnectApi credential method requires (F3).
3. Whether `callout:NC` plus `.host` or `@host` suffixes change the host (F4).
4. Whether Setup Audit Trail records Named Credential URLs (F5).
5. `getCredential` output for `encrypted = true` values (F6).
6. Whether a subscriber FINEST trace shows variable assignments in namespaced code (F8).
7. Already listed in the design: `createCredential` for Custom protocol principals,
   `SetupEntityAccess` inserts for principals, `callout:` from namespaced Apex to a
   subscriber-created Named Credential.
