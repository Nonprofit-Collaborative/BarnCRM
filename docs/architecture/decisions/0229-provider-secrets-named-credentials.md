# ADR-0229: Provider Secrets in Named Credentials, and Stripe Events Fetched Back from Stripe

**Status:** Accepted (owner decision)
**Date:** 2026-11-18
**Source:** D-209, release 1.27 item N-13 (Brandon, 2026-11-14: "Named Credentials approved").
Amends ADR-0220 (provider secrets stay in protected custom settings), ADR-0201 (Payments module,
decisions 4, 5 and 7) and ADR-0209 (Address Verification module, decisions 3 and 5).

## Context

ADR-0220 kept five provider secrets in two Protected hierarchy custom settings (`Payment_Keys__c`,
`Address_Verification_Keys__c`), written by each module's setup page. Salesforce's security
review prefers that Apex never holds a secret: an External Credential principal holds it
encrypted, and Salesforce merges it into a callout made through a Named Credential. ADR-0220's
reasons for not moving were:

1. Apex must read Stripe's webhook signing secret to check the HMAC of each event.
2. Smarty takes its key pair only in the query string.
3. A Named Credential callout needs principal access, including for Site guest users.
4. Writing principals from a setup page through `ConnectApi.NamedCredentials` needs setup
   permissions the setup pages do not require.

This ADR removes reason 1 by not checking the signature at all, and finds reasons 2 to 4 answered.

## Decision

