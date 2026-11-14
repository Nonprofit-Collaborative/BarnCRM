# ADR-0220: Provider secrets stay in Protected custom settings in the managed packages

**Status:** Accepted (builder decision, for Brandon to confirm)
**Date:** 2026-11-12
**Source:** D-199 (2GP managed packages from the first pilot, namespace `barn`), D-200 item N7
("move the secrets to External Credential principals and Named Credentials if the platform
allows the existing callouts and the setup pages to set them through Apex; otherwise keep
protected settings for managed and record why"). Builds on ADR-0201 (Payments module) and the
Address Verification module's ADR, and on the security checklist, section 8.

## Context

Five provider secrets are stored today in two Protected hierarchy custom settings, org
defaults only, written by each module's setup page (write-only: a saved key is never sent back,
at most its last four characters):

| Setting | Field | Used for |
|---|---|---|
| `Payment_Keys__c` | `Stripe_Secret_Key__c` | `Authorization: Bearer` on Stripe calls (`PaymentStripe`) |
| `Payment_Keys__c` | `Stripe_Webhook_Secret__c` | HMAC check of the `Stripe-Signature` header on each webhook, in Apex (`PaymentStripe.verify`, called by `PaymentWebhookRest` as the Site guest user) |
| `Payment_Keys__c` | `PayPal_Client_Secret__c` | Basic header of PayPal's OAuth client-credentials token call (`PaymentPayPal`) |
| `Address_Verification_Keys__c` | `Google_Api_Key__c` | `?key=` query parameter on Google Address Validation |
| `Address_Verification_Keys__c` | `Smarty_Auth_Token__c` | `auth-token` query parameter on Smarty US Street |

The platform option is External Credentials (with principals holding the secrets) behind Named
Credentials. Apex can now create and update a principal's credentials:
`ConnectApi.NamedCredentials.createCredential`, `updateCredential` and `patchCredential`
(Connect in Apex, available well before API 67), and a callout to `callout:<Named Credential>`
can put a principal's custom parameter in a header or body with a `{!$Credential...}` formula.
So a setup page could, in principle, write the outbound keys.

## Decision

Keep all five secrets in the Protected custom settings for the managed packages. Do not ship
External or Named Credentials for these providers now. Revisit per provider when a reason
below goes away.

## Why

1. **The Stripe webhook secret must be read by Apex.** Verifying `Stripe-Signature` is an
   HMAC-SHA256 computed in Apex over the raw body. A credential stored in an External
   Credential principal can only be merged into an outbound callout; Apex can never read it.
   This one secret cannot move at all, so `Payment_Keys__c` stays whatever the others do.
2. **Protected settings already give the managed-package guarantee.** In a managed package a
   Protected custom setting is invisible to the subscriber's Apex, API, reports and Setup data
   views; only the package's own code reads it. That is the property a credential store would
   add, and it holds once D-199's namespace exists. (Unmanaged and source installs, which have
   no namespace boundary, are not the shipped form.)
3. **Two providers put the secret in the query string.** Smarty's server-side scheme is
   `auth-id` and `auth-token` query parameters, and the Google key goes in `?key=` today. Named
   Credential formulas are for headers and bodies; Google also accepts an `X-Goog-Api-Key`
   header, Smarty has no header scheme. Moving only some of them doubles the code paths.
4. **The webhook and public paths run as a Site guest user.** A callout through a Named
   Credential needs the running user to hold principal access through a permission set. For
   the guest user that means another grant on `Payments_Webhook_Guest`, widening the guest's
   access for no gain while (1) still keeps the secret in a setting.
5. **Writing principals through Connect needs setup permissions the setup pages do not
   require today.** `ConnectApi.NamedCredentials` runs as the user and needs Customize
   Application (or Manage Named Credentials) as well as the module's own admin permission. The
   setup pages would change who can save keys, which D-200 asked not to break.

## Consequences

- No change to the Payments or Address Verification setup pages, their Apex or their tests.
- The security checklist (section 8) and the AppExchange notes state where the secrets live
  and why; the review submission cites this ADR for the "Store secrets in protected custom
  settings or named credentials" requirement, which Protected custom settings in a managed
  package meet.
- Candidates to revisit: Stripe secret key and PayPal client secret (header and OAuth, so a
  Named Credential with a Custom or OAuth client-credentials External Credential fits), once
  the setup pages can require Customize Application without losing anyone who saves keys today.
  The Stripe webhook secret and the Smarty token stay in settings regardless.