1. **Every provider secret is an External Credential principal parameter.** Packaged, with no
   value: External Credentials `Barn_Stripe` (principal `Barn_Stripe_Key`, parameter `SecretKey`),
   `Barn_PayPal` (`Barn_PayPal_App`; `ClientId`, `ClientSecret`), `Barn_Smarty`
   (`Barn_Smarty_Key`; `AuthId`, `AuthToken`) and `Barn_Google_Address`
   (`Barn_Google_Address_Key`; `ApiKey`), all with the Custom authentication protocol and a
   named principal. Named Credentials `Barn_Stripe`, `Barn_PayPal_Live`, `Barn_PayPal_Sandbox`
   (both on `Barn_PayPal`, chosen by Payments mode), `Barn_Smarty` and `Barn_Google_Address`,
   each SecuredEndpoint with Allow Formulas in HTTP Header on and no generated Authorization
   header. Apex builds the header as a merge-field formula, so it never sees a value:
   - Stripe: `Authorization: Bearer {!$Credential.Barn_Stripe.SecretKey}`.
   - PayPal sign-in only: `Authorization: Basic {!BASE64ENCODE(BLOB($Credential.Barn_PayPal.ClientId & ":" & $Credential.Barn_PayPal.ClientSecret))}`;
     later calls carry the short-lived access token PayPal returns, held for one transaction.
   - Google: `X-Goog-Api-Key: {!$Credential.Barn_Google_Address.ApiKey}` (Google's documented
     header; the `?key=` query parameter is gone).
   - Smarty: `Authorization: Basic` over `AuthId:AuthToken`. Smarty documents this header as
     its second way of sending a secret key pair (its authentication page: "use the secret key
     pair in the header", joined with a colon and base64 encoded), so no query-string exception
     is needed and none remains.
   Names in Apex go through `NamespaceUtil.qualify`, so `callout:` and `$Credential.` carry
   the package prefix once the namespace exists.
2. **Stripe events are fetched back from Stripe, never verified locally.** The receiver stores a
   posted event (id `evt_...`, a type Payments acts on, Stripe connected) under its key and makes
   no callout. The processing job, running as the administrator who scheduled it, fetches
   `GET /v1/events/{id}` through `Barn_Stripe` and reads only that copy. Stripe answering 404
   marks the event Rejected ("Stripe has no event with this ID"); any other failure throws, is
   logged to the Error Log and leaves the event Received for the next run, as a failed PayPal
   callout does (R-PEV4). Idempotency is unchanged: the unique `Event_Key__c` drops a resend on
   arrival, and the key is set again from Stripe's copy before `apply` checks used keys. No
   signing secret is entered anywhere. Stripe's own guidance lists retrieving the event from the
   API as an alternative to signature verification.
3. **Readiness is a recorded connection, not a stored key.** Apex cannot read a principal, so
   each setup page has Check Connection: one call through the Named Credential as the person
   checking (Stripe `GET /v1/balance`, which also says whether the key is live; PayPal a
   client-credentials sign-in in the current mode; Smarty and Google one lookup of a fixed
   address). Success sets `Payments_Settings__c.Stripe_Connected__c` / `PayPal_Connected__c` or
   `Address_Verification_Settings__c.Connected_Provider__c`; failure clears it and says why.
   Disconnect clears it. `PaymentService.isReady` and `AddressVerifier.isReady` read only these
   (PayPal also needs its webhook id, which is not a secret and is still typed on Payments
   Setup). Health Check: a processor or provider not connected is a warning as before; for
   Stripe, when it is chosen and connected, Health Check also makes the balance call (only in a
   person's own request with nothing written yet) and reports a failing credential or a key for
   the other mode. Address Verification makes no test lookup from Health Check, since each one
   counts against the organization's provider account.
4. **Principal access by permission set.** `Payments_Staff` (so `Payments_Admin`, generated from
   it; not `Payments_Read_Only`) and `Payments_Webhook_Guest` get both Payments principals:
   staff and a public page's Site guest start checkouts, and the processing job runs as the
   admin. The guest set was already assigned to every active Site's guest user by Health
   Check's fix, so public donation, event and membership pages keep working with no new step.
   The receiver itself needs no credential. `Address_Verification_Admin` and a new
   `Address_Verification_User` (principal access only) get both address principals: lookups on
   save run as the person saving, the nightly step as the admin who scheduled it. A person
   without access is not looked up on save; the first failed callout stops that run and is
   logged once, and the nightly step checks those addresses.
5. **Admins enter secrets in Setup, guided by the setup pages.** Each page shows, per provider,
   the External Credential, principal and parameter names (qualified for the org) and the steps:
   Setup, Named Credentials, External Credentials tab, open the credential, edit the principal,
   add each authentication parameter, then Check Connection. The pages never write a principal,
   so ADR-0220 reason 4 does not arise: entering a secret already needs Setup access.
6. **Removed:** `Payment_Keys__c` (its two non-secret ids moved to `Payments_Settings__c`),
   `Address_Verification_Keys__c`, their seven secret fields, every Apex read of them, the five
   Remote Site Settings (`Barn_Stripe_Api`, `Barn_PayPal_Api`, `Barn_PayPal_Sandbox_Api`,
   `Barn_Google_Address_Api`, `Barn_Smarty_Api`; Named Credential callouts need none) and the
   Stripe HMAC check. The suite goes from 199 to 197 custom objects. Nothing is packaged yet, so
   no data migration is needed.

## Consequences

- No secret is readable by Apex, by any user or by the package. The AppExchange notes and the
  security checklist cite Named Credentials for the "store secrets" requirement.
- Stripe processing makes one more callout per event (the fetch). A run reads at most 20 events,
  well inside the callout limits; the callout-time budget is unchanged.
- A forged post to the Stripe receiver can only create a Received event, which the job rejects
  when Stripe has no such event in this account; the hourly cap per processor still bounds it.
- Admins have a Setup step they did not have, and, for on-save address verification, a
  permission set to assign (`Address_Verification_User`). The admin guides and setup pages give
  the steps.
- Not confirmable offline, to check on the first org deploy: that the `$Credential` merge
  formula (including `BASE64ENCODE(BLOB(...))`) resolves in an Apex-set header with Allow
  Formulas in HTTP Header on; the exact form of a namespaced `$Credential` reference once the
  namespace exists; that a permission set with External Credential principal access can be
  assigned to a Site guest user; and the packaging of External and Named Credentials in a 2GP
  managed package.
- ADR-0220's revisit list is closed: no provider secret remains in a custom setting.

## Amended 2026-11-19

Pre-batch review M1: the receiver accepted any anonymous post, bounded only by the hourly cap.
It now stores a post only when its address carries a random token (`?token=`, 64 hexadecimal
characters from `Crypto.generateAesKey(256)`). BarnCRM makes the token the first time Payments
Setup is opened and keeps it in `Payments_Settings__c.Webhook_Token__c` (protected; not a
provider secret, and still no secret is stored). The receiver compares it character by
character in constant time and answers 404 with an empty body, storing nothing, on a missing or
different token. Payments Setup shows each full address and a Regenerate Token button
(confirmation first; the old addresses stop working). The first refusal at the hourly cap each
hour writes one Warning to the Error Log and sets `Webhook_Cap_Hit_At__c`, which Health Check
reports for a day. The consequence above about a forged Stripe post now holds only for someone
holding the token.
